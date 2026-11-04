-- ============================================================
-- L'admin choisit l'équipe de sa soumission ; personne ne décide de sa propre soumission
-- ============================================================
-- Demande de Pascaline du 2026-11-04. Arbitrages du même jour :
--   * l'admin qui soumet (idée ou point bloquant) choisit une équipe du référentiel,
--     obligatoire, hors équipe réservée « Admin ». La soumission suit alors le circuit
--     de cette équipe (US30) : point bloquant aux managers de l'équipe et aux admins,
--     idée aux managers de l'équipe, à défaut aux admins. Les e-mails US60 et US62 et
--     le pôle prérempli à la publication partent déjà de submissions.team : inchangés ;
--   * un auteur, manager ou admin, ne valide, ne refuse ni ne publie sa propre
--     soumission (décision du 2026-11-03 : un autre manager ou l'admin décide) ;
--   * exception : quand l'équipe de la soumission n'a aucun manager inscrit, l'admin
--     qui en est l'auteur peut décider lui-même.
--
-- Les anciennes soumissions de l'admin gardent l'équipe « Admin », sans manager :
-- l'exception s'y applique.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

-- ---------- L'équipe a-t-elle au moins un manager inscrit ? ----------
CREATE OR REPLACE FUNCTION private.equipe_a_un_manager(_team text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.manager_teams mt
      JOIN public.allowed_user_roles r
        ON r.allowed_user_id = mt.allowed_user_id AND r.role = 'manager'::public.app_role
     WHERE lower(btrim(mt.team)) = lower(btrim(coalesce(_team, '')))
  )
$function$;
REVOKE ALL ON FUNCTION private.equipe_a_un_manager(text) FROM public, anon, authenticated;

-- ---------- La personne connectée peut-elle décider de cette soumission ? ----------
-- Faux seulement si elle en est l'auteur, sauf l'admin auteur d'une soumission
-- dont l'équipe n'a aucun manager inscrit. Les droits sur l'équipe restent
-- contrôlés à part (private.can_review_team, RLS).
CREATE OR REPLACE FUNCTION private.peut_decider_soumission(_auteur text, _team text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT lower(btrim(coalesce(_auteur, ''))) IS DISTINCT FROM lower(auth.jwt() ->> 'email')
      OR (private.current_app_role() = 'admin'::public.app_role
          AND NOT private.equipe_a_un_manager(_team))
$function$;
REVOKE ALL ON FUNCTION private.peut_decider_soumission(text, text) FROM public, anon, authenticated;

-- ---------- À l'envoi : l'admin choisit l'équipe concernée ----------
CREATE OR REPLACE FUNCTION private.set_submission_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(auth.jwt() ->> 'email');
  _role public.app_role;
  _team text;
  _uid uuid;
  _chosen text;
  _name text;
BEGIN
  NEW.submitted_by_email := _email;
  SELECT r.role, u.team, u.id, nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), '')
    INTO _role, _team, _uid, _name
  FROM public.allowed_users u
  LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  WHERE u.email = _email;
  IF _role = 'collaborateur' THEN
    IF _team IS NULL OR btrim(_team) = '' THEN
      RAISE EXCEPTION 'Aucune équipe n''est associée à ton compte. Contacte un administrateur.';
    END IF;
    NEW.team := _team;
  ELSIF _role = 'manager' THEN
    SELECT mt.team INTO _chosen FROM public.manager_teams mt
     WHERE mt.allowed_user_id = _uid AND lower(btrim(mt.team)) = lower(btrim(coalesce(NEW.team, '')))
     LIMIT 1;
    IF _chosen IS NULL THEN
      RAISE EXCEPTION 'Choisis une de tes équipes pour cette demande.';
    END IF;
    NEW.team := _chosen;
  ELSIF _role = 'admin' THEN
    -- 2026-11-04 : l'admin choisit une équipe du référentiel, hors équipe réservée.
    SELECT t.name INTO _chosen FROM public.teams t
     WHERE lower(btrim(t.name)) = lower(btrim(coalesce(NEW.team, '')))
       AND NOT t.is_reserved
     LIMIT 1;
    IF _chosen IS NULL THEN
      RAISE EXCEPTION 'Choisis l''équipe concernée par cette soumission.';
    END IF;
    NEW.team := _chosen;
  END IF;
  IF _role IN ('collaborateur', 'manager') AND _name IS NOT NULL THEN
    NEW.author_name := _name;
  END IF;
  -- Le titre, son origine et le point bloquant créé se posent à la publication, jamais à l'envoi.
  NEW.proposed_title := NULL;
  NEW.proposed_title_by_ai := false;
  NEW.blocker_id := NULL;
  RETURN NEW;
END
$function$;

-- ---------- Décider : jamais de sa propre soumission ----------
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- US68 : un manager auteur renvoie ou archive sa propre soumission par les fonctions dédiées.
  IF coalesce(current_setting('hp.author_action', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  -- 2026-11-04 : valider, refuser ou publier revient à une autre personne que l'auteur,
  -- sauf l'admin auteur d'une soumission dont l'équipe n'a aucun manager.
  IF OLD.status = 'en attente'::public.submission_status
     AND NEW.status IN ('validée'::public.submission_status, 'refusée'::public.submission_status)
     AND NOT private.peut_decider_soumission(OLD.submitted_by_email, OLD.team) THEN
    RAISE EXCEPTION 'Tu ne peux pas décider de ta propre soumission : un autre manager ou l''admin s''en charge.'
      USING ERRCODE = '42501';
  END IF;
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.kind IS DISTINCT FROM OLD.kind
       OR NEW.severity IS DISTINCT FROM OLD.severity
       OR NEW.archived_at IS DISTINCT FROM OLD.archived_at
       OR NEW.resubmission_count IS DISTINCT FROM OLD.resubmission_count
       OR NEW.first_submitted_at IS DISTINCT FROM OLD.first_submitted_at
       OR (NEW.blocker_id IS DISTINCT FROM OLD.blocker_id
           AND coalesce(current_setting('hp.publishing', true), '') <> 'on')
       OR NEW.status NOT IN ('validée'::public.submission_status, 'refusée'::public.submission_status)
       OR OLD.status <> 'en attente'::public.submission_status
       OR NOT private.can_review_team(OLD.team) THEN
      RAISE EXCEPTION 'Un manager peut uniquement valider ou refuser une soumission en attente de ses équipes';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

-- ---------- Publier un point bloquant : même règle, message clair avant toute écriture ----------
CREATE OR REPLACE FUNCTION public.publish_blocker_submission(_submission_id uuid, _title text, _department text, _severity blocker_severity, _description text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _s public.submissions;
  _t text := btrim(coalesce(_title, ''));
  _d text := btrim(_description);
  _dep text;
  _blocker uuid;
BEGIN
  IF NOT private.is_manager_or_admin() THEN
    RAISE EXCEPTION 'Seuls un manager ou un admin peuvent publier un point bloquant.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO _s FROM public.submissions WHERE id = _submission_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Soumission introuvable.';
  END IF;
  IF _s.kind <> 'point bloquant'::public.submission_kind THEN
    RAISE EXCEPTION 'Cette soumission n''est pas un point bloquant.';
  END IF;
  IF NOT private.peut_decider_soumission(_s.submitted_by_email, _s.team) THEN
    RAISE EXCEPTION 'Tu ne peux pas publier ton propre point bloquant : un autre manager ou l''admin s''en charge.'
      USING ERRCODE = '42501';
  END IF;
  IF NOT private.can_review_team(_s.team) THEN
    RAISE EXCEPTION 'Ce point bloquant n''est pas assigné à ton équipe.' USING ERRCODE = '42501';
  END IF;
  IF _s.status <> 'en attente'::public.submission_status OR _s.blocker_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ce point bloquant a déjà été traité par une autre personne.';
  END IF;
  IF char_length(_t) < 3 OR char_length(_t) > 160 THEN
    RAISE EXCEPTION 'Le titre doit faire de 3 à 160 caractères.';
  END IF;
  -- US71 : la personne qui publie peut reformuler la description ; NULL garde le texte de l'auteur.
  IF _d IS NOT NULL AND (char_length(_d) < 5 OR char_length(_d) > 2000) THEN
    RAISE EXCEPTION 'La description doit faire de 5 à 2000 caractères.';
  END IF;
  SELECT t.name INTO _dep FROM public.teams t WHERE lower(t.name) = lower(btrim(coalesce(_department, '')));
  IF _dep IS NULL THEN
    RAISE EXCEPTION 'Pôle inconnu : choisis une équipe du référentiel.';
  END IF;

  INSERT INTO public.blockers (title, description, department, severity, status)
  VALUES (_t, coalesce(_d, _s.content), _dep, coalesce(_severity, _s.severity), 'OUVERT'::public.blocker_status)
  RETURNING id INTO _blocker;

  PERFORM set_config('hp.publishing', 'on', true);
  UPDATE public.submissions
     SET status = 'validée'::public.submission_status,
         blocker_id = _blocker,
         proposed_title = _t,
         rejection_category = NULL,
         rejection_note = NULL
   WHERE id = _submission_id;
  PERFORM set_config('hp.publishing', 'off', true);
  RETURN _blocker;
END
$function$;
REVOKE ALL ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity, text) TO authenticated;

-- ---------- Test US60 : l'admin qui signale choisit désormais une équipe du référentiel ----------
CREATE OR REPLACE FUNCTION private.run_us60_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _n public.notifications;
  _cnt int;
  _team text := 'ZZ US60 fumée';
  _team2 text := 'ZZ US60 sans manager';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), (_team2) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.collab@fumee.happyplace.fr', _team, 'Thomas', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.manager@fumee.happyplace.fr', 'Karim', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.demo@biggerboat.example', 'Julie', 'Démo') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email) VALUES ('us60.admin@fumee.happyplace.fr') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.seul@fumee.happyplace.fr', _team2, 'Léa', 'Seule') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');

    -- Point bloquant d'un collaborateur : managers et admin en destinataires, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.collab@fumee.happyplace.fr' = ANY (n.copie) ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : managers de l''équipe et admin en destinataires, auteur en copie',
      'ok', _n.id IS NOT NULL
            AND 'us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.collab@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.copie = ARRAY['us60.collab@fumee.happyplace.fr'],
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    _res := _res || jsonb_build_object('t', 'US60 : adresse de démo (.example) écartée',
      'ok', NOT ('us60.demo@biggerboat.example' = ANY (_n.destinataires)) AND _n.adresses_ecartees >= 1,
      'd', coalesce(_n.adresses_ecartees::text, '?') || ' écartée(s)');

    _res := _res || jsonb_build_object('t', 'US60 : objet, sévérité, date, assignés et lien ; ni description ni nom d''auteur',
      'ok', _n.objet = '[HappyPlace] Nouveau point bloquant à traiter · Critique'
            AND position('CRITIQUE' IN _n.corps_html) > 0
            AND position(private.date_paris(now()) IN _n.corps_html) > 0
            AND position('Julie Démo, Karim Manager, managers ' || _team || ' · Administration HappyPlace' IN _n.corps_html) > 0
            AND position('Administration HappyPlace' IN _n.corps_html) > 0
            AND position('https://happy-place-pascaline.pascalinemillet.workers.dev/' IN _n.corps_html) > 0
            AND position('Les CV ne remontent' IN _n.corps_html) = 0
            AND position('Thomas Auteur' IN _n.corps_html) = 0,
      'd', coalesce(_n.objet, '?'));

    -- Une idée ne déclenche pas US60
    SELECT count(*) INTO _cnt FROM notifications WHERE evenement = 'point_bloquant_soumis';
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe');
    _res := _res || jsonb_build_object('t', 'US60 : une idée ne prépare pas d''e-mail de point bloquant',
      'ok', (SELECT count(*) FROM notifications WHERE evenement = 'point_bloquant_soumis') = _cnt,
      'd', (SELECT count(*) FROM notifications WHERE evenement = 'point_bloquant_soumis')::text || ' ligne(s)');

    -- Équipe sans manager : l'admin seul, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.seul@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le badge ne fonctionne plus à l''accueil.', 'point bloquant', 'warning');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.seul@fumee.happyplace.fr' = ANY (n.copie) LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : équipe sans manager, l''admin seul et l''auteur en copie',
      'ok', _n.id IS NOT NULL AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.objet LIKE '%· Avertissement'
            AND position('>Administration HappyPlace<' IN _n.corps_html) > 0,
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    -- Un admin qui signale : jamais en double
    PERFORM set_config('request.jwt.claims', '{"email":"us60.admin@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('Admin', _team, 'Le serveur de fichiers est lent.', 'point bloquant', 'info');
    SELECT * INTO _n FROM notifications n
     WHERE n.objet LIKE '%· Information' ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : l''auteur n''apparaît jamais en double',
      'ok', _n.id IS NOT NULL
            AND (SELECT count(*) FROM unnest(_n.destinataires || _n.copie) e
                  WHERE e = 'us60.admin@fumee.happyplace.fr') = 1,
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    -- L'app ne lit pas la table d'envoi
    _res := _res || jsonb_build_object('t', 'US60 : la table d''envoi est fermée aux comptes de l''app',
      'ok', NOT has_table_privilege('authenticated', 'public.notifications', 'SELECT')
            AND NOT has_table_privilege('anon', 'public.notifications', 'SELECT'),
      'd', 'droits vérifiés');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US60', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us60_smoke_tests() FROM public, anon, authenticated;

-- ---------- Tests de fumée ----------
CREATE OR REPLACE FUNCTION private.run_admin_equipe_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _pb uuid;
  _idea uuid;
  _seule uuid;
  _midea uuid;
  _mpb uuid;
  _s public.submissions;
  _n public.notifications;
  _avec constant text := 'ZZ AE avec manager';
  _sans constant text := 'ZZ AE sans manager';
  _admin constant text := '{"email":"ae.admin@fumee.happyplace.fr"}';
  _admin2 constant text := '{"email":"ae.admin2@fumee.happyplace.fr"}';
  _m1 constant text := '{"email":"ae.m1@fumee.happyplace.fr"}';
  _m2 constant text := '{"email":"ae.m2@fumee.happyplace.fr"}';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_avec), (_sans) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('ae.admin@fumee.happyplace.fr', 'Olivia', 'Admin') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('ae.admin2@fumee.happyplace.fr', 'Nadia', 'Admin') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('ae.m1@fumee.happyplace.fr', 'Kesha', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _avec);
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('ae.m2@fumee.happyplace.fr', 'Marc', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _avec);

    -- L'admin doit choisir une équipe du référentiel, hors « Admin ».
    PERFORM set_config('request.jwt.claims', _admin, true);
    BEGIN
      INSERT INTO submissions(author_name, team, content) VALUES ('Olivia Admin', '', 'Une idée sans équipe');
      _res := _res || jsonb_build_object('t', 'Admin auteur : l''équipe est obligatoire', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'Admin auteur : l''équipe est obligatoire', 'ok', true, 'd', SQLERRM);
    END;
    BEGIN
      INSERT INTO submissions(author_name, team, content) VALUES ('Olivia Admin', 'Admin', 'Une idée pour l''équipe Admin');
      _res := _res || jsonb_build_object('t', 'Admin auteur : l''équipe réservée « Admin » est refusée', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'Admin auteur : l''équipe réservée « Admin » est refusée', 'ok', true, 'd', SQLERRM);
    END;

    -- Point bloquant de l'admin pour une équipe avec managers.
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('Olivia Admin', lower(_avec), 'La signature électronique ne répond plus.', 'point bloquant', 'critical')
      RETURNING id INTO _pb;
    SELECT * INTO _s FROM submissions WHERE id = _pb;
    SELECT * INTO _n FROM notifications n WHERE n.submission_id = _pb AND n.evenement = 'point_bloquant_soumis';
    _res := _res || jsonb_build_object('t', 'Admin auteur : point bloquant rattaché à l''équipe choisie, e-mail aux managers et à l''autre admin, auteur en copie',
      'ok', _s.team = _avec
            AND _n.destinataires @> ARRAY['ae.m1@fumee.happyplace.fr', 'ae.m2@fumee.happyplace.fr', 'ae.admin2@fumee.happyplace.fr']
            AND NOT ('ae.admin@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.copie = ARRAY['ae.admin@fumee.happyplace.fr']
            AND position('Kesha Manager, Marc Manager, managers ' || _avec IN _n.corps_html) > 0,
      'd', _s.team || ' | ' || coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    -- Idée de l'admin pour la même équipe : aux managers seulement.
    INSERT INTO submissions(author_name, team, content) VALUES ('Olivia Admin', _avec, 'Un modèle commun de compte rendu client.')
      RETURNING id INTO _idea;
    SELECT * INTO _n FROM notifications n WHERE n.submission_id = _idea AND n.evenement = 'idee_soumise';
    _res := _res || jsonb_build_object('t', 'Admin auteur : idée aux managers de l''équipe choisie, auteur en copie',
      'ok', _n.destinataires = ARRAY['ae.m1@fumee.happyplace.fr', 'ae.m2@fumee.happyplace.fr']
            AND _n.copie = ARRAY['ae.admin@fumee.happyplace.fr'],
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    -- L'admin auteur ne décide pas quand l'équipe a un manager.
    BEGIN
      PERFORM public.publish_blocker_submission(_pb, 'Signature électronique en panne', _avec, 'critical', NULL);
      _res := _res || jsonb_build_object('t', 'Admin auteur : il ne publie pas son point bloquant', 'ok', false, 'd', 'publié à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'Admin auteur : il ne publie pas son point bloquant', 'ok',
        NOT EXISTS (SELECT 1 FROM blockers WHERE title = 'Signature électronique en panne'), 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'x' WHERE id = _pb;
      _res := _res || jsonb_build_object('t', 'Admin auteur : il ne refuse pas son point bloquant', 'ok', false, 'd', 'refusé à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'Admin auteur : il ne refuse pas son point bloquant', 'ok', true, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _idea;
      _res := _res || jsonb_build_object('t', 'Admin auteur : il ne valide pas son idée', 'ok', false, 'd', 'validée à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'Admin auteur : il ne valide pas son idée', 'ok', true, 'd', SQLERRM);
    END;

    -- Un manager de l'équipe et l'autre admin décident.
    PERFORM set_config('request.jwt.claims', _m1, true);
    UPDATE submissions SET status = 'validée' WHERE id = _idea;
    PERFORM set_config('request.jwt.claims', _admin2, true);
    PERFORM public.publish_blocker_submission(_pb, 'Signature électronique en panne', _avec, 'critical', NULL);
    _res := _res || jsonb_build_object('t', 'Admin auteur : un manager de l''équipe valide son idée, l''autre admin publie son point bloquant',
      'ok', (SELECT status FROM submissions WHERE id = _idea) = 'validée'
            AND (SELECT status FROM submissions WHERE id = _pb) = 'validée'
            AND EXISTS (SELECT 1 FROM blockers WHERE title = 'Signature électronique en panne' AND department = _avec),
      'd', 'pôle ' || _avec);

    -- Exception : équipe sans manager, l'admin auteur décide lui-même.
    PERFORM set_config('request.jwt.claims', _admin, true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Olivia Admin', _sans, 'Une idée pour une équipe sans manager.')
      RETURNING id INTO _seule;
    UPDATE submissions SET status = 'validée' WHERE id = _seule;
    _res := _res || jsonb_build_object('t', 'Admin auteur : équipe sans manager, il valide lui-même',
      'ok', (SELECT status FROM submissions WHERE id = _seule) = 'validée', 'd', _sans);

    -- Manager auteur : ni valider ni publier ; l'autre manager ou l'admin décide.
    PERFORM set_config('request.jwt.claims', _m1, true);
    INSERT INTO submissions(author_name, team, content) VALUES ('x', _avec, 'Idée du manager pour son équipe.')
      RETURNING id INTO _midea;
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', _avec, 'Le planning partagé est inaccessible.', 'point bloquant', 'warning')
      RETURNING id INTO _mpb;
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _midea;
      _res := _res || jsonb_build_object('t', 'Manager auteur : il ne valide pas sa propre idée', 'ok', false, 'd', 'validée à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'Manager auteur : il ne valide pas sa propre idée', 'ok', true, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.publish_blocker_submission(_mpb, 'Planning partagé inaccessible', _avec, 'warning', NULL);
      _res := _res || jsonb_build_object('t', 'Manager auteur : il ne publie pas son propre point bloquant', 'ok', false, 'd', 'publié à tort');
    EXCEPTION WHEN insufficient_privilege THEN
      _res := _res || jsonb_build_object('t', 'Manager auteur : il ne publie pas son propre point bloquant', 'ok', true, 'd', SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', _m2, true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'autre', rejection_note = 'À préciser' WHERE id = _midea;
    PERFORM set_config('request.jwt.claims', _admin, true);
    PERFORM public.publish_blocker_submission(_mpb, 'Planning partagé inaccessible', _avec, 'warning', NULL);
    _res := _res || jsonb_build_object('t', 'Manager auteur : l''autre manager refuse son idée, l''admin publie son point bloquant',
      'ok', (SELECT status FROM submissions WHERE id = _midea) = 'refusée'
            AND (SELECT status FROM submissions WHERE id = _mpb) = 'validée',
      'd', 'ok');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée « admin et équipe »', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_admin_equipe_smoke_tests() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT * FROM private.run_base_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f1_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us60_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us65_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us61_us62_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f4_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us43_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f4_mois_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us68_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us71_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us64_email_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_admin_equipe_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

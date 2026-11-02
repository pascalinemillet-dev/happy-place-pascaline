-- ============================================================
-- Lot 2 (T12) : « Assigné à » plus court dans les e-mails US60 et US62
-- ============================================================
-- Constat du 2026-11-02 : la ligne répétait « manager <équipe> » après chaque
-- nom. Désormais : « Karim Haddad, manager Direction Commerciale » pour un
-- manager ; « Julie Moreau, Pascaline Millet, managers Pôle Data et IA » pour
-- plusieurs.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

CREATE OR REPLACE FUNCTION private.ligne_managers(_team text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $$
  SELECT CASE count(*)
           WHEN 0 THEN NULL
           WHEN 1 THEN min(n) || ', manager ' || _team
           ELSE string_agg(n, ', ' ORDER BY n) || ', managers ' || _team END
    FROM (
      SELECT DISTINCT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email) AS n
        FROM public.manager_teams mt
        JOIN public.allowed_users u ON u.id = mt.allowed_user_id
        JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
       WHERE lower(btrim(mt.team)) = lower(btrim(_team))
    ) m
$$;
REVOKE ALL ON FUNCTION private.ligne_managers(text) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.preparer_email_point_bloquant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _candidats text[];
  _a text[];
  _cc text[] := '{}';
  _ecartees int;
  _assignes text;
  _objet text;
BEGIN
  SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _candidats
    FROM public.allowed_users u
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE (r.role = 'manager'::public.app_role
          AND EXISTS (SELECT 1 FROM public.manager_teams mt
                       WHERE mt.allowed_user_id = u.id
                         AND lower(btrim(mt.team)) = lower(btrim(NEW.team))))
      OR r.role = 'admin'::public.app_role;

  SELECT count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
         coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
    INTO _ecartees, _a
    FROM unnest(_candidats) e;

  IF private.adresse_distribuable(_auteur) THEN
    IF cardinality(_a) = 0 THEN
      _a := ARRAY[_auteur];
    ELSE
      _cc := ARRAY[_auteur];
    END IF;
  ELSIF _auteur <> '' THEN
    _ecartees := _ecartees + 1;
  END IF;

  IF cardinality(_a) = 0 THEN
    RAISE NOTICE 'US60 : aucune adresse distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  _assignes := private.ligne_managers(NEW.team);
  _assignes := concat_ws(' · ', _assignes, 'Administration HappyPlace');
  _objet := '[HappyPlace] Nouveau point bloquant à traiter · ' || private.libelle_severite(NEW.severity);

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_soumis', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'POINT BLOQUANT', 'Un point bloquant vient d''être signalé',
      ARRAY[
        ARRAY['TYPE', 'Point bloquant'],
        ARRAY['SÉVÉRITÉ', private.tag_severite(NEW.severity)],
        ARRAY['DATE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['ASSIGNÉ À', private.html_echappe(_assignes)]
      ],
      'La première personne qui le traite le publie ou le refuse dans HappyPlace.',
      'OUVRIR DANS HAPPYPLACE', _lien,
      'Pour protéger les données, la description et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car ce point vous est assigné ou parce que vous en êtes l''auteur.'),
    _ecartees);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US60 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_point_bloquant() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.preparer_email_idee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _managers text[];
  _admins text[];
  _a text[];
  _cc text[] := '{}';
  _ecartees int := 0;
  _assignes text;
  _objet text;
BEGIN
  SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _managers
    FROM public.manager_teams mt
    JOIN public.allowed_users u ON u.id = mt.allowed_user_id
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
   WHERE lower(btrim(mt.team)) = lower(btrim(NEW.team));

  -- Managers assignés (US30) ; l'admin si l'équipe n'a pas de manager joignable.
  SELECT count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
         coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
    INTO _ecartees, _a
    FROM unnest(_managers) e;
  IF cardinality(_a) = 0 THEN
    SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _admins
      FROM public.allowed_users u
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'admin'::public.app_role;
    SELECT _ecartees + count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
           coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
      INTO _ecartees, _a
      FROM unnest(_admins) e;
  END IF;

  IF private.adresse_distribuable(_auteur) THEN
    IF cardinality(_a) = 0 THEN
      _a := ARRAY[_auteur];
    ELSE
      _cc := ARRAY[_auteur];
    END IF;
  ELSIF _auteur <> '' THEN
    _ecartees := _ecartees + 1;
  END IF;

  IF cardinality(_a) = 0 THEN
    RAISE NOTICE 'US62 : aucune adresse distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  -- « Assigné à », comme dans l'app (US30) : les managers, sinon l'administration.
  _assignes := private.ligne_managers(NEW.team);
  _assignes := coalesce(_assignes, 'Administration HappyPlace');
  _objet := '[HappyPlace] Nouvelle idée à examiner';

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('idee_soumise', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'IDÉE', 'Une nouvelle idée vient d''être soumise',
      ARRAY[
        ARRAY['TYPE', 'Idée'],
        ARRAY['DATE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['ASSIGNÉ À', private.html_echappe(_assignes)]
      ],
      'Elle est validée ou refusée dans HappyPlace.',
      'OUVRIR DANS HAPPYPLACE', _lien,
      'Pour protéger les données, la description et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car cette idée vous est assignée ou parce que vous en êtes l''auteur.'),
    _ecartees);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US62 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_idee() FROM public, anon, authenticated;

COMMIT;

BEGIN;

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
      VALUES ('Admin', 'x', 'Le serveur de fichiers est lent.', 'point bloquant', 'info');
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

COMMIT;

SELECT * FROM private.run_smoke_tests();

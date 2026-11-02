-- ============================================================
-- F1 « Signaler un point bloquant » (lot 1 : US29 à US34, US63, US64)
-- ============================================================
-- Une soumission est une idée ou un point bloquant. Le point bloquant est
-- assigné aux managers de l'équipe de l'auteur et à l'admin : le premier qui
-- le publie (statut OUVERT, C1, pôle du référentiel des équipes, C2) ou le
-- refuse l'emporte. Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

CREATE TYPE public.submission_kind AS ENUM ('idée', 'point bloquant');

ALTER TABLE public.submissions
  ADD COLUMN kind public.submission_kind NOT NULL DEFAULT 'idée',
  ADD COLUMN severity public.blocker_severity,
  ADD COLUMN proposed_title text,
  ADD COLUMN proposed_title_by_ai boolean NOT NULL DEFAULT false,
  ADD COLUMN blocker_id uuid REFERENCES public.blockers(id) ON DELETE SET NULL;

-- La sévérité n'existe que pour un point bloquant, et elle y est obligatoire.
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_severity_by_kind
  CHECK ((kind = 'point bloquant'::public.submission_kind) = (severity IS NOT NULL));
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_proposed_title_length
  CHECK (proposed_title IS NULL OR char_length(btrim(proposed_title)) BETWEEN 1 AND 160);

CREATE INDEX submissions_kind_status_idx ON public.submissions (kind, status);

-- ---------- Auteur, équipe et nom repris du compte (C4) ----------
-- Un collaborateur ou un manager ne peut plus choisir le nom affiché.
-- L'admin garde la saisie libre de l'écran « Gérer les données ».
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
    NEW.team := 'Admin';
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

-- ---------- Un manager ne change ni le type, ni la sévérité, ni le lien vers le point créé ----------
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.kind IS DISTINCT FROM OLD.kind
       OR NEW.severity IS DISTINCT FROM OLD.severity
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

-- ---------- Lecture : un point bloquant validé n'est pas public (US33) ----------
-- Visible de son auteur, des managers de l'équipe et de l'admin ; le point créé
-- (table blockers) reste lisible par tous les comptes inscrits.
DROP POLICY IF EXISTS "Allowed read submissions" ON public.submissions;
CREATE POLICY "Allowed read submissions" ON public.submissions
  FOR SELECT TO authenticated
  USING (
    private.is_allowed() AND (
      private.is_admin()
      OR ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team))
      OR (submitted_by_email = lower((auth.jwt() ->> 'email'::text)))
      OR (status = 'validée'::public.submission_status AND kind = 'idée'::public.submission_kind)
    )
  );

-- ---------- La revalidation annuelle ne concerne que les idées ----------
-- Un point bloquant validé a créé un point dans le module Points bloquants :
-- le repasser « en attente » après un an permettrait de le publier deux fois.
CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE public.submissions
  SET status = 'en attente', revalidate_at = NULL
  WHERE status = 'validée' AND kind = 'idée' AND revalidate_at <= now();

  UPDATE public.news
  SET status = 'brouillon', revalidate_at = NULL
  WHERE status = 'publiée' AND revalidate_at <= now();
END
$$;
REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;

-- ---------- À qui est assignée ma soumission ? (US30) ----------
-- Renvoie les managers de l'équipe de l'appelant (collaborateur), de l'équipe
-- choisie (manager) ; l'admin n'a pas de manager (équipe Admin). L'interface
-- ajoute « Administration HappyPlace » pour un point bloquant, ou pour une
-- équipe sans manager.
CREATE OR REPLACE FUNCTION public.submission_assignees(_team text DEFAULT NULL)
RETURNS TABLE(full_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _role public.app_role := private.current_app_role();
  _email text := lower(auth.jwt() ->> 'email');
  _t text;
BEGIN
  IF _role IS NULL THEN
    RAISE EXCEPTION 'Compte non inscrit.' USING ERRCODE = '42501';
  END IF;
  IF _role = 'collaborateur' THEN
    SELECT u.team INTO _t FROM public.allowed_users u WHERE u.email = _email;
  ELSIF _role = 'manager' THEN
    SELECT mt.team INTO _t FROM public.manager_teams mt
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
     WHERE u.email = _email AND lower(btrim(mt.team)) = lower(btrim(coalesce(_team, '')))
     LIMIT 1;
  END IF;
  IF _t IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email)
      FROM public.manager_teams mt
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
     WHERE lower(btrim(mt.team)) = lower(btrim(_t))
     ORDER BY 1;
END
$function$;
REVOKE ALL ON FUNCTION public.submission_assignees(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submission_assignees(text) TO authenticated;

-- ---------- Publier un point bloquant (US32) ----------
-- Crée le point au statut OUVERT (C1), avec un pôle du référentiel (C2), et
-- passe la soumission à « validée ». Réservé aux managers de l'équipe et à
-- l'admin ; le premier qui agit l'emporte (la soumission doit être en attente).
CREATE OR REPLACE FUNCTION public.publish_blocker_submission(
  _submission_id uuid,
  _title text,
  _department text,
  _severity public.blocker_severity
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _s public.submissions;
  _t text := btrim(coalesce(_title, ''));
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
  IF NOT private.can_review_team(_s.team) THEN
    RAISE EXCEPTION 'Ce point bloquant n''est pas assigné à ton équipe.' USING ERRCODE = '42501';
  END IF;
  IF _s.status <> 'en attente'::public.submission_status OR _s.blocker_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ce point bloquant a déjà été traité par une autre personne.';
  END IF;
  IF char_length(_t) < 3 OR char_length(_t) > 160 THEN
    RAISE EXCEPTION 'Le titre doit faire de 3 à 160 caractères.';
  END IF;
  SELECT t.name INTO _dep FROM public.teams t WHERE lower(t.name) = lower(btrim(coalesce(_department, '')));
  IF _dep IS NULL THEN
    RAISE EXCEPTION 'Pôle inconnu : choisis une équipe du référentiel.';
  END IF;

  INSERT INTO public.blockers (title, description, department, severity, status)
  VALUES (_t, _s.content, _dep, coalesce(_severity, _s.severity), 'OUVERT'::public.blocker_status)
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
REVOKE ALL ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity) TO authenticated;

-- ---------- Titre proposé par l'IA (US31) ----------
-- L'assigné (manager de l'équipe ou admin) enregistre le titre proposé, sans
-- toucher au reste de la soumission.
CREATE OR REPLACE FUNCTION public.save_proposed_title(_submission_id uuid, _title text, _by_ai boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _s public.submissions;
  _t text := nullif(btrim(coalesce(_title, '')), '');
BEGIN
  IF NOT private.is_manager_or_admin() THEN
    RAISE EXCEPTION 'Réservé aux managers et aux admins.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO _s FROM public.submissions WHERE id = _submission_id FOR UPDATE;
  IF NOT FOUND OR _s.kind <> 'point bloquant'::public.submission_kind
     OR _s.status <> 'en attente'::public.submission_status
     OR NOT private.can_review_team(_s.team) THEN
    RAISE EXCEPTION 'Titre non enregistré : le point bloquant n''est plus à traiter.';
  END IF;
  IF _t IS NOT NULL AND char_length(_t) > 160 THEN
    RAISE EXCEPTION 'Le titre doit faire 160 caractères au plus.';
  END IF;
  UPDATE public.submissions
     SET proposed_title = _t, proposed_title_by_ai = (_t IS NOT NULL AND coalesce(_by_ai, false))
   WHERE id = _submission_id;
END
$function$;
REVOKE ALL ON FUNCTION public.save_proposed_title(uuid, text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.save_proposed_title(uuid, text, boolean) TO authenticated;

-- ---------- Suivi des événements (US34) ----------
-- Aucun contenu saisi : seulement le compte, le rôle, l'événement, le module
-- et quelques compteurs. Lecture réservée aux admins.
CREATE TABLE public.usage_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email text,
  role public.app_role,
  event text NOT NULL CHECK (event IN (
    'module_viewed', 'validated_list_expanded', 'submission_type_selected',
    'submission_sent', 'blocker_report_qualified', 'ai_suggestion_edited',
    'team_recap_generated'
  )),
  module text CHECK (module IS NULL OR char_length(module) <= 40),
  props jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (pg_column_size(props) <= 512),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX usage_events_event_idx ON public.usage_events (event, created_at);

CREATE OR REPLACE FUNCTION private.stamp_usage_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  NEW.user_email := lower(nullif(auth.jwt() ->> 'email', ''));
  NEW.role := private.current_app_role();
  NEW.created_at := now();
  RETURN NEW;
END
$function$;
CREATE TRIGGER stamp_usage_event BEFORE INSERT ON public.usage_events
  FOR EACH ROW EXECUTE FUNCTION private.stamp_usage_event();

ALTER TABLE public.usage_events ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.usage_events TO authenticated;
GRANT ALL ON public.usage_events TO service_role;
CREATE POLICY "Allowed log events" ON public.usage_events
  FOR INSERT TO authenticated WITH CHECK (private.is_allowed());
CREATE POLICY "Admins read events" ON public.usage_events
  FOR SELECT TO authenticated USING (private.is_admin());

COMMIT;

-- ============================================================
-- Tests de fumée de F1, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_f1_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _mgr2 uuid; _adm uuid;
  _pb uuid; _idea uuid; _pb2 uuid; _blk uuid;
  _st text; _cnt int; _txt text;
  _team text := 'ZZ F1 fumée';
  _team2 text := 'ZZ F1 fumée bis';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), (_team2) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('f1.collab@test.invalid', _team, 'Camille', 'Auteur') RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('f1.manager@test.invalid', 'Max', 'Manager') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('f1.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team2);
    INSERT INTO allowed_users(email) VALUES ('f1.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- US29 : le collaborateur envoie un point bloquant, nom et équipe repris du compte (C4)
    PERFORM set_config('request.jwt.claims', '{"email":"f1.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('Nom usurpé', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical')
      RETURNING id, status::text INTO _pb, _st;
    SELECT s.author_name INTO _txt FROM submissions s WHERE s.id = _pb;
    _res := _res || jsonb_build_object('t', 'F1 : point bloquant créé « en attente », nom et équipe repris du compte',
      'ok', _st = 'en attente' AND _txt = 'Camille Auteur'
            AND (SELECT s.team FROM submissions s WHERE s.id = _pb) = _team, 'd', coalesce(_txt, '?'));

    BEGIN
      INSERT INTO submissions(author_name, team, content, kind) VALUES ('x', 'x', 'Point sans sévérité', 'point bloquant');
      _res := _res || jsonb_build_object('t', 'F1 : un point bloquant sans sévérité est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F1 : un point bloquant sans sévérité est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      INSERT INTO submissions(author_name, team, content, kind, severity) VALUES ('x', 'x', 'Idée avec sévérité', 'idée', 'info');
      _res := _res || jsonb_build_object('t', 'F1 : une idée avec une sévérité est refusée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F1 : une idée avec une sévérité est refusée', 'ok', true, 'd', 'refusé par la base');
    END;
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe') RETURNING id INTO _idea;

    -- US30 : assignés = managers de l'équipe de l'auteur
    SELECT count(*), string_agg(a.full_name, ',') INTO _cnt, _txt FROM submission_assignees() a;
    _res := _res || jsonb_build_object('t', 'F1 : les assignés sont les managers de l''équipe de l''auteur',
      'ok', _cnt = 1 AND _txt = 'Max Manager', 'd', coalesce(_txt, 'aucun'));

    -- US32 : un manager d'une autre équipe ne peut pas publier
    PERFORM set_config('request.jwt.claims', '{"email":"f1.manager2@test.invalid"}', true);
    BEGIN
      PERFORM publish_blocker_submission(_pb, 'Titre autre équipe', _team, 'critical');
      _res := _res || jsonb_build_object('t', 'F1 : un manager d''une autre équipe ne peut pas publier', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : un manager d''une autre équipe ne peut pas publier', 'ok', true, 'd', 'refusé par la base');
    END;

    -- US32 : le manager de l'équipe publie, au statut OUVERT, pôle du référentiel
    PERFORM set_config('request.jwt.claims', '{"email":"f1.manager@test.invalid"}', true);
    BEGIN
      _blk := publish_blocker_submission(_pb, 'CV absents des fiches importées', _team, 'warning');
      SELECT b.status::text INTO _st FROM blockers b WHERE b.id = _blk;
      _res := _res || jsonb_build_object('t', 'F1 : le manager publie le point bloquant au statut OUVERT',
        'ok', _st = 'OUVERT'
              AND (SELECT s.status::text FROM submissions s WHERE s.id = _pb) = 'validée'
              AND (SELECT s.blocker_id FROM submissions s WHERE s.id = _pb) = _blk
              AND (SELECT b.severity::text FROM blockers b WHERE b.id = _blk) = 'warning', 'd', _st);
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : le manager publie le point bloquant au statut OUVERT', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM publish_blocker_submission(_pb, 'Double publication', _team, 'info');
      _res := _res || jsonb_build_object('t', 'F1 : le premier qui publie l''emporte', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : le premier qui publie l''emporte', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      PERFORM publish_blocker_submission(_idea, 'Une idée publiée', _team, 'info');
      _res := _res || jsonb_build_object('t', 'F1 : une idée ne se publie pas comme point bloquant', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : une idée ne se publie pas comme point bloquant', 'ok', true, 'd', 'refusé par la base');
    END;

    -- Pôle hors référentiel refusé (C2)
    PERFORM set_config('request.jwt.claims', '{"email":"f1.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le partage d''écran plante en visio.', 'point bloquant', 'warning') RETURNING id INTO _pb2;
    PERFORM set_config('request.jwt.claims', '{"email":"f1.admin@test.invalid"}', true);
    BEGIN
      PERFORM publish_blocker_submission(_pb2, 'Partage d''écran en panne', 'PÔLE INVENTÉ', 'warning');
      _res := _res || jsonb_build_object('t', 'F1 : un pôle hors référentiel est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : un pôle hors référentiel est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    -- L'admin publie aussi, et refuser reste possible avec « doublon »
    BEGIN
      PERFORM publish_blocker_submission(_pb2, 'Partage d''écran en panne', _team, 'warning');
      _res := _res || jsonb_build_object('t', 'F1 : l''admin publie un point bloquant de n''importe quelle équipe', 'ok', true, 'd', 'publié');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : l''admin publie un point bloquant de n''importe quelle équipe', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"f1.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Déjà signalé'
       WHERE id = _idea;
      _res := _res || jsonb_build_object('t', 'F1 : le manager refuse avec le motif « doublon »', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : le manager refuse avec le motif « doublon »', 'ok', false, 'd', SQLERRM);
    END;

    -- US34 : l'événement est signé par la base, sans contenu
    PERFORM set_config('request.jwt.claims', '{"email":"f1.collab@test.invalid"}', true);
    INSERT INTO usage_events(event, module, props) VALUES ('submission_sent', 'soumettre', '{"kind":"point bloquant"}');
    SELECT e.user_email INTO _txt FROM usage_events e
     WHERE e.event = 'submission_sent' AND e.user_email = 'f1.collab@test.invalid' LIMIT 1;
    _res := _res || jsonb_build_object('t', 'F1 : un événement est enregistré avec le compte de l''appelant',
      'ok', _txt = 'f1.collab@test.invalid', 'd', coalesce(_txt, 'aucun'));

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée F1', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_f1_smoke_tests() FROM public, anon, authenticated;

-- private.run_smoke_tests() devient : tests de base + tests de F1
ALTER FUNCTION private.run_smoke_tests() RENAME TO run_base_smoke_tests;
REVOKE ALL ON FUNCTION private.run_base_smoke_tests() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT * FROM private.run_base_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f1_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;
COMMIT;

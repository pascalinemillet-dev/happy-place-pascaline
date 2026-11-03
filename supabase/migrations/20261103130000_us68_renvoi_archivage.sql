-- ============================================================
-- US68 : modifier et renvoyer une soumission refusée, ou l'archiver
-- ============================================================
-- Demande de Pascaline du 2026-11-03. Arbitrages du même jour :
--   * l'auteur modifie tout sauf l'équipe : description, pièce jointe, type et sévérité ;
--   * la soumission renvoyée suit le même circuit qu'un envoi (US30) et repart avec
--     l'e-mail US60 ou US62, signalé « renvoyé après refus » ;
--   * une soumission archivée sort de « Refusée » et de « Tous les statuts » et reste
--     lisible par le filtre « Archivée ». Rien n'est supprimé.
--
-- La soumission renvoyée garde son identifiant. Elle repasse « en attente » ; le motif
-- et la raison du refus restent dans submission_status_history. created_at prend la
-- date du renvoi (ancienneté, retard de 5 jours ouvrés, e-mail) ; la date du premier
-- envoi est gardée dans first_submitted_at.
--
-- L'auteur n'a aucun droit d'écriture direct sur submissions : il passe par
-- public.resubmit_submission et public.archive_submission.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

ALTER TABLE public.submissions
  ADD COLUMN archived_at timestamptz,
  ADD COLUMN resubmission_count integer NOT NULL DEFAULT 0,
  ADD COLUMN first_submitted_at timestamptz;

-- Seule une soumission refusée peut être archivée.
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_archived_if_refused
  CHECK (archived_at IS NULL OR status = 'refusée'::public.submission_status);

-- ---------- Le renvoi et l'archivage passent par les fonctions de l'auteur ----------
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

-- ---------- Modifier et renvoyer une soumission refusée ----------
CREATE OR REPLACE FUNCTION public.resubmit_submission(
  _submission_id uuid,
  _kind public.submission_kind,
  _severity public.blocker_severity,
  _content text,
  _attachment_path text,
  _attachment_name text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _s public.submissions;
BEGIN
  IF _email IS NULL OR NOT private.is_allowed() THEN
    RAISE EXCEPTION 'Session expirée';
  END IF;
  SELECT * INTO _s FROM public.submissions WHERE id = _submission_id FOR UPDATE;
  IF NOT FOUND OR lower(coalesce(_s.submitted_by_email, '')) <> _email THEN
    RAISE EXCEPTION 'Seul l''auteur peut renvoyer cette soumission';
  END IF;
  IF _s.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Une soumission archivée ne peut plus être renvoyée';
  END IF;
  IF _s.status <> 'refusée'::public.submission_status THEN
    RAISE EXCEPTION 'Seule une soumission refusée peut être modifiée et renvoyée';
  END IF;
  IF _kind IS NULL THEN
    RAISE EXCEPTION 'Choisis le type de la soumission';
  END IF;
  IF _kind = 'point bloquant'::public.submission_kind AND _severity IS NULL THEN
    RAISE EXCEPTION 'Choisis une sévérité';
  END IF;

  -- L'ancienne pièce jointe remplacée ou retirée part dans la file de suppression.
  IF _s.attachment_path IS NOT NULL AND _s.attachment_path IS DISTINCT FROM _attachment_path THEN
    INSERT INTO public.attachment_deletion_queue (path, delete_after)
    VALUES (_s.attachment_path, now())
    ON CONFLICT (path) DO UPDATE SET delete_after = least(public.attachment_deletion_queue.delete_after, now());
  END IF;

  PERFORM set_config('hp.author_action', 'on', true);
  UPDATE public.submissions
     SET kind = _kind,
         severity = CASE WHEN _kind = 'point bloquant'::public.submission_kind THEN _severity END,
         content = btrim(coalesce(_content, '')),
         attachment_path = _attachment_path,
         attachment_name = CASE WHEN _attachment_path IS NULL THEN NULL ELSE left(_attachment_name, 200) END,
         status = 'en attente'::public.submission_status,
         rejection_category = NULL,
         rejection_note = NULL,
         proposed_title = NULL,
         proposed_title_by_ai = false,
         first_submitted_at = coalesce(_s.first_submitted_at, _s.created_at),
         created_at = now(),
         resubmission_count = _s.resubmission_count + 1
   WHERE id = _submission_id;
  PERFORM set_config('hp.author_action', 'off', true);
END
$function$;
REVOKE ALL ON FUNCTION public.resubmit_submission(uuid, public.submission_kind, public.blocker_severity, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.resubmit_submission(uuid, public.submission_kind, public.blocker_severity, text, text, text) TO authenticated;

-- ---------- Archiver une soumission refusée ----------
CREATE OR REPLACE FUNCTION public.archive_submission(_submission_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _s public.submissions;
BEGIN
  IF _email IS NULL OR NOT private.is_allowed() THEN
    RAISE EXCEPTION 'Session expirée';
  END IF;
  SELECT * INTO _s FROM public.submissions WHERE id = _submission_id FOR UPDATE;
  IF NOT FOUND OR lower(coalesce(_s.submitted_by_email, '')) <> _email THEN
    RAISE EXCEPTION 'Seul l''auteur peut archiver cette soumission';
  END IF;
  IF _s.status <> 'refusée'::public.submission_status THEN
    RAISE EXCEPTION 'Seule une soumission refusée peut être archivée';
  END IF;
  IF _s.archived_at IS NOT NULL THEN
    RETURN;
  END IF;
  PERFORM set_config('hp.author_action', 'on', true);
  UPDATE public.submissions SET archived_at = now() WHERE id = _submission_id;
  PERFORM set_config('hp.author_action', 'off', true);
END
$function$;
REVOKE ALL ON FUNCTION public.archive_submission(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.archive_submission(uuid) TO authenticated;

-- ---------- E-mails US60 et US62 au renvoi ----------
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
  -- US68 : un point bloquant refusé puis renvoyé suit le même circuit, signalé comme renvoyé.
  _objet := CASE WHEN TG_OP = 'UPDATE' THEN '[HappyPlace] Point bloquant renvoyé après refus · '
                 ELSE '[HappyPlace] Nouveau point bloquant à traiter · ' END
            || private.libelle_severite(NEW.severity);

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_soumis', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'POINT BLOQUANT', CASE WHEN TG_OP = 'UPDATE' THEN 'Un point bloquant refusé vient d''être renvoyé'
                 ELSE 'Un point bloquant vient d''être signalé' END,
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
  -- US68 : une idée refusée puis renvoyée suit le même circuit, signalée comme renvoyée.
  _objet := CASE WHEN TG_OP = 'UPDATE' THEN '[HappyPlace] Idée renvoyée après refus'
                 ELSE '[HappyPlace] Nouvelle idée à examiner' END;

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('idee_soumise', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'IDÉE', CASE WHEN TG_OP = 'UPDATE' THEN 'Une idée refusée vient d''être renvoyée'
                 ELSE 'Une nouvelle idée vient d''être soumise' END,
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

DROP TRIGGER IF EXISTS us68_email_renvoi_point_bloquant ON public.submissions;
CREATE TRIGGER us68_email_renvoi_point_bloquant
  AFTER UPDATE OF status ON public.submissions
  FOR EACH ROW
  WHEN (OLD.status = 'refusée'::public.submission_status
        AND NEW.status = 'en attente'::public.submission_status
        AND NEW.kind = 'point bloquant'::public.submission_kind)
  EXECUTE FUNCTION private.preparer_email_point_bloquant();

DROP TRIGGER IF EXISTS us68_email_renvoi_idee ON public.submissions;
CREATE TRIGGER us68_email_renvoi_idee
  AFTER UPDATE OF status ON public.submissions
  FOR EACH ROW
  WHEN (OLD.status = 'refusée'::public.submission_status
        AND NEW.status = 'en attente'::public.submission_status
        AND NEW.kind = 'idée'::public.submission_kind)
  EXECUTE FUNCTION private.preparer_email_idee();

COMMIT;

-- ============================================================
-- Tests de fumée de US68, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_us68_smoke_tests()
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
  _mine uuid;
  _s public.submissions;
  _n public.notifications;
  _cnt int;
  _created timestamptz;
  _team text := 'ZZ US68 fumée';
  _collab constant text := '{"email":"us68.collab@fumee.happyplace.fr"}';
  _autre constant text := '{"email":"us68.autre@fumee.happyplace.fr"}';
  _manager constant text := '{"email":"us68.manager@fumee.happyplace.fr"}';
  _admin constant text := '{"email":"us68.admin@fumee.happyplace.fr"}';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us68.collab@fumee.happyplace.fr', _team, 'Gontran', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us68.autre@fumee.happyplace.fr', _team, 'Léa', 'Collègue') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us68.manager@fumee.happyplace.fr', 'Kesha', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us68.admin@fumee.happyplace.fr', 'Olivia', 'Admin') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');

    PERFORM set_config('request.jwt.claims', _collab, true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'warning')
      RETURNING id, created_at INTO _pb, _created;
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe')
      RETURNING id INTO _idea;

    PERFORM set_config('request.jwt.claims', _manager, true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'à clarifier',
           rejection_note = 'Préciser depuis quand' WHERE id IN (_pb, _idea);

    -- Le manager ne peut pas remettre lui-même une soumission refusée en attente.
    BEGIN
      UPDATE submissions SET status = 'en attente', rejection_category = NULL, rejection_note = NULL
       WHERE id = _pb;
      _res := _res || jsonb_build_object('t', 'US68 : un manager ne remet pas une soumission refusée en attente', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US68 : un manager ne remet pas une soumission refusée en attente', 'ok', true, 'd', 'refusé par la base');
    END;

    -- Un autre collaborateur ne peut ni renvoyer ni archiver.
    PERFORM set_config('request.jwt.claims', _autre, true);
    BEGIN
      PERFORM public.resubmit_submission(_pb, 'point bloquant', 'warning', 'Texte d''un autre compte', NULL, NULL);
      _res := _res || jsonb_build_object('t', 'US68 : seul l''auteur renvoie sa soumission', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US68 : seul l''auteur renvoie sa soumission', 'ok', true, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.archive_submission(_pb);
      _res := _res || jsonb_build_object('t', 'US68 : seul l''auteur archive sa soumission', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US68 : seul l''auteur archive sa soumission', 'ok', true, 'd', SQLERRM);
    END;

    -- L'auteur renvoie son point bloquant modifié.
    PERFORM set_config('request.jwt.claims', _collab, true);
    BEGIN
      PERFORM public.resubmit_submission(_pb, 'point bloquant', NULL, 'Sans sévérité', NULL, NULL);
      _res := _res || jsonb_build_object('t', 'US68 : un point bloquant renvoyé garde une sévérité obligatoire', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US68 : un point bloquant renvoyé garde une sévérité obligatoire', 'ok', true, 'd', SQLERRM);
    END;

    PERFORM public.resubmit_submission(_pb, 'point bloquant', 'critical',
      'Depuis lundi, les CV ne remontent plus dans les fiches.', NULL, NULL);
    SELECT * INTO _s FROM submissions WHERE id = _pb;
    _res := _res || jsonb_build_object('t', 'US68 : renvoi, en attente, motif effacé, description et sévérité modifiées',
      'ok', _s.status = 'en attente' AND _s.rejection_category IS NULL AND _s.rejection_note IS NULL
            AND _s.severity = 'critical' AND _s.content LIKE 'Depuis lundi%' AND _s.team = _team
            AND _s.resubmission_count = 1 AND _s.first_submitted_at = _created AND _s.archived_at IS NULL,
      'd', _s.status::text || ', renvoi n° ' || _s.resubmission_count);

    SELECT count(*) INTO _cnt FROM submission_status_history h
     WHERE h.submission_id = _pb AND h.old_status = 'refusée' AND h.new_status = 'en attente'
       AND h.changed_by_email = 'us68.collab@fumee.happyplace.fr';
    _res := _res || jsonb_build_object('t', 'US68 : le renvoi est historisé, le refus et son motif restent dans l''historique',
      'ok', _cnt = 1 AND EXISTS (SELECT 1 FROM submission_status_history h
                                  WHERE h.submission_id = _pb AND h.new_status = 'refusée'
                                    AND h.rejection_note = 'Préciser depuis quand'),
      'd', _cnt::text || ' ligne(s) de renvoi');

    SELECT * INTO _n FROM notifications n
     WHERE n.submission_id = _pb AND n.evenement = 'point_bloquant_soumis'
       AND n.objet LIKE '%renvoyé après refus%';
    _res := _res || jsonb_build_object('t', 'US68 : e-mail US60 « renvoyé après refus » aux managers et à l''admin, auteur en copie',
      'ok', _n.objet = '[HappyPlace] Point bloquant renvoyé après refus · Critique'
            AND _n.destinataires @> ARRAY['us68.manager@fumee.happyplace.fr', 'us68.admin@fumee.happyplace.fr']
            AND _n.copie = ARRAY['us68.collab@fumee.happyplace.fr']
            AND position('Un point bloquant refusé vient d&#39;être renvoyé' IN _n.corps_html) > 0
            AND position('Depuis lundi' IN _n.corps_html) = 0,
      'd', coalesce(_n.objet, 'aucune ligne'));

    SELECT count(*) INTO _cnt FROM notifications n
     WHERE n.submission_id = _pb AND n.objet = '[HappyPlace] Nouveau point bloquant à traiter · Avertissement';
    _res := _res || jsonb_build_object('t', 'US68 : le premier envoi garde son e-mail US60 d''origine',
      'ok', _cnt = 1, 'd', _cnt::text || ' e-mail(s)');

    -- Le manager peut de nouveau trancher la soumission renvoyée.
    PERFORM set_config('request.jwt.claims', _manager, true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon',
           rejection_note = 'Déjà signalé' WHERE id = _pb;
    _res := _res || jsonb_build_object('t', 'US68 : une soumission renvoyée se valide ou se refuse comme une nouvelle',
      'ok', (SELECT status FROM submissions WHERE id = _pb) = 'refusée', 'd', 'refusée de nouveau');

    -- Changer de type au renvoi : l'idée devient un point bloquant et suit son circuit.
    PERFORM set_config('request.jwt.claims', _collab, true);
    PERFORM public.resubmit_submission(_idea, 'point bloquant', 'info',
      'En fait, cela bloque la prise de rendez-vous.', NULL, NULL);
    SELECT * INTO _s FROM submissions WHERE id = _idea;
    _res := _res || jsonb_build_object('t', 'US68 : l''auteur change le type au renvoi, le circuit suit le nouveau type',
      'ok', _s.kind = 'point bloquant' AND _s.severity = 'info'
            AND EXISTS (SELECT 1 FROM notifications n WHERE n.submission_id = _idea
                          AND n.objet = '[HappyPlace] Point bloquant renvoyé après refus · Information'),
      'd', _s.kind::text);

    -- Renvoyer une idée : e-mail US62 signalé.
    PERFORM set_config('request.jwt.claims', _manager, true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'autre', rejection_note = 'Plutôt une idée'
     WHERE id = _idea;
    PERFORM set_config('request.jwt.claims', _collab, true);
    PERFORM public.resubmit_submission(_idea, 'idée', 'critical', 'Une idée pour la prise de rendez-vous.', NULL, NULL);
    SELECT * INTO _s FROM submissions WHERE id = _idea;
    SELECT * INTO _n FROM notifications n
     WHERE n.submission_id = _idea AND n.evenement = 'idee_soumise'
       AND n.objet = '[HappyPlace] Idée renvoyée après refus';
    _res := _res || jsonb_build_object('t', 'US68 : idée renvoyée, sans sévérité, e-mail US62 « renvoyée après refus » au manager',
      'ok', _s.kind = 'idée' AND _s.severity IS NULL AND _s.resubmission_count = 2
            AND _n.id IS NOT NULL AND _n.destinataires = ARRAY['us68.manager@fumee.happyplace.fr']
            AND position('Une idée refusée vient d&#39;être renvoyée' IN _n.corps_html) > 0,
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    -- Une soumission en attente ne se renvoie ni ne s'archive.
    BEGIN
      PERFORM public.resubmit_submission(_idea, 'idée', NULL, 'Encore une version', NULL, NULL);
      _res := _res || jsonb_build_object('t', 'US68 : seule une soumission refusée se renvoie', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US68 : seule une soumission refusée se renvoie', 'ok', true, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM public.archive_submission(_idea);
      _res := _res || jsonb_build_object('t', 'US68 : seule une soumission refusée s''archive', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US68 : seule une soumission refusée s''archive', 'ok', true, 'd', SQLERRM);
    END;

    -- Archiver : la soumission refusée reste refusée, datée, et ne se renvoie plus.
    PERFORM public.archive_submission(_pb);
    SELECT * INTO _s FROM submissions WHERE id = _pb;
    _res := _res || jsonb_build_object('t', 'US68 : l''auteur archive sa soumission refusée, rien n''est supprimé',
      'ok', _s.status = 'refusée' AND _s.archived_at IS NOT NULL AND _s.rejection_note = 'Déjà signalé',
      'd', coalesce(_s.archived_at::text, 'non archivée'));
    BEGIN
      PERFORM public.resubmit_submission(_pb, 'point bloquant', 'critical', 'Après archivage', NULL, NULL);
      _res := _res || jsonb_build_object('t', 'US68 : une soumission archivée ne se renvoie plus', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US68 : une soumission archivée ne se renvoie plus', 'ok', true, 'd', SQLERRM);
    END;

    -- Seule une soumission refusée peut porter une date d'archivage.
    PERFORM set_config('request.jwt.claims', _admin, true);
    BEGIN
      UPDATE submissions SET archived_at = now() WHERE id = _idea;
      _res := _res || jsonb_build_object('t', 'US68 : seule une soumission refusée peut être archivée (contrainte)', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'US68 : seule une soumission refusée peut être archivée (contrainte)', 'ok', true, 'd', 'refusée par la base');
    END;

    -- Un manager auteur renvoie sa propre soumission refusée par l'admin.
    PERFORM set_config('request.jwt.claims', _manager, true);
    INSERT INTO submissions(author_name, team, content) VALUES ('x', _team, 'Idée du manager pour son équipe')
      RETURNING id INTO _mine;
    PERFORM set_config('request.jwt.claims', _admin, true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'autre', rejection_note = 'À revoir'
     WHERE id = _mine;
    PERFORM set_config('request.jwt.claims', _manager, true);
    PERFORM public.resubmit_submission(_mine, 'idée', NULL, 'Idée du manager, revue et précisée', NULL, NULL);
    _res := _res || jsonb_build_object('t', 'US68 : un manager auteur renvoie sa propre soumission refusée',
      'ok', (SELECT status FROM submissions WHERE id = _mine) = 'en attente', 'd', 'en attente');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US68', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us68_smoke_tests() FROM public, anon, authenticated;

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
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

-- ============================================================
-- Manager : suivre, modifier et supprimer les points bloquants de ses équipes
-- ============================================================
-- Demande de Pascaline du 2026-11-04. Arbitrages du même jour :
--   * sur le dashboard, bloc « Points bloquants » : le manager modifie le statut,
--     le titre, la description, la sévérité et le pôle des points de ses équipes,
--     et les supprime (suppression définitive, avec confirmation, comme l'admin) ;
--   * le pôle ne peut aller que vers une de ses équipes ;
--   * il ne crée pas de point bloquant directement : la création passe toujours
--     par la publication d'une soumission (public.publish_blocker_submission).
-- La soumission d'origine d'un point supprimé reste « validée » (Publiée) ;
-- son lien blocker_id passe à NULL (ON DELETE SET NULL).
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

-- ---------- Qui peut modifier ou supprimer un point bloquant ? ----------
-- L'admin : tous. Le manager : ceux dont le pôle est une de ses équipes.
CREATE OR REPLACE FUNCTION private.peut_gerer_point_bloquant(_department text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT coalesce(private.is_admin(), false)
      OR (private.current_app_role() = 'manager'::public.app_role
          AND private.can_review_team(_department))
$function$;
REVOKE ALL ON FUNCTION private.peut_gerer_point_bloquant(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION private.peut_gerer_point_bloquant(text) TO authenticated;

DROP POLICY IF EXISTS "Managers update team blockers" ON public.blockers;
CREATE POLICY "Managers update team blockers" ON public.blockers
  FOR UPDATE TO authenticated
  USING (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(department))
  WITH CHECK (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(department));

DROP POLICY IF EXISTS "Managers delete team blockers" ON public.blockers;
CREATE POLICY "Managers delete team blockers" ON public.blockers
  FOR DELETE TO authenticated
  USING (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(department));

-- ---------- Supprimer un point publié libère le lien de la soumission ----------
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
  -- 2026-11-04 : un point bloquant supprimé (par un manager ou l'admin) libère le lien
  -- de sa soumission (ON DELETE SET NULL) ; rien d'autre ne change sur la ligne.
  IF OLD.blocker_id IS NOT NULL AND NEW.blocker_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.blockers b WHERE b.id = OLD.blocker_id)
     AND (to_jsonb(NEW) - 'blocker_id') = (to_jsonb(OLD) - 'blocker_id') THEN
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


-- ---------- Tests de fumée ----------
-- Les fonctions de test tournent avec les droits du propriétaire : elles contrôlent
-- la règle (private.peut_gerer_point_bloquant), les politiques et la soumission
-- d'origine, pas le filtrage RLS lui-même (vérifié à part avec le rôle authenticated).
CREATE OR REPLACE FUNCTION private.run_manager_blockers_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _sub uuid;
  _blk uuid;
  _s public.submissions;
  _mien constant text := 'ZZ MB mon équipe';
  _autre constant text := 'ZZ MB autre équipe';
  _manager constant text := '{"email":"mb.manager@fumee.happyplace.fr"}';
  _collab constant text := '{"email":"mb.collab@fumee.happyplace.fr"}';
  _admin constant text := '{"email":"mb.admin@fumee.happyplace.fr"}';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_mien), (_autre) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('mb.manager@fumee.happyplace.fr', 'Kesha', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _mien);
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('mb.collab@fumee.happyplace.fr', _mien, 'Gontran', 'Collab') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('mb.admin@fumee.happyplace.fr', 'Olivia', 'Admin') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');

    PERFORM set_config('request.jwt.claims', _manager, true);
    _res := _res || jsonb_build_object('t', 'Points bloquants : le manager gère ceux de son équipe, pas ceux d''une autre',
      'ok', private.peut_gerer_point_bloquant(_mien) AND NOT private.peut_gerer_point_bloquant(_autre)
            AND private.peut_gerer_point_bloquant(upper(_mien)),
      'd', 'règle vérifiée');
    PERFORM set_config('request.jwt.claims', _collab, true);
    _res := _res || jsonb_build_object('t', 'Points bloquants : un collaborateur ne gère aucun point bloquant',
      'ok', NOT private.peut_gerer_point_bloquant(_mien), 'd', 'règle vérifiée');
    PERFORM set_config('request.jwt.claims', _admin, true);
    _res := _res || jsonb_build_object('t', 'Points bloquants : l''admin gère tous les points bloquants',
      'ok', private.peut_gerer_point_bloquant(_autre), 'd', 'règle vérifiée');

    _res := _res || jsonb_build_object('t', 'Points bloquants : politiques de modification et de suppression du manager en place',
      'ok', (SELECT count(*) FROM pg_policy
              WHERE polrelid = 'public.blockers'::regclass
                AND polname IN ('Managers update team blockers', 'Managers delete team blockers')) = 2
            AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid = 'public.blockers'::regclass
                              AND polcmd IN ('a') AND polname <> 'Admin write'),
      'd', 'aucune politique de création pour le manager');

    -- Un point publié à partir d'une soumission, puis supprimé par le manager.
    PERFORM set_config('request.jwt.claims', _collab, true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le badge d''accès ne fonctionne plus.', 'point bloquant', 'warning')
      RETURNING id INTO _sub;
    PERFORM set_config('request.jwt.claims', _manager, true);
    _blk := public.publish_blocker_submission(_sub, 'Badge d''accès en panne', _mien, 'warning', NULL);
    UPDATE blockers SET status = 'EN COURS', title = 'Badge d''accès hors service' WHERE id = _blk;
    BEGIN
      UPDATE blockers SET status = 'OUVERT' WHERE id = _blk;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _blk;
      _res := _res || jsonb_build_object('t', 'Points bloquants : la règle OUVERT puis EN COURS avant RÉSOLU s''applique au manager', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'Points bloquants : la règle OUVERT puis EN COURS avant RÉSOLU s''applique au manager', 'ok', true, 'd', SQLERRM);
    END;
    DELETE FROM blockers WHERE id = _blk;
    SELECT * INTO _s FROM submissions WHERE id = _sub;
    _res := _res || jsonb_build_object('t', 'Points bloquants : supprimé par le manager, la soumission d''origine reste publiée, sans lien',
      'ok', NOT EXISTS (SELECT 1 FROM blockers WHERE id = _blk) AND _s.status = 'validée' AND _s.blocker_id IS NULL,
      'd', _s.status::text);

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée « points bloquants du manager »', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_manager_blockers_smoke_tests() FROM public, anon, authenticated;

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
  UNION ALL
  SELECT * FROM private.run_manager_blockers_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

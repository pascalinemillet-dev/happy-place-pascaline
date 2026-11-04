-- ============================================================
-- Point bloquant : pôle choisi uniquement dans le référentiel
-- ============================================================
-- Décision de Pascaline du 2026-11-04 : le pôle d'un point bloquant se choisit
-- uniquement dans le référentiel des équipes (les 6 pôles et « Admin »), sans
-- saisie libre. Jusqu'ici, seule la publication d'une soumission le contrôlait ;
-- l'admin pouvait écrire un pôle libre et « GENERAL » était la valeur par défaut.
--   * blockers.department référence teams.name : renommer un pôle met à jour
--     ses points bloquants ; supprimer un pôle encore utilisé est refusé ;
--   * plus de valeur par défaut « GENERAL ».
-- La migration s'arrête sans rien modifier si un point porte encore un pôle
-- hors référentiel, et le liste.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

DO $$
DECLARE
  _liste text;
BEGIN
  SELECT string_agg(DISTINCT b.department, ', ' ORDER BY b.department) INTO _liste
    FROM public.blockers b
   WHERE NOT EXISTS (SELECT 1 FROM public.teams t WHERE t.name = b.department);
  IF _liste IS NOT NULL THEN
    RAISE EXCEPTION 'Pôles hors référentiel à corriger avant la contrainte : %. Rien n''a été modifié.', _liste;
  END IF;
END $$;

ALTER TABLE public.blockers ALTER COLUMN department DROP DEFAULT;
ALTER TABLE public.blockers DROP CONSTRAINT IF EXISTS blockers_department_fkey;
ALTER TABLE public.blockers
  ADD CONSTRAINT blockers_department_fkey FOREIGN KEY (department)
  REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;

-- ---------- Test de base : le point de test prend un pôle du référentiel ----------
CREATE OR REPLACE FUNCTION private.run_base_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 4 lignes (2 créations, 1 validation, 1 refus)', 'ok', _cnt = 4, 'd', _cnt || ' ligne(s)');

    -- Revalidation annuelle
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Revalidation annuelle : une demande validée échue repasse « en attente »', 'ok', _st = 'en attente', 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO teams(name) VALUES ('ZZ Test blocage') ON CONFLICT DO NOTHING;
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'ZZ Test blocage') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, échéance de revalidation posée', 'ok',
      (SELECT revalidate_at IS NOT NULL FROM news WHERE id = _n), 'd', (SELECT status::text FROM news WHERE id = _n));

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;
REVOKE ALL ON FUNCTION private.run_base_smoke_tests() FROM public, anon, authenticated;

-- ---------- Tests de fumée ----------
CREATE OR REPLACE FUNCTION private.run_pole_referentiel_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _b uuid;
BEGIN
  BEGIN
    BEGIN
      INSERT INTO blockers(title, department) VALUES ('Pôle libre', 'Pôle inventé hors référentiel');
      _res := _res || jsonb_build_object('t', 'Pôle : un point bloquant hors référentiel est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN foreign_key_violation THEN
      _res := _res || jsonb_build_object('t', 'Pôle : un point bloquant hors référentiel est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      INSERT INTO blockers(title) VALUES ('Sans pôle');
      _res := _res || jsonb_build_object('t', 'Pôle : un point bloquant sans pôle est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN not_null_violation THEN
      _res := _res || jsonb_build_object('t', 'Pôle : un point bloquant sans pôle est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    INSERT INTO blockers(title, department) VALUES ('Point de l''administration', 'Admin') RETURNING id INTO _b;
    _res := _res || jsonb_build_object('t', 'Pôle : « Admin » reste un pôle possible', 'ok', _b IS NOT NULL, 'd', 'Admin');
    INSERT INTO teams(name) VALUES ('ZZ Pôle fumée') ON CONFLICT DO NOTHING;
    UPDATE blockers SET department = 'ZZ Pôle fumée' WHERE id = _b;
    UPDATE teams SET name = 'ZZ Pôle fumée renommé' WHERE name = 'ZZ Pôle fumée';
    _res := _res || jsonb_build_object('t', 'Pôle : renommer un pôle met à jour ses points bloquants',
      'ok', (SELECT department FROM blockers WHERE id = _b) = 'ZZ Pôle fumée renommé', 'd', 'renommé');
    BEGIN
      DELETE FROM teams WHERE name = 'ZZ Pôle fumée renommé';
      _res := _res || jsonb_build_object('t', 'Pôle : supprimer un pôle encore utilisé par un point bloquant est refusé', 'ok', false, 'd', 'supprimé à tort');
    EXCEPTION WHEN foreign_key_violation THEN
      _res := _res || jsonb_build_object('t', 'Pôle : supprimer un pôle encore utilisé par un point bloquant est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée « pôle du référentiel »', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;
  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_pole_referentiel_smoke_tests() FROM public, anon, authenticated;

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
  UNION ALL
  SELECT * FROM private.run_poles_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_pole_referentiel_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

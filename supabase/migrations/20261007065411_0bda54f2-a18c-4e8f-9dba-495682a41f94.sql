-- Garde-fou contre les régressions silencieuses après une modification d'ENUM (7 oct. 2026)

-- 1) Audit statique : valeurs d'ENUM écrites en dur dans les fonctions
CREATE OR REPLACE FUNCTION private.audit_enum_literals()
RETURNS TABLE(fonction text, valeur text, probleme text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _f record;
  _m text[];
  _labels text[];
  _ok boolean;
BEGIN
  SELECT array_agg(e.enumlabel) INTO _labels
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public';

  FOR _f IN
    SELECT n.nspname || '.' || p.proname AS fn, p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f'
      AND l.lanname IN ('plpgsql', 'sql')
      AND p.proname NOT IN ('audit_enum_literals', 'run_smoke_tests')
  LOOP
    -- a) valeur castée explicitement vers un ENUM : 'x'::public.mon_enum
    FOR _m IN SELECT regexp_matches(_f.prosrc, '''((?:[^'']|'''')*)''::(?:public\.)?(\w+)', 'g') LOOP
      IF EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'public' AND t.typname = _m[2] AND t.typtype = 'e') THEN
        SELECT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                       JOIN pg_namespace n ON n.oid = t.typnamespace
                       WHERE n.nspname = 'public' AND t.typname = _m[2]
                         AND e.enumlabel = replace(_m[1], '''''', '''')) INTO _ok;
        IF NOT _ok THEN
          fonction := _f.fn; valeur := replace(_m[1], '''''', '''');
          probleme := 'Valeur absente de l''ENUM ' || _m[2];
          RETURN NEXT;
        END IF;
      END IF;
    END LOOP;
    -- b) comparaison non typée sur une colonne d'ENUM : status = 'x', role IN ('x', 'y')…
    FOR _m IN SELECT regexp_matches(_f.prosrc,
        '\m_?(?:status|old_status|new_status|role|severity|rejection_category)\s*(?:=|<>|!=)\s*''((?:[^'']|'''')*)''(?!::)', 'g') LOOP
      IF NOT (replace(_m[1], '''''', '''') = ANY(_labels)) THEN
        fonction := _f.fn; valeur := replace(_m[1], '''''', '''');
        probleme := 'Comparaison à une valeur qui n''existe dans aucun ENUM';
        RETURN NEXT;
      END IF;
    END LOOP;
    FOR _m IN SELECT regexp_matches(_f.prosrc,
        '\m_?(?:status|old_status|new_status|role|severity|rejection_category)\s+(?:NOT\s+)?IN\s*\(([^)]*)\)', 'gi') LOOP
      FOR valeur IN SELECT replace(x[1], '''''', '''')
                    FROM regexp_matches(_m[1], '''((?:[^'']|'''')*)''', 'g') x LOOP
        IF NOT (valeur = ANY(_labels)) THEN
          fonction := _f.fn;
          probleme := 'Liste IN contenant une valeur qui n''existe dans aucun ENUM';
          RETURN NEXT;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END;
$$;

-- 2) Test de fumée : rejoue les parcours qui dépendent des statuts, puis annule tout
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
RETURNS TABLE(test text, ok boolean, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
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
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
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
$$;

REVOKE ALL ON FUNCTION private.audit_enum_literals() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;
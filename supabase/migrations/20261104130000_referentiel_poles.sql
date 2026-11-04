-- ============================================================
-- Référentiel : 12 équipes regroupées en 5 pôles, plus le pôle Cloud et cybersécurité
-- ============================================================
-- Décision de Pascaline du 2026-11-04 :
--   Recrutement et conseil    <- Direction recrutement, Direction Conseil
--   Commercial et marketing   <- Direction Commerciale, Relation clients, Marketing
--   Produit, Data et IA       <- Product, Pôle Data et IA
--   People et opérations      <- People, Opérations
--   Finance et juridique      <- Finance, Accounting, Legal (sans manager : l'admin traite)
--   Cloud et cybersécurité    <- pôle à part entière, nouveau (« CLOUD & CYBERSÉCURITÉ »
--                                saisi sur des points bloquants) ; sans manager : l'admin traite
-- « Admin » reste l'équipe réservée.
--
-- Les comptes, les équipes des managers, les soumissions et le pôle des points
-- bloquants passent au pôle cible. Les pôles saisis hors référentiel sur des
-- points bloquants (« PRODUCT TEAM », « DATA & IA », « RELATIONS CLIENTS »,
-- « OPÉRATIONS »…) sont ramenés au pôle cible.
-- Rien n'est supprimé hormis les anciennes lignes du référentiel, une fois vides.
-- Une équipe absente de la table de correspondance reste telle quelle : la
-- fonction la signale.
--
-- private.appliquer_referentiel_poles() se relance sans effet (idempotente) ;
-- seed.sql l'appelle après le chargement des données de démo.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

CREATE OR REPLACE FUNCTION private.appliquer_referentiel_poles()
 RETURNS TABLE(etape text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _m record;
  _t record;
  _n int;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS pg_temp.hp_poles(ancien text PRIMARY KEY, nouveau text NOT NULL) ON COMMIT DROP;
  TRUNCATE pg_temp.hp_poles;
  INSERT INTO pg_temp.hp_poles(ancien, nouveau) VALUES
    ('direction recrutement', 'Recrutement et conseil'),
    ('direction conseil', 'Recrutement et conseil'),
    ('cloud & cybersécurité', 'Cloud et cybersécurité'),
    ('cloud et cybersécurité', 'Cloud et cybersécurité'),
    ('direction commerciale', 'Commercial et marketing'),
    ('relation clients', 'Commercial et marketing'),
    ('relations clients', 'Commercial et marketing'),
    ('marketing', 'Commercial et marketing'),
    ('product', 'Produit, Data et IA'),
    ('product team', 'Produit, Data et IA'),
    ('pôle data et ia', 'Produit, Data et IA'),
    ('data & ia', 'Produit, Data et IA'),
    ('people', 'People et opérations'),
    ('opérations', 'People et opérations'),
    ('finance', 'Finance et juridique'),
    ('accounting', 'Finance et juridique'),
    ('legal', 'Finance et juridique');

  -- 1. Les 6 pôles existent dans le référentiel.
  INSERT INTO public.teams(name)
  SELECT DISTINCT nouveau FROM pg_temp.hp_poles
  ON CONFLICT DO NOTHING;

  -- 2. Chaque ancienne équipe du référentiel passe au pôle cible, puis disparaît.
  FOR _t IN
    SELECT t.name AS ancien, m.nouveau
      FROM public.teams t
      JOIN pg_temp.hp_poles m ON m.ancien = lower(btrim(t.name))
     WHERE NOT t.is_reserved AND t.name <> m.nouveau
  LOOP
    -- Un manager des deux équipes fusionnées garde une seule ligne.
    DELETE FROM public.manager_teams mt
     WHERE mt.team = _t.ancien
       AND EXISTS (SELECT 1 FROM public.manager_teams m2
                    WHERE m2.allowed_user_id = mt.allowed_user_id AND m2.team = _t.nouveau);
    UPDATE public.manager_teams SET team = _t.nouveau WHERE team = _t.ancien;
    UPDATE public.allowed_users SET team = _t.nouveau WHERE team = _t.ancien;
    UPDATE public.submissions SET team = _t.nouveau WHERE team = _t.ancien;
    DELETE FROM public.teams WHERE name = _t.ancien;
    etape := 'Équipe regroupée'; detail := _t.ancien || ' -> ' || _t.nouveau; RETURN NEXT;
  END LOOP;

  -- 3. Le pôle des points bloquants, y compris les saisies hors référentiel.
  FOR _m IN SELECT ancien, nouveau FROM pg_temp.hp_poles LOOP
    UPDATE public.blockers SET department = _m.nouveau
     WHERE lower(btrim(department)) = _m.ancien AND department <> _m.nouveau;
    GET DIAGNOSTICS _n = ROW_COUNT;
    IF _n > 0 THEN
      etape := 'Pôle de point bloquant'; detail := _m.ancien || ' -> ' || _m.nouveau || ' (' || _n || ')'; RETURN NEXT;
    END IF;
  END LOOP;
  -- Casse différente d'un pôle cible (« produit, data et ia » …).
  UPDATE public.blockers b SET department = t.name
    FROM public.teams t
   WHERE lower(btrim(b.department)) = lower(t.name) AND b.department <> t.name;

  -- 4. Ce qui reste hors des 6 pôles est signalé, pas modifié.
  FOR _t IN
    SELECT name FROM public.teams
     WHERE NOT is_reserved AND name NOT IN (SELECT nouveau FROM pg_temp.hp_poles)
     ORDER BY name
  LOOP
    etape := 'Équipe hors des 6 pôles, inchangée'; detail := _t.name; RETURN NEXT;
  END LOOP;
  FOR _t IN
    SELECT department, count(*) AS n FROM public.blockers
     WHERE department NOT IN (SELECT name FROM public.teams)
     GROUP BY department ORDER BY department
  LOOP
    etape := 'Pôle de point bloquant hors référentiel, inchangé'; detail := _t.department || ' (' || _t.n || ')'; RETURN NEXT;
  END LOOP;
  RETURN;
END
$function$;
REVOKE ALL ON FUNCTION private.appliquer_referentiel_poles() FROM public, anon, authenticated;

-- ---------- Tests de fumée ----------
CREATE OR REPLACE FUNCTION private.run_poles_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _anciennes int;
  _orphelins int;
BEGIN
  SELECT count(*) INTO _anciennes FROM public.teams
   WHERE lower(name) IN ('direction recrutement', 'direction conseil', 'direction commerciale', 'relation clients',
                         'marketing', 'product', 'pôle data et ia', 'people', 'opérations', 'finance', 'accounting', 'legal');
  _res := _res || jsonb_build_object('t', 'Pôles : les 6 pôles existent, les 12 anciennes équipes ont disparu du référentiel',
    'ok', (SELECT count(*) FROM public.teams WHERE name IN ('Recrutement et conseil', 'Commercial et marketing',
            'Produit, Data et IA', 'People et opérations', 'Finance et juridique', 'Cloud et cybersécurité')) = 6
          AND _anciennes = 0,
    'd', _anciennes || ' ancienne(s) équipe(s) restante(s)');
  SELECT count(*) INTO _orphelins FROM public.manager_teams mt
   WHERE NOT EXISTS (SELECT 1 FROM public.teams t WHERE t.name = mt.team);
  _res := _res || jsonb_build_object('t', 'Pôles : chaque équipe de manager existe dans le référentiel',
    'ok', _orphelins = 0, 'd', _orphelins || ' ligne(s) orpheline(s)');
  _res := _res || jsonb_build_object('t', 'Pôles : « Admin » reste l''équipe réservée',
    'ok', EXISTS (SELECT 1 FROM public.teams WHERE name = 'Admin' AND is_reserved), 'd', 'Admin');
  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_poles_smoke_tests() FROM public, anon, authenticated;

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
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

-- ---------- Application ----------
SELECT * FROM private.appliquer_referentiel_poles();

COMMIT;

SELECT * FROM private.run_smoke_tests();

-- ============================================================
-- US43 et F4 révisée (2026-11-03) : ordre unique de 1 à 10, délai en jours
-- ============================================================
-- Demandes de Pascaline du 2026-11-03 :
--   - l'admin choisit l'ordre d'un indicateur du dashboard entre 1 et 10 ;
--     un ordre déjà pris par un autre indicateur affiché ne lui est pas
--     proposé. La base refuse deux indicateurs affichés au même ordre ;
--   - Délai moyen de recrutement s'affiche en jours (« 31 jours »).
--
-- Les indicateurs déjà affichés sont renumérotés de 1 à n dans leur ordre
-- actuel (puis par libellé en cas d'égalité) : l'ordre vu sur le dashboard ne
-- change pas. Un indicateur non affiché garde l'ordre 99 par défaut.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true
-- ============================================================

BEGIN;

-- ---------- Ordre de 1 à 10, unique parmi les indicateurs affichés ----------
WITH rang AS (
  SELECT key, row_number() OVER (ORDER BY ordre_dashboard, label, key) AS n
    FROM public.metrics
   WHERE afficher_dashboard
)
UPDATE public.metrics m SET ordre_dashboard = rang.n
  FROM rang
 WHERE rang.key = m.key AND m.ordre_dashboard IS DISTINCT FROM rang.n;

-- Un indicateur retiré du dashboard libère son ordre.
UPDATE public.metrics SET ordre_dashboard = 99 WHERE NOT afficher_dashboard;

ALTER TABLE public.metrics
  ADD CONSTRAINT metrics_ordre_dashboard_affiche
  CHECK (NOT afficher_dashboard OR ordre_dashboard BETWEEN 1 AND 10);

CREATE UNIQUE INDEX metrics_ordre_dashboard_unique
  ON public.metrics (ordre_dashboard) WHERE afficher_dashboard;

-- ---------- Délai moyen de recrutement en jours ----------
UPDATE public.metrics SET unit = 'jours' WHERE key = 'delai_moyen_recrutement';

COMMIT;

-- ============================================================
-- Tests de fumée
-- ============================================================
BEGIN;

-- US43 : les tests partent d'un dashboard vide (annulé en fin de test), pour
-- ne pas dépendre des ordres choisis sur la base en ligne.
CREATE OR REPLACE FUNCTION private.run_us43_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _v record;
BEGIN
  BEGIN
    UPDATE metrics SET afficher_dashboard = false, ordre_dashboard = 99 WHERE afficher_dashboard;

    INSERT INTO metrics(key, label, value, unit, period_start, period_end)
      VALUES ('zz_us43', 'ZZ US43', 12, NULL, '2026-10-01', '2026-10-31');
    SELECT * INTO _v FROM metrics_with_trend WHERE key = 'zz_us43';
    _res := _res || jsonb_build_object('t', 'US43 : un nouvel indicateur n''est pas affiché sur le dashboard par défaut',
      'ok', _v.afficher_dashboard = false AND _v.ordre_dashboard = 99,
      'd', coalesce(_v.afficher_dashboard::text || ' / ' || _v.ordre_dashboard::text, 'aucune ligne'));

    UPDATE metrics SET afficher_dashboard = true, ordre_dashboard = 3 WHERE key = 'zz_us43';
    SELECT * INTO _v FROM metrics_with_trend WHERE key = 'zz_us43';
    _res := _res || jsonb_build_object('t', 'US43 : l''admin l''affiche, avec son ordre',
      'ok', _v.afficher_dashboard AND _v.ordre_dashboard = 3,
      'd', coalesce(_v.ordre_dashboard::text, 'aucune ligne'));

    BEGIN
      UPDATE metrics SET ordre_dashboard = 0 WHERE key = 'zz_us43';
      _res := _res || jsonb_build_object('t', 'US43 : un ordre hors de 1 à 99 est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'US43 : un ordre hors de 1 à 99 est refusé', 'ok', true, 'd', 'refusé par la base');
    END;

    BEGIN
      UPDATE metrics SET ordre_dashboard = 11 WHERE key = 'zz_us43';
      _res := _res || jsonb_build_object('t', 'US43 : un indicateur affiché a un ordre de 1 à 10', 'ok', false, 'd', 'ordre 11 accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'US43 : un indicateur affiché a un ordre de 1 à 10', 'ok', true, 'd', 'ordre 11 refusé par la base');
    END;

    INSERT INTO metrics(key, label, unit) VALUES ('zz_us43_bis', 'ZZ US43 bis', NULL);
    BEGIN
      UPDATE metrics SET afficher_dashboard = true, ordre_dashboard = 3 WHERE key = 'zz_us43_bis';
      _res := _res || jsonb_build_object('t', 'US43 : deux indicateurs affichés ne partagent pas un ordre', 'ok', false, 'd', 'doublon accepté à tort');
    EXCEPTION WHEN unique_violation THEN
      _res := _res || jsonb_build_object('t', 'US43 : deux indicateurs affichés ne partagent pas un ordre', 'ok', true, 'd', 'refusé par la base');
    END;

    UPDATE metrics SET afficher_dashboard = false, ordre_dashboard = 99 WHERE key = 'zz_us43';
    UPDATE metrics SET afficher_dashboard = true, ordre_dashboard = 3 WHERE key = 'zz_us43_bis';
    SELECT * INTO _v FROM metrics WHERE key = 'zz_us43_bis';
    _res := _res || jsonb_build_object('t', 'US43 : un indicateur retiré du dashboard libère son ordre',
      'ok', _v.afficher_dashboard AND _v.ordre_dashboard = 3,
      'd', coalesce(_v.ordre_dashboard::text, 'aucune ligne'));

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US43', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us43_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

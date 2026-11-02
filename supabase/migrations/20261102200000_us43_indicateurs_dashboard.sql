-- ============================================================
-- Lot 2 (T12) : US43, choisir les indicateurs affichés sur le dashboard
-- ============================================================
-- Retour oral donné au product builder le 2026-11-02 (B7) : le bloc
-- Indicateurs ne montrait que Taux de placement et Missions actives, fixés
-- dans le code. Chaque indicateur porte désormais deux réglages, choisis par
-- l'admin : l'afficher ou non sur le dashboard, et son ordre.
--
-- Au départ, seuls Taux de placement (1) et Missions actives (2) sont
-- affichés, comme avant. Une ligne sans période n'est pas modifiée ici : la
-- contrainte de période (F4) demanderait une période ; l'admin la cochera en
-- saisissant sa période.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

ALTER TABLE public.metrics
  ADD COLUMN afficher_dashboard boolean NOT NULL DEFAULT false,
  ADD COLUMN ordre_dashboard smallint NOT NULL DEFAULT 99
    CONSTRAINT metrics_ordre_dashboard_borne CHECK (ordre_dashboard BETWEEN 1 AND 99);

UPDATE public.metrics
   SET afficher_dashboard = true,
       ordre_dashboard = CASE key WHEN 'taux_placement' THEN 1 ELSE 2 END
 WHERE key IN ('taux_placement', 'missions_actives')
   AND period_start IS NOT NULL AND period_end IS NOT NULL AND period_end >= period_start
   AND (NOT comptage OR value = trunc(value));

CREATE OR REPLACE VIEW public.metrics_with_trend
WITH (security_invoker = true) AS
SELECT m.key,
    m.label,
    m.value,
    m.unit,
    m.updated_at,
    p.value AS previous_value,
    CASE
        WHEN p.value IS NULL OR p.value = m.value THEN 'stable'::text
        WHEN m.value > p.value THEN 'hausse'::text
        ELSE 'baisse'::text
    END AS trend,
    CASE WHEN p.value IS NULL THEN NULL ELSE m.value - p.value END AS delta,
    m.period_start,
    m.period_end,
    m.comptage,
    p.recorded_at AS previous_recorded_at,
    p.period_start AS previous_period_start,
    p.period_end AS previous_period_end,
    m.afficher_dashboard,
    m.ordre_dashboard
FROM public.metrics m
LEFT JOIN LATERAL (
    SELECT h.value, h.recorded_at, h.period_start, h.period_end
    FROM public.metrics_history h
    WHERE h.metric_key = m.key
    ORDER BY h.recorded_at DESC
    OFFSET 1
    LIMIT 1
) p ON true;
GRANT SELECT ON public.metrics_with_trend TO authenticated;

COMMIT;

-- ============================================================
-- Tests de fumée de US43, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

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
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

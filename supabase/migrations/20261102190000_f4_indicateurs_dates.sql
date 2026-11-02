-- ============================================================
-- Lot 2 (T12) : F4 « Indicateurs datés et périodés » (US40, US41, US42)
-- ============================================================
-- US41 : chaque saisie d'un indicateur porte sa période de calcul (début et
--        fin, obligatoires) ; l'historique la conserve.
-- US42 : clés techniques alignées sur les libellés (C3) ; les comptages
--        (Missions actives, Postes ouverts, Entretiens réalisés) sont entiers.
-- US40 : la vue metrics_with_trend donne la période, la date de la saisie
--        comparée par l'écart et sa période.
--
-- Les indicateurs déjà en base n'ont pas de période : ils l'auront à leur
-- prochaine saisie. Les contraintes sont posées NOT VALID : elles s'appliquent
-- à toute nouvelle saisie, sans réécrire l'existant.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

ALTER TABLE public.metrics
  ADD COLUMN period_start date,
  ADD COLUMN period_end date,
  ADD COLUMN comptage boolean NOT NULL DEFAULT false;

ALTER TABLE public.metrics_history
  ADD COLUMN period_start date,
  ADD COLUMN period_end date;

-- ---------- US42 : clés alignées sur les libellés (C3) ----------
-- Le trigger record_metric_history reporte le changement de clé sur l'historique.
DO $$
DECLARE
  _r record;
BEGIN
  FOR _r IN SELECT * FROM (VALUES
      ('training_kpi',   'taux_placement'),
      ('active_users',   'missions_actives'),
      ('nps',            'nps_candidats'),
      ('engagement',     'taux_acceptation'),
      ('turnover',       'delai_moyen_recrutement'),
      ('absenteeism',    'taux_reponse_candidats'),
      ('open_positions', 'postes_ouverts'),
      ('training_hours', 'entretiens_realises')) AS t(ancienne, nouvelle)
  LOOP
    IF EXISTS (SELECT 1 FROM public.metrics WHERE key = _r.ancienne)
       AND NOT EXISTS (SELECT 1 FROM public.metrics WHERE key = _r.nouvelle) THEN
      UPDATE public.metrics SET key = _r.nouvelle WHERE key = _r.ancienne;
    END IF;
  END LOOP;
END $$;

-- Comptages : affichage et saisie entiers
UPDATE public.metrics SET comptage = true
 WHERE key IN ('missions_actives', 'postes_ouverts', 'entretiens_realises');

-- ---------- US41 : période obligatoire à chaque saisie ----------
ALTER TABLE public.metrics
  ADD CONSTRAINT metrics_periode_obligatoire
  CHECK (period_start IS NOT NULL AND period_end IS NOT NULL AND period_end >= period_start) NOT VALID;
ALTER TABLE public.metrics
  ADD CONSTRAINT metrics_comptage_entier
  CHECK (NOT comptage OR value = trunc(value)) NOT VALID;

-- L'historique enregistre la valeur et sa période à chaque changement.
CREATE OR REPLACE FUNCTION private.record_metric_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.key <> OLD.key THEN
    UPDATE public.metrics_history SET metric_key = NEW.key WHERE metric_key = OLD.key;
  END IF;
  IF TG_OP = 'INSERT'
     OR NEW.value IS DISTINCT FROM OLD.value
     OR NEW.period_start IS DISTINCT FROM OLD.period_start
     OR NEW.period_end IS DISTINCT FROM OLD.period_end THEN
    INSERT INTO public.metrics_history (metric_key, value, period_start, period_end)
    VALUES (NEW.key, NEW.value, NEW.period_start, NEW.period_end);
  END IF;
  RETURN NEW;
END
$function$;

-- ---------- US40 : période, saisie comparée et date de mise à jour ----------
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
    p.period_end AS previous_period_end
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
-- Tests de fumée de F4, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_f4_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _cnt int;
  _v record;
BEGIN
  BEGIN
    -- US42 : plus aucune ancienne clé
    SELECT count(*) INTO _cnt FROM metrics
     WHERE key IN ('training_kpi', 'active_users', 'nps', 'engagement', 'turnover',
                   'absenteeism', 'open_positions', 'training_hours');
    _res := _res || jsonb_build_object('t', 'F4 : plus aucune ancienne clé d''indicateur (C3)',
      'ok', _cnt = 0, 'd', _cnt::text || ' ancienne(s) clé(s)');

    -- US41 : période obligatoire
    BEGIN
      INSERT INTO metrics(key, label, value, unit) VALUES ('zz_f4_sans_periode', 'ZZ sans période', 1, NULL);
      _res := _res || jsonb_build_object('t', 'F4 : une saisie sans période est refusée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F4 : une saisie sans période est refusée', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      INSERT INTO metrics(key, label, value, unit, period_start, period_end)
        VALUES ('zz_f4_periode_inversee', 'ZZ période inversée', 1, NULL, '2026-10-31', '2026-10-01');
      _res := _res || jsonb_build_object('t', 'F4 : une période qui finit avant de commencer est refusée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F4 : une période qui finit avant de commencer est refusée', 'ok', true, 'd', 'refusé par la base');
    END;

    -- US42 : un comptage n'accepte pas de décimale
    BEGIN
      INSERT INTO metrics(key, label, value, unit, period_start, period_end, comptage)
        VALUES ('zz_f4_comptage', 'ZZ comptage', 34.2, NULL, '2026-10-01', '2026-10-31', true);
      _res := _res || jsonb_build_object('t', 'F4 : un comptage avec une décimale est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F4 : un comptage avec une décimale est refusé', 'ok', true, 'd', 'refusé par la base');
    END;

    -- US40 et US41 : deux saisies périodées, la vue donne la période et la saisie comparée
    INSERT INTO metrics(key, label, value, unit, period_start, period_end)
      VALUES ('zz_f4_test', 'ZZ test F4', 38.6, '%', '2026-09-01', '2026-09-30');
    UPDATE metrics_history SET recorded_at = '2026-10-05 10:00+02' WHERE metric_key = 'zz_f4_test';
    UPDATE metrics SET value = 40.6, period_start = '2026-10-01', period_end = '2026-10-31', updated_at = now()
     WHERE key = 'zz_f4_test';
    SELECT * INTO _v FROM metrics_with_trend WHERE key = 'zz_f4_test';
    _res := _res || jsonb_build_object('t', 'F4 : la vue donne la période, la saisie comparée et sa période',
      'ok', _v.period_start = '2026-10-01' AND _v.period_end = '2026-10-31'
            AND _v.previous_value = 38.6 AND _v.previous_recorded_at = '2026-10-05 10:00+02'
            AND _v.previous_period_start = '2026-09-01' AND _v.previous_period_end = '2026-09-30'
            AND _v.delta = 2.0 AND _v.trend = 'hausse',
      'd', coalesce(_v.period_start::text || ' / ' || _v.previous_recorded_at::text, 'aucune ligne'));

    SELECT count(*) INTO _cnt FROM metrics_history
     WHERE metric_key = 'zz_f4_test' AND period_start IS NOT NULL;
    _res := _res || jsonb_build_object('t', 'F4 : l''historique conserve la période de chaque saisie',
      'ok', _cnt = 2, 'd', _cnt::text || ' saisie(s) périodée(s)');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée F4', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_f4_smoke_tests() FROM public, anon, authenticated;

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
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

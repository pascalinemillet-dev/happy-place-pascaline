-- ============================================================
-- F4 révisée (2026-11-03) : un mois de référence pour tous les indicateurs
-- ============================================================
-- Demande de Pascaline du 2026-11-03. Remplace la période début-fin libre de
-- chaque saisie (F4, 2026-11-02) :
--   - tous les indicateurs portent sur le même mois, un mois terminé ;
--   - l'admin choisit ce mois (mois et année) dans « Gestion des données >
--     Indicateurs » : le dashboard affiche ce mois, et reste sur le précédent
--     tant que l'admin ne l'a pas changé ;
--   - chaque carte compare la valeur du mois à celle du mois précédent ;
--   - chaque indicateur a un sens favorable (une hausse ou une baisse) qui
--     donne la couleur de l'évolution : verte si favorable, rouge sinon,
--     grise si l'écart est nul ou si le mois précédent n'a pas de valeur.
--
-- Modèle :
--   public.indicateurs_reglages  une seule ligne : le mois affiché
--   public.metrics_mensuels      une valeur par indicateur et par mois
--   public.indicateurs_du_mois   vue lue par le dashboard et par l'admin
-- La table public.metrics garde la définition de l'indicateur (libellé,
-- unité, comptage, affichage, ordre, sens). Ses colonnes value, period_start
-- et period_end ne sont plus saisies ; elles restent en base, avec la vue
-- metrics_with_trend, pour l'historique de F4.
--
-- Données en ligne : seules les saisies dont la période est un mois civil
-- entier sont reprises comme valeurs mensuelles. Aucune valeur ni date n'est
-- inventée : un mois sans saisie s'affiche « Non renseigné ».
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true
-- ============================================================

BEGIN;

-- ---------- La valeur et la période ne se saisissent plus sur l'indicateur ----------
-- Elles se saisissent par mois. Retiré en premier : une ligne sans période
-- (« Période non renseignée ») ne pourrait plus être modifiée.
ALTER TABLE public.metrics ALTER COLUMN value DROP NOT NULL;
ALTER TABLE public.metrics DROP CONSTRAINT IF EXISTS metrics_periode_obligatoire;
ALTER TABLE public.metrics
  ADD CONSTRAINT metrics_periode_coherente
  CHECK (period_start IS NULL OR period_end IS NULL OR period_end >= period_start) NOT VALID;

-- ---------- Définition de l'indicateur : sens favorable ----------
ALTER TABLE public.metrics
  ADD COLUMN sens_favorable text NOT NULL DEFAULT 'hausse'
    CONSTRAINT metrics_sens_favorable_valeur CHECK (sens_favorable IN ('hausse', 'baisse'));

-- Un délai qui s'allonge est une mauvaise nouvelle.
UPDATE public.metrics SET sens_favorable = 'baisse' WHERE key = 'delai_moyen_recrutement';

-- L'historique de F4 n'enregistre que les saisies qui ont une valeur.
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
  IF NEW.value IS NOT NULL AND (
       TG_OP = 'INSERT'
       OR NEW.value IS DISTINCT FROM OLD.value
       OR NEW.period_start IS DISTINCT FROM OLD.period_start
       OR NEW.period_end IS DISTINCT FROM OLD.period_end) THEN
    INSERT INTO public.metrics_history (metric_key, value, period_start, period_end)
    VALUES (NEW.key, NEW.value, NEW.period_start, NEW.period_end);
  END IF;
  RETURN NEW;
END
$function$;

-- ---------- Dernier mois terminé ----------
-- Le 2026-11-03, renvoie le 2026-10-01. Fuseau de Bigger Boat : Europe/Paris.
CREATE OR REPLACE FUNCTION private.dernier_mois_termine()
RETURNS date
LANGUAGE sql
STABLE
AS $function$
  SELECT (date_trunc('month', (now() AT TIME ZONE 'Europe/Paris')) - interval '1 month')::date
$function$;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.dernier_mois_termine() TO authenticated;

-- Refuse un mois qui n'est pas terminé (mois en cours ou à venir).
CREATE OR REPLACE FUNCTION private.refuser_mois_non_termine(_mois date)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  IF _mois > private.dernier_mois_termine() THEN
    RAISE EXCEPTION 'Le mois % n''est pas terminé : choisissez un mois jusqu''à %.',
      to_char(_mois, 'MM/YYYY'), to_char(private.dernier_mois_termine(), 'MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;
END
$function$;

-- ---------- Mois affiché, choisi par l'admin ----------
CREATE TABLE public.indicateurs_reglages (
  id boolean PRIMARY KEY DEFAULT true CONSTRAINT indicateurs_reglages_une_ligne CHECK (id),
  mois_reference date NOT NULL
    CONSTRAINT indicateurs_reglages_premier_du_mois
    CHECK (mois_reference = date_trunc('month', mois_reference)::date),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by_email text
);
GRANT SELECT, UPDATE ON public.indicateurs_reglages TO authenticated;
GRANT ALL ON public.indicateurs_reglages TO service_role;
ALTER TABLE public.indicateurs_reglages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allowed read" ON public.indicateurs_reglages
  FOR SELECT TO authenticated USING (private.is_allowed());
CREATE POLICY "Admin update" ON public.indicateurs_reglages
  FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

-- Au départ : le dernier mois terminé à la date de la migration.
INSERT INTO public.indicateurs_reglages (mois_reference) VALUES (private.dernier_mois_termine());

-- ---------- Une valeur par indicateur et par mois ----------
CREATE TABLE public.metrics_mensuels (
  metric_key text NOT NULL REFERENCES public.metrics(key) ON UPDATE CASCADE ON DELETE CASCADE,
  mois date NOT NULL
    CONSTRAINT metrics_mensuels_premier_du_mois CHECK (mois = date_trunc('month', mois)::date),
  value numeric NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by_email text,
  PRIMARY KEY (metric_key, mois)
);
CREATE INDEX metrics_mensuels_mois ON public.metrics_mensuels (mois);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.metrics_mensuels TO authenticated;
GRANT ALL ON public.metrics_mensuels TO service_role;
ALTER TABLE public.metrics_mensuels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allowed read" ON public.metrics_mensuels
  FOR SELECT TO authenticated USING (private.is_allowed());
CREATE POLICY "Admin write" ON public.metrics_mensuels
  FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

-- Contrôles à la saisie : mois terminé, comptage entier, auteur et date.
CREATE OR REPLACE FUNCTION private.controler_metric_mensuel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM private.refuser_mois_non_termine(NEW.mois);
  IF EXISTS (SELECT 1 FROM public.metrics WHERE key = NEW.metric_key AND comptage)
     AND NEW.value <> trunc(NEW.value) THEN
    RAISE EXCEPTION 'Un comptage est un nombre entier.' USING ERRCODE = 'check_violation';
  END IF;
  NEW.updated_at := now();
  NEW.updated_by_email := coalesce(lower(auth.jwt() ->> 'email'), NEW.updated_by_email);
  RETURN NEW;
END
$function$;
CREATE TRIGGER controler_metric_mensuel
  BEFORE INSERT OR UPDATE ON public.metrics_mensuels
  FOR EACH ROW EXECUTE FUNCTION private.controler_metric_mensuel();

-- Chaque saisie mensuelle laisse une trace dans l'historique de F4 (US41).
CREATE OR REPLACE FUNCTION private.historiser_metric_mensuel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.value IS DISTINCT FROM OLD.value THEN
    INSERT INTO public.metrics_history (metric_key, value, period_start, period_end)
    VALUES (NEW.metric_key, NEW.value, NEW.mois, (NEW.mois + interval '1 month' - interval '1 day')::date);
  END IF;
  RETURN NEW;
END
$function$;
CREATE TRIGGER historiser_metric_mensuel
  AFTER INSERT OR UPDATE ON public.metrics_mensuels
  FOR EACH ROW EXECUTE FUNCTION private.historiser_metric_mensuel();

CREATE OR REPLACE FUNCTION private.controler_indicateurs_reglages()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  PERFORM private.refuser_mois_non_termine(NEW.mois_reference);
  NEW.updated_at := now();
  NEW.updated_by_email := coalesce(lower(auth.jwt() ->> 'email'), NEW.updated_by_email);
  RETURN NEW;
END
$function$;
CREATE TRIGGER controler_indicateurs_reglages
  BEFORE INSERT OR UPDATE ON public.indicateurs_reglages
  FOR EACH ROW EXECUTE FUNCTION private.controler_indicateurs_reglages();

-- ---------- Reprise des saisies existantes ----------
-- Seules les saisies dont la période est un mois civil entier et terminé
-- deviennent des valeurs mensuelles ; pour un même mois, la plus récente.
-- Les triggers sont suspendus : ces saisies figurent déjà dans l'historique,
-- et leur date de saisie d'origine est conservée.
ALTER TABLE public.metrics_mensuels DISABLE TRIGGER historiser_metric_mensuel;
ALTER TABLE public.metrics_mensuels DISABLE TRIGGER controler_metric_mensuel;
INSERT INTO public.metrics_mensuels (metric_key, mois, value, updated_at)
SELECT DISTINCT ON (h.metric_key, h.period_start)
       h.metric_key, h.period_start, h.value, h.recorded_at
  FROM public.metrics_history h
  JOIN public.metrics m ON m.key = h.metric_key
 WHERE h.period_start = date_trunc('month', h.period_start)::date
   AND h.period_end = (h.period_start + interval '1 month' - interval '1 day')::date
   AND h.period_start <= private.dernier_mois_termine()
   AND (NOT m.comptage OR h.value = trunc(h.value))
 ORDER BY h.metric_key, h.period_start, h.recorded_at DESC,
          (h.value = m.value AND h.period_start = m.period_start) DESC, h.id;
ALTER TABLE public.metrics_mensuels ENABLE TRIGGER controler_metric_mensuel;
ALTER TABLE public.metrics_mensuels ENABLE TRIGGER historiser_metric_mensuel;

-- ---------- Vue du mois affiché ----------
-- evolution : favorable (vert), defavorable (rouge), stable (gris, écart nul),
-- nc (gris, pas de valeur le mois précédent), NULL (pas de valeur ce mois-ci).
CREATE OR REPLACE VIEW public.indicateurs_du_mois
WITH (security_invoker = true) AS
SELECT m.key,
    m.label,
    m.unit,
    m.comptage,
    m.sens_favorable,
    m.afficher_dashboard,
    m.ordre_dashboard,
    r.mois_reference AS mois,
    cur.value,
    cur.updated_at,
    (r.mois_reference - interval '1 month')::date AS mois_precedent,
    prev.value AS valeur_precedente,
    cur.value - prev.value AS ecart,
    CASE
        WHEN cur.value IS NULL THEN NULL
        WHEN prev.value IS NULL THEN 'nc'
        WHEN cur.value = prev.value THEN 'stable'
        WHEN (cur.value > prev.value) = (m.sens_favorable = 'hausse') THEN 'favorable'
        ELSE 'defavorable'
    END AS evolution
FROM public.metrics m
CROSS JOIN public.indicateurs_reglages r
LEFT JOIN public.metrics_mensuels cur
       ON cur.metric_key = m.key AND cur.mois = r.mois_reference
LEFT JOIN public.metrics_mensuels prev
       ON prev.metric_key = m.key AND prev.mois = (r.mois_reference - interval '1 month')::date;
GRANT SELECT ON public.indicateurs_du_mois TO authenticated;

COMMIT;

-- ============================================================
-- Tests de fumée
-- ============================================================
BEGIN;

-- F4 : la saisie sans période n'existe plus (la période est le mois de la
-- valeur mensuelle) ; les autres contrôles de F4 restent.
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
    SELECT count(*) INTO _cnt FROM metrics
     WHERE key IN ('training_kpi', 'active_users', 'nps', 'engagement', 'turnover',
                   'absenteeism', 'open_positions', 'training_hours');
    _res := _res || jsonb_build_object('t', 'F4 : plus aucune ancienne clé d''indicateur (C3)',
      'ok', _cnt = 0, 'd', _cnt::text || ' ancienne(s) clé(s)');

    BEGIN
      INSERT INTO metrics(key, label, value, unit, period_start, period_end)
        VALUES ('zz_f4_periode_inversee', 'ZZ période inversée', 1, NULL, '2026-10-31', '2026-10-01');
      _res := _res || jsonb_build_object('t', 'F4 : une période qui finit avant de commencer est refusée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F4 : une période qui finit avant de commencer est refusée', 'ok', true, 'd', 'refusé par la base');
    END;

    BEGIN
      INSERT INTO metrics(key, label, value, unit, period_start, period_end, comptage)
        VALUES ('zz_f4_comptage', 'ZZ comptage', 34.2, NULL, '2026-10-01', '2026-10-31', true);
      _res := _res || jsonb_build_object('t', 'F4 : un comptage avec une décimale est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F4 : un comptage avec une décimale est refusé', 'ok', true, 'd', 'refusé par la base');
    END;

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

CREATE OR REPLACE FUNCTION private.run_f4_mois_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _m date := private.dernier_mois_termine();
  _p date := (private.dernier_mois_termine() - interval '1 month')::date;
  _v record;
  _cnt int;
BEGIN
  BEGIN
    UPDATE indicateurs_reglages SET mois_reference = _m;

    INSERT INTO metrics(key, label, unit, comptage, sens_favorable)
    VALUES ('zz_m_hausse', 'ZZ hausse', '%', false, 'hausse'),
           ('zz_m_delai', 'ZZ délai', 'j', false, 'baisse'),
           ('zz_m_stable', 'ZZ stable', NULL, true, 'hausse'),
           ('zz_m_nc', 'ZZ sans mois précédent', NULL, true, 'hausse'),
           ('zz_m_vide', 'ZZ sans valeur', NULL, true, 'hausse');
    _res := _res || jsonb_build_object('t', 'Mois de référence : un indicateur se crée sans valeur ni période',
      'ok', true, 'd', '5 indicateurs créés');

    INSERT INTO metrics_mensuels(metric_key, mois, value) VALUES
      ('zz_m_hausse', _p, 38.6), ('zz_m_hausse', _m, 40.6),
      ('zz_m_delai', _p, 31), ('zz_m_delai', _m, 33),
      ('zz_m_stable', _p, 40), ('zz_m_stable', _m, 40),
      ('zz_m_nc', _m, 12);

    SELECT * INTO _v FROM indicateurs_du_mois WHERE key = 'zz_m_hausse';
    _res := _res || jsonb_build_object('t', 'Mois de référence : valeur du mois, mois précédent et écart',
      'ok', _v.mois = _m AND _v.mois_precedent = _p AND _v.value = 40.6
            AND _v.valeur_precedente = 38.6 AND _v.ecart = 2.0 AND _v.evolution = 'favorable',
      'd', coalesce(_v.mois::text || ' : ' || _v.value::text || ' / ' || _v.ecart::text || ' / ' || _v.evolution, 'aucune ligne'));

    SELECT * INTO _v FROM indicateurs_du_mois WHERE key = 'zz_m_delai';
    _res := _res || jsonb_build_object('t', 'Mois de référence : un délai qui monte est défavorable (rouge)',
      'ok', _v.ecart = 2 AND _v.evolution = 'defavorable', 'd', coalesce(_v.evolution, 'aucune'));

    SELECT * INTO _v FROM indicateurs_du_mois WHERE key = 'zz_m_stable';
    _res := _res || jsonb_build_object('t', 'Mois de référence : un écart nul est stable (gris)',
      'ok', _v.ecart = 0 AND _v.evolution = 'stable', 'd', coalesce(_v.evolution, 'aucune'));

    SELECT * INTO _v FROM indicateurs_du_mois WHERE key = 'zz_m_nc';
    _res := _res || jsonb_build_object('t', 'Mois de référence : sans valeur le mois précédent, évolution N.C.',
      'ok', _v.value = 12 AND _v.valeur_precedente IS NULL AND _v.ecart IS NULL AND _v.evolution = 'nc',
      'd', coalesce(_v.evolution, 'aucune'));

    SELECT * INTO _v FROM indicateurs_du_mois WHERE key = 'zz_m_vide';
    _res := _res || jsonb_build_object('t', 'Mois de référence : sans valeur ce mois-ci, la carte n''a ni valeur ni évolution',
      'ok', _v.value IS NULL AND _v.evolution IS NULL, 'd', coalesce(_v.evolution, 'aucune'));

    BEGIN
      INSERT INTO metrics_mensuels(metric_key, mois, value)
        VALUES ('zz_m_vide', date_trunc('month', now() AT TIME ZONE 'Europe/Paris')::date, 1);
      _res := _res || jsonb_build_object('t', 'Mois de référence : une valeur du mois en cours est refusée', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Mois de référence : une valeur du mois en cours est refusée', 'ok', true, 'd', 'refusée par la base');
    END;

    BEGIN
      INSERT INTO metrics_mensuels(metric_key, mois, value) VALUES ('zz_m_vide', _p + 14, 1);
      _res := _res || jsonb_build_object('t', 'Mois de référence : une valeur porte sur un mois entier (1er du mois)', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Mois de référence : une valeur porte sur un mois entier (1er du mois)', 'ok', true, 'd', 'refusée par la base');
    END;

    BEGIN
      INSERT INTO metrics_mensuels(metric_key, mois, value) VALUES ('zz_m_vide', _p, 3.5);
      _res := _res || jsonb_build_object('t', 'Mois de référence : un comptage décimal est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Mois de référence : un comptage décimal est refusé', 'ok', true, 'd', 'refusé par la base');
    END;

    BEGIN
      UPDATE indicateurs_reglages
         SET mois_reference = date_trunc('month', now() AT TIME ZONE 'Europe/Paris')::date;
      _res := _res || jsonb_build_object('t', 'Mois de référence : le mois en cours ne peut pas être affiché', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'Mois de référence : le mois en cours ne peut pas être affiché', 'ok', true, 'd', 'refusé par la base');
    END;

    BEGIN
      INSERT INTO indicateurs_reglages(id, mois_reference) VALUES (false, _p);
      _res := _res || jsonb_build_object('t', 'Mois de référence : un seul mois affiché pour tous les indicateurs', 'ok', false, 'd', 'deuxième ligne acceptée');
    EXCEPTION WHEN check_violation OR unique_violation THEN
      _res := _res || jsonb_build_object('t', 'Mois de référence : un seul mois affiché pour tous les indicateurs', 'ok', true, 'd', 'refusé par la base');
    END;

    -- L'admin repasse au mois précédent : toutes les cartes suivent.
    UPDATE indicateurs_reglages SET mois_reference = _p;
    SELECT * INTO _v FROM indicateurs_du_mois WHERE key = 'zz_m_hausse';
    _res := _res || jsonb_build_object('t', 'Mois de référence : changer le mois change toutes les cartes',
      'ok', _v.mois = _p AND _v.value = 38.6 AND _v.evolution = 'nc',
      'd', coalesce(_v.mois::text || ' : ' || _v.value::text, 'aucune ligne'));

    UPDATE metrics_mensuels SET value = 39 WHERE metric_key = 'zz_m_hausse' AND mois = _p;
    SELECT count(*) INTO _cnt FROM metrics_history
     WHERE metric_key = 'zz_m_hausse' AND period_start IS NOT NULL;
    _res := _res || jsonb_build_object('t', 'Mois de référence : chaque saisie mensuelle est historisée avec son mois',
      'ok', _cnt = 3, 'd', _cnt::text || ' ligne(s)');

    UPDATE metrics SET key = 'zz_m_hausse_2' WHERE key = 'zz_m_hausse';
    SELECT count(*) INTO _cnt FROM metrics_mensuels WHERE metric_key = 'zz_m_hausse_2';
    _res := _res || jsonb_build_object('t', 'Mois de référence : renommer la clé garde les valeurs mensuelles',
      'ok', _cnt = 2, 'd', _cnt::text || ' valeur(s)');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée du mois de référence', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_f4_mois_smoke_tests() FROM public, anon, authenticated;

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
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

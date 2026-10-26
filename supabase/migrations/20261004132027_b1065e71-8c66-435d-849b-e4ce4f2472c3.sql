CREATE TABLE public.metrics_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_key text NOT NULL,
  value numeric NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX metrics_history_key_time ON public.metrics_history (metric_key, recorded_at DESC);
GRANT SELECT ON public.metrics_history TO authenticated;
GRANT ALL ON public.metrics_history TO service_role;
ALTER TABLE public.metrics_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allowed read metrics history" ON public.metrics_history
FOR SELECT TO authenticated USING (private.is_allowed());

INSERT INTO public.metrics_history (metric_key, value, recorded_at)
SELECT key, value, updated_at FROM public.metrics;

CREATE OR REPLACE FUNCTION private.record_metric_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.key <> OLD.key THEN
    UPDATE public.metrics_history SET metric_key = NEW.key WHERE metric_key = OLD.key;
  END IF;
  IF TG_OP = 'INSERT' OR NEW.value IS DISTINCT FROM OLD.value THEN
    INSERT INTO public.metrics_history (metric_key, value) VALUES (NEW.key, NEW.value);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER record_metric_history AFTER INSERT OR UPDATE ON public.metrics
FOR EACH ROW EXECUTE FUNCTION private.record_metric_history();

CREATE OR REPLACE FUNCTION private.delete_metric_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  DELETE FROM public.metrics_history WHERE metric_key = OLD.key;
  RETURN OLD;
END $$;
CREATE TRIGGER delete_metric_history AFTER DELETE ON public.metrics
FOR EACH ROW EXECUTE FUNCTION private.delete_metric_history();

ALTER TABLE public.metrics DROP COLUMN delta;

CREATE VIEW public.metrics_with_trend WITH (security_invoker = true) AS
SELECT m.key, m.label, m.value, m.unit, m.updated_at,
  p.value AS previous_value,
  CASE WHEN p.value IS NULL OR p.value = m.value THEN 'stable'
       WHEN m.value > p.value THEN 'hausse' ELSE 'baisse' END AS trend
FROM public.metrics m
LEFT JOIN LATERAL (
  SELECT h.value FROM public.metrics_history h
  WHERE h.metric_key = m.key
  ORDER BY h.recorded_at DESC OFFSET 1 LIMIT 1
) p ON true;
GRANT SELECT ON public.metrics_with_trend TO authenticated;
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
    CASE WHEN p.value IS NULL THEN NULL ELSE m.value - p.value END AS delta
FROM public.metrics m
LEFT JOIN LATERAL (
    SELECT h.value
    FROM public.metrics_history h
    WHERE h.metric_key = m.key
    ORDER BY h.recorded_at DESC
    OFFSET 1
    LIMIT 1
) p ON true;
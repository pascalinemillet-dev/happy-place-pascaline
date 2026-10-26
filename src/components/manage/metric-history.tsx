import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { fetchMetricHistory, formatMetricValue } from "@/lib/dashboard";

const fmt = new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short" });

export function MetricHistory({ metricKey, unit }: { metricKey: string; unit: string | null }) {
  const [open, setOpen] = useState(false);
  const q = useQuery({
    queryKey: ["metrics", "history", metricKey],
    queryFn: () => fetchMetricHistory(metricKey),
    enabled: open,
  });
  return (
    <div className="mt-xs">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="text-[11px] font-label-sm uppercase text-on-surface-variant underline"
      >
        {open ? "▾" : "▸"} Historique
      </button>
      {open && (
        <div className="mt-xs border-l border-outline-variant pl-sm space-y-xs">
          {q.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
          {q.isError && <p className="text-body-sm text-error">Impossible de charger l'historique.</p>}
          {q.data?.length === 0 && (
            <p className="text-body-sm italic text-on-surface-variant">Aucune valeur enregistrée.</p>
          )}
          {q.data?.map((h) => (
            <p key={h.id} className="text-body-sm text-on-surface-variant">
              <span className="font-bold text-primary">{fmt.format(new Date(h.recorded_at))}</span>
              {" — "}
              {formatMetricValue(h.value, unit)}
            </p>
          ))}
        </div>
      )}
    </div>
  );
}

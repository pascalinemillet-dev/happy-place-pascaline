import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { dateFr, fetchValeursMensuelles, formatMetricValue, moisText } from "@/lib/dashboard";

/** Valeurs mensuelles d'un indicateur (F4 révisée), du mois le plus récent au plus ancien. */
export function MetricHistory({
  metricKey,
  unit,
  comptage = false,
}: {
  metricKey: string;
  unit: string | null;
  comptage?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const q = useQuery({
    queryKey: ["metrics", "mensuels", metricKey],
    queryFn: () => fetchValeursMensuelles(metricKey),
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
        {open ? "▾" : "▸"} Valeurs par mois
      </button>
      {open && (
        <div className="mt-xs border-l border-outline-variant pl-sm space-y-xs">
          {q.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
          {q.isError && <p className="text-body-sm text-error">Impossible de charger les valeurs.</p>}
          {q.data?.length === 0 && (
            <p className="text-body-sm italic text-on-surface-variant">Aucune valeur mensuelle.</p>
          )}
          {q.data?.map((v) => (
            <p key={v.mois} className="text-body-sm text-on-surface-variant">
              <span className="font-bold text-primary">{moisText(v.mois)}</span>
              {" — "}
              {formatMetricValue(v.value, unit, comptage)}
              {" · saisi le "}
              {dateFr(v.updated_at)}
            </p>
          ))}
        </div>
      )}
    </div>
  );
}

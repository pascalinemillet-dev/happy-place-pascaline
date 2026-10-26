import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { fetchSubmissionHistory } from "@/lib/dashboard";

const fmt = new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short" });

export function SubmissionHistory({ submissionId }: { submissionId: string }) {
  const [open, setOpen] = useState(false);
  const q = useQuery({
    queryKey: ["submissions", "history", submissionId],
    queryFn: () => fetchSubmissionHistory(submissionId),
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
            <p className="text-body-sm italic text-on-surface-variant">Aucun changement enregistré.</p>
          )}
          {q.data?.map((h) => (
            <div key={h.id} className="text-body-sm">
              <p className="text-on-surface-variant">
                <span className="font-bold text-primary">{fmt.format(new Date(h.changed_at))}</span>
                {" — "}
                {h.old_status ?? "Création"} → {h.new_status}
                {" — "}
                {h.is_automatic ? "Automatique" : (h.changed_by_name ?? h.changed_by_email ?? "—")}
              </p>
              {h.new_status === "refusée" && h.rejection_category && (
                <p className="text-error">
                  Motif : {h.rejection_category}
                  {h.rejection_note ? ` — ${h.rejection_note}` : ""}
                </p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

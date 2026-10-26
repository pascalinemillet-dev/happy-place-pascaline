import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import {
  downloadAttachment,
  downloadDepartureZip,
  fetchMyDepartureNotices,
  markDepartureNoticeDownloaded,
  type DepartureNotice,
} from "@/lib/dashboard";

const frDate = (iso: string) => new Intl.DateTimeFormat("fr-FR").format(new Date(iso));
const frDay = (ymd: string) => ymd.split("-").reverse().join("/");

export function DepartureNotices({ email }: { email: string }) {
  const q = useQuery({
    queryKey: ["departure_notices", email.toLowerCase()],
    queryFn: () => fetchMyDepartureNotices(email),
  });
  if (!q.data?.length) return null;
  return (
    <div className="space-y-xs">
      {q.data.map((n) => (
        <NoticeBanner key={n.id} notice={n} email={email} />
      ))}
    </div>
  );
}

function NoticeBanner({ notice: n, email }: { notice: DepartureNotice; email: string }) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [zipping, setZipping] = useState(false);
  const count = n.documents.length;
  const reminder = !!n.reminder_at;
  const deleteOn = new Date(new Date(n.created_at).getTime() + 7 * 86400000).toISOString();
  const text =
    count === 0
      ? n.kind === "préavis"
        ? `${n.departing_label} quitte Happy Place le ${frDay(n.departure_date)}. Aucun document à télécharger.`
        : `${n.departing_label} a quitté Happy Place. Aucun document à télécharger.`
      : n.kind === "préavis"
        ? `${n.departing_label} quitte Happy Place le ${frDay(n.departure_date)} : ${count} document(s) joint(s) à ses demandes seront alors supprimés.`
        : `${n.departing_label} a quitté Happy Place : ${count} document(s) joint(s) à ses demandes seront supprimés le ${frDate(deleteOn)}`;

  const mark = useMutation({
    mutationFn: () => markDepartureNoticeDownloaded(n.id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["departure_notices", email.toLowerCase()] }),
    onError: (e) => toast.error((e as Error).message),
  });

  async function zipAll() {
    setZipping(true);
    try {
      await downloadDepartureZip(n);
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setZipping(false);
    }
  }

  const btn = "px-sm py-1 border border-outline text-primary font-label-sm text-label-sm hover:bg-surface-container disabled:opacity-50";

  return (
    <div
      role={reminder ? "alert" : "status"}
      className={`p-sm border space-y-xs ${reminder ? "border-error bg-error-container text-on-error-container" : "border-outline-variant bg-surface-container-lowest"}`}
    >
      <p className="font-body-md">
        {reminder && <strong>Rappel : </strong>}
        {text}
      </p>
      <div className="flex flex-wrap gap-xs">
        {count > 0 && (
          <>
            <button type="button" className={btn} onClick={() => setOpen((o) => !o)} aria-expanded={open}>
              {open ? "Masquer les documents" : "Voir les documents"}
            </button>
            <button type="button" className={btn} onClick={zipAll} disabled={zipping}>
              {zipping ? "Préparation…" : "Tout télécharger (.zip)"}
            </button>
          </>
        )}
        <button type="button" className={btn} onClick={() => mark.mutate()} disabled={mark.isPending}>
          {count > 0 ? "J'ai téléchargé les documents" : "J'ai pris note"}
        </button>
      </div>
      {open && (
        <ul className="border-t border-outline-variant pt-xs space-y-xs">
          {n.documents.map((d) => (
            <li key={d.path} className="flex flex-wrap items-center justify-between gap-xs text-body-sm">
              <span>
                <span className="font-bold">{frDate(d.created_at)}</span> — {d.excerpt}
              </span>
              <button
                type="button"
                className="text-primary underline font-label-sm text-label-sm"
                onClick={() => downloadAttachment(d.path, d.name).catch((e) => toast.error((e as Error).message))}
              >
                Télécharger
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

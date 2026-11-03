import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AttachmentLink } from "@/components/attachment-link";
import { SubmissionPreview, formatExactDate } from "@/components/expandable-card";
import { KindTag } from "@/components/submissions/pending-queue";
import { Linkify } from "@/components/linkify";
import { timeAgo, type Submission, type SubmissionKind } from "@/lib/dashboard";
import {
  ADMIN_LABEL,
  KIND_LABELS,
  MY_STATUS_LABELS,
  assigneeLine,
  countMySubmissions,
  fetchAssigneeNames,
  fetchMySubmissionsDetailed,
  type MySubmission,
  type MyStatusFilter,
} from "@/lib/f1";
import { useModuleViewed } from "@/lib/use-module-viewed";
import { ModuleHint, hintId } from "@/components/module-hint";

function statusBadge(s: MySubmission): { label: string; className: string } {
  if (s.status === "refusée")
    return { label: "REFUSÉE", className: "bg-error-container text-on-error-container" };
  // US67 : une idée validée et un point bloquant créé s'affichent tous deux « PUBLIÉE ».
  if (s.status === "validée")
    return { label: "PUBLIÉE", className: "border border-primary text-primary bg-card" };
  return { label: "EN ATTENTE", className: "bg-surface-container-high text-on-surface-variant" };
}

function AssignedTo({ s }: { s: MySubmission }) {
  const names = useQuery({
    queryKey: ["assignees", "author", s.team],
    queryFn: () => fetchAssigneeNames(s.team),
    retry: false,
  });
  if (!names.data) return null;
  return <>Assigné à {assigneeLine(s.kind, names.data) || ADMIN_LABEL}</>;
}

const STATUS_OPTIONS: { value: MyStatusFilter; label: string }[] = [
  { value: "en attente", label: "En attente" },
  { value: "validée", label: "Publiée" },
  { value: "refusée", label: "Refusée" },
  { value: "tous", label: "Tous les statuts" },
];

/** Message quand le filtre ne renvoie rien, accordé au type choisi. */
function emptyMessage(status: MyStatusFilter, kind: "tous" | SubmissionKind): string {
  if (status === "tous") {
    if (kind === "idée") return "Vous n'avez soumis aucune idée.";
    if (kind === "point bloquant") return "Vous n'avez signalé aucun point bloquant.";
    return "Vous n'avez encore rien soumis.";
  }
  if (kind === "point bloquant") {
    const masculin = { "en attente": "en attente", validée: "publié", refusée: "refusé" };
    return `Aucun point bloquant ${masculin[status]}.`;
  }
  const label = MY_STATUS_LABELS[status];
  if (kind === "idée") return `Aucune idée ${label}.`;
  return `Aucune soumission ${label}.`;
}

const selectClass =
  "border border-outline-variant bg-card p-xs font-body-sm normal-case text-on-surface";
const labelClass =
  "flex items-center gap-xs font-label-sm text-label-sm text-on-surface-variant uppercase";

/**
 * Bloc « Mes soumissions » : type, statut, date du dernier changement, statut du point créé (US33).
 * US67 : filtres Statut (en attente par défaut) et Type. Sur la page du collaborateur, ce bloc
 * remplace aussi « Soumissions en attente » et prend sa colonne (`layout="colonne"`).
 * Arriver par un lien `#mes-soumissions` (e-mails US61 et US65) ouvre le filtre sur « Tous les statuts ».
 */
export function MySubmissions({
  email,
  onRead,
  layout = "pleine",
  hideWhenEmpty = false,
}: {
  email: string;
  onRead: (s: Submission) => void;
  layout?: "pleine" | "colonne";
  /** Manager et admin : le bloc reste masqué tant qu'ils n'ont rien soumis. */
  hideWhenEmpty?: boolean;
}) {
  const [status, setStatus] = useState<MyStatusFilter>("en attente");
  const [type, setType] = useState<"tous" | SubmissionKind>("tous");
  const ref = useModuleViewed<HTMLElement>("mes_soumissions");

  // Lien d'un e-mail (refus, publication) : la soumission n'est plus en attente.
  useEffect(() => {
    const open = () => {
      if (window.location.hash === "#mes-soumissions") setStatus("tous");
    };
    open();
    window.addEventListener("hashchange", open);
    return () => window.removeEventListener("hashchange", open);
  }, []);

  const total = useQuery({
    queryKey: ["submissions", "mine", email, "total"],
    queryFn: () => countMySubmissions(email),
    enabled: !!email && hideWhenEmpty,
    retry: false,
  });
  const q = useQuery({
    queryKey: ["submissions", "mine", email, status, type],
    queryFn: () => fetchMySubmissionsDetailed(email, { status, kind: type }),
    enabled: !!email,
    retry: false,
  });
  if (hideWhenEmpty && !total.data) return null;
  const rows = q.data ?? [];
  const column = layout === "colonne";

  return (
    <section
      id="mes-soumissions"
      ref={ref}
      aria-describedby={hintId("mes-soumissions")}
      className={`${
        column ? "col-span-12 lg:col-span-4 flex flex-col" : "col-span-12"
      } min-w-0 bg-surface-container-lowest border border-outline-variant p-md`}
    >
      <div
        className={`flex flex-wrap gap-sm border-b border-outline-variant pb-sm mb-md ${
          column ? "flex-col" : "items-center justify-between"
        }`}
      >
        <div>
          <h2 className="font-headline-sm text-headline-sm text-primary">Mes soumissions</h2>
          <ModuleHint module="mes-soumissions" />
        </div>
        <div className="flex flex-wrap items-center gap-sm">
          <label className={labelClass}>
            Statut
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value as MyStatusFilter)}
              className={selectClass}
            >
              {STATUS_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          </label>
          <label className={labelClass}>
            Type
            <select
              value={type}
              onChange={(e) => setType(e.target.value as "tous" | SubmissionKind)}
              className={selectClass}
            >
              <option value="tous">Tous les types</option>
              <option value="point bloquant">{KIND_LABELS["point bloquant"]}</option>
              <option value="idée">{KIND_LABELS["idée"]}</option>
            </select>
          </label>
        </div>
      </div>
      <div aria-live="polite" className="sr-only">
        {q.data
          ? `${rows.length} soumission${rows.length > 1 ? "s" : ""} affichée${rows.length > 1 ? "s" : ""}`
          : ""}
      </div>
      {q.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
      {q.isError && <p className="text-body-sm text-error">Vos soumissions sont indisponibles.</p>}
      {q.data && rows.length === 0 && (
        <p className="text-body-sm text-on-surface-variant italic">{emptyMessage(status, type)}</p>
      )}
      <div className="space-y-xs">
        {rows.map((s) => {
          const badge = statusBadge(s);
          return (
            <div
              key={s.id}
              className="p-sm border border-outline-variant bg-card min-w-0 overflow-hidden"
            >
              <div className="flex items-start justify-between gap-sm">
                <div className="min-w-0 flex-1 space-y-xs">
                  <KindTag kind={s.kind} />
                  <SubmissionPreview content={s.content} onOpen={() => onRead(s)} />
                  <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
                </div>
                <span
                  className={`shrink-0 px-xs py-0.5 font-label-sm text-label-sm ${badge.className}`}
                >
                  {badge.label}
                </span>
              </div>
              <p className="text-[11px] font-label-sm text-on-surface-variant uppercase mt-xs">
                {s.status === "en attente" ? (
                  <>
                    <AssignedTo s={s} /> · envoyé {timeAgo(s.created_at)}
                  </>
                ) : s.kind === "point bloquant" && s.blocker_status ? (
                  <>
                    Statut du point : {s.blocker_status} · dernier changement le{" "}
                    {formatExactDate(s.last_change_at)}
                  </>
                ) : (
                  <>
                    {MY_STATUS_LABELS[s.status as Exclude<MyStatusFilter, "tous">] ?? s.status} ·{" "}
                    {s.team} · dernier changement le {formatExactDate(s.last_change_at)}
                  </>
                )}
              </p>
              {s.status === "refusée" && s.rejection_category && (
                <div className="mt-xs p-xs bg-error-container text-on-error-container text-body-sm wrap-anywhere">
                  <p className="font-bold">Motif : {s.rejection_category}</p>
                  <p className="whitespace-pre-line">
                    Raison : <Linkify text={s.rejection_note ?? ""} />
                  </p>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}

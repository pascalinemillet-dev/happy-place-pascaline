import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Modal } from "@/components/manage/crud-ui";
import { SubmitModal } from "@/components/submissions/submit-modal";
import { AttachmentLink } from "@/components/attachment-link";
import { SubmissionPreview, formatExactDate } from "@/components/expandable-card";
import { KindTag } from "@/components/submissions/pending-queue";
import { Linkify } from "@/components/linkify";
import { timeAgo, type Submission, type SubmissionKind } from "@/lib/dashboard";
import {
  ADMIN_LABEL,
  KIND_LABELS,
  MY_STATUS_LABELS,
  archiveSubmission,
  assigneeLine,
  fetchAssigneeNames,
  fetchMySubmissionsDetailed,
  type MySubmission,
  type MyStatusFilter,
} from "@/lib/f1";
import { useModuleViewed } from "@/lib/use-module-viewed";
import { ModuleHint, hintId } from "@/components/module-hint";

export function statusBadge(s: Submission): { label: string; className: string } {
  if (s.status === "refusée" && s.archived_at)
    return {
      label: "ARCHIVÉE",
      className: "border border-outline-variant text-on-surface-variant bg-card",
    };
  if (s.status === "refusée")
    return { label: "REFUSÉE", className: "bg-error-container text-on-error-container" };
  // US67 : une idée validée et un point bloquant créé s'affichent tous deux « PUBLIÉE ».
  if (s.status === "validée")
    return { label: "PUBLIÉE", className: "border border-primary text-primary bg-card" };
  return { label: "EN ATTENTE", className: "bg-surface-container-high text-on-surface-variant" };
}

/** Point bloquant publié avec des changements du manager ou de l'admin : le lien avec le point publié. */
export function PublishedChangesNote({ changes }: { changes?: string[] }) {
  if (!changes?.length) return null;
  return (
    <p className="mt-xs inline-block px-xs py-0.5 font-label-sm text-label-sm uppercase bg-tertiary-fixed text-on-tertiary-fixed">
      Publiée avec modification : {changes.join(", ")}
    </p>
  );
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

/** Envoyé par le lien « VOIR MES SOUMISSIONS », même quand l'adresse porte déjà #mes-soumissions. */
export const SHOW_ALL_EVENT = "hp:mes-soumissions";

const STATUS_OPTIONS: { value: MyStatusFilter; label: string }[] = [
  { value: "en attente", label: "En attente" },
  { value: "validée", label: "Publiée" },
  { value: "refusée", label: "Refusée" },
  { value: "archivée", label: "Archivée" },
  { value: "tous", label: "Tous les statuts" },
];

/** Message quand le filtre ne renvoie rien, accordé au type choisi. */
export function emptyMessage(
  status: MyStatusFilter,
  kind: "tous" | SubmissionKind,
  scope: "mine" | "equipes" = "mine",
): string {
  if (status === "tous" && scope === "equipes") {
    if (kind === "idée") return "Aucune idée.";
    if (kind === "point bloquant") return "Aucun point bloquant.";
    return "Aucune soumission.";
  }
  if (status === "tous") {
    if (kind === "idée") return "Vous n'avez soumis aucune idée.";
    if (kind === "point bloquant") return "Vous n'avez signalé aucun point bloquant.";
    return "Vous n'avez encore rien soumis.";
  }
  if (kind === "point bloquant") {
    const masculin = {
      "en attente": "en attente",
      validée: "publié",
      refusée: "refusé",
      archivée: "archivé",
    };
    return `Aucun point bloquant ${masculin[status]}.`;
  }
  const label = status === "archivée" ? "archivée" : MY_STATUS_LABELS[status];
  if (kind === "idée") return `Aucune idée ${label}.`;
  return `Aucune soumission ${label}.`;
}

const selectClass =
  "border border-outline-variant bg-card p-xs font-body-sm normal-case text-on-surface";
const labelClass =
  "flex items-center gap-xs font-label-sm text-label-sm text-on-surface-variant uppercase";

/** Filtres Statut et Type (US67), partagés par « Mes soumissions » et « Soumissions d'équipes » (US70). */
export function SubmissionFilters({
  status,
  onStatus,
  type,
  onType,
}: {
  status: MyStatusFilter;
  onStatus: (s: MyStatusFilter) => void;
  type: "tous" | SubmissionKind;
  onType: (t: "tous" | SubmissionKind) => void;
}) {
  return (
    <div className="flex flex-wrap items-center gap-sm">
      <label className={labelClass}>
        Statut
        <select
          value={status}
          onChange={(e) => onStatus(e.target.value as MyStatusFilter)}
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
          onChange={(e) => onType(e.target.value as "tous" | SubmissionKind)}
          className={selectClass}
        >
          <option value="tous">Tous les types</option>
          <option value="point bloquant">{KIND_LABELS["point bloquant"]}</option>
          <option value="idée">{KIND_LABELS["idée"]}</option>
        </select>
      </label>
    </div>
  );
}

/**
 * Bloc « Mes soumissions » : type, statut, date du dernier changement, statut du point créé (US33).
 * US67 : filtres Statut (en attente par défaut) et Type. Sur la page du collaborateur, ce bloc
 * remplace aussi « Soumissions en attente » et prend sa colonne (`layout="colonne"`).
 * Arriver par un lien `#mes-soumissions` (e-mails US61 et US65) ouvre le filtre sur « Tous les statuts ».
 */
export function MySubmissions({
  role,
  email,
  onRead,
  layout = "pleine",
  embedded = false,
}: {
  role: string;
  email: string;
  onRead: (s: Submission) => void;
  layout?: "pleine" | "colonne";
  /** US70 : vue « Mes soumissions » du bloc unique du manager et de l'admin, sans titre propre. */
  embedded?: boolean;
}) {
  const [status, setStatus] = useState<MyStatusFilter>("en attente");
  const [type, setType] = useState<"tous" | SubmissionKind>("tous");
  const [editing, setEditing] = useState<MySubmission | null>(null);
  const [archiving, setArchiving] = useState<MySubmission | null>(null);
  const ref = useModuleViewed<HTMLDivElement>("mes_soumissions");
  const qc = useQueryClient();

  // US68 : archiver une soumission refusée (elle reste lisible dans « Archivée »).
  const archive = useMutation({
    mutationFn: (s: MySubmission) => archiveSubmission(s.id),
    onSuccess: () => {
      setArchiving(null);
      toast.success("Soumission archivée");
      qc.invalidateQueries({ queryKey: ["submissions"] });
    },
    onError: (e: unknown) => toast.error((e as Error).message),
  });

  // Lien d'un e-mail (refus, publication) ou « VOIR MES SOUMISSIONS » après un envoi :
  // tous les statuts et tous les types, pour que la soumission visée soit à l'écran.
  useEffect(() => {
    const showAll = () => {
      setStatus("tous");
      setType("tous");
    };
    const onHash = () => {
      if (window.location.hash === "#mes-soumissions") showAll();
    };
    onHash();
    window.addEventListener("hashchange", onHash);
    window.addEventListener(SHOW_ALL_EVENT, showAll);
    return () => {
      window.removeEventListener("hashchange", onHash);
      window.removeEventListener(SHOW_ALL_EVENT, showAll);
    };
  }, []);

  const q = useQuery({
    queryKey: ["submissions", "mine", email, status, type],
    queryFn: () => fetchMySubmissionsDetailed(email, { status, kind: type }),
    enabled: !!email,
    retry: false,
  });
  const rows = q.data ?? [];
  const column = layout === "colonne";

  const body = (
    <>
      <div
        className={`flex flex-wrap gap-sm border-b border-outline-variant pb-sm mb-md ${
          column || embedded ? "flex-col" : "items-center justify-between"
        }`}
      >
        {!embedded && (
          <div>
            <h2 className="font-headline-sm text-headline-sm text-primary">Mes soumissions</h2>
            <ModuleHint module="mes-soumissions" />
          </div>
        )}
        <SubmissionFilters status={status} onStatus={setStatus} type={type} onType={setType} />
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
                    <AssignedTo s={s} /> · {s.resubmission_count ? "renvoyé" : "envoyé"}{" "}
                    {timeAgo(s.created_at)}
                  </>
                ) : s.kind === "point bloquant" && s.blocker_status ? (
                  <>
                    Statut du point : {s.blocker_status} · dernier changement le{" "}
                    {formatExactDate(s.last_change_at)}
                  </>
                ) : (
                  <>
                    {MY_STATUS_LABELS[s.status as Exclude<MyStatusFilter, "tous" | "archivée">] ??
                      s.status}{" "}
                    · {s.team} · dernier changement le {formatExactDate(s.last_change_at)}
                  </>
                )}
              </p>
              {s.status === "validée" && <PublishedChangesNote changes={s.published_changes} />}
              {s.status === "refusée" && s.rejection_category && (
                <div className="mt-xs p-xs bg-error-container text-on-error-container text-body-sm wrap-anywhere">
                  <p className="font-bold">Motif : {s.rejection_category}</p>
                  <p className="whitespace-pre-line">
                    Raison : <Linkify text={s.rejection_note ?? ""} />
                  </p>
                </div>
              )}
              {s.status === "refusée" && !s.archived_at && (
                <div className="flex flex-wrap gap-xs mt-xs">
                  <button
                    type="button"
                    aria-haspopup="dialog"
                    onClick={() => setEditing(s)}
                    className="px-sm py-1 bg-primary text-on-primary font-label-sm text-label-sm hover:opacity-90"
                  >
                    MODIFIER ET RENVOYER
                  </button>
                  <button
                    type="button"
                    aria-haspopup="dialog"
                    onClick={() => setArchiving(s)}
                    className="px-sm py-1 border border-outline text-primary font-label-sm text-label-sm hover:bg-surface-container"
                  >
                    ARCHIVER
                  </button>
                </div>
              )}
              {s.archived_at && (
                <p className="text-[11px] font-label-sm text-on-surface-variant uppercase mt-xs">
                  Archivée le {formatExactDate(s.archived_at)}
                </p>
              )}
            </div>
          );
        })}
      </div>
      {editing && (
        <SubmitModal
          role={role}
          email={email}
          managerTeams={[]}
          resubmit={editing}
          onClose={() => setEditing(null)}
          onSent={(sent) => {
            setEditing(null);
            setStatus("en attente");
            toast.success(
              `${sent.kind === "point bloquant" ? "Point bloquant renvoyé" : "Idée renvoyée"}${
                sent.assignedTo ? ` à ${sent.assignedTo}` : ""
              }.`,
            );
          }}
        />
      )}
      {archiving && (
        <Modal title="Archiver la soumission" onClose={() => setArchiving(null)}>
          <p className="font-body-md text-on-surface">
            Archiver cette soumission refusée ? Elle ne pourra plus être renvoyée. Vous la
            retrouverez avec le filtre « Archivée ».
          </p>
          <div className="flex justify-end gap-xs pt-sm">
            <button
              type="button"
              onClick={() => setArchiving(null)}
              className="px-md py-xs border border-outline text-primary font-label-md text-label-md hover:bg-surface-container"
            >
              ANNULER
            </button>
            <button
              type="button"
              disabled={archive.isPending}
              onClick={() => archive.mutate(archiving)}
              className="px-lg py-xs bg-primary text-on-primary font-label-md text-label-md disabled:opacity-50"
            >
              {archive.isPending ? "…" : "ARCHIVER"}
            </button>
          </div>
        </Modal>
      )}
    </>
  );

  if (embedded) return <div ref={ref}>{body}</div>;
  return (
    <section
      id="mes-soumissions"
      ref={ref}
      aria-describedby={hintId("mes-soumissions")}
      className={`${
        column ? "col-span-12 lg:col-span-6 flex flex-col" : "col-span-12"
      } min-w-0 bg-surface-container-lowest border border-outline-variant p-md`}
    >
      {body}
    </section>
  );
}

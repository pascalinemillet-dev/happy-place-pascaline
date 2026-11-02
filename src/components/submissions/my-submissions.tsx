import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AttachmentLink } from "@/components/attachment-link";
import { SubmissionPreview, formatExactDate } from "@/components/expandable-card";
import { KindTag } from "@/components/submissions/pending-queue";
import { Linkify } from "@/components/linkify";
import { timeAgo, type Submission, type SubmissionKind } from "@/lib/dashboard";
import {
  ADMIN_LABEL,
  KIND_LABELS,
  assigneeLine,
  fetchAssigneeNames,
  fetchMySubmissionsDetailed,
  type MySubmission,
} from "@/lib/f1";
import { useModuleViewed } from "@/lib/use-module-viewed";

function statusBadge(s: MySubmission): { label: string; className: string } {
  if (s.status === "refusée")
    return { label: "REFUSÉE", className: "bg-error-container text-on-error-container" };
  if (s.status === "validée") {
    return s.kind === "point bloquant"
      ? { label: "POINT BLOQUANT CRÉÉ", className: "bg-primary text-on-primary" }
      : { label: "VALIDÉE", className: "border border-primary text-primary bg-card" };
  }
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

/** Bloc « Mes soumissions » : type, statut, date du dernier changement, statut du point créé (US33). */
export function MySubmissions({
  email,
  onRead,
}: {
  email: string;
  onRead: (s: Submission) => void;
}) {
  const [type, setType] = useState<"tous" | SubmissionKind>("tous");
  const ref = useModuleViewed<HTMLElement>("mes_soumissions");
  const q = useQuery({
    queryKey: ["submissions", "mine", email],
    queryFn: () => fetchMySubmissionsDetailed(email),
    enabled: !!email,
    retry: false,
  });
  if (!q.data || q.data.length === 0) return null;
  const rows = q.data.filter((s) => type === "tous" || s.kind === type);

  return (
    <section
      id="mes-soumissions"
      ref={ref}
      className="col-span-12 min-w-0 bg-surface-container-lowest border border-outline-variant p-md"
    >
      <div className="flex flex-wrap items-center justify-between gap-sm border-b border-outline-variant pb-sm mb-md">
        <h2 className="font-headline-sm text-headline-sm text-primary">Mes soumissions</h2>
        <label className="flex items-center gap-xs font-label-sm text-label-sm text-on-surface-variant uppercase">
          Type
          <select
            value={type}
            onChange={(e) => setType(e.target.value as "tous" | SubmissionKind)}
            className="border border-outline-variant bg-card p-xs font-body-sm normal-case text-on-surface"
          >
            <option value="tous">Tous les types</option>
            <option value="idée">{KIND_LABELS["idée"]}</option>
            <option value="point bloquant">{KIND_LABELS["point bloquant"]}</option>
          </select>
        </label>
      </div>
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
                    {s.status} · {s.team} · dernier changement le{" "}
                    {formatExactDate(s.last_change_at)}
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

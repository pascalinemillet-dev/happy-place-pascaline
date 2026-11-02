import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { AttachmentLink } from "@/components/attachment-link";
import { SubmissionPreview, rejectionErrorMessage } from "@/components/expandable-card";
import { SubmissionReader } from "@/components/submission-reader";
import { RejectModal } from "@/components/submissions/reject-modal";
import {
  SEVERITY_LABELS,
  fetchSubmissions,
  reviewSubmission,
  timeAgo,
  type BlockerSeverity,
  type Submission,
} from "@/lib/dashboard";
import {
  ADMIN_LABEL,
  KIND_LABELS,
  adminQueue,
  countByKind,
  fetchAssigneeNames,
  fetchTeamNames,
  fetchTeamsWithManager,
  publishBlocker,
  sortQueue,
  trackEvent,
  type QueueFilter,
} from "@/lib/f1";
import { suggestBlockerTitle } from "@/lib/ai.functions";
import { isLate } from "@/lib/recap";

const FILTERS: { value: QueueFilter; label: string }[] = [
  { value: "tous", label: "TOUS" },
  { value: "point bloquant", label: "POINTS BLOQUANTS" },
  { value: "idée", label: "IDÉES" },
];

/** Tag de type : en texte et en couleur, jamais la couleur seule (US63). */
export function KindTag({ kind }: { kind: Submission["kind"] }) {
  return (
    <span
      className={`inline-block px-xs py-0.5 font-label-sm text-label-sm uppercase ${
        kind === "point bloquant"
          ? "bg-tertiary-fixed text-on-tertiary-fixed"
          : "bg-surface-container-high text-on-surface-variant"
      }`}
    >
      {KIND_LABELS[kind]}
    </span>
  );
}

/**
 * Soumissions en attente (US63) : points bloquants en tête, compteur par type, filtre par type.
 * - mode « manager » : ce que la base laisse lire (équipes du manager ; admin : tout) ;
 * - mode « admin » : file de l'admin, option A (points bloquants + idées des équipes sans manager).
 */
export function PendingQueue({
  role,
  mode,
  onPrepareRecap,
}: {
  role: string;
  mode: "manager" | "admin";
  onPrepareRecap?: () => void;
}) {
  const qc = useQueryClient();
  const canReview = role === "admin" || role === "manager";
  const [filter, setFilter] = useState<QueueFilter>("tous");
  const [reading, setReading] = useState<Submission | null>(null);
  const [rejecting, setRejecting] = useState<Submission | null>(null);

  const pending = useQuery({ queryKey: ["submissions"], queryFn: fetchSubmissions, retry: false });
  const withManager = useQuery({
    queryKey: ["manager_teams", "all"],
    queryFn: fetchTeamsWithManager,
    enabled: mode === "admin",
    retry: false,
  });
  const teams = useQuery({
    queryKey: ["teams", "names"],
    queryFn: fetchTeamNames,
    enabled: canReview,
    retry: false,
  });

  const scoped = useMemo(() => {
    const all = pending.data ?? [];
    return mode === "admin" ? adminQueue(all, withManager.data ?? new Set()) : all;
  }, [pending.data, withManager.data, mode]);
  const counts = countByKind(scoped);
  const shown = sortQueue(scoped).filter((s) => filter === "tous" || s.kind === filter);

  const review = useMutation({
    mutationFn: reviewSubmission,
    onSuccess: (_d, vars) => {
      if (vars.status === "refusée") {
        setRejecting(null);
        toast.success("Soumission refusée");
      } else {
        setReading((r) => (r?.id === vars.id ? null : r));
      }
      qc.invalidateQueries({ queryKey: ["submissions"] });
    },
    onError: (e: unknown) => toast.error(rejectionErrorMessage(e)),
  });

  const heading = (
    <div className="flex flex-wrap items-center justify-between gap-xs border-b border-outline-variant pb-sm mb-md">
      <h2 className="font-headline-sm text-headline-sm text-primary">Soumissions en attente</h2>
      <p
        className="font-label-sm text-label-sm text-on-surface-variant uppercase"
        aria-live="polite"
      >
        {counts.blockers} point{counts.blockers > 1 ? "s" : ""} bloquant
        {counts.blockers > 1 ? "s" : ""} · {counts.ideas} idée{counts.ideas > 1 ? "s" : ""}
      </p>
    </div>
  );

  return (
    <>
      {heading}
      {onPrepareRecap && (
        <button
          type="button"
          onClick={onPrepareRecap}
          className="mb-sm w-full border border-outline bg-surface px-sm py-xs font-label-md text-label-md text-primary hover:bg-surface-container"
        >
          PRÉPARER MON POINT D'ÉQUIPE
        </button>
      )}
      <div role="group" aria-label="Filtrer par type" className="mb-sm flex flex-wrap gap-xs">
        {FILTERS.map((f) => (
          <button
            key={f.value}
            type="button"
            aria-pressed={filter === f.value}
            onClick={() => setFilter(f.value)}
            className={`px-sm py-0.5 border font-label-sm text-label-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-primary ${
              filter === f.value
                ? "bg-primary text-on-primary border-primary"
                : "border-outline-variant text-on-surface-variant hover:bg-surface-container"
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="space-y-sm flex-grow min-w-0">
        {pending.isError && (
          <p className="text-body-sm text-error">Les soumissions sont indisponibles.</p>
        )}
        {pending.data && shown.length === 0 && (
          <p className="text-body-sm text-on-surface-variant italic">
            Aucune soumission en attente.
          </p>
        )}
        {shown.map((s) =>
          s.kind === "point bloquant" ? (
            <BlockerCard
              key={s.id}
              s={s}
              canReview={canReview}
              teams={teams.data ?? []}
              onRead={() => setReading(s)}
              onReject={() => setRejecting(s)}
            />
          ) : (
            <IdeaCard
              key={s.id}
              s={s}
              canReview={canReview}
              approving={review.isPending}
              onRead={() => setReading(s)}
              onReject={() => setRejecting(s)}
              onApprove={() => review.mutate({ id: s.id, status: "validée" })}
            />
          ),
        )}
      </div>

      <SubmissionReader
        submission={reading}
        onClose={() => setReading(null)}
        onReject={
          reading && canReview && reading.kind === "idée"
            ? () => {
                setRejecting(reading);
                setReading(null);
              }
            : undefined
        }
        onApprove={
          reading && canReview && reading.kind === "idée"
            ? () => review.mutate({ id: reading.id, status: "validée" })
            : undefined
        }
        approving={review.isPending}
      />
      {rejecting && (
        <RejectModal
          submission={rejecting}
          pending={review.isPending}
          onCancel={() => setRejecting(null)}
          onConfirm={(values) => {
            if (rejecting.kind === "point bloquant") {
              trackEvent("blocker_report_qualified", "soumissions", {
                outcome: "refusé",
                clicks: 2,
              });
            }
            review.mutate({ id: rejecting.id, status: "refusée", ...values });
          }}
        />
      )}
    </>
  );
}

function CardHead({ s }: { s: Submission }) {
  return (
    <div className="flex items-start justify-between gap-sm">
      <div className="min-w-0 space-y-1">
        <KindTag kind={s.kind} />
        <p className="font-body-sm text-primary font-bold wrap-anywhere">{s.author_name}</p>
        <p className="text-[10px] text-on-surface-variant font-label-sm wrap-anywhere">{s.team}</p>
      </div>
      <span className="text-[10px] text-on-surface-variant font-label-sm whitespace-nowrap">
        {timeAgo(s.created_at)}
      </span>
    </div>
  );
}

function IdeaCard({
  s,
  canReview,
  approving,
  onRead,
  onReject,
  onApprove,
}: {
  s: Submission;
  canReview: boolean;
  approving: boolean;
  onRead: () => void;
  onReject: () => void;
  onApprove: () => void;
}) {
  return (
    <div className="p-sm border border-outline-variant bg-card space-y-sm min-w-0 overflow-hidden">
      <CardHead s={s} />
      <SubmissionPreview content={s.content} onOpen={onRead} />
      <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
      {isLate(s.created_at) && (
        <p className="font-label-sm text-label-sm bg-tertiary-fixed text-on-tertiary-fixed inline-block px-xs">
          EN ATTENTE DEPUIS PLUS DE 5 JOURS OUVRÉS
        </p>
      )}
      {canReview && (
        <div className="flex gap-xs pt-xs">
          <button
            type="button"
            onClick={onReject}
            className="flex-1 py-1 border border-outline text-primary font-label-sm text-label-sm hover:bg-surface-container transition-colors"
          >
            REFUSER
          </button>
          <button
            type="button"
            disabled={approving}
            onClick={onApprove}
            className="flex-1 py-1 bg-primary text-on-primary font-label-sm text-label-sm hover:opacity-90 transition-colors disabled:opacity-60"
          >
            VALIDER
          </button>
        </div>
      )}
    </div>
  );
}

function BlockerCard({
  s,
  canReview,
  teams,
  onRead,
  onReject,
}: {
  s: Submission;
  canReview: boolean;
  teams: string[];
  onRead: () => void;
  onReject: () => void;
}) {
  const qc = useQueryClient();
  const [title, setTitle] = useState(s.proposed_title ?? "");
  const [department, setDepartment] = useState(s.team);
  const [severity, setSeverity] = useState<BlockerSeverity>(s.severity ?? "warning");
  const [aiTitle, setAiTitle] = useState<string | null>(
    s.proposed_title_by_ai ? (s.proposed_title ?? null) : null,
  );

  // Titre proposé par l'IA (US31) : une seule demande par carte, seule la description part à l'IA.
  const suggestion = useQuery({
    queryKey: ["title-suggestion", s.id],
    queryFn: () => suggestBlockerTitle({ data: { submissionId: s.id } }),
    enabled: canReview && !s.proposed_title,
    staleTime: Infinity,
    retry: false,
  });
  useEffect(() => {
    const r = suggestion.data;
    if (r?.title && !title) {
      setTitle(r.title);
      if (r.byAi) setAiTitle(r.title);
    }
    // Remplit le champ une seule fois, quand la proposition arrive.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [suggestion.data]);

  const assignees = useQuery({
    queryKey: ["assignees", "manager", s.team],
    queryFn: () => fetchAssigneeNames(s.team),
    retry: false,
  });
  const assigned = [...(assignees.data ?? []), ADMIN_LABEL].join(" · ");

  const publish = useMutation({
    mutationFn: () =>
      publishBlocker({ submissionId: s.id, title: title.trim(), department, severity }),
    onSuccess: () => {
      const edited = !!aiTitle && aiTitle !== title.trim();
      if (edited) trackEvent("ai_suggestion_edited", "soumissions", { edited: true });
      trackEvent("blocker_report_qualified", "soumissions", {
        outcome: "publié",
        clicks: 1,
        edited,
      });
      toast.success("Point bloquant créé au statut OUVERT");
    },
    onError: (e: unknown) => toast.error((e as Error).message),
    onSettled: () => {
      qc.invalidateQueries({ queryKey: ["submissions"] });
      qc.invalidateQueries({ queryKey: ["blockers"] });
    },
  });

  const titleTooShort = title.trim().length < 3;
  const suggesting = suggestion.isLoading && !title;

  return (
    <div className="p-sm border border-outline-variant bg-card space-y-sm min-w-0 overflow-hidden">
      <CardHead s={s} />
      <div className="space-y-xs">
        <p className="font-label-sm text-label-sm text-on-surface-variant uppercase">
          Assigné à : {assigned}
        </p>
        <SubmissionPreview content={s.content} onOpen={onRead} />
        <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
        <div className="flex flex-wrap gap-xs">
          {s.severity && (
            <span className="font-label-sm text-label-sm bg-surface-container-highest px-xs py-0.5 uppercase">
              Sévérité : {SEVERITY_LABELS[s.severity]}
            </span>
          )}
          {isLate(s.created_at) && (
            <span className="font-label-sm text-label-sm bg-tertiary-fixed text-on-tertiary-fixed px-xs py-0.5">
              PLUS DE 5 JOURS OUVRÉS
            </span>
          )}
        </div>
      </div>

      {canReview && (
        <div className="space-y-xs bg-surface-container-low p-sm">
          <p className="font-label-sm text-label-sm text-on-surface-variant uppercase">À valider</p>
          <div className="space-y-1">
            <label className="flex flex-wrap items-center gap-xs font-label-sm text-label-sm text-on-surface-variant uppercase">
              Titre
              {aiTitle && aiTitle === title && (
                <span className="bg-tertiary-fixed text-on-tertiary-fixed px-xs">
                  PROPOSÉ PAR L'IA
                </span>
              )}
              <input
                type="text"
                value={title}
                maxLength={160}
                placeholder={suggesting ? "Titre en cours de proposition…" : "Saisissez un titre"}
                onChange={(e) => setTitle(e.target.value)}
                className="mt-1 w-full border border-outline-variant bg-card p-xs font-body-md normal-case text-on-surface focus:border-primary focus:outline-none"
              />
            </label>
            {titleTooShort && !suggesting && (
              <p className="text-body-sm text-on-surface-variant">
                Saisissez un titre (3 caractères minimum).
              </p>
            )}
          </div>
          <label className="block font-label-sm text-label-sm text-on-surface-variant uppercase">
            Pôle
            <select
              value={department}
              onChange={(e) => setDepartment(e.target.value)}
              className="mt-1 w-full border border-outline-variant bg-card p-xs font-body-md normal-case text-on-surface"
            >
              {(teams.includes(department) ? teams : [department, ...teams]).map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </label>
          <label className="block font-label-sm text-label-sm text-on-surface-variant uppercase">
            Sévérité
            <select
              value={severity}
              onChange={(e) => setSeverity(e.target.value as BlockerSeverity)}
              className="mt-1 w-full border border-outline-variant bg-card p-xs font-body-md normal-case text-on-surface"
            >
              {(Object.keys(SEVERITY_LABELS) as BlockerSeverity[]).map((v) => (
                <option key={v} value={v}>
                  {SEVERITY_LABELS[v]}
                </option>
              ))}
            </select>
          </label>
          <p className="text-[11px] font-label-sm text-on-surface-variant">
            Sera publié au statut OUVERT
          </p>
          <div className="flex gap-xs">
            <button
              type="button"
              onClick={onReject}
              className="flex-1 py-1 border border-outline text-primary font-label-sm text-label-sm hover:bg-surface-container transition-colors"
            >
              REFUSER
            </button>
            <button
              type="button"
              disabled={publish.isPending || titleTooShort}
              onClick={() => publish.mutate()}
              className="flex-1 py-1 bg-primary text-on-primary font-label-sm text-label-sm hover:opacity-90 transition-colors disabled:opacity-50"
            >
              {publish.isPending ? "…" : "CRÉER LE POINT BLOQUANT"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

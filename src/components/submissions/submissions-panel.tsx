import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AttachmentLink } from "@/components/attachment-link";
import { SubmissionPreview, formatExactDate } from "@/components/expandable-card";
import { Linkify } from "@/components/linkify";
import { ModuleHint, hintId, type ModuleHintKey } from "@/components/module-hint";
import { KindTag, PendingQueue } from "@/components/submissions/pending-queue";
import {
  MySubmissions,
  PublishedChangesNote,
  SHOW_ALL_EVENT,
  SubmissionFilters,
  emptyMessage,
  statusBadge,
} from "@/components/submissions/my-submissions";
import type { Submission, SubmissionKind } from "@/lib/dashboard";
import { fetchTeamSubmissions, type MyStatusFilter } from "@/lib/f1";

type View = "equipes" | "mine";

const VIEWS: { value: View; label: string }[] = [
  { value: "mine", label: "MES SOUMISSIONS" },
  { value: "equipes", label: "SOUMISSIONS D'ÉQUIPES" },
];

/**
 * US70 : bloc unique du manager et de l'admin, à la place de « Soumissions en attente » et de
 * « Mes soumissions ». Deux vues, chacune avec les filtres Statut et Type :
 * - « Soumissions d'équipes » (par défaut) : « En attente » montre la file à traiter (US63) ;
 *   les autres statuts montrent les décisions passées, en lecture seule ;
 * - « Mes soumissions » : le suivi de ses propres soumissions (US67, US68).
 * Le manager garde « Préparer mon point d'équipe » (US64), en haut à droite du bloc, avec une icône.
 */
export function SubmissionsPanel({
  role,
  email,
  managerTeams,
  onRead,
  onPrepareRecap,
}: {
  role: string;
  email: string;
  /** Équipes du manager ; null pour l'admin (toutes les équipes) ; undefined pendant le chargement. */
  managerTeams: string[] | null | undefined;
  onRead: (s: Submission) => void;
  onPrepareRecap?: () => void;
}) {
  const [view, setView] = useState<View>("equipes");
  const [status, setStatus] = useState<MyStatusFilter>("en attente");
  const [kind, setKind] = useState<"tous" | SubmissionKind>("tous");

  // Lien d'un e-mail vers « Mes soumissions » ou « VOIR MES SOUMISSIONS » après un envoi.
  useEffect(() => {
    const showMine = () => setView("mine");
    const onHash = () => {
      if (window.location.hash === "#mes-soumissions") showMine();
    };
    onHash();
    window.addEventListener("hashchange", onHash);
    window.addEventListener(SHOW_ALL_EVENT, showMine);
    return () => {
      window.removeEventListener("hashchange", onHash);
      window.removeEventListener(SHOW_ALL_EVENT, showMine);
    };
  }, []);

  const hint: ModuleHintKey =
    view === "mine"
      ? "mes-soumissions"
      : role === "admin"
        ? "soumissions-en-attente-admin"
        : "soumissions-en-attente";

  return (
    <section
      id="mes-soumissions"
      aria-describedby={hintId(hint)}
      className="col-span-12 lg:col-span-6 min-w-0 bg-surface-container-lowest border border-outline-variant p-md flex flex-col"
    >
      <div className="border-b border-outline-variant pb-sm mb-sm space-y-xs">
        <div className="flex flex-wrap items-start justify-between gap-xs">
          <h2 className="font-headline-sm text-headline-sm text-primary">Soumissions</h2>
          {onPrepareRecap && (
            <button
              type="button"
              aria-haspopup="dialog"
              onClick={onPrepareRecap}
              className="flex items-center gap-xs border border-outline bg-surface px-sm py-xs font-label-sm text-label-sm text-primary hover:bg-surface-container focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <span
                aria-hidden="true"
                className="material-symbols-outlined"
                style={{ fontSize: 18 }}
              >
                groups
              </span>
              PRÉPARER MON POINT D'ÉQUIPE
            </button>
          )}
        </div>
        <div role="group" aria-label="Choisir la vue" className="flex flex-wrap gap-xs">
          {VIEWS.map((v) => (
            <button
              key={v.value}
              type="button"
              aria-pressed={view === v.value}
              onClick={() => setView(v.value)}
              className={`px-sm py-0.5 border font-label-sm text-label-sm focus:outline-none focus-visible:ring-2 focus-visible:ring-primary ${
                view === v.value
                  ? "bg-primary text-on-primary border-primary"
                  : "border-outline-variant text-on-surface-variant hover:bg-surface-container"
              }`}
            >
              {v.label}
            </button>
          ))}
        </div>
        <ModuleHint module={hint} />
      </div>

      {view === "mine" ? (
        <MySubmissions role={role} email={email} onRead={onRead} embedded />
      ) : (
        <>
          <div className="border-b border-outline-variant pb-sm mb-md">
            <SubmissionFilters status={status} onStatus={setStatus} type={kind} onType={setKind} />
          </div>
          {status === "en attente" ? (
            <PendingQueue role={role} mode="manager" kindFilter={kind} />
          ) : (
            <TeamHistory teams={managerTeams} status={status} kind={kind} onRead={onRead} />
          )}
        </>
      )}
    </section>
  );
}

/** Décisions passées des équipes (publiées, refusées, archivées), en lecture seule. */
function TeamHistory({
  teams,
  status,
  kind,
  onRead,
}: {
  teams: string[] | null | undefined;
  status: MyStatusFilter;
  kind: "tous" | SubmissionKind;
  onRead: (s: Submission) => void;
}) {
  const q = useQuery({
    queryKey: [
      "submissions",
      "equipes",
      teams === null ? "toutes" : (teams ?? []).join("|"),
      status,
      kind,
    ],
    queryFn: () => fetchTeamSubmissions(teams ?? null, { status, kind }),
    enabled: teams !== undefined,
    retry: false,
  });
  const rows = q.data ?? [];

  return (
    <div className="space-y-xs min-w-0">
      <div aria-live="polite" className="sr-only">
        {q.data
          ? `${rows.length} soumission${rows.length > 1 ? "s" : ""} affichée${rows.length > 1 ? "s" : ""}`
          : ""}
      </div>
      {(q.isLoading || teams === undefined) && (
        <p className="text-body-sm text-on-surface-variant">Chargement…</p>
      )}
      {q.isError && (
        <p className="text-body-sm text-error">Les soumissions des équipes sont indisponibles.</p>
      )}
      {q.data && rows.length === 0 && (
        <p className="text-body-sm text-on-surface-variant italic">
          {emptyMessage(status, kind, "equipes")}
        </p>
      )}
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
                <p className="font-body-sm text-primary font-bold wrap-anywhere">{s.author_name}</p>
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
              {s.team} · envoyé le {formatExactDate(s.created_at)}
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
          </div>
        );
      })}
    </div>
  );
}

import { createFileRoute, Link } from "@tanstack/react-router";
import { signOut } from "@/lib/auth";
import { supabase } from "@/integrations/supabase/client";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { SubmissionReader } from "@/components/submission-reader";
import { NewsReader } from "@/components/news-reader";
import { DepartureNotices } from "@/components/departure-notices";
import { NewsImage, NewsLinks } from "@/components/news-media";
import { NewsDraftsModal, NewsEditorModal } from "@/components/news-modals";
import { BlockerArchive, ValidatedSubmissions } from "@/components/dashboard-extras";
import { PendingQueue } from "@/components/submissions/pending-queue";
import { MySubmissions } from "@/components/submissions/my-submissions";
import { SubmitModal, type SentSubmission } from "@/components/submissions/submit-modal";
import { TeamRecapPanel } from "@/components/submissions/team-recap-panel";
import { useModuleViewed } from "@/lib/use-module-viewed";
import { fetchMyProfile } from "@/lib/f1";
import { ModuleHint, hintId } from "@/components/module-hint";
import { Button } from "@/components/ui/button";
import {
  fetchBlockers,
  fetchIndicateursDuMois,
  indicateursDashboard,
  ecartFleche,
  ecartText,
  formatMetricValue,
  moisText,
  moisTitre,
  EVOLUTION_CLASSES,
  EVOLUTION_LABELS,
  fetchNews,
  exportMyRecentSubmissions,
  type News,
  type Submission,
  timeAgo,
  updateBlockerStatus,
  type IndicateurMois,
} from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/")({
  head: () => ({
    meta: [
      { title: "Happy Place — Actualités et vue d'ensemble" },
      {
        name: "description",
        content:
          "Pilotez les missions de recrutement IT et digital, les propositions des équipes, les alertes opérationnelles et les indicateurs du cabinet.",
      },
      { property: "og:title", content: "Happy Place — Vue d'ensemble" },
      {
        property: "og:description",
        content:
          "Suivez l'activité du cabinet, les missions de recrutement, les alertes et les indicateurs clés.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: ManagerSpace,
});

const PERF_IMAGE =
  "https://lh3.googleusercontent.com/aida-public/AB6AXuAz-Y4URSqOCzUaVC6vomdu54tTiFPC_bF9A_h0SjxJ1mq2OlNfOyeKTNkPIgtPRloYwE5JrWFm2FHBNUq0GScs0ALDVMiq16FLu95dHNGPjmybEoIb2uyz1OGozRn0XkudSMukcPY4gKfeOJMR_KAnhYbkZifswTCbpCs_aHZyMuoZRz_oc4KsWtWiryTdwVD0EKyvxScj3palbDIM2wMlnH0njPGj912mRwhMmTo3Yu07l6xfVv2Zuw";

function Icon({ name, className = "" }: { name: string; className?: string }) {
  return (
    <span aria-hidden="true" className={`material-symbols-outlined ${className}`}>
      {name}
    </span>
  );
}

/**
 * Carte d'indicateur (F4 révisée, 2026-11-03) : nom, valeur du mois choisi par
 * l'admin, évolution par rapport au mois précédent. Vert si l'évolution est
 * favorable, rouge si elle est défavorable, gris si l'écart est nul ou si le
 * mois précédent n'a pas de valeur (N.C.).
 */
function MetricCard({ m, fallback }: { m: IndicateurMois | undefined; fallback: string }) {
  const hasValue = m?.value != null;
  const evo = m?.evolution ?? null;
  return (
    <div className="p-sm bg-card border border-outline-variant text-center">
      <p className="font-label-sm text-label-sm text-on-surface-variant uppercase">
        {m?.label ?? fallback}
      </p>
      <p className="font-display text-[32px] text-primary">
        {m && hasValue ? formatMetricValue(m.value as number, m.unit, m.comptage) : "—"}
      </p>
      {m && !hasValue && (
        <p className="text-[11px] text-on-surface-variant font-label-sm">
          Non renseigné pour {moisText(m.mois)}
        </p>
      )}
      {m && hasValue && evo && (
        <p className={`text-[12px] font-label-sm font-bold ${EVOLUTION_CLASSES[evo]}`}>
          <span className="sr-only">Évolution {EVOLUTION_LABELS[evo]} : </span>
          {evo === "nc" ? (
            "N.C."
          ) : (
            <>
              <span aria-hidden="true">{ecartFleche(m.ecart)} </span>
              {ecartText(m.ecart, m.unit, m.comptage)}
            </>
          )}
        </p>
      )}
      {m && hasValue && (
        <p className="text-[10px] text-on-surface-variant font-label-sm">
          {evo === "nc"
            ? `Pas de valeur pour ${moisText(m.mois_precedent)}`
            : `vs ${moisText(m.mois_precedent)}`}
        </p>
      )}
    </div>
  );
}

function ManagerSpace() {
  const qc = useQueryClient();
  const { role, email, user } = Route.useRouteContext();
  const isAdmin = role === "admin";
  const canReview = role === "admin" || role === "manager";
  const canWriteNews = canReview;
  const myEmail = (email ?? "").toLowerCase();
  const meta = (user?.user_metadata ?? {}) as Record<string, unknown>;

  // Liens des e-mails (US61, US65) : #mes-soumissions ou #points-bloquants.
  // Les blocs s'affichent après le chargement des données : on attend qu'ils existent.
  useEffect(() => {
    const id = window.location.hash.slice(1);
    if (!id) return;
    let tries = 0;
    const timer = window.setInterval(() => {
      const el = document.getElementById(id);
      if (el || ++tries > 20) {
        window.clearInterval(timer);
        el?.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }, 250);
    return () => window.clearInterval(timer);
  }, []);
  // US66 : une actualité est signée du prénom et du nom de la liste blanche, à défaut de l'adresse.
  const profile = useQuery({
    queryKey: ["profile", myEmail],
    enabled: canWriteNews && !!myEmail,
    queryFn: () => fetchMyProfile(myEmail),
  });
  const profileName = profile.data && profile.data.fullName !== myEmail ? profile.data.fullName : "";
  const myName =
    profileName ||
    (typeof meta.full_name === "string" && meta.full_name) ||
    (typeof meta.name === "string" && meta.name) ||
    myEmail;
  // US66 : fenêtres « Créer une actualité » (null = nouvelle, News = brouillon à modifier) et « Brouillons ».
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingDraft, setEditingDraft] = useState<News | null>(null);
  const [draftsOpen, setDraftsOpen] = useState(false);
  const [submitOpen, setSubmitOpen] = useState(false);
  const [sent, setSent] = useState<SentSubmission | null>(null);
  const [recapOpen, setRecapOpen] = useState(false);
  const newsRef = useModuleViewed<HTMLElement>("actus");
  const blockersRef = useModuleViewed<HTMLElement>("points_bloquants");
  const metricsRef = useModuleViewed<HTMLElement>("indicateurs");
  const myTeams = useQuery({
    queryKey: ["manager_teams", "mine", email],
    enabled: role === "manager" && !!email,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("manager_teams")
        .select("team, allowed_users!inner(email)")
        .eq("allowed_users.email", (email ?? "").toLowerCase());
      if (error) throw error;
      return (data ?? []).map((t) => t.team).sort();
    },
  });
  const [reading, setReading] = useState<Submission | null>(null);
  const [readingNews, setReadingNews] = useState<News | null>(null);
  const [archiveOpen, setArchiveOpen] = useState(false);

  const news = useQuery({ queryKey: ["news"], queryFn: fetchNews, retry: false });
  const blockers = useQuery({ queryKey: ["blockers"], queryFn: fetchBlockers, retry: false });
  const metrics = useQuery({ queryKey: ["metrics", "mois"], queryFn: fetchIndicateursDuMois, retry: false });
  const moisAffiche = metrics.data?.[0]?.mois ?? null;
  const onError = (e: unknown) => toast.error((e as Error).message);

  const exportReport = useMutation({
    mutationFn: () => {
      if (!email) throw new Error("Votre adresse e-mail est indisponible.");
      return exportMyRecentSubmissions(email);
    },
    onSuccess: (count) => {
      if (count === 0) {
        toast.info("Aucune soumission en attente ou validée sur les 30 derniers jours.");
        return;
      }
      toast.success(`${count} soumission${count > 1 ? "s" : ""} exportée${count > 1 ? "s" : ""} au format CSV.`);
    },
    onError,
  });

  const setBlocker = useMutation({
    mutationFn: updateBlockerStatus,
    onSuccess: () => qc.invalidateQueries({ queryKey: ["blockers"] }),
    onError,
  });


  const visibleDrafts = news.data?.filter((n) => n.status === "brouillon") ?? [];
  const drafts = visibleDrafts.length;
  // Le dernier brouillon publié ou supprimé ferme la fenêtre « Brouillons ».
  useEffect(() => {
    if (drafts === 0) setDraftsOpen(false);
  }, [drafts]);
  const published = news.data?.filter((n) => n.status === "publiée") ?? [];
  const roleLabel = role === "admin" ? "ADMIN" : role === "manager" ? "MANAGER" : "COLLABORATEUR";

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader />
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        {email && <DepartureNotices email={email} />}
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-sm mb-lg">
          <div className="space-y-sm">
            <p className="font-label-sm text-label-sm text-on-surface-variant uppercase tracking-widest">
              Vue d'ensemble
            </p>
            <h1 className="font-headline-lg text-headline-lg text-primary">Happy Place</h1>
            <button
              onClick={() => {
                setSent(null);
                setSubmitOpen(true);
              }}
              aria-describedby={hintId("soumettre")}
              className="flex items-center gap-xs px-md py-xs bg-primary text-on-primary font-label-md text-label-md hover:opacity-90 transition-all shadow-sm"
            >
              <Icon name="add" /> SOUMETTRE
            </button>
            <ModuleHint module="soumettre" />
          </div>
          <div className="flex flex-wrap gap-xs items-center md:items-end md:justify-end">
            <span className="font-label-sm text-label-sm text-on-surface-variant">
              {email} · {roleLabel}
            </span>
            <button
              onClick={() => signOut()}
              className="flex items-center gap-xs px-md py-xs border border-outline bg-surface text-primary font-label-md text-label-md hover:bg-surface-container"
            >
              <Icon name="logout" /> DÉCONNEXION
            </button>
            {isAdmin && (<Link
              to="/manage/news"
              className="flex items-center gap-xs px-md py-xs border border-outline bg-surface text-primary font-label-md text-label-md hover:bg-surface-container transition-all"
            >
              <Icon name="database" /> GÉRER LES DONNÉES
            </Link>)}
            <Button
              type="button"
              variant="outline"
              disabled={exportReport.isPending}
              onClick={() => exportReport.mutate()}
              className="h-auto rounded-none border-outline bg-surface px-md py-xs font-label-md text-label-md text-primary shadow-none hover:bg-surface-container"
            >
              <Icon name="file_download" /> {exportReport.isPending ? "EXPORT EN COURS…" : "EXPORTER LE RAPPORT"}
            </Button>
          </div>
        </div>

        {sent && (
          <div
            role="status"
            className="flex flex-wrap items-center justify-between gap-sm border border-outline-variant border-l-4 border-l-tertiary-fixed-dim bg-card p-sm"
          >
            <p className="text-body-md text-primary">
              {sent.kind === "point bloquant" ? "Point bloquant envoyé" : "Idée envoyée"}
              {sent.assignedTo ? ` à ${sent.assignedTo}.` : "."}
              {sent.kind === "point bloquant" ? " Vous êtes en copie de l'e-mail." : ""}
            </p>
            <div className="flex items-center gap-sm">
              <a href="#mes-soumissions" className="font-label-sm text-label-sm text-primary underline">
                VOIR MES SOUMISSIONS
              </a>
              <button
                type="button"
                aria-label="Fermer le message"
                onClick={() => setSent(null)}
                className="text-on-surface-variant hover:text-primary"
              >
                <Icon name="close" />
              </button>
            </div>
          </div>
        )}

        <div className="bento-grid">
          {/* News Management & Input */}
          <section
            ref={newsRef}
            aria-describedby={hintId("actus")}
            className="col-span-12 lg:col-span-8 bg-surface-container-lowest border border-outline-variant p-md flex flex-col gap-md"
          >
            <div className="border-b border-outline-variant pb-sm">
              <div className="flex flex-wrap items-center justify-between gap-sm">
                <h2 className="font-headline-sm text-headline-sm text-primary">
                  Actualités du cabinet
                </h2>
                {canWriteNews && (
                  <div className="flex flex-wrap items-center gap-xs">
                    {drafts > 0 && (
                      <button
                        type="button"
                        aria-haspopup="dialog"
                        onClick={() => setDraftsOpen(true)}
                        className="flex items-center gap-xs px-md py-xs border border-outline bg-surface text-primary font-label-md text-label-md hover:bg-surface-container"
                      >
                        <Icon name="draft" /> BROUILLONS ({drafts})
                      </button>
                    )}
                    <button
                      type="button"
                      aria-haspopup="dialog"
                      onClick={() => {
                        setEditingDraft(null);
                        setEditorOpen(true);
                      }}
                      className="flex items-center gap-xs px-md py-xs bg-primary text-on-primary font-label-md text-label-md hover:opacity-90"
                    >
                      <Icon name="add" /> CRÉER UNE ACTUALITÉ
                    </button>
                  </div>
                )}
              </div>
              <ModuleHint module="actus" />
            </div>
            <div>
              <h3 className="font-label-md text-label-md text-on-surface-variant mb-sm">
                PUBLIÉES RÉCEMMENT
              </h3>
              <div className="space-y-xs">
                {news.isLoading && (
                  <p className="text-body-sm text-on-surface-variant">Chargement…</p>
                )}
                {news.isError && (
                  <p className="text-body-sm text-error">
                    Les actualités sont indisponibles.
                  </p>
                )}
                {published.slice(0, 4).map((n) => (
                  <button
                    type="button"
                    key={n.id}
                    onClick={() => setReadingNews(n)}
                    aria-haspopup="dialog"
                    className="w-full text-left p-sm bg-surface-container hover:bg-surface-container-high transition-colors cursor-pointer group min-w-0 overflow-hidden space-y-xs focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                  >
                    {n.image_path && <NewsImage path={n.image_path} alt={n.title} />}
                    <div className="flex items-center justify-between gap-sm min-w-0">
                    <div className="flex items-center gap-md min-w-0">
                      <Icon name="article" className="text-on-surface-variant" />
                      <div className="min-w-0">
                        <p className="font-body-md text-primary group-hover:underline wrap-anywhere">{n.title}</p>
                        <p className="text-xs text-on-surface-variant uppercase font-label-sm">
                          Publiée {timeAgo(n.created_at)} • Par {n.author}
                        </p>
                      </div>
                    </div>
                    {isAdmin && <Icon name="edit" className="text-on-surface-variant" />}
                    </div>
                    <NewsLinks links={n.links} />
                  </button>
                ))}
              </div>
            </div>
          </section>

          {canReview ? (
            <>
              {/* Soumissions en attente (US63) : la file à traiter du manager et de l'admin */}
              <section className="col-span-12 lg:col-span-4 min-w-0 bg-surface-container-lowest border border-outline-variant p-md flex flex-col">
                <PendingQueue
                  role={role}
                  mode="manager"
                  onPrepareRecap={role === "manager" ? () => setRecapOpen(true) : undefined}
                />
              </section>

              {/* Mes soumissions, masqué tant que le manager ou l'admin n'a rien soumis */}
              <MySubmissions email={myEmail} onRead={setReading} hideWhenEmpty />
            </>
          ) : (
            /* Collaborateur (US67) : un seul bloc, à la place de « Soumissions en attente » */
            <MySubmissions email={myEmail} onRead={setReading} layout="colonne" />
          )}

          <ValidatedSubmissions
            role={role}
            email={myEmail}
            managerTeams={myTeams.data ?? []}
            onRead={setReading}
          />

          {/* Points Bloquants */}
          <section
            id="points-bloquants"
            ref={blockersRef}
            aria-describedby={hintId("points-bloquants")}
            className="col-span-12 md:col-span-7 bg-surface-container-lowest border border-outline-variant p-md"
          >
            <div className="flex items-center justify-between mb-xs">
              <div className="flex items-center gap-sm">
                <h2 className="font-headline-sm text-headline-sm text-primary">Points Bloquants</h2>
                <span className="text-xs bg-error-container text-on-error-container px-xs py-1 font-label-sm">
                  PRIORITÉ HAUTE
                </span>
              </div>
              <button
                type="button"
                aria-haspopup="dialog"
                onClick={() => setArchiveOpen(true)}
                className="text-primary font-label-sm text-label-sm underline focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                 VOIR L'ARCHIVE
              </button>
            </div>
            <ModuleHint module="points-bloquants" className="mb-md" />
            <div className="space-y-sm">
              {blockers.isError && (
                <p className="text-body-sm text-error">
                  Les points bloquants sont indisponibles.
                </p>
              )}
              {blockers.data?.length === 0 && (
                <p className="text-body-sm text-on-surface-variant italic">
                  Aucun point bloquant en cours.
                </p>
              )}
              {blockers.data?.map((b) => {
                const critical = b.severity === "critical";
                return (
                  <div
                    key={b.id}
                    className={`${critical ? "accent-bar " : ""}bg-card border border-outline-variant p-sm flex items-start justify-between`}
                  >
                    <div className="flex gap-md">
                      <Icon
                        name={critical ? "error" : "warning"}
                        className={
                          critical
                            ? "text-error mt-1 [font-variation-settings:'FILL'_1]"
                            : "text-secondary mt-1"
                        }
                      />
                      <div>
                        <p className="font-body-md text-primary font-bold">{b.title}</p>
                        <p className="text-body-sm text-on-surface-variant">{b.description}</p>
                        <div className="flex items-center gap-sm mt-xs">
                          <span className="text-[11px] font-label-sm bg-surface-container-highest px-xs py-0.5">
                            {b.department}
                          </span>
                          <span className="text-[11px] font-label-sm text-on-surface-variant">
                            Mis à jour {timeAgo(b.updated_at)}
                          </span>
                        </div>
                      </div>
                    </div>
                    <select
                      aria-label={`Statut de ${b.title}`}
                      value={b.status}
                      disabled={!isAdmin}
                      onChange={(e) => setBlocker.mutate({ id: b.id, status: e.target.value })}
                      className={`bg-transparent border-none text-xs font-label-sm focus:outline-none cursor-pointer ${critical ? "text-error" : "text-on-surface-variant"}`}
                    >
                      <option>OUVERT</option>
                      <option>EN COURS</option>
                      <option>SURVEILLANCE</option>
                      <option
                        disabled={b.status === "OUVERT"}
                        title={b.status === "OUVERT" ? "Passe d'abord par EN COURS" : undefined}
                      >
                        RÉSOLU
                      </option>
                    </select>
                  </div>
                );
              })}
            </div>
          </section>

          {/* Performance Hub */}
          <section
            ref={metricsRef}
            aria-describedby={hintId("indicateurs")}
            className="col-span-12 md:col-span-5 bg-surface-container-lowest border border-outline-variant p-md flex flex-col"
          >
            <div className="flex items-center justify-between mb-xs">
              <h2 className="font-headline-sm text-headline-sm text-primary">Indicateurs</h2>
              <div className="flex items-center gap-xs">
                {moisAffiche && (
                  <p className="font-label-sm text-label-sm text-primary uppercase">
                    <span className="sr-only">Mois des indicateurs : </span>
                    {moisTitre(moisAffiche)}
                  </p>
                )}
                {isAdmin && (
                  <Link
                    to="/manage/metrics"
                    aria-label="Choisir le mois et les indicateurs affichés"
                    title="Choisir le mois et les indicateurs affichés"
                    className="text-on-surface-variant hover:text-primary"
                  >
                    <Icon name="settings" />
                  </Link>
                )}
              </div>
            </div>
            <ModuleHint module="indicateurs" className="mb-md" />
            {/* Indicateurs choisis par l'admin (US43), dans leur ordre ; la grille passe à la ligne */}
            {metrics.isSuccess && indicateursDashboard(metrics.data).length === 0 ? (
              <p className="text-body-sm text-on-surface-variant italic mb-md">
                Aucun indicateur n'est affiché pour le moment.
                {isAdmin && " Choisissez-les dans « Gérer les données > Indicateurs »."}
              </p>
            ) : (
              <div className="grid grid-cols-2 gap-sm mb-md">
                {metrics.isSuccess ? (
                  indicateursDashboard(metrics.data).map((m) => (
                    <MetricCard key={m.key} m={m} fallback={m.label} />
                  ))
                ) : (
                  <>
                    <MetricCard m={undefined} fallback="Indicateur" />
                    <MetricCard m={undefined} fallback="Indicateur" />
                  </>
                )}
              </div>
            )}
            <div className="mt-auto pt-md">
              <img
                src={PERF_IMAGE}
                 alt="Graphiques minimalistes à barres et à lignes dans un tableau de bord anthracite et blanc"
                loading="lazy"
                className="w-full h-24 object-cover border border-outline-variant"
              />
            </div>
          </section>

        </div>
      </main>
      <BlockerArchive open={archiveOpen} onClose={() => setArchiveOpen(false)} />
      <NewsReader news={readingNews} onClose={() => setReadingNews(null)} />
      {canWriteNews && editorOpen && (
        <NewsEditorModal
          key={editingDraft?.id ?? "nouvelle"}
          draft={editingDraft}
          author={myName}
          authorEmail={myEmail}
          onClose={() => {
            setEditorOpen(false);
            setEditingDraft(null);
          }}
        />
      )}
      {canWriteNews && draftsOpen && drafts > 0 && (
        <NewsDraftsModal
          drafts={visibleDrafts}
          isAdmin={isAdmin}
          myEmail={myEmail}
          onEdit={(n) => {
            setDraftsOpen(false);
            setEditingDraft(n);
            setEditorOpen(true);
          }}
          onClose={() => setDraftsOpen(false)}
        />
      )}
      <SubmissionReader
        submission={reading}
        onClose={() => setReading(null)}
      />
      {submitOpen && (
        <SubmitModal
          role={role}
          email={myEmail}
          managerTeams={myTeams.data ?? []}
          onClose={() => setSubmitOpen(false)}
          onSent={(result) => {
            setSubmitOpen(false);
            setSent(result);
          }}
        />
      )}
      {role === "manager" && <TeamRecapPanel open={recapOpen} email={myEmail} onClose={() => setRecapOpen(false)} />}
    </div>
  );
}

import { loadBrowserLib } from "@/lib/browser-lib";
import type { Database, Json } from "@/integrations/supabase/types";
import { applyNewsImage, removeNewsImageFile, type MediaDraft, type NewsLink } from "@/lib/news-media";
import { supabase } from "@/integrations/supabase/client";

export const db = supabase;

type Enums = Database["public"]["Enums"];


export type News = {
  id: string;
  title: string;
  body: string | null;
  author: string;
  author_email?: string | null;
  status: string;
  created_at: string;
  image_path?: string | null;
  links?: unknown;
};

export type Submission = {
  id: string;
  author_name: string;
  team: string;
  content: string;
  status: string;
  created_at: string;
  rejection_category?: string | null;
  rejection_note?: string | null;
  submitted_by_email?: string | null;
  attachment_path?: string | null;
  attachment_name?: string | null;
  kind: SubmissionKind;
  severity?: BlockerSeverity | null;
  proposed_title?: string | null;
  proposed_title_by_ai?: boolean;
  blocker_id?: string | null;
};

export type SubmissionKind = Enums["submission_kind"];
export type BlockerSeverity = Enums["blocker_severity"];

export const SEVERITY_LABELS: Record<BlockerSeverity, string> = {
  critical: "Critique",
  warning: "Avertissement",
  info: "Information",
};

export const REJECTION_CATEGORIES = [
  "à clarifier",
  "en désaccord avec les process",
  "doublon",
  "autre",
] as const;
export type RejectionCategory = (typeof REJECTION_CATEGORIES)[number];

export type Blocker = {
  id: string;
  title: string;
  description: string | null;
  department: string;
  severity: string;
  status: string;
  updated_at: string;
};

export type Metric = {
  key: string;
  label: string;
  value: number;
  unit: string | null;
  updated_at: string;
  trend: "hausse" | "baisse" | "stable";
  previous_value: number | null;
  delta: number | string | null;
  comptage: boolean;
  period_start: string | null;
  period_end: string | null;
  previous_recorded_at: string | null;
  previous_period_start: string | null;
  previous_period_end: string | null;
  afficher_dashboard: boolean;
  ordre_dashboard: number;
};

/** Indicateurs choisis par l'admin pour le dashboard (US43), dans leur ordre. */
export function dashboardMetrics(metrics: Metric[] | undefined): Metric[] {
  return (metrics ?? [])
    .filter((m) => m.afficher_dashboard)
    .sort((a, b) => a.ordre_dashboard - b.ordre_dashboard || a.label.localeCompare(b.label, "fr"));
}

const MOIS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
  "septembre", "octobre", "novembre", "décembre"];

/** Date ISO (AAAA-MM-JJ ou horodatage) en JJ/MM/AAAA, sans décalage de fuseau pour une date seule. */
export function dateFr(iso: string): string {
  const [y, m, d] = iso.slice(0, 10).split("-");
  if (iso.length > 10) {
    return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeZone: "Europe/Paris" }).format(new Date(iso));
  }
  return `${d}/${m}/${y}`;
}

/** Période de calcul (US40) : « septembre 2026 » pour un mois entier, sinon « du 01/09/2026 au 15/09/2026 ». */
export function periodText(start: string | null, end: string | null): string {
  if (!start || !end) return "Période non renseignée";
  const [ys, ms, ds] = start.split("-").map(Number);
  const [ye, me, de] = end.split("-").map(Number);
  const lastDay = new Date(Date.UTC(ye, me, 0)).getUTCDate();
  if (ys === ye && ms === me && ds === 1 && de === lastDay) return `${MOIS[ms - 1]} ${ys}`;
  return `du ${dateFr(start)} au ${dateFr(end)}`;
}

/** Saisie comparée par l'écart (US40) : « par rapport à la saisie du 21/10 ». */
export function comparedText(m: Pick<Metric, "previous_recorded_at">): string {
  if (!m.previous_recorded_at) return "";
  return `par rapport à la saisie du ${dateFr(m.previous_recorded_at).slice(0, 5)}`;
}

export const TREND_LABELS: Record<Metric["trend"], string> = {
  hausse: "▲ En hausse",
  baisse: "▼ En baisse",
  stable: "■ Stable",
};

export function deltaText(m: Pick<Metric, "delta" | "unit"> | undefined): string {
  if (!m || m.delta == null) return "";
  const delta = Number(m.delta);
  if (!Number.isFinite(delta) || delta === 0) return "";
  const abs = Math.abs(delta).toLocaleString("fr-FR", { maximumFractionDigits: 1 });
  const sign = delta > 0 ? "+" : "−";
  const suffix = m.unit === "%" ? " pts" : m.unit ? ` ${m.unit.trim()}` : "";
  return `${sign}${abs}${suffix}`;
}

/* ============================================================
 * F4 révisée (2026-11-03) : un mois de référence pour tous les indicateurs
 * ========================================================== */

/** favorable : vert ; defavorable : rouge ; stable (écart nul) et nc (pas de mois précédent) : gris. */
export type Evolution = "favorable" | "defavorable" | "stable" | "nc";

/** Une ligne de la vue `indicateurs_du_mois` : l'indicateur sur le mois choisi par l'admin. */
export type IndicateurMois = {
  key: string;
  label: string;
  unit: string | null;
  comptage: boolean;
  sens_favorable: "hausse" | "baisse";
  afficher_dashboard: boolean;
  ordre_dashboard: number;
  mois: string;
  value: number | null;
  updated_at: string | null;
  mois_precedent: string;
  valeur_precedente: number | null;
  ecart: number | null;
  evolution: Evolution | null;
};

export async function fetchIndicateursDuMois(): Promise<IndicateurMois[]> {
  const { data, error } = await db.from("indicateurs_du_mois").select("*");
  if (error) throw error;
  return (data ?? []) as IndicateurMois[];
}

/** Ordres proposés à l'admin pour le dashboard (US43, 2026-11-03). */
export const ORDRES_DASHBOARD: readonly number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

/** Indicateurs choisis par l'admin pour le dashboard (US43), dans leur ordre. */
export function indicateursDashboard(list: IndicateurMois[] | undefined): IndicateurMois[] {
  return (list ?? [])
    .filter((m) => m.afficher_dashboard)
    .sort((a, b) => a.ordre_dashboard - b.ordre_dashboard || a.label.localeCompare(b.label, "fr"));
}

/** « octobre 2026 » à partir de « 2026-10-01 ». */
export function moisText(iso: string): string {
  const [y, m] = iso.split("-").map(Number);
  return `${MOIS[m - 1]} ${y}`;
}

/** « Octobre 2026 », pour un titre. */
export function moisTitre(iso: string): string {
  const t = moisText(iso);
  return t.charAt(0).toUpperCase() + t.slice(1);
}

/** Premier jour du mois, au format AAAA-MM-JJ. */
export function moisIso(annee: number, mois: number): string {
  return `${annee}-${String(mois).padStart(2, "0")}-01`;
}

/** Dernier mois terminé, à Paris : le 03/11/2026 donne « 2026-10-01 ». */
export function dernierMoisTermine(now = new Date()): string {
  const [y, m] = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Paris", year: "numeric", month: "2-digit" })
    .format(now)
    .split("-")
    .map(Number);
  return m === 1 ? moisIso(y - 1, 12) : moisIso(y, m - 1);
}

export const MOIS_LABELS = MOIS.map((m) => m.charAt(0).toUpperCase() + m.slice(1));

/** Flèche de l'évolution : sens de la valeur (la couleur dit si c'est favorable). */
export function ecartFleche(ecart: number | null): string {
  if (ecart == null) return "";
  return ecart > 0 ? "▲" : ecart < 0 ? "▼" : "■";
}

/** Écart en valeur : « +2,0 pts », « −11 », « 0 pt » ; pts pour un taux en %. */
export function ecartText(ecart: number | string | null, unit: string | null, comptage = false): string {
  if (ecart == null) return "N.C.";
  const e = Number(ecart);
  if (!Number.isFinite(e)) return "N.C.";
  const abs = Math.abs(e).toLocaleString("fr-FR", {
    minimumFractionDigits: !comptage && unit === "%" && e !== 0 ? 1 : 0,
    maximumFractionDigits: comptage ? 0 : 1,
  });
  const sign = e > 0 ? "+" : e < 0 ? "−" : "";
  const suffix =
    unit === "%"
      ? Math.abs(e) >= 2 ? " pts" : " pt"
      : unit
        ? ` ${uniteMot(unit, e) ?? unit.trim()}`
        : "";
  return `${sign}${abs}${suffix}`;
}

/** Couleur de l'évolution : vert si favorable, rouge si défavorable, gris sinon. */
export const EVOLUTION_CLASSES: Record<Evolution, string> = {
  favorable: "text-success",
  defavorable: "text-error",
  stable: "text-on-surface-variant",
  nc: "text-on-surface-variant",
};

export const EVOLUTION_LABELS: Record<Evolution, string> = {
  favorable: "évolution favorable",
  defavorable: "évolution défavorable",
  stable: "stable",
  nc: "non communiquée",
};

export type IndicateurInput = {
  key: string;
  label: string;
  unit: string | null;
  comptage: boolean;
  sens_favorable: "hausse" | "baisse";
  afficher_dashboard: boolean;
  ordre_dashboard: number;
};

export async function createIndicateur(input: IndicateurInput) {
  const { error } = await db.from("metrics").insert(input);
  if (error) throw error;
}

export async function updateIndicateur(key: string, input: IndicateurInput) {
  const { error } = await db
    .from("metrics")
    .update({ ...input, updated_at: new Date().toISOString() })
    .eq("key", key);
  if (error) throw error;
}

export async function fetchMoisReference(): Promise<string> {
  const { data, error } = await db.from("indicateurs_reglages").select("mois_reference").single();
  if (error) throw error;
  return data.mois_reference;
}

/** Admin : change le mois affiché sur le dashboard, pour tous les indicateurs. */
export async function updateMoisReference(mois: string) {
  const { data, error } = await db
    .from("indicateurs_reglages")
    .update({ mois_reference: mois })
    .eq("id", true)
    .select("mois_reference");
  if (error) throw error;
  if (!data?.length) throw new Error("Vous n'avez pas le droit de changer le mois des indicateurs.");
}

export type ValeurMensuelle = {
  metric_key: string;
  mois: string;
  value: number;
  updated_at: string;
  updated_by_email: string | null;
};

/** Admin : saisit ou corrige la valeur d'un indicateur pour un mois terminé. */
export async function saveValeurMensuelle(input: { metric_key: string; mois: string; value: number }) {
  const { error } = await db.from("metrics_mensuels").upsert(input, { onConflict: "metric_key,mois" });
  if (error) throw error;
}

export async function fetchValeursMensuelles(key: string): Promise<ValeurMensuelle[]> {
  const { data, error } = await db
    .from("metrics_mensuels")
    .select("*")
    .eq("metric_key", key)
    .order("mois", { ascending: false })
    .limit(24);
  if (error) throw error;
  return (data ?? []) as ValeurMensuelle[];
}

/** Clés des indicateurs qui ont une valeur pour ce mois (avant de l'afficher). */
export async function fetchClesRenseignees(mois: string): Promise<string[]> {
  const { data, error } = await db.from("metrics_mensuels").select("metric_key").eq("mois", mois);
  if (error) throw error;
  return (data ?? []).map((r) => r.metric_key);
}

/** Message lisible pour les refus de la base sur les indicateurs. */
export function messageIndicateur(e: unknown): string {
  const msg = (e as { message?: string })?.message ?? String(e);
  if (/n'est pas terminé/.test(msg)) return msg;
  if (/comptage/i.test(msg)) return "Un comptage est un nombre entier.";
  if (/metrics_ordre_dashboard_unique/.test(msg)) return "Cet ordre est déjà pris par un autre indicateur du dashboard.";
  if (/metrics_ordre_dashboard_affiche/.test(msg)) return "L'ordre d'un indicateur du dashboard va de 1 à 10.";
  if (/duplicate key|metrics_pkey/.test(msg)) return "Cette clé technique existe déjà.";
  return msg;
}

/**
 * Unité en toutes lettres (« jours ») : séparée par une espace, au singulier
 * en dessous de 2 (« 1,5 jour »). Un symbole (« % », « j ») reste collé.
 */
function uniteMot(unit: string, n: number): string | null {
  const u = unit.trim();
  if (!/^[a-zà-ÿ]{2,}$/i.test(u)) return null;
  return Math.abs(n) < 2 && u.endsWith("s") ? u.slice(0, -1) : u;
}

export function formatMetricValue(value: number | string, unit: string | null, comptage = false): string {
  const formatted = Number(value).toLocaleString("fr-FR", {
    minimumFractionDigits: !comptage && unit === "%" ? 1 : 0,
    maximumFractionDigits: comptage ? 0 : 1,
  });
  const mot = unit ? uniteMot(unit, Number(value)) : null;
  if (mot) return `${formatted} ${mot}`;
  return `${formatted}${unit ?? ""}`;
}

export async function fetchNews(): Promise<News[]> {
  const { data, error } = await db
    .from("news")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as News[];
}

export async function saveDraftNews(input: {
  id?: string;
  title: string;
  body: string;
  author: string;
  author_email: string;
  links: NewsLink[];
  media: MediaDraft;
}) {
  const payload = {
    title: input.title,
    body: input.body,
    author: input.author,
    author_email: input.author_email.toLowerCase(),
    status: "brouillon" as const,
    links: input.links as unknown as Json,
  };
  const { data, error } = input.id
    ? await db.from("news").update(payload).eq("id", input.id).select("id").single()
    : await db.from("news").insert(payload).select("id").single();
  if (error) throw error;
  await applyNewsImage(data.id, input.media);
}

export async function publishDraftNews(id: string) {
  const { data, error } = await db
    .from("news")
    .update({ status: "publiée" })
    .eq("id", id)
    .eq("status", "brouillon")
    .select("id");
  if (error) throw error;
  if (!data?.length) throw new Error("Vous n'avez pas le droit de publier cette actualité.");
}

export async function deleteDraftNews(id: string, imagePath?: string | null) {
  await removeNewsImageFile(imagePath);
  const { data, error } = await db.from("news").delete().eq("id", id).select("id");
  if (error) throw error;
  if (!data?.length) throw new Error("Vous n'avez pas le droit de supprimer cette actualité.");
}

export async function fetchSubmissions(): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .eq("status", "en attente")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Submission[];
}

export async function fetchMySubmissions(email: string): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .ilike("submitted_by_email", email)
    .order("created_at", { ascending: false })
    .limit(10);
  if (error) throw error;
  return (data ?? []) as Submission[];
}

function csvCell(value: string) {
  return `"${value.replaceAll('"', '""')}"`;
}

export async function exportMyRecentSubmissions(email: string): Promise<number> {
  const since = new Date();
  since.setDate(since.getDate() - 30);

  const { data, error } = await db
    .from("submissions")
    .select("created_at,author_name,submitted_by_email,team,content,status")
    .ilike("submitted_by_email", email)
    .in("status", ["en attente", "validée"])
    .gte("created_at", since.toISOString())
    .order("created_at", { ascending: false });
  if (error) throw error;

  const rows = data ?? [];
  if (rows.length === 0) return 0;

  const header = ["Date", "Auteur", "E-mail", "Équipe", "Question soumise", "Statut"];
  const csv = [
    header.map(csvCell).join(";"),
    ...rows.map((row) =>
      [
        new Date(row.created_at).toLocaleString("fr-FR"),
        row.author_name,
        row.submitted_by_email ?? "",
        row.team,
        row.content,
        row.status,
      ].map((value) => csvCell(String(value))).join(";"),
    ),
  ].join("\r\n");

  const blob = new Blob(["\uFEFF", csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `soumissions-30-jours-${new Date().toISOString().slice(0, 10)}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
  return rows.length;
}

export async function reviewSubmission(
  input:
    | { id: string; status: "validée" }
    | { id: string; status: "refusée"; rejection_category: RejectionCategory; rejection_note: string },
) {
  const patch =
    input.status === "refusée"
      ? { status: input.status, rejection_category: input.rejection_category, rejection_note: input.rejection_note.trim() }
      : { status: input.status, rejection_category: null, rejection_note: null };
  const { error } = await db
    .from("submissions")
    .update(patch)
    .eq("id", input.id);
  if (error) throw error;
}

export async function fetchBlockers(): Promise<Blocker[]> {
  const { data, error } = await db
    .from("blockers")
    .select("*")
    .neq("status", "RÉSOLU")
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Blocker[];
}

export async function fetchResolvedBlockers(): Promise<Blocker[]> {
  const { data, error } = await db
    .from("blockers")
    .select("*")
    .eq("status", "RÉSOLU")
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Blocker[];
}

export type ValidatedSubmission = Submission & { validated_at: string | null };

/** Idées validées, toutes équipes (filtrées par les règles d'accès de la base). */
export async function fetchValidatedSubmissions(): Promise<ValidatedSubmission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .eq("status", "validée")
    .eq("kind", "idée")
    .order("created_at", { ascending: false });
  if (error) throw error;
  const rows = (data ?? []) as Submission[];
  const dates = new Map<string, string>();
  if (rows.length) {
    // L'historique peut ne pas être lisible pour tous : dans ce cas, date de soumission.
    const { data: hist } = await db
      .from("submission_status_history")
      .select("submission_id, changed_at")
      .eq("new_status", "validée")
      .in("submission_id", rows.map((r) => r.id))
      .order("changed_at", { ascending: false });
    for (const h of hist ?? []) if (!dates.has(h.submission_id)) dates.set(h.submission_id, h.changed_at);
  }
  return rows
    .map((r) => ({ ...r, validated_at: dates.get(r.id) ?? null }))
    .sort((a, b) => (b.validated_at ?? b.created_at).localeCompare(a.validated_at ?? a.created_at));
}

export async function updateBlockerStatus(input: { id: string; status: string }) {
  const { error } = await db
    .from("blockers")
    .update({ status: input.status as Enums["blocker_status"], updated_at: new Date().toISOString() })
    .eq("id", input.id);
  if (error) throw error;
}

export async function fetchMetrics(): Promise<Metric[]> {
  const { data, error } = await db.from("metrics_with_trend").select("*");
  if (error) throw error;
  return (data ?? []) as Metric[];
}

export function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const min = Math.round(diff / 60000);
  if (min < 1) return "à l'instant";
  if (min < 60) return `il y a ${min} minute${min > 1 ? "s" : ""}`;
  const h = Math.round(min / 60);
  if (h < 24) return `il y a ${h} heure${h > 1 ? "s" : ""}`;
  const days = Math.round(h / 24);
  return `il y a ${days} jour${days > 1 ? "s" : ""}`;
}

/* ============================================================
 * CRUD complet — news / submissions / blockers / metrics
 * ========================================================== */

export type NewsInput = { title: string; body: string; author: string; status: string; links?: NewsLink[] };
export type SubmissionInput = {
  author_name: string;
  team: string;
  content: string;
  status: string;
  rejection_category?: string | null;
  rejection_note?: string | null;
};
export type BlockerInput = {
  title: string;
  description: string;
  department: string;
  severity: string;
  status: string;
};
export type MetricInput = {
  key: string;
  label: string;
  value: number;
  unit: string | null;
  comptage: boolean;
  period_start: string;
  period_end: string;
  afficher_dashboard: boolean;
  ordre_dashboard: number;
};

export async function fetchAllNews(): Promise<News[]> {
  const { data, error } = await db
    .from("news")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as News[];
}

function newsRow(input: NewsInput) {
  return { ...input, links: (input.links ?? []) as unknown as Json, status: input.status as Enums["news_status"] };
}

/** Admin : crée l'actualité (pour obtenir son id), puis envoie l'image. */
export async function createNews(input: NewsInput, media?: MediaDraft) {
  const { data, error } = await db.from("news").insert(newsRow(input)).select("id").single();
  if (error) throw error;
  if (media) await applyNewsImage(data.id, media);
}

export async function updateNews(id: string, input: NewsInput, media?: MediaDraft) {
  const { error } = await db.from("news").update(newsRow(input)).eq("id", id);
  if (error) throw error;
  if (media) await applyNewsImage(id, media);
}

export async function deleteNews(id: string, imagePath?: string | null) {
  await removeNewsImageFile(imagePath);
  const { error } = await db.from("news").delete().eq("id", id);
  if (error) throw error;
}

export async function fetchAllSubmissions(): Promise<Submission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Submission[];
}

function submissionRow(input: SubmissionInput) {
  const rejected = input.status === "refusée";
  return {
    author_name: input.author_name,
    team: input.team,
    content: input.content,
    status: input.status as Enums["submission_status"],
    rejection_category: rejected ? ((input.rejection_category || null) as Enums["rejection_category"] | null) : null,
    rejection_note: rejected ? input.rejection_note?.trim() || null : null,
  };
}

export async function createSubmission(input: SubmissionInput) {
  const { error } = await db.from("submissions").insert(submissionRow(input));
  if (error) throw error;
}

export const ATTACHMENT_BUCKET = "submission-attachments";
export const MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024;

export type NewSubmission = Omit<SubmissionInput, "status"> & {
  kind: SubmissionKind;
  severity: BlockerSeverity | null;
};

export async function submitSubmission(input: NewSubmission, file?: File | null) {
  let attachment_path: string | null = null;
  let attachment_name: string | null = null;
  if (file) {
    if (file.type !== "application/pdf") throw new Error("Seuls les fichiers PDF sont acceptés.");
    if (file.size > MAX_ATTACHMENT_BYTES) throw new Error("Le fichier dépasse 20 Mo.");
    const { data: u } = await db.auth.getUser();
    if (!u.user) throw new Error("Session expirée");
    attachment_path = `${u.user.id}/${crypto.randomUUID()}.pdf`;
    attachment_name = file.name.slice(0, 200);
    const { error: upErr } = await db.storage
      .from(ATTACHMENT_BUCKET)
      .upload(attachment_path, file, { contentType: "application/pdf" });
    if (upErr) throw upErr;
  }
  const { error } = await db.from("submissions").insert({
    author_name: input.author_name, team: input.team, content: input.content, status: "en attente",
    kind: input.kind, severity: input.kind === "point bloquant" ? input.severity : null,
    attachment_path, attachment_name,
  });
  if (error) throw error;
}

export async function downloadAttachment(path: string, name: string | null) {
  const { data, error } = await db.storage.from(ATTACHMENT_BUCKET).createSignedUrl(path, 60, {
    download: name ?? true,
  });
  if (error) throw error;
  window.open(data.signedUrl, "_blank", "noopener");
}

export async function updateSubmission(id: string, input: SubmissionInput) {
  const { error } = await db.from("submissions").update(submissionRow(input)).eq("id", id);
  if (error) throw error;
}

export async function deleteSubmission(id: string) {
  const { error } = await db.from("submissions").delete().eq("id", id);
  if (error) throw error;
}

export async function fetchAllBlockers(): Promise<Blocker[]> {
  const { data, error } = await db
    .from("blockers")
    .select("*")
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as Blocker[];
}

export async function createBlocker(input: BlockerInput) {
  const { error } = await db
    .from("blockers")
    .insert({ ...input, severity: input.severity as Enums["blocker_severity"], status: input.status as Enums["blocker_status"], updated_at: new Date().toISOString() });
  if (error) throw error;
}

export async function updateBlocker(id: string, input: BlockerInput) {
  const { error } = await db
    .from("blockers")
    .update({ ...input, severity: input.severity as Enums["blocker_severity"], status: input.status as Enums["blocker_status"], updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

export async function deleteBlocker(id: string) {
  const { error } = await db.from("blockers").delete().eq("id", id);
  if (error) throw error;
}

export async function createMetric(input: MetricInput) {
  const { error } = await db.from("metrics").insert(input);
  if (error) throw error;
}

export async function updateMetricRow(key: string, input: MetricInput) {
  const { error } = await db
    .from("metrics")
    .update({ ...input, updated_at: new Date().toISOString() })
    .eq("key", key);
  if (error) throw error;
}

export async function deleteMetric(key: string) {
  const { error } = await db.from("metrics").delete().eq("key", key);
  if (error) throw error;
}

export type SubmissionStatusHistory = {
  id: string;
  submission_id: string;
  old_status: string | null;
  new_status: string;
  changed_by_email: string | null;
  changed_by_name: string | null;
  is_automatic: boolean;
  rejection_category: string | null;
  rejection_note: string | null;
  changed_at: string;
};

export async function fetchSubmissionHistory(submissionId: string): Promise<SubmissionStatusHistory[]> {
  const { data, error } = await supabase
    .from("submission_status_history")
    .select("*")
    .eq("submission_id", submissionId)
    .order("changed_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as SubmissionStatusHistory[];
}

export type MetricHistoryPoint = {
  id: string;
  metric_key: string;
  value: number;
  recorded_at: string;
  period_start: string | null;
  period_end: string | null;
};

export async function fetchMetricHistory(key: string): Promise<MetricHistoryPoint[]> {
  const { data, error } = await supabase
    .from("metrics_history")
    .select("*")
    .eq("metric_key", key)
    .order("recorded_at", { ascending: false })
    .limit(50);
  if (error) throw error;
  return (data ?? []) as MetricHistoryPoint[];
}

/** Supprime du stockage les pièces jointes échues de la file. Renvoie supprimés et restants. */
export async function processAttachmentDeletionQueue(): Promise<{ deleted: number; remaining: number }> {
  const { data, error } = await supabase
    .from("attachment_deletion_queue")
    .select("id, path")
    .lte("delete_after", new Date().toISOString());
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) return { deleted: 0, remaining: 0 };
  const { data: removed, error: rmError } = await supabase.storage
    .from("submission-attachments")
    .remove(rows.map((r) => r.path));
  if (rmError) {
    await supabase
      .from("attachment_deletion_queue")
      .update({ last_error: rmError.message })
      .in("id", rows.map((r) => r.id));
    return { deleted: 0, remaining: rows.length };
  }
  const removedSet = new Set((removed ?? []).map((o) => o.name));
  const done = rows.filter((r) => removedSet.has(r.path));
  const missing = rows.filter((r) => !removedSet.has(r.path));
  // Fichiers que remove() n'a pas renvoyés : vérifier s'ils existent encore dans le bucket.
  // S'ils sont déjà absents, ils sont considérés comme supprimés. Si l'appel `list`
  // échoue, on ne peut pas conclure : le fichier reste dans la file avec l'erreur.
  const stillThere: { id: string; path: string; errorMessage: string }[] = [];
  for (const r of missing) {
    const slash = r.path.lastIndexOf("/");
    const folder = slash >= 0 ? r.path.slice(0, slash) : "";
    const fileName = slash >= 0 ? r.path.slice(slash + 1) : r.path;
    const { data: listing, error: listError } = await supabase.storage
      .from("submission-attachments")
      .list(folder, { search: fileName, limit: 100 });
    if (listError) {
      stillThere.push({ id: r.id, path: r.path, errorMessage: listError.message });
    } else if ((listing ?? []).some((o) => o.name === fileName)) {
      stillThere.push({ id: r.id, path: r.path, errorMessage: "Fichier non supprimé par le stockage" });
    } else {
      done.push(r);
    }
  }
  if (done.length) {
    const donePaths = done.map((r) => r.path);
    const { error: linkError } = await supabase
      .from("submissions")
      .update({ attachment_path: null, attachment_name: null })
      .in("attachment_path", donePaths);
    if (linkError) throw linkError;
    const { error: delError } = await supabase
      .from("attachment_deletion_queue")
      .delete()
      .in("id", done.map((r) => r.id));
    if (delError) throw delError;
  }
  if (stillThere.length) {
    for (const r of stillThere) {
      await supabase
        .from("attachment_deletion_queue")
        .update({ last_error: r.errorMessage })
        .eq("id", r.id);
    }
  }
  return { deleted: done.length, remaining: stillThere.length };
}

export async function countAttachmentDeletionQueue(): Promise<number> {
  const { count, error } = await supabase
    .from("attachment_deletion_queue")
    .select("id", { count: "exact", head: true })
    .lte("delete_after", new Date().toISOString());
  if (error) throw error;
  return count ?? 0;
}

export type DepartureDocument = {
  submission_id: string;
  path: string;
  name: string | null;
  created_at: string;
  excerpt: string;
};

export type DepartureNotice = {
  id: string;
  departing_label: string;
  departure_date: string;
  kind: "préavis" | "sans préavis";
  documents: DepartureDocument[];
  created_at: string;
  reminder_at: string | null;
};

export async function fetchMyDepartureNotices(email: string): Promise<DepartureNotice[]> {
  const { data, error } = await supabase
    .from("departure_notices")
    .select("id, departing_label, departure_date, kind, documents, created_at, reminder_at")
    .eq("recipient_email", email.toLowerCase())
    .is("closed_at", null)
    .is("downloaded_at", null)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as DepartureNotice[];
}

export async function markDepartureNoticeDownloaded(id: string) {
  const { error } = await supabase.rpc("mark_departure_notice_downloaded", { _id: id });
  if (error) throw error;
}

export async function downloadDepartureZip(notice: DepartureNotice) {
  const JSZip = await loadBrowserLib<typeof import("jszip")>("/vendor/jszip-3.10.2.min.js", "JSZip");
  const zip = new JSZip();
  const used = new Set<string>();
  for (const d of notice.documents) {
    const { data, error } = await supabase.storage.from("submission-attachments").download(d.path);
    if (error) throw error;
    const safe = d.excerpt.replace(/[\\/:*?"<>|\n\r]+/g, " ").trim().slice(0, 60) || "document";
    let name = `${d.created_at.slice(0, 10)} - ${safe}.pdf`;
    let i = 2;
    while (used.has(name)) name = `${d.created_at.slice(0, 10)} - ${safe} (${i++}).pdf`;
    used.add(name);
    zip.file(name, data);
  }
  const blob = await zip.generateAsync({ type: "blob" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `documents - ${notice.departing_label}.zip`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";
import {
  ATTACHMENT_BUCKET,
  MAX_ATTACHMENT_BYTES,
  type BlockerSeverity,
  type Submission,
  type SubmissionKind,
} from "@/lib/dashboard";
import { isLate } from "@/lib/recap";
export { isLate };

const db = supabase;
type Enums = Database["public"]["Enums"];

export const ADMIN_LABEL = "Administration HappyPlace";
export const KIND_LABELS: Record<SubmissionKind, string> = {
  idée: "Idée",
  "point bloquant": "Point bloquant",
};

/** Nom, prénom et équipe du compte connecté : repris dans « Soumettre » (C4). */
export type MyProfile = { fullName: string; team: string | null };

export async function fetchMyProfile(email: string): Promise<MyProfile> {
  const { data, error } = await db
    .from("allowed_users")
    .select("first_name, last_name, team")
    .eq("email", email.toLowerCase())
    .maybeSingle();
  if (error) throw error;
  const fullName = [data?.first_name, data?.last_name].filter(Boolean).join(" ").trim();
  return { fullName: fullName || email, team: data?.team ?? null };
}

/** Managers de l'équipe (collaborateur : la sienne ; manager : l'équipe choisie). */
export async function fetchAssigneeNames(team: string | null): Promise<string[]> {
  const { data, error } = await db.rpc("submission_assignees", { _team: team });
  if (error) throw error;
  return (data ?? []).map((r) => r.full_name);
}

/** Texte « Assigné à » selon le type et les managers de l'équipe (US30). */
export function assigneeLine(kind: SubmissionKind, managers: string[]): string {
  const list = managers.join(", ");
  if (managers.length === 0) return ADMIN_LABEL;
  return kind === "point bloquant" ? `${list} · ${ADMIN_LABEL}` : list;
}

export function assigneeHint(kind: SubmissionKind, managers: string[]): string {
  if (kind === "point bloquant")
    return "La première personne qui le traite le publie ou le refuse. Vous serez en copie de l'e-mail.";
  return managers.length === 0
    ? "Aucun manager inscrit dans votre équipe : l'administration examinera votre idée."
    : "Vos managers examineront votre idée.";
}

export async function fetchTeamNames(): Promise<string[]> {
  const { data, error } = await db.from("teams").select("name").order("name");
  if (error) throw error;
  return (data ?? []).map((t) => t.name);
}

/** Équipes qui ont au moins un manager inscrit (lisible par l'admin seulement). */
export async function fetchTeamsWithManager(): Promise<Set<string>> {
  const { data, error } = await db.from("manager_teams").select("team");
  if (error) throw error;
  return new Set((data ?? []).map((r) => r.team.toLowerCase()));
}

export type QueueFilter = "tous" | "point bloquant" | "idée";

/** Points bloquants en tête, puis du plus ancien au plus récent dans chaque type (US63). */
export function sortQueue<T extends Pick<Submission, "kind" | "created_at">>(items: T[]): T[] {
  return [...items].sort((a, b) => {
    if (a.kind !== b.kind) return a.kind === "point bloquant" ? -1 : 1;
    return b.created_at.localeCompare(a.created_at);
  });
}

export function countByKind(items: Pick<Submission, "kind">[]) {
  const blockers = items.filter((s) => s.kind === "point bloquant").length;
  return { blockers, ideas: items.length - blockers };
}

/** File de l'admin (option A) : tous les points bloquants, et les idées des équipes sans manager. */
export function adminQueue(items: Submission[], teamsWithManager: Set<string>): Submission[] {
  return items.filter(
    (s) => s.kind === "point bloquant" || !teamsWithManager.has(s.team.toLowerCase()),
  );
}

export async function publishBlocker(input: {
  submissionId: string;
  title: string;
  department: string;
  severity: BlockerSeverity;
  /** US71 : description reformulée pour le point publié ; absente, le texte de l'auteur est repris. */
  description?: string | null;
}): Promise<string> {
  const { data, error } = await db.rpc("publish_blocker_submission", {
    _submission_id: input.submissionId,
    _title: input.title,
    _department: input.department,
    _severity: input.severity,
    _description: input.description ?? null,
  });
  if (error) throw error;
  return data;
}

export async function saveProposedTitle(submissionId: string, title: string | null, byAi: boolean) {
  const { error } = await db.rpc("save_proposed_title", {
    _submission_id: submissionId,
    _title: title,
    _by_ai: byAi,
  });
  if (error) throw error;
}

type PublishedBlocker = {
  description: string | null;
  severity: BlockerSeverity;
  department: string;
};

/**
 * Ce que le manager ou l'admin a changé en publiant un point bloquant (US71) :
 * description, sévérité, pôle. Comparaison entre la soumission de l'auteur et le point publié.
 */
export function publishedChanges(s: Submission, b: PublishedBlocker | undefined): string[] {
  if (!b || s.kind !== "point bloquant") return [];
  const out: string[] = [];
  if ((b.description ?? "").trim() !== s.content.trim()) out.push("description");
  if (s.severity && b.severity !== s.severity) out.push("sévérité");
  // Une soumission de l'admin porte l'équipe « Admin » : son pôle est toujours choisi à la publication.
  if (s.team !== "Admin" && b.department.trim().toLowerCase() !== s.team.trim().toLowerCase())
    out.push("pôle");
  return out;
}

async function fetchPublishedBlockers(ids: string[]) {
  const map = new Map<
    string,
    PublishedBlocker & { status: Enums["blocker_status"]; updated_at: string }
  >();
  if (ids.length === 0) return map;
  const { data } = await db
    .from("blockers")
    .select("id, status, updated_at, description, severity, department")
    .in("id", ids);
  for (const b of data ?? []) map.set(b.id, b);
  return map;
}

export type MySubmission = Submission & {
  last_change_at: string;
  blocker_status: Enums["blocker_status"] | null;
  blocker_updated_at: string | null;
};

/**
 * Filtre de statut de « Mes soumissions » (US67) : « validée » s'affiche « Publiée ».
 * US68 : « archivée » regroupe les soumissions refusées que l'auteur a archivées ;
 * elles sortent de « Refusée » et de « Tous les statuts ».
 */
export type MyStatusFilter = "tous" | "en attente" | "validée" | "refusée" | "archivée";

export const MY_STATUS_LABELS: Record<Exclude<MyStatusFilter, "tous" | "archivée">, string> = {
  "en attente": "en attente",
  validée: "publiée",
  refusée: "refusée",
};

/**
 * « Mes soumissions » : type, statut, date du dernier changement, statut du point créé (US33).
 * Les filtres de statut et de type s'appliquent dans la requête (US67) : les 10 plus récentes
 * de chaque filtre, pas un tri des 10 plus récentes tous statuts confondus.
 */
export async function fetchMySubmissionsDetailed(
  email: string,
  filters: { status?: MyStatusFilter; kind?: "tous" | SubmissionKind } = {},
): Promise<MySubmission[]> {
  let query = db.from("submissions").select("*").ilike("submitted_by_email", email);
  if (filters.status === "archivée") {
    query = query.eq("status", "refusée").not("archived_at", "is", null);
  } else {
    query = query.is("archived_at", null);
    if (filters.status && filters.status !== "tous") query = query.eq("status", filters.status);
  }
  if (filters.kind && filters.kind !== "tous") query = query.eq("kind", filters.kind);
  const { data, error } = await query.order("created_at", { ascending: false }).limit(10);
  if (error) throw error;
  const rows = (data ?? []) as Submission[];
  if (rows.length === 0) return [];

  const changes = new Map<string, string>();
  const { data: hist } = await db
    .from("submission_status_history")
    .select("submission_id, changed_at")
    .in(
      "submission_id",
      rows.map((r) => r.id),
    )
    .order("changed_at", { ascending: true });
  for (const h of hist ?? []) changes.set(h.submission_id, h.changed_at);

  const blockers = await fetchPublishedBlockers(
    rows.map((r) => r.blocker_id).filter((id): id is string => !!id),
  );

  return rows.map((r) => {
    const b = r.blocker_id ? blockers.get(r.blocker_id) : undefined;
    const last = [changes.get(r.id) ?? r.created_at, b?.updated_at]
      .filter(Boolean)
      .sort()
      .at(-1) as string;
    return {
      ...r,
      last_change_at: last,
      blocker_status: b?.status ?? null,
      blocker_updated_at: b?.updated_at ?? null,
      published_changes: publishedChanges(r, b),
    };
  });
}

/**
 * US70 : vue « Soumissions d'équipes » hors « En attente », en lecture seule.
 * Manager : ses équipes seulement (la base laisse aussi lire les idées validées de tout le cabinet) ;
 * admin (`teams` à null) : toutes les équipes. Les 20 plus récentes du filtre choisi.
 */
export async function fetchTeamSubmissions(
  teams: string[] | null,
  filters: { status: MyStatusFilter; kind: "tous" | SubmissionKind },
): Promise<Submission[]> {
  let query = db.from("submissions").select("*");
  if (teams) query = query.in("team", teams);
  if (filters.status === "archivée") {
    query = query.eq("status", "refusée").not("archived_at", "is", null);
  } else {
    query = query.is("archived_at", null);
    if (filters.status !== "tous") query = query.eq("status", filters.status);
  }
  if (filters.kind !== "tous") query = query.eq("kind", filters.kind);
  const { data, error } = await query.order("created_at", { ascending: false }).limit(20);
  if (error) throw error;
  const rows = (data ?? []) as Submission[];
  const blockers = await fetchPublishedBlockers(
    rows.map((r) => r.blocker_id).filter((id): id is string => !!id),
  );
  return rows.map((r) => ({
    ...r,
    published_changes: publishedChanges(r, r.blocker_id ? blockers.get(r.blocker_id) : undefined),
  }));
}

/**
 * US64 révisée : envoie le récap au manager connecté, par la table d'envoi et le scénario Make R7.
 * La base choisit le destinataire (le manager lui-même) : l'app ne peut pas viser une autre adresse.
 */
export async function sendTeamRecapEmail(objet: string, html: string) {
  const { error } = await db.rpc("send_team_recap_email", { _objet: objet, _html: html });
  if (error) throw error;
}

/* ---------- US68 : modifier et renvoyer une soumission refusée, ou l'archiver ---------- */

export type ResubmitInput = {
  id: string;
  kind: SubmissionKind;
  severity: BlockerSeverity | null;
  content: string;
  /** Pièce jointe à garder (chemin actuel) ; null pour la retirer. Ignoré si un fichier est fourni. */
  keptAttachment: { path: string; name: string | null } | null;
};

/** Renvoie une soumission refusée : même circuit qu'un envoi, e-mail « renvoyé après refus ». */
export async function resubmitSubmission(input: ResubmitInput, file?: File | null) {
  let attachment = input.keptAttachment;
  if (file) {
    if (file.type !== "application/pdf") throw new Error("Seuls les fichiers PDF sont acceptés.");
    if (file.size > MAX_ATTACHMENT_BYTES) throw new Error("Le fichier dépasse 20 Mo.");
    const { data: u } = await db.auth.getUser();
    if (!u.user) throw new Error("Session expirée");
    const path = `${u.user.id}/${crypto.randomUUID()}.pdf`;
    const { error: upErr } = await db.storage
      .from(ATTACHMENT_BUCKET)
      .upload(path, file, { contentType: "application/pdf" });
    if (upErr) throw upErr;
    attachment = { path, name: file.name.slice(0, 200) };
  }
  const { error } = await db.rpc("resubmit_submission", {
    _submission_id: input.id,
    _kind: input.kind,
    _severity: input.kind === "point bloquant" ? input.severity : null,
    _content: input.content,
    _attachment_path: attachment?.path ?? null,
    _attachment_name: attachment?.name ?? null,
  });
  if (error) throw error;
}

/** Archive une soumission refusée : elle reste lisible dans le filtre « Archivée ». */
export async function archiveSubmission(id: string) {
  const { error } = await db.rpc("archive_submission", { _submission_id: id });
  if (error) throw error;
}

/* ---------- Suivi des événements (US34) : jamais de contenu saisi ---------- */

export type UsageEvent =
  | "module_viewed"
  | "validated_list_expanded"
  | "submission_type_selected"
  | "submission_sent"
  | "blocker_report_qualified"
  | "ai_suggestion_edited"
  | "team_recap_generated";

export function trackEvent(
  event: UsageEvent,
  module?: string,
  props: Record<string, string | number | boolean> = {},
) {
  // Fire and forget : le suivi ne doit jamais gêner l'utilisateur.
  void db
    .from("usage_events")
    .insert({ event, module: module ?? null, props })
    .then(({ error }) => {
      if (error) console.warn("[usage_events]", error.message);
    });
}

import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";
import type { BlockerSeverity, Submission, SubmissionKind } from "@/lib/dashboard";
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
    return "La première personne qui le traite le publie ou le refuse.";
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
}): Promise<string> {
  const { data, error } = await db.rpc("publish_blocker_submission", {
    _submission_id: input.submissionId,
    _title: input.title,
    _department: input.department,
    _severity: input.severity,
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

export type MySubmission = Submission & {
  last_change_at: string;
  blocker_status: Enums["blocker_status"] | null;
  blocker_updated_at: string | null;
};

/** « Mes soumissions » : type, statut, date du dernier changement, statut du point créé (US33). */
export async function fetchMySubmissionsDetailed(email: string): Promise<MySubmission[]> {
  const { data, error } = await db
    .from("submissions")
    .select("*")
    .ilike("submitted_by_email", email)
    .order("created_at", { ascending: false })
    .limit(10);
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

  const blockerIds = rows.map((r) => r.blocker_id).filter((id): id is string => !!id);
  const blockers = new Map<string, { status: Enums["blocker_status"]; updated_at: string }>();
  if (blockerIds.length) {
    const { data: bl } = await db
      .from("blockers")
      .select("id, status, updated_at")
      .in("id", blockerIds);
    for (const b of bl ?? []) blockers.set(b.id, { status: b.status, updated_at: b.updated_at });
  }

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
    };
  });
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

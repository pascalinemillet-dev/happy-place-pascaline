// Types et mise en forme du récap du point d'équipe (US64), utilisables côté navigateur.

export type RecapRubric = "bloque" | "attend" | "avance";

export type RecapItem = {
  id: string;
  rubric: RecapRubric;
  team: string;
  type: "idée" | "point bloquant";
  title: string;
  /** Début de la description : colonne « Description » du récap sans IA (décision du 2026-11-01). */
  excerpt: string;
  severity: "critical" | "warning" | "info" | null;
  /** Date de départ de l'ancienneté : envoi, ouverture ou publication. */
  since: string;
  /** En attente depuis plus de 5 jours ouvrés (fictif). */
  late: boolean;
  /** Phrase rédigée par l'IA ; null quand l'IA n'a pas répondu. */
  text: string | null;
};

export type RecapResult = {
  generatedAt: string;
  ai: boolean;
  teams: string[];
  items: RecapItem[];
};

export const RUBRIC_LABELS: Record<RecapRubric, string> = {
  bloque: "Ce qui bloque",
  attend: "Ce qui attend",
  avance: "Ce qui a avancé depuis 7 jours",
};

export const RUBRIC_ORDER: RecapRubric[] = ["bloque", "attend", "avance"];

const EXCERPT_LENGTH = 90;

/** Début d'un texte, coupé à 90 caractères avec des points de suspension. */
export function excerptOf(text: string | null | undefined): string {
  const t = (text ?? "").replace(/\s+/g, " ").trim();
  return t.length > EXCERPT_LENGTH ? `${t.slice(0, EXCERPT_LENGTH - 1).trimEnd()}…` : t;
}

export function ageLabel(iso: string, now: Date = new Date()): string {
  const days = Math.max(0, Math.floor((now.getTime() - new Date(iso).getTime()) / 86_400_000));
  if (days === 0) return "aujourd'hui";
  return days === 1 ? "depuis 1 jour" : `depuis ${days} jours`;
}

export function itemLine(i: RecapItem): string {
  return `${i.team} · ${i.text ?? i.excerpt}`;
}

/** Texte brut du récap, pour « Copier » et « M'envoyer par e-mail ». */
export function recapToText(r: RecapResult): string {
  const date = new Date(r.generatedAt).toLocaleString("fr-FR", {
    dateStyle: "long",
    timeStyle: "short",
  });
  const lines = [
    `Point d'équipe · ${r.teams.join(", ")}`,
    `Généré le ${date}${r.ai ? " (rédigé par l'IA)" : ""}`,
    "",
  ];
  for (const rubric of RUBRIC_ORDER) {
    const items = r.items.filter((i) => i.rubric === rubric);
    lines.push(`${RUBRIC_LABELS[rubric].toUpperCase()} (${items.length})`);
    if (items.length === 0) lines.push("- Aucun élément.");
    for (const i of items)
      lines.push(`- ${itemLine(i)}${i.late ? " [en attente depuis plus de 5 jours ouvrés]" : ""}`);
    lines.push("");
  }
  lines.push("À relire avant de le partager.");
  return lines.join("\n");
}

/** Une soumission en attente depuis plus de 5 jours ouvrés (fictif) est signalée. */
export const LATE_AFTER_WORKDAYS = 5;

/** Nombre de jours ouvrés (lundi à vendredi) écoulés entre deux dates. */
export function workdaysBetween(from: Date, to: Date = new Date()): number {
  if (to <= from) return 0;
  let days = 0;
  const cursor = new Date(from);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(to);
  end.setHours(0, 0, 0, 0);
  while (cursor < end) {
    cursor.setDate(cursor.getDate() + 1);
    const d = cursor.getDay();
    if (d !== 0 && d !== 6) days += 1;
  }
  return days;
}

export function isLate(iso: string): boolean {
  return workdaysBetween(new Date(iso)) > LATE_AFTER_WORKDAYS;
}

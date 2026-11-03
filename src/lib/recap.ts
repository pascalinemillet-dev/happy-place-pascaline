// Types et mise en forme du récap du point d'équipe (US64), utilisables côté navigateur.
// Révision du 2026-11-03 (demande de Pascaline) : tableau Kanban en 3 colonnes, une couleur par
// type, l'équipe affichée seulement si le manager en a plusieurs, même mise en forme à la copie.

export type RecapColumn = "attente" | "publiee" | "refusee";

export type RecapItem = {
  id: string;
  column: RecapColumn;
  team: string;
  type: "idée" | "point bloquant";
  title: string;
  /** Début de la description : texte de la carte quand l'IA n'a pas répondu. */
  excerpt: string;
  severity: "critical" | "warning" | "info" | null;
  /** Statut du point bloquant publié (OUVERT, EN COURS, RÉSOLU…) ; null sinon. */
  blockerStatus: string | null;
  /** Date de départ de l'ancienneté : envoi, publication ou refus. */
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

export const COLUMN_LABELS: Record<RecapColumn, string> = {
  attente: "En attente",
  publiee: "Publiée",
  refusee: "Refusée",
};

/** Ce que chaque colonne contient (décision du 2026-11-03). */
export const COLUMN_HINTS: Record<RecapColumn, string> = {
  attente: "Toutes les soumissions à traiter",
  publiee: "Points bloquants encore ouverts et publications des 7 derniers jours",
  refusee: "Refus des 7 derniers jours",
};

export const COLUMN_ORDER: RecapColumn[] = ["attente", "publiee", "refusee"];

/** Couleurs par type, en hexadécimal pour l'e-mail et le presse-papiers (charte de l'app). */
export const TYPE_COLORS: Record<RecapItem["type"], { bg: string; fg: string; edge: string }> = {
  "point bloquant": { bg: "#f6dccb", fg: "#5a3423", edge: "#c98b6b" },
  idée: { bg: "#ebeae6", fg: "#46484c", edge: "#a9aaa6" },
};

export const TYPE_LABELS: Record<RecapItem["type"], string> = {
  "point bloquant": "Point bloquant",
  idée: "Idée",
};

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

/** L'équipe n'est répétée sur les cartes que si le récap couvre plusieurs équipes. */
export function showTeam(r: RecapResult): boolean {
  return r.teams.length > 1;
}

/** Texte de la carte : la phrase de l'IA, sinon le début de la description. */
export function cardText(i: RecapItem): string {
  return i.text ?? i.excerpt;
}

/** Détails d'une carte : équipe (si plusieurs), statut du point, ancienneté, retard. */
export function cardMeta(i: RecapItem, withTeam: boolean, now: Date = new Date()): string[] {
  const meta: string[] = [];
  if (withTeam) meta.push(i.team);
  if (i.blockerStatus) meta.push(i.blockerStatus);
  meta.push(ageLabel(i.since, now));
  if (i.late) meta.push("plus de 5 jours ouvrés");
  return meta;
}

export function itemsOf(r: RecapResult, column: RecapColumn): RecapItem[] {
  return r.items.filter((i) => i.column === column);
}

function recapTitle(r: RecapResult): string {
  return `Point d'équipe · ${r.teams.join(", ")}`;
}

function recapDate(r: RecapResult): string {
  return new Date(r.generatedAt).toLocaleString("fr-FR", { dateStyle: "long", timeStyle: "short" });
}

/** Texte brut du récap : secours de la copie pour les messageries sans mise en forme. */
export function recapToText(r: RecapResult): string {
  const withTeam = showTeam(r);
  const lines = [recapTitle(r), `Généré le ${recapDate(r)}${r.ai ? " (rédigé par l'IA)" : ""}`, ""];
  for (const column of COLUMN_ORDER) {
    const items = itemsOf(r, column);
    lines.push(`${COLUMN_LABELS[column].toUpperCase()} (${items.length})`);
    if (items.length === 0) lines.push("- Aucun élément.");
    for (const i of items) {
      lines.push(`- [${TYPE_LABELS[i.type]}] ${i.title}`);
      lines.push(`  ${cardText(i)}`);
      lines.push(`  ${cardMeta(i, withTeam).join(" · ")}`);
    }
    lines.push("");
  }
  lines.push("À relire avant de le partager.");
  return lines.join("\n");
}

function esc(t: string): string {
  return t
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Récap en HTML à styles en ligne (tableau à 3 colonnes), pour le presse-papiers :
 * collé dans Gmail ou Outlook, il garde les colonnes et les couleurs par type.
 */
export function recapToHtml(r: RecapResult): string {
  const withTeam = showTeam(r);
  const font = "font-family:Arial,Helvetica,sans-serif;";
  const card = (i: RecapItem) => {
    const c = TYPE_COLORS[i.type];
    return (
      `<div style="${font}margin:0 0 8px 0;padding:8px 10px;background:${c.bg};border-left:4px solid ${c.edge};color:#1b1c1c;">` +
      `<div style="font-size:10px;letter-spacing:1px;text-transform:uppercase;color:${c.fg};font-weight:bold;">${esc(TYPE_LABELS[i.type])}</div>` +
      `<div style="font-size:13px;font-weight:bold;margin-top:2px;">${esc(i.title)}</div>` +
      `<div style="font-size:12px;margin-top:2px;">${esc(cardText(i))}</div>` +
      `<div style="font-size:10px;color:#5f6166;margin-top:4px;text-transform:uppercase;">${esc(cardMeta(i, withTeam).join(" · "))}</div>` +
      `</div>`
    );
  };
  const cells = COLUMN_ORDER.map((column) => {
    const items = itemsOf(r, column);
    const body = items.length
      ? items.map(card).join("")
      : `<div style="${font}font-size:12px;color:#5f6166;font-style:italic;">Aucun élément.</div>`;
    return (
      `<td valign="top" width="33%" style="padding:8px;border:1px solid #d9d9d6;">` +
      `<div style="${font}font-size:12px;font-weight:bold;letter-spacing:1px;text-transform:uppercase;margin-bottom:8px;">${esc(COLUMN_LABELS[column])} (${items.length})</div>` +
      body +
      `</td>`
    );
  }).join("");
  return (
    `<div style="${font}color:#1b1c1c;">` +
    `<div style="font-size:18px;font-weight:bold;">${esc(recapTitle(r))}</div>` +
    `<div style="font-size:11px;color:#5f6166;margin:2px 0 10px 0;">Généré le ${esc(recapDate(r))}${r.ai ? " · rédigé par l'IA" : ""}</div>` +
    `<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;table-layout:fixed;"><tr>${cells}</tr></table>` +
    `<div style="font-size:11px;color:#5f6166;margin-top:8px;">Légende : ` +
    `<span style="background:${TYPE_COLORS["point bloquant"].bg};color:${TYPE_COLORS["point bloquant"].fg};padding:1px 4px;">Point bloquant</span> ` +
    `<span style="background:${TYPE_COLORS.idée.bg};color:${TYPE_COLORS.idée.fg};padding:1px 4px;">Idée</span>` +
    ` · À relire avant de le partager.</div>` +
    `</div>`
  );
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

// Appels à l'IA, exécutés côté serveur (Worker Cloudflare). Décision du 2026-11-01 :
// le Worker lit les données sous l'identité de l'utilisateur (RLS), puis les envoie à un
// webhook Make ; le scénario Make appelle OpenAI et renvoie la réponse au Worker.
// La clé OpenAI reste dans Make : elle n'est ni dans le code, ni dans le navigateur.
//
// Règles RGPD de F1 (backlog US31 et US64) :
// - jamais de nom ni d'e-mail d'auteur envoyé à Make ni à l'IA ;
// - les prompts interdisent de reprendre un nom de personne ;
// - sans MAKE_AI_WEBHOOK_URL, l'IA est désactivée : le titre se saisit à la main et le récap
//   s'affiche en tableau.
import { createMiddleware, createServerFn } from "@tanstack/react-start";
import { getRequest } from "@tanstack/react-start/server";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import type { Database } from "@/integrations/supabase/types";
import { excerptOf, isLate, type RecapItem, type RecapResult } from "@/lib/recap";

const MAX_DETAIL = 300;

const withUser = createMiddleware({ type: "function" }).server(async ({ next }) => {
  const url = import.meta.env["VITE_SUPABASE_URL"] || process.env["SUPABASE_URL"];
  const key =
    import.meta.env["VITE_SUPABASE_PUBLISHABLE_KEY"] || process.env["SUPABASE_PUBLISHABLE_KEY"];
  if (!url || !key) throw new Error("Configuration Supabase manquante côté serveur.");
  const token = getRequest()
    ?.headers.get("authorization")
    ?.replace(/^Bearer /, "");
  if (!token || token.split(".").length !== 3) throw new Error("Non autorisé : session absente.");
  // Client authentifié par le jeton de l'utilisateur : les règles RLS s'appliquent à chaque lecture.
  const supabase = createClient<Database>(url, key, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { storage: undefined, persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase.auth.getClaims(token);
  if (error || !data?.claims?.sub) throw new Error("Non autorisé : jeton invalide.");
  return next({ context: { supabase } });
});

export function aiEnabled(): boolean {
  return !!process.env["MAKE_AI_WEBHOOK_URL"];
}

/**
 * Envoie une consigne et un texte au scénario Make « HappyPlace - IA », qui appelle OpenAI
 * (Chat Completions, sans conservation) et renvoie `{ "reponse": "…" }`.
 * Le secret partagé `x-happyplace-secret` empêche quiconque d'autre d'utiliser le scénario.
 * Renvoie null si Make ou l'IA ne répond pas : l'appelant affiche alors la version sans IA.
 */
async function askAi(
  tache: "titre" | "recap",
  consigne: string,
  texte: string,
  json: boolean,
): Promise<string | null> {
  const url = process.env["MAKE_AI_WEBHOOK_URL"];
  if (!url) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 40_000);
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-happyplace-secret": process.env["MAKE_AI_SECRET"] ?? "",
      },
      body: JSON.stringify({ tache, consigne, texte, format_json: json }),
      signal: controller.signal,
    });
    if (!res.ok) {
      console.error("[make-ia]", tache, res.status);
      return null;
    }
    const raw = await res.text();
    let reponse: unknown = raw;
    try {
      const body = JSON.parse(raw) as { reponse?: unknown };
      if (body && typeof body === "object" && "reponse" in body) reponse = body.reponse;
    } catch {
      // Make peut renvoyer le texte brut : on le garde tel quel.
    }
    // Make répond « Accepted » quand le scénario est arrêté ou que le filtre a bloqué l'appel :
    // ce n'est pas une réponse de l'IA.
    if (typeof reponse !== "string" || !reponse.trim() || reponse.trim() === "Accepted") return null;
    return reponse.trim();
  } catch (e) {
    console.error("[make-ia]", tache, (e as Error).name);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Garde l'objet JSON d'une réponse, même entouré de texte ou de balises ```json. */
function jsonPart(raw: string): string {
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  return start >= 0 && end > start ? raw.slice(start, end + 1) : raw;
}

/** Consigne du titre (US31) : versionnée ici, envoyée à Make à chaque appel. */
export const PROMPT_TITRE =
  "Tu rédiges des titres de points bloquants pour un tableau de bord interne. " +
  "Donne un titre factuel en français, 80 caractères au plus, sans point final ni guillemets. " +
  "Reprends seulement les faits de la description : n'ajoute ni cause, ni conséquence, ni détail " +
  "qui n'y figure pas. Si la description est vague, le titre reste vague. " +
  "N'écris jamais de nom ni de prénom de personne, même si la description en contient : " +
  "remplace-le par un rôle ou une équipe. Réponds uniquement par le titre.";

/** Consigne du récap (US64) : versionnée ici, envoyée à Make à chaque appel. */
export const PROMPT_RECAP =
  "Tu prépares le point d'équipe d'un manager. Tu reçois une liste d'éléments en JSON. " +
  "Pour chaque élément, écris UNE phrase en français de 25 mots au plus qui dit ce que c'est " +
  "et ce qu'il faut en retenir. N'indique ni équipe ni durée : l'application les ajoute. " +
  "Reprends seulement les faits du titre et de la description : n'ajoute ni cause, ni conséquence, " +
  "ni urgence, ni détail qui n'y figure pas. Si un élément est vague, la phrase reste vague. " +
  "N'écris jamais de nom ni de prénom de personne, même si une description en contient : " +
  "remplace-le par un rôle ou une équipe. " +
  'Réponds uniquement en JSON : {"items":[{"id":"…","text":"…"}]}, avec les mêmes id.';

/* ---------- US31 : titre proposé à partir de la description ---------- */

export type TitleSuggestion = {
  title: string | null;
  byAi: boolean;
  state: "ok" | "disabled" | "failed" | "unavailable";
};

export const suggestBlockerTitle = createServerFn({ method: "POST" })
  .middleware([withUser])
  .inputValidator(z.object({ submissionId: z.string().uuid() }))
  .handler(async ({ data, context }): Promise<TitleSuggestion> => {
    const { supabase } = context;
    const { data: s } = await supabase
      .from("submissions")
      .select("id, kind, status, content, proposed_title, proposed_title_by_ai")
      .eq("id", data.submissionId)
      .maybeSingle();
    if (!s || s.kind !== "point bloquant" || s.status !== "en attente") {
      return { title: null, byAi: false, state: "unavailable" };
    }
    if (s.proposed_title)
      return { title: s.proposed_title, byAi: s.proposed_title_by_ai, state: "ok" };
    if (!aiEnabled()) return { title: null, byAi: false, state: "disabled" };

    // Seule la description part chez Make et OpenAI, sans nom, e-mail ni équipe de l'auteur.
    const raw = await askAi("titre", PROMPT_TITRE, s.content.slice(0, 2000), false);
    const title = raw?.replace(/^["«\s]+|["»\s.]+$/g, "").slice(0, 160) || null;
    if (!title) return { title: null, byAi: false, state: "failed" };
    const { error } = await supabase.rpc("save_proposed_title", {
      _submission_id: s.id,
      _title: title,
      _by_ai: true,
    });
    if (error) console.error("[save_proposed_title]", error.message);
    return { title, byAi: true, state: "ok" };
  });

/* ---------- US64 : récap du point d'équipe, à la demande du manager ---------- */

type Draft = Omit<RecapItem, "text"> & { detail: string };

function sinceDays(n: number) {
  return new Date(Date.now() - n * 86_400_000).toISOString();
}

export const generateTeamRecap = createServerFn({ method: "POST" })
  .middleware([withUser])
  .handler(async ({ context }): Promise<RecapResult> => {
    const { supabase } = context;
    // RLS : un manager ne lit que ses propres équipes, et les soumissions de ses équipes.
    const { data: mt, error: mtErr } = await supabase.from("manager_teams").select("team");
    if (mtErr) throw new Error(mtErr.message);
    const teams = [...new Set((mt ?? []).map((t) => t.team))].sort();
    if (teams.length === 0)
      throw new Error("Le récap est réservé aux managers qui ont une équipe.");
    const lower = new Set(teams.map((t) => t.toLowerCase()));
    const week = sinceDays(7);
    const drafts: Draft[] = [];

    const { data: pending } = await supabase
      .from("submissions")
      .select("id, kind, team, content, severity, proposed_title, created_at")
      .eq("status", "en attente");
    for (const s of pending ?? []) {
      if (!lower.has(s.team.toLowerCase())) continue;
      drafts.push({
        id: `s-${s.id}`,
        rubric: "attend",
        team: s.team,
        type: s.kind,
        title: s.proposed_title || excerptOf(s.content),
        excerpt: excerptOf(s.content),
        severity: s.severity,
        since: s.created_at,
        late: isLate(s.created_at),
        detail: s.content.slice(0, MAX_DETAIL),
      });
    }

    const { data: blockers } = await supabase
      .from("blockers")
      .select("id, title, description, department, severity, status, created_at, updated_at");
    for (const b of blockers ?? []) {
      if (!lower.has(b.department.toLowerCase())) continue;
      const base = {
        team: b.department,
        type: "point bloquant" as const,
        title: b.title,
        excerpt: excerptOf(b.description || b.title),
        severity: b.severity,
        late: false,
        detail: (b.description ?? "").slice(0, MAX_DETAIL),
      };
      if (b.status !== "RÉSOLU") {
        drafts.push({ ...base, id: `b-${b.id}`, rubric: "bloque", since: b.created_at });
      }
      if (b.created_at >= week || (b.status === "RÉSOLU" && b.updated_at >= week)) {
        drafts.push({
          ...base,
          id: `a-${b.id}`,
          rubric: "avance",
          since: b.status === "RÉSOLU" ? b.updated_at : b.created_at,
          title: b.status === "RÉSOLU" ? `${b.title} (résolu)` : `${b.title} (publié)`,
          excerpt: `${base.excerpt} (${b.status === "RÉSOLU" ? "résolu" : "publié"})`,
        });
      }
    }

    const { data: hist } = await supabase
      .from("submission_status_history")
      .select("submission_id, changed_at")
      .eq("new_status", "validée")
      .gte("changed_at", week);
    const validatedIds = [...new Set((hist ?? []).map((h) => h.submission_id))];
    if (validatedIds.length) {
      const { data: ideas } = await supabase
        .from("submissions")
        .select("id, team, content, created_at")
        .in("id", validatedIds)
        .eq("kind", "idée");
      for (const s of ideas ?? []) {
        if (!lower.has(s.team.toLowerCase())) continue;
        drafts.push({
          id: `v-${s.id}`,
          rubric: "avance",
          team: s.team,
          type: "idée",
          title: `${excerptOf(s.content)} (validée)`,
          excerpt: `${excerptOf(s.content)} (validée)`,
          severity: null,
          since: hist?.find((h) => h.submission_id === s.id)?.changed_at ?? s.created_at,
          late: false,
          detail: s.content.slice(0, MAX_DETAIL),
        });
      }
    }

    // Make et l'IA ne reçoivent ni nom, ni e-mail, ni équipe, ni durée : seulement l'id, la rubrique,
    // le type, la sévérité, le titre et la description.
    const texts = new Map<string, string>();
    let ai = false;
    if (drafts.length && aiEnabled()) {
      const payload = drafts.map((d) => ({
        id: d.id,
        rubrique: d.rubric,
        type: d.type,
        severite: d.severity,
        titre: d.title,
        description: d.detail,
      }));
      const raw = await askAi("recap", PROMPT_RECAP, JSON.stringify(payload), true);
      try {
        const parsed = raw
          ? (JSON.parse(jsonPart(raw)) as { items?: { id?: unknown; text?: unknown }[] })
          : null;
        for (const it of parsed?.items ?? []) {
          if (typeof it.id === "string" && typeof it.text === "string" && it.text.trim()) {
            texts.set(it.id, it.text.trim().slice(0, 300));
          }
        }
        ai = texts.size > 0;
      } catch {
        ai = false;
      }
    }

    const items: RecapItem[] = drafts.map(({ detail: _detail, ...d }) => ({
      ...d,
      text: ai ? (texts.get(d.id) ?? null) : null,
    }));
    return { generatedAt: new Date().toISOString(), ai, teams, items };
  });

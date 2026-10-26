import { Fragment } from "react";

// http(s):// ou www. jusqu'au prochain espace ; la ponctuation finale est retirée ensuite.
const URL_RE = /\b(?:https?:\/\/|www\.)[^\s<>"]+/gi;
const TRAILING = /[.,;:!?)\]}'»"…]+$/;

/** Transforme les adresses web du texte en liens (morceaux React, aucun HTML injecté). */
export function Linkify({ text }: { text: string }) {
  const parts: React.ReactNode[] = [];
  let last = 0;
  for (const m of text.matchAll(URL_RE)) {
    const start = m.index ?? 0;
    let raw = m[0];
    const trail = raw.match(TRAILING)?.[0] ?? "";
    if (trail) raw = raw.slice(0, -trail.length);
    if (!raw || /^www\.$/i.test(raw)) continue;
    const href = /^www\./i.test(raw) ? `https://${raw}` : raw;
    let safe: string | null = null;
    try {
      const u = new URL(href);
      if (u.protocol === "http:" || u.protocol === "https:") safe = u.href;
    } catch {
      safe = null;
    }
    if (!safe) continue;
    if (start > last) parts.push(text.slice(last, start));
    parts.push(
      <a
        key={start}
        href={safe}
        target="_blank"
        rel="noopener noreferrer"
        className="text-primary underline underline-offset-2 wrap-anywhere not-italic"
        onClick={(e) => e.stopPropagation()}
      >
        {raw}
      </a>,
    );
    last = start + raw.length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return <Fragment>{parts}</Fragment>;
}

import { useEffect, useRef, useState } from "react";
import { Linkify } from "@/components/linkify";

const REJECTION_NOTE_DB_MSG = "La raison du refus ne doit pas dépasser 500 caractères.";

/** Traduit l'erreur de contrainte de longueur de la raison du refus. */
export function rejectionErrorMessage(e: unknown): string {
  const msg = (e as Error)?.message ?? String(e);
  if (msg.includes("submissions_rejection_note_max_500")) return REJECTION_NOTE_DB_MSG;
  if (msg.includes("submissions_content_length_check"))
    return "La proposition doit faire entre 5 et 2 000 caractères.";
  return msg;
}

/** Compteur de caractères (espaces de début/fin exclus, comme la base). */
export function CharCounter({ value, max, min }: { value: string; max: number; min?: number }) {
  const n = value.trim().length;
  const over = n > max;
  const under = min !== undefined && n > 0 && n < min;
  const fmt = (x: number) => x.toLocaleString("fr-FR");
  return (
    <div className="mt-1 text-[11px] font-label-sm" aria-live="polite">
      <p className={`text-right ${over ? "text-error font-bold" : "text-on-surface-variant"}`}>
        {fmt(n)} / {fmt(max)}
      </p>
      {over && (
        <p className="text-error">
          {fmt(max)} caractères maximum : supprime {fmt(n - max)} caractère{n - max > 1 ? "s" : ""}.
        </p>
      )}
      {under && <p className="text-error">{min} caractères minimum</p>}
    </div>
  );
}

export function formatExactDate(iso: string) {
  return new Date(iso).toLocaleString("fr-FR", { dateStyle: "long", timeStyle: "short" });
}

/**
 * Aperçu sur 3 lignes. « Voir plus » n'apparaît que si le texte dépasse
 * réellement 3 lignes (recalculé au redimensionnement) et ouvre la fenêtre de lecture.
 */
export function SubmissionPreview({ content, onOpen }: { content: string; onOpen: () => void }) {
  const ref = useRef<HTMLParagraphElement>(null);
  const [overflows, setOverflows] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => setOverflows(el.scrollHeight > el.clientHeight + 1);
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [content]);

  return (
    <div className="min-w-0 space-y-xs">
      <p
        ref={ref}
        className="font-body-sm text-body-sm italic text-on-surface-variant whitespace-pre-line wrap-anywhere line-clamp-3"
      >
        “<Linkify text={content} />”
      </p>
      {overflows && (
        <button
          type="button"
          aria-haspopup="dialog"
          onClick={onOpen}
          className="font-label-sm text-label-sm text-primary font-bold underline-offset-2 hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
        >
          Voir plus
        </button>
      )}
    </div>
  );
}

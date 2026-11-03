import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useEffect, useRef } from "react";
import { useMutation } from "@tanstack/react-query";
import { toast } from "sonner";
import { generateTeamRecap } from "@/lib/ai.functions";
import { sendTeamRecapEmail, trackEvent } from "@/lib/f1";
import {
  COLUMN_HINTS,
  COLUMN_LABELS,
  COLUMN_ORDER,
  TYPE_COLORS,
  TYPE_LABELS,
  cardMeta,
  cardText,
  itemsOf,
  recapToEmail,
  recapToHtml,
  recapToText,
  showTeam,
  type RecapItem,
  type RecapResult,
} from "@/lib/recap";

/** Copie le récap mis en forme (HTML) avec sa version texte ; texte seul si le navigateur refuse. */
async function copyRecap(r: RecapResult): Promise<"html" | "text"> {
  const html = recapToHtml(r);
  const text = recapToText(r);
  if (typeof ClipboardItem !== "undefined" && navigator.clipboard?.write) {
    try {
      await navigator.clipboard.write([
        new ClipboardItem({
          "text/html": new Blob([html], { type: "text/html" }),
          "text/plain": new Blob([text], { type: "text/plain" }),
        }),
      ]);
      return "html";
    } catch {
      // Navigateur sans copie HTML : on retombe sur le texte.
    }
  }
  await navigator.clipboard.writeText(text);
  return "text";
}

/**
 * Panneau « Préparer mon point d'équipe » (US64), révisé le 2026-11-03 : tableau Kanban
 * « En attente », « Publiée », « Refusée », une couleur par type, une phrase de l'IA par carte.
 * « Copier » met le récap en HTML et en texte dans le presse-papiers ; « M'envoyer par e-mail »
 * l'envoie au manager par la table d'envoi et Make (décision de Pascaline du 2026-11-03).
 */
export function TeamRecapPanel({
  open,
  email,
  onClose,
}: {
  open: boolean;
  email: string;
  onClose: () => void;
}) {
  const recap = useMutation({
    mutationFn: () => generateTeamRecap(),
    onSuccess: (r) => trackEvent("team_recap_generated", "point_equipe", { ai: r.ai }),
    onError: (e: unknown) => toast.error((e as Error).message),
  });
  const started = useRef(false);

  // Une génération à chaque ouverture du panneau ; « Régénérer » en relance une autre.
  useEffect(() => {
    if (open && !started.current) {
      started.current = true;
      recap.mutate();
    }
    if (!open) started.current = false;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const r = recap.data;
  const withTeam = r ? showTeam(r) : false;

  async function copy() {
    if (!r) return;
    try {
      const kind = await copyRecap(r);
      toast.success(kind === "html" ? "Récap copié avec sa mise en forme" : "Récap copié (texte)");
      trackEvent("team_recap_generated", "point_equipe", { copied: true });
    } catch {
      toast.error("Copie impossible : sélectionne le texte à la main.");
    }
  }

  // US64 révisée (décision de Pascaline du 2026-11-03) : l'e-mail part par Make, au manager lui-même.
  const send = useMutation({
    mutationFn: (res: RecapResult) =>
      sendTeamRecapEmail(`Point d'équipe · ${res.teams.join(", ")}`, recapToEmail(res)),
    onSuccess: () => {
      toast.success(
        `Récap envoyé à ${email} : il arrive en général en moins d'une minute. S'il n'arrive pas, utilisez « Copier ».`,
        { duration: 8000 },
      );
      trackEvent("team_recap_generated", "point_equipe", { emailed: true });
    },
    onError: (e: unknown) =>
      toast.error(`L'e-mail n'a pas pu être envoyé : ${(e as Error).message}`, { duration: 8000 }),
  });

  return (
    <DialogPrimitive.Root open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/40" />
        <DialogPrimitive.Content className="fixed z-50 inset-y-0 right-0 flex w-full flex-col border-l border-outline-variant bg-surface-container-lowest shadow-lg focus:outline-none lg:w-[64rem]">
          <div className="flex items-start justify-between gap-sm border-b border-outline-variant p-md">
            <div className="min-w-0 space-y-1">
              <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary wrap-anywhere">
                Point d'équipe{r ? ` · ${r.teams.join(", ")}` : ""}
              </DialogPrimitive.Title>
              <DialogPrimitive.Description className="font-label-sm text-label-sm text-on-surface-variant uppercase">
                {r
                  ? `Généré le ${new Date(r.generatedAt).toLocaleString("fr-FR", { dateStyle: "long", timeStyle: "short" })}`
                  : "Récap de votre équipe"}
              </DialogPrimitive.Description>
              <div className="flex flex-wrap items-center gap-xs">
                {r?.ai && (
                  <span className="inline-block bg-tertiary-fixed px-xs font-label-sm text-label-sm text-on-tertiary-fixed">
                    RÉDIGÉ PAR L'IA
                  </span>
                )}
                {r && <Legend />}
              </div>
            </div>
            <DialogPrimitive.Close
              aria-label="Fermer"
              className="text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <span aria-hidden="true" className="material-symbols-outlined">
                close
              </span>
            </DialogPrimitive.Close>
          </div>

          <div className="flex-1 space-y-md overflow-y-auto p-md" aria-busy={recap.isPending}>
            {recap.isPending && (
              <p className="text-body-sm text-on-surface-variant">Préparation du récap…</p>
            )}
            {recap.isError && (
              <p role="alert" className="text-body-sm text-error">
                Le récap n'a pas pu être généré. Réessayez avec « Actualiser ».
              </p>
            )}
            {r && !r.ai && (
              <p className="bg-surface-container p-sm text-body-sm text-on-surface-variant">
                L'IA n'est pas disponible : chaque carte montre le début de la description.
              </p>
            )}
            {r && (
              <div className="grid grid-cols-1 gap-sm md:grid-cols-3">
                {COLUMN_ORDER.map((column) => {
                  const items = itemsOf(r, column);
                  return (
                    <section
                      key={column}
                      aria-label={`${COLUMN_LABELS[column]} (${items.length})`}
                      className="min-w-0 space-y-xs border border-outline-variant bg-surface-container-low p-sm"
                    >
                      <div className="border-b border-outline-variant pb-xs">
                        <h3 className="font-label-md text-label-md text-primary uppercase">
                          {COLUMN_LABELS[column]} ({items.length})
                        </h3>
                        <p className="text-[11px] text-on-surface-variant">
                          {COLUMN_HINTS[column]}
                        </p>
                      </div>
                      {items.length === 0 ? (
                        <p className="text-body-sm text-on-surface-variant italic">
                          Aucun élément.
                        </p>
                      ) : (
                        <ul className="space-y-xs">
                          {items.map((i) => (
                            <RecapCard key={i.id} item={i} withTeam={withTeam} />
                          ))}
                        </ul>
                      )}
                    </section>
                  );
                })}
              </div>
            )}
            {r && (
              <p className="text-[11px] font-label-sm text-on-surface-variant">
                À relire avant de le partager. Les indicateurs seront ajoutés avec leur période.
              </p>
            )}
          </div>

          <div className="space-y-xs border-t border-outline-variant p-md">
            <p className="text-[11px] text-on-surface-variant">
              « M'envoyer par e-mail » vous envoie ce récap, mis en forme, à {email}. Relisez-le
              avant de le transférer. S'il n'arrive pas dans quelques minutes, utilisez « Copier ».
            </p>
            <div className="flex flex-wrap gap-xs">
              <button
                type="button"
                disabled={!r}
                onClick={copy}
                className="border border-outline px-sm py-xs font-label-sm text-label-sm text-primary hover:bg-surface-container disabled:opacity-50"
              >
                COPIER
              </button>
              <button
                type="button"
                disabled={!r || send.isPending}
                onClick={() => r && send.mutate(r)}
                className="border border-outline px-sm py-xs font-label-sm text-label-sm text-primary hover:bg-surface-container disabled:opacity-50"
              >
                {send.isPending ? "ENVOI…" : "M'ENVOYER PAR E-MAIL"}
              </button>
              <button
                type="button"
                disabled={recap.isPending}
                onClick={() => recap.mutate()}
                className="ml-auto bg-primary px-md py-xs font-label-sm text-label-sm text-on-primary disabled:opacity-50"
              >
                {r && !r.ai ? "ACTUALISER" : "RÉGÉNÉRER"}
              </button>
            </div>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

/** Légende des couleurs : le type est aussi écrit sur chaque carte, jamais la couleur seule. */
function Legend() {
  return (
    <span className="flex items-center gap-xs font-label-sm text-label-sm uppercase">
      {(["point bloquant", "idée"] as const).map((t) => (
        <span
          key={t}
          className="px-xs"
          style={{ background: TYPE_COLORS[t].bg, color: TYPE_COLORS[t].fg }}
        >
          {TYPE_LABELS[t]}
        </span>
      ))}
    </span>
  );
}

function RecapCard({ item, withTeam }: { item: RecapItem; withTeam: boolean }) {
  const c = TYPE_COLORS[item.type];
  return (
    <li
      className="space-y-1 p-xs wrap-anywhere"
      style={{ background: c.bg, borderLeft: `4px solid ${c.edge}` }}
    >
      <p className="font-label-sm text-label-sm uppercase" style={{ color: c.fg }}>
        {TYPE_LABELS[item.type]}
      </p>
      <p className="font-body-sm text-body-sm font-bold text-on-surface">{item.title}</p>
      <p className="text-body-sm text-on-surface">{cardText(item)}</p>
      <p className="text-[11px] font-label-sm uppercase text-on-surface-variant">
        {cardMeta(item, withTeam).join(" · ")}
      </p>
    </li>
  );
}

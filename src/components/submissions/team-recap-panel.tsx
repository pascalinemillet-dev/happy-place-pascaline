import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useEffect, useRef } from "react";
import { useMutation } from "@tanstack/react-query";
import { toast } from "sonner";
import { generateTeamRecap } from "@/lib/ai.functions";
import { trackEvent } from "@/lib/f1";
import {
  RUBRIC_LABELS,
  RUBRIC_ORDER,
  ageLabel,
  itemLine,
  recapToText,
  type RecapItem,
  type RecapResult,
} from "@/lib/recap";

/** Panneau « Préparer mon point d'équipe » (US64) : récap à la demande, rédigé par l'IA ou en tableau. */
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

  async function copy() {
    if (!r) return;
    try {
      await navigator.clipboard.writeText(recapToText(r));
      toast.success("Récap copié");
      trackEvent("team_recap_generated", "point_equipe", { copied: true });
    } catch {
      toast.error("Copie impossible : sélectionne le texte à la main.");
    }
  }

  function mail() {
    if (!r) return;
    const subject = `Point d'équipe · ${r.teams.join(", ")}`;
    window.location.href = `mailto:${encodeURIComponent(email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(recapToText(r))}`;
    trackEvent("team_recap_generated", "point_equipe", { emailed: true });
  }

  return (
    <DialogPrimitive.Root open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/40" />
        <DialogPrimitive.Content className="fixed z-50 inset-y-0 right-0 flex w-full flex-col border-l border-outline-variant bg-surface-container-lowest shadow-lg focus:outline-none sm:w-[30rem]">
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
              {r?.ai && (
                <span className="inline-block bg-tertiary-fixed px-xs font-label-sm text-label-sm text-on-tertiary-fixed">
                  RÉDIGÉ PAR L'IA
                </span>
              )}
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
                L'IA n'est pas disponible : voici les données de votre équipe, sans synthèse.
              </p>
            )}
            {r &&
              RUBRIC_ORDER.map((rubric) => {
                const items = r.items.filter((i) => i.rubric === rubric);
                return (
                  <section key={rubric} className="space-y-xs">
                    <h3 className="font-label-md text-label-md text-primary uppercase">
                      {RUBRIC_LABELS[rubric]} ({items.length})
                    </h3>
                    {items.length === 0 ? (
                      <p className="text-body-sm text-on-surface-variant italic">Aucun élément.</p>
                    ) : r.ai ? (
                      <ul className="list-disc space-y-xs pl-md">
                        {items.map((i) => (
                          <li key={i.id} className="text-body-sm text-on-surface wrap-anywhere">
                            {itemLine(i)}
                            {i.late && (
                              <span className="ml-xs bg-tertiary-fixed px-xs font-label-sm text-label-sm text-on-tertiary-fixed">
                                PLUS DE 5 JOURS OUVRÉS
                              </span>
                            )}
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <RecapTable items={items} />
                    )}
                  </section>
                );
              })}
            {r && (
              <p className="text-[11px] font-label-sm text-on-surface-variant">
                À relire avant de le partager. Les indicateurs seront ajoutés avec leur période.
              </p>
            )}
          </div>

          <div className="flex flex-wrap gap-xs border-t border-outline-variant p-md">
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
              disabled={!r}
              onClick={mail}
              className="border border-outline px-sm py-xs font-label-sm text-label-sm text-primary hover:bg-surface-container disabled:opacity-50"
            >
              M'ENVOYER PAR E-MAIL
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
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function RecapTable({ items }: { items: RecapItem[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-body-sm">
        <thead>
          <tr className="border-b border-outline-variant font-label-sm text-label-sm uppercase text-on-surface-variant">
            <th className="py-1 pr-sm font-normal">Équipe</th>
            <th className="py-1 pr-sm font-normal">Description</th>
            <th className="py-1 pr-sm font-normal">Type</th>
            <th className="py-1 font-normal">Ancienneté</th>
          </tr>
        </thead>
        <tbody>
          {items.map((i) => (
            <tr key={i.id} className="border-b border-outline-variant align-top">
              <td className="py-1 pr-sm">{i.team}</td>
              <td className="py-1 pr-sm wrap-anywhere">{i.excerpt}</td>
              <td className="py-1 pr-sm whitespace-nowrap">
                {i.type === "idée" ? "Idée" : "Point bloquant"}
              </td>
              <td className="py-1 whitespace-nowrap">{ageLabel(i.since)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

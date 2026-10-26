import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Linkify } from "@/components/linkify";
import { formatExactDate } from "@/components/expandable-card";
import { NewsImage, NewsLinks } from "@/components/news-media";
import type { News } from "@/lib/dashboard";

/** Fenêtre de lecture d'une actualité publiée (lecture seule, Échap, clic fond). */
export function NewsReader({ news: n, onClose }: { news: News | null; onClose: () => void }) {
  return (
    <DialogPrimitive.Root open={!!n} onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50" />
        {n && (
          <DialogPrimitive.Content
            className="fixed z-50 inset-0 md:inset-auto md:left-1/2 md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 w-full md:w-[min(48rem,calc(100vw-2rem))] h-dvh md:h-auto md:max-h-[85vh] flex flex-col bg-surface-container-lowest border border-outline shadow-lg focus:outline-none"
          >
            <div className="flex items-start justify-between gap-sm border-b border-outline-variant p-md">
              <div className="min-w-0">
                <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary wrap-anywhere">
                  {n.title}
                </DialogPrimitive.Title>
                <DialogPrimitive.Description className="font-label-sm text-label-sm text-on-surface-variant">
                  Publiée le {formatExactDate(n.created_at)} • Par {n.author}
                </DialogPrimitive.Description>
              </div>
              <DialogPrimitive.Close
                aria-label="Fermer"
                className="text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <span aria-hidden="true" className="material-symbols-outlined">close</span>
              </DialogPrimitive.Close>
            </div>
            <div className="flex-1 overflow-y-auto p-md space-y-md">
              {n.image_path && <NewsImage path={n.image_path} alt={n.title} />}
              {n.body && (
                <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
                  <Linkify text={n.body} />
                </p>
              )}
              <NewsLinks links={n.links} />
            </div>
          </DialogPrimitive.Content>
        )}
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

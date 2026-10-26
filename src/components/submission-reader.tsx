import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Linkify } from "@/components/linkify";
import { AttachmentLink } from "@/components/attachment-link";
import { formatExactDate } from "@/components/expandable-card";
import type { Submission } from "@/lib/dashboard";

/** Grande fenêtre de lecture d'une soumission (focus piégé, Échap, clic fond). */
export function SubmissionReader({
  submission: s,
  statusLabel,
  onClose,
  onReject,
  onApprove,
  approving,
}: {
  submission: Submission | null;
  statusLabel?: string;
  onClose: () => void;
  onReject?: () => void;
  onApprove?: () => void;
  approving?: boolean;
}) {
  return (
    <DialogPrimitive.Root open={!!s} onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50" />
        {s && (
          <DialogPrimitive.Content
            className="fixed z-50 inset-0 md:inset-auto md:left-1/2 md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 w-full md:w-[min(48rem,calc(100vw-2rem))] h-dvh md:h-auto md:max-h-[85vh] flex flex-col bg-surface-container-lowest border border-outline shadow-lg focus:outline-none"
          >
            <div className="flex items-start justify-between gap-sm border-b border-outline-variant p-md">
              <div className="min-w-0">
                <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary wrap-anywhere">
                  {s.author_name}
                </DialogPrimitive.Title>
                <DialogPrimitive.Description className="font-label-sm text-label-sm text-on-surface-variant">
                  {s.team} • {(statusLabel ?? s.status).toUpperCase()} • Soumise le {formatExactDate(s.created_at)}
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
              <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
                <Linkify text={s.content} />
              </p>
              <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
              {s.status === "refusée" && s.rejection_category && (
                <div className="p-sm bg-error-container text-on-error-container text-body-sm wrap-anywhere">
                  <p className="font-bold">Motif : {s.rejection_category}</p>
                  <p className="whitespace-pre-line">Raison : <Linkify text={s.rejection_note ?? ""} /></p>
                </div>
              )}
            </div>
            {(onReject || onApprove) && (
              <div className="flex gap-xs border-t border-outline-variant p-md">
                {onReject && (
                  <button
                    type="button"
                    onClick={onReject}
                    className="flex-1 py-sm border border-outline text-primary font-label-sm text-label-sm hover:bg-surface-container transition-colors"
                  >
                    REFUSER
                  </button>
                )}
                {onApprove && (
                  <button
                    type="button"
                    disabled={approving}
                    onClick={onApprove}
                    className="flex-1 py-sm bg-primary text-on-primary font-label-sm text-label-sm hover:opacity-90 transition-colors disabled:opacity-60"
                  >
                    VALIDER
                  </button>
                )}
              </div>
            )}
          </DialogPrimitive.Content>
        )}
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { downloadAttachment } from "@/lib/dashboard";

const BUCKET = "submission-attachments";

/** Ouvre le PDF dans un nouvel onglet via une URL signée (5 min). L'onglet est
 *  ouvert immédiatement au clic pour éviter le blocage des popups. */
async function openAttachment(path: string) {
  const tab = window.open("", "_blank");
  if (tab) tab.opener = null;
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, 300);
  if (error || !data?.signedUrl) {
    tab?.close();
    toast.error("Impossible d'ouvrir le document. Vérifie tes droits ou réessaie.");
    return;
  }
  if (tab) tab.location.href = data.signedUrl;
  else window.open(data.signedUrl, "_blank", "noopener");
}

export function AttachmentLink({ path, name }: { path?: string | null; name?: string | null }) {
  if (!path) return null;
  const label = name ?? "Document joint";
  return (
    <span className="inline-flex items-center gap-xs mt-xs max-w-full">
      <a
        href="#"
        target="_blank"
        rel="noopener noreferrer"
        onClick={(e) => {
          e.preventDefault();
          void openAttachment(path);
        }}
        className="inline-flex min-w-0 items-center gap-xs text-primary underline font-label-sm text-label-sm"
        title={`Ouvrir ${label} dans un nouvel onglet`}
      >
        <span aria-hidden="true" className="material-symbols-outlined text-sm">picture_as_pdf</span>
        <span className="truncate">{label}</span>
      </a>
      <button
        type="button"
        aria-label={`Télécharger ${label}`}
        title="Télécharger"
        onClick={() => downloadAttachment(path, name ?? null).catch((e) => toast.error((e as Error).message))}
        className="inline-flex items-center text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      >
        <span aria-hidden="true" className="material-symbols-outlined text-sm">download</span>
      </button>
    </span>
  );
}

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Modal } from "@/components/manage/crud-ui";
import { NewsMediaEditor } from "@/components/news-media";
import { emptyMedia, linkErrors, mediaFromNews, toNewsLinks, type MediaDraft } from "@/lib/news-media";
import {
  deleteDraftNews,
  publishDraftNews,
  saveDraftNews,
  timeAgo,
  type News,
} from "@/lib/dashboard";

function Icon({ name, className = "" }: { name: string; className?: string }) {
  return (
    <span aria-hidden="true" className={`material-symbols-outlined ${className}`}>
      {name}
    </span>
  );
}

/**
 * Fenêtre « Créer une actualité » (US66) : titre, contenu, image et liens,
 * puis « Enregistrer en brouillon » ou « Publier ». Sert aussi à modifier un brouillon.
 * La base n'accepte qu'un brouillon à la création pour un manager : « Publier »
 * enregistre le brouillon puis le publie.
 */
export function NewsEditorModal({
  draft,
  author,
  authorEmail,
  onClose,
}: {
  draft: News | null;
  author: string;
  authorEmail: string;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [title, setTitle] = useState(draft?.title ?? "");
  const [body, setBody] = useState(draft?.body ?? "");
  const [media, setMedia] = useState<MediaDraft>(() => (draft ? mediaFromNews(draft) : emptyMedia()));
  const [showErrs, setShowErrs] = useState(false);
  const titleErr = showErrs && !title.trim() ? "Le titre est obligatoire." : undefined;
  const linkErrs = showErrs ? linkErrors(media.links) : {};

  const save = useMutation({
    mutationFn: async (publish: boolean) => {
      const id = await saveDraftNews({
        id: draft?.id,
        title: title.trim(),
        body,
        author,
        author_email: authorEmail,
        links: toNewsLinks(media.links),
        media,
      });
      if (publish) await publishDraftNews(id);
      return publish;
    },
    onSuccess: (published) => {
      toast.success(published ? "Actualité publiée" : "Brouillon enregistré");
      qc.invalidateQueries({ queryKey: ["news"] });
      onClose();
    },
    onError: (e: unknown) => {
      toast.error((e as Error).message);
      // Le brouillon a pu être enregistré avant l'échec de la publication.
      qc.invalidateQueries({ queryKey: ["news"] });
    },
  });

  const submit = (publish: boolean) => {
    setShowErrs(true);
    if (!title.trim()) return;
    if (Object.keys(linkErrors(media.links)).length) {
      toast.error("Corrige les liens invalides avant d'enregistrer.");
      return;
    }
    save.mutate(publish);
  };

  return (
    <Modal title={draft ? "Modifier le brouillon" : "Créer une actualité"} onClose={onClose}>
      <form
        className="space-y-md"
        onSubmit={(e) => {
          e.preventDefault();
          submit(false);
        }}
      >
        <div className="space-y-xs">
          <label htmlFor="news-title" className="font-label-md text-label-md text-on-surface-variant block">
            TITRE
          </label>
          <input
            id="news-title"
            autoFocus
            className="w-full bg-transparent border-b border-outline-variant focus:border-primary focus:outline-none transition-colors font-headline-sm text-headline-sm px-0 py-xs"
            placeholder="Saisis un titre…"
            type="text"
            value={title}
            aria-invalid={!!titleErr}
            onChange={(e) => setTitle(e.target.value)}
          />
          {titleErr && (
            <p role="alert" className="text-body-sm text-error">
              {titleErr}
            </p>
          )}
        </div>
        <div className="space-y-xs">
          <label htmlFor="news-body" className="font-label-md text-label-md text-on-surface-variant block">
            CONTENU
          </label>
          <textarea
            id="news-body"
            className="w-full bg-card border border-outline-variant focus:border-primary focus:outline-none p-sm font-body-md"
            placeholder="Rédige l'actualité…"
            rows={6}
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
        </div>
        <NewsMediaEditor
          value={media}
          onChange={setMedia}
          linkErrs={linkErrs}
          disabled={save.isPending}
          title={title}
        />
        <div className="flex flex-wrap justify-end gap-xs pt-sm border-t border-outline-variant">
          <button
            type="button"
            onClick={onClose}
            className="px-md py-xs text-on-surface-variant font-label-md text-label-md hover:text-primary"
          >
            ANNULER
          </button>
          <button
            type="submit"
            disabled={save.isPending}
            className="px-md py-xs border border-outline text-primary font-label-md text-label-md hover:bg-surface-container disabled:opacity-50"
          >
            {save.isPending && save.variables === false ? "ENREGISTREMENT…" : "ENREGISTRER EN BROUILLON"}
          </button>
          <button
            type="button"
            disabled={save.isPending}
            onClick={() => submit(true)}
            className="px-lg py-xs bg-primary text-on-primary font-label-md text-label-md disabled:opacity-50"
          >
            {save.isPending && save.variables === true ? "PUBLICATION…" : "PUBLIER"}
          </button>
        </div>
      </form>
    </Modal>
  );
}

/**
 * Fenêtre « Brouillons » (US66). La base filtre déjà : l'admin voit les brouillons
 * de tous les managers, le manager ne voit que les siens.
 */
export function NewsDraftsModal({
  drafts,
  isAdmin,
  myEmail,
  onEdit,
  onClose,
}: {
  drafts: News[];
  isAdmin: boolean;
  myEmail: string;
  onEdit: (n: News) => void;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const publish = useMutation({
    mutationFn: publishDraftNews,
    onSuccess: () => {
      toast.success("Actualité publiée");
      qc.invalidateQueries({ queryKey: ["news"] });
    },
    onError: (e: unknown) => toast.error((e as Error).message),
  });
  const remove = useMutation({
    mutationFn: (n: News) => deleteDraftNews(n.id, n.image_path),
    onSuccess: () => {
      toast.success("Brouillon supprimé");
      qc.invalidateQueries({ queryKey: ["news"] });
    },
    onError: (e: unknown) => toast.error((e as Error).message),
  });

  return (
    <Modal title={isAdmin ? "Brouillons des managers et de l'administration" : "Mes brouillons"} onClose={onClose}>
      {drafts.length === 0 ? (
        <p className="text-body-sm text-on-surface-variant italic">Aucun brouillon en attente.</p>
      ) : (
        <ul className="space-y-xs">
          {drafts.map((n) => {
            const own = (n.author_email ?? "").toLowerCase() === myEmail;
            const allowed = isAdmin || own;
            return (
              <li
                key={n.id}
                className="flex flex-col sm:flex-row sm:items-center justify-between gap-sm p-sm bg-surface-container"
              >
                <div className="flex items-center gap-md min-w-0">
                  <Icon name="draft" className="text-on-surface-variant" />
                  <div className="min-w-0">
                    <p className="font-body-md text-primary wrap-anywhere">{n.title}</p>
                    <p className="text-xs text-on-surface-variant uppercase font-label-sm">
                      Créé {timeAgo(n.created_at)} • Par {n.author}
                    </p>
                  </div>
                </div>
                {allowed && (
                  <div className="flex items-center gap-sm shrink-0">
                    <button
                      type="button"
                      className="font-label-sm text-label-sm text-on-surface-variant hover:text-primary"
                      onClick={() => onEdit(n)}
                    >
                      Modifier
                    </button>
                    <button
                      type="button"
                      className="font-label-sm text-label-sm text-error"
                      disabled={remove.isPending}
                      onClick={() => {
                        if (window.confirm(`Supprimer le brouillon « ${n.title} » ?`)) remove.mutate(n);
                      }}
                    >
                      Supprimer
                    </button>
                    <button
                      type="button"
                      className="px-sm py-1 bg-primary text-on-primary font-label-sm text-label-sm disabled:opacity-50"
                      disabled={publish.isPending}
                      onClick={() => {
                        if (window.confirm(`Publier l'actualité « ${n.title} » ? Elle sera visible par tous.`))
                          publish.mutate(n.id);
                      }}
                    >
                      Publier
                    </button>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </Modal>
  );
}

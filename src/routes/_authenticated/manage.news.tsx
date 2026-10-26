import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import {
  ConfirmDelete,
  ErrorSummary,
  Field,
  FormActions,
  Modal,
  RowActions,
  Select,
  TextArea,
  TextInput,
} from "@/components/manage/crud-ui";
import { newsSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import {
  createNews,
  deleteNews,
  fetchAllNews,
  timeAgo,
  updateNews,
  type News,
  type NewsInput,
} from "@/lib/dashboard";
import { NewsImage, NewsLinks, NewsMediaEditor } from "@/components/news-media";
import { emptyMedia, linkErrors, mediaFromNews, toNewsLinks, type MediaDraft } from "@/lib/news-media";

export const Route = createFileRoute("/_authenticated/manage/news")({
  head: () => ({
    meta: [
      { title: "Gestion des actualités — Happy Place" },
      { name: "description", content: "Créez, modifiez et supprimez les actualités de Happy Place." },
      { property: "og:title", content: "Gestion des actualités — Happy Place" },
      { property: "og:description", content: "Gérez les actualités du cabinet de recrutement dans Happy Place." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: ManageNews,
});

const newsStatusLabels: Record<string, string> = {
  brouillon: "Brouillon",
  publiée: "Publiée",
};

const empty: NewsInput = { title: "", body: "", author: "Direction Recrutement", status: "brouillon" };

function ManageNews() {
  const qc = useQueryClient();
  const [form, setForm] = useState<NewsInput | null>(null);
  const [editing, setEditing] = useState<News | null>(null);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [toDelete, setToDelete] = useState<News | null>(null);
  const [media, setMedia] = useState<MediaDraft>(emptyMedia);
  const [showLinkErrs, setShowLinkErrs] = useState(false);

  const list = useQuery({ queryKey: ["news", "all"], queryFn: fetchAllNews, retry: false });
  const invalidate = () => qc.invalidateQueries({ queryKey: ["news"] });
  const onError = (e: unknown) => toast.error((e as Error).message);

  const save = useMutation({
    mutationFn: (input: NewsInput) =>
      editing ? updateNews(editing.id, input, media) : createNews(input, media),
    onSuccess: () => {
      toast.success(editing ? "Actualité modifiée" : "Actualité créée");
      close();
      invalidate();
    },
    onError,
  });

  const remove = useMutation({
    mutationFn: (n: News) => deleteNews(n.id, n.image_path),
    onSuccess: () => {
      toast.success("Actualité supprimée");
      setToDelete(null);
      invalidate();
    },
    onError,
  });

  function close() {
    setForm(null);
    setEditing(null);
    setErrors({});
    setMedia(emptyMedia());
    setShowLinkErrs(false);
  }

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    const res = validate(newsSchema, form);
    if (!res.ok) {
      setErrors(res.errors);
      return;
    }
    setErrors({});
    setShowLinkErrs(true);
    if (Object.keys(linkErrors(media.links)).length) return;
    save.mutate({ ...res.data, links: toNewsLinks(media.links) });
  }

  return (
    <section className="space-y-md">
      <div className="flex items-center justify-between">
        <h2 className="font-headline-sm text-headline-sm text-primary">
          Actualités ({list.data?.length ?? 0})
        </h2>
        <button
          onClick={() => {
            setEditing(null);
            setErrors({});
            setMedia(emptyMedia());
            setShowLinkErrs(false);
            setForm({ ...empty });
          }}
          className="px-md py-xs bg-primary text-on-primary font-label-md text-label-md"
        >
          + NOUVELLE ACTUALITÉ
        </button>
      </div>

      {list.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
      {list.isError && (
        <p className="text-body-sm text-error">Impossible de charger les actualités.</p>
      )}

      <div className="space-y-xs">
        {list.data?.map((n) => (
          <article
            key={n.id}
            className="flex flex-col sm:flex-row items-start justify-between gap-sm p-sm min-w-0 overflow-hidden bg-card border border-outline-variant"
          >
            <div className="min-w-0 flex-1 space-y-xs">
              {n.image_path && <NewsImage path={n.image_path} alt={n.title} />}
              <p className="font-body-md text-primary font-bold wrap-anywhere">{n.title}</p>
              <p className="text-body-sm text-on-surface-variant line-clamp-2 wrap-anywhere">{n.body}</p>
              <NewsLinks links={n.links} />
              <p className="text-[11px] font-label-sm text-on-surface-variant uppercase mt-xs">
                 {newsStatusLabels[n.status] ?? n.status} • {n.author} • {timeAgo(n.created_at)}
              </p>
            </div>
            <RowActions
              onEdit={() => {
                setEditing(n);
                setErrors({});
                setMedia(mediaFromNews(n));
                setShowLinkErrs(false);
                setForm({
                  title: n.title,
                  body: n.body ?? "",
                  author: n.author ?? "",
                  status: n.status,
                });
              }}
              onDelete={() => setToDelete(n)}
            />
          </article>
        ))}
        {list.data?.length === 0 && (
          <p className="text-body-sm italic text-on-surface-variant">Aucune actualité.</p>
        )}
      </div>

      {form && (
        <Modal title={editing ? "Modifier l'actualité" : "Nouvelle actualité"} onClose={close}>
          <form onSubmit={submit} className="space-y-sm" noValidate>
            <ErrorSummary errors={errors} />
            <Field label="Titre" error={errors.title}>
              <TextInput
                value={form.title}
                maxLength={160}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
              />
            </Field>
            <Field label="Contenu" error={errors.body}>
              <TextArea
                rows={5}
                value={form.body}
                maxLength={5000}
                onChange={(e) => setForm({ ...form, body: e.target.value })}
              />
            </Field>
            <Field label="Image et liens">
              <NewsMediaEditor
                value={media}
                onChange={setMedia}
                linkErrs={showLinkErrs ? linkErrors(media.links) : {}}
                disabled={save.isPending}
                title={form.title}
              />
            </Field>
            <Field label="Auteur" error={errors.author}>
              <TextInput
                value={form.author}
                maxLength={80}
                onChange={(e) => setForm({ ...form, author: e.target.value })}
              />
            </Field>
            <Field label="Statut" error={errors.status}>
              <Select
                value={form.status}
                onChange={(e) => setForm({ ...form, status: e.target.value })}
              >
                <option value="brouillon">Brouillon</option>
                <option value="publiée">Publiée</option>
              </Select>
            </Field>
            <FormActions pending={save.isPending} onCancel={close} />
          </form>
        </Modal>
      )}

      {toDelete && (
        <ConfirmDelete
          label={toDelete.title}
          pending={remove.isPending}
          onCancel={() => setToDelete(null)}
          onConfirm={() => remove.mutate(toDelete)}
        />
      )}
    </section>
  );
}

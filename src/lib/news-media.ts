import { supabase } from "@/integrations/supabase/client";

export const NEWS_MEDIA_BUCKET = "news-media";
export const NEWS_IMAGE_MAX_BYTES = 5 * 1024 * 1024;
export const NEWS_IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
export const NEWS_IMAGE_ERROR = "Image JPG, PNG ou WebP, 5 Mo maximum";
export const MAX_NEWS_LINKS = 3;
const EXT: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };

export type NewsLink = { url: string; label?: string | null };
export type LinkDraft = { url: string; label: string };
export type MediaDraft = {
  links: LinkDraft[];
  file: File | null;
  existingPath: string | null;
  removeExisting: boolean;
};

export const emptyMedia = (): MediaDraft => ({ links: [], file: null, existingPath: null, removeExisting: false });

export function mediaFromNews(n: { image_path?: string | null; links?: unknown }): MediaDraft {
  const links = Array.isArray(n.links) ? (n.links as NewsLink[]) : [];
  return {
    links: links.map((l) => ({ url: l.url ?? "", label: l.label ?? "" })),
    file: null,
    existingPath: n.image_path ?? null,
    removeExisting: false,
  };
}

/** Message d'erreur si l'image est refusée, sinon null. */
export function imageError(file: File): string | null {
  if (!(NEWS_IMAGE_TYPES as readonly string[]).includes(file.type)) return NEWS_IMAGE_ERROR;
  if (file.size > NEWS_IMAGE_MAX_BYTES) return NEWS_IMAGE_ERROR;
  return null;
}

/** Normalise une URL saisie (www. → https://). Renvoie null si invalide. */
export function normalizeLinkUrl(raw: string): string | null {
  let v = raw.trim();
  if (!v) return null;
  if (/^www\./i.test(v)) v = `https://${v}`;
  if (!/^https?:\/\//i.test(v) || /\s/.test(v) || v.length > 2000) return null;
  try {
    const u = new URL(v);
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    if (!u.hostname) return null;
  } catch {
    return null;
  }
  return v;
}

export function linkErrors(links: LinkDraft[]): Record<number, string> {
  const errs: Record<number, string> = {};
  links.forEach((l, i) => {
    if (!l.url.trim()) errs[i] = "Adresse obligatoire";
    else if (l.url.trim().length > 2000) errs[i] = "2 000 caractères maximum";
    else if (!normalizeLinkUrl(l.url)) errs[i] = "Adresse invalide : http:// ou https:// uniquement";
    else if (l.label.trim().length > 80) errs[i] = "Libellé : 80 caractères maximum";
  });
  return errs;
}

export function toNewsLinks(links: LinkDraft[]): NewsLink[] {
  return links.slice(0, MAX_NEWS_LINKS).map((l) => {
    const label = l.label.trim();
    return label ? { url: normalizeLinkUrl(l.url)!, label } : { url: normalizeLinkUrl(l.url)! };
  });
}

export function linkDisplay(l: NewsLink): string {
  if (l.label) return l.label;
  try {
    return new URL(l.url).hostname.replace(/^www\./, "");
  } catch {
    return l.url;
  }
}

/** Envoie / remplace / retire l'image après l'enregistrement de l'actualité, puis supprime l'ancien fichier. */
export async function applyNewsImage(newsId: string, media: MediaDraft) {
  const old = media.existingPath;
  if (media.file) {
    const err = imageError(media.file);
    if (err) throw new Error(err);
    const path = `${newsId}/${crypto.randomUUID()}.${EXT[media.file.type]}`;
    const { error: upErr } = await supabase.storage
      .from(NEWS_MEDIA_BUCKET)
      .upload(path, media.file, { contentType: media.file.type });
    if (upErr) throw new Error(`L'image n'a pas pu être envoyée : ${upErr.message}`);
    const { error } = await supabase.from("news").update({ image_path: path }).eq("id", newsId);
    if (error) {
      await supabase.storage.from(NEWS_MEDIA_BUCKET).remove([path]);
      throw error;
    }
    if (old && old !== path) await supabase.storage.from(NEWS_MEDIA_BUCKET).remove([old]);
  } else if (media.removeExisting && old) {
    const { error } = await supabase.from("news").update({ image_path: null }).eq("id", newsId);
    if (error) throw error;
    await supabase.storage.from(NEWS_MEDIA_BUCKET).remove([old]);
  }
}

/** Supprime le fichier image d'une actualité (avant la suppression de la ligne, tant que les droits s'appliquent). */
export async function removeNewsImageFile(path: string | null | undefined) {
  if (!path) return;
  const { error } = await supabase.storage.from(NEWS_MEDIA_BUCKET).remove([path]);
  if (error) throw new Error(`L'image n'a pas pu être supprimée : ${error.message}`);
}

export async function signedNewsImageUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage.from(NEWS_MEDIA_BUCKET).createSignedUrl(path, 3600);
  if (error || !data?.signedUrl) throw error ?? new Error("Image indisponible");
  return data.signedUrl;
}

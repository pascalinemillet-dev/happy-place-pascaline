CREATE TYPE public.rejection_category AS ENUM ('à clarifier', 'en désaccord avec les process', 'doublon', 'autre');
ALTER TABLE public.submissions
  ADD COLUMN rejection_category public.rejection_category,
  ADD COLUMN rejection_note text;
UPDATE public.submissions
  SET rejection_category = 'autre', rejection_note = 'Motif non renseigné (refus antérieur à la mise en place des motifs)'
  WHERE status = 'rejected';
ALTER TABLE public.submissions ADD CONSTRAINT submissions_rejection_reason_check CHECK (
  (status = 'rejected' AND rejection_category IS NOT NULL AND rejection_note IS NOT NULL AND length(btrim(rejection_note)) > 0)
  OR (status <> 'rejected' AND rejection_category IS NULL AND rejection_note IS NULL)
);
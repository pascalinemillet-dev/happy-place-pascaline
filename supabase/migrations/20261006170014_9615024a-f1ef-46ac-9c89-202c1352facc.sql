CREATE TABLE public.attachment_deletion_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path text NOT NULL UNIQUE,
  queued_at timestamptz NOT NULL DEFAULT now(),
  last_error text
);
GRANT SELECT, UPDATE, DELETE ON public.attachment_deletion_queue TO authenticated;
GRANT ALL ON public.attachment_deletion_queue TO service_role;
ALTER TABLE public.attachment_deletion_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage attachment deletion queue" ON public.attachment_deletion_queue
  FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Pièces jointes : fichiers mis en file de suppression, liens retirés (avant l'anonymisation de l'email)
  INSERT INTO public.attachment_deletion_queue (path)
  SELECT attachment_path FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  UPDATE public.submissions
     SET attachment_path = NULL,
         attachment_name = NULL
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL;

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé',
         changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);

  RETURN OLD;
END $function$;
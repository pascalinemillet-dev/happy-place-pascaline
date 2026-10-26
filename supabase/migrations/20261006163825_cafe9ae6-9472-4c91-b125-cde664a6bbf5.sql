CREATE TABLE public.submission_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  old_status public.submission_status,
  new_status public.submission_status NOT NULL,
  changed_by_email text,
  changed_by_name text,
  is_automatic boolean NOT NULL DEFAULT false,
  rejection_category public.rejection_category,
  rejection_note text,
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX submission_status_history_submission_idx
  ON public.submission_status_history (submission_id, changed_at);

GRANT SELECT ON public.submission_status_history TO authenticated;
GRANT ALL ON public.submission_status_history TO service_role;

ALTER TABLE public.submission_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read history of readable submissions" ON public.submission_status_history
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND EXISTS (
    SELECT 1 FROM public.submissions s WHERE s.id = submission_id
  ));

CREATE OR REPLACE FUNCTION private.record_submission_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _name text := coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() -> 'user_metadata' ->> 'name', _email);
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.submission_status_history
      (submission_id, old_status, new_status, changed_by_email, changed_by_name, is_automatic, rejection_category, rejection_note)
    VALUES
      (NEW.id,
       CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
       NEW.status,
       _email,
       CASE WHEN _email IS NULL THEN NULL ELSE _name END,
       _email IS NULL,
       CASE WHEN NEW.status = 'refusée'::public.submission_status THEN NEW.rejection_category END,
       CASE WHEN NEW.status = 'refusée'::public.submission_status THEN NEW.rejection_note END);
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER record_submission_status
  AFTER INSERT OR UPDATE ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.record_submission_status();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
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

INSERT INTO public.submission_status_history (submission_id, old_status, new_status, is_automatic, changed_at)
SELECT id, NULL, status, true, created_at FROM public.submissions;
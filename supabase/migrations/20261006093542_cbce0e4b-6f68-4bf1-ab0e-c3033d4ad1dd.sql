ALTER TYPE public.blocker_status RENAME VALUE 'CRITICAL' TO 'CRITIQUE';
ALTER TYPE public.blocker_status RENAME VALUE 'IN PROGRESS' TO 'EN COURS';
ALTER TYPE public.blocker_status RENAME VALUE 'MONITORING' TO 'SURVEILLANCE';
ALTER TYPE public.blocker_status RENAME VALUE 'SOLVED' TO 'RÉSOLU';

ALTER TYPE public.news_status RENAME VALUE 'draft' TO 'brouillon';
ALTER TYPE public.news_status RENAME VALUE 'published' TO 'publiée';

ALTER TYPE public.submission_status RENAME VALUE 'pending' TO 'en attente';
ALTER TYPE public.submission_status RENAME VALUE 'approved' TO 'validée';
ALTER TYPE public.submission_status RENAME VALUE 'rejected' TO 'refusée';

CREATE OR REPLACE FUNCTION private.set_revalidate_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, private
AS $$
DECLARE
  live text := CASE TG_TABLE_NAME WHEN 'submissions' THEN 'validée' ELSE 'publiée' END;
BEGIN
  IF NEW.status::text = live THEN
    IF TG_OP = 'INSERT' OR OLD.status::text <> live OR NEW.revalidate_at IS NULL THEN
      NEW.revalidate_at := now() + interval '1 year';
    END IF;
  ELSE
    NEW.revalidate_at := NULL;
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE public.submissions
  SET status = 'en attente', revalidate_at = NULL
  WHERE status = 'validée' AND revalidate_at <= now();

  UPDATE public.news
  SET status = 'brouillon', revalidate_at = NULL
  WHERE status = 'publiée' AND revalidate_at <= now();
END
$$;

REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;
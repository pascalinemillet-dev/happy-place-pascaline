ALTER TABLE public.submissions ADD COLUMN revalidate_at timestamptz;
ALTER TABLE public.news ADD COLUMN revalidate_at timestamptz;

CREATE OR REPLACE FUNCTION private.set_revalidate_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, private AS $$
DECLARE
  live text := CASE TG_TABLE_NAME WHEN 'submissions' THEN 'approved' ELSE 'published' END;
BEGIN
  IF NEW.status::text = live THEN
    IF TG_OP = 'INSERT' OR OLD.status::text <> live OR NEW.revalidate_at IS NULL THEN
      NEW.revalidate_at := now() + interval '1 year';
    END IF;
  ELSE
    NEW.revalidate_at := NULL;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER set_revalidate_at BEFORE INSERT OR UPDATE OF status ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.set_revalidate_at();
CREATE TRIGGER set_revalidate_at BEFORE INSERT OR UPDATE OF status ON public.news
FOR EACH ROW EXECUTE FUNCTION private.set_revalidate_at();

UPDATE public.submissions SET revalidate_at = now() + interval '1 year' WHERE status = 'approved';
UPDATE public.news SET revalidate_at = now() + interval '1 year' WHERE status = 'published';

CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  UPDATE public.submissions SET status = 'pending', revalidate_at = NULL
   WHERE status = 'approved' AND revalidate_at <= now();
  UPDATE public.news SET status = 'draft', revalidate_at = NULL
   WHERE status = 'published' AND revalidate_at <= now();
END $$;
REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('expire-revalidations-daily', '0 3 * * *', $$SELECT private.expire_revalidations()$$);
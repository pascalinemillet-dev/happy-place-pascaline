CREATE OR REPLACE FUNCTION private.queue_deleted_submission_attachment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF OLD.attachment_path IS NOT NULL THEN
    INSERT INTO public.attachment_deletion_queue (path, delete_after)
    VALUES (OLD.attachment_path, now())
    ON CONFLICT (path) DO UPDATE SET delete_after = least(public.attachment_deletion_queue.delete_after, now());
  END IF;
  RETURN OLD;
END
$function$;

CREATE TRIGGER queue_deleted_submission_attachment
  AFTER DELETE ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.queue_deleted_submission_attachment();
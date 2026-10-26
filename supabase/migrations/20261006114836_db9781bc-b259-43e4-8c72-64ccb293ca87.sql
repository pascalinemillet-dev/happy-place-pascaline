CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status NOT IN ('validée'::public.submission_status, 'refusée'::public.submission_status) THEN
      RAISE EXCEPTION 'Une soumission ne peut passer qu''à validée ou refusée';
    END IF;
    IF OLD.status <> 'en attente'::public.submission_status THEN
      RAISE EXCEPTION 'Seule une soumission en attente peut être validée ou refusée';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
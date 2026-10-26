CREATE OR REPLACE FUNCTION private.check_blocker_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'RÉSOLU'::public.blocker_status THEN
    RAISE EXCEPTION 'Un point bloquant ne peut pas être créé directement au statut RÉSOLU.';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'OUVERT'::public.blocker_status
     AND NEW.status = 'RÉSOLU'::public.blocker_status THEN
    RAISE EXCEPTION 'Un point bloquant OUVERT doit d''abord passer EN COURS avant d''être RÉSOLU.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER check_blocker_transition
  BEFORE INSERT OR UPDATE OF status ON public.blockers
  FOR EACH ROW EXECUTE FUNCTION private.check_blocker_transition();
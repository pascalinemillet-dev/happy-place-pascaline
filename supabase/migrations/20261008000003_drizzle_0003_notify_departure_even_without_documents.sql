CREATE OR REPLACE FUNCTION private.notify_departure(_user_id uuid, _email text, _team text, _date date, _kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _docs jsonb := private.departure_documents(_email);
BEGIN
  UPDATE public.departure_notices SET closed_at = now()
   WHERE departing_user_id = _user_id AND closed_at IS NULL;
  INSERT INTO public.departure_notices (departing_user_id, departing_label, recipient_email, departure_date, kind, documents)
  SELECT _user_id, _email, rcpt, _date, _kind, _docs FROM private.departure_recipients(_email, _team) AS rcpt;
END $function$;
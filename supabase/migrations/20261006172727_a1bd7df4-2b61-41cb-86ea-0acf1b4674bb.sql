-- Date de départ prévue
ALTER TABLE public.allowed_users ADD COLUMN departure_date date;

CREATE OR REPLACE FUNCTION private.check_departure_date()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'private' AS $function$
BEGIN
  IF NEW.departure_date IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.departure_date IS DISTINCT FROM OLD.departure_date)
     AND NEW.departure_date < current_date + 7 THEN
    RAISE EXCEPTION 'La date de départ doit être au moins 7 jours après aujourd''hui';
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER check_departure_date BEFORE INSERT OR UPDATE OF departure_date ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION private.check_departure_date();

-- Suppression différée des fichiers
ALTER TABLE public.attachment_deletion_queue ADD COLUMN delete_after timestamptz NOT NULL DEFAULT now();

-- Alertes de départ (servent aussi de journal des alertes envoyées)
CREATE TABLE public.departure_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  departing_user_id uuid,
  departing_label text NOT NULL,
  recipient_email text NOT NULL,
  departure_date date NOT NULL,
  kind text NOT NULL CHECK (kind IN ('préavis', 'sans préavis')),
  documents jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  reminder_at timestamptz,
  downloaded_at timestamptz,
  closed_at timestamptz
);
CREATE INDEX departure_notices_open_idx ON public.departure_notices (recipient_email) WHERE closed_at IS NULL;
GRANT SELECT ON public.departure_notices TO authenticated;
GRANT ALL ON public.departure_notices TO service_role;
ALTER TABLE public.departure_notices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Recipients and admins read departure notices" ON public.departure_notices
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND (recipient_email = lower(auth.jwt() ->> 'email') OR private.is_admin()));

-- Destinataires : les managers de l'équipe de la personne qui part, et les admins (sauf elle-même)
CREATE OR REPLACE FUNCTION private.departure_recipients(_email text, _team text)
RETURNS SETOF text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  SELECT DISTINCT u.email
  FROM public.allowed_users u
  JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  LEFT JOIN public.manager_teams mt ON mt.allowed_user_id = u.id
  WHERE lower(u.email) <> lower(_email)
    AND (r.role = 'admin'::public.app_role
         OR (r.role = 'manager'::public.app_role AND _team IS NOT NULL
             AND lower(btrim(mt.team)) = lower(btrim(_team))))
$function$;

CREATE OR REPLACE FUNCTION private.departure_documents(_email text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'submission_id', s.id, 'path', s.attachment_path, 'name', s.attachment_name,
           'created_at', s.created_at, 'excerpt', left(s.content, 60)) ORDER BY s.created_at), '[]'::jsonb)
  FROM public.submissions s
  WHERE lower(s.submitted_by_email) = lower(_email) AND s.attachment_path IS NOT NULL
$function$;

CREATE OR REPLACE FUNCTION private.notify_departure(_user_id uuid, _email text, _team text, _date date, _kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _docs jsonb := private.departure_documents(_email);
BEGIN
  UPDATE public.departure_notices SET closed_at = now()
   WHERE departing_user_id = _user_id AND closed_at IS NULL;
  IF jsonb_array_length(_docs) = 0 THEN RETURN; END IF;
  INSERT INTO public.departure_notices (departing_user_id, departing_label, recipient_email, departure_date, kind, documents)
  SELECT _user_id, _email, rcpt, _date, _kind, _docs FROM private.departure_recipients(_email, _team) AS rcpt;
END $function$;

CREATE OR REPLACE FUNCTION private.on_departure_date_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
BEGIN
  IF NEW.departure_date IS DISTINCT FROM OLD.departure_date THEN
    IF NEW.departure_date IS NULL THEN
      UPDATE public.departure_notices SET closed_at = now()
       WHERE departing_user_id = NEW.id AND closed_at IS NULL;
    ELSE
      PERFORM private.notify_departure(NEW.id, NEW.email, NEW.team, NEW.departure_date, 'préavis');
    END IF;
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER on_departure_date_change AFTER UPDATE OF departure_date ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION private.on_departure_date_change();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _planned boolean := OLD.departure_date IS NOT NULL AND OLD.departure_date <= current_date;
BEGIN
  INSERT INTO public.attachment_deletion_queue (path, delete_after)
  SELECT attachment_path, CASE WHEN _planned THEN now() ELSE now() + interval '7 days' END
    FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  IF _planned THEN
    UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
     WHERE departing_user_id = OLD.id AND closed_at IS NULL;
  ELSE
    PERFORM private.notify_departure(OLD.id, OLD.email, OLD.team, current_date, 'sans préavis');
  END IF;

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé', submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);
  UPDATE public.news
     SET author = 'Utilisateur supprimé', author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);
  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé', changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);
  RETURN OLD;
END $function$;

CREATE OR REPLACE FUNCTION public.mark_departure_notice_downloaded(_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  UPDATE public.departure_notices SET downloaded_at = now()
   WHERE id = _id AND downloaded_at IS NULL
     AND (recipient_email = lower(auth.jwt() ->> 'email') OR private.is_admin());
$function$;
REVOKE ALL ON FUNCTION public.mark_departure_notice_downloaded(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mark_departure_notice_downloaded(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.run_departures()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE u record;
BEGIN
  UPDATE public.departure_notices SET reminder_at = now()
   WHERE closed_at IS NULL AND downloaded_at IS NULL AND reminder_at IS NULL
     AND kind = 'préavis' AND departure_date - 2 <= current_date;

  FOR u IN SELECT id FROM public.allowed_users
            WHERE departure_date IS NOT NULL AND departure_date <= current_date LOOP
    BEGIN
      DELETE FROM public.allowed_users WHERE id = u.id;
    EXCEPTION WHEN others THEN
      RAISE WARNING 'Départ non appliqué pour % : %', u.id, SQLERRM;
    END;
  END LOOP;

  UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
   WHERE closed_at IS NULL AND kind = 'sans préavis' AND created_at <= now() - interval '7 days';
END $function$;
SELECT cron.schedule('run-departures-daily', '15 3 * * *', 'SELECT private.run_departures()');
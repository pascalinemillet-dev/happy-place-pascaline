ALTER TYPE public.blocker_status RENAME VALUE 'CRITIQUE' TO 'OUVERT';
ALTER TABLE public.blockers ALTER COLUMN status SET DEFAULT 'OUVERT'::public.blocker_status;

CREATE OR REPLACE FUNCTION private.set_submission_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(auth.jwt() ->> 'email');
  _role public.app_role;
  _team text;
  _uid uuid;
  _chosen text;
BEGIN
  NEW.submitted_by_email := _email;
  SELECT r.role, u.team, u.id INTO _role, _team, _uid
  FROM public.allowed_users u
  LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  WHERE u.email = _email;
  IF _role = 'collaborateur' THEN
    IF _team IS NULL OR btrim(_team) = '' THEN
      RAISE EXCEPTION 'Aucune équipe n''est associée à ton compte. Contacte un administrateur.';
    END IF;
    NEW.team := _team;
  ELSIF _role = 'manager' THEN
    SELECT mt.team INTO _chosen FROM public.manager_teams mt
     WHERE mt.allowed_user_id = _uid AND lower(btrim(mt.team)) = lower(btrim(coalesce(NEW.team, '')))
     LIMIT 1;
    IF _chosen IS NULL THEN
      RAISE EXCEPTION 'Choisis une de tes équipes pour cette demande.';
    END IF;
    NEW.team := _chosen;
  ELSIF _role = 'admin' THEN
    NEW.team := 'Admin';
  END IF;
  RETURN NEW;
END
$function$;

ALTER TABLE public.manager_teams
  ADD CONSTRAINT manager_teams_not_admin_team CHECK (lower(btrim(team)) <> 'admin');

-- Version élèves : cette tâche planifiée n'existe pas sur une base neuve
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-attachments-daily') THEN
    PERFORM cron.unschedule('purge-attachments-daily');
  END IF;
END $$;
ALTER TABLE public.allowed_users ADD COLUMN team text;

CREATE OR REPLACE FUNCTION private.set_submission_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _email text := lower(auth.jwt() ->> 'email');
  _role public.app_role;
  _team text;
BEGIN
  NEW.submitted_by_email := _email;
  SELECT COALESCE(r.role, u.role), u.team INTO _role, _team
  FROM public.allowed_users u
  LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  WHERE u.email = _email;
  IF _role = 'collaborateur' THEN
    IF _team IS NULL OR btrim(_team) = '' THEN
      RAISE EXCEPTION 'Aucune équipe n''est associée à ton compte. Contacte un administrateur.';
    END IF;
    NEW.team := _team;
  END IF;
  RETURN NEW;
END
$$;
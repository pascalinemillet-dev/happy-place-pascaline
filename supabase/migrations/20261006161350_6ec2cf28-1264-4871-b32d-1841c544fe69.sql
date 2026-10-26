-- Le trigger de protection du dernier admin sur allowed_users lisait l'ancienne colonne.
-- La protection reste assurée par private.protect_last_admin_role() sur allowed_user_roles,
-- qui se déclenche aussi lors d'une suppression en cascade depuis allowed_users.
DROP TRIGGER IF EXISTS protect_last_admin ON public.allowed_users;
DROP FUNCTION IF EXISTS public.protect_last_admin();

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
BEGIN
  NEW.submitted_by_email := _email;
  SELECT r.role, u.team INTO _role, _team
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
$function$;

ALTER TABLE public.allowed_users DROP COLUMN role;
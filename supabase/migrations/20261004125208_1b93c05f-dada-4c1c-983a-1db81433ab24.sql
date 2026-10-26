DROP POLICY "Managers review assigned submissions" ON public.submissions;
DROP POLICY "Allowed read submissions" ON public.submissions;
DROP FUNCTION private.current_app_role();

ALTER TYPE public.app_role RENAME TO app_role_old;
CREATE TYPE public.app_role AS ENUM ('admin', 'manager', 'collaborateur');

ALTER TABLE public.allowed_users ALTER COLUMN role DROP DEFAULT;
ALTER TABLE public.allowed_users ALTER COLUMN role TYPE public.app_role USING role::text::public.app_role;
ALTER TABLE public.allowed_user_roles ALTER COLUMN role TYPE public.app_role USING role::text::public.app_role;
ALTER TABLE public.allowed_users ALTER COLUMN role SET DEFAULT 'collaborateur'::public.app_role;

DROP TYPE public.app_role_old;

CREATE FUNCTION private.current_app_role()
RETURNS public.app_role
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $$
  SELECT aur.role
  FROM public.allowed_users au
  JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
  WHERE au.email = lower(auth.jwt() ->> 'email')
  LIMIT 1
$$;

CREATE POLICY "Allowed read submissions" ON public.submissions
FOR SELECT TO authenticated
USING (private.is_admin() OR ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team)) OR (submitted_by_email = lower((auth.jwt() ->> 'email'::text))) OR (status = 'approved'::text));

CREATE POLICY "Managers review assigned submissions" ON public.submissions
FOR UPDATE TO authenticated
USING ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team) AND (status = 'pending'::text))
WITH CHECK ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team) AND (status = ANY (ARRAY['approved'::text, 'rejected'::text])));
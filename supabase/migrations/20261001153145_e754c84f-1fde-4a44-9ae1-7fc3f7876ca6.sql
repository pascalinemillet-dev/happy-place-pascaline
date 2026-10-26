CREATE TABLE public.allowed_user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  allowed_user_id uuid NOT NULL UNIQUE REFERENCES public.allowed_users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.allowed_user_roles TO authenticated;
GRANT ALL ON public.allowed_user_roles TO service_role;
ALTER TABLE public.allowed_user_roles ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.manager_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  allowed_user_id uuid NOT NULL REFERENCES public.allowed_users(id) ON DELETE CASCADE,
  team text NOT NULL CHECK (char_length(trim(team)) BETWEEN 2 AND 60),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (allowed_user_id, team)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.manager_teams TO authenticated;
GRANT ALL ON public.manager_teams TO service_role;
ALTER TABLE public.manager_teams ENABLE ROW LEVEL SECURITY;

INSERT INTO public.allowed_user_roles (allowed_user_id, role)
SELECT id, CASE WHEN role::text = 'admin' THEN 'admin'::public.app_role ELSE 'collaborateur'::public.app_role END
FROM public.allowed_users
ON CONFLICT (allowed_user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION private.current_app_role()
RETURNS public.app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT aur.role
  FROM public.allowed_users au
  JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
  WHERE au.email = lower(auth.jwt() ->> 'email')
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION private.is_manager_or_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT coalesce(private.current_app_role() IN ('admin'::public.app_role, 'manager'::public.app_role), false)
$$;

CREATE OR REPLACE FUNCTION private.can_review_team(_team text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT coalesce(private.is_admin(), false)
    OR EXISTS (
      SELECT 1
      FROM public.allowed_users au
      JOIN public.allowed_user_roles aur ON aur.allowed_user_id = au.id
      JOIN public.manager_teams mt ON mt.allowed_user_id = au.id
      WHERE au.email = lower(auth.jwt() ->> 'email')
        AND aur.role = 'manager'::public.app_role
        AND lower(mt.team) = lower(_team)
    )
$$;

REVOKE ALL ON FUNCTION private.current_app_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_manager_or_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.can_review_team(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_app_role() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_manager_or_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_review_team(text) TO authenticated;

CREATE POLICY "Admins manage roles"
ON public.allowed_user_roles FOR ALL TO authenticated
USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY "Users see own role"
ON public.allowed_user_roles FOR SELECT TO authenticated
USING (allowed_user_id IN (
  SELECT id FROM public.allowed_users WHERE email = lower(auth.jwt() ->> 'email')
));

CREATE POLICY "Admins manage manager teams"
ON public.manager_teams FOR ALL TO authenticated
USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY "Managers see own teams"
ON public.manager_teams FOR SELECT TO authenticated
USING (allowed_user_id IN (
  SELECT id FROM public.allowed_users WHERE email = lower(auth.jwt() ->> 'email')
));

DROP POLICY IF EXISTS "Allowed read" ON public.news;
CREATE POLICY "Allowed read published news"
ON public.news FOR SELECT TO authenticated
USING (private.is_allowed() AND (status = 'published' OR private.is_admin()));

DROP POLICY IF EXISTS "Allowed read" ON public.submissions;
DROP POLICY IF EXISTS "Admin write" ON public.submissions;
CREATE POLICY "Allowed read submissions"
ON public.submissions FOR SELECT TO authenticated
USING (
  private.is_admin()
  OR (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team))
  OR (private.current_app_role() = 'collaborateur'::public.app_role AND status = 'approved')
);
CREATE POLICY "Allowed create pending submissions"
ON public.submissions FOR INSERT TO authenticated
WITH CHECK (private.is_allowed() AND status = 'pending');
CREATE POLICY "Managers review assigned submissions"
ON public.submissions FOR UPDATE TO authenticated
USING (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status = 'pending')
WITH CHECK (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status IN ('approved', 'rejected'));
CREATE POLICY "Admins manage submissions"
ON public.submissions FOR ALL TO authenticated
USING (private.is_admin()) WITH CHECK (private.is_admin());

CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.status NOT IN ('approved', 'rejected')
       OR OLD.status <> 'pending'
       OR NOT private.can_review_team(OLD.team) THEN
      RAISE EXCEPTION 'Un manager peut uniquement valider ou refuser une soumission en attente de ses équipes';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS enforce_submission_review ON public.submissions;
CREATE TRIGGER enforce_submission_review
BEFORE UPDATE ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.enforce_submission_review();

CREATE OR REPLACE FUNCTION private.protect_last_admin_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF OLD.role = 'admin'::public.app_role
     AND (TG_OP = 'DELETE' OR NEW.role <> 'admin'::public.app_role)
     AND (SELECT count(*) FROM public.allowed_user_roles WHERE role = 'admin'::public.app_role) <= 1 THEN
    RAISE EXCEPTION 'Impossible de retirer le dernier admin';
  END IF;
  RETURN COALESCE(NEW, OLD);
END
$$;

DROP TRIGGER IF EXISTS protect_last_admin_role ON public.allowed_user_roles;
CREATE TRIGGER protect_last_admin_role
BEFORE UPDATE OR DELETE ON public.allowed_user_roles
FOR EACH ROW EXECUTE FUNCTION private.protect_last_admin_role();
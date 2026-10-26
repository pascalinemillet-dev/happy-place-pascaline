CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;
ALTER FUNCTION public.current_app_role() SET SCHEMA private;
ALTER FUNCTION public.is_allowed() SET SCHEMA private;
ALTER FUNCTION public.is_admin() SET SCHEMA private;
ALTER FUNCTION private.current_app_role() SET search_path = public, private;
ALTER FUNCTION private.is_allowed() SET search_path = public, private;
ALTER FUNCTION private.is_admin() SET search_path = public, private;
CREATE OR REPLACE FUNCTION private.is_allowed()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT private.current_app_role() IS NOT NULL
$$;
CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT coalesce(private.current_app_role() = 'admin', false)
$$;
ALTER TABLE public.news ALTER COLUMN status SET DEFAULT 'brouillon'::public.news_status;

CREATE OR REPLACE FUNCTION private.set_news_author_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF NOT private.is_admin() OR NEW.author_email IS NULL THEN
    NEW.author_email := lower(auth.jwt() ->> 'email');
  END IF;
  RETURN NEW;
END $function$;

DROP POLICY IF EXISTS "Allowed read published news" ON public.news;
CREATE POLICY "Allowed read published news" ON public.news
  FOR SELECT TO authenticated
  USING (
    private.is_allowed() AND (
      status = 'publiée'::public.news_status
      OR private.is_admin()
      OR (private.current_app_role() = 'manager'::public.app_role AND author_email = lower(auth.jwt() ->> 'email'))
    )
  );

CREATE POLICY "Manager insert own draft news" ON public.news
  FOR INSERT TO authenticated
  WITH CHECK (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'brouillon'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  );

CREATE POLICY "Manager update own draft news" ON public.news
  FOR UPDATE TO authenticated
  USING (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'brouillon'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  )
  WITH CHECK (
    private.current_app_role() = 'manager'::public.app_role
    AND status IN ('brouillon'::public.news_status, 'publiée'::public.news_status)
    AND author_email = lower(auth.jwt() ->> 'email')
  );

CREATE POLICY "Manager delete own draft news" ON public.news
  FOR DELETE TO authenticated
  USING (
    private.current_app_role() = 'manager'::public.app_role
    AND status = 'brouillon'::public.news_status
    AND author_email = lower(auth.jwt() ->> 'email')
  );
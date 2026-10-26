ALTER TABLE public.submissions ADD COLUMN submitted_by_email text;

CREATE OR REPLACE FUNCTION private.set_submission_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  NEW.submitted_by_email := lower(auth.jwt() ->> 'email');
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS set_submission_owner ON public.submissions;
CREATE TRIGGER set_submission_owner
BEFORE INSERT ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.set_submission_owner();

DROP POLICY IF EXISTS "Allowed read submissions" ON public.submissions;
CREATE POLICY "Allowed read submissions"
ON public.submissions FOR SELECT TO authenticated
USING (
  private.is_admin()
  OR (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team))
  OR submitted_by_email = lower(auth.jwt() ->> 'email')
  OR status = 'approved'
);
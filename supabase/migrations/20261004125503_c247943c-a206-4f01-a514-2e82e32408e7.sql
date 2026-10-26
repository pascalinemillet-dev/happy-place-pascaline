CREATE TYPE public.blocker_status AS ENUM ('CRITICAL','IN PROGRESS','MONITORING','SOLVED');
CREATE TYPE public.blocker_severity AS ENUM ('critical','warning','info');
CREATE TYPE public.news_status AS ENUM ('draft','published');
CREATE TYPE public.submission_status AS ENUM ('pending','approved','rejected');

DROP POLICY "Allowed read published news" ON public.news;
DROP POLICY "Allowed create pending submissions" ON public.submissions;
DROP POLICY "Allowed read submissions" ON public.submissions;
DROP POLICY "Managers review assigned submissions" ON public.submissions;

ALTER TABLE public.blockers ALTER COLUMN status DROP DEFAULT, ALTER COLUMN status TYPE public.blocker_status USING status::public.blocker_status, ALTER COLUMN status SET DEFAULT 'CRITICAL';
ALTER TABLE public.blockers ALTER COLUMN severity DROP DEFAULT, ALTER COLUMN severity TYPE public.blocker_severity USING severity::public.blocker_severity, ALTER COLUMN severity SET DEFAULT 'warning';
ALTER TABLE public.news ALTER COLUMN status DROP DEFAULT, ALTER COLUMN status TYPE public.news_status USING status::public.news_status, ALTER COLUMN status SET DEFAULT 'published';
ALTER TABLE public.submissions ALTER COLUMN status DROP DEFAULT, ALTER COLUMN status TYPE public.submission_status USING status::public.submission_status, ALTER COLUMN status SET DEFAULT 'pending';

CREATE POLICY "Allowed read published news" ON public.news FOR SELECT TO authenticated
USING (private.is_allowed() AND (status = 'published' OR private.is_admin()));
CREATE POLICY "Allowed create pending submissions" ON public.submissions FOR INSERT TO authenticated
WITH CHECK (private.is_allowed() AND status = 'pending');
CREATE POLICY "Allowed read submissions" ON public.submissions FOR SELECT TO authenticated
USING (private.is_admin() OR (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team)) OR submitted_by_email = lower(auth.jwt() ->> 'email') OR status = 'approved');
CREATE POLICY "Managers review assigned submissions" ON public.submissions FOR UPDATE TO authenticated
USING (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status = 'pending')
WITH CHECK (private.current_app_role() = 'manager'::public.app_role AND private.can_review_team(team) AND status IN ('approved','rejected'));
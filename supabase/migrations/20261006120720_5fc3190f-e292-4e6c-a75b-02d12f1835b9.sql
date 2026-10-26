-- 1. Faille : un compte non inscrit sur la liste blanche pouvait lire les soumissions validées
DROP POLICY IF EXISTS "Allowed read submissions" ON public.submissions;
CREATE POLICY "Allowed read submissions" ON public.submissions
  FOR SELECT TO authenticated
  USING (
    private.is_allowed() AND (
      private.is_admin()
      OR ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team))
      OR (submitted_by_email = lower((auth.jwt() ->> 'email'::text)))
      OR (status = 'validée'::public.submission_status)
    )
  );

-- 2. Longueur du contenu d'une soumission contrôlée en base (5 à 2000 caractères)
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_content_length_check
  CHECK (char_length(btrim(content)) BETWEEN 5 AND 2000);

-- 3. Un seul manager par équipe, sans tenir compte des majuscules ni des espaces
ALTER TABLE public.manager_teams DROP CONSTRAINT IF EXISTS manager_teams_team_unique;
CREATE UNIQUE INDEX manager_teams_team_unique_ci ON public.manager_teams (lower(btrim(team)));
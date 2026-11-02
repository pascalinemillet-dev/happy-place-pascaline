-- ============================================================
-- Happy Place — installation complète de la base (version élèves)
-- ============================================================
-- À coller en entier dans Supabase > SQL Editor > New query, puis Run.
-- Contient les 39 migrations de l'app, dans l'ordre. Chacune est
-- validée séparément (BEGIN/COMMIT) : certaines ajoutent des valeurs
-- d'ENUM qui doivent être enregistrées avant d'être utilisées.
-- Ensuite, exécuter seed.sql pour charger les données de démo.

-- ---------- 20260929094155_c7483fb2-20dd-4f6c-a253-6036ecdd0ac2.sql ----------
BEGIN;
CREATE TYPE public.app_role AS ENUM ('admin', 'viewer');

CREATE TABLE public.allowed_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  role public.app_role NOT NULL DEFAULT 'viewer',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT email_lower CHECK (email = lower(email))
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.allowed_users TO authenticated;
GRANT ALL ON public.allowed_users TO service_role;
ALTER TABLE public.allowed_users ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS public.app_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.allowed_users WHERE email = lower(auth.jwt() ->> 'email') LIMIT 1
$$;
CREATE OR REPLACE FUNCTION public.is_allowed()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.current_app_role() IS NOT NULL
$$;
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(public.current_app_role() = 'admin', false)
$$;
REVOKE EXECUTE ON FUNCTION public.current_app_role(), public.is_allowed(), public.is_admin() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.current_app_role(), public.is_allowed(), public.is_admin() TO authenticated;

CREATE POLICY "Admins manage whitelist" ON public.allowed_users FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Users see own entry" ON public.allowed_users FOR SELECT TO authenticated
  USING (email = lower(auth.jwt() ->> 'email'));

-- Prevent admin from removing/demoting the last admin
CREATE OR REPLACE FUNCTION public.protect_last_admin()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.role = 'admin' AND (TG_OP = 'DELETE' OR NEW.role <> 'admin') THEN
    IF (SELECT count(*) FROM public.allowed_users WHERE role = 'admin') <= 1 THEN
      RAISE EXCEPTION 'Impossible de retirer le dernier admin';
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER protect_last_admin BEFORE UPDATE OR DELETE ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION public.protect_last_admin();

INSERT INTO public.allowed_users (email, role) VALUES ('admin@biggerboat.example', 'admin');

CREATE TABLE public.news (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL, body text,
  author text NOT NULL DEFAULT 'Admin',
  status text NOT NULL DEFAULT 'published',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_name text NOT NULL, team text NOT NULL, content text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.blockers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL, description text,
  department text NOT NULL DEFAULT 'GENERAL',
  severity text NOT NULL DEFAULT 'warning',
  status text NOT NULL DEFAULT 'CRITICAL',
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.metrics (
  key text PRIMARY KEY, label text NOT NULL, value numeric NOT NULL,
  unit text, delta text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.news, public.submissions, public.blockers, public.metrics TO authenticated;
GRANT ALL ON public.news, public.submissions, public.blockers, public.metrics TO service_role;
ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blockers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allowed read" ON public.news FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.news FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Allowed read" ON public.submissions FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.submissions FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Allowed read" ON public.blockers FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.blockers FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Allowed read" ON public.metrics FOR SELECT TO authenticated USING (public.is_allowed());
CREATE POLICY "Admin write" ON public.metrics FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

INSERT INTO public.news (title, body, author, status, created_at) VALUES
('Résultats S1 2026', 'Croissance de 12% sur le premier semestre, portée par les nouveaux comptes.', 'Direction', 'published', now() - interval '1 day'),
('Ouverture du bureau de Lyon', 'Nos équipes s''installent dans les nouveaux locaux de la Part-Dieu en octobre.', 'RH', 'published', now() - interval '2 days'),
('Semaine de la qualité de vie au travail', 'Ateliers, conférences et activités du 14 au 18 octobre.', 'RH', 'published', now() - interval '3 days'),
('Mise à jour de la charte télétravail', 'Jusqu''à 3 jours de télétravail par semaine à partir de novembre.', 'RH', 'published', now() - interval '4 days'),
('Q3 Strategy Update', 'Priorités du trimestre : fidélisation client et efficacité opérationnelle.', 'Direction', 'published', now() - interval '6 days'),
('Nouveau portail des avantages salariés', 'Tous vos avantages regroupés dans un seul espace.', 'RH', 'published', now() - interval '8 days'),
('Bilan carbone 2025', 'Nos émissions baissent de 9% par rapport à l''an dernier.', 'RSE', 'published', now() - interval '10 days'),
('Arrivée de 14 nouveaux collaborateurs', 'Bienvenue aux nouvelles recrues de septembre.', 'RH', 'published', now() - interval '12 days'),
('Séminaire annuel', 'Rendez-vous les 5 et 6 décembre à Annecy.', 'Direction', 'published', now() - interval '14 days'),
('Programme de mentorat', 'Lancement d''un programme de mentorat interne (brouillon).', 'RH', 'draft', now() - interval '1 day'),
('Migration des outils IT', 'Calendrier de migration vers la nouvelle suite bureautique (brouillon).', 'IT', 'draft', now() - interval '2 days');

INSERT INTO public.submissions (author_name, team, content, status, created_at) VALUES
('Sarah Jenkins', 'Marketing', 'Refonte du kit de présentation commerciale.', 'pending', now() - interval '2 hours'),
('Thomas Martin', 'Support', 'Créer un canal dédié aux retours clients.', 'pending', now() - interval '5 hours'),
('Léa Bernard', 'IT', 'Demande de budget pour le renouvellement des postes.', 'pending', now() - interval '1 day'),
('Karim Haddad', 'Communication', 'Lancer une newsletter interne mensuelle.', 'pending', now() - interval '1 day'),
('Julie Moreau', 'Finance', 'Simplifier le processus de notes de frais.', 'approved', now() - interval '3 days'),
('Marc Dupont', 'Produit', 'Revue design hebdomadaire ouverte à tous.', 'approved', now() - interval '4 days'),
('Nina Petit', 'Ventes', 'Prime trimestrielle par équipe plutôt qu''individuelle.', 'rejected', now() - interval '6 days'),
('Paul Lefèvre', 'Logistique', 'Tableau d''affichage des délais de livraison.', 'pending', now() - interval '3 hours');

INSERT INTO public.blockers (title, description, department, severity, status) VALUES
('API Gateway Downtime', 'Coupures intermittentes du service de paiement.', 'IT', 'critical', 'IN PROGRESS'),
('Delayed Q4 Printing', 'Retard fournisseur sur les supports imprimés.', 'MARKETING', 'warning', 'IN PROGRESS'),
('Retard de livraison matériel', 'Les ordinateurs des nouvelles recrues arrivent avec 3 semaines de retard.', 'IT', 'critical', 'CRITICAL'),
('Absentéisme entrepôt', 'Hausse de l''absentéisme sur l''équipe de nuit.', 'LOGISTIQUE', 'warning', 'MONITORING'),
('Consommation du budget formation', 'Déjà 85% du budget annuel consommé.', 'RH', 'warning', 'MONITORING'),
('Accès VPN instable', 'Problème résolu après mise à jour du client.', 'IT', 'warning', 'SOLVED');

INSERT INTO public.metrics (key, label, value, unit, delta) VALUES
('training_kpi', 'Training KPI', 94.2, '%', '▲ 2.1%'),
('active_users', 'Active Users', 1280, NULL, 'vs 1,200 goal'),
('nps', 'NPS', 82, NULL, '▲ 4 pts'),
('engagement', 'Engagement', 72.5, '%', '▲ 1.8%'),
('turnover', 'Turnover', 8.4, '%', '▼ 0.6%'),
('absenteeism', 'Absentéisme', 3.9, '%', '▲ 0.3%'),
('open_positions', 'Postes ouverts', 17, NULL, '5 en finale'),
('training_hours', 'Heures de formation', 2340, 'h', '▲ 12%');
COMMIT;

-- ---------- 20260929094221_b002fc46-2fd7-4204-94bc-943049ab0f35.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261001152245_e9ea9c51-57c9-41a0-a2f1-76cbae4a40a5.sql ----------
BEGIN;
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'manager';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'collaborateur';
COMMIT;

-- ---------- 20261001153145_e754c84f-1fde-4a44-9ae1-7fc3f7876ca6.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261001153329_a9070f80-16a7-4191-8423-dceb407f7c59.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261004125208_1b93c05f-dada-4c1c-983a-1db81433ab24.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261004125503_c247943c-a206-4f01-a514-2e82e32408e7.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261004130041_92857a61-e2b3-4822-a5ca-4953e8707d86.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261004130819_8177e3c3-73fc-4c2e-ba7f-0b26c4238353.sql ----------
BEGIN;
ALTER TABLE public.manager_teams ADD CONSTRAINT manager_teams_team_unique UNIQUE (team);
COMMIT;

-- ---------- 20261004130926_b749e8ed-a820-4ef6-ba88-124f578b7eb2.sql ----------
BEGIN;
CREATE TYPE public.rejection_category AS ENUM ('à clarifier', 'en désaccord avec les process', 'doublon', 'autre');
ALTER TABLE public.submissions
  ADD COLUMN rejection_category public.rejection_category,
  ADD COLUMN rejection_note text;
UPDATE public.submissions
  SET rejection_category = 'autre', rejection_note = 'Motif non renseigné (refus antérieur à la mise en place des motifs)'
  WHERE status = 'rejected';
ALTER TABLE public.submissions ADD CONSTRAINT submissions_rejection_reason_check CHECK (
  (status = 'rejected' AND rejection_category IS NOT NULL AND rejection_note IS NOT NULL AND length(btrim(rejection_note)) > 0)
  OR (status <> 'rejected' AND rejection_category IS NULL AND rejection_note IS NULL)
);
COMMIT;

-- ---------- 20261004131123_36086d66-c492-447f-ae17-0fa9d76307a0.sql ----------
BEGIN;
ALTER TABLE public.news ADD COLUMN author_email text;

CREATE OR REPLACE FUNCTION private.set_news_author_email()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NEW.author_email IS NULL THEN
    NEW.author_email := lower(auth.jwt() ->> 'email');
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER set_news_author_email
BEFORE INSERT ON public.news
FOR EACH ROW EXECUTE FUNCTION private.set_news_author_email();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  RETURN OLD;
END $$;

CREATE TRIGGER anonymize_removed_user
AFTER DELETE ON public.allowed_users
FOR EACH ROW EXECUTE FUNCTION private.anonymize_removed_user();
COMMIT;

-- ---------- 20261004131651_56ca3c56-582c-4d37-b709-3b74c725970a.sql ----------
BEGIN;
ALTER TABLE public.submissions ADD COLUMN revalidate_at timestamptz;
ALTER TABLE public.news ADD COLUMN revalidate_at timestamptz;

CREATE OR REPLACE FUNCTION private.set_revalidate_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, private AS $$
DECLARE
  live text := CASE TG_TABLE_NAME WHEN 'submissions' THEN 'approved' ELSE 'published' END;
BEGIN
  IF NEW.status::text = live THEN
    IF TG_OP = 'INSERT' OR OLD.status::text <> live OR NEW.revalidate_at IS NULL THEN
      NEW.revalidate_at := now() + interval '1 year';
    END IF;
  ELSE
    NEW.revalidate_at := NULL;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER set_revalidate_at BEFORE INSERT OR UPDATE OF status ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.set_revalidate_at();
CREATE TRIGGER set_revalidate_at BEFORE INSERT OR UPDATE OF status ON public.news
FOR EACH ROW EXECUTE FUNCTION private.set_revalidate_at();

UPDATE public.submissions SET revalidate_at = now() + interval '1 year' WHERE status = 'approved';
UPDATE public.news SET revalidate_at = now() + interval '1 year' WHERE status = 'published';

CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  UPDATE public.submissions SET status = 'pending', revalidate_at = NULL
   WHERE status = 'approved' AND revalidate_at <= now();
  UPDATE public.news SET status = 'draft', revalidate_at = NULL
   WHERE status = 'published' AND revalidate_at <= now();
END $$;
REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('expire-revalidations-daily', '0 3 * * *', $$SELECT private.expire_revalidations()$$);
COMMIT;

-- ---------- 20261004131801_3b2b328c-9616-4f46-9085-7c574e911d93.sql ----------
BEGIN;
ALTER TABLE public.submissions ADD COLUMN attachment_path text, ADD COLUMN attachment_name text;

CREATE OR REPLACE FUNCTION private.check_submission_attachment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF NEW.attachment_path IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.attachment_path IS DISTINCT FROM OLD.attachment_path)
     AND NOT private.is_admin()
     AND split_part(NEW.attachment_path, '/', 1) <> coalesce(auth.uid()::text, '') THEN
    RAISE EXCEPTION 'Pièce jointe invalide';
  END IF;
  IF NEW.attachment_path IS NULL THEN NEW.attachment_name := NULL; END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER check_submission_attachment BEFORE INSERT OR UPDATE ON public.submissions
FOR EACH ROW EXECUTE FUNCTION private.check_submission_attachment();

CREATE POLICY "Allowed users upload own submission PDF" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'submission-attachments'
  AND private.is_allowed()
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND lower(storage.extension(name)) = 'pdf'
);

CREATE POLICY "Reviewers and owner read submission PDF" ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'submission-attachments'
  AND (
    private.is_admin()
    OR (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.submissions s
      WHERE s.attachment_path = storage.objects.name
        AND private.current_app_role() = 'manager'::public.app_role
        AND private.can_review_team(s.team)
    )
  )
);

CREATE POLICY "Admins delete submission PDF" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'submission-attachments' AND private.is_admin());
COMMIT;

-- ---------- 20261004132027_b1065e71-8c66-435d-849b-e4ce4f2472c3.sql ----------
BEGIN;
CREATE TABLE public.metrics_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_key text NOT NULL,
  value numeric NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX metrics_history_key_time ON public.metrics_history (metric_key, recorded_at DESC);
GRANT SELECT ON public.metrics_history TO authenticated;
GRANT ALL ON public.metrics_history TO service_role;
ALTER TABLE public.metrics_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allowed read metrics history" ON public.metrics_history
FOR SELECT TO authenticated USING (private.is_allowed());

INSERT INTO public.metrics_history (metric_key, value, recorded_at)
SELECT key, value, updated_at FROM public.metrics;

CREATE OR REPLACE FUNCTION private.record_metric_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.key <> OLD.key THEN
    UPDATE public.metrics_history SET metric_key = NEW.key WHERE metric_key = OLD.key;
  END IF;
  IF TG_OP = 'INSERT' OR NEW.value IS DISTINCT FROM OLD.value THEN
    INSERT INTO public.metrics_history (metric_key, value) VALUES (NEW.key, NEW.value);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER record_metric_history AFTER INSERT OR UPDATE ON public.metrics
FOR EACH ROW EXECUTE FUNCTION private.record_metric_history();

CREATE OR REPLACE FUNCTION private.delete_metric_history()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  DELETE FROM public.metrics_history WHERE metric_key = OLD.key;
  RETURN OLD;
END $$;
CREATE TRIGGER delete_metric_history AFTER DELETE ON public.metrics
FOR EACH ROW EXECUTE FUNCTION private.delete_metric_history();

ALTER TABLE public.metrics DROP COLUMN delta;

CREATE VIEW public.metrics_with_trend WITH (security_invoker = true) AS
SELECT m.key, m.label, m.value, m.unit, m.updated_at,
  p.value AS previous_value,
  CASE WHEN p.value IS NULL OR p.value = m.value THEN 'stable'
       WHEN m.value > p.value THEN 'hausse' ELSE 'baisse' END AS trend
FROM public.metrics m
LEFT JOIN LATERAL (
  SELECT h.value FROM public.metrics_history h
  WHERE h.metric_key = m.key
  ORDER BY h.recorded_at DESC OFFSET 1 LIMIT 1
) p ON true;
GRANT SELECT ON public.metrics_with_trend TO authenticated;
COMMIT;

-- ---------- 20261006093542_cbce0e4b-6f68-4bf1-ab0e-c3033d4ad1dd.sql ----------
BEGIN;
ALTER TYPE public.blocker_status RENAME VALUE 'CRITICAL' TO 'CRITIQUE';
ALTER TYPE public.blocker_status RENAME VALUE 'IN PROGRESS' TO 'EN COURS';
ALTER TYPE public.blocker_status RENAME VALUE 'MONITORING' TO 'SURVEILLANCE';
ALTER TYPE public.blocker_status RENAME VALUE 'SOLVED' TO 'RÉSOLU';

ALTER TYPE public.news_status RENAME VALUE 'draft' TO 'brouillon';
ALTER TYPE public.news_status RENAME VALUE 'published' TO 'publiée';

ALTER TYPE public.submission_status RENAME VALUE 'pending' TO 'en attente';
ALTER TYPE public.submission_status RENAME VALUE 'approved' TO 'validée';
ALTER TYPE public.submission_status RENAME VALUE 'rejected' TO 'refusée';

CREATE OR REPLACE FUNCTION private.set_revalidate_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, private
AS $$
DECLARE
  live text := CASE TG_TABLE_NAME WHEN 'submissions' THEN 'validée' ELSE 'publiée' END;
BEGIN
  IF NEW.status::text = live THEN
    IF TG_OP = 'INSERT' OR OLD.status::text <> live OR NEW.revalidate_at IS NULL THEN
      NEW.revalidate_at := now() + interval '1 year';
    END IF;
  ELSE
    NEW.revalidate_at := NULL;
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE public.submissions
  SET status = 'en attente', revalidate_at = NULL
  WHERE status = 'validée' AND revalidate_at <= now();

  UPDATE public.news
  SET status = 'brouillon', revalidate_at = NULL
  WHERE status = 'publiée' AND revalidate_at <= now();
END
$$;

REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;
COMMIT;

-- ---------- 20261006114836_db9781bc-b259-43e4-8c72-64ccb293ca87.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status NOT IN ('validée'::public.submission_status, 'refusée'::public.submission_status) THEN
      RAISE EXCEPTION 'Une soumission ne peut passer qu''à validée ou refusée';
    END IF;
    IF OLD.status <> 'en attente'::public.submission_status THEN
      RAISE EXCEPTION 'Seule une soumission en attente peut être validée ou refusée';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
COMMIT;

-- ---------- 20261006114933_6bf78b7c-2c1c-4e6c-89f4-ff5bfd6783a3.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.status NOT IN ('validée'::public.submission_status, 'refusée'::public.submission_status)
       OR OLD.status <> 'en attente'::public.submission_status
       OR NOT private.can_review_team(OLD.team) THEN
      RAISE EXCEPTION 'Un manager peut uniquement valider ou refuser une soumission en attente de ses équipes';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;
COMMIT;

-- ---------- 20261006120720_5fc3190f-e292-4e6c-a75b-02d12f1835b9.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261006160032_924327a2-5ab9-4dcd-918a-209d615d6254.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261006161350_6ec2cf28-1264-4871-b32d-1841c544fe69.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261006162220_30e65ee6-8958-489c-b816-58418f6c104d.sql ----------
BEGIN;
CREATE OR REPLACE VIEW public.metrics_with_trend
WITH (security_invoker = true) AS
SELECT m.key,
    m.label,
    m.value,
    m.unit,
    m.updated_at,
    p.value AS previous_value,
    CASE
        WHEN p.value IS NULL OR p.value = m.value THEN 'stable'::text
        WHEN m.value > p.value THEN 'hausse'::text
        ELSE 'baisse'::text
    END AS trend,
    CASE WHEN p.value IS NULL THEN NULL ELSE m.value - p.value END AS delta
FROM public.metrics m
LEFT JOIN LATERAL (
    SELECT h.value
    FROM public.metrics_history h
    WHERE h.metric_key = m.key
    ORDER BY h.recorded_at DESC
    OFFSET 1
    LIMIT 1
) p ON true;
COMMIT;

-- ---------- 20261006163825_cafe9ae6-9472-4c91-b125-cde664a6bbf5.sql ----------
BEGIN;
CREATE TABLE public.submission_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES public.submissions(id) ON DELETE CASCADE,
  old_status public.submission_status,
  new_status public.submission_status NOT NULL,
  changed_by_email text,
  changed_by_name text,
  is_automatic boolean NOT NULL DEFAULT false,
  rejection_category public.rejection_category,
  rejection_note text,
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX submission_status_history_submission_idx
  ON public.submission_status_history (submission_id, changed_at);

GRANT SELECT ON public.submission_status_history TO authenticated;
GRANT ALL ON public.submission_status_history TO service_role;

ALTER TABLE public.submission_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read history of readable submissions" ON public.submission_status_history
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND EXISTS (
    SELECT 1 FROM public.submissions s WHERE s.id = submission_id
  ));

CREATE OR REPLACE FUNCTION private.record_submission_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _name text := coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() -> 'user_metadata' ->> 'name', _email);
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.submission_status_history
      (submission_id, old_status, new_status, changed_by_email, changed_by_name, is_automatic, rejection_category, rejection_note)
    VALUES
      (NEW.id,
       CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
       NEW.status,
       _email,
       CASE WHEN _email IS NULL THEN NULL ELSE _name END,
       _email IS NULL,
       CASE WHEN NEW.status = 'refusée'::public.submission_status THEN NEW.rejection_category END,
       CASE WHEN NEW.status = 'refusée'::public.submission_status THEN NEW.rejection_note END);
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER record_submission_status
  AFTER INSERT OR UPDATE ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.record_submission_status();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé',
         changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);

  RETURN OLD;
END $function$;

INSERT INTO public.submission_status_history (submission_id, old_status, new_status, is_automatic, changed_at)
SELECT id, NULL, status, true, created_at FROM public.submissions;
COMMIT;

-- ---------- 20261006170014_9615024a-f1ef-46ac-9c89-202c1352facc.sql ----------
BEGIN;
CREATE TABLE public.attachment_deletion_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path text NOT NULL UNIQUE,
  queued_at timestamptz NOT NULL DEFAULT now(),
  last_error text
);
GRANT SELECT, UPDATE, DELETE ON public.attachment_deletion_queue TO authenticated;
GRANT ALL ON public.attachment_deletion_queue TO service_role;
ALTER TABLE public.attachment_deletion_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins manage attachment deletion queue" ON public.attachment_deletion_queue
  FOR ALL TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  -- Pièces jointes : fichiers mis en file de suppression, liens retirés (avant l'anonymisation de l'email)
  INSERT INTO public.attachment_deletion_queue (path)
  SELECT attachment_path FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  UPDATE public.submissions
     SET attachment_path = NULL,
         attachment_name = NULL
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL;

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé',
         submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);

  UPDATE public.news
     SET author = 'Utilisateur supprimé',
         author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);

  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé',
         changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);

  RETURN OLD;
END $function$;
COMMIT;

-- ---------- 20261006172727_a1bd7df4-2b61-41cb-86ea-0acf1b4674bb.sql ----------
BEGIN;
-- Date de départ prévue
ALTER TABLE public.allowed_users ADD COLUMN departure_date date;

CREATE OR REPLACE FUNCTION private.check_departure_date()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'private' AS $function$
BEGIN
  IF NEW.departure_date IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.departure_date IS DISTINCT FROM OLD.departure_date)
     AND NEW.departure_date < current_date + 7 THEN
    RAISE EXCEPTION 'La date de départ doit être au moins 7 jours après aujourd''hui';
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER check_departure_date BEFORE INSERT OR UPDATE OF departure_date ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION private.check_departure_date();

-- Suppression différée des fichiers
ALTER TABLE public.attachment_deletion_queue ADD COLUMN delete_after timestamptz NOT NULL DEFAULT now();

-- Alertes de départ (servent aussi de journal des alertes envoyées)
CREATE TABLE public.departure_notices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  departing_user_id uuid,
  departing_label text NOT NULL,
  recipient_email text NOT NULL,
  departure_date date NOT NULL,
  kind text NOT NULL CHECK (kind IN ('préavis', 'sans préavis')),
  documents jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  reminder_at timestamptz,
  downloaded_at timestamptz,
  closed_at timestamptz
);
CREATE INDEX departure_notices_open_idx ON public.departure_notices (recipient_email) WHERE closed_at IS NULL;
GRANT SELECT ON public.departure_notices TO authenticated;
GRANT ALL ON public.departure_notices TO service_role;
ALTER TABLE public.departure_notices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Recipients and admins read departure notices" ON public.departure_notices
  FOR SELECT TO authenticated
  USING (private.is_allowed() AND (recipient_email = lower(auth.jwt() ->> 'email') OR private.is_admin()));

-- Destinataires : les managers de l'équipe de la personne qui part, et les admins (sauf elle-même)
CREATE OR REPLACE FUNCTION private.departure_recipients(_email text, _team text)
RETURNS SETOF text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  SELECT DISTINCT u.email
  FROM public.allowed_users u
  JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
  LEFT JOIN public.manager_teams mt ON mt.allowed_user_id = u.id
  WHERE lower(u.email) <> lower(_email)
    AND (r.role = 'admin'::public.app_role
         OR (r.role = 'manager'::public.app_role AND _team IS NOT NULL
             AND lower(btrim(mt.team)) = lower(btrim(_team))))
$function$;

CREATE OR REPLACE FUNCTION private.departure_documents(_email text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'submission_id', s.id, 'path', s.attachment_path, 'name', s.attachment_name,
           'created_at', s.created_at, 'excerpt', left(s.content, 60)) ORDER BY s.created_at), '[]'::jsonb)
  FROM public.submissions s
  WHERE lower(s.submitted_by_email) = lower(_email) AND s.attachment_path IS NOT NULL
$function$;

CREATE OR REPLACE FUNCTION private.notify_departure(_user_id uuid, _email text, _team text, _date date, _kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _docs jsonb := private.departure_documents(_email);
BEGIN
  UPDATE public.departure_notices SET closed_at = now()
   WHERE departing_user_id = _user_id AND closed_at IS NULL;
  IF jsonb_array_length(_docs) = 0 THEN RETURN; END IF;
  INSERT INTO public.departure_notices (departing_user_id, departing_label, recipient_email, departure_date, kind, documents)
  SELECT _user_id, _email, rcpt, _date, _kind, _docs FROM private.departure_recipients(_email, _team) AS rcpt;
END $function$;

CREATE OR REPLACE FUNCTION private.on_departure_date_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
BEGIN
  IF NEW.departure_date IS DISTINCT FROM OLD.departure_date THEN
    IF NEW.departure_date IS NULL THEN
      UPDATE public.departure_notices SET closed_at = now()
       WHERE departing_user_id = NEW.id AND closed_at IS NULL;
    ELSE
      PERFORM private.notify_departure(NEW.id, NEW.email, NEW.team, NEW.departure_date, 'préavis');
    END IF;
  END IF;
  RETURN NEW;
END $function$;
CREATE TRIGGER on_departure_date_change AFTER UPDATE OF departure_date ON public.allowed_users
  FOR EACH ROW EXECUTE FUNCTION private.on_departure_date_change();

CREATE OR REPLACE FUNCTION private.anonymize_removed_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _planned boolean := OLD.departure_date IS NOT NULL AND OLD.departure_date <= current_date;
BEGIN
  INSERT INTO public.attachment_deletion_queue (path, delete_after)
  SELECT attachment_path, CASE WHEN _planned THEN now() ELSE now() + interval '7 days' END
    FROM public.submissions
   WHERE lower(submitted_by_email) = lower(OLD.email) AND attachment_path IS NOT NULL
  ON CONFLICT (path) DO NOTHING;

  IF _planned THEN
    UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
     WHERE departing_user_id = OLD.id AND closed_at IS NULL;
  ELSE
    PERFORM private.notify_departure(OLD.id, OLD.email, OLD.team, current_date, 'sans préavis');
  END IF;

  UPDATE public.submissions
     SET author_name = 'Utilisateur supprimé', submitted_by_email = 'Utilisateur supprimé'
   WHERE lower(submitted_by_email) = lower(OLD.email);
  UPDATE public.news
     SET author = 'Utilisateur supprimé', author_email = 'Utilisateur supprimé'
   WHERE lower(author_email) = lower(OLD.email);
  UPDATE public.submission_status_history
     SET changed_by_name = 'Utilisateur supprimé', changed_by_email = 'Utilisateur supprimé'
   WHERE lower(changed_by_email) = lower(OLD.email);
  RETURN OLD;
END $function$;

CREATE OR REPLACE FUNCTION public.mark_departure_notice_downloaded(_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
  UPDATE public.departure_notices SET downloaded_at = now()
   WHERE id = _id AND downloaded_at IS NULL
     AND (recipient_email = lower(auth.jwt() ->> 'email') OR private.is_admin());
$function$;
REVOKE ALL ON FUNCTION public.mark_departure_notice_downloaded(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mark_departure_notice_downloaded(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.run_departures()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE u record;
BEGIN
  UPDATE public.departure_notices SET reminder_at = now()
   WHERE closed_at IS NULL AND downloaded_at IS NULL AND reminder_at IS NULL
     AND kind = 'préavis' AND departure_date - 2 <= current_date;

  FOR u IN SELECT id FROM public.allowed_users
            WHERE departure_date IS NOT NULL AND departure_date <= current_date LOOP
    BEGIN
      DELETE FROM public.allowed_users WHERE id = u.id;
    EXCEPTION WHEN others THEN
      RAISE WARNING 'Départ non appliqué pour % : %', u.id, SQLERRM;
    END;
  END LOOP;

  UPDATE public.departure_notices SET closed_at = now(), departing_label = 'Utilisateur supprimé'
   WHERE closed_at IS NULL AND kind = 'sans préavis' AND created_at <= now() - interval '7 days';
END $function$;
SELECT cron.schedule('run-departures-daily', '15 3 * * *', 'SELECT private.run_departures()');
COMMIT;

-- ---------- 20261006174221_e48290ac-5fab-491f-8872-f3f2ba2ff848.sql ----------
BEGIN;
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
COMMIT;

-- ---------- 20261006181329_24292ff8-bc0d-41e2-853d-f06cac21faf8.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.check_blocker_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.status = 'RÉSOLU'::public.blocker_status THEN
    RAISE EXCEPTION 'Un point bloquant ne peut pas être créé directement au statut RÉSOLU.';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'OUVERT'::public.blocker_status
     AND NEW.status = 'RÉSOLU'::public.blocker_status THEN
    RAISE EXCEPTION 'Un point bloquant OUVERT doit d''abord passer EN COURS avant d''être RÉSOLU.';
  END IF;
  RETURN NEW;
END
$function$;

CREATE TRIGGER check_blocker_transition
  BEFORE INSERT OR UPDATE OF status ON public.blockers
  FOR EACH ROW EXECUTE FUNCTION private.check_blocker_transition();
COMMIT;

-- ---------- 20261006182306_7842ec11-02a6-45b1-adee-bdba515f0ea9.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.queue_deleted_submission_attachment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF OLD.attachment_path IS NOT NULL THEN
    INSERT INTO public.attachment_deletion_queue (path, delete_after)
    VALUES (OLD.attachment_path, now())
    ON CONFLICT (path) DO UPDATE SET delete_after = least(public.attachment_deletion_queue.delete_after, now());
  END IF;
  RETURN OLD;
END
$function$;

CREATE TRIGGER queue_deleted_submission_attachment
  AFTER DELETE ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION private.queue_deleted_submission_attachment();
COMMIT;

-- ---------- 20261006184200_e816c7cd-5737-47c1-97ef-4218181f7d72.sql ----------
BEGIN;
ALTER TABLE public.allowed_users
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name text;

ALTER TABLE public.allowed_users
  ADD CONSTRAINT allowed_users_first_name_len CHECK (first_name IS NULL OR char_length(btrim(first_name)) BETWEEN 1 AND 100),
  ADD CONSTRAINT allowed_users_last_name_len CHECK (last_name IS NULL OR char_length(btrim(last_name)) BETWEEN 1 AND 100);

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _r jsonb;
  _i int := 0;
  _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role;
  _reason text;
  _id uuid;
  _out jsonb := '[]'::jsonb;
  _dup_emails text[];
  _dup_teams text[];
  _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN
    RAISE EXCEPTION 'Le fichier ne contient aucune ligne.';
  END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;

  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  SELECT coalesce(array_agg(t), '{}') INTO _dup_teams FROM (
    SELECT lower(btrim(x->>'team')) t FROM jsonb_array_elements(_rows) x
    WHERE lower(btrim(x->>'role')) = 'manager' AND coalesce(btrim(x->>'team'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    _reason := NULL;

    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND (char_length(_team) < 2 OR char_length(_team) > 60) THEN _reason := 'Nom d''équipe invalide (2 à 60 caractères)';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
    ELSIF _role_txt = 'manager' AND _team IS NOT NULL AND lower(_team) = ANY(_dup_teams) THEN _reason := 'Équipe attribuée à plusieurs managers dans le fichier';
    ELSIF _role_txt = 'manager' AND _team IS NOT NULL AND EXISTS (SELECT 1 FROM public.manager_teams WHERE lower(btrim(team)) = lower(_team)) THEN _reason := 'Cette équipe a déjà un manager';
    END IF;

    IF _reason IS NULL THEN
      _role := _role_txt::public.app_role;
      BEGIN
        INSERT INTO public.allowed_users (email, team, first_name, last_name)
        VALUES (_email, CASE WHEN _role = 'collaborateur' THEN _team END, _first, _last)
        RETURNING id INTO _id;
        INSERT INTO public.allowed_user_roles (allowed_user_id, role) VALUES (_id, _role);
        IF _role = 'manager' AND _team IS NOT NULL THEN
          INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _team);
        END IF;
        IF _dry_run THEN
          RAISE EXCEPTION 'HP_DRY_RUN_OK';
        END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail ou équipe déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN OTHERS THEN
          IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
      END;
    END IF;

    IF _reason IS NULL THEN _ok := _ok + 1; ELSE _ko := _ko + 1; END IF;
    _out := _out || jsonb_build_object(
      'line', _line, 'email', _email, 'last_name', _last, 'first_name', _first,
      'role', _role_txt, 'team', _team,
      'status', CASE WHEN _reason IS NOT NULL THEN 'refusée' WHEN _dry_run THEN 'valide' ELSE 'importée' END,
      'reason', _reason);
  END LOOP;

  RETURN jsonb_build_object('dry_run', _dry_run, 'accepted', _ok, 'rejected', _ko, 'rows', _out);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
COMMIT;

-- ---------- 20261007063846_fe451ba6-7500-4135-9841-4958631aa2e0.sql ----------
BEGIN;
DROP INDEX IF EXISTS public.manager_teams_team_unique_ci;
CREATE UNIQUE INDEX manager_teams_user_team_unique_ci ON public.manager_teams (allowed_user_id, lower(btrim(team)));

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _r jsonb;
  _i int := 0;
  _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role;
  _reason text;
  _id uuid;
  _out jsonb := '[]'::jsonb;
  _dup_emails text[];
  _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN
    RAISE EXCEPTION 'Le fichier ne contient aucune ligne.';
  END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;

  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    _reason := NULL;

    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND (char_length(_team) < 2 OR char_length(_team) > 60) THEN _reason := 'Nom d''équipe invalide (2 à 60 caractères)';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
    END IF;

    IF _reason IS NULL THEN
      _role := _role_txt::public.app_role;
      BEGIN
        INSERT INTO public.allowed_users (email, team, first_name, last_name)
        VALUES (_email, CASE WHEN _role = 'collaborateur' THEN _team END, _first, _last)
        RETURNING id INTO _id;
        INSERT INTO public.allowed_user_roles (allowed_user_id, role) VALUES (_id, _role);
        IF _role = 'manager' AND _team IS NOT NULL THEN
          INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _team);
        END IF;
        IF _dry_run THEN
          RAISE EXCEPTION 'HP_DRY_RUN_OK';
        END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN OTHERS THEN
          IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
      END;
    END IF;

    IF _reason IS NULL THEN _ok := _ok + 1; ELSE _ko := _ko + 1; END IF;
    _out := _out || jsonb_build_object(
      'line', _line, 'email', _email, 'last_name', _last, 'first_name', _first,
      'role', _role_txt, 'team', _team,
      'status', CASE WHEN _reason IS NOT NULL THEN 'refusée' WHEN _dry_run THEN 'valide' ELSE 'importée' END,
      'reason', _reason);
  END LOOP;

  RETURN jsonb_build_object('dry_run', _dry_run, 'accepted', _ok, 'rejected', _ko, 'rows', _out);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
COMMIT;

-- ---------- 20261007065411_0bda54f2-a18c-4e8f-9dba-495682a41f94.sql ----------
BEGIN;
-- Garde-fou contre les régressions silencieuses après une modification d'ENUM (7 oct. 2026)

-- 1) Audit statique : valeurs d'ENUM écrites en dur dans les fonctions
CREATE OR REPLACE FUNCTION private.audit_enum_literals()
RETURNS TABLE(fonction text, valeur text, probleme text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _f record;
  _m text[];
  _labels text[];
  _ok boolean;
BEGIN
  SELECT array_agg(e.enumlabel) INTO _labels
  FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public';

  FOR _f IN
    SELECT n.nspname || '.' || p.proname AS fn, p.prosrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname IN ('public', 'private') AND p.prokind = 'f'
      AND l.lanname IN ('plpgsql', 'sql')
      AND p.proname NOT IN ('audit_enum_literals', 'run_smoke_tests')
  LOOP
    -- a) valeur castée explicitement vers un ENUM : 'x'::public.mon_enum
    FOR _m IN SELECT regexp_matches(_f.prosrc, '''((?:[^'']|'''')*)''::(?:public\.)?(\w+)', 'g') LOOP
      IF EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'public' AND t.typname = _m[2] AND t.typtype = 'e') THEN
        SELECT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                       JOIN pg_namespace n ON n.oid = t.typnamespace
                       WHERE n.nspname = 'public' AND t.typname = _m[2]
                         AND e.enumlabel = replace(_m[1], '''''', '''')) INTO _ok;
        IF NOT _ok THEN
          fonction := _f.fn; valeur := replace(_m[1], '''''', '''');
          probleme := 'Valeur absente de l''ENUM ' || _m[2];
          RETURN NEXT;
        END IF;
      END IF;
    END LOOP;
    -- b) comparaison non typée sur une colonne d'ENUM : status = 'x', role IN ('x', 'y')…
    FOR _m IN SELECT regexp_matches(_f.prosrc,
        '\m_?(?:status|old_status|new_status|role|severity|rejection_category)\s*(?:=|<>|!=)\s*''((?:[^'']|'''')*)''(?!::)', 'g') LOOP
      IF NOT (replace(_m[1], '''''', '''') = ANY(_labels)) THEN
        fonction := _f.fn; valeur := replace(_m[1], '''''', '''');
        probleme := 'Comparaison à une valeur qui n''existe dans aucun ENUM';
        RETURN NEXT;
      END IF;
    END LOOP;
    FOR _m IN SELECT regexp_matches(_f.prosrc,
        '\m_?(?:status|old_status|new_status|role|severity|rejection_category)\s+(?:NOT\s+)?IN\s*\(([^)]*)\)', 'gi') LOOP
      FOR valeur IN SELECT replace(x[1], '''''', '''')
                    FROM regexp_matches(_m[1], '''((?:[^'']|'''')*)''', 'g') x LOOP
        IF NOT (valeur = ANY(_labels)) THEN
          fonction := _f.fn;
          probleme := 'Liste IN contenant une valeur qui n''existe dans aucun ENUM';
          RETURN NEXT;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END;
$$;

-- 2) Test de fumée : rejoue les parcours qui dépendent des statuts, puis annule tout
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
RETURNS TABLE(test text, ok boolean, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 4 lignes (2 créations, 1 validation, 1 refus)', 'ok', _cnt = 4, 'd', _cnt || ' ligne(s)');

    -- Revalidation annuelle
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Revalidation annuelle : une demande validée échue repasse « en attente »', 'ok', _st = 'en attente', 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, échéance de revalidation posée', 'ok',
      (SELECT revalidate_at IS NOT NULL FROM news WHERE id = _n), 'd', (SELECT status::text FROM news WHERE id = _n));

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$$;

REVOKE ALL ON FUNCTION private.audit_enum_literals() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;
COMMIT;

-- ---------- 20261007082655_aefb36b5-4606-4e03-8a0d-0dc4788c9906.sql ----------
BEGIN;
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_rejection_note_max_500
  CHECK (rejection_note IS NULL OR char_length(btrim(rejection_note)) <= 500);
COMMIT;

-- ---------- 20261008000000_drizzle_0000_us26_teams.sql ----------
BEGIN;
-- Référentiel des équipes (US26)
CREATE TABLE IF NOT EXISTS public.teams (
  name text PRIMARY KEY,
  is_reserved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT teams_name_length CHECK (char_length(btrim(name)) BETWEEN 2 AND 60 AND name = btrim(name))
);
CREATE UNIQUE INDEX IF NOT EXISTS teams_name_unique_ci ON public.teams (lower(name));

CREATE OR REPLACE FUNCTION private.protect_reserved_team()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'private' AS $$
BEGIN
  IF OLD.is_reserved THEN
    RAISE EXCEPTION 'L''équipe % est réservée : elle ne peut être ni renommée ni supprimée.', OLD.name;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.is_reserved := OLD.is_reserved;
    RETURN NEW;
  END IF;
  RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS protect_reserved_team ON public.teams;
CREATE TRIGGER protect_reserved_team BEFORE UPDATE OR DELETE ON public.teams
  FOR EACH ROW EXECUTE FUNCTION private.protect_reserved_team();

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allowed read teams" ON public.teams;
CREATE POLICY "Allowed read teams" ON public.teams FOR SELECT TO authenticated USING (private.is_allowed());
DROP POLICY IF EXISTS "Admins insert teams" ON public.teams;
CREATE POLICY "Admins insert teams" ON public.teams FOR INSERT TO authenticated WITH CHECK (private.is_admin() AND NOT is_reserved);
DROP POLICY IF EXISTS "Admins update teams" ON public.teams;
CREATE POLICY "Admins update teams" ON public.teams FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());
DROP POLICY IF EXISTS "Admins delete teams" ON public.teams;
CREATE POLICY "Admins delete teams" ON public.teams FOR DELETE TO authenticated USING (private.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teams TO authenticated;

INSERT INTO public.teams (name, is_reserved) VALUES ('Admin', true) ON CONFLICT DO NOTHING;
INSERT INTO public.teams (name) VALUES
  ('Accounting'), ('Finance'), ('Legal'), ('Marketing'), ('People'), ('Product'),
  ('Direction Commerciale'), ('Opérations'), ('Relation clients'),
  ('Direction Conseil'), ('Pôle Data et IA'), ('Direction recrutement')
ON CONFLICT DO NOTHING;

UPDATE public.allowed_users SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';
DELETE FROM public.manager_teams a USING public.manager_teams b
  WHERE lower(btrim(a.team)) = 'sales' AND lower(btrim(b.team)) = 'direction commerciale' AND a.allowed_user_id = b.allowed_user_id;
UPDATE public.manager_teams SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';
UPDATE public.submissions SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';

UPDATE public.allowed_users u SET team = t.name FROM public.teams t WHERE lower(btrim(u.team)) = lower(t.name) AND u.team <> t.name;
UPDATE public.manager_teams m SET team = t.name FROM public.teams t WHERE lower(btrim(m.team)) = lower(t.name) AND m.team <> t.name;
UPDATE public.submissions s SET team = t.name FROM public.teams t WHERE lower(btrim(s.team)) = lower(t.name) AND s.team <> t.name;

INSERT INTO public.teams (name)
SELECT DISTINCT btrim(x.team) FROM (
  SELECT team FROM public.allowed_users UNION SELECT team FROM public.manager_teams UNION SELECT team FROM public.submissions
) x WHERE x.team IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.teams t WHERE lower(t.name) = lower(btrim(x.team)))
ON CONFLICT DO NOTHING;

ALTER TABLE public.allowed_users DROP CONSTRAINT IF EXISTS allowed_users_team_fkey;
ALTER TABLE public.allowed_users ADD CONSTRAINT allowed_users_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.manager_teams DROP CONSTRAINT IF EXISTS manager_teams_team_fkey;
ALTER TABLE public.manager_teams ADD CONSTRAINT manager_teams_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.submissions DROP CONSTRAINT IF EXISTS submissions_team_fkey;
ALTER TABLE public.submissions ADD CONSTRAINT submissions_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _r jsonb; _i int := 0; _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role; _reason text; _id uuid;
  _out jsonb := '[]'::jsonb; _dup_emails text[]; _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN RAISE EXCEPTION 'Le fichier ne contient aucune ligne.'; END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;
  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> '' GROUP BY 1 HAVING count(*) > 1) d;
  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    IF _team IS NOT NULL THEN
      _team := coalesce((SELECT t.name FROM public.teams t WHERE lower(t.name) = lower(_team)), _team);
    END IF;
    _reason := NULL;
    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.teams t WHERE t.name = _team) THEN _reason := 'Équipe inconnue : choisis une équipe de la liste';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
    END IF;
    IF _reason IS NULL THEN
      _role := _role_txt::public.app_role;
      BEGIN
        INSERT INTO public.allowed_users (email, team, first_name, last_name)
        VALUES (_email, CASE WHEN _role = 'collaborateur' THEN _team END, _first, _last)
        RETURNING id INTO _id;
        INSERT INTO public.allowed_user_roles (allowed_user_id, role) VALUES (_id, _role);
        IF _role = 'manager' AND _team IS NOT NULL THEN
          INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _team);
        END IF;
        IF _dry_run THEN RAISE EXCEPTION 'HP_DRY_RUN_OK'; END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN foreign_key_violation THEN _reason := 'Équipe inconnue : choisis une équipe de la liste';
        WHEN OTHERS THEN IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
      END;
    END IF;
    IF _reason IS NULL THEN _ok := _ok + 1; ELSE _ko := _ko + 1; END IF;
    _out := _out || jsonb_build_object(
      'line', _line, 'email', _email, 'last_name', _last, 'first_name', _first,
      'role', _role_txt, 'team', _team,
      'status', CASE WHEN _reason IS NOT NULL THEN 'refusée' WHEN _dry_run THEN 'valide' ELSE 'importée' END,
      'reason', _reason);
  END LOOP;
  RETURN jsonb_build_object('dry_run', _dry_run, 'accepted', _ok, 'rejected', _ko, 'rows', _out);
END;
$function$;
REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
COMMIT;

-- ---------- 20261008000001_drizzle_0001_us26_fix_smoke_tests.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _adm uuid;
  _s1 uuid; _s2 uuid; _b uuid; _n uuid;
  _st text; _cnt int; _err text;
  _team text := 'ZZ Test fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team) VALUES ('smoke.collab@test.invalid', _team) RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email) VALUES ('smoke.manager@test.invalid') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('smoke.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- Collaborateur : soumission
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 1') RETURNING id, status::text INTO _s1, _st;
    _res := _res || jsonb_build_object('t', 'Soumission créée « en attente », dans l''équipe du collaborateur',
      'ok', _st = 'en attente' AND (SELECT team FROM submissions WHERE id = _s1) = _team, 'd', _st);
    INSERT INTO submissions(author_name, team, content) VALUES ('Smoke', 'x', 'Demande de test 2') RETURNING id INTO _s2;

    -- Manager : validation et refus
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'validée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', true, 'd', 'validée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager valide une demande en attente', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Test' WHERE id = _s2;
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager refuse une demande avec un motif', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      UPDATE submissions SET status = 'refusée' WHERE id = _s1;
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Le manager ne peut pas revenir sur une demande validée', 'ok', true, 'd', 'refusé par la base');
    END;
    SELECT count(*) INTO _cnt FROM submission_status_history WHERE submission_id IN (_s1, _s2);
    _res := _res || jsonb_build_object('t', 'Historique : 4 lignes (2 créations, 1 validation, 1 refus)', 'ok', _cnt = 4, 'd', _cnt || ' ligne(s)');

    -- Revalidation annuelle
    PERFORM set_config('request.jwt.claims', '', true);
    UPDATE submissions SET revalidate_at = now() - interval '1 day' WHERE id = _s1;
    PERFORM private.expire_revalidations();
    SELECT status::text INTO _st FROM submissions WHERE id = _s1;
    _res := _res || jsonb_build_object('t', 'Revalidation annuelle : une demande validée échue repasse « en attente »', 'ok', _st = 'en attente', 'd', _st);

    -- Points bloquants
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.admin@test.invalid"}', true);
    INSERT INTO blockers(title, department) VALUES ('Blocage de test', 'Test') RETURNING id, status::text INTO _b, _st;
    _res := _res || jsonb_build_object('t', 'Point bloquant créé au statut OUVERT', 'ok', _st = 'OUVERT', 'd', _st);
    BEGIN
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → RÉSOLU refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      UPDATE blockers SET status = 'EN COURS' WHERE id = _b;
      UPDATE blockers SET status = 'SURVEILLANCE' WHERE id = _b;
      UPDATE blockers SET status = 'RÉSOLU' WHERE id = _b;
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', true, 'd', 'RÉSOLU');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'OUVERT → EN COURS → SURVEILLANCE → RÉSOLU accepté', 'ok', false, 'd', SQLERRM);
    END;

    -- Actualités
    PERFORM set_config('request.jwt.claims', '{"email":"smoke.manager@test.invalid"}', true);
    INSERT INTO news(title, body, author, status) VALUES ('Actu de test', 'Corps', 'Smoke', 'brouillon') RETURNING id INTO _n;
    UPDATE news SET status = 'publiée' WHERE id = _n;
    _res := _res || jsonb_build_object('t', 'Actualité : brouillon puis publiée, échéance de revalidation posée', 'ok',
      (SELECT revalidate_at IS NOT NULL FROM news WHERE id = _n), 'd', (SELECT status::text FROM news WHERE id = _n));

    -- Référentiel des équipes
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      UPDATE teams SET name = 'ZZ Test fumée 2' WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok',
        (SELECT team FROM allowed_users WHERE id = _collab) = 'ZZ Test fumée 2'
        AND (SELECT team FROM manager_teams WHERE allowed_user_id = _mgr) = 'ZZ Test fumée 2'
        AND (SELECT team FROM submissions WHERE id = _s1) = 'ZZ Test fumée 2', 'd', 'ZZ Test fumée 2');
      _team := 'ZZ Test fumée 2';
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'Référentiel : renommer une équipe met à jour utilisateurs, managers et demandes', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      DELETE FROM teams WHERE name = _team;
      _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION
      WHEN foreign_key_violation THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', true, 'd', 'refusé par la base');
      WHEN OTHERS THEN
        _res := _res || jsonb_build_object('t', 'Référentiel : supprimer une équipe encore utilisée est refusé', 'ok', false, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO _cnt FROM private.audit_enum_literals();
  _res := _res || jsonb_build_object('t', 'Aucune valeur d''ENUM obsolète dans les fonctions', 'ok', _cnt = 0, 'd', _cnt || ' anomalie(s)');

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END;
$function$;
COMMIT;

-- ---------- 20261008000002_drizzle_0002_news_media_links.sql ----------
BEGIN;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS image_path text;
ALTER TABLE public.news ADD COLUMN IF NOT EXISTS links jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE OR REPLACE FUNCTION private.check_news_links()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, private AS $$
DECLARE _l jsonb; _url text; _label text;
BEGIN
  IF NEW.links IS NULL OR jsonb_typeof(NEW.links) <> 'array' THEN
    RAISE EXCEPTION 'Les liens doivent être une liste.' USING ERRCODE = '23514';
  END IF;
  IF jsonb_array_length(NEW.links) > 3 THEN
    RAISE EXCEPTION '3 liens maximum par actualité.' USING ERRCODE = '23514';
  END IF;
  FOR _l IN SELECT value FROM jsonb_array_elements(NEW.links) LOOP
    IF jsonb_typeof(_l) <> 'object' OR jsonb_typeof(_l->'url') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'Chaque lien doit avoir une adresse.' USING ERRCODE = '23514';
    END IF;
    _url := _l->>'url';
    IF _url !~* '^https?://[^\s]+$' THEN
      RAISE EXCEPTION 'Adresse de lien invalide : seules les adresses http:// ou https:// sont acceptées.' USING ERRCODE = '23514';
    END IF;
    IF char_length(_url) > 2000 THEN
      RAISE EXCEPTION 'Adresse de lien trop longue (2 000 caractères maximum).' USING ERRCODE = '23514';
    END IF;
    IF _l ? 'label' AND jsonb_typeof(_l->'label') NOT IN ('string', 'null') THEN
      RAISE EXCEPTION 'Libellé de lien invalide.' USING ERRCODE = '23514';
    END IF;
    _label := _l->>'label';
    IF _label IS NOT NULL AND char_length(_label) > 80 THEN
      RAISE EXCEPTION 'Libellé de lien trop long (80 caractères maximum).' USING ERRCODE = '23514';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS check_news_links ON public.news;
CREATE TRIGGER check_news_links BEFORE INSERT OR UPDATE OF links ON public.news
FOR EACH ROW EXECUTE FUNCTION private.check_news_links();

CREATE OR REPLACE FUNCTION private.can_edit_news_media(_news_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, private AS $$
  SELECT private.is_admin() OR EXISTS (
    SELECT 1 FROM public.news n
    WHERE n.id::text = _news_id
      AND private.current_app_role() = 'manager'
      AND n.status = 'brouillon'
      AND n.author_email = lower(auth.jwt() ->> 'email'))
$$;
REVOKE EXECUTE ON FUNCTION private.can_edit_news_media(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION private.can_edit_news_media(text) TO authenticated;

CREATE POLICY "News media read" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'news-media' AND private.is_allowed()
  AND EXISTS (SELECT 1 FROM public.news n WHERE n.id::text = (storage.foldername(name))[1]));

CREATE POLICY "News media insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'news-media' AND private.is_allowed()
  AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp')
  AND private.can_edit_news_media((storage.foldername(name))[1]));

CREATE POLICY "News media update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'news-media' AND private.can_edit_news_media((storage.foldername(name))[1]))
WITH CHECK (bucket_id = 'news-media' AND lower(storage.extension(name)) IN ('jpg', 'jpeg', 'png', 'webp')
  AND private.can_edit_news_media((storage.foldername(name))[1]));

CREATE POLICY "News media delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'news-media' AND private.can_edit_news_media((storage.foldername(name))[1]));
COMMIT;

-- ---------- 20261008000003_drizzle_0003_notify_departure_even_without_documents.sql ----------
BEGIN;
CREATE OR REPLACE FUNCTION private.notify_departure(_user_id uuid, _email text, _team text, _date date, _kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private' AS $function$
DECLARE _docs jsonb := private.departure_documents(_email);
BEGIN
  UPDATE public.departure_notices SET closed_at = now()
   WHERE departing_user_id = _user_id AND closed_at IS NULL;
  INSERT INTO public.departure_notices (departing_user_id, departing_label, recipient_email, departure_date, kind, documents)
  SELECT _user_id, _email, rcpt, _date, _kind, _docs FROM private.departure_recipients(_email, _team) AS rcpt;
END $function$;
COMMIT;

-- ---------- 20261008000004_drizzle_0004_verify_smoke_tests_after_notify_change.sql ----------
BEGIN;
DO $$
DECLARE _bad int;
BEGIN
  SELECT count(*) INTO _bad FROM private.run_smoke_tests() WHERE NOT ok;
  IF _bad > 0 THEN
    RAISE EXCEPTION 'Smoke tests failed: % test(s) not ok', _bad;
  END IF;
END $$;
COMMENT ON FUNCTION private.notify_departure(uuid, text, text, date, text) IS 'Crée les alertes de départ même sans document joint (le bandeau informe alors simplement du départ).';
COMMIT;

-- ---------- 20261016085900_buckets_stockage.sql ----------
BEGIN;
-- Version élèves : espaces de stockage utilisés par l'app (créés hors migrations dans l'app d'origine)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
  ('submission-attachments', 'submission-attachments', false, 20971520, ARRAY['application/pdf']),
  ('news-media', 'news-media', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;
COMMIT;

-- ---------- 20261016090000_connexion_libre.sql ----------
BEGIN;
-- ============================================================
-- Version élèves : connexion libre et choix du rôle
-- ============================================================
-- Dans l'app d'origine, seul un admin inscrit un email sur la liste blanche
-- et lui attribue un rôle. Ici, toute personne connectée choisit elle-même
-- son rôle (et peut en changer). Les règles de sécurité (RLS) ne changent pas :
-- elles lisent toujours allowed_users / allowed_user_roles / manager_teams.

-- 1. La liste des équipes doit être lisible avant d'avoir un rôle
--    (sinon l'écran de choix ne peut pas proposer les équipes).
DROP POLICY IF EXISTS "Authenticated read teams" ON public.teams;
CREATE POLICY "Authenticated read teams" ON public.teams
  FOR SELECT TO authenticated USING (true);

-- 2. Choisir (ou changer) son rôle
CREATE OR REPLACE FUNCTION public.choisir_mon_role(
  _role public.app_role,
  _first_name text,
  _last_name text,
  _team text DEFAULT NULL
)
RETURNS public.app_role
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _first text := nullif(btrim(coalesce(_first_name, '')), '');
  _last text := nullif(btrim(coalesce(_last_name, '')), '');
  _t text := nullif(btrim(coalesce(_team, '')), '');
  _id uuid;
BEGIN
  IF _email IS NULL THEN
    RAISE EXCEPTION 'Connecte-toi avant de choisir un rôle.' USING ERRCODE = '42501';
  END IF;
  IF _role IS NULL THEN
    RAISE EXCEPTION 'Choisis un rôle.';
  END IF;
  IF _first IS NULL OR _last IS NULL THEN
    RAISE EXCEPTION 'Renseigne ton prénom et ton nom.';
  END IF;

  IF _role = 'admin' THEN
    _t := NULL;
  ELSE
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Choisis une équipe.';
    END IF;
    SELECT t.name INTO _t FROM public.teams t
     WHERE lower(t.name) = lower(_t) AND NOT t.is_reserved;
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Équipe inconnue : choisis une équipe de la liste.';
    END IF;
  END IF;

  INSERT INTO public.allowed_users (email, first_name, last_name, team)
  VALUES (_email, _first, _last, CASE WHEN _role = 'collaborateur' THEN _t END)
  ON CONFLICT (email) DO UPDATE
    SET first_name = excluded.first_name,
        last_name = excluded.last_name,
        team = excluded.team
  RETURNING id INTO _id;

  BEGIN
    INSERT INTO public.allowed_user_roles (allowed_user_id, role)
    VALUES (_id, _role)
    ON CONFLICT (allowed_user_id) DO UPDATE
      SET role = excluded.role, updated_at = now();
  EXCEPTION WHEN raise_exception THEN
    -- Déclenché par private.protect_last_admin_role()
    RAISE EXCEPTION 'Tu es le dernier admin : un autre membre doit devenir admin avant que tu changes de rôle.';
  END;

  DELETE FROM public.manager_teams WHERE allowed_user_id = _id;
  IF _role = 'manager' THEN
    INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _t);
  END IF;

  RETURN _role;
END;
$$;

REVOKE ALL ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) IS
  'Version élèves : la personne connectée choisit son rôle (admin, manager ou collaborateur) et son équipe.';
COMMIT;

-- ---------- 20261016100000_entree_directe.sql ----------
BEGIN;
-- ============================================================
-- Version élèves : entrée directe, sans email ni mot de passe
-- ============================================================
-- L'app ouvre une session anonyme Supabase (signInAnonymously). Au premier
-- choix de rôle, la base donne à ce compte une adresse interne
-- (eleve-xxxx@happyplace.test) : toutes les règles de sécurité de l'app
-- reposent sur l'email du compte connecté, elles fonctionnent donc sans changement.

CREATE OR REPLACE FUNCTION public.choisir_mon_role(
  _role public.app_role,
  _first_name text,
  _last_name text,
  _team text DEFAULT NULL
)
RETURNS public.app_role
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _uid uuid := auth.uid();
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _first text := nullif(btrim(coalesce(_first_name, '')), '');
  _last text := nullif(btrim(coalesce(_last_name, '')), '');
  _t text := nullif(btrim(coalesce(_team, '')), '');
  _id uuid;
BEGIN
  IF _uid IS NULL AND _email IS NULL THEN
    RAISE EXCEPTION 'Session introuvable : recharge la page.' USING ERRCODE = '42501';
  END IF;

  -- Compte anonyme : on lui attribue une adresse interne, une fois pour toutes
  IF _email IS NULL THEN
    SELECT lower(u.email) INTO _email FROM auth.users u WHERE u.id = _uid;
    IF _email IS NULL OR _email = '' THEN
      _email := 'eleve-' || left(replace(_uid::text, '-', ''), 12) || '@happyplace.test';
      UPDATE auth.users SET email = _email WHERE id = _uid;
    END IF;
  END IF;

  IF _role IS NULL THEN
    RAISE EXCEPTION 'Choisis un rôle.';
  END IF;
  IF _first IS NULL OR _last IS NULL THEN
    RAISE EXCEPTION 'Renseigne ton prénom et ton nom.';
  END IF;

  IF _role = 'admin' THEN
    _t := NULL;
  ELSE
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Choisis une équipe.';
    END IF;
    SELECT t.name INTO _t FROM public.teams t
     WHERE lower(t.name) = lower(_t) AND NOT t.is_reserved;
    IF _t IS NULL THEN
      RAISE EXCEPTION 'Équipe inconnue : choisis une équipe de la liste.';
    END IF;
  END IF;

  INSERT INTO public.allowed_users (email, first_name, last_name, team)
  VALUES (_email, _first, _last, CASE WHEN _role = 'collaborateur' THEN _t END)
  ON CONFLICT (email) DO UPDATE
    SET first_name = excluded.first_name,
        last_name = excluded.last_name,
        team = excluded.team
  RETURNING id INTO _id;

  BEGIN
    INSERT INTO public.allowed_user_roles (allowed_user_id, role)
    VALUES (_id, _role)
    ON CONFLICT (allowed_user_id) DO UPDATE
      SET role = excluded.role, updated_at = now();
  EXCEPTION WHEN raise_exception THEN
    RAISE EXCEPTION 'Tu es le dernier admin : un autre membre doit devenir admin avant que tu changes de rôle.';
  END;

  DELETE FROM public.manager_teams WHERE allowed_user_id = _id;
  IF _role = 'manager' THEN
    INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _t);
  END IF;

  RETURN _role;
END;
$$;

REVOKE ALL ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) TO authenticated;
COMMIT;

-- Vérification finale : toutes les lignes doivent indiquer ok = true

-- ---------- 20261030220000_liste_blanche.sql ----------
-- ============================================================
-- Lot 0 (T9) : retour de la liste blanche
-- ============================================================
-- Seules les adresses inscrites dans allowed_users peuvent créer un compte
-- (email et mot de passe). Le rôle vient de allowed_user_roles, attribué par un admin :
-- personne ne choisit plus son propre rôle. Les règles RLS ne changent pas.
-- À faire aussi dans Supabase : couper « Allow anonymous sign-ins » et « Confirm email ».

BEGIN;

-- 1. Plus de choix de rôle libre : la fonction de la version élèves n'est plus appelable.
REVOKE EXECUTE ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) FROM public, anon, authenticated;
COMMENT ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) IS
  'Version élèves, désactivée au lot 0 (liste blanche) : plus aucun rôle ne peut l''appeler.';

-- 2. Les équipes redeviennent lisibles par les seuls invités (règle « Allowed read teams » d'origine).
DROP POLICY IF EXISTS "Authenticated read teams" ON public.teams;

-- 3. La base refuse la création d'un compte dont l'adresse n'est pas invitée
--    (comptes anonymes compris, qui n'ont pas d'adresse).
CREATE OR REPLACE FUNCTION private.refuser_compte_non_invite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF NEW.email IS NULL OR NEW.email = ''
     OR NOT EXISTS (SELECT 1 FROM public.allowed_users WHERE email = lower(NEW.email)) THEN
    RAISE EXCEPTION 'Adresse non invitée : demande à un admin de t''ajouter à Happy Place.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

GRANT USAGE ON SCHEMA private TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION private.refuser_compte_non_invite() TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION private.refuser_compte_non_invite() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS refuser_compte_non_invite ON auth.users;
CREATE TRIGGER refuser_compte_non_invite
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.refuser_compte_non_invite();

COMMIT;

-- ---------- 20261031090000_f1_point_bloquant.sql ----------
-- ============================================================
-- F1 « Signaler un point bloquant » (lot 1 : US29 à US34, US63, US64)
-- ============================================================
-- Une soumission est une idée ou un point bloquant. Le point bloquant est
-- assigné aux managers de l'équipe de l'auteur et à l'admin : le premier qui
-- le publie (statut OUVERT, C1, pôle du référentiel des équipes, C2) ou le
-- refuse l'emporte. Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

CREATE TYPE public.submission_kind AS ENUM ('idée', 'point bloquant');

ALTER TABLE public.submissions
  ADD COLUMN kind public.submission_kind NOT NULL DEFAULT 'idée',
  ADD COLUMN severity public.blocker_severity,
  ADD COLUMN proposed_title text,
  ADD COLUMN proposed_title_by_ai boolean NOT NULL DEFAULT false,
  ADD COLUMN blocker_id uuid REFERENCES public.blockers(id) ON DELETE SET NULL;

-- La sévérité n'existe que pour un point bloquant, et elle y est obligatoire.
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_severity_by_kind
  CHECK ((kind = 'point bloquant'::public.submission_kind) = (severity IS NOT NULL));
ALTER TABLE public.submissions
  ADD CONSTRAINT submissions_proposed_title_length
  CHECK (proposed_title IS NULL OR char_length(btrim(proposed_title)) BETWEEN 1 AND 160);

CREATE INDEX submissions_kind_status_idx ON public.submissions (kind, status);

-- ---------- Auteur, équipe et nom repris du compte (C4) ----------
-- Un collaborateur ou un manager ne peut plus choisir le nom affiché.
-- L'admin garde la saisie libre de l'écran « Gérer les données ».
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
  _name text;
BEGIN
  NEW.submitted_by_email := _email;
  SELECT r.role, u.team, u.id, nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), '')
    INTO _role, _team, _uid, _name
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
  IF _role IN ('collaborateur', 'manager') AND _name IS NOT NULL THEN
    NEW.author_name := _name;
  END IF;
  -- Le titre, son origine et le point bloquant créé se posent à la publication, jamais à l'envoi.
  NEW.proposed_title := NULL;
  NEW.proposed_title_by_ai := false;
  NEW.blocker_id := NULL;
  RETURN NEW;
END
$function$;

-- ---------- Un manager ne change ni le type, ni la sévérité, ni le lien vers le point créé ----------
CREATE OR REPLACE FUNCTION private.enforce_submission_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  IF private.current_app_role() = 'manager'::public.app_role THEN
    IF NEW.author_name IS DISTINCT FROM OLD.author_name
       OR NEW.team IS DISTINCT FROM OLD.team
       OR NEW.content IS DISTINCT FROM OLD.content
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.kind IS DISTINCT FROM OLD.kind
       OR NEW.severity IS DISTINCT FROM OLD.severity
       OR (NEW.blocker_id IS DISTINCT FROM OLD.blocker_id
           AND coalesce(current_setting('hp.publishing', true), '') <> 'on')
       OR NEW.status NOT IN ('validée'::public.submission_status, 'refusée'::public.submission_status)
       OR OLD.status <> 'en attente'::public.submission_status
       OR NOT private.can_review_team(OLD.team) THEN
      RAISE EXCEPTION 'Un manager peut uniquement valider ou refuser une soumission en attente de ses équipes';
    END IF;
  END IF;
  RETURN NEW;
END
$function$;

-- ---------- Lecture : un point bloquant validé n'est pas public (US33) ----------
-- Visible de son auteur, des managers de l'équipe et de l'admin ; le point créé
-- (table blockers) reste lisible par tous les comptes inscrits.
DROP POLICY IF EXISTS "Allowed read submissions" ON public.submissions;
CREATE POLICY "Allowed read submissions" ON public.submissions
  FOR SELECT TO authenticated
  USING (
    private.is_allowed() AND (
      private.is_admin()
      OR ((private.current_app_role() = 'manager'::public.app_role) AND private.can_review_team(team))
      OR (submitted_by_email = lower((auth.jwt() ->> 'email'::text)))
      OR (status = 'validée'::public.submission_status AND kind = 'idée'::public.submission_kind)
    )
  );

-- ---------- La revalidation annuelle ne concerne que les idées ----------
-- Un point bloquant validé a créé un point dans le module Points bloquants :
-- le repasser « en attente » après un an permettrait de le publier deux fois.
CREATE OR REPLACE FUNCTION private.expire_revalidations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  UPDATE public.submissions
  SET status = 'en attente', revalidate_at = NULL
  WHERE status = 'validée' AND kind = 'idée' AND revalidate_at <= now();

  UPDATE public.news
  SET status = 'brouillon', revalidate_at = NULL
  WHERE status = 'publiée' AND revalidate_at <= now();
END
$$;
REVOKE ALL ON FUNCTION private.expire_revalidations() FROM PUBLIC, anon, authenticated;

-- ---------- À qui est assignée ma soumission ? (US30) ----------
-- Renvoie les managers de l'équipe de l'appelant (collaborateur), de l'équipe
-- choisie (manager) ; l'admin n'a pas de manager (équipe Admin). L'interface
-- ajoute « Administration HappyPlace » pour un point bloquant, ou pour une
-- équipe sans manager.
CREATE OR REPLACE FUNCTION public.submission_assignees(_team text DEFAULT NULL)
RETURNS TABLE(full_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _role public.app_role := private.current_app_role();
  _email text := lower(auth.jwt() ->> 'email');
  _t text;
BEGIN
  IF _role IS NULL THEN
    RAISE EXCEPTION 'Compte non inscrit.' USING ERRCODE = '42501';
  END IF;
  IF _role = 'collaborateur' THEN
    SELECT u.team INTO _t FROM public.allowed_users u WHERE u.email = _email;
  ELSIF _role = 'manager' THEN
    SELECT mt.team INTO _t FROM public.manager_teams mt
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
     WHERE u.email = _email AND lower(btrim(mt.team)) = lower(btrim(coalesce(_team, '')))
     LIMIT 1;
  END IF;
  IF _t IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email)
      FROM public.manager_teams mt
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
     WHERE lower(btrim(mt.team)) = lower(btrim(_t))
     ORDER BY 1;
END
$function$;
REVOKE ALL ON FUNCTION public.submission_assignees(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submission_assignees(text) TO authenticated;

-- ---------- Publier un point bloquant (US32) ----------
-- Crée le point au statut OUVERT (C1), avec un pôle du référentiel (C2), et
-- passe la soumission à « validée ». Réservé aux managers de l'équipe et à
-- l'admin ; le premier qui agit l'emporte (la soumission doit être en attente).
CREATE OR REPLACE FUNCTION public.publish_blocker_submission(
  _submission_id uuid,
  _title text,
  _department text,
  _severity public.blocker_severity
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _s public.submissions;
  _t text := btrim(coalesce(_title, ''));
  _dep text;
  _blocker uuid;
BEGIN
  IF NOT private.is_manager_or_admin() THEN
    RAISE EXCEPTION 'Seuls un manager ou un admin peuvent publier un point bloquant.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO _s FROM public.submissions WHERE id = _submission_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Soumission introuvable.';
  END IF;
  IF _s.kind <> 'point bloquant'::public.submission_kind THEN
    RAISE EXCEPTION 'Cette soumission n''est pas un point bloquant.';
  END IF;
  IF NOT private.can_review_team(_s.team) THEN
    RAISE EXCEPTION 'Ce point bloquant n''est pas assigné à ton équipe.' USING ERRCODE = '42501';
  END IF;
  IF _s.status <> 'en attente'::public.submission_status OR _s.blocker_id IS NOT NULL THEN
    RAISE EXCEPTION 'Ce point bloquant a déjà été traité par une autre personne.';
  END IF;
  IF char_length(_t) < 3 OR char_length(_t) > 160 THEN
    RAISE EXCEPTION 'Le titre doit faire de 3 à 160 caractères.';
  END IF;
  SELECT t.name INTO _dep FROM public.teams t WHERE lower(t.name) = lower(btrim(coalesce(_department, '')));
  IF _dep IS NULL THEN
    RAISE EXCEPTION 'Pôle inconnu : choisis une équipe du référentiel.';
  END IF;

  INSERT INTO public.blockers (title, description, department, severity, status)
  VALUES (_t, _s.content, _dep, coalesce(_severity, _s.severity), 'OUVERT'::public.blocker_status)
  RETURNING id INTO _blocker;

  PERFORM set_config('hp.publishing', 'on', true);
  UPDATE public.submissions
     SET status = 'validée'::public.submission_status,
         blocker_id = _blocker,
         proposed_title = _t,
         rejection_category = NULL,
         rejection_note = NULL
   WHERE id = _submission_id;
  PERFORM set_config('hp.publishing', 'off', true);
  RETURN _blocker;
END
$function$;
REVOKE ALL ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity) TO authenticated;

-- ---------- Titre proposé par l'IA (US31) ----------
-- L'assigné (manager de l'équipe ou admin) enregistre le titre proposé, sans
-- toucher au reste de la soumission.
CREATE OR REPLACE FUNCTION public.save_proposed_title(_submission_id uuid, _title text, _by_ai boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _s public.submissions;
  _t text := nullif(btrim(coalesce(_title, '')), '');
BEGIN
  IF NOT private.is_manager_or_admin() THEN
    RAISE EXCEPTION 'Réservé aux managers et aux admins.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO _s FROM public.submissions WHERE id = _submission_id FOR UPDATE;
  IF NOT FOUND OR _s.kind <> 'point bloquant'::public.submission_kind
     OR _s.status <> 'en attente'::public.submission_status
     OR NOT private.can_review_team(_s.team) THEN
    RAISE EXCEPTION 'Titre non enregistré : le point bloquant n''est plus à traiter.';
  END IF;
  IF _t IS NOT NULL AND char_length(_t) > 160 THEN
    RAISE EXCEPTION 'Le titre doit faire 160 caractères au plus.';
  END IF;
  UPDATE public.submissions
     SET proposed_title = _t, proposed_title_by_ai = (_t IS NOT NULL AND coalesce(_by_ai, false))
   WHERE id = _submission_id;
END
$function$;
REVOKE ALL ON FUNCTION public.save_proposed_title(uuid, text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.save_proposed_title(uuid, text, boolean) TO authenticated;

-- ---------- Suivi des événements (US34) ----------
-- Aucun contenu saisi : seulement le compte, le rôle, l'événement, le module
-- et quelques compteurs. Lecture réservée aux admins.
CREATE TABLE public.usage_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email text,
  role public.app_role,
  event text NOT NULL CHECK (event IN (
    'module_viewed', 'validated_list_expanded', 'submission_type_selected',
    'submission_sent', 'blocker_report_qualified', 'ai_suggestion_edited',
    'team_recap_generated'
  )),
  module text CHECK (module IS NULL OR char_length(module) <= 40),
  props jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (pg_column_size(props) <= 512),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX usage_events_event_idx ON public.usage_events (event, created_at);

CREATE OR REPLACE FUNCTION private.stamp_usage_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
BEGIN
  NEW.user_email := lower(nullif(auth.jwt() ->> 'email', ''));
  NEW.role := private.current_app_role();
  NEW.created_at := now();
  RETURN NEW;
END
$function$;
CREATE TRIGGER stamp_usage_event BEFORE INSERT ON public.usage_events
  FOR EACH ROW EXECUTE FUNCTION private.stamp_usage_event();

ALTER TABLE public.usage_events ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.usage_events TO authenticated;
GRANT ALL ON public.usage_events TO service_role;
CREATE POLICY "Allowed log events" ON public.usage_events
  FOR INSERT TO authenticated WITH CHECK (private.is_allowed());
CREATE POLICY "Admins read events" ON public.usage_events
  FOR SELECT TO authenticated USING (private.is_admin());

COMMIT;

-- ============================================================
-- Tests de fumée de F1, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_f1_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _collab uuid; _mgr uuid; _mgr2 uuid; _adm uuid;
  _pb uuid; _idea uuid; _pb2 uuid; _blk uuid;
  _st text; _cnt int; _txt text;
  _team text := 'ZZ F1 fumée';
  _team2 text := 'ZZ F1 fumée bis';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), (_team2) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('f1.collab@test.invalid', _team, 'Camille', 'Auteur') RETURNING id INTO _collab;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_collab, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('f1.manager@test.invalid', 'Max', 'Manager') RETURNING id INTO _mgr;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr, _team);
    INSERT INTO allowed_users(email) VALUES ('f1.manager2@test.invalid') RETURNING id INTO _mgr2;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_mgr2, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_mgr2, _team2);
    INSERT INTO allowed_users(email) VALUES ('f1.admin@test.invalid') RETURNING id INTO _adm;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_adm, 'admin');

    -- US29 : le collaborateur envoie un point bloquant, nom et équipe repris du compte (C4)
    PERFORM set_config('request.jwt.claims', '{"email":"f1.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('Nom usurpé', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical')
      RETURNING id, status::text INTO _pb, _st;
    SELECT s.author_name INTO _txt FROM submissions s WHERE s.id = _pb;
    _res := _res || jsonb_build_object('t', 'F1 : point bloquant créé « en attente », nom et équipe repris du compte',
      'ok', _st = 'en attente' AND _txt = 'Camille Auteur'
            AND (SELECT s.team FROM submissions s WHERE s.id = _pb) = _team, 'd', coalesce(_txt, '?'));

    BEGIN
      INSERT INTO submissions(author_name, team, content, kind) VALUES ('x', 'x', 'Point sans sévérité', 'point bloquant');
      _res := _res || jsonb_build_object('t', 'F1 : un point bloquant sans sévérité est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F1 : un point bloquant sans sévérité est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      INSERT INTO submissions(author_name, team, content, kind, severity) VALUES ('x', 'x', 'Idée avec sévérité', 'idée', 'info');
      _res := _res || jsonb_build_object('t', 'F1 : une idée avec une sévérité est refusée', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN check_violation THEN
      _res := _res || jsonb_build_object('t', 'F1 : une idée avec une sévérité est refusée', 'ok', true, 'd', 'refusé par la base');
    END;
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe') RETURNING id INTO _idea;

    -- US30 : assignés = managers de l'équipe de l'auteur
    SELECT count(*), string_agg(a.full_name, ',') INTO _cnt, _txt FROM submission_assignees() a;
    _res := _res || jsonb_build_object('t', 'F1 : les assignés sont les managers de l''équipe de l''auteur',
      'ok', _cnt = 1 AND _txt = 'Max Manager', 'd', coalesce(_txt, 'aucun'));

    -- US32 : un manager d'une autre équipe ne peut pas publier
    PERFORM set_config('request.jwt.claims', '{"email":"f1.manager2@test.invalid"}', true);
    BEGIN
      PERFORM publish_blocker_submission(_pb, 'Titre autre équipe', _team, 'critical');
      _res := _res || jsonb_build_object('t', 'F1 : un manager d''une autre équipe ne peut pas publier', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : un manager d''une autre équipe ne peut pas publier', 'ok', true, 'd', 'refusé par la base');
    END;

    -- US32 : le manager de l'équipe publie, au statut OUVERT, pôle du référentiel
    PERFORM set_config('request.jwt.claims', '{"email":"f1.manager@test.invalid"}', true);
    BEGIN
      _blk := publish_blocker_submission(_pb, 'CV absents des fiches importées', _team, 'warning');
      SELECT b.status::text INTO _st FROM blockers b WHERE b.id = _blk;
      _res := _res || jsonb_build_object('t', 'F1 : le manager publie le point bloquant au statut OUVERT',
        'ok', _st = 'OUVERT'
              AND (SELECT s.status::text FROM submissions s WHERE s.id = _pb) = 'validée'
              AND (SELECT s.blocker_id FROM submissions s WHERE s.id = _pb) = _blk
              AND (SELECT b.severity::text FROM blockers b WHERE b.id = _blk) = 'warning', 'd', _st);
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : le manager publie le point bloquant au statut OUVERT', 'ok', false, 'd', SQLERRM);
    END;
    BEGIN
      PERFORM publish_blocker_submission(_pb, 'Double publication', _team, 'info');
      _res := _res || jsonb_build_object('t', 'F1 : le premier qui publie l''emporte', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : le premier qui publie l''emporte', 'ok', true, 'd', 'refusé par la base');
    END;
    BEGIN
      PERFORM publish_blocker_submission(_idea, 'Une idée publiée', _team, 'info');
      _res := _res || jsonb_build_object('t', 'F1 : une idée ne se publie pas comme point bloquant', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : une idée ne se publie pas comme point bloquant', 'ok', true, 'd', 'refusé par la base');
    END;

    -- Pôle hors référentiel refusé (C2)
    PERFORM set_config('request.jwt.claims', '{"email":"f1.collab@test.invalid"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le partage d''écran plante en visio.', 'point bloquant', 'warning') RETURNING id INTO _pb2;
    PERFORM set_config('request.jwt.claims', '{"email":"f1.admin@test.invalid"}', true);
    BEGIN
      PERFORM publish_blocker_submission(_pb2, 'Partage d''écran en panne', 'PÔLE INVENTÉ', 'warning');
      _res := _res || jsonb_build_object('t', 'F1 : un pôle hors référentiel est refusé', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : un pôle hors référentiel est refusé', 'ok', true, 'd', 'refusé par la base');
    END;
    -- L'admin publie aussi, et refuser reste possible avec « doublon »
    BEGIN
      PERFORM publish_blocker_submission(_pb2, 'Partage d''écran en panne', _team, 'warning');
      _res := _res || jsonb_build_object('t', 'F1 : l''admin publie un point bloquant de n''importe quelle équipe', 'ok', true, 'd', 'publié');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : l''admin publie un point bloquant de n''importe quelle équipe', 'ok', false, 'd', SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', '{"email":"f1.manager@test.invalid"}', true);
    BEGIN
      UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Déjà signalé'
       WHERE id = _idea;
      _res := _res || jsonb_build_object('t', 'F1 : le manager refuse avec le motif « doublon »', 'ok', true, 'd', 'refusée');
    EXCEPTION WHEN OTHERS THEN
      _res := _res || jsonb_build_object('t', 'F1 : le manager refuse avec le motif « doublon »', 'ok', false, 'd', SQLERRM);
    END;

    -- US34 : l'événement est signé par la base, sans contenu
    PERFORM set_config('request.jwt.claims', '{"email":"f1.collab@test.invalid"}', true);
    INSERT INTO usage_events(event, module, props) VALUES ('submission_sent', 'soumettre', '{"kind":"point bloquant"}');
    SELECT e.user_email INTO _txt FROM usage_events e
     WHERE e.event = 'submission_sent' AND e.user_email = 'f1.collab@test.invalid' LIMIT 1;
    _res := _res || jsonb_build_object('t', 'F1 : un événement est enregistré avec le compte de l''appelant',
      'ok', _txt = 'f1.collab@test.invalid', 'd', coalesce(_txt, 'aucun'));

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée F1', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_f1_smoke_tests() FROM public, anon, authenticated;

-- private.run_smoke_tests() devient : tests de base + tests de F1
ALTER FUNCTION private.run_smoke_tests() RENAME TO run_base_smoke_tests;
REVOKE ALL ON FUNCTION private.run_base_smoke_tests() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT * FROM private.run_base_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f1_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;
COMMIT;

-- ---------- 20261102120000_assignes_vue_admin.sql ----------
-- ============================================================
-- Lot 1 (T10) : « Assigné à » dans la file de l'admin
-- ============================================================
-- Constat de la recette du 2026-11-02 : dans l'onglet « Soumissions » de /manage,
-- les cartes n'affichaient que « Administration HappyPlace ». L'admin voit
-- désormais aussi les managers de l'équipe de la soumission (maquette, écran 2 Admin).
-- Pour un admin qui soumet, l'équipe est « Admin » : aucun manager, rien ne change.
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- 25 lignes, toutes ok = true

BEGIN;

CREATE OR REPLACE FUNCTION public.submission_assignees(_team text DEFAULT NULL)
RETURNS TABLE(full_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _role public.app_role := private.current_app_role();
  _email text := lower(auth.jwt() ->> 'email');
  _t text;
BEGIN
  IF _role IS NULL THEN
    RAISE EXCEPTION 'Compte non inscrit.' USING ERRCODE = '42501';
  END IF;
  IF _role = 'admin' THEN
    -- L'admin voit les managers de l'équipe de chaque soumission (file de /manage).
    _t := nullif(btrim(coalesce(_team, '')), '');
  ELSIF _role = 'collaborateur' THEN
    SELECT u.team INTO _t FROM public.allowed_users u WHERE u.email = _email;
  ELSIF _role = 'manager' THEN
    SELECT mt.team INTO _t FROM public.manager_teams mt
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
     WHERE u.email = _email AND lower(btrim(mt.team)) = lower(btrim(coalesce(_team, '')))
     LIMIT 1;
  END IF;
  IF _t IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email)
      FROM public.manager_teams mt
      JOIN public.allowed_users u ON u.id = mt.allowed_user_id
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
     WHERE lower(btrim(mt.team)) = lower(btrim(_t))
     ORDER BY 1;
END
$function$;
REVOKE ALL ON FUNCTION public.submission_assignees(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.submission_assignees(text) TO authenticated;

COMMIT;

-- ---------- 20261102150000_us60_email_point_bloquant.sql ----------
-- ============================================================
-- Lot 2 (T12) : US60, e-mail à l'envoi d'un point bloquant
-- ============================================================
-- Décision du 2026-11-02 : la base prépare chaque e-mail dans une table d'envoi
-- (public.notifications) ; le webhook de base Supabase écoute cette table et
-- appelle le scénario Make, qui envoie l'e-mail par Gmail sans rien recalculer.
-- Make ne reçoit aucune clé Supabase.
--
-- US60 : à la création d'un point bloquant, e-mail aux managers de l'équipe de
-- l'auteur et aux admins ; auteur en copie, jamais en double. Contenu : type,
-- sévérité, date (heure de Paris), personnes assignées, lien vers HappyPlace.
-- Ni description ni pièce jointe (RGPD).
--
-- Les adresses non distribuables (.example, .invalid, .test, .localhost) des
-- données de démo et des tests sont écartées et comptées.
-- Les lignes de plus de 30 jours sont purgées chaque nuit.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  evenement text NOT NULL CHECK (evenement IN ('point_bloquant_soumis')),
  submission_id uuid REFERENCES public.submissions(id) ON DELETE SET NULL,
  destinataires text[] NOT NULL CHECK (cardinality(destinataires) > 0),
  copie text[] NOT NULL DEFAULT '{}',
  objet text NOT NULL,
  corps_html text NOT NULL,
  adresses_ecartees integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_created_at_idx ON public.notifications (created_at);

-- Aucune lecture ni écriture depuis l'app : seule la base y écrit, et le webhook la lit.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notifications FROM public, anon, authenticated;
GRANT ALL ON public.notifications TO service_role;

-- ---------- Outils ----------
CREATE OR REPLACE FUNCTION private.adresse_distribuable(_email text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT _email IS NOT NULL
     AND _email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     AND lower(_email) !~ '\.(example|invalid|test|localhost)$'
     AND lower(_email) !~ '@example\.(com|net|org)$'
$$;

CREATE OR REPLACE FUNCTION private.html_echappe(_t text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT replace(replace(replace(replace(replace(coalesce(_t, ''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;')
$$;

-- « 2 novembre 2026 à 15:07 », heure de Paris
CREATE OR REPLACE FUNCTION private.date_paris(_ts timestamptz)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT CASE WHEN extract(day FROM l) = 1 THEN '1er' ELSE extract(day FROM l)::int::text END
      || ' ' || (ARRAY['janvier','février','mars','avril','mai','juin','juillet','août',
                       'septembre','octobre','novembre','décembre'])[extract(month FROM l)::int]
      || ' ' || extract(year FROM l)::int::text
      || ' à ' || to_char(l, 'HH24:MI')
  FROM (SELECT _ts AT TIME ZONE 'Europe/Paris' AS l) x
$$;

-- ---------- Préparer l'e-mail US60 ----------
CREATE OR REPLACE FUNCTION private.preparer_email_point_bloquant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _candidats text[];
  _a text[];
  _cc text[] := '{}';
  _ecartees int;
  _assignes text;
  _sev text;
  _sev_style text;
  _date text;
  _objet text;
  _html text;
BEGIN
  -- Managers de l'équipe de l'auteur, puis admins.
  SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _candidats
    FROM public.allowed_users u
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE (r.role = 'manager'::public.app_role
          AND EXISTS (SELECT 1 FROM public.manager_teams mt
                       WHERE mt.allowed_user_id = u.id
                         AND lower(btrim(mt.team)) = lower(btrim(NEW.team))))
      OR r.role = 'admin'::public.app_role;

  SELECT count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
         coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
    INTO _ecartees, _a
    FROM unnest(_candidats) e;

  -- Auteur en copie, jamais en double ; seul destinataire si personne d'autre ne peut recevoir.
  IF private.adresse_distribuable(_auteur) THEN
    IF cardinality(_a) = 0 THEN
      _a := ARRAY[_auteur];
    ELSE
      _cc := ARRAY[_auteur];
    END IF;
  ELSIF _auteur <> '' THEN
    _ecartees := _ecartees + 1;
  END IF;

  IF cardinality(_a) = 0 THEN
    RAISE NOTICE 'US60 : aucune adresse distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  -- « Assigné à », comme dans l'app (US30) : managers de l'équipe, puis l'administration.
  SELECT string_agg(n || ', manager ' || NEW.team, ' · ' ORDER BY n) INTO _assignes
    FROM (
      SELECT DISTINCT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email) AS n
        FROM public.manager_teams mt
        JOIN public.allowed_users u ON u.id = mt.allowed_user_id
        JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
       WHERE lower(btrim(mt.team)) = lower(btrim(NEW.team))
    ) m;
  _assignes := concat_ws(' · ', _assignes, 'Administration HappyPlace');

  _sev := CASE NEW.severity
            WHEN 'critical' THEN 'Critique'
            WHEN 'warning' THEN 'Avertissement'
            ELSE 'Information' END;
  _sev_style := CASE NEW.severity
            WHEN 'critical' THEN 'color:#ba1a1a;background:#ffdad6;border:1px solid #ba1a1a;'
            WHEN 'warning' THEN 'color:#574142;background:#fcdbdb;border:1px solid #d9b8b8;'
            ELSE 'color:#444748;background:#efeded;border:1px solid #d1d1cb;' END;
  _date := private.date_paris(NEW.created_at);
  _objet := '[HappyPlace] Nouveau point bloquant à traiter · ' || _sev;

  -- Gabarit de la maquette (écran 5), en HTML compatible messageries : tableaux et styles en ligne.
  _html :=
'<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><title>' || private.html_echappe(_objet) || '</title></head>'
|| '<body style="margin:0;padding:0;background:#f3f2ef;">'
|| '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f2ef;"><tr><td align="center" style="padding:32px 12px;">'
|| '<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid #e6e6e1;font-family:Arial,Helvetica,sans-serif;color:#1b1c1c;">'
|| '<tr><td align="center" style="padding:40px 40px 0 40px;font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:34px;line-height:40px;">Happy Place</td></tr>'
|| '<tr><td align="center" style="padding:20px 40px 0 40px;"><span style="display:inline-block;padding:6px 12px;background:#fcdbdb;color:#574142;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;font-weight:bold;">POINT BLOQUANT</span></td></tr>'
|| '<tr><td align="center" style="padding:20px 40px 24px 40px;font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:26px;line-height:32px;">Un point bloquant vient d''être signalé</td></tr>'
|| '<tr><td style="padding:0 40px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #e6e6e1;">'
|| '<tr><td style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;color:#444748;vertical-align:top;">TYPE</td>'
||     '<td align="right" style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-size:16px;">Point bloquant</td></tr>'
|| '<tr><td style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;color:#444748;vertical-align:top;">SÉVÉRITÉ</td>'
||     '<td align="right" style="padding:16px 0;border-bottom:1px solid #e6e6e1;"><span style="display:inline-block;padding:4px 10px;font-family:''Courier New'',monospace;font-size:13px;letter-spacing:1px;font-weight:bold;' || _sev_style || '">' || upper(_sev) || '</span></td></tr>'
|| '<tr><td style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;color:#444748;vertical-align:top;">DATE</td>'
||     '<td align="right" style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-size:16px;">' || private.html_echappe(_date) || '</td></tr>'
|| '<tr><td style="padding:16px 16px 16px 0;border-bottom:1px solid #e6e6e1;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;color:#444748;vertical-align:top;white-space:nowrap;">ASSIGNÉ À</td>'
||     '<td align="right" style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-size:15px;line-height:22px;">' || private.html_echappe(_assignes) || '</td></tr>'
|| '</table></td></tr>'
|| '<tr><td align="center" style="padding:28px 40px 0 40px;font-size:16px;line-height:24px;color:#444748;">La première personne qui le traite le publie ou le refuse dans HappyPlace.</td></tr>'
|| '<tr><td align="center" style="padding:24px 40px 0 40px;"><a href="' || _lien || '" style="display:inline-block;padding:16px 36px;background:#171818;color:#ffffff;text-decoration:none;font-family:''Courier New'',monospace;font-size:14px;letter-spacing:2px;font-weight:bold;">OUVRIR DANS HAPPYPLACE</a></td></tr>'
|| '<tr><td align="center" style="padding:28px 40px 40px 40px;font-size:12px;line-height:18px;color:#747878;border-top:0;">'
||     '<div style="width:40px;border-top:1px solid #d1d1cb;margin:0 auto 20px auto;"></div>'
||     'Pour protéger les données, la description et la pièce jointe ne figurent pas dans cet e-mail.<br>'
||     'Vous le recevez car ce point vous est assigné ou parce que vous en êtes l''auteur.</td></tr>'
|| '</table></td></tr></table></body></html>';

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_soumis', NEW.id, _a, _cc, _objet, _html, _ecartees);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Un e-mail raté ne doit jamais bloquer l'envoi du point bloquant.
  RAISE WARNING 'US60 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_point_bloquant() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS us60_email_point_bloquant ON public.submissions;
CREATE TRIGGER us60_email_point_bloquant
  AFTER INSERT ON public.submissions
  FOR EACH ROW
  WHEN (NEW.kind = 'point bloquant'::public.submission_kind)
  EXECUTE FUNCTION private.preparer_email_point_bloquant();

-- ---------- Purge après 30 jours (minimisation) ----------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-notifications-daily') THEN
    PERFORM cron.unschedule('purge-notifications-daily');
  END IF;
END $$;
SELECT cron.schedule('purge-notifications-daily', '30 3 * * *',
  $$DELETE FROM public.notifications WHERE created_at < now() - interval '30 days'$$);

COMMIT;

-- ============================================================
-- Tests de fumée de US60, branchés sur private.run_smoke_tests()
-- ============================================================
-- Tout est annulé en fin de test : aucune ligne ne reste dans notifications,
-- donc aucun webhook ne part.
BEGIN;

CREATE OR REPLACE FUNCTION private.run_us60_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _n public.notifications;
  _cnt int;
  _team text := 'ZZ US60 fumée';
  _team2 text := 'ZZ US60 sans manager';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), (_team2) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.collab@fumee.happyplace.fr', _team, 'Thomas', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.manager@fumee.happyplace.fr', 'Karim', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.demo@biggerboat.example', 'Julie', 'Démo') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email) VALUES ('us60.admin@fumee.happyplace.fr') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.seul@fumee.happyplace.fr', _team2, 'Léa', 'Seule') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');

    -- Point bloquant d'un collaborateur : managers et admin en destinataires, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.collab@fumee.happyplace.fr' = ANY (n.copie) ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : managers de l''équipe et admin en destinataires, auteur en copie',
      'ok', _n.id IS NOT NULL
            AND 'us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.collab@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.copie = ARRAY['us60.collab@fumee.happyplace.fr'],
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    _res := _res || jsonb_build_object('t', 'US60 : adresse de démo (.example) écartée',
      'ok', NOT ('us60.demo@biggerboat.example' = ANY (_n.destinataires)) AND _n.adresses_ecartees >= 1,
      'd', coalesce(_n.adresses_ecartees::text, '?') || ' écartée(s)');

    _res := _res || jsonb_build_object('t', 'US60 : objet, sévérité, date, assignés et lien ; ni description ni nom d''auteur',
      'ok', _n.objet = '[HappyPlace] Nouveau point bloquant à traiter · Critique'
            AND position('CRITIQUE' IN _n.corps_html) > 0
            AND position(private.date_paris(now()) IN _n.corps_html) > 0
            AND position('Karim Manager, manager ' || _team IN _n.corps_html) > 0
            AND position('Julie Démo, manager ' || _team IN _n.corps_html) > 0
            AND position('Administration HappyPlace' IN _n.corps_html) > 0
            AND position('https://happy-place-pascaline.pascalinemillet.workers.dev/' IN _n.corps_html) > 0
            AND position('Les CV ne remontent' IN _n.corps_html) = 0
            AND position('Thomas Auteur' IN _n.corps_html) = 0,
      'd', coalesce(_n.objet, '?'));

    -- Une idée ne déclenche pas US60
    SELECT count(*) INTO _cnt FROM notifications;
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe');
    _res := _res || jsonb_build_object('t', 'US60 : une idée ne prépare pas d''e-mail de point bloquant',
      'ok', (SELECT count(*) FROM notifications) = _cnt, 'd', (SELECT count(*) FROM notifications)::text || ' ligne(s)');

    -- Équipe sans manager : l'admin seul, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.seul@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le badge ne fonctionne plus à l''accueil.', 'point bloquant', 'warning');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.seul@fumee.happyplace.fr' = ANY (n.copie) LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : équipe sans manager, l''admin seul et l''auteur en copie',
      'ok', _n.id IS NOT NULL AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.objet LIKE '%· Avertissement'
            AND position('>Administration HappyPlace<' IN _n.corps_html) > 0,
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    -- Un admin qui signale : jamais en double
    PERFORM set_config('request.jwt.claims', '{"email":"us60.admin@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('Admin', 'x', 'Le serveur de fichiers est lent.', 'point bloquant', 'info');
    SELECT * INTO _n FROM notifications n
     WHERE n.objet LIKE '%· Information' ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : l''auteur n''apparaît jamais en double',
      'ok', _n.id IS NOT NULL
            AND (SELECT count(*) FROM unnest(_n.destinataires || _n.copie) e
                  WHERE e = 'us60.admin@fumee.happyplace.fr') = 1,
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    -- L'app ne lit pas la table d'envoi
    _res := _res || jsonb_build_object('t', 'US60 : la table d''envoi est fermée aux comptes de l''app',
      'ok', NOT has_table_privilege('authenticated', 'public.notifications', 'SELECT')
            AND NOT has_table_privilege('anon', 'public.notifications', 'SELECT'),
      'd', 'droits vérifiés');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US60', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us60_smoke_tests() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT * FROM private.run_base_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f1_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us60_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

-- ---------- 20261102160000_us65_email_refus.sql ----------
-- ============================================================
-- Lot 2 (T12) : US65, e-mail à l'auteur d'un point bloquant refusé
-- ============================================================
-- Même mécanisme que US60 : la base prépare l'e-mail dans public.notifications,
-- le webhook de base l'envoie au scénario Make R7, qui l'expédie par Gmail.
--
-- US65 : au refus d'un point bloquant, e-mail à l'auteur. Contenu : date du
-- refus, motif (dont « doublon »), personne qui a refusé, lien vers
-- « Mes soumissions », où la raison détaillée reste lisible. Ni description,
-- ni raison détaillée, ni pièce jointe.
--
-- Le gabarit HTML devient commun (private.email_gabarit) : US60 le reprend
-- sans changer son rendu.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_evenement_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_evenement_check
  CHECK (evenement IN ('point_bloquant_soumis', 'point_bloquant_refuse'));

-- ---------- Gabarit commun (maquette, écran 5) ----------
-- _lignes : tableau de paires {libellé, valeur HTML déjà échappée}.
CREATE OR REPLACE FUNCTION private.email_gabarit(
  _objet text, _tag text, _titre text, _lignes text[], _phrase text,
  _bouton text, _lien text, _pied text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  _rows text := '';
  i int;
  _last int := coalesce(array_length(_lignes, 1), 0);
BEGIN
  FOR i IN 1.._last LOOP
    _rows := _rows
      || '<tr><td style="padding:16px 16px 16px 0;border-bottom:1px solid #e6e6e1;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;color:#444748;vertical-align:top;white-space:nowrap;">'
      || private.html_echappe(_lignes[i][1]) || '</td>'
      || '<td align="right" style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-size:16px;line-height:22px;">'
      || _lignes[i][2] || '</td></tr>';
  END LOOP;
  RETURN
'<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><title>' || private.html_echappe(_objet) || '</title></head>'
|| '<body style="margin:0;padding:0;background:#f3f2ef;">'
|| '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f2ef;"><tr><td align="center" style="padding:32px 12px;">'
|| '<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid #e6e6e1;font-family:Arial,Helvetica,sans-serif;color:#1b1c1c;">'
|| '<tr><td align="center" style="padding:40px 40px 0 40px;font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:34px;line-height:40px;">Happy Place</td></tr>'
|| '<tr><td align="center" style="padding:20px 40px 0 40px;"><span style="display:inline-block;padding:6px 12px;background:#fcdbdb;color:#574142;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;font-weight:bold;">' || private.html_echappe(_tag) || '</span></td></tr>'
|| '<tr><td align="center" style="padding:20px 40px 24px 40px;font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:26px;line-height:32px;">' || private.html_echappe(_titre) || '</td></tr>'
|| '<tr><td style="padding:0 40px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #e6e6e1;">'
|| _rows
|| '</table></td></tr>'
|| '<tr><td align="center" style="padding:28px 40px 0 40px;font-size:16px;line-height:24px;color:#444748;">' || private.html_echappe(_phrase) || '</td></tr>'
|| '<tr><td align="center" style="padding:24px 40px 0 40px;"><a href="' || private.html_echappe(_lien) || '" style="display:inline-block;padding:16px 36px;background:#171818;color:#ffffff;text-decoration:none;font-family:''Courier New'',monospace;font-size:14px;letter-spacing:2px;font-weight:bold;">' || private.html_echappe(_bouton) || '</a></td></tr>'
|| '<tr><td align="center" style="padding:28px 40px 40px 40px;font-size:12px;line-height:18px;color:#747878;">'
||     '<div style="width:40px;border-top:1px solid #d1d1cb;margin:0 auto 20px auto;"></div>'
||     _pied || '</td></tr>'
|| '</table></td></tr></table></body></html>';
END
$function$;

CREATE OR REPLACE FUNCTION private.libelle_severite(_s public.blocker_severity)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE _s WHEN 'critical' THEN 'Critique' WHEN 'warning' THEN 'Avertissement' ELSE 'Information' END
$$;

CREATE OR REPLACE FUNCTION private.tag_severite(_s public.blocker_severity)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT '<span style="display:inline-block;padding:4px 10px;font-family:''Courier New'',monospace;font-size:13px;letter-spacing:1px;font-weight:bold;'
    || CASE _s
         WHEN 'critical' THEN 'color:#ba1a1a;background:#ffdad6;border:1px solid #ba1a1a;'
         WHEN 'warning' THEN 'color:#574142;background:#fcdbdb;border:1px solid #d9b8b8;'
         ELSE 'color:#444748;background:#efeded;border:1px solid #d1d1cb;' END
    || '">' || upper(private.libelle_severite(_s)) || '</span>'
$$;

-- ---------- US60 reprend le gabarit commun ----------
CREATE OR REPLACE FUNCTION private.preparer_email_point_bloquant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _candidats text[];
  _a text[];
  _cc text[] := '{}';
  _ecartees int;
  _assignes text;
  _objet text;
BEGIN
  SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _candidats
    FROM public.allowed_users u
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE (r.role = 'manager'::public.app_role
          AND EXISTS (SELECT 1 FROM public.manager_teams mt
                       WHERE mt.allowed_user_id = u.id
                         AND lower(btrim(mt.team)) = lower(btrim(NEW.team))))
      OR r.role = 'admin'::public.app_role;

  SELECT count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
         coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
    INTO _ecartees, _a
    FROM unnest(_candidats) e;

  IF private.adresse_distribuable(_auteur) THEN
    IF cardinality(_a) = 0 THEN
      _a := ARRAY[_auteur];
    ELSE
      _cc := ARRAY[_auteur];
    END IF;
  ELSIF _auteur <> '' THEN
    _ecartees := _ecartees + 1;
  END IF;

  IF cardinality(_a) = 0 THEN
    RAISE NOTICE 'US60 : aucune adresse distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  SELECT string_agg(n || ', manager ' || NEW.team, ' · ' ORDER BY n) INTO _assignes
    FROM (
      SELECT DISTINCT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email) AS n
        FROM public.manager_teams mt
        JOIN public.allowed_users u ON u.id = mt.allowed_user_id
        JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
       WHERE lower(btrim(mt.team)) = lower(btrim(NEW.team))
    ) m;
  _assignes := concat_ws(' · ', _assignes, 'Administration HappyPlace');
  _objet := '[HappyPlace] Nouveau point bloquant à traiter · ' || private.libelle_severite(NEW.severity);

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_soumis', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'POINT BLOQUANT', 'Un point bloquant vient d''être signalé',
      ARRAY[
        ARRAY['TYPE', 'Point bloquant'],
        ARRAY['SÉVÉRITÉ', private.tag_severite(NEW.severity)],
        ARRAY['DATE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['ASSIGNÉ À', private.html_echappe(_assignes)]
      ],
      'La première personne qui le traite le publie ou le refuse dans HappyPlace.',
      'OUVRIR DANS HAPPYPLACE', _lien,
      'Pour protéger les données, la description et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car ce point vous est assigné ou parce que vous en êtes l''auteur.'),
    _ecartees);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US60 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_point_bloquant() FROM public, anon, authenticated;

-- ---------- US65 : e-mail à l'auteur d'un point bloquant refusé ----------
CREATE OR REPLACE FUNCTION private.preparer_email_refus()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/#mes-soumissions';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _qui_email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _qui text;
  _role public.app_role;
  _motif text;
  _objet text;
BEGIN
  IF NOT private.adresse_distribuable(_auteur) THEN
    RAISE NOTICE 'US65 : adresse de l''auteur non distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  -- Personne qui a refusé : son nom, sinon « Administration HappyPlace » pour un admin.
  SELECT nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), r.role
    INTO _qui, _role
    FROM public.allowed_users u
    LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE u.email = _qui_email;
  _qui := coalesce(_qui || CASE WHEN _role = 'manager' THEN ', manager' WHEN _role = 'admin' THEN ', administration HappyPlace' ELSE '' END,
                   'Administration HappyPlace');

  _motif := CASE NEW.rejection_category
              WHEN 'à clarifier' THEN 'À clarifier'
              WHEN 'en désaccord avec les process' THEN 'En désaccord avec les process'
              WHEN 'doublon' THEN 'Doublon'
              ELSE 'Autre' END;
  _objet := '[HappyPlace] Votre point bloquant n''a pas été retenu · ' || _motif;

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_refuse', NEW.id, ARRAY[_auteur], '{}', _objet,
    private.email_gabarit(
      _objet, 'POINT BLOQUANT', 'Votre point bloquant n''a pas été retenu',
      ARRAY[
        ARRAY['MOTIF', private.html_echappe(_motif)],
        ARRAY['REFUSÉ PAR', private.html_echappe(_qui)],
        ARRAY['DATE DU REFUS', private.html_echappe(private.date_paris(now()))],
        ARRAY['SIGNALÉ LE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['SÉVÉRITÉ', private.tag_severite(NEW.severity)]
      ],
      'La raison détaillée est lisible dans « Mes soumissions ». Vous pouvez reformuler votre point et le renvoyer.',
      'VOIR MES SOUMISSIONS', _lien,
      'Pour protéger les données, la description, la raison détaillée et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car vous êtes l''auteur de ce point bloquant.'),
    0);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US65 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_refus() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS us65_email_refus ON public.submissions;
CREATE TRIGGER us65_email_refus
  AFTER UPDATE OF status ON public.submissions
  FOR EACH ROW
  WHEN (NEW.kind = 'point bloquant'::public.submission_kind
        AND NEW.status = 'refusée'::public.submission_status
        AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION private.preparer_email_refus();

COMMIT;

-- ============================================================
-- Tests de fumée de US65, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_us65_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _pb uuid;
  _idea uuid;
  _n public.notifications;
  _cnt int;
  _team text := 'ZZ US65 fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us65.collab@fumee.happyplace.fr', _team, 'Thomas', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us65.manager@fumee.happyplace.fr', 'Karim', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"us65.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical')
      RETURNING id INTO _pb;
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe')
      RETURNING id INTO _idea;

    PERFORM set_config('request.jwt.claims', '{"email":"us65.manager@fumee.happyplace.fr"}', true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon',
           rejection_note = 'Déjà signalé par la Direction Commerciale'
     WHERE id = _pb;
    SELECT * INTO _n FROM notifications n
     WHERE n.submission_id = _pb AND n.evenement = 'point_bloquant_refuse';
    _res := _res || jsonb_build_object('t', 'US65 : refus d''un point bloquant, e-mail à l''auteur seul',
      'ok', _n.id IS NOT NULL AND _n.destinataires = ARRAY['us65.collab@fumee.happyplace.fr']
            AND cardinality(_n.copie) = 0,
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    _res := _res || jsonb_build_object('t', 'US65 : motif, personne qui refuse, date et lien ; ni description ni raison détaillée',
      'ok', _n.objet = '[HappyPlace] Votre point bloquant n''a pas été retenu · Doublon'
            AND position('Doublon' IN _n.corps_html) > 0
            AND position('Karim Manager, manager' IN _n.corps_html) > 0
            AND position(private.date_paris(now()) IN _n.corps_html) > 0
            AND position('#mes-soumissions' IN _n.corps_html) > 0
            AND position('Les CV ne remontent' IN _n.corps_html) = 0
            AND position('Déjà signalé' IN _n.corps_html) = 0,
      'd', coalesce(_n.objet, '?'));

    -- Le refus d'une idée ne déclenche pas US65
    SELECT count(*) INTO _cnt FROM notifications WHERE evenement = 'point_bloquant_refuse';
    UPDATE submissions SET status = 'refusée', rejection_category = 'autre', rejection_note = 'Hors périmètre'
     WHERE id = _idea;
    _res := _res || jsonb_build_object('t', 'US65 : le refus d''une idée ne prépare pas cet e-mail',
      'ok', (SELECT count(*) FROM notifications WHERE evenement = 'point_bloquant_refuse') = _cnt,
      'd', 'aucun e-mail de refus');

    -- US60 inchangé avec le gabarit commun
    SELECT * INTO _n FROM notifications n
     WHERE n.submission_id = _pb AND n.evenement = 'point_bloquant_soumis';
    _res := _res || jsonb_build_object('t', 'US60 : rendu inchangé avec le gabarit commun',
      'ok', _n.id IS NOT NULL
            AND position('Un point bloquant vient d&#39;être signalé' IN _n.corps_html) > 0
            AND position('CRITIQUE' IN _n.corps_html) > 0
            AND position('Karim Manager, manager ' || _team || ' · Administration HappyPlace' IN _n.corps_html) > 0,
      'd', coalesce(_n.objet, 'aucune ligne'));

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US65', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us65_smoke_tests() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT * FROM private.run_base_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f1_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us60_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us65_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

-- ---------- 20261102170000_us61_us62_emails.sql ----------
-- ============================================================
-- Lot 2 (T12) : US61 et US62, e-mails de publication et d'idée
-- ============================================================
-- Même mécanisme que US60 et US65 : la base prépare l'e-mail dans
-- public.notifications, le webhook de base l'envoie au scénario Make R7,
-- qui l'expédie par Gmail.
--
-- US61 : à la publication d'un point bloquant (statut OUVERT, US32), e-mail à
-- l'auteur. Contenu : titre publié, statut, pôle, date, personne qui l'a
-- publié, lien vers le module Points bloquants.
-- US62 : à chaque soumission d'une idée, e-mail aux managers assignés (US30),
-- à l'admin si l'équipe n'a pas de manager ; auteur en copie. Contenu : type,
-- date, personnes assignées, lien vers HappyPlace. Ni description ni pièce
-- jointe.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_evenement_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_evenement_check
  CHECK (evenement IN ('point_bloquant_soumis', 'point_bloquant_refuse',
                       'point_bloquant_publie', 'idee_soumise'));

-- ---------- Gabarit : tag « IDÉE » sur fond gris clair (maquette, écran 2) ----------
CREATE OR REPLACE FUNCTION private.email_gabarit(
  _objet text, _tag text, _titre text, _lignes text[], _phrase text,
  _bouton text, _lien text, _pied text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  _rows text := '';
  i int;
  _last int := coalesce(array_length(_lignes, 1), 0);
BEGIN
  FOR i IN 1.._last LOOP
    _rows := _rows
      || '<tr><td style="padding:16px 16px 16px 0;border-bottom:1px solid #e6e6e1;font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;color:#444748;vertical-align:top;white-space:nowrap;">'
      || private.html_echappe(_lignes[i][1]) || '</td>'
      || '<td align="right" style="padding:16px 0;border-bottom:1px solid #e6e6e1;font-size:16px;line-height:22px;">'
      || _lignes[i][2] || '</td></tr>';
  END LOOP;
  RETURN
'<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><title>' || private.html_echappe(_objet) || '</title></head>'
|| '<body style="margin:0;padding:0;background:#f3f2ef;">'
|| '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f2ef;"><tr><td align="center" style="padding:32px 12px;">'
|| '<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid #e6e6e1;font-family:Arial,Helvetica,sans-serif;color:#1b1c1c;">'
|| '<tr><td align="center" style="padding:40px 40px 0 40px;font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:34px;line-height:40px;">Happy Place</td></tr>'
|| '<tr><td align="center" style="padding:20px 40px 0 40px;"><span style="display:inline-block;padding:6px 12px;' || CASE WHEN _tag = 'POINT BLOQUANT' THEN 'background:#fcdbdb;color:#574142;' ELSE 'background:#efeded;color:#444748;' END || 'font-family:''Courier New'',monospace;font-size:12px;letter-spacing:1px;font-weight:bold;">' || private.html_echappe(_tag) || '</span></td></tr>'
|| '<tr><td align="center" style="padding:20px 40px 24px 40px;font-family:Georgia,''Times New Roman'',serif;font-style:italic;font-size:26px;line-height:32px;">' || private.html_echappe(_titre) || '</td></tr>'
|| '<tr><td style="padding:0 40px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #e6e6e1;">'
|| _rows
|| '</table></td></tr>'
|| '<tr><td align="center" style="padding:28px 40px 0 40px;font-size:16px;line-height:24px;color:#444748;">' || private.html_echappe(_phrase) || '</td></tr>'
|| '<tr><td align="center" style="padding:24px 40px 0 40px;"><a href="' || private.html_echappe(_lien) || '" style="display:inline-block;padding:16px 36px;background:#171818;color:#ffffff;text-decoration:none;font-family:''Courier New'',monospace;font-size:14px;letter-spacing:2px;font-weight:bold;">' || private.html_echappe(_bouton) || '</a></td></tr>'
|| '<tr><td align="center" style="padding:28px 40px 40px 40px;font-size:12px;line-height:18px;color:#747878;">'
||     '<div style="width:40px;border-top:1px solid #d1d1cb;margin:0 auto 20px auto;"></div>'
||     _pied || '</td></tr>'
|| '</table></td></tr></table></body></html>';
END
$function$;

-- ---------- Personne qui agit : « Nom, manager », sinon l'administration ----------
CREATE OR REPLACE FUNCTION private.nom_acteur()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $$
  SELECT coalesce(
    (SELECT nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), '')
            || CASE r.role WHEN 'manager' THEN ', manager'
                           WHEN 'admin' THEN ', administration HappyPlace' ELSE '' END
       FROM public.allowed_users u
       LEFT JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
      WHERE u.email = lower(nullif(auth.jwt() ->> 'email', ''))
      LIMIT 1),
    'Administration HappyPlace')
$$;
REVOKE ALL ON FUNCTION private.nom_acteur() FROM public, anon, authenticated;

-- ---------- US61 : e-mail à l'auteur d'un point bloquant publié ----------
CREATE OR REPLACE FUNCTION private.preparer_email_publication()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/#points-bloquants';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _b public.blockers;
  _objet text;
BEGIN
  IF NOT private.adresse_distribuable(_auteur) THEN
    RAISE NOTICE 'US61 : adresse de l''auteur non distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;
  SELECT * INTO _b FROM public.blockers WHERE id = NEW.blocker_id;
  IF NOT FOUND THEN
    RAISE NOTICE 'US61 : point bloquant publié introuvable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;
  _objet := '[HappyPlace] Votre point bloquant est publié';

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_publie', NEW.id, ARRAY[_auteur], '{}', _objet,
    private.email_gabarit(
      _objet, 'POINT BLOQUANT', 'Votre point bloquant est pris en charge',
      ARRAY[
        ARRAY['TITRE', private.html_echappe(_b.title)],
        ARRAY['STATUT', private.html_echappe(_b.status::text)],
        ARRAY['PÔLE', private.html_echappe(_b.department)],
        ARRAY['SÉVÉRITÉ', private.tag_severite(_b.severity)],
        ARRAY['PUBLIÉ LE', private.html_echappe(private.date_paris(now()))],
        ARRAY['PUBLIÉ PAR', private.html_echappe(private.nom_acteur())]
      ],
      'Il est suivi dans le module Points bloquants de HappyPlace, visible de toute l''entreprise.',
      'VOIR LES POINTS BLOQUANTS', _lien,
      'Pour protéger les données, la pièce jointe ne figure pas dans cet e-mail.<br>'
      || 'Vous le recevez car vous êtes l''auteur de ce point bloquant.'),
    0);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US61 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_publication() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS us61_email_publication ON public.submissions;
CREATE TRIGGER us61_email_publication
  AFTER UPDATE OF status ON public.submissions
  FOR EACH ROW
  WHEN (NEW.kind = 'point bloquant'::public.submission_kind
        AND NEW.status = 'validée'::public.submission_status
        AND OLD.status IS DISTINCT FROM NEW.status
        AND NEW.blocker_id IS NOT NULL)
  EXECUTE FUNCTION private.preparer_email_publication();

-- ---------- US65 reprend private.nom_acteur() (même rendu) ----------
CREATE OR REPLACE FUNCTION private.preparer_email_refus()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/#mes-soumissions';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _motif text;
  _objet text;
BEGIN
  IF NOT private.adresse_distribuable(_auteur) THEN
    RAISE NOTICE 'US65 : adresse de l''auteur non distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;
  _motif := CASE NEW.rejection_category
              WHEN 'à clarifier' THEN 'À clarifier'
              WHEN 'en désaccord avec les process' THEN 'En désaccord avec les process'
              WHEN 'doublon' THEN 'Doublon'
              ELSE 'Autre' END;
  _objet := '[HappyPlace] Votre point bloquant n''a pas été retenu · ' || _motif;

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_refuse', NEW.id, ARRAY[_auteur], '{}', _objet,
    private.email_gabarit(
      _objet, 'POINT BLOQUANT', 'Votre point bloquant n''a pas été retenu',
      ARRAY[
        ARRAY['MOTIF', private.html_echappe(_motif)],
        ARRAY['REFUSÉ PAR', private.html_echappe(private.nom_acteur())],
        ARRAY['DATE DU REFUS', private.html_echappe(private.date_paris(now()))],
        ARRAY['SIGNALÉ LE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['SÉVÉRITÉ', private.tag_severite(NEW.severity)]
      ],
      'La raison détaillée est lisible dans « Mes soumissions ». Vous pouvez reformuler votre point et le renvoyer.',
      'VOIR MES SOUMISSIONS', _lien,
      'Pour protéger les données, la description, la raison détaillée et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car vous êtes l''auteur de ce point bloquant.'),
    0);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US65 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_refus() FROM public, anon, authenticated;

-- ---------- US62 : e-mail à chaque soumission d'une idée ----------
CREATE OR REPLACE FUNCTION private.preparer_email_idee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _managers text[];
  _admins text[];
  _a text[];
  _cc text[] := '{}';
  _ecartees int := 0;
  _assignes text;
  _objet text;
BEGIN
  SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _managers
    FROM public.manager_teams mt
    JOIN public.allowed_users u ON u.id = mt.allowed_user_id
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
   WHERE lower(btrim(mt.team)) = lower(btrim(NEW.team));

  -- Managers assignés (US30) ; l'admin si l'équipe n'a pas de manager joignable.
  SELECT count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
         coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
    INTO _ecartees, _a
    FROM unnest(_managers) e;
  IF cardinality(_a) = 0 THEN
    SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _admins
      FROM public.allowed_users u
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'admin'::public.app_role;
    SELECT _ecartees + count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
           coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
      INTO _ecartees, _a
      FROM unnest(_admins) e;
  END IF;

  IF private.adresse_distribuable(_auteur) THEN
    IF cardinality(_a) = 0 THEN
      _a := ARRAY[_auteur];
    ELSE
      _cc := ARRAY[_auteur];
    END IF;
  ELSIF _auteur <> '' THEN
    _ecartees := _ecartees + 1;
  END IF;

  IF cardinality(_a) = 0 THEN
    RAISE NOTICE 'US62 : aucune adresse distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  -- « Assigné à », comme dans l'app (US30) : les managers, sinon l'administration.
  SELECT string_agg(n || ', manager ' || NEW.team, ' · ' ORDER BY n) INTO _assignes
    FROM (
      SELECT DISTINCT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email) AS n
        FROM public.manager_teams mt
        JOIN public.allowed_users u ON u.id = mt.allowed_user_id
        JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
       WHERE lower(btrim(mt.team)) = lower(btrim(NEW.team))
    ) m;
  _assignes := coalesce(_assignes, 'Administration HappyPlace');
  _objet := '[HappyPlace] Nouvelle idée à examiner';

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('idee_soumise', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'IDÉE', 'Une nouvelle idée vient d''être soumise',
      ARRAY[
        ARRAY['TYPE', 'Idée'],
        ARRAY['DATE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['ASSIGNÉ À', private.html_echappe(_assignes)]
      ],
      'Elle est validée ou refusée dans HappyPlace.',
      'OUVRIR DANS HAPPYPLACE', _lien,
      'Pour protéger les données, la description et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car cette idée vous est assignée ou parce que vous en êtes l''auteur.'),
    _ecartees);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US62 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_idee() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS us62_email_idee ON public.submissions;
CREATE TRIGGER us62_email_idee
  AFTER INSERT ON public.submissions
  FOR EACH ROW
  WHEN (NEW.kind = 'idée'::public.submission_kind)
  EXECUTE FUNCTION private.preparer_email_idee();

COMMIT;

-- ============================================================
-- Tests de fumée de US61 et US62, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_us61_us62_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _pb uuid;
  _idea uuid;
  _n public.notifications;
  _team text := 'ZZ US61 fumée';
  _team2 text := 'ZZ US62 sans manager';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), (_team2) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us61.collab@fumee.happyplace.fr', _team, 'Thomas', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us61.manager@fumee.happyplace.fr', 'Karim', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email) VALUES ('us61.admin@fumee.happyplace.fr') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us62.seul@fumee.happyplace.fr', _team2, 'Léa', 'Seule') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');

    -- US62 : idée d'un collaborateur, managers en destinataires, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us61.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe')
      RETURNING id INTO _idea;
    SELECT * INTO _n FROM notifications n WHERE n.submission_id = _idea AND n.evenement = 'idee_soumise';
    _res := _res || jsonb_build_object('t', 'US62 : idée, managers assignés en destinataires, auteur en copie, sans l''admin',
      'ok', _n.id IS NOT NULL
            AND _n.destinataires = ARRAY['us61.manager@fumee.happyplace.fr']
            AND _n.copie = ARRAY['us61.collab@fumee.happyplace.fr']
            AND _n.objet = '[HappyPlace] Nouvelle idée à examiner'
            AND position('Karim Manager, manager ' || _team IN _n.corps_html) > 0
            AND position('Une idée pour' IN _n.corps_html) = 0,
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    -- US62 : équipe sans manager, l'admin
    PERFORM set_config('request.jwt.claims', '{"email":"us62.seul@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée sans manager')
      RETURNING id INTO _idea;
    SELECT * INTO _n FROM notifications n WHERE n.submission_id = _idea AND n.evenement = 'idee_soumise';
    _res := _res || jsonb_build_object('t', 'US62 : équipe sans manager, l''admin en destinataire',
      'ok', _n.id IS NOT NULL AND 'us61.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND _n.copie = ARRAY['us62.seul@fumee.happyplace.fr']
            AND position('>Administration HappyPlace<' IN _n.corps_html) > 0,
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    -- US61 : publication d'un point bloquant, e-mail à l'auteur seul
    PERFORM set_config('request.jwt.claims', '{"email":"us61.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical')
      RETURNING id INTO _pb;
    PERFORM set_config('request.jwt.claims', '{"email":"us61.manager@fumee.happyplace.fr"}', true);
    PERFORM publish_blocker_submission(_pb, 'CV absents des fiches candidats', _team, 'critical');
    SELECT * INTO _n FROM notifications n WHERE n.submission_id = _pb AND n.evenement = 'point_bloquant_publie';
    _res := _res || jsonb_build_object('t', 'US61 : publication, e-mail à l''auteur seul avec titre, statut OUVERT et lien',
      'ok', _n.id IS NOT NULL
            AND _n.destinataires = ARRAY['us61.collab@fumee.happyplace.fr'] AND cardinality(_n.copie) = 0
            AND position('CV absents des fiches candidats' IN _n.corps_html) > 0
            AND position('>OUVERT<' IN _n.corps_html) > 0
            AND position('Karim Manager, manager' IN _n.corps_html) > 0
            AND position('#points-bloquants' IN _n.corps_html) > 0
            AND position('Les CV ne remontent' IN _n.corps_html) = 0,
      'd', coalesce(_n.objet, 'aucune ligne'));

    -- US65 inchangé avec private.nom_acteur()
    PERFORM set_config('request.jwt.claims', '{"email":"us61.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le badge ne marche plus.', 'point bloquant', 'warning')
      RETURNING id INTO _pb;
    PERFORM set_config('request.jwt.claims', '{"email":"us61.manager@fumee.happyplace.fr"}', true);
    UPDATE submissions SET status = 'refusée', rejection_category = 'doublon', rejection_note = 'Déjà signalé'
     WHERE id = _pb;
    SELECT * INTO _n FROM notifications n WHERE n.submission_id = _pb AND n.evenement = 'point_bloquant_refuse';
    _res := _res || jsonb_build_object('t', 'US65 : « Refusé par » inchangé avec le nom de la personne qui agit',
      'ok', _n.id IS NOT NULL AND position('Karim Manager, manager' IN _n.corps_html) > 0,
      'd', coalesce(_n.objet, 'aucune ligne'));

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US61 et US62', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us61_us62_smoke_tests() FROM public, anon, authenticated;

-- Le test US60 « une idée ne prépare pas d'e-mail de point bloquant » ne compte
-- plus que les e-mails de point bloquant : une idée prépare désormais l'e-mail US62.
CREATE OR REPLACE FUNCTION private.run_us60_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _n public.notifications;
  _cnt int;
  _team text := 'ZZ US60 fumée';
  _team2 text := 'ZZ US60 sans manager';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), (_team2) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.collab@fumee.happyplace.fr', _team, 'Thomas', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.manager@fumee.happyplace.fr', 'Karim', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.demo@biggerboat.example', 'Julie', 'Démo') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email) VALUES ('us60.admin@fumee.happyplace.fr') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.seul@fumee.happyplace.fr', _team2, 'Léa', 'Seule') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');

    -- Point bloquant d'un collaborateur : managers et admin en destinataires, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.collab@fumee.happyplace.fr' = ANY (n.copie) ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : managers de l''équipe et admin en destinataires, auteur en copie',
      'ok', _n.id IS NOT NULL
            AND 'us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.collab@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.copie = ARRAY['us60.collab@fumee.happyplace.fr'],
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    _res := _res || jsonb_build_object('t', 'US60 : adresse de démo (.example) écartée',
      'ok', NOT ('us60.demo@biggerboat.example' = ANY (_n.destinataires)) AND _n.adresses_ecartees >= 1,
      'd', coalesce(_n.adresses_ecartees::text, '?') || ' écartée(s)');

    _res := _res || jsonb_build_object('t', 'US60 : objet, sévérité, date, assignés et lien ; ni description ni nom d''auteur',
      'ok', _n.objet = '[HappyPlace] Nouveau point bloquant à traiter · Critique'
            AND position('CRITIQUE' IN _n.corps_html) > 0
            AND position(private.date_paris(now()) IN _n.corps_html) > 0
            AND position('Karim Manager, manager ' || _team IN _n.corps_html) > 0
            AND position('Julie Démo, manager ' || _team IN _n.corps_html) > 0
            AND position('Administration HappyPlace' IN _n.corps_html) > 0
            AND position('https://happy-place-pascaline.pascalinemillet.workers.dev/' IN _n.corps_html) > 0
            AND position('Les CV ne remontent' IN _n.corps_html) = 0
            AND position('Thomas Auteur' IN _n.corps_html) = 0,
      'd', coalesce(_n.objet, '?'));

    -- Une idée ne déclenche pas US60
    SELECT count(*) INTO _cnt FROM notifications WHERE evenement = 'point_bloquant_soumis';
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe');
    _res := _res || jsonb_build_object('t', 'US60 : une idée ne prépare pas d''e-mail de point bloquant',
      'ok', (SELECT count(*) FROM notifications WHERE evenement = 'point_bloquant_soumis') = _cnt,
      'd', (SELECT count(*) FROM notifications WHERE evenement = 'point_bloquant_soumis')::text || ' ligne(s)');

    -- Équipe sans manager : l'admin seul, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.seul@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le badge ne fonctionne plus à l''accueil.', 'point bloquant', 'warning');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.seul@fumee.happyplace.fr' = ANY (n.copie) LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : équipe sans manager, l''admin seul et l''auteur en copie',
      'ok', _n.id IS NOT NULL AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.objet LIKE '%· Avertissement'
            AND position('>Administration HappyPlace<' IN _n.corps_html) > 0,
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    -- Un admin qui signale : jamais en double
    PERFORM set_config('request.jwt.claims', '{"email":"us60.admin@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('Admin', 'x', 'Le serveur de fichiers est lent.', 'point bloquant', 'info');
    SELECT * INTO _n FROM notifications n
     WHERE n.objet LIKE '%· Information' ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : l''auteur n''apparaît jamais en double',
      'ok', _n.id IS NOT NULL
            AND (SELECT count(*) FROM unnest(_n.destinataires || _n.copie) e
                  WHERE e = 'us60.admin@fumee.happyplace.fr') = 1,
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    -- L'app ne lit pas la table d'envoi
    _res := _res || jsonb_build_object('t', 'US60 : la table d''envoi est fermée aux comptes de l''app',
      'ok', NOT has_table_privilege('authenticated', 'public.notifications', 'SELECT')
            AND NOT has_table_privilege('anon', 'public.notifications', 'SELECT'),
      'd', 'droits vérifiés');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US60', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us60_smoke_tests() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.run_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  SELECT * FROM private.run_base_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f1_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us60_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us65_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us61_us62_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

-- ---------- 20261102180000_assignes_email.sql ----------
-- ============================================================
-- Lot 2 (T12) : « Assigné à » plus court dans les e-mails US60 et US62
-- ============================================================
-- Constat du 2026-11-02 : la ligne répétait « manager <équipe> » après chaque
-- nom. Désormais : « Karim Haddad, manager Direction Commerciale » pour un
-- manager ; « Julie Moreau, Pascaline Millet, managers Pôle Data et IA » pour
-- plusieurs.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

CREATE OR REPLACE FUNCTION private.ligne_managers(_team text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $$
  SELECT CASE count(*)
           WHEN 0 THEN NULL
           WHEN 1 THEN min(n) || ', manager ' || _team
           ELSE string_agg(n, ', ' ORDER BY n) || ', managers ' || _team END
    FROM (
      SELECT DISTINCT coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), u.email) AS n
        FROM public.manager_teams mt
        JOIN public.allowed_users u ON u.id = mt.allowed_user_id
        JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
       WHERE lower(btrim(mt.team)) = lower(btrim(_team))
    ) m
$$;
REVOKE ALL ON FUNCTION private.ligne_managers(text) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.preparer_email_point_bloquant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _candidats text[];
  _a text[];
  _cc text[] := '{}';
  _ecartees int;
  _assignes text;
  _objet text;
BEGIN
  SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _candidats
    FROM public.allowed_users u
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id
   WHERE (r.role = 'manager'::public.app_role
          AND EXISTS (SELECT 1 FROM public.manager_teams mt
                       WHERE mt.allowed_user_id = u.id
                         AND lower(btrim(mt.team)) = lower(btrim(NEW.team))))
      OR r.role = 'admin'::public.app_role;

  SELECT count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
         coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
    INTO _ecartees, _a
    FROM unnest(_candidats) e;

  IF private.adresse_distribuable(_auteur) THEN
    IF cardinality(_a) = 0 THEN
      _a := ARRAY[_auteur];
    ELSE
      _cc := ARRAY[_auteur];
    END IF;
  ELSIF _auteur <> '' THEN
    _ecartees := _ecartees + 1;
  END IF;

  IF cardinality(_a) = 0 THEN
    RAISE NOTICE 'US60 : aucune adresse distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  _assignes := private.ligne_managers(NEW.team);
  _assignes := concat_ws(' · ', _assignes, 'Administration HappyPlace');
  _objet := '[HappyPlace] Nouveau point bloquant à traiter · ' || private.libelle_severite(NEW.severity);

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('point_bloquant_soumis', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'POINT BLOQUANT', 'Un point bloquant vient d''être signalé',
      ARRAY[
        ARRAY['TYPE', 'Point bloquant'],
        ARRAY['SÉVÉRITÉ', private.tag_severite(NEW.severity)],
        ARRAY['DATE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['ASSIGNÉ À', private.html_echappe(_assignes)]
      ],
      'La première personne qui le traite le publie ou le refuse dans HappyPlace.',
      'OUVRIR DANS HAPPYPLACE', _lien,
      'Pour protéger les données, la description et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car ce point vous est assigné ou parce que vous en êtes l''auteur.'),
    _ecartees);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US60 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_point_bloquant() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.preparer_email_idee()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _lien constant text := 'https://happy-place-pascaline.pascalinemillet.workers.dev/';
  _auteur text := lower(btrim(coalesce(NEW.submitted_by_email, '')));
  _managers text[];
  _admins text[];
  _a text[];
  _cc text[] := '{}';
  _ecartees int := 0;
  _assignes text;
  _objet text;
BEGIN
  SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _managers
    FROM public.manager_teams mt
    JOIN public.allowed_users u ON u.id = mt.allowed_user_id
    JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'manager'::public.app_role
   WHERE lower(btrim(mt.team)) = lower(btrim(NEW.team));

  -- Managers assignés (US30) ; l'admin si l'équipe n'a pas de manager joignable.
  SELECT count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
         coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
    INTO _ecartees, _a
    FROM unnest(_managers) e;
  IF cardinality(_a) = 0 THEN
    SELECT coalesce(array_agg(DISTINCT lower(btrim(u.email))), '{}') INTO _admins
      FROM public.allowed_users u
      JOIN public.allowed_user_roles r ON r.allowed_user_id = u.id AND r.role = 'admin'::public.app_role;
    SELECT _ecartees + count(*) FILTER (WHERE NOT private.adresse_distribuable(e)),
           coalesce(array_agg(e ORDER BY e) FILTER (WHERE private.adresse_distribuable(e) AND e <> _auteur), '{}')
      INTO _ecartees, _a
      FROM unnest(_admins) e;
  END IF;

  IF private.adresse_distribuable(_auteur) THEN
    IF cardinality(_a) = 0 THEN
      _a := ARRAY[_auteur];
    ELSE
      _cc := ARRAY[_auteur];
    END IF;
  ELSIF _auteur <> '' THEN
    _ecartees := _ecartees + 1;
  END IF;

  IF cardinality(_a) = 0 THEN
    RAISE NOTICE 'US62 : aucune adresse distribuable pour la soumission %', NEW.id;
    RETURN NULL;
  END IF;

  -- « Assigné à », comme dans l'app (US30) : les managers, sinon l'administration.
  _assignes := private.ligne_managers(NEW.team);
  _assignes := coalesce(_assignes, 'Administration HappyPlace');
  _objet := '[HappyPlace] Nouvelle idée à examiner';

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('idee_soumise', NEW.id, _a, _cc, _objet,
    private.email_gabarit(
      _objet, 'IDÉE', 'Une nouvelle idée vient d''être soumise',
      ARRAY[
        ARRAY['TYPE', 'Idée'],
        ARRAY['DATE', private.html_echappe(private.date_paris(NEW.created_at))],
        ARRAY['ASSIGNÉ À', private.html_echappe(_assignes)]
      ],
      'Elle est validée ou refusée dans HappyPlace.',
      'OUVRIR DANS HAPPYPLACE', _lien,
      'Pour protéger les données, la description et la pièce jointe ne figurent pas dans cet e-mail.<br>'
      || 'Vous le recevez car cette idée vous est assignée ou parce que vous en êtes l''auteur.'),
    _ecartees);
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'US62 : e-mail non préparé pour la soumission % (%)', NEW.id, SQLERRM;
  RETURN NULL;
END
$function$;
REVOKE ALL ON FUNCTION private.preparer_email_idee() FROM public, anon, authenticated;

COMMIT;

BEGIN;

CREATE OR REPLACE FUNCTION private.run_us60_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _n public.notifications;
  _cnt int;
  _team text := 'ZZ US60 fumée';
  _team2 text := 'ZZ US60 sans manager';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team), (_team2) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.collab@fumee.happyplace.fr', _team, 'Thomas', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.manager@fumee.happyplace.fr', 'Karim', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us60.demo@biggerboat.example', 'Julie', 'Démo') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);
    INSERT INTO allowed_users(email) VALUES ('us60.admin@fumee.happyplace.fr') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'admin');
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us60.seul@fumee.happyplace.fr', _team2, 'Léa', 'Seule') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');

    -- Point bloquant d'un collaborateur : managers et admin en destinataires, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les CV ne remontent plus dans les fiches.', 'point bloquant', 'critical');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.collab@fumee.happyplace.fr' = ANY (n.copie) ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : managers de l''équipe et admin en destinataires, auteur en copie',
      'ok', _n.id IS NOT NULL
            AND 'us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.collab@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.copie = ARRAY['us60.collab@fumee.happyplace.fr'],
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    _res := _res || jsonb_build_object('t', 'US60 : adresse de démo (.example) écartée',
      'ok', NOT ('us60.demo@biggerboat.example' = ANY (_n.destinataires)) AND _n.adresses_ecartees >= 1,
      'd', coalesce(_n.adresses_ecartees::text, '?') || ' écartée(s)');

    _res := _res || jsonb_build_object('t', 'US60 : objet, sévérité, date, assignés et lien ; ni description ni nom d''auteur',
      'ok', _n.objet = '[HappyPlace] Nouveau point bloquant à traiter · Critique'
            AND position('CRITIQUE' IN _n.corps_html) > 0
            AND position(private.date_paris(now()) IN _n.corps_html) > 0
            AND position('Julie Démo, Karim Manager, managers ' || _team || ' · Administration HappyPlace' IN _n.corps_html) > 0
            AND position('Administration HappyPlace' IN _n.corps_html) > 0
            AND position('https://happy-place-pascaline.pascalinemillet.workers.dev/' IN _n.corps_html) > 0
            AND position('Les CV ne remontent' IN _n.corps_html) = 0
            AND position('Thomas Auteur' IN _n.corps_html) = 0,
      'd', coalesce(_n.objet, '?'));

    -- Une idée ne déclenche pas US60
    SELECT count(*) INTO _cnt FROM notifications WHERE evenement = 'point_bloquant_soumis';
    INSERT INTO submissions(author_name, team, content) VALUES ('x', 'x', 'Une idée pour l''équipe');
    _res := _res || jsonb_build_object('t', 'US60 : une idée ne prépare pas d''e-mail de point bloquant',
      'ok', (SELECT count(*) FROM notifications WHERE evenement = 'point_bloquant_soumis') = _cnt,
      'd', (SELECT count(*) FROM notifications WHERE evenement = 'point_bloquant_soumis')::text || ' ligne(s)');

    -- Équipe sans manager : l'admin seul, auteur en copie
    PERFORM set_config('request.jwt.claims', '{"email":"us60.seul@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le badge ne fonctionne plus à l''accueil.', 'point bloquant', 'warning');
    SELECT * INTO _n FROM notifications n
     WHERE 'us60.seul@fumee.happyplace.fr' = ANY (n.copie) LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : équipe sans manager, l''admin seul et l''auteur en copie',
      'ok', _n.id IS NOT NULL AND 'us60.admin@fumee.happyplace.fr' = ANY (_n.destinataires)
            AND NOT ('us60.manager@fumee.happyplace.fr' = ANY (_n.destinataires))
            AND _n.objet LIKE '%· Avertissement'
            AND position('>Administration HappyPlace<' IN _n.corps_html) > 0,
      'd', coalesce(array_to_string(_n.destinataires, ', '), 'aucune ligne'));

    -- Un admin qui signale : jamais en double
    PERFORM set_config('request.jwt.claims', '{"email":"us60.admin@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('Admin', 'x', 'Le serveur de fichiers est lent.', 'point bloquant', 'info');
    SELECT * INTO _n FROM notifications n
     WHERE n.objet LIKE '%· Information' ORDER BY n.created_at DESC LIMIT 1;
    _res := _res || jsonb_build_object('t', 'US60 : l''auteur n''apparaît jamais en double',
      'ok', _n.id IS NOT NULL
            AND (SELECT count(*) FROM unnest(_n.destinataires || _n.copie) e
                  WHERE e = 'us60.admin@fumee.happyplace.fr') = 1,
      'd', coalesce(array_to_string(_n.destinataires, ', ') || ' | cc ' || array_to_string(_n.copie, ', '), 'aucune ligne'));

    -- L'app ne lit pas la table d'envoi
    _res := _res || jsonb_build_object('t', 'US60 : la table d''envoi est fermée aux comptes de l''app',
      'ok', NOT has_table_privilege('authenticated', 'public.notifications', 'SELECT')
            AND NOT has_table_privilege('anon', 'public.notifications', 'SELECT'),
      'd', 'droits vérifiés');

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US60', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us60_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

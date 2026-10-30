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

SELECT * FROM private.run_smoke_tests();

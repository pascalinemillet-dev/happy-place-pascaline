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
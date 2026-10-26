-- ============================================================
-- Happy Place — données de démo (version élèves)
-- ============================================================
-- Reprend le contenu de l'app de démo au 16 octobre 2026.
-- Les dates sont calculées à partir du jour de l'installation, pour que le
-- dashboard paraisse « vivant ». À exécuter APRÈS toutes les migrations.
-- Peut être relancé : il remet les contenus dans leur état de départ.

BEGIN;

-- 0. On repart d'une base propre (les premières migrations contiennent une ancienne démo)
DELETE FROM public.submissions;
DELETE FROM public.news;
DELETE FROM public.blockers;
DELETE FROM public.metrics;          -- vide aussi metrics_history (trigger)
DELETE FROM public.departure_notices;

-- 1. Équipes
INSERT INTO public.teams (name, is_reserved) VALUES ('Admin', true) ON CONFLICT DO NOTHING;
INSERT INTO public.teams (name) VALUES
  ('Accounting'), ('Direction Commerciale'), ('Direction Conseil'), ('Direction recrutement'),
  ('Finance'), ('Legal'), ('Marketing'), ('Opérations'), ('People'), ('Pôle Data et IA'),
  ('Product'), ('Relation clients')
ON CONFLICT DO NOTHING;

-- Équipes héritées de l'ancienne démo, plus utilisées
DELETE FROM public.teams t
 WHERE NOT t.is_reserved
   AND t.name NOT IN ('Accounting', 'Direction Commerciale', 'Direction Conseil', 'Direction recrutement',
                      'Finance', 'Legal', 'Marketing', 'Opérations', 'People', 'Pôle Data et IA',
                      'Product', 'Relation clients')
   AND NOT EXISTS (SELECT 1 FROM public.allowed_users u WHERE u.team = t.name)
   AND NOT EXISTS (SELECT 1 FROM public.manager_teams m WHERE m.team = t.name);

-- 2. Membres fictifs de Bigger Boat (sans compte de connexion : ils peuplent
--    l'écran « Utilisateurs » et servent de managers aux équipes)
WITH people(email, first_name, last_name, role, team) AS (
  VALUES
    ('admin@biggerboat.example',         'Claire',  'Vasseur', 'admin',         NULL),
    ('sophie.marchand@biggerboat.example','Sophie',  'Marchand','manager',       'Product'),
    ('karim.haddad@biggerboat.example',  'Karim',   'Haddad',  'manager',       'Direction Commerciale'),
    ('julie.moreau@biggerboat.example',  'Julie',   'Moreau',  'manager',       'People'),
    ('thomas.diallo@biggerboat.example', 'Thomas',  'Diallo',  'collaborateur', 'Direction Commerciale'),
    ('nina.petit@biggerboat.example',    'Nina',    'Petit',   'collaborateur', 'Product'),
    ('hugo.martin@biggerboat.example',   'Hugo',    'Martin',  'collaborateur', 'People'),
    ('lea.bernard@biggerboat.example',   'Léa',     'Bernard', 'collaborateur', 'Pôle Data et IA'),
    ('julien.caron@biggerboat.example',  'Julien',  'Caron',   'collaborateur', 'Marketing'),
    ('sofia.benali@biggerboat.example',  'Sofia',   'Benali',  'collaborateur', 'Direction Commerciale')
), up AS (
  INSERT INTO public.allowed_users (email, first_name, last_name, team)
  SELECT email, first_name, last_name, CASE WHEN role = 'collaborateur' THEN team END FROM people
  ON CONFLICT (email) DO UPDATE SET first_name = excluded.first_name, last_name = excluded.last_name, team = excluded.team
  RETURNING id, email
)
INSERT INTO public.allowed_user_roles (allowed_user_id, role)
SELECT up.id, p.role::public.app_role FROM up JOIN people p ON p.email = up.email
ON CONFLICT (allowed_user_id) DO UPDATE SET role = excluded.role;

INSERT INTO public.manager_teams (allowed_user_id, team)
SELECT u.id, m.team
FROM (VALUES
  ('sophie.marchand@biggerboat.example', 'Product'),
  ('karim.haddad@biggerboat.example',    'Direction Commerciale'),
  ('karim.haddad@biggerboat.example',    'Marketing'),
  ('julie.moreau@biggerboat.example',    'People'),
  ('julie.moreau@biggerboat.example',    'Pôle Data et IA')
) AS m(email, team)
JOIN public.allowed_users u ON u.email = m.email
ON CONFLICT DO NOTHING;

-- 3. Actualités
INSERT INTO public.news (title, body, author, status, created_at) VALUES
('Meet-up candidats Cloud & DevOps', 'Une rencontre candidats et entreprises est organisée le 6 novembre autour des métiers Platform Engineering, SRE et Cloud.', 'Communauté Tech', 'publiée', now() - interval '31 days'),
('Trois consultants rejoignent le cabinet', 'Bienvenue à Inès, spécialisée Product & Design, Mathieu sur le pôle Cloud et Nora sur les profils Data.', 'People & Culture', 'publiée', now() - interval '29 days'),
('Observatoire des salaires IT 2026', 'La synthèse des rémunérations par métier, niveau d’expérience et région est disponible pour préparer les briefs clients.', 'Pôle Études', 'publiée', now() - interval '27 days'),
('Partenariat avec l’école Ada Tech School', 'Le cabinet accompagnera les promotions sur les simulations d’entretien, la préparation du portfolio et la mise en relation avec nos clients.', 'Relations Écoles', 'publiée', now() - interval '25 days'),
('Priorités commerciales du quatrième trimestre', 'Nos priorités : développer les comptes SaaS B2B, accélérer les mandats Data & IA et maintenir un suivi candidat hebdomadaire.', 'Direction Commerciale', 'publiée', now() - interval '23 days'),
('Nouvelle grille d’évaluation des compétences tech', 'La nouvelle trame d’entretien couvre désormais l’expertise technique, la collaboration, l’impact produit et les attentes managériales.', 'Direction Recrutement', 'publiée', now() - interval '21 days'),
('Petit-déjeuner CTO : attirer les profils pénuriques', 'Rendez-vous avec nos clients CTO et DRH pour partager les pratiques qui accélèrent les recrutements sur les métiers en tension.', 'Relations Clients', 'publiée', now() - interval '20 days'),
('Migration vers notre nouvel ATS', 'Le déploiement du nouvel outil de suivi des candidatures est prévu dans trois semaines. Une reprise des dossiers actifs sera réalisée en amont.', 'Opérations', 'publiée', now() - interval '19 days'),
('Renforcement du pôle Cybersécurité', 'Deux consultants spécialisés rejoignent l’équipe pour accompagner les recrutements SOC, GRC et sécurité cloud.', 'Direction Recrutement', 'publiée', now() - interval '19 days'),
('Lancement du vivier Data & IA', 'Centralisation en cours de nos candidats Data Engineer, ML Engineer et AI Product Manager qualifiés.', 'Pôle Data & IA', 'publiée', now() - interval '18 days'),
('Bilan du marché tech — septembre 2026', 'La demande reste soutenue sur les profils cybersécurité, cloud et data. Le délai moyen de recrutement observé ce mois-ci est de 31 jours.', 'Direction Conseil', 'publiée', now() - interval '18 days');

-- 4. Soumissions (idées et demandes des équipes)
INSERT INTO public.submissions (author_name, team, content, status, created_at) VALUES
('Thomas Diallo',  'Direction Commerciale', 'Réserver les points de qualification client aux seuls consultants seniors.', 'validée', now() - interval '23 days'),
('Nina Petit',     'Product',               'Créer un vivier partagé de Product Designers seniors avec portfolio vérifié.', 'validée', now() - interval '21 days'),
('Hugo Martin',    'People',                'Automatiser les relances candidats après sept jours sans retour du client.', 'validée', now() - interval '20 days'),
('Léa Bernard',    'Pôle Data et IA',       'Souscrire un accès à une plateforme d’évaluation SQL et Python pour les profils Data.', 'validée', now() - interval '18 days'),
('Julien Caron',   'Marketing',             'Publier chaque mois une analyse courte des tendances de recrutement dans la tech.', 'validée', now() - interval '18 days'),
('Sofia Benali',   'Direction Commerciale', 'Mettre en place un compte rendu client systématique sous 24 heures après chaque entretien candidat.', 'validée', now() - interval '17 days'),
('Antoine Mercier','Product',               'Organiser une session de sourcing dédiée aux profils SRE et Platform Engineer disponibles sous deux mois.', 'validée', now() - interval '17 days'),
('Camille Roux',   'Product',               'Créer une fiche de brief standardisée pour les recrutements Product Manager et Product Designer.', 'validée', now() - interval '17 days'),
-- En attente : de quoi tester la validation côté manager… et l'absence de relance
('Nina Petit',     'Product',               'À qui dois-je m’adresser pour obtenir un accès au job board premium ?', 'en attente', now() - interval '12 days'),
('Thomas Diallo',  'Direction Commerciale', 'Les indicateurs du dashboard ne correspondent pas aux chiffres de notre tableau d’équipe.', 'en attente', now() - interval '9 days'),
('Léa Bernard',    'Pôle Data et IA',       'Proposition : un déjeuner mensuel pour accueillir les nouveaux arrivants.', 'en attente', now() - interval '4 days'),
('Julien Caron',   'Marketing',             'Ajouter une rubrique « qui fait quoi » pour savoir à qui s’adresser selon le sujet.', 'en attente', now() - interval '1 day');

INSERT INTO public.submissions (author_name, team, content, status, rejection_category, rejection_note, created_at) VALUES
('Hugo Martin', 'People', 'Prime trimestrielle par équipe plutôt qu’individuelle.', 'en attente', NULL, NULL, now() - interval '15 days');
UPDATE public.submissions
   SET status = 'refusée', rejection_category = 'en désaccord avec les process',
       rejection_note = 'La politique de rémunération est fixée au niveau de la direction.'
 WHERE content = 'Prime trimestrielle par équipe plutôt qu’individuelle.';

-- 5. Points bloquants
INSERT INTO public.blockers (title, description, department, severity, status, created_at, updated_at) VALUES
('Pénurie de profils DevSecOps seniors', 'Trois mandats prioritaires ouverts depuis plus de 30 jours avec peu de candidats disponibles en Île-de-France.', 'CLOUD & CYBERSÉCURITÉ', 'critical', 'EN COURS', now() - interval '17 days', now() - interval '17 days'),
('Brief client incomplet — Head of Product', 'Les critères de séniorité et le périmètre managérial doivent être clarifiés avant la reprise du sourcing.', 'PRODUCT TEAM', 'warning', 'EN COURS', now() - interval '17 days', now() - interval '17 days'),
('Délai de validation des tests techniques', 'Le retour client dépasse actuellement cinq jours et entraîne la perte de candidats en phase finale.', 'RELATIONS CLIENTS', 'critical', 'OUVERT', now() - interval '17 days', now() - interval '17 days'),
('Faible taux de réponse sur les profils Data', 'Le taux de réponse aux approches directes est passé sous 18 % sur les Data Engineers seniors.', 'DATA & IA', 'warning', 'SURVEILLANCE', now() - interval '17 days', now() - interval '17 days'),
('Capacité limitée sur le pôle Cybersécurité', 'Deux nouveaux mandats nécessitent un renfort temporaire en sourcing spécialisé.', 'DIRECTION RECRUTEMENT', 'warning', 'SURVEILLANCE', now() - interval '17 days', now() - interval '17 days'),
('Import des candidatures dans l’ATS', 'Les dossiers actifs ont été repris et contrôlés dans le nouvel outil de suivi.', 'OPÉRATIONS', 'warning', 'EN COURS', now() - interval '17 days', now() - interval '17 days');
UPDATE public.blockers SET status = 'RÉSOLU' WHERE title = 'Import des candidatures dans l’ATS';

-- 6. Indicateurs (l'historique d'abord, puis la valeur actuelle)
INSERT INTO public.metrics_history (metric_key, value, recorded_at) VALUES
('training_kpi', 38.6, now() - interval '12 days'),
('active_users', 42,   now() - interval '12 days'),
('active_users', 45,   now() - interval '8 days'),
('nps',          71,   now() - interval '12 days'),
('nps',          72,   now() - interval '8 days'),
('engagement',   84.3, now() - interval '12 days'),
('turnover',     31,   now() - interval '12 days'),
('absenteeism',  27.8, now() - interval '12 days'),
('open_positions', 63, now() - interval '12 days'),
('training_hours', 186, now() - interval '12 days');

-- Indicateurs mis à jour il y a 8 jours (taux de placement, missions, NPS) ou 12 jours (les autres)
INSERT INTO public.metrics (key, label, value, unit, updated_at) VALUES
('training_kpi',   'Taux de placement',           40.6, '%', now() - interval '8 days'),
('active_users',   'Missions actives',            34.2, NULL, now() - interval '8 days'),
('nps',            'NPS candidats',               71,   NULL, now() - interval '8 days'),
('engagement',     'Taux d’acceptation',          84.3, '%', now() - interval '12 days'),
('turnover',       'Délai moyen de recrutement',  31,   'j', now() - interval '12 days'),
('absenteeism',    'Taux de réponse candidats',   27.8, '%', now() - interval '12 days'),
('open_positions', 'Postes ouverts',              63,   NULL, now() - interval '12 days'),
('training_hours', 'Entretiens réalisés',         186,  NULL, now() - interval '12 days');

-- Le trigger d'historique a ajouté une ligne datée d'aujourd'hui : on la recale
-- sur la date de mise à jour, et on retire les doublons de valeur inchangée.
UPDATE public.metrics_history h SET recorded_at = m.updated_at
  FROM public.metrics m
 WHERE h.metric_key = m.key AND h.recorded_at > now() - interval '1 minute';
DELETE FROM public.metrics_history a USING public.metrics_history b
 WHERE a.metric_key = b.metric_key AND a.recorded_at = b.recorded_at AND a.value = b.value AND a.id > b.id;

-- Historique des demandes : la date de création et la décision suivent la date de la demande
UPDATE public.submission_status_history h
   SET changed_at = s.created_at + CASE WHEN h.old_status IS NULL THEN interval '0' ELSE interval '1 day' END
  FROM public.submissions s
 WHERE h.submission_id = s.id;

COMMIT;

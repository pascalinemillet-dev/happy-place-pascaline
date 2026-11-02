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

SELECT * FROM private.run_smoke_tests();

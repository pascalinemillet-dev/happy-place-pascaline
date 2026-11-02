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

SELECT * FROM private.run_smoke_tests();

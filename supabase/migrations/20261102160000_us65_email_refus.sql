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

SELECT * FROM private.run_smoke_tests();

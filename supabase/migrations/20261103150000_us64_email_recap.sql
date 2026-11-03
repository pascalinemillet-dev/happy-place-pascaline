-- ============================================================
-- US64 révisée : « M'envoyer par e-mail » du récap, envoyé par Make
-- ============================================================
-- Décision de Pascaline du 2026-11-03 : l'e-mail du récap part automatiquement par
-- la table d'envoi (public.notifications), le webhook de base Supabase et le scénario
-- Make R7, comme les autres e-mails. Le récap ne contient que des titres, des phrases
-- de l'IA (sans nom de personne) et des débuts de description quand l'IA ne répond pas :
-- Pascaline juge qu'il ne contient pas de données sensibles. Exception assumée à la
-- règle « ni description dans les e-mails » de US60.
--
-- public.send_team_recap_email : réservée aux managers ; destinataire = le manager
-- connecté, jamais une autre adresse ; au plus 10 envois par heure.
-- À faire dans Make : ajouter `evenement = recap_point_equipe` au filtre du scénario R7
-- (ou le supprimer).
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_evenement_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_evenement_check
  CHECK (evenement IN ('point_bloquant_soumis', 'point_bloquant_refuse',
                       'point_bloquant_publie', 'idee_soumise', 'recap_point_equipe'));

CREATE OR REPLACE FUNCTION public.send_team_recap_email(_objet text, _html text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _email text := lower(nullif(auth.jwt() ->> 'email', ''));
  _o text := left(btrim(coalesce(_objet, '')), 200);
  _sent int;
BEGIN
  IF _email IS NULL OR NOT private.is_allowed() THEN
    RAISE EXCEPTION 'Session expirée';
  END IF;
  IF private.current_app_role() IS DISTINCT FROM 'manager'::public.app_role THEN
    RAISE EXCEPTION 'Le récap du point d''équipe est réservé aux managers.';
  END IF;
  IF NOT private.adresse_distribuable(_email) THEN
    RAISE EXCEPTION 'Votre adresse ne peut pas recevoir d''e-mail : utilisez « Copier ».';
  END IF;
  IF _html IS NULL OR char_length(_html) < 20 OR char_length(_html) > 200000 THEN
    RAISE EXCEPTION 'Récap vide ou trop long pour être envoyé.';
  END IF;
  SELECT count(*) INTO _sent FROM public.notifications
   WHERE evenement = 'recap_point_equipe'
     AND destinataires = ARRAY[_email]
     AND created_at > now() - interval '1 hour';
  IF _sent >= 10 THEN
    RAISE EXCEPTION 'Trop d''envois en une heure : utilisez « Copier » ou réessayez plus tard.';
  END IF;

  INSERT INTO public.notifications (evenement, submission_id, destinataires, copie, objet, corps_html, adresses_ecartees)
  VALUES ('recap_point_equipe', NULL, ARRAY[_email], '{}',
          '[HappyPlace] ' || coalesce(nullif(_o, ''), 'Point d''équipe'), _html, 0);
END
$function$;
REVOKE ALL ON FUNCTION public.send_team_recap_email(text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.send_team_recap_email(text, text) TO authenticated;

COMMIT;

-- ============================================================
-- Tests de fumée, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_us64_email_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _n public.notifications;
  _i int;
  _html constant text := '<div>Point d''équipe · récap de test</div>';
BEGIN
  BEGIN
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us64.manager@fumee.happyplace.fr', 'Kesha', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us64.collab@fumee.happyplace.fr', 'Gontran', 'Collab') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us64.manager@fumee.example', 'Démo', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');

    PERFORM set_config('request.jwt.claims', '{"email":"us64.manager@fumee.happyplace.fr"}', true);
    PERFORM public.send_team_recap_email('Point d''équipe · Pôle test', _html);
    SELECT * INTO _n FROM notifications WHERE evenement = 'recap_point_equipe'
     AND destinataires = ARRAY['us64.manager@fumee.happyplace.fr'];
    _res := _res || jsonb_build_object('t', 'US64 : le récap part au seul manager connecté, par la table d''envoi',
      'ok', _n.id IS NOT NULL AND cardinality(_n.copie) = 0
            AND _n.objet = '[HappyPlace] Point d''équipe · Pôle test' AND _n.corps_html = _html,
      'd', coalesce(_n.objet, 'aucune ligne'));

    PERFORM set_config('request.jwt.claims', '{"email":"us64.collab@fumee.happyplace.fr"}', true);
    BEGIN
      PERFORM public.send_team_recap_email('x', _html);
      _res := _res || jsonb_build_object('t', 'US64 : un collaborateur ne peut pas envoyer de récap', 'ok', false, 'd', 'accepté à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US64 : un collaborateur ne peut pas envoyer de récap', 'ok', true, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"us64.manager@fumee.example"}', true);
    BEGIN
      PERFORM public.send_team_recap_email('x', _html);
      _res := _res || jsonb_build_object('t', 'US64 : une adresse non distribuable est refusée', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US64 : une adresse non distribuable est refusée', 'ok', true, 'd', SQLERRM);
    END;

    PERFORM set_config('request.jwt.claims', '{"email":"us64.manager@fumee.happyplace.fr"}', true);
    FOR _i IN 2..10 LOOP
      PERFORM public.send_team_recap_email('x', _html);
    END LOOP;
    BEGIN
      PERFORM public.send_team_recap_email('x', _html);
      _res := _res || jsonb_build_object('t', 'US64 : au plus 10 récaps par heure et par manager', 'ok', false, 'd', '11e envoi accepté');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US64 : au plus 10 récaps par heure et par manager', 'ok', true, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée de l''e-mail du récap', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us64_email_smoke_tests() FROM public, anon, authenticated;

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
  UNION ALL
  SELECT * FROM private.run_f4_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us43_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_f4_mois_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us68_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us71_smoke_tests()
  UNION ALL
  SELECT * FROM private.run_us64_email_smoke_tests()
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

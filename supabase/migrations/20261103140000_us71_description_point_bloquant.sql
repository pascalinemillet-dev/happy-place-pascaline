-- ============================================================
-- US71 : modifier la description d'un point bloquant avant de le publier
-- ============================================================
-- Demande de Pascaline du 2026-11-03. Arbitrage du même jour : la description
-- modifiée part dans le point bloquant publié (table blockers, visible de tous) ;
-- la soumission garde le texte de l'auteur, lisible dans « Mes soumissions ».
--
-- publish_blocker_submission prend un 5e paramètre, _description, facultatif :
-- NULL recopie la description de l'auteur, comme avant. Les appels à 4 paramètres
-- restent valides.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true

BEGIN;

DROP FUNCTION IF EXISTS public.publish_blocker_submission(uuid, text, text, public.blocker_severity);

CREATE OR REPLACE FUNCTION public.publish_blocker_submission(
  _submission_id uuid,
  _title text,
  _department text,
  _severity public.blocker_severity,
  _description text DEFAULT NULL
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _s public.submissions;
  _t text := btrim(coalesce(_title, ''));
  _d text := btrim(_description);
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
  -- US71 : la personne qui publie peut reformuler la description ; NULL garde le texte de l'auteur.
  IF _d IS NOT NULL AND (char_length(_d) < 5 OR char_length(_d) > 2000) THEN
    RAISE EXCEPTION 'La description doit faire de 5 à 2000 caractères.';
  END IF;
  SELECT t.name INTO _dep FROM public.teams t WHERE lower(t.name) = lower(btrim(coalesce(_department, '')));
  IF _dep IS NULL THEN
    RAISE EXCEPTION 'Pôle inconnu : choisis une équipe du référentiel.';
  END IF;

  INSERT INTO public.blockers (title, description, department, severity, status)
  VALUES (_t, coalesce(_d, _s.content), _dep, coalesce(_severity, _s.severity), 'OUVERT'::public.blocker_status)
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
REVOKE ALL ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.publish_blocker_submission(uuid, text, text, public.blocker_severity, text) TO authenticated;

COMMIT;

-- ============================================================
-- Tests de fumée de US71, branchés sur private.run_smoke_tests()
-- ============================================================
BEGIN;

CREATE OR REPLACE FUNCTION private.run_us71_smoke_tests()
 RETURNS TABLE(test text, ok boolean, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _res jsonb := '[]'::jsonb;
  _u uuid;
  _a uuid;
  _b uuid;
  _c uuid;
  _blocker uuid;
  _desc text;
  _team text := 'ZZ US71 fumée';
BEGIN
  BEGIN
    INSERT INTO teams(name) VALUES (_team) ON CONFLICT DO NOTHING;
    INSERT INTO allowed_users(email, team, first_name, last_name)
      VALUES ('us71.collab@fumee.happyplace.fr', _team, 'Gontran', 'Auteur') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'collaborateur');
    INSERT INTO allowed_users(email, first_name, last_name)
      VALUES ('us71.manager@fumee.happyplace.fr', 'Kesha', 'Manager') RETURNING id INTO _u;
    INSERT INTO allowed_user_roles(allowed_user_id, role) VALUES (_u, 'manager');
    INSERT INTO manager_teams(allowed_user_id, team) VALUES (_u, _team);

    PERFORM set_config('request.jwt.claims', '{"email":"us71.collab@fumee.happyplace.fr"}', true);
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Le chef de projet Dupont ne valide pas les CV.', 'point bloquant', 'warning')
      RETURNING id INTO _a;
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les accès au portail tombent chaque matin.', 'point bloquant', 'warning')
      RETURNING id INTO _b;
    INSERT INTO submissions(author_name, team, content, kind, severity)
      VALUES ('x', 'x', 'Les badges ne fonctionnent plus.', 'point bloquant', 'info')
      RETURNING id INTO _c;

    PERFORM set_config('request.jwt.claims', '{"email":"us71.manager@fumee.happyplace.fr"}', true);
    _blocker := public.publish_blocker_submission(_a, 'Validation des CV bloquée', _team, 'critical',
      '  Un chef de projet ne valide plus les CV depuis lundi.  ');
    SELECT description INTO _desc FROM blockers WHERE id = _blocker;
    _res := _res || jsonb_build_object('t', 'US71 : la description modifiée part dans le point publié',
      'ok', _desc = 'Un chef de projet ne valide plus les CV depuis lundi.', 'd', coalesce(_desc, 'aucune'));
    _res := _res || jsonb_build_object('t', 'US71 : la soumission garde le texte de l''auteur',
      'ok', (SELECT content FROM submissions WHERE id = _a) = 'Le chef de projet Dupont ne valide pas les CV.',
      'd', 'texte d''origine conservé');

    _blocker := public.publish_blocker_submission(_b, 'Accès au portail instables', _team, 'warning');
    SELECT description INTO _desc FROM blockers WHERE id = _blocker;
    _res := _res || jsonb_build_object('t', 'US71 : sans description modifiée, le texte de l''auteur est publié',
      'ok', _desc = 'Les accès au portail tombent chaque matin.', 'd', coalesce(_desc, 'aucune'));

    BEGIN
      PERFORM public.publish_blocker_submission(_c, 'Badges en panne', _team, 'info', '  ab ');
      _res := _res || jsonb_build_object('t', 'US71 : une description de moins de 5 caractères est refusée', 'ok', false, 'd', 'acceptée à tort');
    EXCEPTION WHEN raise_exception THEN
      _res := _res || jsonb_build_object('t', 'US71 : une description de moins de 5 caractères est refusée', 'ok', true, 'd', SQLERRM);
    END;

    RAISE EXCEPTION 'HP_SMOKE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'HP_SMOKE_ROLLBACK' THEN
      _res := _res || jsonb_build_object('t', 'Exécution du test de fumée US71', 'ok', false, 'd', 'Erreur inattendue : ' || SQLERRM);
    END IF;
  END;

  RETURN QUERY SELECT x->>'t', (x->>'ok')::boolean, x->>'d' FROM jsonb_array_elements(_res) x;
END
$function$;
REVOKE ALL ON FUNCTION private.run_us71_smoke_tests() FROM public, anon, authenticated;

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
$function$;
REVOKE ALL ON FUNCTION private.run_smoke_tests() FROM public, anon, authenticated;

COMMIT;

SELECT * FROM private.run_smoke_tests();

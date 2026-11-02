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

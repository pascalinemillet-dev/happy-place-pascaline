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

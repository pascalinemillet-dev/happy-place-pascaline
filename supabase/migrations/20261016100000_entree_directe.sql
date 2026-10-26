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

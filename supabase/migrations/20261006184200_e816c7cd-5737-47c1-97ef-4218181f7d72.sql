ALTER TABLE public.allowed_users
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name text;

ALTER TABLE public.allowed_users
  ADD CONSTRAINT allowed_users_first_name_len CHECK (first_name IS NULL OR char_length(btrim(first_name)) BETWEEN 1 AND 100),
  ADD CONSTRAINT allowed_users_last_name_len CHECK (last_name IS NULL OR char_length(btrim(last_name)) BETWEEN 1 AND 100);

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  _r jsonb;
  _i int := 0;
  _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role;
  _reason text;
  _id uuid;
  _out jsonb := '[]'::jsonb;
  _dup_emails text[];
  _dup_teams text[];
  _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN
    RAISE EXCEPTION 'Le fichier ne contient aucune ligne.';
  END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;

  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  SELECT coalesce(array_agg(t), '{}') INTO _dup_teams FROM (
    SELECT lower(btrim(x->>'team')) t FROM jsonb_array_elements(_rows) x
    WHERE lower(btrim(x->>'role')) = 'manager' AND coalesce(btrim(x->>'team'), '') <> ''
    GROUP BY 1 HAVING count(*) > 1) d;

  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    _reason := NULL;

    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND (char_length(_team) < 2 OR char_length(_team) > 60) THEN _reason := 'Nom d''équipe invalide (2 à 60 caractères)';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
    ELSIF _role_txt = 'manager' AND _team IS NOT NULL AND lower(_team) = ANY(_dup_teams) THEN _reason := 'Équipe attribuée à plusieurs managers dans le fichier';
    ELSIF _role_txt = 'manager' AND _team IS NOT NULL AND EXISTS (SELECT 1 FROM public.manager_teams WHERE lower(btrim(team)) = lower(_team)) THEN _reason := 'Cette équipe a déjà un manager';
    END IF;

    IF _reason IS NULL THEN
      _role := _role_txt::public.app_role;
      BEGIN
        INSERT INTO public.allowed_users (email, team, first_name, last_name)
        VALUES (_email, CASE WHEN _role = 'collaborateur' THEN _team END, _first, _last)
        RETURNING id INTO _id;
        INSERT INTO public.allowed_user_roles (allowed_user_id, role) VALUES (_id, _role);
        IF _role = 'manager' AND _team IS NOT NULL THEN
          INSERT INTO public.manager_teams (allowed_user_id, team) VALUES (_id, _team);
        END IF;
        IF _dry_run THEN
          RAISE EXCEPTION 'HP_DRY_RUN_OK';
        END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail ou équipe déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN OTHERS THEN
          IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
      END;
    END IF;

    IF _reason IS NULL THEN _ok := _ok + 1; ELSE _ko := _ko + 1; END IF;
    _out := _out || jsonb_build_object(
      'line', _line, 'email', _email, 'last_name', _last, 'first_name', _first,
      'role', _role_txt, 'team', _team,
      'status', CASE WHEN _reason IS NOT NULL THEN 'refusée' WHEN _dry_run THEN 'valide' ELSE 'importée' END,
      'reason', _reason);
  END LOOP;

  RETURN jsonb_build_object('dry_run', _dry_run, 'accepted', _ok, 'rejected', _ko, 'rows', _out);
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
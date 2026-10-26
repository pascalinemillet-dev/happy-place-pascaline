-- Référentiel des équipes (US26)
CREATE TABLE IF NOT EXISTS public.teams (
  name text PRIMARY KEY,
  is_reserved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT teams_name_length CHECK (char_length(btrim(name)) BETWEEN 2 AND 60 AND name = btrim(name))
);
CREATE UNIQUE INDEX IF NOT EXISTS teams_name_unique_ci ON public.teams (lower(name));

CREATE OR REPLACE FUNCTION private.protect_reserved_team()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public', 'private' AS $$
BEGIN
  IF OLD.is_reserved THEN
    RAISE EXCEPTION 'L''équipe % est réservée : elle ne peut être ni renommée ni supprimée.', OLD.name;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.is_reserved := OLD.is_reserved;
    RETURN NEW;
  END IF;
  RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS protect_reserved_team ON public.teams;
CREATE TRIGGER protect_reserved_team BEFORE UPDATE OR DELETE ON public.teams
  FOR EACH ROW EXECUTE FUNCTION private.protect_reserved_team();

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allowed read teams" ON public.teams;
CREATE POLICY "Allowed read teams" ON public.teams FOR SELECT TO authenticated USING (private.is_allowed());
DROP POLICY IF EXISTS "Admins insert teams" ON public.teams;
CREATE POLICY "Admins insert teams" ON public.teams FOR INSERT TO authenticated WITH CHECK (private.is_admin() AND NOT is_reserved);
DROP POLICY IF EXISTS "Admins update teams" ON public.teams;
CREATE POLICY "Admins update teams" ON public.teams FOR UPDATE TO authenticated USING (private.is_admin()) WITH CHECK (private.is_admin());
DROP POLICY IF EXISTS "Admins delete teams" ON public.teams;
CREATE POLICY "Admins delete teams" ON public.teams FOR DELETE TO authenticated USING (private.is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teams TO authenticated;

INSERT INTO public.teams (name, is_reserved) VALUES ('Admin', true) ON CONFLICT DO NOTHING;
INSERT INTO public.teams (name) VALUES
  ('Accounting'), ('Finance'), ('Legal'), ('Marketing'), ('People'), ('Product'),
  ('Direction Commerciale'), ('Opérations'), ('Relation clients'),
  ('Direction Conseil'), ('Pôle Data et IA'), ('Direction recrutement')
ON CONFLICT DO NOTHING;

UPDATE public.allowed_users SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';
DELETE FROM public.manager_teams a USING public.manager_teams b
  WHERE lower(btrim(a.team)) = 'sales' AND lower(btrim(b.team)) = 'direction commerciale' AND a.allowed_user_id = b.allowed_user_id;
UPDATE public.manager_teams SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';
UPDATE public.submissions SET team = 'Direction Commerciale' WHERE lower(btrim(team)) = 'sales';

UPDATE public.allowed_users u SET team = t.name FROM public.teams t WHERE lower(btrim(u.team)) = lower(t.name) AND u.team <> t.name;
UPDATE public.manager_teams m SET team = t.name FROM public.teams t WHERE lower(btrim(m.team)) = lower(t.name) AND m.team <> t.name;
UPDATE public.submissions s SET team = t.name FROM public.teams t WHERE lower(btrim(s.team)) = lower(t.name) AND s.team <> t.name;

INSERT INTO public.teams (name)
SELECT DISTINCT btrim(x.team) FROM (
  SELECT team FROM public.allowed_users UNION SELECT team FROM public.manager_teams UNION SELECT team FROM public.submissions
) x WHERE x.team IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.teams t WHERE lower(t.name) = lower(btrim(x.team)))
ON CONFLICT DO NOTHING;

ALTER TABLE public.allowed_users DROP CONSTRAINT IF EXISTS allowed_users_team_fkey;
ALTER TABLE public.allowed_users ADD CONSTRAINT allowed_users_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.manager_teams DROP CONSTRAINT IF EXISTS manager_teams_team_fkey;
ALTER TABLE public.manager_teams ADD CONSTRAINT manager_teams_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.submissions DROP CONSTRAINT IF EXISTS submissions_team_fkey;
ALTER TABLE public.submissions ADD CONSTRAINT submissions_team_fkey
  FOREIGN KEY (team) REFERENCES public.teams(name) ON UPDATE CASCADE ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.bulk_import_allowed_users(_rows jsonb, _dry_run boolean DEFAULT true)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'private'
AS $function$
DECLARE
  _r jsonb; _i int := 0; _line int;
  _email text; _first text; _last text; _role_txt text; _team text;
  _role public.app_role; _reason text; _id uuid;
  _out jsonb := '[]'::jsonb; _dup_emails text[]; _ok int := 0; _ko int := 0;
BEGIN
  IF NOT private.is_admin() THEN
    RAISE EXCEPTION 'Seul un admin peut importer des utilisateurs.' USING ERRCODE = '42501';
  END IF;
  IF _rows IS NULL OR jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'Format invalide : une liste de lignes est attendue.';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN RAISE EXCEPTION 'Le fichier ne contient aucune ligne.'; END IF;
  IF jsonb_array_length(_rows) > 500 THEN
    RAISE EXCEPTION 'Maximum 500 lignes par import (% reçues).', jsonb_array_length(_rows);
  END IF;
  SELECT coalesce(array_agg(e), '{}') INTO _dup_emails FROM (
    SELECT lower(btrim(x->>'email')) e FROM jsonb_array_elements(_rows) x
    WHERE coalesce(btrim(x->>'email'), '') <> '' GROUP BY 1 HAVING count(*) > 1) d;
  FOR _r IN SELECT value FROM jsonb_array_elements(_rows) LOOP
    _i := _i + 1;
    _line := coalesce((_r->>'line')::int, _i + 1);
    _email := lower(btrim(coalesce(_r->>'email', '')));
    _first := nullif(btrim(coalesce(_r->>'first_name', '')), '');
    _last := nullif(btrim(coalesce(_r->>'last_name', '')), '');
    _role_txt := lower(btrim(coalesce(_r->>'role', '')));
    _team := nullif(btrim(coalesce(_r->>'team', '')), '');
    IF _team IS NOT NULL THEN
      _team := coalesce((SELECT t.name FROM public.teams t WHERE lower(t.name) = lower(_team)), _team);
    END IF;
    _reason := NULL;
    IF _last IS NULL THEN _reason := 'Nom manquant';
    ELSIF _first IS NULL THEN _reason := 'Prénom manquant';
    ELSIF char_length(_last) > 100 OR char_length(_first) > 100 THEN _reason := 'Nom ou prénom trop long (100 caractères maximum)';
    ELSIF _email = '' THEN _reason := 'Adresse mail manquante';
    ELSIF char_length(_email) > 255 OR _email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN _reason := 'Adresse mail invalide';
    ELSIF _email = ANY(_dup_emails) THEN _reason := 'Adresse mail en double dans le fichier : une adresse ne peut avoir qu''un seul rôle';
    ELSIF EXISTS (SELECT 1 FROM public.allowed_users WHERE email = _email) THEN _reason := 'Adresse mail déjà autorisée';
    ELSIF _role_txt NOT IN ('admin', 'manager', 'collaborateur') THEN _reason := 'Rôle invalide (collaborateur, manager ou admin)';
    ELSIF _team IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.teams t WHERE t.name = _team) THEN _reason := 'Équipe inconnue : choisis une équipe de la liste';
    ELSIF _role_txt = 'collaborateur' AND _team IS NULL THEN _reason := 'Équipe obligatoire pour un collaborateur';
    ELSIF _role_txt IN ('collaborateur', 'manager') AND lower(_team) = 'admin' THEN _reason := 'L''équipe Admin est réservée aux admins';
    ELSIF _role_txt = 'admin' AND _team IS NOT NULL AND lower(_team) <> 'admin' THEN _reason := 'Un admin appartient à l''équipe Admin : laisser vide ou choisir Admin';
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
        IF _dry_run THEN RAISE EXCEPTION 'HP_DRY_RUN_OK'; END IF;
      EXCEPTION
        WHEN unique_violation THEN _reason := 'Adresse mail déjà utilisée';
        WHEN check_violation THEN _reason := 'Valeur refusée par la base (' || SQLERRM || ')';
        WHEN foreign_key_violation THEN _reason := 'Équipe inconnue : choisis une équipe de la liste';
        WHEN OTHERS THEN IF SQLERRM <> 'HP_DRY_RUN_OK' THEN _reason := SQLERRM; END IF;
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
$function$;
REVOKE ALL ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_import_allowed_users(jsonb, boolean) TO authenticated;
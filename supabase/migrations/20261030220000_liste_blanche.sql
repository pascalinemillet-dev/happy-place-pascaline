-- ============================================================
-- Lot 0 (T9) : retour de la liste blanche
-- ============================================================
-- Seules les adresses inscrites dans allowed_users peuvent créer un compte
-- (email et mot de passe). Le rôle vient de allowed_user_roles, attribué par un admin :
-- personne ne choisit plus son propre rôle. Les règles RLS ne changent pas.
-- À faire aussi dans Supabase : couper « Allow anonymous sign-ins » et « Confirm email ».

BEGIN;

-- 1. Plus de choix de rôle libre : la fonction de la version élèves n'est plus appelable.
REVOKE EXECUTE ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) FROM public, anon, authenticated;
COMMENT ON FUNCTION public.choisir_mon_role(public.app_role, text, text, text) IS
  'Version élèves, désactivée au lot 0 (liste blanche) : plus aucun rôle ne peut l''appeler.';

-- 2. Les équipes redeviennent lisibles par les seuls invités (règle « Allowed read teams » d'origine).
DROP POLICY IF EXISTS "Authenticated read teams" ON public.teams;

-- 3. La base refuse la création d'un compte dont l'adresse n'est pas invitée
--    (comptes anonymes compris, qui n'ont pas d'adresse).
CREATE OR REPLACE FUNCTION private.refuser_compte_non_invite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  IF NEW.email IS NULL OR NEW.email = ''
     OR NOT EXISTS (SELECT 1 FROM public.allowed_users WHERE email = lower(NEW.email)) THEN
    RAISE EXCEPTION 'Adresse non invitée : demande à un admin de t''ajouter à Happy Place.'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

GRANT USAGE ON SCHEMA private TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION private.refuser_compte_non_invite() TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION private.refuser_compte_non_invite() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS refuser_compte_non_invite ON auth.users;
CREATE TRIGGER refuser_compte_non_invite
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.refuser_compte_non_invite();

COMMIT;

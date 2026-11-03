-- ============================================================
-- US66 (2026-11-03) : une actualité est signée par le nom de son auteur
-- ============================================================
-- Demande de Pascaline du 2026-11-03 : les actualités créées depuis le
-- dashboard affichaient « Par pascalinemillet@gmail.com » quand le compte
-- n'avait pas de nom dans ses métadonnées de connexion. L'app prend désormais
-- le prénom et le nom de `allowed_users`.
--
-- Cette migration corrige les actualités déjà enregistrées : quand l'auteur
-- affiché est l'adresse e-mail de l'auteur, il est remplacé par son prénom et
-- son nom de `allowed_users`, s'ils sont renseignés. Un auteur choisi par
-- l'admin dans « Gérer les données » (ex. « Direction Recrutement ») n'est
-- pas touché. Relancer la migration ne change rien.
--
-- Après cette migration :
--   select * from private.run_smoke_tests();   -- toutes les lignes ok = true
-- ============================================================

BEGIN;

UPDATE public.news n
   SET author = btrim(concat_ws(' ', btrim(a.first_name), btrim(a.last_name)))
  FROM public.allowed_users a
 WHERE lower(a.email) = lower(n.author_email)
   AND lower(btrim(n.author)) = lower(n.author_email)
   AND btrim(concat_ws(' ', btrim(a.first_name), btrim(a.last_name))) <> '';

COMMIT;

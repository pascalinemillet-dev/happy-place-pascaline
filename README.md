# Happy Place (reprise de Pascaline)

Happy Place est le dashboard interne de **Bigger Boat**, un cabinet de recrutement fictif. Il réunit les actualités, les idées et demandes des équipes, les points bloquants et les indicateurs.

Ce dépôt part de la version élèves de l'app. Depuis le lot 0 (2026-10-30), **la connexion est réservée à une liste blanche** : seules les adresses inscrites par un admin peuvent créer leur mot de passe et entrer, avec le rôle (collaborateur, manager ou admin) que l'admin leur a donné.

Chaque groupe installe **sa propre base Supabase**, sans toucher à celle des autres groupes. Tout le groupe partage la même app et les mêmes données.

---

## Ce qu'il te faut

- Un compte [GitHub](https://github.com) et un compte [Supabase](https://supabase.com) (plans gratuits ; tu peux te connecter à Supabase avec ton compte GitHub).
- Rien à installer : l'app se lance dans ton navigateur avec **GitHub Codespaces**. Si tu préfères travailler sur ton ordinateur, il te faut [Node.js](https://nodejs.org) version 20 ou plus.

Compte environ 20 minutes. **Une seule personne par groupe** fait l'installation.

---

## 0. Créer le dépôt du groupe

1. En haut de cette page GitHub, clique sur le bouton vert **Use this template** → **Create a new repository**.
2. Donne-lui un nom (par exemple `happy-place-groupe-3`), puis **Create repository**.

Tu travailles désormais dans **ce nouveau dépôt** : c'est la copie de ton groupe.

## 1. Créer le projet Supabase

1. Sur [supabase.com/dashboard](https://supabase.com/dashboard), clique sur **New project**.
2. Donne-lui un nom (par exemple `happy-place-groupe-3`), clique sur **Generate a password** et choisis une région en Europe.
3. Clique sur **Create new project** et attends 1 à 2 minutes.

## 2. Régler la connexion

La connexion se fait par email et mot de passe, réservée aux adresses invitées.

1. **Authentication** → **Sign In / Providers** → vérifie que **Allow anonymous sign-ins** est **désactivé** → **Save**.
2. Même écran, rubrique **Email** : désactive **Confirm email** → **Save**. Supabase n'a ainsi aucun email à envoyer (son expéditeur par défaut ne sert qu'aux tests).
3. Après l'étape 3, inscris au moins une adresse admin dans `allowed_users` (avec son rôle dans `allowed_user_roles`) : sans invité, personne ne peut entrer.

## 3. Installer la base de données

1. Dans ton dépôt GitHub, ouvre le dossier **supabase**, puis le fichier **setup.sql**. Clique sur l'icône **Copy raw file** (deux carrés superposés, au-dessus du code à droite).
2. Dans Supabase : **SQL Editor** → **+ New query**. Colle, puis clique sur **Run**.
3. Si Supabase te demande comment gérer la sécurité des tables (RLS), choisis **Run without RLS** : le script active lui-même les règles de sécurité sur toutes les tables. Si un avertissement parle de « destructive operations », clique sur **Run this query**.
4. Un tableau de 90 lignes apparaît : **toutes les lignes doivent indiquer `ok = true`**.
5. Fais de même avec **seed.sql** (les données de démo), dans une **nouvelle** requête. Résultat attendu : « Success. No rows returned ».

> Tu peux relancer `seed.sql` à tout moment pour remettre les contenus de démo dans leur état de départ. Les profils créés sont conservés.

## 4. Récupérer tes deux clés

Dans Supabase, clique sur **Connect** (en haut de la page) et note :
- l'**URL du projet** : `https://xxxx.supabase.co`
- la **Publishable key** : `sb_publishable_…`

*Sinon : **Project Settings** → **API Keys** pour la clé, **Data API** pour l'URL.*

> La clé « publishable » est faite pour être utilisée dans le navigateur. N'utilise **jamais** la clé `secret` ou `service_role`.

## 5. Lancer l'app dans un Codespace

1. Dans ton dépôt GitHub : bouton vert **Code** → onglet **Codespaces** → **Create codespace on main**. Un éditeur s'ouvre dans ton navigateur (environ une minute).
2. Dans le **Terminal** en bas de l'écran, tape `cp .env.example .env` puis Entrée. Le fichier `.env` apparaît à gauche : ouvre-le, remplace les deux valeurs par tes clés de l'étape 4, puis **Ctrl + S**.
3. Dans le terminal, tape `npm install` (attends la fin), puis `npm run dev`.
4. Clique sur **Open in Browser** dans la fenêtre qui apparaît (ou onglet **Ports** → ligne **3000** → icône du globe).

L'app s'ouvre sur l'écran **Connexion**. Une adresse invitée crée son mot de passe avec « Première connexion ? Créer mon mot de passe ».

Pour partager l'app avec ton groupe : onglet **Ports** → clic droit sur la ligne **3000** → **Port Visibility** → **Public**, puis copie l'adresse et envoie-la.

> Un Codespace s'arrête tout seul après 30 minutes d'inactivité. Pour le relancer : **Code** → **Codespaces** → clique sur son nom, puis relance `npm run dev`. Le compte gratuit GitHub inclut un quota mensuel d'heures de Codespaces.

**Sur ton ordinateur plutôt ?** Télécharge le dépôt, crée le fichier `.env` de la même façon, puis lance `npm install` et `npm run dev` dans un terminal, et ouvre [http://localhost:3000](http://localhost:3000).

---

## Les trois rôles

| Rôle | Ce qu'il peut faire |
|---|---|
| **Collaborateur** | Lit les actualités et les indicateurs, soumet une idée ou un point bloquant pour son équipe, suit ses soumissions, modifie et renvoie ou archive une soumission refusée. |
| **Manager** | Valide ou refuse les soumissions des équipes qu'il manage, publie un point bloquant de son équipe, prépare son point d'équipe (récap par l'IA), rédige et publie des actualités. Sa propre soumission est validée par un autre manager ou par l'admin. |
| **Admin** | Gère tout : contenus, indicateurs, équipes et utilisateurs (espace « Gérer les données »). |

Ces droits sont appliqués **par la base elle-même** (règles RLS de Supabase), pas seulement par l'interface.

La base contient aussi dix membres fictifs de Bigger Boat (`@biggerboat.example`). Ils n'ont pas de compte : ils peuplent l'écran des utilisateurs et managent certaines équipes.

**Première connexion** : une personne invitée clique sur « Première connexion ? Créer mon mot de passe ». Une adresse non invitée est refusée par la base elle-même.

---

## Pour aller plus loin

- **Commandes utiles** : `npm run build` (version de production), `npm run start` (lance cette version), `npm run typecheck` (vérifie les types).
- **Structure** : les écrans sont dans `src/routes`, les composants dans `src/components`, et la base dans `supabase/migrations` (une migration par évolution, dans l'ordre).
- **Modifier la base** : écris une nouvelle migration SQL plutôt que de modifier les anciennes. Après toute modification d'ENUM, de trigger ou de statut, lance `select * from private.run_smoke_tests();` : toutes les lignes doivent revenir à `ok = true`.
- **Règles du projet** : le fichier `AGENTS.md` liste les conventions à respecter. Donne-le à ton assistant IA de code.
- **Tâches automatiques** : trois tâches tournent chaque nuit dans Supabase (revalidation annuelle des contenus, départs programmés des collaborateurs, purge des e-mails de plus de 30 jours dans `notifications`). Tu les retrouves dans le module **Cron** de Supabase.
- **Mise en ligne** : l'app est déployée sur Cloudflare Workers, branché sur ce dépôt GitHub (Workers Builds) : chaque envoi sur `main` redéploie l'app. Le build Nitro détecte Cloudflare tout seul (preset `cloudflare_module`) et complète `wrangler.jsonc`. Dans Cloudflare, `VITE_SUPABASE_URL` et `VITE_SUPABASE_PUBLISHABLE_KEY` se saisissent en **variables de build**, car Vite les intègre au moment du build.

## F1 « Signaler un point bloquant » (lot 1)

- **Base déjà installée** : dans Supabase, **SQL Editor** → **+ New query**, colle le contenu de `supabase/migrations/20261031090000_f1_point_bloquant.sql`, puis **Run**, et de même pour chaque migration plus récente, dans l'ordre des noms. Lance ensuite `select * from private.run_smoke_tests();` : toutes les lignes doivent être à `ok = true` (90 au 2026-11-03). Sur un projet neuf, `setup.sql` contient déjà toutes les migrations.
- **IA (titre US31 et récap US64)** : le Worker Cloudflare lit les données sous l'identité de l'utilisateur, puis appelle le scénario Make « HappyPlace - IA », qui appelle OpenAI. Dans Cloudflare (Workers → `happy-place-pascaline` → Settings → Variables and Secrets), ajoute en **Secret** `MAKE_AI_WEBHOOK_URL` (adresse du webhook Make) et `MAKE_AI_SECRET` (chaîne que le scénario vérifie dans l'en-tête `x-happyplace-secret`). Sans ces secrets, l'app marche sans IA : titre saisi à la main, récap en tableau.
- **Scénario Make attendu** : webhook personnalisé → filtre sur l'en-tête `x-happyplace-secret` → OpenAI « Generate a response » (Instructions = `consigne`, Prompt = `texte`, modèle `gpt-4o-mini`, Temperature 0.2, **Store : No**, **Create a new conversation : No**, réponse en texte) → **Webhook response** (statut 200, corps = résultat du module OpenAI). Store sur No : OpenAI ne conserve pas la réponse. L'app retrouve elle-même le JSON du récap dans la réponse ; si Make répond « Accepted » (scénario arrêté ou filtre bloquant), l'app passe en version sans IA.

## Lot 2 : e-mails, indicateurs et suivi des soumissions

- **E-mails (US60, US61, US62, US65, récap US64)** : la base prépare chaque e-mail par trigger dans la table `public.notifications` (événement, destinataires, copie, objet, corps HTML). La table est fermée à l'app. Un **webhook de base Supabase** (Integrations → Database Webhooks, table `notifications`, événement Insert, POST) envoie chaque ligne au scénario Make **R7**, qui l'expédie par Gmail. Le filtre de R7 laisse passer les événements `point_bloquant_soumis`, `point_bloquant_refuse`, `point_bloquant_publie`, `idee_soumise` et `recap_point_equipe`. Make ne reçoit aucune clé Supabase. Les adresses `.example`, `.invalid`, `.test` et `.localhost` sont écartées ; les lignes de plus de 30 jours sont purgées chaque nuit.
- **Indicateurs (F4, US43)** : une valeur par indicateur et par mois terminé (`metrics_mensuels`), un seul mois affiché pour tous, choisi par l'admin (`indicateurs_reglages`) ; vue `indicateurs_du_mois` (écart avec le mois précédent, sens favorable propre à chaque indicateur) ; ordre d'affichage de 1 à 10, sans doublon.
- **Écritures par fonctions seulement** : `publish_blocker_submission` (5 paramètres, description reformulée facultative), `resubmit_submission` et `archive_submission` (soumission refusée, auteur seul), `send_team_recap_email` (manager seul, vers sa propre adresse, 10 envois par heure au plus).
- **Ordre de mise en ligne** : lancer la migration sur la base en ligne, vérifier le test de fumée, puis envoyer le commit. Dans l'autre ordre, l'app appelle une colonne ou une fonction absente.

## En cas de problème

| Symptôme | Cause probable |
|---|---|
| « Missing Supabase environment variable(s) » | Le fichier `.env` est absent ou mal nommé. Relance `npm run dev` après l'avoir corrigé. |
| « Cette adresse n'est pas sur la liste des invités » | L'adresse n'est pas dans `allowed_users`, ou elle n'a pas de rôle. Un admin doit l'ajouter. |
| « Ce compte attend une confirmation par email » | **Confirm email** est encore activé (étape 2). |
| « Blocked request. This host is not allowed » | Le fichier `vite.config.ts` a été modifié : il doit contenir `allowedHosts: [".app.github.dev"]`. |
| « Impossible de charger les équipes » | `setup.sql` n'a pas été exécuté en entier. Relance-le sur un projet neuf. |
| Le dashboard est vide | `seed.sql` n'a pas été exécuté. |
| Un test de `setup.sql` est à `false` | Le script a été lancé deux fois, ou en partie. Le plus simple est de repartir d'un projet Supabase neuf. |

---

### Différences avec l'app d'origine

- **Connexion** : email et mot de passe réservés à la liste blanche (migration `20261030220000_liste_blanche.sql`), à la place de la connexion Google de l'app d'origine. L'entrée libre de la version élèves (`/choisir-role`, fonction `choisir_mon_role`) est désactivée.
- **Configuration standard** à la place des outils propres à Lovable (`vite.config.ts`, client Supabase), compatible GitHub Codespaces.
- **Base installable de zéro** : migrations regroupées dans `supabase/migrations`, espaces de stockage ajoutés, et une ancienne migration inutilisée retirée.

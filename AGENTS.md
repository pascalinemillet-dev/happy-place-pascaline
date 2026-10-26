- Store application roles in `allowed_user_roles`, separate from the email whitelist, to prevent privilege escalation.
- Scope manager review permissions through `manager_teams`, because one manager may oversee multiple teams.
- Render company identity through the shared `BrandHeader` so every user-facing page stays consistently branded.
- Generate personal submission reports in the browser from RLS-scoped queries so exports never exceed the signed-in user's access.
- After any migration that touches an ENUM, a trigger, or a status-related function, run `select * from private.run_smoke_tests();` — every row must come back with ok = true.

- Load heavy browser-only libraries (ExcelJS, JSZip) from `public/vendor` via `loadBrowserLib`, never `import()` them: bundling their Node dependencies into the server crashes the published site on every page.
- News images live in the private `news-media` bucket at `{news_id}/{uuid}.{ext}`; storage write rights mirror news edit rights via `private.can_edit_news_media`, and the app removes old files itself (before deleting the row) because storage objects cannot be deleted from SQL.
- Keep metric delta and value formatting in shared dashboard helpers so management rows and dashboard trends interpret numeric text consistently.

- Version élèves : la connexion est libre et chaque compte choisit son rôle via `public.choisir_mon_role` (écran `/choisir-role`). Ne pas réintroduire de liste blanche : les règles RLS par rôle restent la référence.

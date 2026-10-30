import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { z } from "zod";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/brand-header";
import { Button } from "@/components/ui/button";

// Connexion réservée à la liste blanche (lot 0, T9) : email et mot de passe.
// Seule une adresse inscrite par un admin dans allowed_users peut créer son compte :
// la base refuse les autres (trigger private.refuser_compte_non_invite sur auth.users).
// Un compte connecté sans rôle est déconnecté par /_authenticated et renvoyé ici (?refuse=1).

type AuthSearch = { refuse?: 1 };

export const Route = createFileRoute("/auth")({
  ssr: false,
  validateSearch: (search: Record<string, unknown>): AuthSearch =>
    search.refuse === 1 || search.refuse === "1" ? { refuse: 1 } : {},
  head: () => ({
    meta: [
      { title: "Connexion — Happy Place" },
      {
        name: "description",
        content: "Connexion à Happy Place, le dashboard interne de Bigger Boat.",
      },
    ],
  }),
  component: AuthPage,
});

type Mode = "signin" | "signup";

const NON_INVITE =
  "Cette adresse n'est pas sur la liste des invités de Happy Place. Demande à un admin de t'ajouter, puis réessaie.";

function AuthPage() {
  const navigate = useNavigate();
  const { refuse } = Route.useSearch();
  const [error, setError] = useState<string | null>(refuse ? NON_INVITE : null);
  const [info, setInfo] = useState<string | null>(null);
  const [mode, setMode] = useState<Mode>("signin");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) navigate({ to: "/" });
    });
  }, [navigate]);

  function switchMode(m: Mode) {
    setMode(m);
    setError(null);
    setInfo(null);
    setPassword("");
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setInfo(null);
    const cleanEmail = email.trim().toLowerCase();
    if (!z.string().email().safeParse(cleanEmail).success) {
      setError("Saisis une adresse email valide.");
      return;
    }
    if (password.length < 8) {
      setError("Le mot de passe doit contenir au moins 8 caractères.");
      return;
    }
    setBusy(true);
    try {
      if (mode === "signin") {
        const { error: err } = await supabase.auth.signInWithPassword({
          email: cleanEmail,
          password,
        });
        if (err) {
          setError(
            /not confirmed/i.test(err.message)
              ? "Ce compte attend une confirmation par email. Un admin doit désactiver « Confirm email » dans Supabase."
              : "Email ou mot de passe incorrect.",
          );
          return;
        }
        navigate({ to: "/" });
      } else {
        const { data, error: err } = await supabase.auth.signUp({ email: cleanEmail, password });
        if (err) {
          setError(
            /already registered|already exists/i.test(err.message)
              ? "Un compte existe déjà avec cette adresse : connecte-toi."
              : /database error|non invit/i.test(err.message)
                ? NON_INVITE
                : `Création du compte impossible : ${err.message}`,
          );
          return;
        }
        if (data.session) {
          navigate({ to: "/" });
        } else {
          setInfo("Mot de passe créé. Connecte-toi avec ton email et ce mot de passe.");
          setMode("signin");
        }
      }
    } finally {
      setBusy(false);
    }
  }

  const inputCls =
    "mt-xs h-11 w-full border border-outline-variant bg-background px-sm font-body-md text-body-md text-on-surface focus:outline-none focus:ring-2 focus:ring-primary";
  const labelCls = "block font-label-sm text-label-sm uppercase text-on-surface-variant";
  const linkCls = "font-body-sm text-body-sm text-primary underline-offset-2 hover:underline";

  return (
    <div className="min-h-dvh w-full bg-background flex flex-col">
      <BrandHeader />
      <main className="flex flex-1 items-center justify-center px-md py-lg">
        <section className="w-[min(100%,28rem)] border border-outline-variant bg-surface-container-lowest p-lg shadow-sm">
          <div className="space-y-xs">
            <p className="font-label-sm text-label-sm uppercase text-on-surface-variant">
              {mode === "signin" ? "Connexion" : "Première connexion"}
            </p>
            <h1 className="font-headline-lg text-headline-lg text-primary">Happy Place</h1>
            <p className="w-full font-body-md text-body-md text-on-surface-variant">
              {mode === "signin"
                ? "Connecte-toi avec ton email professionnel et ton mot de passe."
                : "Ton adresse a été invitée par un admin : choisis ton mot de passe (8 caractères minimum)."}
            </p>
          </div>

          {error && (
            <p
              className="mt-md border border-error bg-error-container p-sm font-body-sm text-on-error-container"
              role="alert"
            >
              {error}
            </p>
          )}
          {info && (
            <p
              className="mt-md border border-outline-variant bg-surface-container p-sm font-body-sm text-on-surface"
              role="status"
            >
              {info}
            </p>
          )}

          <form onSubmit={submit} className="mt-md space-y-sm" noValidate>
            <label className={labelCls}>
              Email
              <input
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className={inputCls}
              />
            </label>
            <label className={labelCls}>
              Mot de passe
              <input
                type="password"
                autoComplete={mode === "signup" ? "new-password" : "current-password"}
                required
                minLength={8}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className={inputCls}
              />
            </label>
            <Button
              type="submit"
              disabled={busy}
              className="h-12 w-full rounded-none font-label-md text-xs uppercase text-on-primary"
            >
              {busy ? "PATIENTE…" : mode === "signin" ? "SE CONNECTER" : "CRÉER MON MOT DE PASSE"}
            </Button>
          </form>

          <div className="mt-sm flex flex-col items-start gap-xs">
            {mode === "signin" ? (
              <button type="button" className={linkCls} onClick={() => switchMode("signup")}>
                Première connexion ? Créer mon mot de passe
              </button>
            ) : (
              <button type="button" className={linkCls} onClick={() => switchMode("signin")}>
                ← J'ai déjà un mot de passe
              </button>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}

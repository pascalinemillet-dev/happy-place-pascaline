import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { BrandHeader } from "@/components/brand-header";
import { Button } from "@/components/ui/button";

// Version élèves : entrée directe, sans email ni mot de passe.
// Une session anonyme Supabase est ouverte automatiquement, puis l'écran
// /choisir-role permet de choisir son rôle. Le navigateur garde la session :
// on retrouve son rôle à la visite suivante.

export const Route = createFileRoute("/auth")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Happy Place" },
      { name: "description", content: "Happy Place, le dashboard interne de Bigger Boat." },
    ],
  }),
  component: EntreePage,
});

function EntreePage() {
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setError(null);
      const { data } = await supabase.auth.getSession();
      if (data.session) {
        navigate({ to: "/" });
        return;
      }
      const { error: err } = await supabase.auth.signInAnonymously();
      if (cancelled) return;
      if (err) {
        setError(
          /anonymous/i.test(err.message) && /disabled|not enabled/i.test(err.message)
            ? "Les connexions anonymes ne sont pas activées dans Supabase. Active « Allow anonymous sign-ins » (voir le README, étape 2), puis réessaie."
            : `Impossible d'ouvrir Happy Place : ${err.message}`,
        );
        return;
      }
      navigate({ to: "/choisir-role" });
    })();
    return () => {
      cancelled = true;
    };
  }, [navigate, attempt]);

  return (
    <div className="min-h-dvh w-full bg-background flex flex-col">
      <BrandHeader />
      <main className="flex flex-1 items-center justify-center px-md py-lg">
        <section className="w-[min(100%,28rem)] border border-outline-variant bg-surface-container-lowest p-lg shadow-sm">
          <h1 className="font-headline-lg text-headline-lg text-primary">Happy Place</h1>
          {error ? (
            <>
              <p className="mt-md border border-error bg-error-container p-sm font-body-sm text-on-error-container" role="alert">
                {error}
              </p>
              <Button
                onClick={() => setAttempt((n) => n + 1)}
                className="mt-md h-12 w-full rounded-none font-label-md text-xs uppercase text-on-primary"
              >
                RÉESSAYER
              </Button>
            </>
          ) : (
            <p className="mt-sm font-body-md text-body-md text-on-surface-variant" role="status">
              Ouverture de ton espace…
            </p>
          )}
        </section>
      </main>
    </div>
  );
}

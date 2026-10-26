import { Link, useRouterState } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import sharkLogo from "@/assets/bigger-boat-shark.png";
import { supabase } from "@/integrations/supabase/client";

export function BrandHeader() {
  // Version élèves : lien « Changer de rôle » visible dès qu'on est connecté.
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const [signedIn, setSignedIn] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSignedIn(!!data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => setSignedIn(!!session));
    return () => sub.subscription.unsubscribe();
  }, []);

  return (
    <header className="border-b border-outline-variant bg-surface-container-lowest">
      <div className="mx-auto flex min-h-16 w-full max-w-interface items-center justify-between gap-md px-sm py-xs md:px-md">
        <Link to="/" className="flex min-w-0 items-center gap-sm" aria-label="Bigger Boat — accueil">
          <img
            src={sharkLogo}
            alt=""
            width={1024}
            height={1024}
            className="h-11 w-14 shrink-0 object-contain"
          />
          <span className="font-label-md text-lg font-bold uppercase text-primary">Bigger Boat</span>
        </Link>
        <div className="flex items-center gap-md">
          {signedIn && pathname !== "/choisir-role" && (
            <Link
              to="/choisir-role"
              className="font-label-sm text-label-sm uppercase text-primary underline-offset-2 hover:underline"
            >
              Changer de rôle
            </Link>
          )}
          <span className="font-label-sm text-label-sm uppercase text-on-surface-variant">Happy Place</span>
        </div>
      </div>
    </header>
  );
}

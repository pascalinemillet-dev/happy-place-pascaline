import { createFileRoute, isRedirect, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { fetchOwnRole } from "@/lib/auth";

// Liste blanche (lot 0, T9) : un compte connecté sans rôle n'est pas invité.
// Il est déconnecté et renvoyé vers /auth avec un message.
export const Route = createFileRoute("/_authenticated")({
  ssr: false,
  beforeLoad: async () => {
    try {
      const { data, error } = await supabase.auth.getUser();
      if (error || !data.user) throw redirect({ to: "/auth" });
      const email = data.user.email ?? "";
      const role = email ? await fetchOwnRole(email) : null;
      if (!role) {
        await supabase.auth.signOut({ scope: "local" }).catch(() => {});
        throw redirect({ to: "/auth", search: { refuse: 1 } });
      }
      return { user: data.user, email, role };
    } catch (e) {
      if (isRedirect(e)) throw e;
      // Session périmée ou compte changé dans un autre onglet : retour propre à la connexion.
      await supabase.auth.signOut({ scope: "local" }).catch(() => {});
      throw redirect({ to: "/auth" });
    }
  },
  component: () => <Outlet />,
});

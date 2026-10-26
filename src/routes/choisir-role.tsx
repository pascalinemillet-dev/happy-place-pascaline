import { createFileRoute, redirect } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { fetchOwnRole, signOut, type AppRole } from "@/lib/auth";
import { BrandHeader } from "@/components/brand-header";
import { Button } from "@/components/ui/button";

// Version élèves : chaque personne connectée choisit son rôle et son équipe,
// et peut revenir ici à tout moment pour en changer (lien « Changer de rôle » dans l'en-tête).

export const Route = createFileRoute("/choisir-role")({
  ssr: false,
  head: () => ({ meta: [{ title: "Choisir mon rôle — Happy Place" }] }),
  beforeLoad: async () => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/auth" });
    return { email: data.user.email ?? "" };
  },
  component: ChoisirRolePage,
});

const ROLES: { value: AppRole; label: string; description: string }[] = [
  {
    value: "collaborateur",
    label: "Collaborateur",
    description: "Je lis les actualités et les indicateurs, et je remonte des idées, questions ou problèmes à mon équipe.",
  },
  {
    value: "manager",
    label: "Manager",
    description: "Je valide ou refuse les demandes de mon équipe, je rédige des actualités et je suis les points bloquants.",
  },
  {
    value: "admin",
    label: "Admin",
    description: "Je gère tout : contenus, indicateurs, équipes et utilisateurs.",
  },
];

function ChoisirRolePage() {
  const { email } = Route.useRouteContext();
  const [teams, setTeams] = useState<string[]>([]);
  const [current, setCurrent] = useState<AppRole | null>(null);
  const [role, setRole] = useState<AppRole>("collaborateur");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [team, setTeam] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        // Compte anonyme tout neuf : pas encore d'adresse, donc pas encore de profil
        const [{ data: teamRows, error: teamErr }, own, existingRole] = await Promise.all([
          supabase.from("teams").select("name").eq("is_reserved", false).order("name"),
          email
            ? supabase.from("allowed_users").select("id, first_name, last_name, team").eq("email", email.toLowerCase()).maybeSingle()
            : Promise.resolve({ data: null }),
          email ? fetchOwnRole(email) : Promise.resolve(null),
        ]);
        if (teamErr) throw teamErr;
        setTeams((teamRows ?? []).map((t) => t.name));
        if (own.data) {
          setFirstName(own.data.first_name ?? "");
          setLastName(own.data.last_name ?? "");
          let currentTeam = own.data.team ?? "";
          if (existingRole === "manager") {
            const { data: mt } = await supabase.from("manager_teams").select("team").eq("allowed_user_id", own.data.id).limit(1);
            currentTeam = mt?.[0]?.team ?? "";
          }
          setTeam(currentTeam);
        }
        if (existingRole) {
          setCurrent(existingRole);
          setRole(existingRole);
        }
      } catch {
        setError("Impossible de charger les équipes. Vérifie que les migrations Supabase ont bien été exécutées.");
      } finally {
        setLoading(false);
      }
    })();
  }, [email]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!firstName.trim() || !lastName.trim()) {
      setError("Renseigne ton prénom et ton nom.");
      return;
    }
    if (role !== "admin" && !team) {
      setError("Choisis une équipe.");
      return;
    }
    setBusy(true);
    const { error: err } = await supabase.rpc("choisir_mon_role", {
      _role: role,
      _first_name: firstName.trim(),
      _last_name: lastName.trim(),
      _team: role === "admin" ? null : team,
    });
    if (err) {
      setBusy(false);
      setError(err.message);
      return;
    }
    // La base vient éventuellement d'attribuer une adresse interne au compte :
    // on rafraîchit la session pour que les règles de sécurité la voient.
    await supabase.auth.refreshSession();
    // Rechargement complet : le dashboard relit le rôle à l'ouverture.
    window.location.replace("/");
  }

  const inputCls =
    "mt-xs h-11 w-full border border-outline-variant bg-background px-sm font-body-md text-body-md text-on-surface focus:outline-none focus:ring-2 focus:ring-primary";
  const labelCls = "block font-label-sm text-label-sm uppercase text-on-surface-variant";

  return (
    <div className="min-h-dvh w-full bg-background flex flex-col">
      <BrandHeader />
      <main className="flex flex-1 items-center justify-center px-md py-lg">
        <section className="w-[min(100%,34rem)] border border-outline-variant bg-surface-container-lowest p-lg shadow-sm">
          <div className="space-y-xs">
            <p className="font-label-sm text-label-sm uppercase text-on-surface-variant">
              {current ? `Rôle actuel : ${current}` : "Première connexion"}
            </p>
            <h1 className="font-headline-lg text-headline-lg text-primary">Choisis ton rôle</h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Tu pourras en changer à tout moment pour tester l'app sous un autre angle.
            </p>
          </div>

          {error && (
            <p className="mt-md border border-error bg-error-container p-sm font-body-sm text-on-error-container" role="alert">
              {error}
            </p>
          )}

          {loading ? (
            <p className="mt-md font-body-md text-on-surface-variant">Chargement…</p>
          ) : (
            <form onSubmit={submit} className="mt-md space-y-md" noValidate>
              <div className="grid grid-cols-1 gap-sm sm:grid-cols-2">
                <label className={labelCls}>
                  Prénom
                  <input value={firstName} onChange={(e) => setFirstName(e.target.value)} maxLength={100} autoComplete="given-name" className={inputCls} />
                </label>
                <label className={labelCls}>
                  Nom
                  <input value={lastName} onChange={(e) => setLastName(e.target.value)} maxLength={100} autoComplete="family-name" className={inputCls} />
                </label>
              </div>

              <fieldset className="space-y-xs">
                <legend className={labelCls}>Rôle</legend>
                {ROLES.map((r) => (
                  <label
                    key={r.value}
                    className={`flex cursor-pointer gap-sm border p-sm ${
                      role === r.value ? "border-primary bg-surface-container" : "border-outline-variant"
                    }`}
                  >
                    <input
                      type="radio"
                      name="role"
                      value={r.value}
                      checked={role === r.value}
                      onChange={() => setRole(r.value)}
                      className="mt-1 accent-[var(--color-primary)]"
                    />
                    <span>
                      <span className="block font-label-md text-label-md text-on-surface">{r.label}</span>
                      <span className="block font-body-sm text-body-sm text-on-surface-variant">{r.description}</span>
                    </span>
                  </label>
                ))}
              </fieldset>

              {role !== "admin" && (
                <label className={labelCls}>
                  {role === "manager" ? "Équipe que tu manages" : "Ton équipe"}
                  <select value={team} onChange={(e) => setTeam(e.target.value)} className={inputCls}>
                    <option value="">Choisir une équipe…</option>
                    {teams.map((t) => (
                      <option key={t} value={t}>
                        {t}
                      </option>
                    ))}
                  </select>
                </label>
              )}

              <Button type="submit" disabled={busy} className="h-12 w-full rounded-none font-label-md text-xs uppercase text-on-primary">
                {busy ? "PATIENTE…" : current ? "CHANGER DE RÔLE" : "ENTRER DANS HAPPY PLACE"}
              </Button>
            </form>
          )}

          <div className="mt-sm flex flex-wrap items-center justify-between gap-xs font-body-sm text-body-sm text-on-surface-variant">
            <span>Ton rôle est gardé dans ce navigateur.</span>
            <button type="button" onClick={signOut} className="text-primary underline-offset-2 hover:underline">
              Recommencer avec un nouveau profil
            </button>
          </div>
        </section>
      </main>
    </div>
  );
}

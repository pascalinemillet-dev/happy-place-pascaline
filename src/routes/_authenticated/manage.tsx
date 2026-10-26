import { createFileRoute, Link, Outlet, redirect } from "@tanstack/react-router";
import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { processAttachmentDeletionQueue } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/manage")({
  head: () => ({
    meta: [
      { title: "Gestion des données — Happy Place" },
      {
        name: "description",
        content:
          "Gérer les actualités du cabinet, les propositions internes, les alertes sur les recrutements et les indicateurs de performance.",
      },
      { property: "og:title", content: "Gestion des données — Happy Place" },
      {
        property: "og:description",
        content: "Gestion de l'activité d'un cabinet de recrutement spécialisé dans l'IT et le digital.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  beforeLoad: ({ context }) => {
    if (context.role !== "admin") throw redirect({ to: "/" });
  },
  component: ManageLayout,
});

const tabs = [
  { to: "/manage/news", label: "ACTUALITÉS" },
  { to: "/manage/submissions", label: "SOUMISSIONS" },
  { to: "/manage/blockers", label: "POINTS BLOQUANTS" },
  { to: "/manage/metrics", label: "INDICATEURS" },
  { to: "/manage/users", label: "UTILISATEURS AUTORISÉS" },
] as const;

function ManageLayout() {
  const qc = useQueryClient();
  // Suppression silencieuse des pièces jointes échues, une fois par chargement de /manage
  useEffect(() => {
    processAttachmentDeletionQueue()
      .then((r) => {
        if (r.remaining > 0) toast.error(`${r.remaining} document(s) n'ont pas pu être supprimés.`);
        else if (r.deleted > 0) toast.success(`${r.deleted} document(s) supprimé(s)`);
      })
      .catch(() => toast.error("La suppression des documents échus a échoué."))
      .finally(() => qc.invalidateQueries({ queryKey: ["attachment_deletion_queue"] }));
  }, [qc]);
  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen">
      <BrandHeader />
      <main className="w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-sm">
          <div className="space-y-1">
            <p className="font-label-sm text-label-sm text-on-surface-variant uppercase tracking-widest">
              Gestion des données
            </p>
            <h1 className="font-headline-lg text-headline-lg text-primary">Gestion des données</h1>
          </div>
          <Link
            to="/"
            className="px-md py-xs border border-outline bg-surface text-primary font-label-md text-label-md hover:bg-surface-container"
          >
            ← RETOUR À LA VUE D'ENSEMBLE
          </Link>
        </div>

        <nav className="flex flex-wrap gap-xs border-b border-outline-variant pb-sm">
          {tabs.map((t) => (
            <Link
              key={t.to}
              to={t.to}
              className="px-md py-xs border border-outline-variant font-label-md text-label-md text-on-surface-variant hover:bg-surface-container"
              activeProps={{ className: "bg-primary text-on-primary border-primary" }}
            >
              {t.label}
            </Link>
          ))}
        </nav>

        <Outlet />
      </main>
    </div>
  );
}

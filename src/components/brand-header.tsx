import { Link } from "@tanstack/react-router";
import { MessageSquare } from "lucide-react";
import sharkLogo from "@/assets/bigger-boat-shark.png";
import { FEEDBACK_FORM_URL } from "@/lib/feedback";

export function BrandHeader({ showFeedback = true }: { showFeedback?: boolean }) {
  // Liste blanche (lot 0, T9) : plus de lien « Changer de rôle ». Le rôle vient de la liste des invités ;
  // la déconnexion se fait par le bouton « Déconnexion » du tableau de bord.
  return (
    <header className="border-b border-outline-variant bg-surface-container-lowest">
      <div className="mx-auto flex min-h-16 w-full max-w-interface items-center justify-between gap-md px-sm py-xs md:px-md">
        <Link
          to="/"
          className="flex min-w-0 items-center gap-sm"
          aria-label="Bigger Boat — accueil"
        >
          <img
            src={sharkLogo}
            alt=""
            width={1024}
            height={1024}
            className="h-11 w-14 shrink-0 object-contain"
          />
          <span className="font-label-md text-lg font-bold uppercase text-primary">
            Bigger Boat
          </span>
        </Link>
        <div className="flex shrink-0 items-center gap-md">
          {showFeedback && (
            <a
              href={FEEDBACK_FORM_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-xs font-label-sm text-label-sm text-primary underline-offset-2 hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              aria-label="Vos feedbacks (nouvel onglet)"
              title="Donnez votre avis sur HappyPlace"
            >
              <MessageSquare className="h-4 w-4" aria-hidden="true" />
              Vos feedbacks
            </a>
          )}
          <span className="font-label-sm text-label-sm uppercase text-on-surface-variant">
            Happy Place
          </span>
        </div>
      </div>
    </header>
  );
}

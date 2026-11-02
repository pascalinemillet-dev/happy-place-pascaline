/**
 * Phrase d'aide sous le titre de chaque module de la page d'accueil (US56).
 * Textes validés par Pascaline le 2026-11-02 (Soumettre et file de l'admin révisés le même jour).
 * Un seul endroit pour les modifier.
 */
export const MODULE_HINTS = {
  "points-bloquants": "Ce qui freine le travail en ce moment, et où en est sa résolution.",
  indicateurs: "Les chiffres clés du cabinet, avec leur période de calcul.",
  actus: "Les annonces du cabinet, publiées par les managers et l'administration.",
  soumettre: "Proposez une idée ou signalez un point bloquant à votre équipe d'encadrement.",
  "mes-soumissions": "Le suivi de vos idées et points bloquants : statut, décision et raison.",
  "idees-validees": "Les idées retenues par les managers, visibles de tous.",
  "soumissions-en-attente":
    "Les idées et points bloquants de votre équipe, à valider ou à refuser.",
  "soumissions-en-attente-admin":
    "Les points bloquants de toutes les équipes et les idées des équipes sans manager, à valider ou à refuser.",
} as const;

export type ModuleHintKey = keyof typeof MODULE_HINTS;

/** Identifiant à reprendre dans `aria-describedby` du bloc, pour les lecteurs d'écran. */
export const hintId = (key: ModuleHintKey) => `aide-${key}`;

export function ModuleHint({ module, className = "" }: { module: ModuleHintKey; className?: string }) {
  return (
    <p id={hintId(module)} className={`text-body-sm text-on-surface-variant ${className}`}>
      {MODULE_HINTS[module]}
    </p>
  );
}

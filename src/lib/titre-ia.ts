// Titre proposé par l'IA (US31), révision du 2026-11-03 (demande de Pascaline) :
// le titre résume la description en 5 mots au plus. Utilisable côté serveur et navigateur.
// La limite vaut pour la proposition de l'IA seulement : un titre saisi à la main reste libre
// (160 caractères au plus, contrôlés par la base).

export const MAX_MOTS_TITRE_IA = 5;

/** Mots qui ne terminent pas un titre : on les retire après une coupe. */
const MOTS_DE_LIAISON = new Set(
  "à au aux avec chez d dans de des du en entre et l la le les ou par pour sans sur un une vers".split(
    " ",
  ),
);

function mots(texte: string): string[] {
  return texte.trim().split(/\s+/).filter(Boolean);
}

/** Nombre de mots séparés par des espaces : « d'accès » compte pour un mot. */
export function compterMots(texte: string): number {
  return mots(texte).length;
}

/** Un titre de l'IA est trop long s'il dépasse 5 mots. */
export function titreIaTropLong(titre: string | null | undefined): boolean {
  return !!titre && compterMots(titre) > MAX_MOTS_TITRE_IA;
}

/**
 * Garde-fou si l'IA ne respecte pas la consigne : nettoie la réponse, garde les 5 premiers mots
 * et retire un mot de liaison ou une ponctuation laissés en fin de titre.
 */
export function nettoyerTitreIa(brut: string | null | undefined): string | null {
  if (!brut) return null;
  const ligne = brut.split(/\r?\n/).find((l) => l.trim()) ?? "";
  const propre = ligne.replace(/^["«“\s]+|["»”\s.]+$/g, "").replace(/^titre\s*:\s*/i, "");
  const garde = mots(propre).slice(0, MAX_MOTS_TITRE_IA);
  while (garde.length > 1) {
    const dernier = garde[garde.length - 1]
      .toLowerCase()
      .replace(/[’']$/, "")
      .replace(/[,;:–-]+$/, "");
    if (dernier && !MOTS_DE_LIAISON.has(dernier)) break;
    garde.pop();
  }
  const titre = garde
    .join(" ")
    .replace(/[,;:–-]+$/, "")
    .trim();
  return titre || null;
}

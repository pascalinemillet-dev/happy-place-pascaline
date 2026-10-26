// Bibliothèques lourdes chargées dans le navigateur uniquement, depuis /public/vendor.
// Les importer depuis le code de l'app les embarque côté serveur, où leurs
// dépendances Node font planter tout le site publié.
const cache = new Map<string, Promise<unknown>>();

export function loadBrowserLib<T>(src: string, globalName: string): Promise<T> {
  const w = window as unknown as Record<string, unknown>;
  if (w[globalName]) return Promise.resolve(w[globalName] as T);
  let p = cache.get(src) as Promise<T> | undefined;
  if (!p) {
    p = new Promise<T>((resolve, reject) => {
      const script = document.createElement("script");
      script.src = src;
      script.async = true;
      script.onload = () =>
        w[globalName] ? resolve(w[globalName] as T) : reject(new Error("Impossible de charger un composant du navigateur."));
      script.onerror = () => {
        cache.delete(src);
        reject(new Error("Impossible de charger un composant du navigateur. Vérifie ta connexion et réessaie."));
      };
      document.head.appendChild(script);
    });
    cache.set(src, p);
  }
  return p;
}

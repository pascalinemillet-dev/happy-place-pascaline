import { useEffect, useRef } from "react";
import { trackEvent } from "@/lib/f1";

/** Enregistre `module_viewed` une fois par affichage de page, quand le bloc entre à l'écran (US34). */
export function useModuleViewed<T extends Element>(module: string) {
  const ref = useRef<T>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          trackEvent("module_viewed", module);
          observer.disconnect();
        }
      },
      { threshold: 0.25 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [module]);
  return ref;
}

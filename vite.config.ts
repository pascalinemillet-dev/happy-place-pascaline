// Configuration Vite standard (remplace @lovable.dev/vite-tanstack-config).
import { defineConfig, loadEnv } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import tsConfigPaths from "vite-tsconfig-paths";
import { nitro } from "nitro/vite";

export default defineConfig(({ mode }) => {
  // Les fonctions serveur (src/lib/ai.functions.ts) lisent MAKE_AI_WEBHOOK_URL dans process.env :
  // en développement, on y recopie le contenu de .env (sans écraser l'environnement existant).
  for (const [key, value] of Object.entries(loadEnv(mode, process.cwd(), ""))) {
    if (!(key in process.env)) process.env[key] = value;
  }
  return {
    server: {
      port: 3000,
      // Autorise l'aperçu dans GitHub Codespaces (adresses en *.app.github.dev)
      allowedHosts: [".app.github.dev"],
    },
    resolve: { dedupe: ["react", "react-dom", "@tanstack/react-router", "@tanstack/react-start"] },
    plugins: [
      tsConfigPaths(),
      tanstackStart({
        // Point d'entrée serveur : src/server.ts (page d'erreur propre en cas de plantage)
        server: { entry: "server" },
      }),
      nitro(),
      viteReact(),
      tailwindcss(),
    ],
  };
});

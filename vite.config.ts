// Configuration Vite standard (remplace @lovable.dev/vite-tanstack-config).
import { defineConfig } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import tsConfigPaths from "vite-tsconfig-paths";
import { nitro } from "nitro/vite";

export default defineConfig({
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
});

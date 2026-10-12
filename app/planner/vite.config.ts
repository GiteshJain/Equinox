// The new planner's build (decision #18, design §3). Run from the repository root by the npm scripts:
//   npm run build   builds app/planner into web/app/ (emptied first), served under /app/
//   npm test        runs the unit tests (Vitest)
// Paths are relative to the repository root, where npm runs the scripts.
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  root: "app/planner",
  // On Cloudflare, _redirects rules win over files and /planner/* already goes to the old planner, so the new planner's
  // files live under /app/ and only its page is mapped to /planner/next/ (design §3, choice 6).
  base: "/app/",
  plugins: [react()],
  // The planning library (decision #19, design §7), imported from its source as "@rules" (tsconfig.json's paths say the
  // same for the type check). No screen uses it yet; pull request 5 onwards do.
  resolve: { alias: { "@rules": fileURLToPath(new URL("../../lib/rules/src/index.ts", import.meta.url)) } },
  build: {
    outDir: "../../web/app",
    emptyOutDir: true,
    sourcemap: false,
    // The libraries in files of their own: they change only when a version does, so a planner change doesn't make the
    // browser fetch them again (web/_headers caches /app/assets/ for a year).
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            { name: "react", test: /node_modules[\\/](react|react-dom|scheduler|react-router)[\\/]/ },
            { name: "supabase", test: /node_modules[\\/]@supabase[\\/]/ },
            { name: "query", test: /node_modules[\\/]@tanstack[\\/]/ },
          ],
        },
      },
    },
  },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
    environment: "node",
  },
});

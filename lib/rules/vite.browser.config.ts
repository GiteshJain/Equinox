// The planning library as one browser file for the website's trip search (decision #19, design §3 and §7): `npm run
// build` (build:rules) bundles src/browser.ts into web/assets/rules.js, a plain script that sets window.EqRules. Not
// committed (.gitignore); Cloudflare builds it with the rest. Paths are relative to lib/rules, this config's root.
import { defineConfig } from "vite";

export default defineConfig({
  root: "lib/rules",
  publicDir: false,
  build: {
    outDir: "../../web/assets",
    emptyOutDir: false, // web/assets holds the website's own files: only rules.js is written
    sourcemap: false,
    copyPublicDir: false,
    lib: {
      entry: "src/browser.ts",
      name: "EqRules",
      formats: ["iife"],
      fileName: () => "rules.js",
    },
  },
});

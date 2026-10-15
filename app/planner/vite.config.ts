// The new planner's build (decision #18, design §3). Run from the repository root by the npm scripts:
//   npm run build   builds app/planner into web/app/ (emptied first), served under /app/
//   npm test        runs the unit tests (Vitest)
// Paths are relative to the repository root, where npm runs the scripts.
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// The planner's own build (decision #23): the moment it was built and the change it was built from, written in so Check's
// Systems board can show them; after a merge, a time that hasn't moved means Cloudflare's build failed. Cloudflare names
// the change it builds (CF_PAGES_COMMIT_SHA); elsewhere git does, and GitHub's runs name theirs (GITHUB_SHA).
const git = (...args: string[]): string => {
  try {
    return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return "";
  }
};
const commit = process.env.CF_PAGES_COMMIT_SHA || git("rev-parse", "HEAD") || process.env.GITHUB_SHA || "";
const build = { at: new Date().toISOString(), commit, subject: commit ? git("log", "-1", "--format=%s", commit) : "" };

export default defineConfig({
  root: "app/planner",
  define: {
    "import.meta.env.EQ_BUILD_AT": JSON.stringify(build.at),
    "import.meta.env.EQ_BUILD_COMMIT": JSON.stringify(build.commit),
    "import.meta.env.EQ_BUILD_SUBJECT": JSON.stringify(build.subject),
  },
  // On Cloudflare, _redirects rules win over files and /planner/* goes to the planner's page, so the new planner's files
  // live under /app/ and only its page is mapped, to /planner/ since the switch (design §3, choice 6).
  base: "/app/",
  plugins: [react()],
  // The planning library (decision #19, design §7), imported from its source as "@rules" (tsconfig.json's paths say the
  // same for the type check). Home uses it since pull request 5, and every rebuilt screen after it.
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
            // three.js, for Home's globe: loaded only when Home opens (screens/home/Globe.tsx imports the scene)
            { name: "three", test: /node_modules[\\/]three[\\/]/ },
          ],
        },
      },
    },
    // three.js is about 540 kB on its own (136 kB as sent); it's loaded only on Home, so it may pass the usual 500 kB note
    chunkSizeWarningLimit: 600,
  },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
    environment: "node",
  },
});

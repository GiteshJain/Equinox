// Lint for the new planner (decision #18, design §3): ESLint's and TypeScript's recommended rules, and React's hook
// rules. Run with `npm run lint`. The generated database types and the built output aren't linted.
// The planning library (decision #19, lib/rules/) gets the same recommended rules, and its parts are kept pure (spec §1:
// no clock, network or global state; a moment is always an argument): no Date.now(), new Date() without a moment,
// Math.random(), timers, fetch, process or browser globals, and no Node modules, outside its command (src/cli.ts) and
// its tests.
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import { defineConfig, globalIgnores } from "eslint/config";

const impure = ["process", "window", "document", "localStorage", "sessionStorage", "fetch", "setTimeout", "setInterval", "XMLHttpRequest", "navigator", "performance"];

export default defineConfig([
  globalIgnores(["web/**", "node_modules/**", "app/planner/src/db/types.ts", "lib/rules/dist/**"]),
  {
    files: ["app/**/*.{ts,tsx}"],
    extends: [js.configs.recommended, tseslint.configs.recommended, reactHooks.configs.flat.recommended],
  },
  {
    files: ["lib/**/*.ts"],
    extends: [js.configs.recommended, tseslint.configs.recommended],
  },
  {
    files: ["lib/rules/src/**/*.ts"],
    ignores: ["lib/rules/src/cli.ts"],
    rules: {
      "no-restricted-globals": ["error", ...impure.map((name) => ({ name, message: "The library is pure: pass what it needs as an argument." }))],
      "no-restricted-properties": ["error",
        { object: "Date", property: "now", message: "The library never reads a clock: take the moment as an argument." },
        { object: "Math", property: "random", message: "The library is pure: no randomness." }],
      "no-restricted-syntax": ["error",
        { selector: "NewExpression[callee.name='Date'][arguments.length=0]", message: "The library never reads a clock: take the moment as an argument." }],
      "no-restricted-imports": ["error", { patterns: [{ group: ["node:*", "fs", "path", "url", "os", "child_process", "http", "https"], message: "Only the command (src/cli.ts) may use Node." }] }],
    },
  },
]);

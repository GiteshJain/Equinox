// Lint for the new planner (decision #18, design §3): ESLint's and TypeScript's recommended rules, and React's hook
// rules. Run with `npm run lint`. The generated database types and the built output aren't linted.
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import { defineConfig, globalIgnores } from "eslint/config";

export default defineConfig([
  globalIgnores(["web/**", "node_modules/**", "app/planner/src/db/types.ts"]),
  {
    files: ["app/**/*.{ts,tsx}"],
    extends: [js.configs.recommended, tseslint.configs.recommended, reactHooks.configs.flat.recommended],
  },
]);

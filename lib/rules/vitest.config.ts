// The planning library's tests (decision #19, spec §4), run by `npm test` from the repository root: the hand-made cases
// in lib/rules/cases/ and the tests beside them in lib/rules/test/.
import { defineConfig } from "vitest/config";

export default defineConfig({
  root: "lib/rules",
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});

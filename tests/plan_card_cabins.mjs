// The cabin each plan card's routes call for (the planning library's card.cabinFor; manual §5, spec
// docs/specs/2026-10-21-cabins-new-rule.md §3), for tests/planner_next_test.py, which lists them for every plan card not yet
// filed on the rehearsal's copy and checks Tails shows the same on a card. Needs the library built (npm run build).
// Input on standard input: {"rules": rules_input()'s answer, "cards": [{registration, aircraft_id, config_id, legs: [...]}]}.
// Output: [{registration, card, suggested, layout, reason, missing, differs, error}], in the order given.
import { readFileSync } from "node:fs";
import { buildRules, card } from "../lib/rules/dist/index.js";

const x = JSON.parse(readFileSync(0, "utf8"));
const rules = buildRules(x.rules);
const out = (x.cards ?? []).map((c) => {
  try {
    const s = card.cabinFor(rules, { aircraft: c.aircraft_id, config_id: c.config_id ?? null, legs: c.legs ?? [] });
    return { registration: c.registration, card: s.card_code, suggested: s.code, layout: s.layout, reason: s.reason, missing: s.missing, differs: s.differs, error: null };
  } catch (e) {
    return { registration: c.registration, card: null, suggested: null, layout: null, reason: null, missing: null, differs: null, error: e instanceof Error ? e.message : String(e) };
  }
});
process.stdout.write(JSON.stringify(out));

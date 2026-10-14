// An airline's flights as the planner has them (the planning library's game.plannerFlights, the list the Check screen's
// game check compares with the game's), for tests/planner_saves_test.py, which answers the game check with them, a few
// changed. Needs the library built (npm run build: lib/rules/dist/).
// Input on standard input: {"rules": rules_input()'s answer, "markets": [{id, default_type_id}], "airline": <id>}.
// Output: {"<flight number>": [{from, to, dep, arr, days}]}.
import { readFileSync } from "node:fs";
import { buildRules, game } from "../lib/rules/dist/index.js";

const x = JSON.parse(readFileSync(0, "utf8"));
const rules = buildRules(x.rules);
const markets = new Map((x.markets ?? []).map((m) => [m.id, m.default_type_id]));
process.stdout.write(JSON.stringify(Object.fromEntries(game.plannerFlights(rules, x.airline, markets))));

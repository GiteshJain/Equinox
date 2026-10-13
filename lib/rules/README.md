# The planning library (`lib/rules/`)

The planning rules in one place (decision #19, design `docs/design/2026-10-12-planner-app.md` §7): block times,
turns, connections, banks, maintenance, an aircraft's week, the schedule checks, where each aircraft is, and the
optimiser. The new planner, the website's trip search, the optimiser and Claude all use it, so they all give the same
answer. The rules themselves are in the manual (§4 and §9); this is how they are worked out.

- **Plain data in, plain data out.** No screen code, no clock, no network: a moment is always an argument. Lint
  refuses `Date.now()`, timers, `fetch` and Node modules anywhere but the command.
- **Every number comes from the database:** `settings` (an airline's own value where it has one), `world_rules`,
  `aircraft_types` and the airports. A missing number is an error that names it, never a guess. The one figure in code
  is the 90-minute minimum connection time for an airport that has none (spec §5).
- **Nothing assumes six airlines or one world.** Airlines, bases and airports come from the input.

## The input
One JSON document, the database function `rules_input(world)`'s answer (staff), or `export_for_report(secret,
'rules')` for the scripts. `buildRules()` checks it and indexes it:

```ts
import { buildRules, connections } from "@rules";              // the new planner imports it from source
const rules = buildRules(input);                                // input: rules_input()'s answer
connections.connectionsAt(rules, "JFK").city_pairs.length;      // 171 on the 10 Oct sample
```

Times are minutes, in UTC, as `flight_legs` stores them: a leg leaves at `dep_utc_min` (0 to 1439) on each weekday
in `days_utc` (1 = Monday), so a moment in the week is 0 (Monday 00:00 UTC) to 10,079 (Sunday 23:59).

## The parts
Each part is exported under its name. One example each, on the cases' small world (`cases/_base.json`).

| Part | What it works out | Example |
|---|---|---|
| `time` | Local and UTC times at an airport, standard time all year; an airport's offset is the world's correction if it has one | `time.toLocal(rules, "CCC", 0)` → 330: Monday 00:00 UTC is 05:30 at +5:30 |
| `block` | Block minutes for a leg not yet timed: `block_allowance_min` + distance ÷ the type's `cruise_kmh`, rounded. A leg with `block_min` stored uses it | `block.blockFor(rules, "HUB", "AAA", "A321 NEO LIGHT").block_min` → 75 (25 + 700 km ÷ 840 km/h) |
| `turns` | Whether a turn fits: the type's `min_turn_min` + `turn_margin_min`; under the turnaround is short, under the margin tight | `turns.checkTurn(rules, a321, 75)` → tight (76 needed) |
| `connections` | Which arrivals connect onto which departures: from `mct_min` + `connection_buffer_min` to `connection_max_wait_h`, day by day across the week, across all our airlines; onward flights and feeders of a leg; a hub's city pairs and the bank each connects in | `connections.link(rules, arrival, departure)` → `{days: 7, of: 7, gap_min: 60}` |
| `banks` | A hub's bank windows (`airline_bases.bank_times`, the bank settings); which bank a departure collects and an arrival feeds. A focus city has none | `banks.bankOfArrival(rules, hub, 270)` → bank 1, "in", 90 minutes before it leaves |
| `maintenance` | Usable ground time against the need for an aircraft's week: need = cycles × `maint_per_cycle` + block hours × `maint_per_hour`; have = each gap beyond `ground_keep_min`, once that is at least `maint_min_ground_min`. Bad under `maintenance_min_pct`, a warning under `maintenance_target_pct`. A gap is left out only when it is a real overlap (the next flight leaves before this one lands); the old planner also left out every gap longer than 156 hours. No aircraft on the 12 Oct copy was affected | `maintenance.forAircraft(rules, "T-001").pct` → 101, a warning |
| `aircraftWeek` | An aircraft's week, as the Tails screen shows it: legs a week, block hours a day, routes, each departure with its ground time, turn and position | `aircraftWeek.forAircraft(rules, "T-001").block_hours_day` → 12 |
| `schedule` | Night bans hit, a second daily too close (`second_daily_gap_h`, and the game's `same_route_gap_min`), flight numbers used twice, departures a week per airport against the cap, the next free flight-number pair at a base | `schedule.nextFlightNumbers(rules, hub)` → 1009 / 1010 |
| `positions` | Where each aircraft is at a moment: in the air with the share flown, or on the ground since its last landing | `positions.positionsAt(rules, "2026-10-12T06:30:00Z")` → T-001 in the air, 40% of the way |
| `optimiser` | The best day's schedule for one aircraft from a base and some destinations: every order and start time, feasible against night bans, maintenance, the second-daily gap and turns; best by connections at the base (and any extra hubs), then maintenance | `optimiser.optimise(rules, {base: "HUB", destinations: ["AAA", "DDD"], ...}).best.order` → `["DDD", "AAA"]` |

Two more: `card.checkCard()` checks a plan card's legs against every rule above, at both ends, and `airport` gives an
airport's minimum connection time and night ban.

## The command
For Claude and the scripts (how to get the input: `scripts/README.md`). `npm run build` writes it to `dist/`.

```bash
node lib/rules/dist/cli.js block       rules.json DEL BOM "A321 NEO LIGHT"
node lib/rules/dist/cli.js connections rules.json KUL
node lib/rules/dist/cli.js aircraft    rules.json            # every aircraft; or add a registration for one week
node lib/rules/dist/cli.js check-card  rules.json card.json
node lib/rules/dist/cli.js optimise    rules.json KUL KCH,PQC,PEN --type "A321 NEO LIGHT" --start 05:00-11:00 --hubs DEL
```

It answers in JSON; an error goes to standard error with a non-zero exit. A card is
`{"aircraft": "9M-AAB", "legs": [{"flight_no": 6101, "origin_code": "KUL", "dest_code": "KCH", "dep_local": "06:45",
"days_local": [1, 2, 3, 4, 5, 6, 7]}, ...]}` (or `dep_utc_min` and `days_utc`, as `plan_card_legs` stores them); a leg
without `block_min` gets the estimate, and an aircraft not in the input needs `type` and `airline`. The optimiser's
start window and step default to 05:00 to 11:00 local and 5 minutes.

## The tests
- **Cases** (`cases/*.json`), run by Vitest in `npm test`: plain JSON, so pull request 3's database tests can answer the
  same questions. `_base.json` is a small made-up world; each file is one part's cases, each with its input (laid over
  the base: `settings` and `world_rules` merge key by key, lists are replaced), a question (`ask`) and the answer. An
  answer names only what it checks; numbers match to within 1e-9; `{"error": "..."}` expects a refusal. The questions
  are listed in `test/ask.ts`.
- **`tests/fixtures/optimiser_kul_2026-10-10.json`**: the optimiser on the test sample's legs at KUL, whose answer is
  plan.py's. A case in the same format, kept with the dated samples because it is game data (decision #9); the Vitest
  runner lists it in `test/cases.test.ts` and lays it over `_base.json` like the rest. `tests/rules_planpy_test.py`
  runs plan.py, unchanged, on the same input and checks it still gives that answer.
- **`test/library.test.ts`**: the builder's checks, settings and world rules, a plan card, every command.
- **On last night's copy** (the rehearsal): `tests/rules_library_test.py` compares the library with the old planner's
  Tails and Hubs screens (`tests/README.md`).

Run them: `npm run typecheck`, `npm run lint`, `npm test`, then `npm run build` and `python3 tests/rules_planpy_test.py`.

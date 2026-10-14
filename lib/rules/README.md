# The planning library (`lib/rules/`)

The planning rules in one place (decision #19, design `docs/design/2026-10-12-planner-app.md` §7): block times,
turns, connections, banks, maintenance, an aircraft's week, the schedule checks, where each aircraft is, the key
figures for the planner's Home, a route's frequencies for its Routes screen, an airport's board for its Hubs screen,
the game check, cabins, daily load report and growth lists for its Check screen, the plan card's service check, and the
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
| `time` | Local and UTC times at an airport, standard time all year; an airport's offset is the world's correction if it has one; the game clocks under the planner's header (`clocks`: one per time zone of the airports given, west to east, the local time and day from 06:00 to 18:00) | `time.toLocal(rules, "CCC", 0)` → 330: Monday 00:00 UTC is 05:30 at +5:30 |
| `block` | Block minutes for a leg not yet timed: `block_allowance_min` + distance ÷ the type's `cruise_kmh`, rounded. A leg with `block_min` stored uses it | `block.blockFor(rules, "HUB", "AAA", "A321 NEO LIGHT").block_min` → 75 (25 + 700 km ÷ 840 km/h) |
| `turns` | Whether a turn fits: the type's `min_turn_min` + `turn_margin_min`; under the turnaround is short, under the margin tight | `turns.checkTurn(rules, a321, 75)` → tight (76 needed) |
| `connections` | Which arrivals connect onto which departures: from `mct_min` + `connection_buffer_min` to `connection_max_wait_h`, day by day across the week, across all our airlines; onward flights and feeders of a leg; a hub's city pairs and the bank each connects in | `connections.link(rules, arrival, departure)` → `{days: 7, of: 7, gap_min: 60}` |
| `banks` | A hub's bank windows (`airline_bases.bank_times`, the bank settings); which bank a departure collects and an arrival feeds. A focus city has none | `banks.bankOfArrival(rules, hub, 270)` → bank 1, "in", 90 minutes before it leaves |
| `banks` (bank fit in words) | `wave`: how a frequency's departure and arrival fit a base's banks, as the old Routes words it ("B1 out · B2 in", "dep floats", "B2 in, 2:00 early", "arr off wave", "focus city · times to X banks", "no banks set"), each with its pill's level; `airlineBaseAt`, an airline's base at an airport (#18 build pull request 6) | `banks.wave(rules, hub, 390, 270).text` → "B1 out · B1 in" (leaves 06:30, the return lands 04:30; `cases/banks.json`) |
| `maintenance` | Usable ground time against the need for an aircraft's week: need = cycles × `maint_per_cycle` + block hours × `maint_per_hour`; have = each gap beyond `ground_keep_min`, once that is at least `maint_min_ground_min`. Bad under `maintenance_min_pct`, a warning under `maintenance_target_pct`. A gap is left out only when it is a real overlap (the next flight leaves before this one lands); the old planner also left out every gap longer than 156 hours. No aircraft on the 12 Oct copy was affected | `maintenance.forAircraft(rules, "T-001").pct` → 101, a warning |
| `aircraftWeek` | An aircraft's week, as the Tails screen shows it: legs a week, block hours a day, routes, each departure with its ground time, turn and position | `aircraftWeek.forAircraft(rules, "T-001").block_hours_day` → 12 |
| `schedule` | Night bans hit, a second daily too close (`second_daily_gap_h`, and the game's `same_route_gap_min`), flight numbers used twice, departures a week per airport against the cap (and Home's warning from `airport_cap_warning_pct` of it, bad at the cap: `airportCapWarnings`), the next free flight-number pair at a base | `schedule.nextFlightNumbers(rules, hub)` → 1009 / 1010 |
| `frequency` | A route's frequency for the Routes screen (#18 build pull request 6): a rotation's two legs from the times typed in local time at each end (`toLegs`: stored in UTC; the return on the old planner's day, the first departure after the outbound lands; an arrival left empty stores no block and takes the estimate) and back (`localTimes`, `view`: the old `computeFreq`, with day markers and est); `retime`, the legs re-timed to keep their local times when an airport's offset changes (`withOffset`); `checks`, every check on one frequency against the whole schedule (night bans, numbers used twice, the second-daily gap, the aircraft's position, the turn at the destination, the connections at both ends); `numberRanges` | `frequency.toLegs(rules, ends, {days: [1], dep_hub: 1200, arr_dest: 1335, dep_dest: 390, arr_hub: 410})` → the return on day 2, `cases/frequency.json` |
| `service` | The service profile a route takes by its distance (`profileFor`: the airline's own profile first, Ryanair's R, then the shared ones, the first the distance is under), as the old `serviceFor`; the profiles are in the input since build pull request 10 (`service_profiles`), or the caller's. The plan card's service check (`checkLegs`, build pull request 10): each leg's code against the one its route's distance calls for (`wantedFor`: the airline's own route either way round, with any override, else another's, else the great circle), flagging a wrong code or none with the leg, the code given and the code wanted; an input without service profiles isn't checked | `service.profileFor(profiles, 1, 700).code` → S1; on `cases/service.json`, S3 on a 700 km leg → "leg 2 (1102 AAA–HUB): service S3 given, its route's 700 km calls for S1" |
| `positions` | Where each aircraft is at a moment: in the air with the share flown, or on the ground since its last landing | `positions.positionsAt(rules, "2026-10-12T06:30:00Z")` → T-001 in the air, 40% of the way |
| `summary` | The key figures on the planner's Home (#18 build pull request 5), for the group and each airline: aircraft in service (status active), routes flying (those with a rotation), flights a day (each departure by an aircraft in service, ÷ 7) and seats a day (those departures' seats: the aircraft's cabin layout, else its type's `seats_max`, ÷ 7) | `summary.keyFigures(rules).flights_day` → 3.14 on `cases/summary.json` (22 departures a week) |
| `summary` (Home's other figures) | `airlineCards`: each airline's card (aircraft, routes, flights and block hours a day of its aircraft in service, the lowest maintenance with its level, departures with a short turn or wrong position, tight turns, flying, clean, its bases with live ones marked); `now`: the hero at a moment (aircraft in the air, departures on the moment's UTC weekday and in its next hour); `roundTrips`: each flying route's round trips a week | `summary.now(rules, "2026-10-12T06:30:00Z").in_air` → 1 on `cases/summary.json` |
| `tails` | An aircraft's issues on the Tails screen (#18 build pull request 7), in the old planner's `tailIssues` order: under the block-hours target (`aircraft_block_target_h`, a flag, not a floor), short turns, maintenance under `maintenance_min_pct` or `maintenance_target_pct`, tight turns, legs starting where it isn't, its longest ground gap under the type's `gap_target_h`, rotations off wave at either end (`offWave`: the bank fit's level bad); `marked` (the list's red dot) and `needsALook` (the Needs a look filter) | `tails.issues(rules, "T-001")` → four issues on `cases/tails.json`'s second case (8 h a day, 7 short and 7 tight turns, 14 legs starting elsewhere) |
| `hubs` | The Hubs screen (#18 build pull request 8), in local time at the airport, across all our airlines: `board` (one day, 0 = Monday: each flight with the bank it collects or feeds at its own airline's base there, the arrival's being the first bank it can make however long the wait, as the old Hubs named it; the hours; the week in 15-minute slots shaded by the bank windows; departures a week against the cap; the next free pair) and `connectionsTable` (`connections.connectionsAt` by bank, with the airports arriving and leaving, their flights by region (each airport's `region` in the input, from `countries.region`, through `regionOf`: **Other** when it has none), the tightest eight city pairs); `airports`, the boards there are | `hubs.board(rules, "HUB", 1).flights[1]` → flight 1004 from BBB landing 06:00 on Tuesday, bank 2 (`cases/hubs.json`) |
| `game` | The planner against the game's public schedule (Tails' check before filing and Check's game check, #18 build pull requests 7 and 9), as the old planner's `plannerFlights`, `compareFlights`, `importCandidates` and `applyGameFix`: `plannerFlights` (each flight number's entries in local time, a return on the day it leaves), `compare` (each number the same, different, in the planner only or in the game only, a flight valid only for some dates aside, with the fix where it's only a time or a day change), `importCandidates` (the game's numbers the planner hasn't got, paired into round trips one apart), `fixTimes` (the frequencies a fix changes, with their new local times) and `compareCard` (a plan card's legs) | `game.compare(rules, 1, flights).issues[0]` → flight 1002, "Different: departure, arrival", with the game's times as its fix (`cases/game.json`) |
| `cabins` | Check's Cabins board (#18 build pull request 9): `fit` (each aircraft whose cabin isn't the one most of its block time wants: a leg wants its route's own choice, else its market's default layout's cabin; the share, the mix, the layout of its type to refit to, strong at `cabin_refit_share_pct`, kept as is only for the cabin kept) and `refitCost` (`cabin_refit_cost`) | `cabins.refitCost(rules, 1)` → 200000 (`cases/cabins.json`) |
| `loadReport` | Check's daily load report (#18 build pull request 9): `flightsOn` (one day's departures, each outbound on its local weekdays at the hub and each return on the day it leaves, by airline then departure, a frequency in its first `load_leeway_days` after its launch marked) | `loadReport.flightsOn(rules, "2026-10-13", launches)` → 1001 at 06:00, then the overnight return 1004 at 06:30, in its first week (`cases/loadReport.json`) |
| `growth` | Check's Growth board (#18 build pull request 9): the order rotation (manual §3: `lastMove`, `nextMove`, `moveCandidates` with `growth_big_min_stars`, `shownMove` skipping a move with nothing ready), `readyFromLoads` (ready for another flight from the load reports: `growth_ready_full_share` over `growth_ready_min_days`), `hubReadiness` (each bank's cities feeding it now and with the plan cards, by region), `suggestedSize` (the aircraft size the next move suggests for a route: the first entry of the setting `suggested_size` for the move, the airline's own list before the world's, whose `min_stars` and `over_km` the route meets) and `orderQueues` (`order_queue_grace_h`, `order_queue_warn_h`) | `growth.nextMove(log, 2)` → `big` for an airline with nothing logged (`cases/growth.json`) |
| `checks` | The one-week aircraft checks (manual §1): each aircraft in service falls due `aircraft_check_after_days` after its latest launch or schedule change, done once checked on or after that day; the dates come from the tables (`aircraft.checked_on`, `schedule_changed_on`, `rotations.launched_on`), today is an argument | `checks.oneWeek(rules, facts, "2026-10-12")` → T-003 coming up on 13 Oct |
| `optimiser` | The best day's schedule for one aircraft from a base and some destinations: every order and start time, feasible against night bans, maintenance, the second-daily gap and turns; best by connections at the base (and any extra hubs), then maintenance | `optimiser.optimise(rules, {base: "HUB", destinations: ["AAA", "DDD"], ...}).best.order` → `["DDD", "AAA"]` |

Two more: `card.checkCard()` checks a plan card's legs against every rule above, at both ends, its service codes
included (each leg's `service_code`, its `service_given` and `service_wanted`, and `service` with the issues), and
`airport` gives an airport's minimum connection time and night ban.

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
"days_local": [1, 2, 3, 4, 5, 6, 7]}, ...]}` (or `dep_utc_min` and `days_utc`, as `plan_card_legs` stores them), each with its `service_code`; a leg
without `block_min` gets the estimate, and an aircraft not in the input needs `type` and `airline`. The optimiser's
start window and step default to 05:00 to 11:00 local and 5 minutes.

## The tests
- **Cases** (`cases/*.json`), run by Vitest in `npm test`: plain JSON, so pull request 3's database tests can answer the
  same questions. `_base.json` is a small made-up world; each file is one part's cases, each with its input (laid over
  the base: `settings` and `world_rules` merge key by key, lists are replaced), a question (`ask`) and the answer. An
  answer names only what it checks; numbers match to within 1e-9; `{"error": "..."}` expects a refusal. The questions
  are listed in `test/ask.ts`.
- **`tests/fixtures/optimiser_kul_2026-10-10.json`**: the optimiser on the test sample's legs at KUL, whose answer is
  plan.py's, saved before plan.py was retired (build pull request 4). A case in the same format, kept with the dated
  samples because it is game data (decision #9); the Vitest runner lists it in `test/cases.test.ts` and lays it over
  `_base.json` like the rest. `tests/optimiser_saved_answer_test.py` runs the built command on it and must find that
  answer.
- **`test/library.test.ts`**: the builder's checks, settings and world rules, a plan card, every command, and the
  website's connection test (below) against the library's own.
- **On last night's copy** (the rehearsal): `tests/rules_library_test.py` compares the library with the old planner's
  Tails, Hubs and Check screens (`tests/README.md`).

Run them: `npm run typecheck`, `npm run lint`, `npm test`, then `npm run build` and `python3 tests/optimiser_saved_answer_test.py`.

## The website's file
The website's trip search uses the library's connection test, from one browser file: `npm run build` (`build:rules`)
bundles `src/browser.ts` into `web/assets/rules.js` (`vite.browser.config.ts`; not committed, Cloudflare builds it), which
the website loads before `site.js` as `window.EqRules`. It holds only what the trip search needs:
`EqRules.connections.limitsFrom(mct_min, connection_max_wait_h)` (the same limits `connectionLimits()` gives, from the two
figures `site_public()` gives the website: each airport's `content.mct`, 90 minutes where it has none, and
`content.connection_max_wait_h`) and `isConnection(gap, limits)`.

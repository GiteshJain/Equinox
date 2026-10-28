# The planning library (`lib/rules/`)

The planning rules in one place (decision #19, design `docs/design/2026-10-12-planner-app.md` §7): block times,
turns, connections, banks, maintenance, an aircraft's week, the schedule checks, where each aircraft is, the key
figures for the planner's Home, a route's frequencies for its Routes screen, the game check, daily load report
and growth lists for its Check screen, the plan card's service check and its cabin, the optimiser and, since 28 Oct, the
7-day line optimiser and the card check across a line. (An airport's
board for the Hubs screen went with the Hubs clean-up, 21 Oct; the Cabins board's `cabins` with the board, 21 Oct; the one-week aircraft checks' `checks`, 22 Oct.) The new planner, the website's trip search, the optimiser and Claude all use it, so they all give the same
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
| `maintenance` | Usable ground time against the need for an aircraft's week: need = cycles × `maint_per_cycle` + block hours × `maint_per_hour`; have = each gap beyond `ground_keep_min`, once that is at least `maint_min_ground_min`. Bad under `maintenance_min_pct`, a warning under `maintenance_target_pct`. A gap is left out only when it is a real overlap (the next flight leaves before this one lands); the old planner also left out every gap longer than 156 hours. No aircraft on the 12 Oct copy was affected. **The spacing** (since 28 Oct, spec `docs/specs/2026-10-27-long-haul-lines.md` §3): the figures also give `counting_stops` and `max_gap_h`, the longest stretch between two stops that count (from the departure after one to the landing at the next, over the repeating week and wrapping its end; null when none counts), against `maintenance_max_gap_h` (`max_gap_limit_h`, `max_gap_ok`; both null on an input without the setting). A plain card (one day repeated) and a line's card (7 different days) are each one repeating week, so the same walk serves both (`spacing`) | `maintenance.forAircraft(rules, "T-001").pct` → 101, a warning; on `cases/maintenance.json`'s 78-hour card `max_gap_h` → 78, not ok |
| `aircraftWeek` | An aircraft's week, as the Tails screen shows it: legs a week, block hours a day, routes, each departure with its ground time, turn and position | `aircraftWeek.forAircraft(rules, "T-001").block_hours_day` → 12 |
| `schedule` | Night bans hit, a second daily too close (`second_daily_gap_h`, and the game's `same_route_gap_min`), flight numbers used twice, departures a week per airport against the cap (and Home's warning from `airport_cap_warning_pct` of it, bad at the cap: `airportCapWarnings`), the next free flight-number pair at a base | `schedule.nextFlightNumbers(rules, hub)` → 1009 / 1010 |
| `frequency` | A route's frequency for the Routes screen (#18 build pull request 6): a rotation's two legs from the times typed in local time at each end (`toLegs`: stored in UTC; the return on the old planner's day, the first departure after the outbound lands; an arrival left empty stores no block and takes the estimate) and back (`localTimes`, `view`: the old `computeFreq`, with day markers and est); `retime`, the legs re-timed to keep their local times when an airport's offset changes (`withOffset`); `checks`, every check on one frequency against the whole schedule (night bans, numbers used twice, the second-daily gap, the aircraft's position, the turn at the destination, the connections at both ends); `numberRanges` | `frequency.toLegs(rules, ends, {days: [1], dep_hub: 1200, arr_dest: 1335, dep_dest: 390, arr_hub: 410})` → the return on day 2, `cases/frequency.json` |
| `service` | The service profile a route takes by its distance (`profileFor`: the airline's own profile first, Ryanair's R, then the shared ones, the first the distance is under), as the old `serviceFor`; the profiles are in the input since build pull request 10 (`service_profiles`), or the caller's. The plan card's service check (`checkLegs`, build pull request 10): each leg's code against the one its route's distance calls for (`wantedFor`: the airline's own route either way round, with any override, else another's, else the great circle), flagging a wrong code or none with the leg, the code given and the code wanted; an input without service profiles isn't checked | `service.profileFor(profiles, 1, 700).code` → S1; on `cases/service.json`, S3 on a 700 km leg → "leg 2 (1102 AAA–HUB): service S3 given, its route's 700 km calls for S1" |
| `positions` | Where each aircraft is at a moment: in the air with the share flown, or on the ground since its last landing | `positions.positionsAt(rules, "2026-10-12T06:30:00Z")` → T-001 in the air, 40% of the way |
| `summary` | The key figures on the planner's Home (#18 build pull request 5), for the group and each airline: aircraft in service (status active), routes flying (those with a rotation), flights a day (each departure by an aircraft in service, ÷ 7) and seats a day (those departures' seats: the aircraft's cabin layout, else its type's `seats_max`, ÷ 7) | `summary.keyFigures(rules).flights_day` → 3.14 on `cases/summary.json` (22 departures a week) |
| `summary` (Home's other figures) | `airlineCards`: each airline's card (aircraft, routes, flights and block hours a day of its aircraft in service, the lowest maintenance with its level, departures with a short turn or wrong position, tight turns, flying, clean, its bases with live ones marked); `now`: the hero at a moment (aircraft in the air, departures on the moment's UTC weekday and in its next hour); `roundTrips`: each flying route's round trips a week | `summary.now(rules, "2026-10-12T06:30:00Z").in_air` → 1 on `cases/summary.json` |
| `tails` | An aircraft's issues on the Tails screen (#18 build pull request 7), in the old planner's `tailIssues` order: under the block-hours target (`aircraft_block_target_h`, a flag, not a floor), short turns, maintenance under `maintenance_min_pct` or `maintenance_target_pct`, tight turns, legs starting where it isn't, its longest ground gap under the type's `gap_target_h`, since 28 Oct a stretch without a counting maintenance stop over `maintenance_max_gap_h` (`maintenance_gap`: "no maintenance stop for 78 h, over 40"; nothing on an input without the setting), rotations off wave at either end (`offWave`: the bank fit's level bad); `marked` (the list's red dot) and `needsALook` (the Needs a look filter) | `tails.issues(rules, "T-001")` → four issues on `cases/tails.json`'s second case (8 h a day, 7 short and 7 tight turns, 14 legs starting elsewhere) |
| `game` | The planner against the game's public schedule (Tails' check before filing and Check's game check, #18 build pull requests 7 and 9), as the old planner's `plannerFlights`, `compareFlights`, `importCandidates` and `applyGameFix`: `plannerFlights` (each flight number's entries in local time, a return on the day it leaves), `compare` (each number the same, different, in the planner only or in the game only, a flight valid only for some dates aside, with the fix where it's only a time or a day change), `importCandidates` (the game's numbers the planner hasn't got, paired into round trips one apart), `fixTimes` (the frequencies a fix changes, with their new local times) and `compareCard` (a plan card's legs). A rotation with no aircraft estimates its empty arrival on the airline's most-flown type (`mostFlownType`: the type with the most departures a week; its market's default type until 21 Oct) | `game.compare(rules, 1, flights).issues[0]` → flight 1002, "Different: departure, arrival", with the game's times as its fix (`cases/game.json`) |
| `loadReport` | Check's daily load report (#18 build pull request 9): `flightsOn` (one day's departures, each outbound on its local weekdays at the hub and each return on the day it leaves, by airline then departure, a frequency in its first `load_leeway_days` after its launch marked) | `loadReport.flightsOn(rules, "2026-10-13", launches)` → 1001 at 06:00, then the overnight return 1004 at 06:30, in its first week (`cases/loadReport.json`) |
| `growth` | Check's Growth board (#18 build pull request 9): the order rotation (manual §3: `lastMove`, `nextMove`, `moveCandidates` with `growth_big_min_stars`, `shownMove` skipping a move with nothing ready), `readyFromLoads` (ready for another flight from the load reports: `growth_ready_full_share` over `growth_ready_min_days`), `hubReadiness` (each bank's cities feeding it now and with the plan cards, by region), `suggestedSize` (the aircraft size the next move suggests for a route: the first entry of the setting `suggested_size` for the move, the airline's own list before the world's, whose `min_stars` and `over_km` the route meets) and `orderQueues` (`order_queue_grace_h`, `order_queue_warn_h`) | `growth.nextMove(log, 2)` → `big` for an airline with nothing logged (`cases/growth.json`) |
| `lineOptimiser` | **The best 7-day rotating line** (since 28 Oct; manual §4, long haul in lines; spec `docs/specs/2026-10-27-long-haul-lines.md` §1): for an airline, a type, the hubs a line day may start or end at (where its connections count) and the candidate routes (long ones and medium fillers; `fixed` ones must be on it), one aircraft's 168 hours over the routes, each flown once each way as one closed walk from a hub (day 2 starts where day 1 ends, day 7 ends where day 1 starts), and its 7 cards: aircraft k flies line day d on weekday ((d + k − 2) mod 7) + 1, so every leg operates daily. Feasible when turns (the turnaround plus `turn_margin_min`), night bans, the same-route gap against the flights flying (`same_route_gap_min`), every route within the type's reach (`aircraft_types.range_km`, or the caller's `rangeKm` since `rules_input()` doesn't carry it yet: a route beyond is refused with the reason, a reach it hasn't got is an error naming it), maintenance at or above `maintenance_min_pct`, no stretch over `maintenance_max_gap_h` without a counting stop, and the week closing on itself. Scored by connections within `plan_connection_target_h` at the hubs (counted as the day optimiser counts them, `optimiser.countConnections`), then all to `connection_max_wait_h`, then routes covered, block hours, maintenance. The search is a heuristic: every route set (all, then each with one dropped, only while nothing fits), each closed walk in a fixed order, the first departure on the start hub's bank ladder (by `step`), the rest by a greedy chain kept as a small beam (at a hub its ladder times and the banks' arrival deadlines, everywhere the earliest and the earliest that makes a counting stop, pushed past night bans), then local moves on the best line; capped by a `budget` of work (chains plus lines evaluated) or the caller's time check, and the answer says whether it finished (`search.finished`, `search.note`: "best found …, search not finished"). No randomness: the same input and work budget give the same answer. Each leg gets a flight number from the airline's pool at the start hub (`schedule.nextFlightNumbers`, above the flight legs' and the base's last number, skipping `usedFlightNumbers`, the plan cards'; the way out odd, the way back the next) and its service code by distance (`service.wantedFor`) | `lineOptimiser.optimiseLine(rules, {airlineId: 1, type: "A321 NEO LIGHT", hubs: ["HUB"], routes: [["HUB","BBB"],["HUB","CCC"],["HUB","NBN"]], step: 30, rangeKm: 7000, budget: {work: 120}}).best.legs.length` → 6 on `cases/lineOptimiser.json`; the Pan Am A350 sample in `tests/fixtures/line_a350_2026-10-12.json` |
| `optimiser` | The best day's schedule for one aircraft from a base and some destinations: every order and start time, feasible against night bans, maintenance, the second-daily gap and turns; best by the connections at the base (and any extra hubs) within the planning target, from the minimum connection time to `plan_connection_target_h` (4 hours, since 27 Oct, manual §4); then all connections, to `connection_max_wait_h`; then maintenance. Its `best` gives both counts (`connections_within_target`, `connections`) and the answer the target (`connection_target_h`); an input without the setting is refused, naming it | `optimiser.optimise(rules, {base: "HUB", destinations: ["AAA", "DDD"], ...}).best.order` → `["DDD", "AAA"]` |

Two more: `card.checkCard()` checks a plan card's legs against every rule above, at both ends, its service codes
included (each leg's `service_code`, its `service_given` and `service_wanted`, and `service` with the issues), and its
cabin (since 21 Oct, manual §5; by distance since 26 Oct): `card.cabinFor()` works out the cabin the card's routes call
for (each route in a distance range, `card.cabinRange()`: Leisure under `cabin_leisure_max_km`, Leisure Plus to under
`cabin_leisure_plus_max_km`, Comfort beyond, from the route's distance else the great circle; the range over
`cabin_route_share_pct` of the card's block time decides, otherwise the layout with the most seats; no market layout or
route choice overrides it; a low-cost airline Standard only; then the variant's layout of that name, among those the
airline may choose), with each route's and each range's share and the reason in words ("3,500–6,500 km is 72% of block
time: Leisure Plus", "no distance range over 65%: the most seats"), and a card whose cabin is missing or differs is a
problem; an input without the variant's layouts, or without `cabin_route_share_pct` or the two distance settings (made
before they came), isn't checked for its cabin (`cases/cabinFor.json`). Since 21 Oct
(manual §5; spec `docs/specs/2026-10-21-frequencies-and-fares.md` §2) `card.cardFares()` gives the fare level of each route
the card flies, once per route in the order of its legs, from `fare_ladder()`'s answer for the card's airline: each cabin
the ladder has for the route at its level (this week's new level once the move is on the fare plan), worded as the
game's Ticket price adjustment takes it ("economy +10%, business +5% of the default price"), and a route not flown yet
at launch ("launch (+0% of the default price)", Ryanair −15%); handed the same ladder, `checkCard()`'s answer has them
as `fares` (`cases/cardFares.json`). Since 26 Oct (spec `docs/specs/2026-10-26-fare-ladder-per-direction.md` §3) each
direction has its own level: the answer has one entry per direction the card flies, in the order of its legs, each with
`direction` (out from the route's hub, back to it; null for a pair the airline has no route for), `from` and `to`, and
the levels of that direction's ladder rows (a row without a direction, from before then, counts for both). Nothing is
stored on the card. Since 27 Oct (manual §4; spec `docs/specs/2026-10-27-planning-connection-target.md` §3) the check
also says how many of the connections fall within the planning target, `plan_connection_target_h` (4 hours;
`connections.targetLimits`): each leg's `feeders_within_target`, `onward_within_target`, `within_target` and
`within_target_share` (percent, one decimal; null with no connections) beside its `feeders` and `onward`, and the card's
`connections` (`target_h`, `total`, `within_target`, `within_target_share`; each arrival and departure pair once). It is
a figure, never a problem: a card isn't wrong for having long connections. An input made before the setting gets null
figures (`cases/connections.json`'s last case). Since 28 Oct (spec `docs/specs/2026-10-27-long-haul-lines.md` §3) the
check also flags the maintenance spacing: a stretch without a counting stop longer than `maintenance_max_gap_h` is a
problem ("no maintenance stop for 78 h, over 40"; "no maintenance stop all week, over 40 h" when none counts), on every
card, lines or not, and an input without the setting isn't checked. And `card.checkLine()` checks **a line of up to 7
cards** (the same spec): each card as `checkCard()` does, with the other cards' legs laid into the network (so a line's
own flights count as its connections, and two cards with the same number on the same local weekday clash as they would
in the game), then the line as a whole: each flight's local weekdays across the cards (`flights`: `days`, `missing`,
`daily`, which cards), `missing_days` until all 7 cards exist, each route's days out and back (`routes`,
`both_ways_daily`), and `complete` with 7 cards; with every card, a flight missing a day or a route not flown back daily
is a problem, with fewer cards the missing days are reported and not. The same flight number on different days of
different cards is never a clash, and since 28 Oct an aircraft of the line that already flies (filed) isn't counted
twice: its card stands for its flights, so they are left out of the network the other cards are checked against.
`card.fromLine(line, offset)` (since 28 Oct, spec §2) gives the card of the aircraft at an offset (0 to 6) on a line
from the line's legs as `plan_line_legs` keeps them (`line_day`, `flight_no`, `origin_code`, `dest_code`,
`dep_utc_min`, `block_min`, `service_code`): every leg, in the line's order, each on UTC weekday
`card.lineWeekday(line_day, offset)` = ((d + offset − 1) mod 7) + 1. The optimiser's 7 cards are made the same way, and
the planner's Write the next card uses it. `airport` gives an airport's minimum connection time
and night ban.

**Stations** (since 22 Oct, manual §2; spec `docs/specs/2026-10-22-station-role.md`): an `airline_bases` row with role
`station` is an airport the airline flies point-to-point routes from without making it a base. `banks.isStation` and
`banks.hasBanks` say which; a station has no bank windows, `wave` words it "station · no banks" (never off wave), and a
card's legs there collect no bank. `banks.baseAt` takes the airline's own row at an airport (a station included) and
never falls back to another airline's station; with no airline given, a hub or focus city there comes first, else a
station, so the optimiser finds the airline from a station as from a base. `schedule.nextFlightNumbers` gives a station
the next free pair in the airline's one station pool (`station_flight_no_from` to `station_flight_no_to`), above the
highest number the airline uses anywhere in the pool and any station's `last_flight_no`, with `pool` and `full` (no pair
left). Stations never feed big growth candidates or count as banked hubs, and Home's airline cards leave them out of
the bases. Cases: `cases/stations.json`.

## The command
For Claude and the scripts (how to get the input: `scripts/README.md`). `npm run build` writes it to `dist/`.

```bash
node lib/rules/dist/cli.js block       rules.json DEL BOM "A321 NEO LIGHT"
node lib/rules/dist/cli.js connections rules.json KUL
node lib/rules/dist/cli.js aircraft    rules.json            # every aircraft; or add a registration for one week
node lib/rules/dist/cli.js check-card  rules.json card.json [--fares ladder.json]     # or line.json: a line of cards
node lib/rules/dist/cli.js optimise    rules.json KUL KCH,PQC,PEN --type "A321 NEO LIGHT" --start 05:00-11:00 --hubs DEL
node lib/rules/dist/cli.js optimise-line rules.json --airline 1 --type A350-900 --hubs SFO,LGW,SEA,LAX,PVG,PKX \
     --routes SFO-LGW,LGW-SEA,SEA-PKX,LGW-LAX,SFO-PVG,PVG-LAX [--fixed SFO-LGW] [--step 15] [--seconds 60] [--work 1200] \
     [--range 14200] [--used 5001,5002]   # --range only to override aircraft_types.range_km
```

It answers in JSON; an error goes to standard error with a non-zero exit. A card is
`{"aircraft": "9M-AAB", "legs": [{"flight_no": 6101, "origin_code": "KUL", "dest_code": "KCH", "dep_local": "06:45",
"days_local": [1, 2, 3, 4, 5, 6, 7]}, ...]}` (or `dep_utc_min` and `days_utc`, as `plan_card_legs` stores them), each with its `service_code`; a leg
without `block_min` gets the estimate, and an aircraft not in the input needs `type` and `airline`. The card's cabin is
`config_id` (as `plan_cards` stores it, or a layout's code such as `"321-LP"`); the answer's `cabin` is the suggestion.
With `--fares`, `fare_ladder()`'s answer for the card's airline (`select public.fare_ladder(<id>);`, or the airline
briefing's `fare_ladder`, or its whole JSON), the answer's `fares` is each route's fare level (since 21 Oct), once per
direction the card flies it (since 26 Oct).
The optimiser's
start window and step default to 05:00 to 11:00 local and 5 minutes.

**`optimise-line`** (since 28 Oct) answers with the line (`best`: `routes`, `start_hub`, each leg with its `line_day`,
`flight_no`, `service_code`, `dep_utc_min` and `dep_local`, `arr_local`, `block_min`, the ground after it and whether it
is a maintenance stop, the banks at each end; `days`, where each line day starts and ends; `block_hours_day`;
`maintenance` with the spacing; `connections` and `connections_within_target`; `score`; `flight_numbers`, the pool
used; and `cards`, the 7 aircraft cards as `check-card` takes them, each with its `line_day_offset`), the settings it
used (`turn_min`, `connection_target_h`, `maintenance_max_gap_h`, `range_km`), `search` (`finished`, `work`,
`lines_evaluated`, `feasible`, and `note`: "best found with 906 lines evaluated, search not finished") and `rejected`,
why lines were dropped. `--seconds` is the run-time cap (60 by default, the one clock the command reads; 0 for none),
`--work` a cap on chains and lines evaluated instead (the same answer on every machine; the tests use it), `--step` the
minutes between the candidate times on each hub's bank ladder (15), `--range` the type's reach in km when the input
doesn't carry `range_km` or to override it (`rules_input()` carries `aircraft_types.range_km` since 28 Oct; without
either the command refuses, naming it), `--fixed` routes
that must be on the line, `--used` flight numbers already taken by plan cards. Save `best.cards` as
`{"line": {...}, "cards": [...]}` and `check-card` checks the line.
**`check-card` on a line file** (a document with `cards`, up to 7, each a card as above, and optionally `line` with the
`airline` and `type` the cards share) answers with each card's check (`card_checks`) and the line as a whole
(`flights`, `routes`, `missing_days`, `complete`, `ok`, `problems`); a document with `legs` is one card, as today.

## The tests
- **Cases** (`cases/*.json`), run by Vitest in `npm test`: plain JSON, so pull request 3's database tests can answer the
  same questions. `_base.json` is a small made-up world; each file is one part's cases, each with its input (laid over
  the base: `settings` and `world_rules` merge key by key, lists are replaced), a question (`ask`) and the answer. An
  answer names only what it checks; numbers match to within 1e-9; `{"error": "..."}` expects a refusal. The questions
  are listed in `test/ask.ts`.
- **`tests/fixtures/optimiser_kul_2026-10-10.json`**: the optimiser on the test sample's legs at KUL, whose answer is
  plan.py's, saved before plan.py was retired (build pull request 4). Since 27 Oct the score counts the connections
  within 4 hours first; the same plan still wins, and the answer adds its 43 connections within 4 hours (of 70). A case in the same format, kept with the dated
  samples because it is game data (decision #9); the Vitest runner lists it in `test/cases.test.ts` and lays it over
  `_base.json` like the rest. `tests/optimiser_saved_answer_test.py` runs the built command on it and must find that
  answer.
- **`tests/fixtures/line_a350_2026-10-12.json`** (since 28 Oct): the line optimiser on the Pan Am A350-900 sample of the
  Scheduling chat's hand-built line (the 12 Oct sample's 140 legs at SFO, LGW, SEA, PKX, LAX and PVG, six routes, the
  A350-900 with its reach), with a work budget so the answer is the same everywhere, its 7 cards through the line check,
  one card alone, and a route beyond reach refused; the Vitest runner lists it with the KUL case, and
  `tests/line_saved_answer_test.py` runs the built command on it. `cases/lineOptimiser.json` has the mechanics on the
  base world, and `cases/maintenance.json` and `cases/tails.json` the spacing (the 78-hour card).
- **`test/library.test.ts`**: the builder's checks, settings and world rules, a plan card, every command, and the
  website's connection test (below) against the library's own.
- **On last night's copy** (the rehearsal): `tests/rules_library_test.py` compares the library with the old planner's
  Tails, Hubs and Check screens (`tests/README.md`).

Run them: `npm run typecheck`, `npm run lint`, `npm test`, then `npm run build`, `python3 tests/optimiser_saved_answer_test.py` and
`python3 tests/line_saved_answer_test.py`.

## The website's file
The website's trip search uses the library's connection test, from one browser file: `npm run build` (`build:rules`)
bundles `src/browser.ts` into `web/assets/rules.js` (`vite.browser.config.ts`; not committed, Cloudflare builds it), which
the website loads before `site.js` as `window.EqRules`. It holds only what the trip search needs:
`EqRules.connections.limitsFrom(mct_min, connection_max_wait_h)` (the same limits `connectionLimits()` gives, from the two
figures `site_public()` gives the website: each airport's `content.mct`, 90 minutes where it has none, and
`content.connection_max_wait_h`) and `isConnection(gap, limits)`.

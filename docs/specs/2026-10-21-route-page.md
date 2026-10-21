# Build spec: the route page (21 Oct 2026)

**Why:** Gitesh, 20 Oct: load monitoring is too simple and the screens aren't fun to use. This is the last step of the
four (`docs/specs/2026-10-20-today-performance-systems.md`; competition analysis came first, Gitesh 21 Oct). A route
gets one page that tells its story since launch, so a fare move, a new frequency or a rival can be judged by what
happened after it.

**Outcome when done:**
- `/planner/performance/<code>/<route>` (for example `/planner/performance/PA/JFK-ORD`) opens **the route page**.
- Routes' route detail, Performance's route profit table, Today's needs attention and Competition's threats link to it.
- One database call, `route_story()`, answers it; the Scheduling chat can read it too.
- The daily history keeps loads and fares by cabin and the hours flown, so the story survives the month's archiving.

## 1. The daily history by cabin (`route_days`)
New migration (adds columns and `CREATE OR REPLACE` only; nothing dropped or renamed):
- **New columns**, each described:
  - `eco_pax`, `eco_seats`, `bus_pax`, `bus_seats` (integers; seats only from flights whose loads were captured, as
    `seats` is now);
  - `bus_fare_avg` (average business fare, AS$, weighted by business passengers, as `eco_fare_avg`);
  - `block_min` (the flights' scheduled block, minutes: `arr_at − dep_at` summed over the flights that have both).
  - First class: add `fst_pax`, `fst_seats`, `fst_fare_avg` only if `game_flights` has any first-class seats on the
    copy; otherwise leave first out and say so in the pull request.
- **The writer** (the function that recomputes `route_days` for the snapshot's day and the two before; find it from
  `private.take_snapshot()`) fills them, with the same matching as today.
- **Filled back** in the same migration for every day `game_flights` still holds (since 6 Oct), as one statement per
  table, not a loop of calls; days older than `game_flights` keep nulls. Say in the pull request how long it took on the
  copy.
- Business history matters beyond this page: `fig_fare_ladder()` reads the economy fare from `route_days` once flights
  are archived; leave it as it is, but note in the pull request whether the business index can now read
  `bus_fare_avg` the same way (one line, not changed in this build).

## 2. The figure: `route_story()`
`private.fig_route_story(p_route_id bigint, p_as_of timestamptz)` and the staff function
`public.route_story(p_route_id bigint, p_as_of timestamptz default now())`, read with GET, `SECURITY DEFINER`, empty
search path, refused to anyone who isn't staff, as the other figures are. Descriptions, grants and a database test.

A route is its airline's hub and destination; the story counts **both directions** together, and gives each direction
where it says so.

**The answer:**
1. **The route:** id, airline (id, code, name), hub, dest, city, stars, distance, market, the cabin it calls for
   (its own choice, else its market's, as Routes' header since 21 Oct), and **launched**: the earliest rotation's
   launch day, as `fig_fare_ladder()` and route profit find a route's age, else its first day in `route_days`.
2. **Now:** weekly departures each way from the live schedule; the aircraft types flying it; the fare ladder's rows
   for the route from `fig_fare_ladder()` (each cabin's level, this Saturday's move and its reason, whether it's on the
   fare plan and applied).
3. **Days** (from launch, or the last 90 days if longer, to the latest captured day), one row per UTC day from
   `route_days`: flights, passengers, seats, load %, economy and business passengers, seats and load %, average
   economy and business fares, revenue, costs, profit, block hours, and profit per aircraft hour (profit ÷ block hours).
   A day with no flights is left out, not zero.
4. **Weeks:** the same figures in 7-day blocks ending on the latest captured day, newest first, at most 13.
5. **Events**, newest first, each with its day, kind and words:
   - `launched`;
   - `frequency added`, `frequency removed`, `aircraft changed`, `retimed`: from `change_log` on the schedule's tables
     for this route's legs and rotations (group a save's rows by `txid`, one event per save);
   - `fare`: each fare plan row for the route (`fare_plan`, the ladder's rows with `level_pct` and fare tests), with
     the cabin, the level or change, the move and whether it was dropped;
   - `cabin`: the route's `cabin_choice` changed (`change_log` on `routes`);
   - `rival`: a rival starting or growing on the pair between two scans, by competition analysis's rule (as
     `private.competition_threats()` applies it: started, or added at least `competition_threat_min_weekly` a week),
     for every pair of consecutive finished scans since launch that still have their schedules. Read the flights with
     `private.scan_pair_flights()` (passenger flights only, `private.scan_passenger()`); don't copy its SQL.
6. **Rivals on the pair:** from the latest finished scan, every rival flying the pair either way (passenger flights
   only, through `private.scan_pair_flights()`), with weekly departures and the change against the week-before scan
   (chosen as `competition()` chooses it); our weekly departures and our share; and our share at each finished scan
   since launch, for a small chart. Our own departures at a scan are our airlines' flights in that scan, as
   `competition()`'s `me_then` reads them.
7. `as_of`, the latest captured day, and the scans used with their dates.

**Speed:** the role's statement limit applies. Measure the call on the copy for the busiest route of each airline and
give the times in the pull request; if it needs more than 3 seconds, give the staff function its own limit as
`capture_fare_actions()` does, and say why.

**The test** (`database/tests/route_story_test.sql`, on a world made inside the test): a route launched with days in
both directions; the cabin columns and block hours summed; a fare row, a frequency added and a cabin change in the
events; a rival starting between two scans; the share; a route with no flights yet; refused when not staff.

## 3. The planner
**The route page** at `/performance/<code>/<route>`, inside Performance (the airline's page stays at
`/performance/<code>`). Phone first, and the rules for every screen (`docs/specs/2026-10-20-today-performance-systems.md`).
Each figure in `src/screens/performance/` with its logic in `model.ts` and unit tests beside it. Its parts, top to
bottom:
1. **Header:** route and city, stars, airline, distance, market, the cabin, launched (date and "N days"), departures a
   week each way, the types, and each cabin's fare level with this Saturday's move. Links: "‹ <airline>" back to the
   airline's page and "Schedule in Routes" to `/routes/<code>/<route>`.
2. **The last 7 days against the 7 before:** load %, passengers, profit, profit per aircraft hour, economy and business
   fares, each with its arrow.
3. **Since launch** (one chart, drawn like the other charts in `Charts.tsx`, with their tip): daily load % for economy
   and business as two lines; the fare level as a step line on its own scale; each event as a marker on the day axis,
   its words in the tip. Under 14 days of data, say so instead of drawing it.
4. **Profit per aircraft hour by week:** bars, with the airline's average across its routes for the same weeks as a
   line if `route_profit()` gives it cheaply; otherwise without the line.
5. **Events:** the list, newest first, 10 shown with "show all".
6. **Rivals on the pair:** the table and our share at each scan as a small line; "no rival flies this pair" when none.
7. **Connections:** how many onward city pairs this route's flights connect to at each end, and the top 10 with how
   many times a week, from the planning library's connections (`lib/rules/src/connections.ts`,
   `connectionsAtBothEnds`, the same rule the plan card uses: the airport's minimum connection time up to
   `connection_max_wait_h`, across all our airlines). Worked out in the app from the schedule the planner already reads.

**Links to it:**
- Routes' route detail: "How it's doing ›" in the header when the route is flown.
- Performance's route profit table: each route's name.
- Today's needs attention: items that link to `/performance/<code>/<route>` now open the route page (check each still
  makes sense there).
- Competition's threats, when we fly the pair.
- The route profit table's filtered view (what the address did before) stays reachable by its search box.

## 4. The Scheduling chat's call
- `route_story()` in the map's "Which call answers which question" (`docs/architecture.md`): "how has this route done
  since launch, and what changed on it", with a tested example.

## Checks
- `bash tests/run_all.sh` green; the rehearsal green with the new database test and the migration on the copy.
- Screenshots of the route page at both widths, for a busy legacy route and a Ryanair route.
- The pull request gives, from the copy: the call's time for each airline's busiest route; one route's story in
  numbers (launch, last 7 days, events); and the backfill's row count.

## Docs
- `docs/planner-guide.md`: the route page and the links to it.
- `docs/architecture.md`: the figure, the Planner row, the guide's row.
- `docs/playbook.md`: the Saturday review opens the route page for a route it's unsure about.
- `tests/README.md` for the new tests. `docs/data.md`, `database/current/functions.sql` and the types are regenerated by
  the rehearsal as usual.

## Not in this build
- Changing what the fare ladder reads.
- Passenger connection data (the game's pages we capture don't give transfers); connections here are the schedule's.

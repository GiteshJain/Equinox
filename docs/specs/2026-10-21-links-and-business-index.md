# Build spec: flights linked to their routes and aircraft, and the business fare index (21 Oct 2026)

**Why:** Gitesh, 21 Oct ("let's build the three loose ends"). Two loose ends the route page build turned up.
1. Most captured flights have no route or aircraft attached. On live on 21 Oct, 1,404 of 6,592 `game_flights` rows
   have `route_id` and `aircraft_id`, and 1,151 of 5,138 `route_days` rows have `route_id`. The cause:
   `private.fill_flight_links()` ran once, at the 10 Oct data load (`20261010120000_planner_data_load.sql`), and nothing
   has called it since. Every row it could fill matches today: 5,187 by route (by airports, either way round) and
   5,187 by aircraft (by registration); one money-only row has no airports.
   The figures match by airports, so nothing is wrong on screen today; the links make them sturdier and let a route's
   history follow it when a route is renamed or its airports overlap.
2. The fare ladder's business index reads only `game_flights`, so it is lost once a month's flights are archived;
   economy falls back on `route_days.eco_fare_avg`. Since 22 Oct `route_days` keeps `bus_fare_avg` too.

**Outcome when done:** every captured flight carries its route and aircraft from the evening it's captured, the daily
history carries its route, and the business fare index survives archiving as economy's does.

## 1. The links (new migration, `CREATE OR REPLACE` and data only)
- **Called every capture:** `private.fill_flight_links(world)` runs after the capture stores a loads or statement page
  (find the right place in `private.capture_page()` / `capture_refresh()`; once per page is enough), and before
  `private.history_flows()` in the daily snapshot, so `route_days.route_id` is set when the day is written. It must stay
  cheap: it touches only rows still without a link (check its plan on the copy; add an index only if the copy shows it's
  needed, and say so).
- **The matching stays as it is** (the schedule's leg with that number and direction, else the route by its airports
  forward, else backward; the aircraft by registration), with one fix: prefer a route that isn't removed when the
  airports match more than one.
- **Filled back now:** `game_flights` (route and aircraft) for every row, then `route_days.route_id` for rows without
  one, from the airline's route by its airports, either way round (not removed first). Raise a notice with the counts.
- **Test** (`database/tests/`): a flight captured through `capture_page()` (or the function it calls) gets its route
  and aircraft; a removed route loses to a live one; the snapshot's `route_days` row has its route.

## 2. The business fare index from the daily history
- **In `private.fig_fare_ladder()`** (`CREATE OR REPLACE`): the `hd` step reads business as it reads economy, from
  `route_days.bus_fare_avg` (rows with `bus_pax > 0`), so a business baseline day older than `game_flights` still has
  a fare. Nothing else in the ladder changes.
- **Test:** the fare ladder test gets a business baseline that only `route_days` holds.
- In the pull request, give from the copy: the business rows whose baseline or index changed (expected none today,
  since `game_flights` still holds every day since 6 Oct).

## Checks
- `bash tests/run_all.sh` green; the rehearsal green with the migration and the tests on the copy.
- The pull request gives the backfill's counts and the time `fill_flight_links()` takes per capture page on the copy.

## Docs
- `docs/data.md` regenerated; `docs/architecture.md` where it says when the links are filled; the manual only if a
  rule's wording names this (none expected).

## Not in this build
- Changing how the figures match flights (they keep matching by airports; the links are extra).

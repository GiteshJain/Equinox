# Spec: Fare results, what the fare ladder has done to each route

Asked for by Gitesh, 3 Nov 2026 (Scheduling chat): "a tab which shows current level for routes where we have changed
prices and how the flight profits/loads have changed". One pull request. Read `CLAUDE.md`, the map
(`docs/architecture.md`), manual §5 (the fare ladder) and the fare-ladder specs (`docs/specs/2026-10-21-fare-ladder.md`,
`2026-10-26-fare-ladder-per-direction.md`) first.

## Why
The fare ladder moves hundreds of fares a week (773 directions and cabins on 26 Oct, 306 planned on 2 Nov), and nothing
shows what that did. Today's pieces each show a slice:
- Performance → **Fare changes**: the latest 12 economy fare changes, load before and after, no money;
- Performance → **Fare plan**: this week's planned changes and whether the captures see them;
- each **route page**: loads with the fare level drawn over them, one route at a time.

Nobody can see, per airline, which routes have been repriced, where they stand now and whether flights earn more for
it. The weekly report is meant to cover "fare-plan results" (manual §7) but its scripts don't pull any.

What the figures already say (worked out by hand on 3 Nov, so the build has a check): directions whose economy fare went
up on 26 Oct and were seen in the game from 30–31 Oct, 7 days before against the days since:

| Airline | Profit a flight before → since | Economy load before → since |
|---|---|---|
| Pan Am | 29,441 → 32,787 AS$ (+11%) | 100.0% → 99.7% |
| Kingfisher | 23,615 → 25,372 (+7%) | 100.0% → 99.7% |
| Ryanair | 13,262 → 13,273 (0%) | 100.0% → 99.8% |
| Virgin | 17,173 → 18,293 (+7%) | 100.0% → 99.3% |
| China Eastern | 20,590 → 22,750 (+10%) | 100.0% → 99.8% |
| Malaysia | 23,815 → 25,648 (+8%) | 100.0% → 100.0% |

(Only 3–4 days "since"; the query is in the PR's notes so the function can be checked against it.)

## 1. The figure: `fare_results(p_airline_id bigint, p_as_of timestamptz default now())`
A new figure in the usual pattern (`private.fig_fare_results`, a `public` wrapper, the figures' cache and limits like
`fare_plan_status()`), described, with the same grants as `fare_plan_status()`. It reads `fare_plan` (as
`fare_plan_status()` does, for each change's `applied` and `seen_on`), `route_days` and `routes`; nothing new is stored.

**A repriced direction** is a route and direction (out from the route's hub, back to it) of that airline with at least
one `fare_plan` row that the captures have seen (`applied`, a `seen_on`), any cabin, any move (up, down, jump, set
back). Rows from before 26 Oct with no direction count for both directions.

For each repriced direction, one row:
- `route_id`, `hub`, `dest`, `direction`, `from`, `to`, `km`;
- **levels now**: economy and business level (% of the default price) as `fare_ladder()` gives them today, and whether
  either is at the cap or the 60% floor;
- **moves**: how many seen changes, the first `seen_on` (**first_seen**), the latest change's date, move and level, and
  any change planned but not yet seen (with its date);
- **before**: the 7 UTC days before `first_seen` from `route_days` for that direction (origin = `from`): flights, economy
  fare (average), economy load, business load, revenue a flight, profit a flight;
- **now**: the latest 7 complete UTC days (as `airline_days.complete` marks them), the same figures;
- **change**: now against before for each figure (points for loads, % for fares and money), and **profit a week** =
  (profit a flight now − before) × flights a week now;
- **flags** (each a word on the row): `load_fell` (economy load now under 95% while before was 95% or more),
  `frequency_changed` (flights a week now differ from before by 2 or more: the money per flight is then not like for
  like), `too_soon` (fewer than 3 days since `first_seen`: figures shown, change greyed), `at_cap`.

**A baseline**, so fuel, fees and type changes don't pass for fare effects: the same figures for the airline's
directions with **no** seen change, before = the 7 days before the airline's earliest `first_seen` in the list, now =
the latest 7 days. Its profit a flight change is shown beside the repriced total ("repriced +9%, the rest +1%").

**Totals** for the airline: repriced directions, at cap, load fell, profit a flight before → now for all repriced
directions together (weighted by flights), the baseline's, and profit a week gained (sum of the rows').

Order the rows by profit a week gained, largest first. Keep to the figures' time limit; `route_days` is small.

## 2. Planner: a **Fare results** board on each airline's Performance page
Placed directly under the fare ladder (`#fare-results`), closed on arrival like the other boards, in the page's style.
- **Its title line is the answer**: "Fares up on 214 directions: profit a flight +9% (the rest +1%), about +1.4M a
  week". With nothing seen yet: "No fare changes seen in the game yet".
- **The table** (search box like Route profit's; "show as table" isn't needed: it is a table):
  Route (the route name opens the route page, the direction beside it as on the Fare plan table) · Economy level · Business
  level · Moves (count, latest date) · Economy fare before → now · Economy load before → now · Profit a flight before →
  now (with %) · Profit a week gained · flags as small pills (`load fell` amber, `frequency changed` and `too soon` dim,
  `at cap` plain).
- **A filter row**: All · Load fell · At cap · Frequency changed.
- **A chart above the table** (the chart kit in `src/ui/charts`, `ChartOrTable` with the table one tap away is fine
  if it fits better): one dot per repriced direction, economy level now across, profit a flight change up, the
  baseline's change as a line. A dot opens its route page.
- The **group page** gets one line per airline under its fare-ladder links: the title line's numbers, linking to the
  airline's `#fare-results`.
- Logic in `model.ts` beside the screen, with unit tests (titles, ordering, the filter, the flags' words).

## 3. The weekly report
`scripts/report/pull.py` pulls `fare_results()` per airline; `build.py` adds a **Fare results** section per airline: the
title line, the top 5 directions by profit a week gained, every direction flagged `load fell`, and the at-cap count. Keep it
to half a page per airline. This makes manual §7's "fare-plan results" real.

## 4. Docs and tests
- Manual §5, at the end of the fare ladder: one sentence that Performance's Fare results board and the weekly report
  show each repriced direction's level now and its loads and profit a flight before and after, against the rest of the
  airline. §7's weekly report line already names "fare-plan results": point it at the board.
- `docs/architecture.md`: the new figure and board. `database/current/functions.sql` updated.
- `database/tests/`: a fixture with two routes, one repriced (before/after days) and one not, checking the row, the
  flags, the baseline and the totals. Planner unit tests as above. The briefing and report tests updated if their
  saved answers move.
- Run `bash tests/run_all.sh`; the pull request says which saved answers moved and why.

## Out of scope
Changing the ladder's rules (step size, hold, cap): the figures this board shows are what the Saturday review will use to
decide that, separately.

# Build spec: the captured figures in the database (#18 build, pull request 3) — 12 Oct 2026

**Why:** step 3 of the build order (`docs/design/2026-10-12-planner-app.md` §13), decision #19. The figures worked out
from what the capture recorded get their one home, the database: the cash forecast that decides every order (manual
§3), the Review cards, profit by day, route and aircraft, the growth signals, hub progress, the capture's status and
fare changes. The new planner, the report scripts and Claude in every chat will then read the same rows. The game is
paused and the old planner frozen (manual §1): **nothing in `web/planner/` or `web/assets/` changes.**

**Outcome when done:**
- Database functions (§1) give each figure the old planner shows today, for any moment (`p_as_of`, now by default).
- On last night's copy, at the same frozen moment, every figure equals the old planner's on screen. Any difference is
  a finding, reported with the figures, never smoothed over.
- `export_for_report()` gains kind `figures` for the scripts (pull request 4 moves them on).
- Nothing changes for any user: no screen, no script, the website untouched.

## What to build
The design is the specification: §2 (principles), §8 (the functions), §10 (checks). Where the design, the manual and
this spec disagree, stop and say so. **The manual (§3) is the rulebook** for the cash forecast and ordering. **The old
planner's code is the reference for how each figure is worked out:** port each one faithfully, including its windows,
roundings and edge cases, and say in a comment which old function each part follows.

### 1. The functions (one migration)
All in `public`, `stable`, staff only (`private.caller_is_staff()`), running as owner with an empty search path, each
with a description. Each takes `p_as_of timestamptz default now()` and uses only rows that existed by then (captures
up to that moment, payments scheduled after it), so a test can freeze time. Money in millions of AS$, as the old
planner shows it. Airlines come from `airlines` (ours, active, in `position` order), never a list of names, and each
airline's home airport (where the game's events page shows times) from its main base in `airline_bases`.

| Function | What it gives | The old code to follow |
|---|---|---|
| `cash_forecast(p_airline_id, p_orders jsonb default '[]', p_as_of)` | The latest captured cash and when; flight profit a day (profit a flight from `game_ops_recent` × planned flights a day); every scheduled payment for 14 days from the captured events, repeated weekly beyond what the game lists; the balance at each payment and each day; the lowest point and the payment that makes it; for each type the airline may buy, the first day it's safe to order, keeping `order_cushion` in hand with its price (cabin included) and its own weekly lease from 7 days after it's ordered; and, for `p_orders` (a list of types, with a count each), whether ordering them all today stays safe and the lowest point after. A type's lease is the highest leasing payment seen for it in the captured events, else `lease_estimate_pct` of its price. When there's no capture, or fewer than 5 flights in the bank statement, it says what's missing instead of a figure | `cashForecast`, `flightsPerDay`, `leaseM`, `orderNow`, `fcNext`, `forecastBoard`, `BUY_TYPES` |
| `airline_cards(p_world_id default null, p_as_of)` | Review's card for each airline: profit a day over the last 7 days, per aircraft, return on fleet, pays back in, funds a new aircraft every, fleet, flights a day, average load, and the next order (from `cash_forecast`); and **the group today**: per airline cash, flight profit a day, leases and week-end closing a day, net, and aircraft on the ground with their lease | `finStats`, `renderFinance` (the cards), `groupOverviewHtml`, `fcNext` |
| `airline_profit(p_airline_id, p_as_of)` | Profit for each day between captures: the change in cash plus that period's order payments (losses stay in profit), with the aircraft, flights and load that day | `finSeries`, `finStats`, `capexIn`, `dayOps` |
| `route_profit(p_airline_id, p_days int default 7, p_as_of)` | Each route over 1, 3 or 7 days: flights, profit, income, margin, profit a flight and a week, average economy, business and cargo load, average economy fare, share sold out, and the mark (add a flight, raise fares, hold, fix, losing), using the `growth_*` settings | `routeProfit` (including how it matches each flight's money to its loads) |
| `aircraft_profit(p_airline_id, p_days int default 7, p_as_of)` | Each aircraft's flight profit a day, its lease a day, and the net | `routeProfit`'s per-aircraft part (`R.tails`) |
| `growth_signals(p_world_id default null, p_as_of)` | Ready for another flight, raise fares, fix or reduce, and aircraft losing money after their lease, across our airlines (from `route_profit` and `aircraft_profit`); and the load patterns (add, watch, cut) from the loads, using the `pattern_*` settings | `capSignalsHtml`, `growthBoard`'s "Ready for another flight", `patterns` |
| `hub_progress(p_world_id default null, p_as_of)` | Each airline's main hub: departures a week flying, plus those on plan cards not yet filed, against `hub_first_departures`; Ryanair's exemption from `hub_first_exempt`; and for each other base, whether it's contested from the latest world scan (`contested_rival_weekly`, `contested_rival_daily`) | `hubProgressHtml`; manual §3, *Hubs first* |
| `capture_status(p_world_id default null, p_as_of)` | For each airline, today's and yesterday's capture: each page kind, when (UTC), and how many flights the loads page held | `captureBoard` |
| `fare_changes(p_airline_id, p_as_of)` | Economy fare changes seen in the captures, by route and date, with the load the day before and after | `routeProfit`'s fare changes (`R.changes`), shown under "Fare changes" |

- **Same windows as the old planner** (9 days of loads, 8 of flight money, events from 7 days back to 16 ahead), so
  the figures match. If a window looks wrong, say so in the pull request rather than changing it.
- **Times:** the game's events page shows times at the airline's home airport, in standard time all year (manual
  §9). Convert exactly as the old planner does.
- **Speed:** each function answers in under 500 ms on last night's copy (best of 3); the test prints each time.
- **Not in this pull request:** "Next move", "Order queues" and "Hub readiness" on the Check screen. Pull request 9
  places them by #19's test (planning rule or captured figure).

### 2. `export_for_report()`: kind `figures`
`export_for_report(secret, 'figures', p_arg)` where `p_arg` is a JSON object `{"as_of": ..., "world": ...}` (both
optional), answering every §1 function for every airline in one document. The ingest secret as for the other kinds;
every other kind unchanged. Build on `export_for_report()` as live has it now (migration
`20261012180000_rules_input.sql`).

### 3. Tests
- **Database tests** (`database/tests/captured_figures_test.sql`), hand-made, in a transaction rolled back:
  - an airline with no capture, and one with fewer than 5 flights (says what's missing);
  - a payment exactly at the lowest point;
  - an order of a type never leased (10% of its price) and of one already leased (the highest payment seen);
  - two orders tested together, each with its own lease;
  - the weekly repeat of a payment beyond what the game lists;
  - an order payment between two captures (added back to profit), a loss (stays in profit);
  - a route with no loads matched;
  - `p_as_of` before a capture ignores it;
  - signed out and an account that isn't staff are refused; `export_for_report('figures')` refuses a wrong secret.
- **Side by side on last night's copy** (the rehearsal), a new test `tests/captured_figures_test.py`:
  1. pick the moment: the copy's latest capture plus one hour;
  2. open the old planner on the copy at that frozen moment (the browser clock fixed, as `tests/harness.py` does for
     the sample), signed in as the test staff user, as `real_saves_test.py` opens it;
  3. call each §1 function as that staff user with `p_as_of` = the same moment;
  4. compare, for every airline:
     - Review: each card's figures, the group today, profit by day, "Cash, next 14 days" (every point, the lowest
       point, every type's safe date), route profit for 1, 3 and 7 days (every route and mark), aircraft, fare
       changes;
     - Check: every growth list, the load patterns, main hubs towards 750, and the capture board;
     - "Next order" on each card, and "can order now".

     Money to the old planner's rounding, counts exactly, dates exactly. Anything that differs fails, and the test
     prints the airline, the figure, both values and the old function it came from.
  5. print each function's time.
- The *Planner* check's saved answers (`tests/fixtures/planner_numbers.expected.json`) are unchanged: this pull request
  doesn't touch the old planner.

### 4. The rehearsal
`tests/captured_figures_test.py` runs in the rehearsal after the existing steps. The time limit stays 30 minutes; say
in the pull request how long the run took.

### 5. Docs, in the same pull request
- **The map** (`docs/architecture.md`): the captured figures and where each lives. Claude copies it into the project
  after the merge.
- **`scripts/README.md`:** kind `figures`, and that the weekly report moves onto it in pull request 4.
- **`tests/README.md`:** the new tests. **`docs/data.md`:** regenerated by the rehearsal.
- **The manual §3:** no rule changes. Under *When an airline can order*, one line saying the forecast is worked out
  by `cash_forecast()` in the database, with the old planner's Review screen showing the same figures until the switch.

## Proving it
- `bash tests/run_all.sh` passes.
- The rehearsal passes: `captured_figures_test.sql` ok; every comparison in `tests/captured_figures_test.py` ok, for
  every airline; each function's time printed and under 500 ms.
- **A deliberate failure** is seen to fail, then removed: the order's own lease counted from 14 days instead of 7
  (both the database test and the side by side must go red).

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` and its rule files. Read
  `tests/rules_library_test.py`, `tests/planner_next_test.py`, `tests/real_saves_test.py` and `database/rehearse.sh`
  before writing the new test.
- The old planner is one large file: search for the functions named above rather than reading it whole. Its screen
  code starts at `// ---- Gander planner: UI ----`; the capture board's reads are in `loadCapture`.
- **Never connect to the live database or use the Supabase connector tools.** Test by pushing and reading the *checks*
  and *Database rehearsal* results. Docker is available here.
- **Don't change `web/planner/`, `web/assets/` or anything in `scripts/`** (pull request 4 moves the scripts).
- Work on branch `captured-figures`, open the pull request with the REST API (GraphQL is blocked), and don't merge.

## Done when
- Every proof above is `ok`, and the deliberate failure was seen to fail, then removed.
- The pull request says: what changed; the rehearsal's run time; each function's time; any finding, with the figures;
  the steps after "merge" in order (Claude applies the migration to live, or gives Gitesh the file if it's cancelled
  twice, then sets the migration record); how to roll back (revert, then drop the new functions and restore
  `export_for_report()`); anything outside the repository that needs a follow-up.

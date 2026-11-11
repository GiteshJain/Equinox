# Spec: the planner's figures stored after every capture

To-do 223 (decided by Gitesh, 11 Nov, Building chat: brief `docs/briefs/2026-11-11-instant-planner.md`, **option B**;
manual *Decided, not yet built*). Read `CLAUDE.md`, the map (`docs/architecture.md`, then `docs/map/planner.md`,
`docs/map/captured-figures.md` and `docs/map/database.md`), manual §1 and §7, and the brief first.

## What it does, in one paragraph
After every capture (the unattended runs and Gitesh's press, with their world scan and market pages), the database
works out every figure the planner shows, once, and stores the answers. While a capture is running, and until its new
answers are stored and loaded, the planner shows one landing page instead of its screens. Opening the planner shows the
same landing page while the browser loads every stored answer and the tables the screens read. After that, moving
between screens asks the database to work nothing out: each screen reads what is already loaded. A save that changes
figures still updates its board at once, as today, and the stored answers catch up within a few minutes. The landing
page never stays for good: when a capture stalls or the work fails, the planner opens on the last answers with a line
saying so.

## Measured on 11 Nov (the brief's figures, to compare against)
- Every figure the planner reads, all six airlines, one after another on a quiet database: **30.1 s, 5.4 MB of text**.
  Fare ladder 5.2 s, competition 8.3 s, fare results 0.9 s, cash forecast with profit, fare plan and fare changes 7.8 s,
  route and aircraft profit for 1, 3 and 7 days 4.5 s, the world-wide figures 3.3 s.
- A route's page (`route_story()`): about 2.9 s and 51,000 characters; 419 routes flown.
- A capture, first page to last: 1.9 to 3.3 minutes without the scan, about 20 minutes with the scan and market pages
  (`game_capture_raw`, 9 to 11 Nov). The scan's and market pages' own progress is in `game_scans` and `market_runs`.
- Supabase compresses its answers (site_public 193 KB sent as 38 KB).

## 1. The database (one migration, the first pull request)

### The stored answers
- **`planner_figures`** (new table; described; its own grants: staff read through `is_planner_user()`, nothing for
  `anon`, written only by the functions below): `world_id`, `kind` (the function's name), `key` (text: `''` for a
  world-wide figure, the airline id, `<airline id>:<days>` for route and aircraft profit, the route id for a route's
  page), `answer` (jsonb, exactly what the function gives), `as_of` (the moment it was worked out, passed to the
  function as `p_as_of`), `generation` (bigint), `worked_ms` (int). Primary key `(world_id, kind, key)`. Each refresh
  replaces rows in place; only the latest set is kept.
- **`planner_figures_state`** (new table, one row per world; described; staff read): `generation` (the set the planner
  should load), `ready_at` (when that set was finished), `sources` (jsonb: what the set was worked out from, below),
  `refreshing_since`, `routes_done`, `routes_total`, `last_error`, `last_error_at`.

### What is stored (the planner's reads today, each with the arguments the planner passes)
- **Each world:** `airline_cards`, `growth_signals`, `hub_progress`, `route_loads`, `fleet_checks`, `cash_log`,
  `shared_pairs_status`; and, with no world argument, `cabin_charges` and `market_service_checks`.
- **Each of our active airlines:** `airline_profit`, `cash_forecast` (no orders), `fare_changes`, `fare_plan_status`,
  `fare_ladder`, `fare_results`, `competition` (the planner's limit), `route_profit` and `aircraft_profit` for 1, 3
  and 7 days.
- **Each flown route** (a route with rotations, not removed): `route_story`, after the rest (below).
- **Not stored, read live as now:** `capture_status` and `system_status` (light, and they say whether a capture is
  running), `loads_by_day` (one day, on demand), `rules_input` (the planner tables; loaded once at opening, below), and
  anything a save asks for again (§2).

### When the work runs
- **`private.figures_capture_running(p_world, p_at)`**: true while a capture is running: a capture page arrived in
  the last `settings.figures_capture_quiet_min` minutes (5; `game_capture_raw.captured_at`), or a world scan of the
  world started within the hour is neither done nor stopped (`game_scans`), or a market run started within the hour is
  open (`market_runs`). It answers what is running ("capture", "world scan", "market pages") and since when.
- **`private.figures_sources(p_world)`**: what the stored set depends on: the latest capture page's time, the latest
  finished scan's id, the latest finished market run's id, and the latest `change_log` id on the planner tables.
- **`private.figures_refresh(p_world, p_at)`**, run every minute by `pg_cron` (job `equinox-figures`, scheduled by
  `private.schedule_jobs()` like the others; as postgres; its own statement limit of 5 minutes):
  1. When a capture is running: nothing (the state says so through the status call).
  2. Otherwise, when the capture, scan or market stamps differ from the stored set's, or the planner-table stamp differs
     and the last planner save is more than a minute old: it works out the whole list above (not the route pages) at
     one moment, each figure on its own, into a new generation. A figure that fails keeps its previous answer and
     writes `last_error`; the rest go on. Then `generation`, `ready_at` and `sources` move on together, so the planner
     never sees half a set. One `job_runs` row (job `figures`, the reason, the time taken, any failure).
  3. Then, while the run has time left (`settings.figures_route_budget_s`, 40), route pages whose stored answer is
     older than the latest capture, scan or market stamps, oldest first; the rest in the next minutes. A save alone
     never redoes route pages.
- The refresh never runs inside a capture's own calls, so their 30-second limits are untouched.

### What the planner asks
- **`planner_figures_status(p_world)`** (staff; GET; light, never works a figure out): the stored `generation` and
  `ready_at`; whether a capture is running, what, and since when; whether a refresh is due or running; `routes_done`
  of `routes_total`; `last_error`; and the capture's progress the landing page shows (airlines captured this run, the
  scan's airlines read, the market pages read of expected).
- The stored answers are read straight from `planner_figures` by the planner (§2).

### Room
Only the latest set is kept: about 5.4 MB of figures and about 21 MB of route pages before the database compresses
them. Updating rows in place leaves dead rows until autovacuum reuses them, so the table can hold up to about twice
that. `system_status()` adds the table's size to the usage figures (amber from 50 MB), and the Systems board shows it.

## 2. The planner (the second pull request)

### The landing page
- One full-window page in the planner's look: the brand, one line saying what is happening, and its progress:
  - "Capture running · Ryanair (3 of 6)", "World scan · 120 of 163 airlines", "Market pages · 340 of 686";
  - "Working out the figures…" while the refresh runs;
  - "Loading… 18 of 24" while the browser reads the stored set and the tables.

  Draw it so the glass look (to-do 225) can restyle it later without touching its logic: its words and decisions in a
  `model.ts` with unit tests, its look in one small component.
- **When it shows:**
  - from the first sign-in of a session until the stored set and the opening tables are loaded;
  - whenever the status says a capture is running;
  - after a capture, until the new generation is stored and loaded.

  A refresh caused by a save alone doesn't show it.
- **The status is asked every 30 s while the planner is open, never again while the last ask is unanswered.**
- **It never stays for good.** The planner opens on the last stored answers, with a line at the top of every screen
  ("Figures from the 09:30 UTC capture: the new ones aren't ready because …"), when:
  - a capture has been running for more than `settings.figures_landing_max_min` (30) minutes;
  - no new set is stored 10 minutes after a capture ends;
  - the status fails three times in a row.

  With no stored set at all (the first time after the build), it reads live, as today.
- **No "open anyway" link** (Gitesh, 11 Nov: "No"): during a capture the landing page has no way past it except the
  time limits above.

### Reading
- On opening (and on each new generation) the planner reads every stored row except the route pages in one paged read
  of `planner_figures`. It then puts each answer into the query cache under the keys the screens already use
  (`["figures", <kind>, …]`), with no expiry until the next generation. It also reads the tables the screens use at
  opening (routes, rotations, flight legs, aircraft, plan cards and their legs, plan lines, airports, world airports,
  to-dos, dismissals, interline agreements, settings) and `rules_input(world, 'flown')`, through the same queue, at most
  four at a time.
- The screens' own reads stay as they are. A screen asking for a figure that the stored set doesn't have (an
  airline added since, a new route) reads it live.
- **A route's page:** read from `planner_figures` (kind `route_story`, its id) when it's stored for the current sources,
  otherwise live, as today.
- **One key per figure:** growth signals are read once (Home's, Performance's and Routes' load patterns share it), and
  so are route loads and the airlines' cards. Systems' 14-night capture history keeps its own reads, which are light.
- **After a save:** the invalidations screens already make (the fare plan, cash entries, a route, a cabin charge) read
  those figures live, as today, and the live answer stands until the next generation. Table saves work as today.
- **The as-of line:** Home's header and the Performance pages say "Figures as of 15:02 IST" (the set's `as_of`). Where
  a stored figure names a time ("can order from 14:00"), the screen compares it with the clock.

## 3. What the checks should show
- **Database (the rehearsal, on the copy):**
  - after `private.figures_refresh()` at the copy's latest capture plus one hour, every stored answer equals the live
    function called with the same arguments and `as_of` (`database/tests/stored_figures_test.sql`);
  - a capture page inserted within the quiet window makes `figures_capture_running()` true and the refresh do nothing;
  - a failed figure keeps its previous answer and the generation still moves on;
  - the status call stays under 100 ms;
  - the table's grants: staff read, `anon` nothing.
- **The planner (unit):** the landing page's decisions: first opening, a capture running, a refresh pending, the
  30-minute and 10-minute limits, three failed status calls, a save-only refresh not showing it.
- **The planner on the copy** (`planner_next_test.py`):
  - the rehearsal runs the refresh on the copy first;
  - the planner opens through the landing page;
  - after it, opening every screen in turn makes no call to a stored figure's function (count `/rpc/` requests other
    than the status call);
  - every screen still opens at 1280 and 380 px with no errors.
  - Saves are unchanged (`planner_saves_test.py`).
- **Measured before and after,** in the second pull request: on the preview (look-only, live data), the first opening
  to the first screen ready, and five screen changes (Home → Today → Performance (an airline) → Competition (an
  airline) → Routes), each from click to ready. Target: every screen change under 1 s.

## 4. Documents (in the same pull requests)
- **The map:** `docs/map/planner.md` (a dated note: the landing page, the stored reads),
  `docs/map/captured-figures.md` (stored after each capture), `docs/map/database.md` (the two tables), and the map's
  What runs when (the `equinox-figures` job) and When something breaks ("the planner stays on its landing page").
- The planner guide (the landing page), `database/current/`, `docs/data.md` (regenerated), `tests/README.md`.
- The manual: the *Decided, not yet built* item moves into §1 (how the planner reads) and §7 (the job) when the second
  pull request merges, with rule-history logging it.

## 5. Built in two pull requests
1. **The database:** the tables, the refresh and its job, the status call, the tests. Once merged and applied, figures
   start being stored while the planner still reads live, so the stored answers can be compared with the live ones on
   real captures for a few days before anything reads them.
2. **The planner:** the landing page, reading the stored set, one key per figure, the as-of line, the measurements.

## 6. Gitesh's steps
None. On 11 Nov he said: "Start building and merging when done. Don't disturb and complete." So the Building chat merges
each pull request itself once every check is green and its review against this spec passes (never with a red check),
applies the database change to live, and reports at the end.

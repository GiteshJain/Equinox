# Build spec: the fare ladder (step 2), and the Hubs clean-up (21 Oct 2026)

**Why:** Gitesh chose option A of `docs/briefs/2026-10-21-fare-ladder.md` on 21 Oct. Manual §5, "The fare ladder,
every Saturday", is the rule; read it first. Almost every flight sells out at launch fares, and no fare has ever been
raised. Each 5% step that holds is worth about 5M a week.

**Outcome when done:**
- Every Saturday, the planner says, for each route and cabin, its fare level and this week's move (up, hold or down).
- It also says the fewest changes to make in the game's **Ticket price adjustment**.
- One tap puts them on the fare plan, and the next capture ticks each one off.
- The Saturday review chat can get the same list from one database call.

## 1. The figure: `fare_ladder()` in the database
One home for the calculation, as for the other captured figures (`private.fig_fare_ladder` and a staff function
`public.fare_ladder(p_airline_id, p_as_of)`, read with GET). This is a new migration, with a description, a grant to
`authenticated` and a test in `database/tests/` (CLAUDE.md).

- **For each route and cabin** (economy, and business where the aircraft have business seats; Ryanair has economy
  only), over the 7 days before `p_as_of`, from `game_flights`:
  - departures;
  - departures sold out (that cabin's load at 100%);
  - the sold-out share;
  - the average fare.
- **Its level, as a % of the game's default price.**
  - The latest level the fare plan recorded for that route and cabin (see 2), if there is one.
  - Otherwise the launch level: `settings.fare_launch_pct`, with Ryanair's override. Every route was launched there.
    Ryanair's four early cuts (BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC) took them to 85%, its launch level.
  - Also give the **fare index**: the latest average fare against the first captured fare, times the launch level.
    That way a level that doesn't match the captured fares shows up (a flag, not a fix).
- **The move,** from the settings, all new and described:
  - `fare_ladder_step_pts` 5;
  - `fare_ladder_up_share` 100;
  - `fare_ladder_down_share` 90;
  - `fare_ladder_min_departures` 5;
  - `fare_ladder_hold_weeks` 2;
  - `fare_ladder_cap_pts` 20.

  The moves:
  - **up** when the sold-out share is 100% and the route has at least 5 departures;
  - **hold** at 90–99%;
  - **down** under 90%;
  - **hold** for 2 weeks after a recorded down move;
  - **hold** under 5 departures, or while the route is under 7 days old (`growth_new_route_days`).

  Up never takes a level past launch + cap. Down never takes it under launch, nor under `fare_floor_pct` where another
  player flies the route. Each move gives its reason in words ("sold out 14 of 14", "capped at 120%", "held after a
  step down on 18 Oct").
- **The game actions:** the fewest Ticket price adjustments that put every route of the airline, in each cabin, at its
  new level, with the baseline **default price** (each action sets a level, so the order matters: broad first, single
  routes after).
  - **For each base:** if setting the whole base to its most common new level (From base, To anywhere; and From
    anywhere, To base) plus the single routes that differ takes fewer actions than single routes alone, use the base
    actions first.
  - **A single route** is two actions: From A to B, and From B to A.
  - Each action names From, To, + or − and the %, the baseline and the class, in the game's words, in order. Only
    routes whose level changes, or that a base action would otherwise move, need an action.
- **Rivals pausing a route** (manual §5) needs the scans compared, which is step 4. Until then the figure doesn't pause,
  the Saturday review checks by hand, and the figure says so in its notes.
- Test (`database/tests/fare_ladder_test.sql`, on the rehearsal's copy), covering:
  - up, hold and down;
  - the cap, the launch floor and the 60% floor;
  - the 2-week hold after a down move;
  - a new route;
  - too few departures;
  - Ryanair's 85%;
  - the action grouping: a base with most routes moving together gives 2 base actions plus the exceptions; a base
    where few move gives single routes; a route between two of an airline's bases.

## 2. The fare plan records levels
- `fare_plan` gains `level_pct` (numeric(5,1), the level set as a % of the default price) and `ladder_move` (up, down or
  hold), in the migration. Existing rows keep null. Each column gets a description.
- `fare_plan_status()` keeps working: it treats a row with `level_pct` as the ladder's, and "seen in the game" when the
  captured fare moves by the expected ratio (within 1%).
- The Saturday button writes one row per changed route and cabin in one `planner_save()` call. It also writes a row
  for each hold that follows a down move, so the hold has a record.

## 3. The screen: Performance
- **The fare ladder** board, open, after the scorecards. For each airline:
  - this Saturday's moves in one line: "12 up, 30 hold, 2 down";
  - **the game actions** to make, numbered, in order, each copyable;
  - **Put on the fare plan**, one tap: the rows of part 2;
  - the routes table: route, cabin, level (with how many steps above launch), the sold-out share, the move and its
    reason. Sortable, and cut to 10 rows with "show all", as the growth lists are.
- On the airline page's route profit table, a **fare index** column and a 14-day load **sparkline** (from
  `route_days`).
- The rules for every screen (`docs/specs/2026-10-20-today-performance-systems.md`) apply: colour only for action
  (down in amber, up plain), phone first, nothing sideways at 380 px.
- The ladder's moves never appear on Today or in Needs attention (manual §5).

## 4. The Hubs clean-up (from the step 1 pull request)
- Take out the planning library's `hubs` functions that only `tests/planner_figures.mjs` now uses, and their figures in
  that test (say which in the pull request). Keep anything Routes, the connection checks, the briefing or the scripts
  use.
- Take out the Hubs screen's styles from `styles.css`.
- `docs/playbook.md`: "our plan and progress (the growth rotation, what's coming)" becomes "our plan and progress
  (what's coming)".
- `scripts/README.md`: "Review's cards" becomes "Performance's scorecards". Leave `docs/decisions.md`'s history as it
  is.

## Checks
- `bash tests/run_all.sh` all green.
- The rehearsal runs the new database test and the planner on the copy. The figures test names any figure that
  moved (only the removed Hubs ones are expected).
- Unit tests beside `performance/model.ts` for the board's wording.
- `tests/planner_saves_test.py`: one new kind of save, "performance: put the fare ladder on the fare plan", with its
  rows recorded.
- `tests/planner_next_test.py`: the board is there, folded to 10 rows, and at 380 px nothing scrolls sideways.
- The generated `app/planner/src/db/types.ts` and `docs/data.md` come from the rehearsal (tests/README.md).
- The pull request lists, from the rehearsal's copy, how many routes go up, hold and down for each airline, and the
  game actions for one airline, so Gitesh can sanity-check them.

## Docs, in the same pull request
- `docs/planner-guide.md`: Performance's fare ladder, the route table's new columns.
- `docs/architecture.md`: the Planner row and the database's figures (`fare_ladder()`), plus "Which call answers which
  question" ("this Saturday's fare moves").
- `docs/playbook.md`: the Saturday fare ladder step points to Performance and `fare_ladder()` (remove "Until the
  planner lists them (step 2), Claude lists them here").
- `tests/README.md` for the new tests. The Building chat updates the project copies after the merge.

## Not in this build
- Rival pauses (step 4).
- Lifting the cap: that's Gitesh's decision, a setting.
- The route page (step 3).
- Changing fares in the game automatically: Gitesh makes the changes.

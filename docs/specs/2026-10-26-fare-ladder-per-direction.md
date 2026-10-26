# Spec: the fare ladder per direction — 26 Oct 2026

Decided by Gitesh on 26 Oct (brief `docs/briefs/2026-10-26-fare-ladder-per-direction.md`, option A; operating manual,
*Decided, not yet built*). One pull request, built by a helper (manual §1, big builds). Read `CLAUDE.md`, the map
(`docs/architecture.md`), the manual (§5 especially) and the two earlier fare-ladder specs first:
`docs/specs/2026-10-21-fare-ladder.md` and `docs/specs/2026-10-23-fare-ladder-under-launch.md`.

**Start from `main` once pull request #102 (each direction's average load, `load_out` and `load_back`) is merged**, since
it changes the same builder and table. This build replaces #102's out · back column (see 4).

## What and why
Today each cabin of each route has one **level**, judged on both directions' flights together. From now on **each
direction of each cabin of each route has its own level** (A→B and B→A apart; "out" is from the route's hub, "back"
is to it), judged on that direction's flights only. Passengers book each direction separately (manual §9) and the game's
Ticket price adjustment already changes one direction at a time. In the week to 26 Oct, 24 of 266 routes had one
direction sell out every economy flight while the route as a whole held.

## The rule (it goes into manual §5 in this pull request; see 7)
Per direction and cabin:
- **up / hold / down** by that direction's sold-out share over the 7 days, with that direction's departures counted for
  the minimum (`fare_ladder_min_departures`); the step, cap and floor settings unchanged; the **hold after a step down**
  per direction;
- **under launch** (the two jumps, the revenue judgement, revert, cut or keep?) per direction: its window, its launch
  baseline and its jump levels from that direction's flights only;
- **set back** per direction: a direction whose latest captured day is more than a point off its own level gets one
  change, for that direction only;
- **the same for the whole route** (both directions together, as now): a new route's first 7 days
  (`growth_new_route_days`), the capacity hold after a new frequency (`fare_ladder_capacity_hold_days`), the rival pause
  (`competition_threats()`), and whether the pair is contested (the 60% floor);
- **starting levels:** when it ships, each direction's level is the route and cabin's level then (the latest fare plan
  row), so nothing moves on day one.

## 1. The fare plan (database)
- `fare_plan` gets **`direction text`**, `'out'` or `'back'` (a check constraint), null meaning both directions (every
  row written before this build). Describe it in the migration. Grants unchanged.
- A direction's level is its latest ladder row (`level_pct` not null, status not dropped, proposed before this Saturday)
  **for that direction, or a both-directions row (direction null) if that is later** (the same ordering as now: proposed
  on, then id). So old rows keep counting for both directions until a direction gets its own.
- This week's row (`wk`), the hold after a step down (`dn`), the jumps (`jr`, `jf`, `jl`), the done state (`ud`) and the
  latest change (`lch`) read the same way, per direction.
- **Put on the fare plan** writes one row per direction and cabin with its `direction`, `level_pct` and `ladder_move`
  (`planner_save()`, as now; `planner_save()` must accept the new column).

## 2. `fare_ladder()` (`private.fig_fare_ladder`)
- **One row per route, cabin and direction**, ordered hub, dest, direction (out first), cabin (economy first). Each row
  adds `direction` (`out`/`back`) and `from`, `to` (the airports in that direction); `hub` and `dest` stay as they are.
- Every figure that was per route and cabin becomes per direction: `departures`, `sold_out`, `sold_out_share`,
  `average_fare`, the fare index (`latest`, `ratios`, `baseline_fare`: they are per direction already inside, keep them
  so), `level`, `steps`, `move`, `new_level`, `change_pct`, `reason`, `planned`, `plan_id`, `applied`, `seen_on`,
  `to_plan`, `ladder_kind`, `under_launch`, `decide`, `fix`, `fix_reason`. Add `load` (that direction's average load in
  the cabin over the 7 days, rounded to 0.1) and remove #102's `load_out`, `load_back`, `departures_out` and
  `departures_back`.
- `new_route`, the capacity hold (`added`), the rival pause and `contested` are worked out per route and given on both
  of its directions' rows.
- **Actions:** one per direction (From → To), set-back changes first, then the moves, in the rows' order; where a
  direction's two cabins go to the same level, one action with both classes ticked (as today per route). A direction
  whose level doesn't change gets no action. Each action keeps today's fields (`n`, `route`, `classes`, `from`, `to`,
  `level`, `sign`, `pct`, `baseline`, `fix`, `reason`, `text`).
- `moves`, `to_plan`, `planned` and `off_level` count directions (`off_level`: distinct route and direction).
- Keep the 30 s limit and `plan_cache_mode` (the figures' settings) and update `database/current/functions.sql`.
- Mind the time: the builder is the heaviest figure (about 1 to 2 s alone on live). Splitting by direction must not make
  it more than about 20% slower on the rehearsal's copy; say the before and after in the pull request.

## 3. Everything that reads the ladder or the fare plan
- **`fare_plan_status()`** (`private.fig_fare_plan`): a row with a direction is seen when that direction's day average
  fare (economy or business) shows the change; a both-directions row as now.
- **`capture_fare_actions()`** (the fares userscript's list): unchanged in shape; it lists the per-direction actions,
  and a direction is "unseen" by the same rule as `fare_plan_status()`. `capture/fares_apply.user.js` needs no change
  if the actions keep their fields; check it with `tests/fares_userscript_test.mjs`.
- **`route_story()`**: `now.fares` lists the rows per direction; `events` keep a fare plan row's direction in its words
  ("fare out: …"); `docs/data.md` follows.
- **The briefing** (`export_for_report('briefing')`'s `fare_ladder`, `scripts/briefing/brief.py`): per direction.
- **The planning library** (`lib/rules/src/card.ts`, `card.cardFares`, and the command's `--fares`): each leg of a plan
  card shows the level of **its own direction** (a leg from the route's hub takes `out`, else `back`); a route not flown
  yet still shows launch. Update `cases/` and the tests.
- **The planner:**
  - Performance → **the fare ladder**: the routes table gets a row per direction and cabin, its route shown as
    "EDI → FRA" (the airports in that direction), with its own sold out, **Load** (that direction's average, in place of
    #102's out · back column), level, move and why; the cards' counts, the numbered game changes and **Put on the fare
    plan** follow (`screens/performance/FareLadder.tsx`, `model.ts`).
  - The airline page's route profit table's fare index, the fare plan list (show a row's direction: "out", "back" or
    nothing for both), the route page's header fares and events, Tails' plan card **Fare level** column (per leg, from the
    library).
  - Regenerate `app/planner/src/db/types.ts` from a database with every migration applied.

## 4. Starting levels
Nothing to copy: a direction with no row of its own reads the latest both-directions row (1). Test it: on the copy, each
route and cabin's two directions start at the level the route had before the migration.

## 5. Tests (the database rehearsal runs them on last night's copy)
- `database/tests/fare_ladder_test.sql`: extend with per-direction cases: one direction sold out and the other at 80%
  (out up, back down); one direction under the minimum departures; a both-directions row read by both; a direction's own
  row winning over an older both-directions row and losing to a newer one; the hold after a step down on one direction
  only; under launch on one direction only; a set-back on one direction only; the capacity hold and the rival pause
  holding both; the actions (one per direction, both classes ticked when the cabins agree, set-backs first).
- `capture_fare_actions_test.sql`, `frequencies_and_fares_test.sql`, `route_story_test.sql`, `briefing_test.sql` and
  `flight_links_test.sql`: update for the new shape.
- The planner's unit tests, `tests/planner_saves_test.py` (Put on the fare plan writes `direction`), the library's
  cases, `tests/fares_userscript_test.mjs`.
- Add `direction` wherever the rehearsal's checks list `fare_plan`'s columns; follow the helpers' lessons: generate
  `docs/data.md`, `functions.sql` and the planner's types from a database with every migration applied; have
  `clean_up_test.sql` set aside exactly the new fields that reach `export_for_report('figures')`, if any do.

## 6. What the checks should show
All three checks green (Checks, Database rehearsal, Cloudflare Pages). The rehearsal's `figures-moved` artifact shows the
fare ladder's rows doubled (per direction) and no other figure moved.

## 7. Documents, in the same pull request
- **The manual, §5:** rewrite the fare ladder's rule per direction (the rule above), and remove the item from *Decided,
  not yet built*. Log the old wording and the reason in `docs/rule-history.md` (a narrative entry under §5's history and
  a row in the table of changes). The Building chat updates the project copies on merge.
- The map (`docs/architecture.md`): the fare ladder's lines (the captured figures row, Performance, the fares
  userscript, the plan card's fare level).
- The planner guide's fare ladder section, `lib/rules/README.md`, `scripts/README.md` if the briefing's words change.

## Out of scope
The fare floor, the cap and the step themselves; Ryanair's levels; the weekly report's pages (they don't read the ladder's
rows). If anything outside this spec looks wrong, say so in the pull request rather than change it.

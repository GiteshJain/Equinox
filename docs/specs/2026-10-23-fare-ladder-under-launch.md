# Build spec: the fare ladder under launch (23 Oct 2026)

**Why:** Gitesh decided on 23 Oct that a cabin that doesn't fill may go under its launch level. Read first:
- the manual's *Decided, not yet built* entry "To build: the fare ladder under launch" (the rule);
- the brief `docs/briefs/2026-10-23-fare-ladder-under-launch.md`, its Outcome and the "Changed 23 Oct" paragraph (why two
  jumps, not small steps);
- manual §5, "The fare ladder, every Saturday" (the ladder this changes);
- the earlier specs `docs/specs/2026-10-21-fare-ladder.md` and `docs/specs/2026-10-21-frequencies-and-fares.md`.

Today a cabin under 90% sold out at launch is marked `floor` and holds for ever. After this build it can jump to 80%
of the default price, then 60%, each judged on revenue a flight after 2 weeks.

**Outcome when done:** on Saturday, `fare_ladder()` gives a cabin that has been under 80% full for 2 weeks at launch the
move **jump** to 80%, with its reason. Two weeks later it judges it: paid off, or on to 60%, or back to the last level
that paid with a cut-or-keep decision for Gitesh. Put on the fare plan records it; the fares userscript makes it in the
game with no change of its own, since a level under 100 is already a "−" action. Performance's fare ladder shows the
new moves.

## 1. Settings (new rows, each described; world rows, an airline may override)
| Key | Value | Meaning |
|---|---|---|
| `fare_under_launch_load_pct` | 80 | a cabin at launch averaging under this % full over the window may jump |
| `fare_under_launch_levels` | `[80, 60]` | the jump levels, % of the default price, in order. Ryanair takes the same for now; Gitesh may set its own row later as a data change |
| `fare_under_launch_days` | 14 | the window: days at launch before the first jump, and days held at a jump level before it's judged |
| `fare_under_launch_min_flights` | 10 | flights the cabin needs in a window to be judged; fewer, it waits (reason says how many) |
| `fare_under_launch_decide_load_pct` | 60 | at the last level, a cabin still averaging under this % full goes to Gitesh |

The floor under launch is the last jump level; `world_rules.fare_floor_pct` keeps its role for contested routes above
launch. No other rule number changes.

## 2. The figure: `private.fig_fare_ladder`
A new migration replacing the function (and `database/current/functions.sql`). Keep everything else it does exactly as
it is: the moves above launch, the holds, the rival pause, set back, the actions, the notes.

**Per cabin, add the window figures** from `game_flights` (by cabin, both directions together, as the 7-day figures are):
flights, average load (`eco_pct` or `bus_pct`), and **revenue a flight** (`eco_pax × eco_fare`, or `bus_pax × bus_fare`,
averaged over the flights).

**The cabin's under-launch state,** from the fare plan's recorded rows for that route and cabin
(`fare_plan.ladder_move`, see 3):
- **at launch, never jumped:** level equal to launch and no `jump` row;
- **holding after a jump:** its latest `jump` row is less than `fare_under_launch_days` old, counted from the day the
  captures saw it applied (`fare_plan_status()`'s seen day; the plan's `proposed_on` until then);
- **due to be judged:** the hold is over;
- **done:** a `revert` row exists, or a jump was judged as paid. No more jumps for that cabin.

**The new moves,** placed in the existing `case` after `planned`, `young`, `few`, `held`, `added` and `rival` (those
still win):
1. **jump** (first): at launch, never jumped, the ladder's own result would be `floor` (under 90% sold out at launch),
   the window's flights at least `fare_under_launch_min_flights`, all at the launch level (no recorded level change in
   the window), and the average load under `fare_under_launch_load_pct`. New level: the first jump level. Reason, e.g.
   "41% full over 14 days at launch: to 80% for 2 weeks".
2. **jump hold**: holding after a jump. Move `hold`; reason "at 80% since 25 Oct: judged on 8 Nov".
3. **judged** (due, with at least the minimum flights at that level since the jump was seen; fewer waits, saying so).
   Compare the cabin's revenue a flight over those days with its **launch baseline**: revenue a flight over the
   `fare_under_launch_days` before its first jump.
   - **Paid off** (not lower than the baseline), and not at the last level with load under
     `fare_under_launch_decide_load_pct`: stays, state done, the normal ladder from there (below). Reason "at 80%:
     revenue a flight 12,400 against 11,000 at launch, paid off".
   - **Didn't pay, a next level exists:** **jump** to it, with the same hold. Reason "at 80%: revenue a flight 9,100
     against 11,000 at launch: to 60% for 2 weeks".
   - **At the last level and didn't pay:** **revert** to launch. **At the last level, paid, but under the decide
     load:** hold at that level. Either way the row is marked `decide` (true) and the reason says it's a cut-or-keep
     decision for Gitesh, e.g. "at 60% for 2 weeks: 38% full, revenue a flight 9,800 against 11,000 at launch: back to
     launch; cut or keep? (Saturday review)". State done.
4. **Below launch, once done (or between jumps):** the ladder only climbs or holds. Where its own result would be
   `down` or `floor` under launch, the move is `hold` with the reason "under launch: climbs or holds only". Up moves and
   the cap are unchanged (from 80, Pan Am steps 7 to 87, and so on).

**The output:** each route row gains `under_launch` (`{state, baseline_revenue, window_revenue, window_load,
window_flights, jumped_on, judge_on}` where they apply) and `decide` (boolean). Moves `jump` and `revert` give
`move: 'down'` and `move: 'up'` respectively, with a new field `ladder_kind` ('jump', 'revert', or the existing kinds),
so existing readers keep working. `to_plan` includes jumps and reverts. `moves` keeps its three counts; add
`jumps` and `decisions`. The actions loop needs no change: a level under 100 already gives "−".

## 3. The fare plan
- Allow `ladder_move` values `jump` and `revert` (the check constraint), described.
- **Put on the fare plan** (Performance) writes `ladder_move` from the row's `ladder_kind` when it is `jump` or `revert`,
  else as today. `fare_plan_status()` ticks them off as any other level.
- `capture_fare_actions()` needs no change; check it lists a jump with its plan rows.

## 4. The planner: Performance → fare ladder
`app/planner/src/screens/performance/FareLadder.tsx` and its model:
- the week's line counts jumps and decisions ("2 jumps, 1 decision");
- the routes table shows `jump`, `revert` and the under-launch hold in words, with the reason;
- a cabin with `decide` shows a plain marker "cut or keep?" beside its reason. Nothing goes to Today's Needs attention
  (fare moves never do, manual §5).
- types regenerated (`app/planner/src/db/types.ts`) if the migration changes them.

## 5. Tests
- `database/tests/fare_ladder_test.sql` (on the rehearsal's copy), new cases built from recorded rows:
  jump at launch under 80%; no jump at 85% full; no jump with 9 flights (waits, reason); hold during the 14 days; paid
  off at 80% (stays, then only climbs or holds); not paid at 80% → jump to 60%; not paid at 60% → revert with decide;
  paid at 60% but under 60% full → hold with decide; a jumped cabin that later sells out climbs normally; a cabin above
  launch still never goes under launch by a 5-point down; Ryanair (launch 85) jumps to 80; a contested route keeps its
  60% floor above launch; existing cases unchanged.
- The planner saves test (`tests/planner_saves_test.py`): Put on the fare plan with a jump writes `ladder_move` jump
  (update `tests/fixtures/planner_saves.expected.json`).
- The fares userscript test: an action at 80% is "−20%" (it should pass unchanged; add the case).
- Screen figures and the rehearsal's every-screen check stay green. Say in the pull request which saved answers moved
  and why (on live today, expect a few jumps: PVG–CCU, KUL–TRV, DEL–AMS among them, if their windows qualify).

## 6. Documents (same pull request)
- The map (`docs/architecture.md`, and paste the same into the pull request description for `claude/architecture.md`):
  the fare ladder's under-launch jumps in the captured figures' `fare_ladder()` entry and the Performance entry.
- The planner guide (`docs/planner-guide.md`): the new moves and "cut or keep?".
- The playbook (`docs/playbook.md`): the Saturday fare step mentions the cut-or-keep decisions the fare ladder lists.
  Steps only; it points to the manual.
- `database/current/functions.sql`; `docs/data.md` via the rehearsal.
- **Not the manual:** the Building chat moves the rule into §5 after the merge.

## 7. What the checks should show
All green: Checks and the Database rehearsal. In the rehearsal's `figures-moved` artifact, only `fare_ladder` (and the
figures that read it: the briefing's `fare_ladder`, the plan card's fare levels for any jumped route) moved.

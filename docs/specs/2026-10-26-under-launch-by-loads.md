# The fare ladder under launch, judged by loads

Decided 26 Oct 2026 (Gitesh): brief `docs/briefs/2026-10-26-under-launch-by-loads.md`; the rule is already in the
manual, §5 ("Under launch, two jumps … judged by loads since 26 Oct"), with a *Decided, not yet built* entry until this
is merged.

## What changes (database: `private.fig_fare_ladder()`; current definition in `database/current/functions.sql`)
The under-launch states built on 23 Oct (spec `docs/specs/2026-10-23-fare-ladder-under-launch.md`, migration
`20261023…_fare_ladder_under_launch`, and the per-direction rework of 26 Oct) judge a cabin after each jump's 2-week hold
on **revenue a flight against its launch baseline** (`b_rev`, `j_rev`, the kinds `ul_keep`, `ul_revert`, the 14-day
baseline, `fare_under_launch_decide_load_pct`). Replace that judgement:

1. **The first jump stays as it is:** a direction at launch that the ladder would hold there (under 90% sold out),
   averaging under `fare_under_launch_load_pct` (80%) full over `fare_under_launch_days` (14) with at least
   `fare_under_launch_min_flights` (10) flights, all at launch, jumps to the first of `fare_under_launch_levels`, and
   holds `fare_under_launch_days` from the day the captures see it.
2. **After a jump's hold, judge by the week's loads exactly as the normal ladder does** (the same sold-out share, the
   same minimum departures, the same step and its airline overrides):
   - sold out → move **up** one step (a normal `up`, so the hold after a step up applies the next Saturday), and it
     carries on through launch to the cap like any direction;
   - 90–99% sold out → hold;
   - under 90% sold out → if at the first jump level, jump to the next of `fare_under_launch_levels` (60%) and hold its
     2 weeks; if at the last level, **hold** there and mark it **decide** (cut or keep?), with a reason saying so.
3. **Gone:** the revenue test, the launch baseline, the revert (`ladder_kind` revert and `ul_revert`), `ul_keep`. Under
   launch the ladder still only climbs or holds (no 5-point cuts). It never jumps again after the second jump, nor after
   it has climbed back to launch.
4. A cabin marked decide stays marked (shown on the airline's fare ladder with "cut or keep?") until Gitesh acts; it
   keeps being judged by loads, so if it starts selling out it climbs and the mark goes.
5. The setting `fare_under_launch_decide_load_pct` is no longer read: leave the row, and change its description to say
   so (since 26 Oct). Don't remove settings rows.
6. Everything else unchanged: the capacity hold, the rival pause, the set-back, the 60% floor where another player flies
   the pair, the cap, per direction.

## Planner
`screens/performance/FareLadder.tsx` and `model.ts` word the kinds (`jump`, `revert`, "hold under launch", "back to
launch, 100%"). Remove what's gone (revert's words); keep jump and decide. Check Put on the fare plan still writes the
right `ladder_move` (`jump` for jumps, else the move).

## Tests
- `database/tests/fare_ladder_test.sql`: rework the under-launch sections: a jumped cabin that sells out after its hold
  steps up (and holds the next Saturday); one at 90–99% holds; one under 90% at 80% jumps to 60%; one under 90% at 60%
  holds and is marked decide; no revert anywhere; a cabin that climbed back to launch carries on to the cap and never
  jumps again.
- Planner unit tests for the words; saved answers that move (say which and why).

## Documents (same pull request)
`docs/architecture.md` (`fare_ladder()`'s under-launch paragraph), `docs/planner-guide.md` (the fare ladder's
under-launch words), `docs/data.md` (descriptions you change), `database/current/functions.sql`. Leave
`docs/operating-manual.md` alone: the Building chat removes its *Decided, not yet built* entry after the merge.

## Lessons from earlier helpers
Add or change settings in `rules_input_test.sql`'s list if their set changes; `clean_up_test.sql` sets aside new fields
reaching `export_for_report('figures')` (the fare ladder doesn't reach it); a test comparing whole JSON breaks when fields
change; `(x -> 'a') - 'b'`, not `x #> '{a}' - 'b'`; the migration repeats the whole function (large is expected); keep
the branch up to date with main.

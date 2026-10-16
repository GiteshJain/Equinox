# Build spec: new routes aren't judged for a week — 16 Oct 2026

**Why:** on 16 Oct Home listed PVG–CCU (China Eastern) and KUL–TRV (Malaysia) as "losing money — its average flight
loses money". Each had flown one round trip (2 flights, 15 Oct), economy 3 to 9%, a loss of 1.6k to 4.8k a flight.
Home's mark comes from `route_profit()`, whose "losing" needs only 2 departures (`growth_losing_min_departures`), a single
round trip, so every new route gets it on its first day. The next problem mark, "fix" (from 5 departures, economy under
75%), would have followed within three days. Gitesh chose a route-age condition with N = 7 days (16 Oct, Building chat).

## What to build
1. **A setting, `growth_new_route_days` = 7**, in every world, unit days, described, with its reason (like the other
   `growth_*` settings; an airline may override it).
2. **`private.fig_route_profit()`** (the one home of the marks, #19): a route is *young* when its launch day is fewer than
   that many days before the moment asked (UTC date). Its launch day is the earliest `rotations.launched_on` of the route
   (all its rotations, so a second daily added later doesn't make an old route young); none on record counts as old.
   A young route gets none of the **problem marks**: `losing`, `fix` and the thin-margin `fix`. The sold-out marks (`add`,
   `raise`) are unchanged, and a young route that gets no mark is `hold`. Nothing else in the document changes: no new keys.
3. Everything that reads the marks follows on its own (Home's routes to fix, Check's Fix or reduce, the weekly report, the
   airline briefing), since they read `route_profit()` and `growth_signals()`.

## Not in the spec
- The load patterns (`pattern_*`), which Home shows only when no profit has been captured.
- "Aircraft losing money after their lease" (an aircraft's net, not a route's mark).
- Any other threshold.

## Files
`database/migrations/20261016120000_new_route_age.sql` (the setting, and the function replaced with the same arguments:
nothing dropped, so it can be applied from the chat), `database/current/functions.sql`, the tests below, and the docs the
manual lists: manual §3, playbook §6, planner guide (Check), the map's guide, `tests/README.md`.

## Checks
- `database/tests/new_route_age_test.sql` (new): five routes in a world of its own; young routes held, old ones and one
  with no launch day marked; the edge at 6 and 7 days; the setting at 0; an airline's own value.
- `clean_up_test.sql` compares every captured figure with before the changes; while this migration is pending it puts the
  setting at 0 days (nothing counts as new) so everything else must still be exactly as before
  (`before/clean_up_before.sql` saves whether the setting existed). The rehearsal's `figures-moved` artifact shows which
  marks moved on last night's copy: expected PVG–CCU and KUL–TRV and any other route launched in the last 7 days.

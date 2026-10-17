# Add a flight or raise fares, by profit per aircraft hour (17 Oct 2026)

Decided in the Saturday review chat, 17 Oct: option B of `docs/briefs/2026-10-17-add-or-raise.md` (manual §3).

## What changes
- `private.fig_route_profit()`: a sold-out route (`growth_sold_out_share`, `growth_sold_out_min_departures`, as
  before) is marked **add** when its profit an aircraft hour is at or above its airline's median route, **raise** when
  below.
  - **Aircraft hours a flight:** each of the route's legs (the airline's rotations of that route), its block time plus
    its aircraft type's turnaround (`aircraft_types.min_turn_min`) and the turn margin (`settings.turn_margin_min`, an
    airline's own where it has one), averaged over the flights a week each leg flies. An untimed leg's block is the
    estimate the planning library uses: `block_allowance_min` + distance ÷ the type's cruise speed.
  - **Profit an aircraft hour** = the route's average flight's profit ÷ its aircraft hours.
  - **The middle route:** the median profit an aircraft hour among the airline's routes that have hours.
  - **No legs on record** (a route flown in the window whose rotation has gone): no hours, so it's still compared by
    profit a flight against the median profit a flight, as before. Its why says "a flight".
  - Each route also gives `aircraft_hours` and `profit_per_aircraft_hour`. The why reads "profit an aircraft hour at or
    above / below the airline's middle route".
  - Losing, fix, fix-margin (still by profit a flight's bottom quarter), the age condition and the cash forecast are
    unchanged.
- Check → Growth: the notes for Ready for another flight and Raise fares say "an aircraft hour", and both tables gain an
  **An aircraft hour** column.
- Documents: the manual (§3 line now built, the old rule retired), the planner guide, the handover guide, the map's
  guide row, `tests/README.md`.

## Files
- Migration `database/migrations/20261017180000_add_or_raise_aircraft_hour.sql`; `database/current/functions.sql`.
- Test `database/tests/add_or_raise_test.sql` (a world of its own: hours, marks, the why, the fallback, the airline's
  own margin). `database/tests/before/clean_up_before.sql` saves route profit's definition before the changes, and
  `clean_up_test.sql` puts it back while this is pending, so every other figure must still be exactly as before.
- `app/planner/src/screens/check/Growth.tsx`, `reads.ts`.

## Not in scope (said in the pull request)
- The weekly report and the airline briefing show profit a flight, not yet profit an aircraft hour; their marks and
  whys come from route profit, so they follow the new rule.
- Review's route profit table shows each route's mark and why (which follow), without an aircraft-hour column.

## What the checks should show
- The rehearsal's `figures-moved` artifact: only route profit's sold-out routes' marks and whys, the two new fields,
  and the growth lists built from them move. The brief counted 36 of 180 sold-out routes changing on 10–17 Oct.

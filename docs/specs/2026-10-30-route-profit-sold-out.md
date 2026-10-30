# Spec: route profit shows the ladder's move — 30 Oct 2026

*Building chat. Decided 30 Oct (Gitesh), brief `docs/briefs/2026-10-30-route-profit-and-fare-ladder.md`, option B.
Manual: *Decided, not yet built*, "Route profit shows the ladder's move".*

## What
- **`route_profit()`** (`private.fig_route_profit` or wherever the mark is set): a sold-out route below its airline's
  middle route per aircraft hour gets mark `sold_out` with why "sold out · fares climbing (the fare ladder raises it each
  Saturday)" instead of `raise`. `add` (at or above the middle) and every other mark unchanged. A small migration;
  descriptions kept word for word with the change added (append, as before).
- **Everything that reads `raise`:** find every reader (`growth_signals()`, the planner's Performance (route profit
  chart's colours and legend, growth signals' kinds), the route page and Routes' story, Today if it lists them, the
  weekly report, the briefing, docs) and switch it to `sold_out`. Where a sold-out route is shown with its mark, show the
  fare ladder's move for each direction beside it (from `fare_ladder()` where the screen already reads it; on the
  airline page it does; on the group page, which reads no ladder, show the mark only).
- Rename the growth signal "raise fares" to "sold out · fares climbing" wherever it's a label.
- **Not changed:** the fare ladder, `add`, fix, losing, hold, the 7-day rule for new routes.

## Tests
`database/tests/`: a sold-out route below the middle is `sold_out`, above is `add`; no `raise` left anywhere in the
answer. The planner's unit tests and figures; the report and briefing tests. The saved answers in
`tests/planner_figures.mjs` move only where they named `raise`: say which in the PR. Remember the lessons: when
replacing a description keep every word; `clean_up_test.sql`'s figures comparison may need the new mark set aside
while the copy predates it (as for `contested`).

## Docs
The map, `docs/planner-guide.md`, `docs/data.md` through the rehearsal, `database/current/`, the playbook if the Saturday
review reads the mark. Don't change the manual: the Building chat replaces §3's sentence after the merge.

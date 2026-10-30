# Spec: charts everywhere — 30 Oct 2026

*Building chat. Gitesh, 30 Oct: "use charts (pie, combo, bar, timeline, line graph, etc.) everywhere instead of text or
tables as much as possible". The screen-by-screen list below was agreed the same day. No database change is expected:
every chart draws figures the screens already read. Three pull requests, in this order: A Performance, B Competition,
C Today, Tails, Home and Systems.*

## Common to all three
- **One chart kit:** the planner draws its charts by hand in SVG (`screens/performance/Charts.tsx`, no chart library).
  Move the reusable parts to `src/ui/charts/` and add what's needed: horizontal bars, stacked bars, a donut, a step line
  with a reference line, a timeline (rows with markers), a scatter with sized points, a gauge against a trigger, a
  heat-strip, small multiples. No new dependency unless a chart can't reasonably be drawn by hand; say so in the PR if
  one is added (pinned, and loaded only on the screen that uses it).
- **Every chart:** a title and a one-line note as the boards have, axis labels, a legend where there's more than one
  series, a tip on hover or tap with the exact figure, colours from the planner's airline colours and its good/warn/bad
  tokens, and an empty state in words. Readable on a phone at 380 px (no sideways scroll; charts shrink or stack) and in
  dark mode if the planner has one.
- **A table stays reachable:** where a table is replaced, a "show as table" toggle keeps the exact figures one tap away
  (remembered per board in the address or local storage, as the screens do now).
- **Figures don't change:** the charts read the same model functions; unit tests check each chart's layout figures
  (bars, points, labels) on the existing samples, and `tests/planner_figures.mjs`' saved answers don't move.
- Docs: the map's paragraph for each screen and `docs/planner-guide.md`.

## A. Performance
**An airline** (`/planner/performance/<code>`):
- **Route profit:** horizontal bars of profit per aircraft hour per route, sorted, coloured by its mark (add a flight,
  raise fares, fix, losing, hold), the airline's middle route as a reference line; the 1/3/7-day switch stays. Table
  behind the toggle.
- **Cash, next 14 days:** a step line of the forecast with the 0.5M cushion (`order_cushion`) drawn as a line and the
  lowest point marked; each lease and closing a dot with its tip.
- **The fare ladder's week:** a stacked bar per cabin and direction kind of this Saturday's moves (up, hold, down, jump,
  decide, set back), above the existing list. **The game changes list stays a table** (it's copied into the game).
- The profit chart, the table of reported days and the fare plan: the days as a bar chart (already), the fare plan as a
  small timeline of planned changes and when the captures saw them; tables behind the toggle.

**The group** (`/planner/performance`):
- **Scorecards:** small multiples, one per airline: profit a day, average load and fleet over the last 14 days.
- **Growth signals:** a stacked bar per airline by kind (ready for another flight, raise fares, fix or reduce, losing
  after lease), each segment opening its list.
- **Main hubs towards 750:** already bars; keep.
- **Flights by day:** a load heat-strip by hour of the day and airline for the chosen day, the flight list behind the
  toggle.

## B. Competition
- **Market share:** a donut per market (ours, the top rivals, the rest), the game's share beside the scan's where read.
- **Threats:** a timeline of rival moves by scan date, each marker a threat with its tip and link.
- **Openings:** a scatter of stars against rivals' departures a week, point size by distance, coloured by variant
  family, hubs-first marked; **the ranked list stays below** (the Scheduling chat reads its order).
- **Rival profiles:** each rival's fleet and orders as a stacked bar by type, with the week's change.
- **Order books:** bars of orders against fleet, the flag threshold drawn.

## C. Today, Tails, Home, Systems
- **Today → Orders:** a timeline per airline of its delivery lines (each line's queued aircraft until it runs dry, now,
  and the cash-safe date as a marker), the current table behind the toggle. **To-dos, Aircraft to file and Game check
  stay as they are.**
- **Tails list:** bars of block hours a day per aircraft against the 10- and 12-hour marks
  (`aircraft_block_target_h`, and 12), coloured by maintenance state, grouped by base; tap a bar for the aircraft. The
  aircraft page's legs stay a table.
- **Home:** each airline card gains a 14-day profit sparkline.
- **Systems:** database size, report PDFs and the website's data as gauges against their triggers; each airline's
  capture verdicts over the last 14 nights as a small bar history. Manual entry and Cabin charges stay tables.

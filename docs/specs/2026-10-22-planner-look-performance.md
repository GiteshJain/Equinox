# The planner's new look, step 5: Performance (22 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md` (B in steps; "Next ... Performance", Gitesh 22 Oct: "these still look
bad"). Steps 1 to 4 (#71 foundation, #72 Today, #73 Routes, #74 Systems) are live; this rebuilds Performance's layout in
the same style. Everything Performance shows and does stays reachable: the scorecards, the fare ladder and Put on the
fare plan, the group today, growth signals, main hubs, flights by day; on an airline's page profit, cash for 14 days,
route profit (its table, chart, fare plan adds, the 14-day sparkline), aircraft, fare changes and the fare plan; the
route pages. No figure, save or query changes.

## The group page (/planner/performance)
1. **The answer is the title.** The page head's title becomes a short answer from the cards already read, with no
   group total (manual §1: each airline is its own business): "Six airlines, all in profit", or how many aren't ("5 of 6
   airlines in profit"). The context line stays ("Results").
2. **Scorecards:** keep the three-up grid with this afternoon's fix (top-aligned, readable labels); make the big profit
   figure and name line the card's head, the rows below in two tidy columns (label left, value and its ▲▼ change right,
   in one cell), and the "Next order" line as the card's footer with its pill.
3. **The fare ladder as one card per airline**, in a two-column grid (one on phones): the airline's dot and name, its
   moves as three counts in Unbounded (up, hold, down), the number of game changes, and its two actions: **Put on the
   fare plan (n)** as the primary button and **See the changes** that opens the list of game changes (the copy lines)
   and the routes table below the card. Nothing long is shown until opened. Keep the sort pills inside the opened part.
4. **Group today, growth signals, main hubs, flights by day** as the detail rows that open (the pattern Systems uses
   since step 4), each with a one-line count or state, all closed on arrival except the fare ladder cards.

## An airline's page (/planner/performance/<code>)
1. **Head:** the airline's name as the display title, its scorecard figures as a row of four big numbers under it
   (profit a day, per aircraft, return on fleet, next order), the airline switch as the segmented control Routes uses.
2. **Charts that read:**
   - **Load against profit:** the load axis from the lowest load among the routes shown, rounded down to the next 5%
     (never below 40%), to 100%, so the routes spread out; labels only on the five routes with the most profit and the
     ones off the pattern (marked fix, raise fares or add a flight), placed so they don't overlap (drop a label rather
     than overlap); the axis title fully inside the chart.
   - **An average flight:** sits beside the chart at the same height, or under it on narrower screens; no half-empty box.
3. Profit, cash for 14 days, route profit, aircraft, fare changes and the fare plan as the detail rows that open, with
   route profit open on arrival.

## Checks
- `bash tests/run_all.sh` green; the database rehearsal green: Performance (group, an airline, a route page) opens at
  1280 and 380 px with no errors and no sideways scroll, and every save on Performance (Put on the fare plan, fare plan
  add and drop) still works. The screens' figures tests must not move. Keep every `data-figure`, id and data attribute;
  change a test only where the layout requires it (e.g. opening a row first), and say which in the pull request.
- Update `docs/planner-guide.md` (Performance).
- Read performance-1280, performance-380, performance-airline-1280 and -380 from the rehearsal before reporting.

## Not in this build
Any other screen; any change to data, figures, saves or queries.

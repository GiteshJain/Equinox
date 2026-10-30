# Spec: the market pages, part 2 (the route page, Competition, the service check, the weekly report) — 30 Oct 2026

*Building chat. Decided 30 Oct (Gitesh), brief `docs/briefs/2026-10-29-market-pages.md`, option C. Builds on part 1
(`docs/specs/2026-10-30-market-pages.md`, merged first): the tables `market_runs`, `market_reads` (with
`service_code`), `market_fares`, `market_shares`, `market_weeks`. Also folds in the route page proposal of 29 Oct: the
right half of every board is empty at 1280 px.*

## What
1. The route page goes to two columns on wide screens and gains five boards.
2. `route_story()` gives what they need.
3. A weekly service check: our service profile on each pair in the game against the planner and the distance rule.
4. Competition shows the game's passenger share beside the scan's.
5. The weekly report shows rivals' fares.

Until the first market read lands, every new board says so plainly ("No market read yet: the capture reads the
market pages once a week") and nothing errors.

## 1. The route page (`app/planner/src/screens/performance/RoutePage.tsx`, its logic in `model.ts`)
**Layout:** at 1100 px and wider, the boards pair up in a two-column grid, each pair the same height where it can be;
under 1100 px one column, as now (380 px unchanged: no sideways scroll). The header and the 7-day tiles stay full
width. Order (left · right):

| Row | Left | Right |
|---|---|---|
| 1 | Since launch | **Load by direction** (new) |
| 2 | **Loads by flight** (new) | Profit an aircraft hour |
| 3 | **Rival fares** (new) | **Market share** (new) |
| 4 | Rivals on the pair | **Rivals over time** (new) |
| 5 | Events | Connections |

Folding, Collapse all and Expand all work for the new boards as for the old (`ROUTE_BOARDS`).

**Load by direction:** economy load each UTC day since launch, out (from the hub) and back as two lines, the same
chart style as Since launch, each direction's fare level as a step line on the right axis (from the fare plan's ladder
rows per direction, as the fare ladder reads them). Under `STORY_MIN_DAYS` days it says so, as Since launch does.
Source: `route_story()`'s new `days_by_direction`.

**Loads by flight:** each flight number on the route over the last 7 days: direction, departure (local), average
load, flights and how many sold out (`growth_sold_out_min_departures` doesn't apply; sold out is 100% economy), as a
row each with a horizontal bar for the load. Source: `route_loads()`'s `flights` (no database change).

**Rival fares:** from the latest market read of each direction: a table per direction (out, back) with each airline on
the pair (ours first, marked), its economy and business fares (average, with lowest–highest when they differ), flights
seen and sold out of finished, and ours as a % of the cheapest rival's economy fare ("we're 15% under KLM"). The read's
date at the top. Source: `route_story()`'s new `market`.

**Market share:** the game's passenger share on the pair, this week and last, each direction, as a bar per direction
(ours and the top rivals, the rest grouped), with our change in points. Beside it, the scan's departures share for
comparison, labelled. Source: `route_story()`'s `market`.

**Rivals over time:** each rival's direct departures a week at every scan since launch (weekly points from
`scan_pair_airlines` before the latest month, every scan within it, as Rivals on the pair's share line already reads),
ours too, as lines (top 5 rivals, the rest grouped); and the pair's seats offered and price per unit by calendar week
from `market_weeks` as a second small chart under it. Source: `route_story()`'s new `rivals.history` and
`market.weeks`.

## 2. `route_story()` (new keys; nothing existing changes)
- `days_by_direction`: per UTC day and direction (out, back): economy and business passengers, seats and load, from
  `route_days`.
- `rivals.history`: per scan since launch (the same scans as `rivals.shares`): each airline's direct departures a week
  on the pair, ours included, passenger flights only.
- `market`: `null` when no read; else per direction: the read's time and run, `service_code`, the fares by airline and
  class (`market_fares`, airline names), the shares this week and last (`market_shares`), and `weeks` (`market_weeks`,
  the pair's both directions).
Update `database/current/`, the description, and `database/tests/` for each key (including a route with no read).

## 3. The service check
A captured figure `market_service_checks(p_airline_id default null)` (staff, GET, the captured figures' 30 s limit,
builder `private.fig_market_service_checks()`): for each pair and direction in the latest finished run, the game's
service profile against (a) the code the route's distance calls for (manual §4: S1 under 800 km, S2 800 to 1,500, S3
over 1,500; Ryanair R; from `service_profiles` as the planning library reads them) and (b) the codes of the planner's
legs that way. A row for every mismatch: the pair, direction, airline, the game's code, the distance's code, the
planner's codes. Shown:
- **Today → Needs attention**, a group **Service in the game** (one item per mismatch, worst first: game differs from
  the distance code; then the planner differs), each linking to the route page. Dismissable as other items.
- **Systems board:** the market line (latest finished read, its age, pages and failed; amber over 8 days, red over 15,
  as the scan's), with the number of service mismatches.
- The route page's header: "service S2 in the game" beside the layout, amber when it differs.

## 4. Competition
Each market card (airline page and group page) shows, where the market's pairs have reads, **the game's passenger
share**: our share over the market's pairs weighted by each pair's seats offered in the latest week (`market_weeks`),
labelled "game share (pairs read: 12 of 14)", beside the scan's departures share, never replacing it. Openings, threats,
contested and hubs first don't change. Source: `competition()` gains `game_share` per market (null with no reads).

## 5. The weekly report
In each airline's competition section: its contested pairs (a rival with at least as many departures as ours, from
`competition()`) with our economy fare against the cheapest rival's each way, from the latest read, and the game's
passenger share this week against last. Through `export_for_report('figures')` (add the market figures there), money
untouched. `tests/report_test.py` covers it on the sample (with and without reads).

## Tests and checks
- The planner: unit tests beside `model.ts` for each new board's figures (with and without a read); the screens'
  figures check and the rehearsal's screen run at 1280 and 380 px with no errors and no sideways scroll; the saved
  route page addresses still open. Add a market read to the rehearsal's copy only through `capture_market()` in a
  database test, never live data.
- `database/tests/`: `route_story()`'s new keys; `market_service_checks()` on a pair set right and one set wrong;
  `competition()`'s `game_share`.
- The map's call guide: one tested example each for `market_service_checks()` and `route_story()`'s `market`
  (aggregating into one row so an empty table still returns one).

## Docs, in the same pull request
The map (the planner row's route page, Today, Systems and Competition, the captured figures row, the call guide),
`docs/planner-guide.md` (the route page's boards, the service check), `docs/data.md` through the rehearsal,
`database/current/`, the playbook's Saturday step if the report's section changes how the review reads it. **Don't
change the manual:** the Building chat moves the rule into §7 (and the service check into §4) after the merge.

## Not in this pull request
The fare ladder's rules, the openings' order, the contested test, reading pairs we don't fly.

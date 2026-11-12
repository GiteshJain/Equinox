# Tables into charts, screen by screen — 12 Nov 2026

Main chat, to-do 232. His standing preference (30 Oct): "use charts (pie, combo, bar, timeline, line and the like) instead
of text or tables as much as possible, everywhere". The glass look kept charts out of its build (brief
`2026-11-11-glass-look.md`, decision 5) so that each screen's charts are his decision first. On 12 Nov he said to start
with what the Main chat thinks best.

The money columns of the usual table don't apply: no game cash, routes or growth move. The tables compare what he sees,
effort in pull requests, risk and how easy each is to undo.

**The short answer:** the job is smaller than it looked. The 30 Oct build (spec `2026-10-30-charts-everywhere.md`)
already turned most tables he *reads* into charts. Of the planner's 47 tables, 11 already are a chart with the table one
tap away, 28 are lists he acts on row by row or edits (they should stay tables), and only 8 are left to change: 4 to
become charts and 4 to gain a small chart beside them. That is about 4–5 pull requests in all, not ten screens' worth.

**Sample:** `charts-sample.html` (the Main chat has it): the first screen's charts beside today's tables, in the glass look,
with made-up figures for Pan Am JFK–ORD. The alternatives are side by side, marked A and B.

---

## Decision 1: which screen first

**Decision:** where the first chart build goes.
**Recommendation: A, the route page** (Performance → a route, and the same boards in Routes' story column). Three of
the four tables left to turn into charts are here. All three are for reading, never acting. The route page is where he
goes to see *why* a route does what it does, so it gains the most from charts. And the boards are one shared component
(`RouteStory.tsx`), so one build changes two screens.

| | A. The route page (+ Routes' story) | B. Today's Coming up | C. Performance's airline page |
|---|---|---|---|
| What changes | Rival fares, Rivals on the pair and Connections become charts (Loads by flight is decision 5) | a 14-day strip of marks above the list; the list stays | Fare changes becomes a chart of load change per fare change; hub readiness gets bars in its cells |
| What he gains | see at a glance where our fare sits, who is growing on the pair, and which cities the route feeds | when the next 14 days' events bunch up, on the screen he opens every day | whether raising fares cost load |
| Pull requests | 2 (or 1 if he takes 5A) | 1, small | 1 |
| Risk | the kit gets two new layouts (before → now, mirrored bars) with unit tests; the rehearsal reads these tables' rows, so its checks move to the chart or flip the toggle | low | low |
| Easy to undo? | yes: revert, or "show as table" (remembered per board) | yes | yes |

**Order after the first (recommended):**

| # | Screen | What | Pull requests |
|---|---|---|---|
| 1 | Route page + Routes' story | Rival fares, Rivals on the pair, Connections (decisions 2–5) | 2 |
| 2 | Performance, airline and group pages | Fare changes → load change by fare change (bars); hub readiness → bars in the "cities flying" cells | 1 |
| 3 | Today | Coming up → a 14-day strip of marks over the list (the kit's timeline) | 1 |
| 4 | Systems (optional) | Fleet → a maintenance bar in each cell, against the airline's limit | 1, low value |
| — | Reference, Interline, Tails, Routes' own tables, Competition, Home, Photos | none: already charts, edit tables or lists he acts on | 0 |

## Decision 2: Rival fares (the route page and Routes' story)

**Today:** a table for each direction: airline, economy fare, business fare, flights, sold out, ours first, then
"we're 8% over Polar Connect". About 3–8 rows.
**Recommendation: A, bars.** One bar per airline for its economy fare, cheapest at the top. Ours is in the airline's own
colour and rivals are grey. A dashed line marks our fare. The label at each bar's end gives the fare and how many flights
sold out. The tip gives business, flights a week and sold out. The "we're 8% over…" line stays. One chart per direction.

| | A. Bars, cheapest first | B. Dots on one fare scale |
|---|---|---|
| What he sees | the exact order and the gap to ours at a glance | economy and business on one scale; each dot sized by flights a week; ringed amber where half or more sold out |
| Weakness | business only in the tip | dots overlap when fares are close (they do in the sample); exact order is hard to read |
| Effort | the kit's bars as they are | a new dot-strip layout |
| Easy to undo? | yes | yes |

## Decision 3: Rivals on the pair (the route page)

**Today:** rival, direct flights a week, change since the last scan, connecting flights. About 2–8 rows, and our own line
under it.
**Recommendation: A, before → now.** One row per rival. A hollow dot shows the last scan and a filled dot shows now,
joined by a line: red if the rival grew, green if it shrank, grey if it held. A dashed line marks our own flights a week.
Connecting flights stay a separate number at the right and are never added to direct (manual §3). The tip gives every
figure.

| | A. Before → now | B. Bars of today, the change in words |
|---|---|---|
| What he sees | who is growing jumps out (a red dot moving right) | each rival's size today; the change only in the label |
| Weakness | a little busier | a big move doesn't stand out |
| Effort | a new kit layout (before → now) with unit tests | the kit's bars as they are |
| Easy to undo? | yes | yes |

## Decision 4: Loads by flight (the route page and Routes' story)

**Today:** a table with one row per flight number: way, departure, average load (already drawn as a bar in the cell),
flights, and 95%+. Usually 2–6 rows.
**Recommendation: A, leave it.** It already has a bar in each row, and each row is a flight he may retime or drop. A
chart adds little with this few rows.

| | A. Leave it as it is | B. Load by departure time |
|---|---|---|
| What he sees | as today | a bar for each flight at its time of day, out and back in two colours, with a line at 95%: morning and evening peaks show |
| Weakness | none new | with 2–4 flights most of the day axis is empty |
| Effort | none | part of the second pull request |
| Easy to undo? | — | yes |

## Not his choice: one sensible way
- **Connections** become mirrored bars: city pairs down the middle, feeding to the left, onward to the right, one chart
  for each end of the route. "The top 8 of 23" stays under it. Grouped bars would also work, but the mirror shows each
  pair's balance without comparing two numbers. A new kit layout with unit tests.
- **A shared pair's money** (the route page, 2 rows of exact revenue and profit) stays a table: there's a chart above it
  already.
- **Every new chart works as the kit's do:** the chart shows first unless this browser chose the table; "show as table"
  is remembered per board (`eq.showTable.<board>`). The route page and Routes share each board's choice because they
  share the component. A click opens the chart full size; text is 11 px or more; colours are the glass chart colours,
  with ours in the airline's `livery_color`.
- **The checks:** each new layout gets unit tests in `ui/charts/charts.test.ts`. The rehearsal
  (`tests/planner_next_test.py`) reads these tables' rows today, so it will check the chart and flip to the table for
  the rows.

---

## The inventory

Counted in the code on 12 Nov (`<table>` in `app/planner/src/screens/`): **47 tables on 8 screens**. Home and Photos
have none. The count is the same at the 11 Nov commit, so the glass look removed none; the "51" on 11 Nov was counted
another way. Some tables are drawn several times on screen (one per airline or per direction), so he sees more than 47.

a = already a chart with its table one tap away · b = should become a chart · c = better left a table · d = could gain a
small chart beside it.

| Screen | Tables | a | b | c | d |
|---|---|---|---|---|---|
| Performance (with the route page) | 16 | 5 | 4 | 5 | 2 |
| Reference | 8 | 0 | 0 | 8 | 0 |
| Tails | 6 | 1 | 0 | 5 | 0 |
| Systems | 6 | 1 | 0 | 4 | 1 |
| Today | 4 | 1 | 0 | 2 | 1 |
| Competition | 3 | 3 | 0 | 0 | 0 |
| Interline | 2 | 0 | 0 | 2 | 0 |
| Routes | 2 | 0 | 0 | 2 | 0 |
| **All** | **47** | **11** | **4** | **28** | **4** |

### Performance (16)
| Table | Rows × columns in use | What he does with it | Sort |
|---|---|---|---|
| Profit by day (airline) | 14 × 9 | reads a trend | a: bars |
| Route profit (airline) | 20–60 × 10 | compares routes, adds to the fare plan | a: bars of profit an aircraft hour |
| Aircraft (airline) | 5–20 × 7 | compares aircraft | a: bars, the table folded under them |
| Fare plan (airline) | 0–15 × 9 | reads, removes a row | a: timeline |
| Fare results (airline) | 50–200 × 9 | reads what each repricing did | a: a dot per direction above the table |
| Fare changes (airline) | up to 12 × 4 | reads whether a raise cost load | **b**: bars of load change per fare change, coloured by fare up or down |
| Rival fares (route page, Routes) | 3–8 × 5, each way | compares airlines | **b**: decision 2 |
| Rivals on the pair (route page) | 2–8 × 4 | sees who is growing | **b**: decision 3 |
| Connections (route page) | up to 10 × 3, each end | sees which cities the route feeds | **b**: mirrored bars |
| Loads by flight (route page, Routes) | 2–6 × 6 | compares its flights | d: already a bar in each cell (decision 4) |
| Hub readiness (group, folded in Main hubs) | 3–9 × 5 an airline | reads how many cities feed each bank | d: a bar in "cities flying", the planned ones lighter |
| Growth lists: ready, sold out, fix, aircraft losing (group) | up to 10 × 5–7 each | picks a route to act on | c: action lists; the stacked bar above already counts them |
| Ready for another flight, from loads (group) | up to 10 × 6 | adds a flight from a row | c: has **Add** per row |
| Reduce, from loads (group) | up to 10 × 4 | picks a route to cut | c: action list |
| Fare ladder routes (airline) | 10 shown of 20–80 × 7 | copies each move into the game | c: exact game actions; the week's stacked bar sits above |
| A shared pair's money (route page) | 2 × 7 | reads exact money | c: a chart sits above it |

### Today (4)
| Table | Rows × columns | What he does | Sort |
|---|---|---|---|
| Orders | 6 + lines × 5–7 | reads when to order | a: timeline |
| Aircraft to file | 0–6 × 7 | files each, row by row | c: **File into planner** per row |
| Game check differences | 0–20 × 5 | fixes each, row by row | c: per-row fixes |
| Coming up | 5–25 × 2 | reads what's next | d: a 14-day strip of marks over the list |

### Tails (6)
| Table | Rows × columns | What he does | Sort |
|---|---|---|---|
| The list | 5–25 × 8 | picks an aircraft | a: bars of block hours |
| An aircraft's flights | 4–20 × 8 | reads and edits legs | c: the week strip above is already the chart |
| A plan card's legs (Deliveries) | 4–14 × 6–8 | copies times and fare levels into the game | c: exact figures |
| Deliveries | 0–20 × 8 | opens a plan card | c: Today's Orders timeline already shows arrivals |
| File check | 4–14 × 5 | checks before filing | c: row by row |
| The aircraft pop-up's flights | 4–20 × 6 | reads | c: the pop-up's week strip shows the day |

### Systems (6)
| Table | Rows × columns | What he does | Sort |
|---|---|---|---|
| Capture | 6 × 8 | checks each night | a: the 14 nights' heat strip beside it |
| Evening capture (Systems board) | 6 × 3 | checks status | c: six status lines |
| Fleet | 5–25 × 10, per airline | finds problems | d: a maintenance bar in the cell against the limit (problems are already pills; low value) |
| Cabin charges | 0–10 × 7 | fixes row by row | c: **Use the game's amount** per row |
| Nightly log | 7 × 7 (folded) | checks what was entered | c: an entry check; the cash trend lives on Performance |
| Paste preview | 10–60 × 5 | checks a paste before saving | c: row by row |

### Reference (8), Competition (3), Interline (2), Routes (2)
- **Reference:** hubs and banks, aircraft types, own order cabins, configs, markets, service profiles, night bans, game
  schedules. All c: edit boxes in every row.
- **Competition:** threats (group and airline) and order books. All a: timeline and bars, table one tap away. (The
  openings table sits under its scatter: a.)
- **Interline:** agreements and countries. Both c: he sets status and partner row by row; the tiles by status already
  count them.
- **Routes:** a frequency's connections and the route pop-up's frequencies. Both c: exact times he schedules from.

## What would change the recommendation
- If he'd rather see a change on a screen he opens every day first: **1B**, Today's Coming up (one small pull request),
  then the route page.
- If he wants charts even where a table is the working tool (the fare ladder's routes, growth lists): those would be
  "d", a small chart beside the table, never a replacement, because he copies those figures into the game or acts on
  each row.
- If the overlap in Rival fares B doesn't bother him and he wants business on the chart: **2B**.
- If a route he watches has 5 or more flights a day: **4B** becomes worth it.

## Outcome
<Gitesh's decision and the date>

# Spec: the aircraft evaluation script — 27 Oct 2026

*From the Scheduling chat, for the Building chat. Gitesh's decisions of 27 Oct. Gitesh brings the tool's saved pages
(the form and one result) to the Building chat directly.*

## What and why
**What:** a userscript that runs the game's **aircraft evaluation tool** over a list of routes, one route after
another, and collects what the tool shows for every aircraft on each route (at least the seats that fit and the
margin %).

**Why:** the default line (manual §3) picks variants by the game's published ranges, which are at full load with each
type's maximum seats. Our cabins carry 19–41% fewer seats, and the game flies them further: 9M-AAY (KUL), an A320neo
LIGHT with 147 seats, flies KUL–Beijing (4,414 km), 20% past its published 3,690 km, with every seat sold and no cargo
cut. Across about 4,000 captured flights the game never cut seats or cargo for distance. Real ranges would move many
routes to a cheaper variant (SHARP instead of Heavy, A321neo LIGHT instead of LR or XLR: 3–9M of list price each).
The same runs also say which aircraft earns the best margin at each distance. The Scheduling chat turns the results
into a proposed new reach column for §3, a rule change for Gitesh to decide.

## How the tool works (Gitesh, 27 Oct)
- Select a route, select the aircraft (all of them can be selected at once), select the economy seat type, run.
- One run shows the analysis for every selected aircraft together.
- For the next run only the route changes; the aircraft and seat type stay as they were.

## The runs (about 520)
Built by the Scheduling chat once the input format is fixed, sorted by pass and then by distance:

| Pass | What | Runs | Seat type |
|---|---|---|---|
| 1. Distance ladder | A real pair from our route lists every 250 km from 1,000 to 16,000 km, and every 100 km within ±1,500 km of each type's published range | about 120 | by distance (below) |
| 2. Second region | Another pair at each ladder distance, in a different region, so market effects can be told apart from the aircraft | about 120 | by distance |
| 3. Real decisions | Every November trunk and each airline's top 20 openings (`competition()`) | about 200 | by distance |
| 4. Ryanair | Routes up to about 5,000 km again, Standard seats | about 80 | Standard |

**Seat type by distance** (manual §5): Leisure under 3,500 km, Leisure Plus from 3,500 to under 6,500 km, Comfort from
6,500 km. Within passes 1–3 the rows run shortest first, so the seat type changes only twice; pass 4 sets Standard once.
Each row in the list carries its seat type, and the script sets it whenever it differs from the last row's.

**Aircraft:** all 13 selected every run: E195-E2, E190-E2, A320neo SHARP, A320neo LIGHT, A320neo, A320neo Heavy,
A321neo LIGHT, A321neo, A321LR, A321XLR, A350-900, A350-1000, A350-900ULR.

## What the script does
- **Started by Gitesh and watched,** like the fares userscript (manual §5): a button in the tool's page, which shows
  how many runs are left and asks once before starting. Never on a schedule.
- **Read only:** it fills the tool's form and reads the result. It never changes anything in the game.
- **Paced:** a few seconds between runs (the fares script uses 2 seconds), so it doesn't load the game's servers.
- **Stop and resume:** a Stop button throughout; run again, it carries on from the first route without a result. A
  page reload carries on too.
- **Stops at the first problem** and says which route and why (a route the tool won't take, a page that doesn't read).
- **Keeps everything the result shows** for each aircraft, not just seats and margin (the raw row as well as the
  parsed fields), so nothing needs re-running if another figure turns out to matter.

## Where the run list comes from and the results go
The Building chat's choice. Suggested, following the fares script's pattern (`capture_fare_actions()` with the capture
key): the run list in a table, read by the script through a function with the capture key, and results written back
through another, so the Scheduling chat reads them straight from the database. A new table grants its own access
(manual §1). A CSV in and out is the simpler fallback if that's much more work.

## Checks
- Gitesh's saved pages (the form and one result) become test fixtures, and the script's reading of them is checked on
  every pull request like the other userscripts (manual §1, automatic checks).
- The usual: documents updated in the same pull request (map, planner guide if it touches the planner,
  `scripts/README.md` or the userscript's notes, `database/current/` for a new function).

## Rules this touches
- **Manual §9 (Gander is an exclusive world)** lists the scripts allowed there. This one would be added; it's read-only,
  like the world scanner. That's a rule change for Gitesh to agree when the pull request is ready.

## Out of scope
The analysis: the Scheduling chat reads the results and proposes the new reach column and any variant changes.
The 151-run workbook of 27 Oct (`aircraft-range-tests.xlsx`, one row per route and aircraft) is replaced by this list.

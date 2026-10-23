# Keeping each scan's rivals by pair — 23 Oct 2026

**Decision:** whether to keep a small summary of who flies each city pair, so a route's rival history survives the
monthly archive.

**Recommendation: C.** Keep, for good, each airline's weekly departures on every pair in the world from **one scan a
week** (the first finished scan on or after each Saturday). The route page reads the full schedules for the last month
as now, and the weekly summary before that.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Every scan, every pair, kept for good | none | none | none | about 155 MB a year | reaches the 350 MB trigger (§1) in under two years on its own | yes |
| B. Every scan, only pairs on our route lists | none | none | none | about 45 MB a year | a pair added to a list later has no history | yes |
| **C. One scan a week, every pair, kept for good (recommended)** | **none** | **none** | **none** | **about 20 MB a year; one small build** | **weekly points only before the last month** | **yes** |
| D. One scan a week, only pairs on our route lists | none | none | none | about 6 MB a year | as B | yes |
| E. Nothing: the history stops at about a month | none | none | none | none | the route page's rival line is cut at one to two months | — |

## Background
**The gap.** The monthly archive deletes the world scans' full schedules once they are more than a full calendar month
old (manual §7). The route page's *Rivals on the pair* (`route_story()`) reads those schedules for each scan since
launch, so from 1 December its line reaches back only one to two months. Every other figure the planner and the report
use reads the daily history or the scan totals kept for good (`scan_airline_airports`, `scan_airline_markets`).

**The size** (scan 7, 23 Oct): 3,867 airline-and-pair rows in the whole world; 1,138 on the 6,497 pairs on our route
lists. At about 110 bytes a row with its index: every scan, every pair, about 155 MB a year; one a week, about 20 MB.
The database is 96 MB today, against the 350 MB trigger.

**Why every pair and weekly.** A pair joins a route list when we decide to open it, often long after rivals started
there; keeping every pair means its history is already there. Weekly points are enough for a share line over months;
the last month keeps every evening's scan as now.

**The build.** A table `scan_pair_airlines` (scan, world, airline, pair, weekly departures each way), filled at the
scan's finish when it is the week's kept scan, and filled back from the scans still held; `route_story()` reads it for
scans whose schedules are archived. With the connections build (`docs/specs/2026-10-23-rival-connections.md`) it
fits after that one, since both touch the scan's finish.

## What would change the recommendation
- **Gitesh wants daily points for good on the pairs we fly:** B.
- **The database nears the 350 MB trigger for other reasons:** D.

## Outcome
**C, 23 Oct (Gitesh, Building chat):** one scan a week (the first finished scan on or after each Saturday), every pair
in the world, kept for good. Built after the rival connections pull request.

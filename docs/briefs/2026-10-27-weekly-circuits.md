# New aircraft: weekly circuits instead of 24-hour days? — 27 Oct 2026

*Scheduling chat. Gitesh asked whether new aircraft should be planned as 168-hour circuits, with several aircraft
flying one weekly schedule, instead of each aircraft repeating the same 24-hour day. Existing aircraft are out of
scope. Figures: block times and turns by manual §4, maintenance by the planning library's model
(`lib/rules/src/maintenance.ts`), with each type's figures from `aircraft_types`. The working is in the scratchpad
script `circuits.py` (rebuild from this brief if needed).*

## Decision and recommendation
**Recommendation: C, circuits for long haul only.** New aircraft whose round trip runs past about 20 hours (the A350s
and the longest A321XLR routes, November's long-haul trunks above all) are planned as multi-day circuits: a small pool
of the same type flies the airline's long-haul routes in one weekly pattern, each route daily, ending some days at
another of its hubs. New narrowbodies keep the 24-hour day.

Why: a short-haul day already packs to within minutes of 24 hours, so a circuit gains almost nothing there, and it
costs a lot of setup. Long haul is where the 24-hour day breaks: a 25-to-32-hour round trip can't repeat daily on one
aircraft, so every such route needs two aircraft for a daily service. Pooled in circuits, the same routes need about a
third fewer A350s.

## Options

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. 24-hour days for everything new (today) | as now | as now | as now | long-haul routes need 2 A350s each for a daily | none new | — |
| B. Weekly circuits for every new aircraft | under 2% more flying on narrowbodies | a few % at most on narrowbodies | a pool waits for 7 aircraft of one type at one base | about 7 times the game entries per aircraft; new routes wait for the pool to fill; a new optimiser to build | high: one aircraft late or wrong breaks the whole week | hard once flying |
| **C. Circuits for long haul only (recommended)** | **every long-haul route daily with about 30% fewer A350s** | **about 0.72M a week saved per A350 not needed (its lease), or one more daily long-haul route per 1.0–1.3 aircraft saved** | **each A350 not ordered keeps its price (140.1M list) in hand** | **small pools (2–5 aircraft) built by hand until a circuit optimiser exists** | **medium: a pool waits for its aircraft (one every 30 hours on the A350 line)** | **yes, before the A350s are ordered** |
| D. Weekly schedules with routes under daily (thin routes 3–5 a week) | fewer empty seats on thin routes | small | none | fewer departures, so less market share, and some days with no connection | against manual §3 (market share first) and §9 (more departures win more of a market) | yes |

## Background

**Short haul: the 24-hour day is already nearly full.** The best daily days for a new A320neo SHARP at Mumbai, back at
base each night, with turns at 76 minutes and one maintenance stop:

| Day | Block | Minutes left over |
|---|---|---|
| Bangkok twice | 16.1 h | 34 |
| Riyadh, Bangkok | 15.5 h | 73 |
| Hyderabad, Bengaluru, Bangkok | 13.2 h | 6 |
| Bengaluru twice, Riyadh | 13.1 h | 14 |
| Chennai, Kolkata twice | 12.9 h | 26 |

A circuit's whole gain is those few minutes, under 2% of the day; it can't give more than 24 hours a day either. The
two E195 cards of 26 Oct (9M-ABB (KUL) 13.4 h, G-AAFL (LGW) 13.2 h) were also within 20 to 35 minutes of full.

**Maintenance doesn't change.** The need is per departure and per hour flown, and each stop that counts must be at
least the type's ground keep plus 120 minutes. One long stop a week costs about the same ground time as one shorter
stop each day (an E195 on six legs a day: about 1,060 minutes a week either way).

**Long haul: the 24-hour day breaks.** A350-900, one round trip with turns and its maintenance:

| Route | km | Round trip | Aircraft for a daily |
|---|---|---|---|
| Dallas–Gatwick | 7,660 | 22.9 h | 0.96 |
| Gatwick–Seattle | 7,742 | 23.1 h | 0.96 |
| Gatwick–San Francisco | 8,655 | 25.1 h | 1.05 |
| Los Angeles–Gatwick | 8,798 | 25.4 h | 1.06 |
| Beijing Daxing–Seattle | 8,741 | 25.3 h | 1.05 |
| Shanghai–San Francisco | 9,877 | 27.8 h | 1.16 |
| Los Angeles–Shanghai | 10,415 | 29.0 h | 1.21 |
| Kuala Lumpur–Gatwick | 10,594 | 29.5 h | 1.23 |
| JFK–Beijing Daxing | 11,044 | 30.5 h | 1.27 |
| Delhi–JFK | 11,755 | 32.1 h | 1.34 |

With 24-hour days, every route over 24 hours needs 2 aircraft for a daily (as Delhi–JFK did: VT-AAA (DEL) and VT-AAB
(DEL) at 11.4 h a day each). These twelve routes (the eleven above and Gatwick–Chicago) need 20 aircraft that way, or
13.1, so 14, pooled. The real pools are smaller, since each pool is one airline and one type (Pan Am's US–Europe and
US–China trunks, say), so each rounds up on its own: three routes at 1.05, 1.06 and 1.16 take 4 aircraft pooled
against 6. A circuit can also end a day at another of the airline's hubs (San Francisco to Gatwick, Gatwick to Los
Angeles), which a 24-hour day can't.

**What already works.** The planner's legs carry their own days (`days_utc`); Delhi–JFK flew on 3-day patterns.
The card check, Tails, filing and the capture's checks read legs by day, and the library's aircraft report tracks
where each aircraft is across the week. **What doesn't:** the optimiser builds one aircraft's 24-hour day. A circuit
optimiser (several aircraft, several days) would be a Building chat job; small pools can be planned by hand and
checked with `check-card` meanwhile.

**Setting it up in the game.** A daily aircraft is about 6 flights, each flown all 7 days. A circuit aircraft has
different flights on different days, so each one needs more entries, by about 7 times on a full 7-aircraft
circuit. Long-haul pools are small (2 to 5 aircraft, 2 to 4 flights a day), so this stays manageable there.

## Scenarios and the risk of waiting
- Nothing needs deciding before the first A350 order. November's trunks open shortest first, so the A350 trunks come
  last (manual §4), probably mid-to-late November.
- Deciding now lets each long-haul order be sized for its pool, rather than ordering 2 per route and finding the
  spare hours later.

## What would change the recommendation
- **The game's schedule editor makes per-day flights much easier than expected:** circuits for wide narrowbody pools
  too (B), for the few % gained.
- **Long haul is dropped or delayed past November:** A until it comes back.
- **A circuit optimiser gets built:** larger pools, more of the gain.

# Spec: long haul in 7-day lines — 27 Oct 2026

*From the Scheduling chat, for the Building chat. Gitesh's decision of 27 Oct (option B of
`docs/briefs/2026-10-27-long-haul-lines.md`). Build after the short-connections planning target
(`docs/specs/2026-10-27-planning-connection-target.md`, to-do 179): the line optimiser scores by the same target.
Probably 3–4 pull requests; each on its own branch, with its tests and documents, as usual.*

## What and why
Routes whose round trip (with turns and a maintenance stop) doesn't fit in a day, those beyond about **7,750 km**
(nearly every A321XLR route and every A350 route), are flown by **7-day rotating lines**: 7 aircraft of one type at
one airline fly one weekly pattern, each a day apart, so every route on the line flies daily at the same time.
Beyond that distance one aircraft can't fly a route daily and a pair gives only 6 a week. XLR lines first; A350 lines
wait for the narrowbody-against-A350 question. Shorter routes keep the 24-hour day. Gitesh wants none of it done by
hand, so the planner and the library carry it from planning to filing.

**How a line works.** Line days 1 to 7, each 24 hours of one aircraft's flying, chained: day 2 starts where day 1 ends
(often away from base), and day 7 ends where day 1 starts. Aircraft k flies line day d on weekday ((d + k − 2) mod 7)
+ 1, so on every weekday each line day is flown by exactly one aircraft and every flight on the line operates daily at
the same time. Because the game repeats each aircraft's week, a rotating line must be exactly 7 days and 7 aircraft.
In the game Gitesh sets up each aircraft with the schedule editor's copy and offset.

## Settings (new rows, with descriptions; manual §1, one source)
- `line_min_km` = 7,750: routes at or beyond this go on lines (the Scheduling chat's choice of which routes; nothing
  enforces it automatically).
- `maintenance_max_gap_h` = 40: the longest stretch between two stops that count for maintenance (the stop rule as in
  `lib/rules/src/maintenance.ts`). Gitesh, 27 Oct: condition can fall below 50% with only one long stop a week.
- `line_aircraft` = 7.

## 1. Line optimiser (planning library, `optimise-line`)
**In:** the airline, the aircraft type, the hubs the line may start or end days at, the candidate routes (long ones and
medium fillers), optionally fixed routes that must be on it.
**Out:** the best 7-day line: each leg's line day, departure (UTC minutes, local at each end), block, flight number
from the airline's pool (checked against `flight_legs` and `plan_card_legs`), service code; and the 7 aircraft cards
with their weekday offsets.
**Feasible when:** turns (type's turnaround plus the margin), night bans, the same-route gap (§9), every route within
the type's reach (§3, `aircraft_types.range_km`, asking first being the Scheduling chat's job), maintenance at or above
100% on the week, no stretch longer than `maintenance_max_gap_h` without a counting stop, the line closing on itself
after 168 hours, each route flown both ways the same number of times.
**Scored by:** connections within `plan_connection_target_h` at the hubs (the short-connections spec), then all
connections up to `connection_max_wait_h`, then routes covered, then block hours, then maintenance.
**Search:** the order of the legs and each day's start; the ladder of bank departure times at each hub is a good set of
candidate times. Exhaustive search won't scale past a handful of routes; a heuristic (greedy chain through the banks,
then local swaps) with a cap on run time is fine, as long as it returns the best it found and says so.
Reference: the Scheduling chat's hand-built sample of 27 Oct (Pan Am, A350-900, SFO–LGW, LGW–SEA, SEA–PKX, SEA–LGW,
LGW–LAX, LAX–LGW, SFO–PVG, PVG–LAX, LAX–PVG, PVG–SFO: 12 legs, 17.7 h a day each, maintenance 193%, a counting stop
at most every 39.6 h, US departures in their banks); a good test case.

## 2. Lines in the planner
- A line: a row (`plan_lines`: airline, aircraft type, name, created from which optimiser run) and its legs by line day;
  plan cards carry `line_id` and `line_day_offset`.
- When an aircraft of the line is ordered, its card is written from the line with the next free offset (the order
  logging in the Scheduling chat, or the planner's card screen).
- Tails → Deliveries and the card screen show the line: its 7 slots, which are ordered, arrived, filed.

## 3. Card check across a line
- Each card as today, plus: the maintenance spacing (`maintenance_max_gap_h`) on every card, lines or not.
- Across the line: every leg operates daily once all 7 cards exist (and which days are missing until then); the same
  flight number on different days of different cards is not a clash; each route flown both ways every day.

## 4. Filing, Game check, route profit
- **Filing** compares each line aircraft's game schedule with its card day by day, and pairs a flight with its return
  when the return is on another day (today it pairs within the day as a round trip).
- **Game check** compares each aircraft day by day.
- **Route profit** counts a line route's aircraft hours across the aircraft that fly it (manual §3, profit per aircraft
  hour).
- Anything else that assumes an aircraft repeats one day (the capture's loads check by aircraft, Tails' block hours a
  day, the connection audit): check with a saved line and fix what misreads it.

## 5. Pool progress on Today → Orders
Each open line: "XLR line, Pan Am: 3 of 7 ordered (2 arrived)", and when its next aircraft can be ordered by the cash
forecast.

## 6. Tests
A saved sample line (the A350 sample above, or an XLR one) through every check: the optimiser's answer as a saved
answer, the line card check, filing day by day, Game check, route profit, the maintenance spacing on a card with a
78-hour stretch (the first sample's fault) marked.

## Documents
Manual §4 (long haul in lines: the rule, the settings), §3 (ordering a line's aircraft), the planner guide, the map,
`lib/rules/README.md`, `scripts/README.md`, rule history. Until the last pull request merges, the manual lists this
under Decided, not yet built.

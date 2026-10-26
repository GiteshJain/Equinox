# The fare ladder per direction — 26 Oct 2026

**Decision:** whether the fare ladder sets one level per route and cabin (both directions together) or one per direction.
**Recommendation:** A, a level per direction, because passengers book each direction separately and the game prices each
direction on its own, so one level for both leaves money on a direction that sells out.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A. A level per direction** | none directly | up: a direction that sells out climbs 5 points (7 for Pan Am and China Eastern) without waiting for the other; this week 24 routes | no change | a build of about half a day (the Building chat's helper) | more rows on the ladder and more changes in the game each Saturday | yes: the levels can be set equal again |
| B. One level per route (as now) | none | as now | no change | the climbs above | none new | — |

## Background
- **How the ladder works now** (manual §5): each cabin of each route has one level; every Saturday it goes up 5 points
  when every flight of the week sold out, holds at 90–99% sold out, and goes down 5 points under 90%. Both directions'
  flights are counted together.
- **How the game works:** passengers book each direction separately (manual §9), and Ticket price adjustment changes
  one direction at a time (From A to B). The fares userscript already makes each direction a separate change, at the
  same level.
- **What the data shows** (captured flights of the 7 days to 26 Oct, economy, routes with at least 5 flights each
  way, `game_flights`): 266 routes; on **24**, one direction sold out every flight while the route as a whole didn't, so
  that direction missed its climb; on **7**, the route stepped down although one direction was at 90% or more. Virgin's
  EDI–MUC: 11 of 14 sold out (hold), averaging 99% full one way and 100% the other.
- **Competition:** unchanged; the rival pause stays the whole route's.

## Scenarios and the risk of waiting
- **A, going well:** each direction finds its own level; the strong direction earns its 5 points a week sooner.
- **A, going badly:** a direction priced up loses connecting passengers who fly the other way at the lower fare; the
  ladder's own hold and step down catch it a week later.
- **Waiting:** each Saturday about 24 directions don't climb.

## What would change the recommendation
- If the game priced a route as a pair (it doesn't: each direction is its own change).
- If one-way passengers were a small share (they aren't: bookings are per direction).

## Outcome
**26 Oct 2026, Gitesh: A.** Each direction of each cabin of each route gets its own level, judged on its own flights:
up, hold, down, the hold after a step down, the under-launch jumps and the set-back each per direction; the capacity
hold after a new frequency and the rival pause stay the whole route's; each direction starts from the route's level
when it's built. Recorded in the operating manual under *Decided, not yet built*; §5 is rewritten when the build
merges. Spec: `docs/specs/2026-10-26-fare-ladder-per-direction.md`.

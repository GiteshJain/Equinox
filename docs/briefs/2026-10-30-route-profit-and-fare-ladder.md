# Route profit's marks and the fare ladder: one answer per route? — 30 Oct 2026

*Building chat. Gitesh asked on 30 Oct whether route profit and the fare plan conflict. Figures: `route_profit(<airline>,
7)` and `fare_ladder(<airline>)` for all six airlines, economy, 30 Oct 18:59 UTC (7 days to that moment). Rules: manual
§3 "Add a flight or raise fares, by profit per aircraft hour" and §5 "The fare ladder, every Saturday".*

## Decision and recommendation
**Decision:** what route profit's sold-out marks should say, now that the fare ladder raises every sold-out direction
by itself each Saturday.

**Recommendation: B.** Route profit keeps **add a flight** (sold out and earning at or above the airline's middle route
per aircraft hour: the routes the Scheduling chat should add frequency to first) and drops its own **raise fares** mark.
A sold-out route below the middle shows **sold out · fares climbing** with the ladder's move for each direction beside
it, so every screen gives one answer on price: the ladder's. Nothing in the ladder changes.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Keep both, show the ladder's move beside route profit's mark | none | none | none | the two still read as two answers | confusion stays | yes |
| **B. Drop "raise fares"; route profit shows the ladder's move (recommended)** | **none: add a flight stays for frequency** | **none: the ladder already raises these** | **none** | **none** | **low** | **yes** |
| C. The ladder holds a route marked "add a flight" until the flight is added | more seats sold at today's fares | about −5.5M a week at each step not taken: the 164 routes marked add a flight earn 111M a week, and a 5-point step is about 5% of it | lower | fares stay low on our best routes while aircraft are found | high: 164 routes, far more than the order lines can add flights to | yes, but the lost steps don't come back |
| D. Route profit's mark decides the ladder (raise only where marked raise fares) | as C on the add routes | as C | as C | as C | as C | yes |

## Background
**Nearly everything sells out.** Of 344 routes with figures over the 7 days, 315 are sold out: 164 marked add a flight
(111.1M income, 70.1M profit, economy 99.9% full) and 151 marked raise fares (52.8M income, 28.8M profit, 99.7%). 24 are
held (82.6%) and 5 marked fix (48.3%).

**How the two line up** (economy; a route's directions can move differently, shown as "hold/up"):

| Route profit | Ladder | Routes |
|---|---|---|
| add a flight | up | 140 |
| add a flight | hold, or hold one way and up the other | 24 |
| raise fares | up | 109 |
| raise fares | hold, or hold/up, down/up | 42 |
| hold | hold, up or down | 24 |
| fix | down, or down/hold | 5 |

- **Where they agree** (raise fares and up, fix and down): 114 routes.
- **Where they seem to differ but don't:** raise fares and a ladder hold (34) is the ladder's own reasons to wait: the
  hold after last week's step up, a rival starting on the pair, a frequency added that week, or the cap. Route profit's
  hold against a ladder move (9) is route profit judging the whole route both ways together and the ladder judging each
  direction, so one way can sell out while the route doesn't.
- **The real overlap:** add a flight and up (140). Route profit's two marks were meant to choose between more flights
  and a higher fare (manual §3, 17 Oct), but since 21 Oct the ladder raises every sold-out direction whatever the mark,
  so "raise fares" repeats the ladder and "add a flight" reads as "don't raise", which nothing acts on. In practice they
  don't fight: adding a flight holds the ladder on that route for a week (§5, the capacity hold).

**Why not C or D:** with 164 routes marked add a flight and three delivery lines per airline, most of those routes wait
weeks for a flight; holding their fares meanwhile gives up the biggest step-ups we have. Market share first (§3) is met
by adding flights, which the capacity hold already protects.

## Scenarios and the risk of waiting
- **B goes well:** one price answer everywhere (the ladder's); route profit's add a flight becomes a clean shortlist for
  the Scheduling chat. **Badly:** nothing changes in money; at worst a screen loses a word Gitesh used.
- **Waiting:** no money at stake, only the two-answers confusion on Performance, the route page and the weekly report.

## What would change the recommendation
- If loads start falling below 90% on routes marked add a flight after a few steps up, the ladder is already finding the
  price ceiling there, and the add list should shrink by itself; nothing to change.
- If we want market share over fare on specific pairs (a contested trunk, say), that's a rule for those pairs (a lower
  cap), not C.

## What gets built (B)
`route_profit()`: a sold-out route below the middle gets mark `sold_out` (words "sold out · fares climbing") instead of
`raise`; Performance, the route page, Routes' story and the weekly report show the ladder's move per direction beside a
sold-out route. Manual §3's sentence replaced; rule history logged. One pull request with a small migration.

## Outcome
**30 Oct 2026, Gitesh: B.** Manual: *Decided, not yet built* until the pull request merges, then §3's sentence is replaced.

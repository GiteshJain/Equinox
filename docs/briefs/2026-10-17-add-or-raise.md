# Add a flight or raise fares: what "earning well" means — 17 Oct 2026

**Recommendation and outcome:** B. A sold-out route gets "add a flight" when its profit per aircraft hour (block time
plus the type's turnaround and the 10-minute turn margin) is at or above its airline's middle route, and "raise fares"
when it's below.

## The question
Gitesh, 17 Oct: don't look only at profit per flight on a route, but at profit per hour it blocks the plane. Today a
sold-out route is marked add when its profit per flight is at or above the airline's median route, raise fares when
it's below (`private.fig_route_profit`, `settings.growth_sold_out_share` 0.8, `growth_sold_out_min_departures` 4).

## Options, on last week's 180 sold-out routes (captured flights, 10–17 Oct)

| Option | The plane's time | Routes that change mark | Effect |
|---|---|---|---|
| A. Profit per block hour | Gate to gate | 85 | 34 short hops (under 1.5 h) to add, 9 long routes (4 h+) to raise; a 50-minute hop ties the aircraft up for about two hours with its turn |
| **B. Profit per block hour plus turn** | **Block + turnaround + 10 min** | **36** | **14 short routes to add, no long route to raise** |
| C. Profit per flight (today) | – | 0 | Long routes favoured |

No cash effect: the mark decides where the next aircraft and the fare tests go. Easy to undo.

| Route | Block, profit a flight | Today | A | B |
|---|---|---|---|---|
| JFK–Washington Dulles | 0.9 h, 11k | raise | add | raise (5.3k an aircraft hour vs Pan Am's 5.9k) |
| JFK–Frankfurt | 7.8 h, 54k | add | raise | add |
| Paris–Amsterdam | 0.9 h, 9k | raise | add | add |
| Delhi–Bhopal | 1.1 h, 16k | raise | add | add |
| Delhi–London Heathrow | 8.4 h, 58k | add | raise | add |

**Risk with B:** the turn is the planned minimum, not the real ground time; waiting for a bank isn't charged to the
route. **What would change it:** if turns at hubs run long enough that real ground time matters, use each aircraft's
actual ground time instead.

## Outcome
**17 Oct: B.** Rule in the manual (§3, and *Decided, not yet built* until the Building chat builds it).

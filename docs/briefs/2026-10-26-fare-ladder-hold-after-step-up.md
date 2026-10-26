# The fare ladder after the 3-day booking window — 26 Oct 2026

**Decision:** how the Saturday fare ladder should judge a direction whose fare it changed the week before, now that
fare changes only reach flights booked after them.
**Recommendation (Gitesh's own proposal, agreed):** a direction that steps up holds the next Saturday; every other
direction stays weekly. Each move is then judged on a full week at its new price, with a small build.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A. Hold one week after a step up** (chosen) | Sold-out routes climb every 2 weeks: the cap (+20, or +28 for Pan Am and China Eastern) in about 8 weeks | Slower gains on routes that keep selling out; no overshoot from judging old prices | No effect | About 4 extra weeks to the cap on routes that keep selling out | Low: every move is judged on a clean week | Yes: one `settings` row |
| B. Judge only flights flown at the current level | Sold-out routes can climb weekly: the cap in about 4 weeks | Fastest gains | No effect | Larger build (filter flights by fare) | Medium: as few as 4 days of evidence, missing some weekdays | Yes, but more code |
| C. Two-weekly ladder for every direction | Every route moves every 2 weeks | Slower everywhere, including routes that held at a stable price | No effect | Directions that didn't move wait a week for nothing | Low | Yes |
| D. Leave it | Routes can climb two steps in two weeks on old-price evidence | Overshoot caught a week late, loads lost meanwhile | No effect | None | High: the ladder judges the wrong price | — |

## Background
- **The game's booking window** (Gitesh, from the game's documentation, 26 Oct): bookings open 3 days ahead, and a
  fare change applies only to flights not yet booked. Flights already selling fly at the old price. Now in the manual,
  §9.
- **The first full run** (26 Oct evening, fares script 1.2): 463 changes across all six airlines, none failed. The
  first flights at the new fares leave around 29–30 Oct.
- **What 31 Oct would have judged under D:** the week 24–30 Oct, five or six days at the old prices and one or two at
  the new, so routes that sold out at 100% would go up again to 105–110% (107–114% for Pan Am and China Eastern)
  without evidence that the first step still sells out.
- **Loads:** 96–99% for every airline in the week to 23 Oct (weekly report figures), which is why the speed of the
  ladder matters: a slower climb leaves money on routes that are underpriced.
- **Untouched by this decision:** the hold after a step down (already 2 weeks), the under-launch jumps (their 2-week
  hold already starts when the captures see the new fare), the capacity hold, the rival pause and the set-back of
  directions off their level.

## Scenarios and the risk of waiting
- **Demand strong:** under A, a route that sells out at every step reaches the cap in about 8 weeks, against about 4
  under B. If that proves too slow, a larger step for routes that sell out every flight is the fix, not a faster cycle.
- **Demand soft at the new price:** under A, the ladder sees a clean week at the new level and steps down once, a week
  later than B could, but on solid evidence. Under D it could already have stepped up twice.
- **Waiting:** without a decision, 31 Oct judges mostly old-price flights for every direction moved on 26 Oct.

## What would change the recommendation
- Routes reaching the cap too slowly while loads stay at 100%: consider a larger step for directions that sold out
  every flight.
- A change to the game's booking window: the hold's length is a `settings` row.

## Outcome
**Gitesh, 26 Oct (review chat): A**, his own proposal. The manual's §5 now holds a direction for one Saturday after a
step up (`settings.fare_ladder_up_hold_weeks`, 1), logged in `rule-history.md`. Until the Building chat builds it
(*Decided, not yet built*), the review chat holds those directions by hand: on 31 Oct, every direction moved on 26 Oct.

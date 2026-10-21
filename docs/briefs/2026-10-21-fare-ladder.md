# The fare ladder — 21 Oct 2026

**Decision:** how we raise fares on routes that sell out. This is step 2 of the planner work (Gitesh, 20 Oct), and it
changes the fares rule in manual §5.

**Recommendation:** **A, a weekly ladder.** Each Saturday, every route that sold out all week goes up 5% in that cabin.
A route that stops selling out goes back one step and holds there. Each step that holds is worth about **+5M a week**
across the group, and we've never raised a single fare.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A. Weekly ladder:** +5% each Saturday on every route and cabin that sold out all week; one step back when it doesn't | Seats and departures unchanged; full flights stay full | **About +5M** for each step that holds (7% on 72M) | Rises by the same, so orders come sooner | Saturday's fare work grows: maybe 100–200 changes in the game at first | A step too far empties some seats for a week before it's caught | Yes: one step back on the next Saturday |
| B. Twice a week (Wednesday and Saturday) | As A | Reaches the same fares in half the time | Better than A sooner | Twice the fare work | Less data for each decision (3–4 days of loads) | Yes |
| C. Keep today's rule: occasional tests, a few routes a week | As now | Close to nothing: no raise has been captured yet | As now | The 5M a week per step stays unearned | Lowest | — |

## Background
- **Nearly every flight is full.** In the last 7 captured days (14–20 Oct), 88–98% of each airline's economy flights
  sold out, and 98–100% in business (`game_flights`, from the capture).
- **No fare has ever gone up.** Of our 246 city pairs, only 4 have changed fare since 7 Oct, all Ryanair, and all were
  cuts towards its 85% launch fare. The fare plan is empty, and `fare_changes()` finds no change in the window. Every
  route still flies at its launch fare (100% of standard, Ryanair 85%).
- **What a step is worth.** Ticket income on flights that sold out was 85.7M in economy and 17.3M in business last
  week, against 71.6M of flight profit before leases. 5% on that is about **5.1M a week** if the flights stay full.
  The costs don't change: same seats, same fuel.

  | Airline | Economy on full flights | Business on full flights | Flight profit |
  |---|---|---|---|
  | Pan Am | 14.2M | 3.6M | 12.1M |
  | Kingfisher | 9.0M | 2.9M | 9.3M |
  | Ryanair | 19.2M | — | 13.0M |
  | Virgin | 14.8M | 3.5M | 12.2M |
  | China Eastern | 15.4M | 3.5M | 12.3M |
  | Malaysia | 13.1M | 3.8M | 12.7M |

- **What it does for orders.** 5M a week is roughly two more A321neos a week across the group, on top of today's two
  or three a day.
- **Market share isn't touched while flights stay full.** We keep the same seats and departures. The ladder stops
  climbing at the point where seats start going empty, and that's the signal that demand is near our capacity.

## How the ladder would work (the rule, if A)
- **Each cabin of each route separately.** Economy and business each have their own step. Ryanair has economy only.
- **Up a step (+5%)** when every captured flight of that cabin sold out in the week (7 days, at least 5 departures).
- **Hold** when 90–99% of flights sold out.
- **Down a step (−5%)** when under 90% of flights sold out. The route then holds for 2 weeks before climbing again.
- **New routes** start climbing after their first full week (the 7-day rule for new routes stays).
- **Limits:** no cap above. Below, never under launch fare, and the 60% floor still applies where another player flies
  the route. A rival entering one of our pairs (from the scan) stops that route's climb for a week.
- The numbers would be settings: step 5%, up at 100% sold out, down under 90%, hold 2 weeks.

## What the planner would show (step 2's build)
- On Performance, **the fare ladder:** each route and cabin with its fare against its launch fare, how many steps it has
  climbed, last week's sold-out share, and this Saturday's move (up, hold, down).
- **Saturday's fare list:** the changes to make in the game, grouped by airline, with one tap to put them all on the
  fare plan. The next capture sees each change and ticks it off.
- On the route table: the fare index and a 14-day sparkline of loads.

## Scenarios and the risk of waiting
- **If demand is deep** (likely, with 95% of flights full at launch fares): routes climb several steps, and each step
  adds about 5M a week. After four steps, about +20M a week, roughly a quarter more flight profit.
- **If demand is shallow on some routes:** they drop under 90% sold out after one step, step back the next Saturday,
  and hold. The cost is about a week of a few empty seats on those routes.
- **Waiting** costs about 5M a week for each step we haven't taken.

## What would change the recommendation
- **If the game can't change many fares at once,** 100–200 changes on a Saturday may be too much by hand. Then: B
  isn't worth it, and A would start with the 50 routes earning most and widen from there.
- **If higher fares cost us something else in the game,** such as passengers choosing rivals on connecting trips or a
  hit to the airline's image, a slower ladder or a cap would be safer.

## Outcome
**A, the weekly ladder** (Gitesh, 21 Oct). The game changes fares in bulk (**Ticket price adjustment**: from, to,
service profile, + or − %, baseline default price or current, by class), so the work is a handful of actions per
airline, not 100–200. He expects the game's passengers to be price-sensitive and higher fares may hurt image, so the
ladder goes **at most 20 points above launch for now**, lifted only when loads and image show it's safe. Manual §5
updated the same day; the old rule is under Retired rules.

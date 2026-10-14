# Order now, or wait for the new planner — 14 Oct 2026

**Decision:** whether to order the next aircraft now, while the game is paused for the planner rebuild (#18), or
wait until `/planner/` switches to the new planner.
**Recommendation:** B. Order now and let the aircraft arrive while the build finishes. Plan their routes together now,
and schedule them on the new planner the day it switches. Each aircraft's first lease falls 7 days after it arrives,
so a few days parked costs only flying, and the batch flies about three days sooner than if we wait.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Wait: order on switch day | the batch flies 1–5 days after the switch | none until then | unchanged now: 8.9–15.4M | about 3 days of flying on the batch, roughly 4–5M of flight profit | none for the build | yes |
| **B. Order now, park, schedule at the switch** | **20 aircraft flying from switch day** | **~6M once flying (20 × ~45k a day after lease)** | **1.1M (Virgin) to 3.2M (Pan Am)** | the 11 Oct cabin conversions (5.2M) wait | the switch slips: after 7 days parked, each aircraft pays ~34k a day in lease | no: the up-front payment is spent |
| C. Lift the pause: order and schedule now, in the old planner | each aircraft flies about a day after it lands | ~6M, a few days sooner than B | as B | the freeze ends: plan cards and logs go back into the old planner | low; mainly attention split between the game and the build | no |

The batch is what the cash forecast allows today with each order's lease counted (manual §3): three A321neos each for
Pan Am, Kingfisher, Virgin, China Eastern and Malaysia, and five for Ryanair. That's 20 aircraft at about 2.6M each,
cabin included. Which types and how many per airline is the next decision, made one airline at a time. Under hubs first
they all go to the main hubs (Ryanair exempt).

## Background
- **Cash** (database `cash_forecast()`, capture 14 Oct 03:12 UTC). Lowest point in the next 14 days without orders:
  Ryanair 15.4M, Pan Am 11.0M, China Eastern 9.8M, Kingfisher 9.6M, Malaysia 9.4M, Virgin 8.9M. With the batch above,
  every airline stays above the 0.5M cushion. The lowest point after the orders is the day they're paid: Virgin 1.1M,
  Malaysia 1.6M, Kingfisher 1.8M, China Eastern 2.0M, Ryanair 2.9M, Pan Am 3.2M. Planned refits aren't in the forecast:
  the 321-LEI conversions (China Eastern 1.8M, Virgin and Kingfisher 1.2M each, Pan Am 0.8M, Malaysia 0.2M) don't fit
  alongside the full batch at Virgin or China Eastern.
- **What an A321neo earns** (game_flights, 7–13 Oct, median flight profit per aircraft per day): Malaysia 87k,
  Kingfisher 85k, China Eastern 82k, Ryanair 81k, Virgin 73k. The lease is about 34k a day from the 8th day after
  arrival, which leaves about 40–50k a day before crew pay. Payback on 2.6M is about two months.
- **Demand:** 93–99% of flights sold out in economy at every airline that week (Kingfisher 88%).
- **Delivery:** the last big order (45 A321neos on 26 Sep) arrived at about one aircraft per airline per day. Single
  orders since have arrived within a day.
- **The build** (decision #18, design §13): pull requests 1–8 are merged; 9 (Check) is specified; 10–12 (Review,
  Interline, Photos, Reference) and 13 (the switch) remain. Four screens were merged on 13 Oct, so at that pace the
  switch is probably 2–4 days away. That's an estimate, not a date.
- **The rule today** (manual §1, since 12 Oct): the game is paused until the switch, with no orders or scheduling, and
  the old planner is frozen with no data changes by Claude. The 15 A321neos that arrived 6–9 Oct were scheduled on 13 Oct
  as an exception.

## Scenarios and the risk of waiting
- **B goes to plan:** most of the batch lands during the build, sits a few lease-free days, and is scheduled the day
  the new planner goes live. **B goes badly:** the switch slips past a week. Then the aircraft that have waited 6 days
  get scheduled in the old planner, as on 13 Oct, rather than paying idle leases.
- **A:** nothing changes until the switch, and then the batch arrives over the following days. Waiting costs about 3
  days of flying per aircraft, roughly 20 × 3 × 80k ≈ 4.8M of flight profit, most of it in each aircraft's lease-free
  first week.
- **C** earns the most, but ends the pause you set on 12 Oct to keep the game and the build apart.

## What would change the recommendation
- The switch looking more than a week away: C, or a smaller batch.
- Wanting the cabin conversions first: a smaller batch at Virgin and China Eastern.
- Loads on the 15 new aircraft coming in weak over the next two captures: a smaller batch.

## Outcome
<open>

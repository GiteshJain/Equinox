# The fare ladder under launch — 23 Oct 2026

**Decision:** Gitesh wants the fare ladder allowed to go under launch. Today §5 stops every cabin at its launch level
(100%, Ryanair 85%), so a cabin that doesn't sell out holds at launch for ever. The questions are how low it may go,
how fast, and what stops it cutting fares where that loses money.

**Recommendation: C.** Allow the ladder down to a **60% floor** everywhere: the house rule's floor, which already
applies wherever another player flies.
- **Only where a cut can pay:** cabins averaging **under 80% full**.
- **Bigger steps under launch:** **10 points**, judged again the next Saturday.
- **A revenue check:** a step that lowers the cabin's revenue a flight is undone.
- **At the floor and still under 60% full:** the route goes to Gitesh as a cut-or-keep decision, the rule we have
  today ("weak routes get cut rather than launched cheap").

**What it touches today.** Only four cabins, all economy and all uncontested:
- Delhi–JFK, being handed back;
- PVG–Kolkata, 32% full;
- KUL–Thiruvananthapuram, 34% full;
- Delhi–Amsterdam, not enough departures to judge.

So the rule matters less for money now than as the first tool before a cut.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Keep "never under launch"; weak routes go straight to a cut decision | none | no change | none | a route that would sell at a lower fare is cut instead | low | yes |
| B. Same ladder, floor 60%: down 5 points (Pan Am and China Eastern 7), then hold 2 weeks | slow | small; 100% to 60% takes about 24 weeks | none | months at a fare that doesn't fill | near-full cabins (85–89%) get cut and lose revenue | yes |
| **C. Floor 60%; under launch only for cabins under 80% full; 10-point steps judged weekly; revenue check; at the floor and still under 60% full, a cut decision (recommended)** | **reaches a fare that fills within about 4 weeks** | **up to about +0.1M a week a route if demand responds (below); none lost where it doesn't** | **none** | **one helper build** | **demand's response to price is unknown, and the revenue check catches a bad step after a week** | **yes** |
| D. Set the level straight from the load (e.g. a 32% cabin to 60% at once) | fastest | as C, sooner | none | as C | one big jump on a guess, with no measure of what each step did | yes |

## Background
**Why C's limits.**
- **Cutting a near-full cabin loses money.** The ladder's down move is "under 90% of flights sold out". A cabin
  averaging 88% full can only gain 12% more passengers, so 5 points off the fare roughly breaks even and 10 loses.
  Under 80% full, there's room for the cut to pay.
- **A cut has to win more passengers than it gives up in fare.** Taking PVG–Kolkata's economy (32% full, 280 a
  seat):

  | Level | Load needed to keep the same revenue |
  |---|---|
  | 90% | 36% |
  | 80% | 40% |
  | 70% | 46% |
  | 60% | 53% |

  Each extra passenger also adds its own handling and onboard costs, so the real break-even is a little higher. The
  revenue check measures this directly instead of assuming it.
- **10-point steps:** at 5 points with a 2-week hold, a 32% cabin needs months to find its price. Under launch, each
  step is checked the next Saturday instead.
- **The 60% floor:** the house rule (§9, `world_rules.fare_floor_pct`) already holds every contested route there. Using
  it everywhere keeps one number, and keeps cheap fares from becoming the answer to a route that has no market.

**The routes it would touch** (`fare_ladder()` and `route_profit(…, 7)`, 23 Oct):

| Route | Cabin | Full | Fare | Profit a week | Note |
|---|---|---|---|---|---|
| PVG–Kolkata (China Eastern) | economy | 32% | 280 | 0.144M | Malaysia's KUL–Kolkata sells out at 233 |
| KUL–Thiruvananthapuram (Malaysia) | economy | 34% | 243 | 0.108M | business 89% |
| Delhi–JFK (Kingfisher) | economy | 59% | 779 | — | handed back (brief 2026-10-23-kingfisher-a350s, C) |
| Delhi–Amsterdam (Kingfisher) | economy | 54% | — | — | 4 departures, needs 5 to be judged |

PVG–Kolkata and KUL–Thiruvananthapuram are Saturday's decision (to-do #146). This rule gives them a third path
besides keeping or cutting: try the price first. If PVG–Kolkata filled to 60% at 70%, economy income would rise about
30%, roughly +0.1M a week.

**What we don't know: how the game's demand answers price.** We have no fare change on record yet; every route sits
at its launch level since 21 Oct.
- **The first evidence** comes from this Saturday's first real fare run, which raises sold-out routes (Pan Am and
  China Eastern 7 points). It shows how loads answer a higher price, not a lower one.
- **Older note:** the rule history says the game's passengers are price-sensitive, and that every lane ran full at
  lower fares in September.
- **Image:** whether low fares help or hurt the airline's image is not known either.

**The build.** C changes `fare_ladder()` and adds settings rows:
- the floor (60%);
- the load limit (80%);
- the step under launch (10);
- the revenue check, which compares the cabin's revenue a flight in the week before and after the step.

It's one helper build for the Building chat, with tests. Until it's merged, the manual's rule stands. B would only
change the floor.

## What would change the recommendation
- **Saturday's raises show demand barely moves with price:** cuts won't fill seats either, so A.
- **Many cabins between 80% and 90% start failing the sold-out test:** look again at the 80% limit.
- **Image is found to fall with low fares:** a higher floor (say 80%).

## Outcome
*Waiting for Gitesh.*

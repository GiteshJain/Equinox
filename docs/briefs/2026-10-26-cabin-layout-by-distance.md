# Cabin layout by distance — 26 Oct 2026

**Decision:** whether a new aircraft's cabin layout is chosen by the distance it flies instead of by its main route's
market, as service codes are (manual §4, service codes by distance).
**Recommendation:** C, two distance bands: **Leisure under 4,000 km, Leisure Plus from 4,000 km.** In our own flights
the densest layout earned as much or more a flight at every distance we have, and on long haul Leisure Plus outsold
Comfort. Demand differences are left to the fare ladder, as Gitesh suggests.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A Keep the market rule (§5) | No change | No change | No change | Markets marked Leisure Plus or Comfort keep giving up 15–25% of economy seats on short routes | Low; known | — |
| B Three bands like service codes: Leisure under 1,500 km, Leisure Plus 1,500–4,000, Comfort from 4,000 | More seats on short routes only | Roughly flat: gives back seats from 1,500 km where our data shows Leisure still earns more | Cabin 0.02M dearer per aircraft above 1,500 km | Seats given up on medium haul with no evidence they pay | Medium: bands copied from service codes, not from loads | Yes, for later orders |
| **C Two bands: Leisure under 4,000 km, Leisure Plus from 4,000** | Most seats wherever we have evidence they sell: about 30 more economy seats per A321neo than Leisure Plus | About 2% more revenue a flight under 4,000 km, about 6% more beyond it than Comfort (Background) | Cabin 0.02M cheaper per A321neo (Leisure 0.19M against 0.21M) | Comfort is no longer used where Leisure Plus exists | Low–medium: Leisure is lightly tested from 3,200 to 4,000 km | Yes, for later orders |
| D Most seats everywhere (Leisure wherever the variant has it) | Most seats of all | Unknown beyond 4,000 km: we have no long-haul Leisure flights | Cheapest cabins | Nothing | Medium: untested on long haul | Yes, for later orders |

## Background
**The layouts differ in the economy seat, not in business** (`cabin_configs`, 26 Oct). Business is 15–16 seats on
the A320 and A321 family and 12 on the E195 in every two-cabin layout. On the A321neo LIGHT: Leisure 180 economy,
Leisure Plus 150, Comfort 125. So each step up trades seat count for comfort.

**Our flights, 12 to 25 Oct** (`game_flights`, all airlines except Ryanair, which flies Standard only):

Revenue a flight by layout and distance, all types:

| Distance | Leisure | Leisure Plus |
|---|---|---|
| Under 800 km | 19.6k (889 flights) | 17.5k (221) |
| 800–1,500 km | 26.0k (2,364) | 25.4k (176) |
| 1,500–2,500 km | 36.2k (915) | 35.4k (263) |
| 2,500–4,000 km | 46.2k (59) | 45.7k (852) |

The same type on both layouts, the A321neo LIGHT:

| Distance | Leisure: load, eco pax, revenue | Leisure Plus: load, eco pax, revenue |
|---|---|---|
| 2,000–2,500 km | 97%, 171, 43.2k (129 flights) | 99%, 148, 41.0k (99) |
| 2,500–3,200 km | 83%, 142, 44.3k (43) | 94%, 141, 42.8k (489) |
| 3,200–4,000 km | 100%, 180, 59.0k (11, 2 routes) | 86%, 130, 48.9k (249) |

Beyond 4,000 km, the A321XLR: Leisure Plus 99%, 149 eco pax, 74.9k a flight (42 flights); Comfort 97%, 121, 70.6k
(229).

What it shows:
- **Leisure earns as much or more a flight in every band** where both layouts fly.
- **From 2,500 km Leisure's extra seats stop filling** (83% against 94%), but it still carries as many passengers, so
  the empty seats cost nothing.
- **Comfort did not earn back its lost seats** on long haul.

**How the game treats seat comfort:** we found no AirlineSim documentation on it, so the recommendation rests on our
own flights only.

**Demand and fares (Gitesh's point):** agreed for this rule. The fare ladder already raises a sold-out cabin's fare
and lets a weak one fall, including under launch (§5), so a market's demand can be met by price rather than by the
layout. Two limits: fares can't add seats to a full aircraft (the extra demand is lost), and they can't go under 60%
where another player flies the pair (§9). Neither argues for fewer seats.

**How the rule would read:** the cabin follows the distance of the aircraft's main route (the one taking most of its
block time), replacing the market and the 65% share in §5. The A350-1000 has only Comfort set up; under C it would
need a Leisure Plus layout set up in the game (a couple of minutes, §3).

## Scenarios and the risk of waiting
- **Goes well:** new aircraft carry 15–30 more economy passengers a flight on short and medium haul at the same or
  higher revenue, and the fare ladder prices the extra seats.
- **Goes badly:** Leisure turns out to lose passengers somewhere between 3,200 and 4,000 km, where we have only 11
  flights. The weekly review sees it in route profit within two weeks, and the band moves down for later orders.
- **Waiting** costs only the seats on whatever is ordered meanwhile: we don't refit, so the current fleet keeps its
  cabins under any option.

## What would change the recommendation
- More Leisure flights from 3,200 to 4,000 km showing loads or revenue below Leisure Plus: move the band down.
- Long-haul Leisure flights (none yet) earning as much as Leisure Plus: option D.
- AirlineSim documentation showing a seat-comfort penalty by flight length: set the bands from it.

## Outcome
**Gitesh, 26 Oct: by distance, three bands** (a variant of C, after asking whether Comfort is ever used):
**Leisure under 3,500 km, Leisure Plus 3,500 to 6,500 km, Comfort from 6,500 km**, by the aircraft's main route. In
air time, roughly: Leisure under about 4¼ hours, Leisure Plus about 4¼ to 7¾, Comfort beyond. Comfort stays on long
haul because nothing in our data tests Leisure Plus there. Manual §5 changed; the old rule is in `rule-history.md`;
`settings.cabin_leisure_max_km` (3,500) and `cabin_leisure_plus_max_km` (6,500) added. The planner's suggestion and
card check follow when the Building chat builds them (manual, *Decided, not yet built*).

# Pan Am: which rules to lift so it grows faster — 22 Oct 2026

**Decision:** Gitesh (review chat, 22 Oct): "Pan Am needs to move very quick. If needed remove rules." Which rules to
lift for Pan Am, and which to keep.
**Recommendation:** B + C together: let Pan Am's fares climb faster (10 points a week, cap 140%) and let it add flights
on its sold-out routes now instead of from 1 Nov. Keep hubs first and the order cushion: they barely slow Pan Am.
Cash is Pan Am's limit, and fares are the only lever that adds cash.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Change nothing | About 0.55 aircraft a day (cash-limited); about 76 aircraft by 31 Dec (base case, 21 Oct projection) | About 8.9M net today | 2.8M now, rising about 1.3M a day before orders (forecast, 22 Oct) | United and American keep outgrowing us on our pairs | None new | — |
| B. Faster fare ladder for Pan Am: 10 points a week while every flight sells out, cap 140% (Pan Am only) | About +0.1 aircraft a day once fares have climbed (3–4 weeks); roughly 80–85 aircraft by 31 Dec | +1.5M to +2.5M a week once fares are 10–20% higher, if loads hold | Unchanged at first; higher every week after | Some passengers to rivals on the busiest pairs; share by departures doesn't change | Loads fall below 90%: the ladder steps back 5 and holds, as today | Yes: a settings change |
| C. Frequency now: lift "until 31 Oct, only new routes" for Pan Am | No extra aircraft; frequency on 19 sold-out routes instead of new cities | About the same per aircraft (sold-out routes earn 6–12k an aircraft hour; JFK–Heathrow 12.1k) | Same as A | 10 days of new cities | Low; the second daily splits bookings | Yes |
| D. Exempt Pan Am from hubs first | Almost none: 844 of 1,297 openings are already allowed, the top 30 included | Same as A | Same as A | JFK's 750 slips further (259 today) | Spreads aircraft across six bases before JFK's banks are full | Yes |
| E. Lower the order cushion (0.5M to 0) | One order about half a day sooner, once | Same as A | 0.5M lower | — | One late payment can't be covered | Yes |

## Background
- **Cash is the limit, not the rules.** Pan Am's forecast (`cash_forecast(1)`, 22 Oct 13:58 UTC): 2.81M in hand, flight
  profit 2.26M a day, 6.93M of leases and salaries in the next 7 days, so about 1.27M a day to order with. An A320neo
  SHARP costs 2.22M with its cabin, an E195 1.87M: one aircraft every 1.5 to 1.7 days. The delivery lines could take one
  every 21 hours (A320 family) and every 15 hours (E195).
- **Every route sells out.** `route_profit(1, 7 days)`, 22 Oct: 30 of 37 routes at 100% economy; 19 marked add a flight,
  11 raise fares. Fares are at 100% of the game's default (launch level since 21 Oct).
- **Hubs first barely binds Pan Am.** `competition(1)`, 22 Oct: 844 of 1,297 openings allowed; every one of the top 30
  is allowed (contested West Coast and Midwest pairs). JFK has 259 weekly departures against 750.
- **Competition by market** (latest scan, 21 Oct, against the week before): US trunks 8.9% share, rivals +570 a week
  (United 1,176, American 824); transcon 3.7%, rivals +574; transatlantic dense 23% (was 27%); Mexico and Caribbean 12%
  (was 15%). This week: American added JFK–San Francisco and JFK–Dulles, United started Chicago–LaGuardia, KLM started
  JFK–Amsterdam.

## Scenarios and the risk of waiting
- **B goes well:** fares 10–20% higher in 2–3 weeks with loads above 95%; about 0.2–0.35M a day more cash, so one more
  aircraft every 6–10 days.
- **B goes badly:** loads drop under 90% on some pairs; the ladder steps those back and holds 2 weeks (as today).
  Cost: a week or two of lower loads on those pairs.
- **C:** the frequency the November trunks would add anyway comes 10 days earlier, where rivals are adding fastest.
- **Waiting:** United and American add hundreds of flights a week on our pairs; every week at today's fares leaves
  money on sold-out flights.

## What would change the recommendation
- Loads falling below 95% on the main trunks in the first week of B: slow back to 5 points.
- The fares userscript not yet confirmed with the world's owner (manual §5): the higher fares can still be set by hand.
- A cash shortfall from a large order (an A350): E's cushion would matter then.

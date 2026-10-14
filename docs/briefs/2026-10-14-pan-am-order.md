# Pan Am's next order — 14 Oct 2026

**Decision:** what Pan Am orders now. An order is just the aircraft; routes are decided when each one lands (manual §3).
**Recommendation:** C, two A321neos and one A321XLR. The A321neos add JFK departures and domestic feed; the XLR adds
the Atlantic, Pan Am's best-paying flying. It leaves 2.8M at the lowest point, enough for Pan Am's four cabin
conversions too, and the forecast allows another aircraft within a few days.

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Four A321neos | ~8 new or extra domestic routes · JFK +~55 departures a week | ~1.6M | 0.63M | no Atlantic growth; the cabin conversions (0.8M) wait | 0.13M over the cushion; one bigger week-end closing breaches it | no |
| B. Three XLRs | 3 new five-star Europe routes or second dailies · JFK +21 | ~1.2M | 1.96M | no domestic feed; fewest JFK departures | low | no |
| **C. Two A321neos + one XLR** | **~4 domestic routes + 1 Atlantic · JFK +~35** | **~1.2M** | **2.80M** | the third and fourth aircraft wait a few days | **low** | **no** |

The cash forecast is the database's `cash_forecast()` on the 14 Oct 03:11 UTC capture, with each order's lease counted
(manual §3). Mixes it refused: three A321neos plus an XLR (0.21M) and two of each (−0.21M). Profit is an estimate:
- **A321neo:** about 90k a day of flight profit on a pair of new trunks, from JFK's domestic routes at 14–46k a flight
  by distance. Its lease is about 34k a day.
- **XLR:** about 100k a day on one Atlantic rotation, from Frankfurt, Paris and Amsterdam at 51–54k a flight. Its lease
  is about 41k a day.

The forecast leaves out the new aircraft's own income, which adds buffer once they fly.

*Departure figures halved on 14 Oct: they first counted flights both ways, but the 750 target counts departures from
the hub only. The decision doesn't change.*

## Background
- **Route profit** (game_flights, 7–13 Oct): every Pan Am route sold out in economy except Toronto (67%, 6k a flight).
  - **Atlantic:** JFK–Heathrow on the A350 makes 100k a flight. The XLRs make Frankfurt 54k, Amsterdam 51k, Paris
    51k, Gatwick 49k and Dublin 46k.
  - **Transcon:** San Francisco 46k (A321neo), Seattle 41k and Los Angeles 39k (XLR).
  - **Other routes:** Mexico City 34k, Cancún 24k; Chicago's routes 14–21k; East Coast trunks 11–18k.
- **Per aircraft:** XLRs on the Atlantic make about 90–110k a day; the A321neos 86–110k. After lease, the two types
  earn about the same per aircraft, and the A321neo costs 0.42M less with its cabin.
- **Open markets from JFK** (routes list; rivals from the 6 Oct world scan):
  - **Five-star US trunks:** Miami, Minneapolis, Dallas and Las Vegas with no rival; Houston and Denver with 2–3
    flights a week; Phoenix contested (US Airways 42 a week).
  - **Five-star Europe:** Barcelona, Zurich, Munich and Rome with no rival. Madrid (Iberia) and Lisbon (TAP) have 14 a
    week each. Rome is 6,866 km, near the XLR's 6,939.
- **JFK** (flight_legs): 154 departures a week, the furthest of any main hub from 750. Each XLR on the Atlantic adds
  7 departures a week, and an A321neo on two domestic round trips 14. At JFK we're largest (154), ahead of United 56,
  Air Canada 49 and British Caledonian 42.
- **Rotation:** Pan Am's last two moves were big markets (Chicago O'Hare opened, 30 Sep; Gatwick, 5 Oct), so frequency is next.
  The sold-out Atlantic and transcon routes are the obvious second dailies. It stays flexible.
- **Already on the board:** trim Toronto to free part of N002AW; N001AW flies 9.0 h a day; Pan Am's four 321-LEI OLD
  conversions (0.8M).

## Scenarios and the risk of waiting
- **C goes well:** the two A321neos open trunks like Denver and Miami (or add a second San Francisco), the XLR adds a
  second daily on a sold-out Atlantic route or opens Barcelona, and cash rebuilds by about 0.85M a day.
  **Badly:** a new trunk sells like Detroit (14k a flight). That's still above the lease.
- **A** earns the most but runs within 0.13M of the cushion.
- **Waiting:** each day an A321neo isn't flying gives up about 90k of flight profit.

## What would change the recommendation
- Wanting the fastest climb to 750 at JFK: A, once the conversions are done or skipped.
- A rival appearing on JFK–Barcelona, Zurich or Munich in the next scan: B, to get there first.
- Toronto's trim freeing a whole aircraft: one fewer A321neo.

## Outcome
**14 Oct: C,** two A321neos and one A321XLR, all based at JFK. Gitesh orders them in the game and tells Claude, who
logs them (To-do board). Routes are decided when they land. Under the rotation, frequency comes first: second dailies on
the sold-out Atlantic and transcon routes.

# Virgin's next order, for new routes — 14 Oct 2026

**Decision:** what Virgin orders now, aimed at new markets from Gatwick (Gitesh, 14 Oct: "order for new routes").
An order is just the aircraft; routes are decided when each one lands (manual §3). Under hubs first, all go to Gatwick.
**Recommendation (revised the same night):** C, two A321neos, together with refitting all eleven of Virgin's A321s
still on the old cabin. The refits pay back in about two weeks, a new A321neo in about two months, so they come first.
Two new aircraft still bring about six new four-star cities, and Virgin keeps about 1.6M at the lowest point.
*First recommendation: A, three A321neos and the refits waiting. Changed when Gitesh found that the seven aircraft
scheduled on 13 Oct had been fitted with the old cabin, which put eleven Virgin aircraft on it.*

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Three A321neos | ~9 new 4-star cities · LGW +~125 departures a week | ~1.0M | 1.12M | the 11 refits (2.1M, ~1.1M a week) can't be afforded | low; new routes unproven | no |
| B. Two A321neos + one E195 | ~6 new 4-star cities plus ~3 thinner 3-star ones · LGW +~125 | ~0.8M | 1.82M | the refits still don't fit | low | no |
| **C. Two A321neos, plus the 11 refits** | **~6 new 4-star cities · LGW +~85; +264 seats on the routes Virgin already flies** | **~0.65M + ~1.1M from the refits** | **~1.6M (3.72M less 2.1M)** | **three fewer new cities than A** | **low** | **no** |

**The refits** (`cabin_configs`; game_flights, 7–13 Oct): the new 321-LEI has 180 economy and 15 business seats
against the old cabin's 156 and 16. Virgin's old-cabin A321s sell out in economy at an average fare of 128 and fly
about 5 flights a day. So 24 more economy seats are worth about 3,000 a flight, roughly 15k a day per aircraft, for
0.19M each with no time out of service.

The cash forecast is the database's `cash_forecast()` on the 14 Oct capture, with each order's lease counted (manual
§3). Two A321neos plus two E195s would breach the cushion (−0.08M). Profit is an estimate. Gatwick's existing four-star
routes make 9–18k a flight (median about 14k); an A321neo on three such round trips makes about 84k a day, less a lease
of about 34k. Virgin's E195s make about 45k a day, less 25k.

## Background
- **Loads and profit** (game_flights, 7–13 Oct): Virgin's routes all sold out except Cairo (97%), Oslo (96%) and
  Toulouse (98%). Cairo makes 40k a flight, Istanbul 25k, Malaga 22k, Lisbon 20k and Venice 18k. Virgin's A321neos
  make 69–82k a day and its E195s about 45k.
- **Gatwick:** 322 departures a week of 750 (with the 15 aircraft scheduled 13 Oct). easyJet has 385 there (6 Oct scan).
  Every five-star market from Gatwick is already flown or planned.
- **Open four-star markets from Gatwick** (6 Oct scan):
  - **No rival:** Stuttgart, Milan Linate, Alicante, Seville, Casablanca and Tel Aviv.
  - **easyJet once daily:** Düsseldorf, Geneva, Hamburg, Berlin, Palma and Warsaw.
  - **easyJet twice daily or more:** Budapest and Athens (28 a week), Vienna (42).
- **Three-star leisure, mostly no rival:** the Canaries, Faro, Madeira, the Greek islands, Larnaca, Antalya and
  Marrakech, at 2,000–3,200 km. Malaga (22k a flight) suggests long sunny routes do well on an A321neo.
- **Not Virgin's:** US routes from Gatwick are Pan Am's under one airline per city pair. Gulf and Canada routes would
  be long-haul, which comes later under reach first.
- **Cabins:** Tel Aviv and Casablanca sit in markets whose default is Comfort, so the aircraft that flies them would
  take 321-LP. That gets settled at scheduling.
- **The 15 aircraft from 13 Oct** started flying today; their new routes (Stockholm, Nice, Valencia, Naples, Porto)
  show their first loads from tomorrow night.

## Scenarios and the risk of waiting
- **A goes well:** the new cities sell like Venice or Prague (17–18k a flight). **Badly:** like Cologne (9k), which is
  still above an A321neo's lease on three round trips.
- **B** spreads to thinner cities at half the margin. **C** is the cautious choice and leaves cash for the conversions.
- **Waiting** for the new routes' first loads (two nights) would show whether Gatwick's new four-star cities sell before
  adding more of them. Each day an A321neo isn't flying gives up about 75k of flight profit.

## What would change the recommendation
- The first loads on Stockholm, Nice and Valencia coming in under 90%: C.
- Wanting the cabin conversions first: C.

## Outcome
**14 Oct: C,** two A321neos at Gatwick for new four-star cities, with all eleven of Virgin's old-cabin A321s refitted
to the new 321-LEI first. Gitesh orders and refits in the game and tells Claude, who logs them (To-do board: the order,
and the refit list for all 35 aircraft group-wide). Routes are decided when the aircraft land.

# Kingfisher's next order — 14 Oct 2026

**Decision:** what Kingfisher orders now. An order is just the aircraft; routes are decided when each one lands
(manual §3).
**Recommendation:** C, two A321neos and one A320neo. The A321neos add frequency on Delhi's sold-out trunks and Gulf
route, and the A320neo opens new secondary cities. Kingfisher's only A320neo earns as much a day as an A321neo for 0.28M
less. It leaves 2.1M at the lowest point, enough for Kingfisher's six cabin conversions too.

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Three A321neos | ~6 more flights a day on trunks, Gulf and new cities · DEL +~50 departures a week | ~1.05M | 1.83M | conversions (1.2M) fit only just (0.63M left) | low | no |
| B. Two A321neos + one XLR | the XLR for a second Heathrow or a new Europe route · DEL +~35 | ~1.1M | 1.41M | the conversions wait; Amsterdam's XLR could do Heathrow instead (see below) | Europe beyond London is soft | no |
| **C. Two A321neos + one A320neo** | **trunk and Gulf frequency plus ~3 new secondary cities · DEL +~50** | **~1.05M** | **2.11M** | **none of note** | **low** | **no** |
| D. Two A321neos + two E195s | E195s start the regional layer on 3-star routes · DEL +~65 | ~1.0M | 0.63M | conversions wait; no E195 data at Kingfisher yet | 0.13M over the cushion | no |

The cash forecast is the database's `cash_forecast()` on the 14 Oct 03:11 UTC capture, with each order's lease counted
(manual §3). Profit is an estimate from Kingfisher's own aircraft (game_flights, 7–13 Oct):
- **A321neo:** 70–93k a day of flight profit (median 85k), less its lease of about 34k.
- **A320neo (VT-AAM):** 83k a day, less about 31k.
- **XLR on Heathrow:** 102k a day, less about 41k.
- **E195:** 45–56k a day at the other airlines, less about 25k.

*Departure figures halved on 14 Oct: they first counted flights both ways, but the 750 target counts departures from
the hub only. The decision doesn't change.*

## Background
- **Route profit** (game_flights, 7–13 Oct): every domestic and Gulf flight sold out in economy.
  - **Trunks:** Chennai 23k a flight, Bangalore 22k, Hyderabad 20k, Kolkata 19k and Mumbai 18k, each twice daily.
  - **Once daily:** Kochi 24k, Dubai 23k, Goa 20k; Ahmedabad and Bhopal 15k; Pune 13k; Srinagar, Varanasi and
    Indore 12k; Lucknow 10k.
  - **Long-haul:** Delhi–Heathrow on the XLR makes 58k a flight, sold out. Paris makes 50k at 86% economy, and
    Amsterdam 31k at 52%. JFK on the A350s makes 112k a flight at 55% economy and 85% business.
- **Per aircraft:** A321neos 70–93k a day, the A320neo 83k. The XLRs make Heathrow 102k, Paris 73k and Amsterdam 57k
  (about 16k over its lease). The A350s make 146–164k against about 103k of lease each.
- **Open markets from Delhi** (routes list; rivals from the 6 Oct world scan):
  - **Five-star:** Abu Dhabi, Doha, Bangkok and Singapore with no rival; Istanbul (Turkish 14 a week); Munich,
    Frankfurt, Zurich and Rome on the XLR, with no rival.
  - **Four-star, no rival:** Patna, Bhubaneswar, Guwahati, Thiruvananthapuram, Kathmandu, Dhaka, Colombo, Male,
    Sharjah, Kuwait and Riyadh.
  - **Three-star short routes,** for E195s later: Jaipur, Chandigarh, Amritsar and others.
  - Delhi–China belongs to China Eastern under one airline per city pair, so Beijing and Guangzhou are out.
- **Delhi** (flight_legs): 167 departures a week, of 750. In the 6 Oct scan we're by far the largest airline there;
  the next is Oman Air with 14. India is effectively uncontested. Mumbai is a hub for contested Gulf routes only (hubs first,
  §3).
- **Rotation:** Kingfisher's last moves were feeders (1 Oct) and a big market (3 Oct), so frequency is next. Third
  dailies on the trunks, and second dailies to Kochi, Dubai or Goa, are the obvious ones. It stays flexible.
- **Already on the board:** the Delhi early-morning connection (fix with the next Kingfisher card); the A350 review;
  six 321-LEI OLD conversions (1.2M).

## Scenarios and the risk of waiting
- **C goes well:** the A321neos add third dailies to Chennai and Bangalore or second dailies to Kochi and Dubai, and
  the A320neo opens Patna, Bhubaneswar and Guwahati, all with no rival. **Badly:** the new secondary cities sell like
  Lucknow (10k a flight). That's still above the A320neo's lease.
- **B:** a second Heathrow daily is the strongest single route on offer, but it doesn't need a new aircraft. Moving the
  Amsterdam XLR (52% economy) to Heathrow would do it, so it's better raised as its own scheduling item.
- **Waiting:** each day a narrowbody isn't flying gives up about 85k of flight profit.

## What would change the recommendation
- Wanting the regional layer started now: D, once the conversions are done.
- Choosing not to move the Amsterdam XLR: B, with the new XLR on Heathrow.
- Loads on Kingfisher's newest routes (Pune, Ahmedabad) slipping below 90%: A, to keep to proven trunk frequency.

## Outcome
**14 Oct: A,** three A321neos, all based at Delhi. Gitesh orders them in the game and tells Claude, who logs them
(To-do board). Routes are decided when they land; frequency comes first under the rotation. With all three, the six
cabin conversions (1.2M) still fit, but only just (about 0.63M left at the lowest point), so stage them if a week-end
closing comes in high.

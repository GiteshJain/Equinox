# China Eastern's next order, for new routes — 14 Oct 2026

**Decision:** what China Eastern orders now, aimed at new markets from Shanghai (Gitesh, 14 Oct: "order for new
routes"), and when its 13 old-cabin A321s are refitted. An order is just the aircraft; routes are decided when each
one lands (manual §3). Under hubs first, all go to Shanghai PVG.
**Recommendation:** A, three A321neos now, with the 13 refits on Friday 16 Oct. China Eastern earns about 1M a day
after leases and salaries, the most in the group, so it can afford both within two days. The refits wait only two
days (about 0.35M of extra fares given up), and the third aircraft adds about 0.45M a week for good. It leaves 2.00M at
the lowest point now and 1.44M once the refits are paid on Friday.

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A. Three A321neos now, the 13 refits on Friday** | **~6 new 4- and 5-star cities · PVG +~40 departures a week** | **~1.35M, plus ~1.2M from the refits once done** | **2.00M now; 1.44M after the refits** | **the refits start two days later (~0.35M)** | **low; 0.76M if the refits are done tomorrow instead** | **no** |
| B. One A321neo + one XLR, refits now | Delhi (5-star, no rival) plus ~2 new cities · PVG +~25 | ~0.9M + ~1.2M | 1.67M (4.17M less 2.50M) | one fewer A321neo; the XLR costs 0.42M more | Delhi is long-haul in the game, so it runs ahead of reach first; India–China loads unproven | no |
| C. Two A321neos, refits now | ~4 new cities · PVG +~28 | ~0.9M + ~1.2M | 2.09M (4.59M less 2.50M) | one fewer new aircraft than A (~0.45M a week) | low | no |

The cash forecast is the database's `cash_forecast()` on the 14 Oct 03:12 UTC capture, with each order's lease counted
(manual §3). China Eastern had 9.77M; its lowest point is now, because flight profit (about 1.73M a day) outruns its
payments. The refits are not in the forecast, so I took their 2.50M (13 × 0.19M) off by hand on the day they'd be
paid. Two A321neos plus an XLR would leave 1.58M before the refits and 1.02M with them on Friday.

Profit is an estimate. China Eastern's A321s make about 82k a day of flight profit (game_flights, 7–13 Oct), mostly on
domestic routes of 600–2,000 km. Its profit per flight rises with distance: four-star Haikou (1,686 km) makes 22k and
five-star Bangkok (2,897 km) 32k. An A321neo on, say, Saigon and Manila round trips would make about 100k a day, less a
lease of about 34k. An XLR on Delhi plus a short round trip would make roughly the same after its 41k lease.

**The refits** (`cabin_configs`; game_flights, 7–13 Oct): the new 321-LEI has 180 economy and 15 business seats against
the old cabin's 156 and 16. China Eastern's old-cabin A321s sell out in economy at an average fare of 150 and fly about
3.9 flights a day. So 24 more economy seats are worth about 3,600 a flight, roughly 14k a day per aircraft, for 0.19M
each. That pays back in about two weeks; a new A321neo takes about two months. The 13 are B-0157 to B-0168 and B-0171
(To-do board).

## Background
- **Loads and profit** (game_flights, 7–13 Oct): every China Eastern route sold out except Hangzhou–Xi'an (93%).
  From Shanghai: Bangkok 32k a flight, Kunming 25k, Narita 23k, Haikou, Chengdu, Chongqing and Haneda 22k, Guiyang
  19k, Xi'an and Shenzhen 18k. Daxing–Shenzhen 25k. The E195 routes make 9–15k.
- **The five aircraft filed on 13 Oct** (B-0167 to B-0171) started flying yesterday. Their new routes (Kolkata,
  Nanning, Lanzhou, Tianjin, Shenyang, Taiyuan and Dalian) show first loads from tomorrow night. Kolkata is China
  Eastern's first India route.
- **Shanghai PVG** (flight_legs): 301 departures a week, of 750. In the 6 Oct scan the next airline there was Air
  China with 91.
- **Open four- and five-star markets from Shanghai** within an A321neo's 4,192 km (routes list; rivals from the 6 Oct
  scan; no rival unless noted):
  - **Five-star:** Singapore, 3,806 km (Singapore Airlines 14 a week).
  - **Four-star:** Hefei (467 km), Manila (1,851), Sanya (1,896), Hanoi (1,937), Saigon (2,746), Bangkok Don Mueang
    (2,889), Urumqi (3,312) and Kathmandu (3,535).
  - Kota Kinabalu and Penang are Malaysia's under one airline per city pair, so they're left out here.
- **XLR only:** Delhi (5-star, 4,293 km, just past the A321neo's range) and Mumbai (5-star, 5,064 km), both India–China
  and so China Eastern's; Jakarta, Bali, Colombo and Male (4-star). The Gulf (Dubai, Abu Dhabi, Doha, 6,450–6,800 km)
  is long-haul and comes later under reach first.
- **Three-star within reach,** mostly no rival: Osaka Kansai, Cebu, Vientiane, Chiang Mai, Phnom Penh, Phuket and
  Almaty, plus many domestic secondary cities (Harbin, Changchun, Guilin, Lijiang and others).
- **Cabins:** Singapore, Manila, Hanoi, Saigon and Don Mueang are in the Asia regional market, whose default is 321-LP.
  Sanya, Urumqi and Hefei default to 321-LEI. Kathmandu's market defaults to the XLR cabin, which an A321neo can't take.
  This gets settled at scheduling.
- **Rotation:** the last batch (B-0167 to B-0171) covered a big market (Kolkata), frequency (two aircraft) and feeders
  (two aircraft), so the cycle starts again with a big market. New cities fit.
- **Already on the board:** the 13 refits (2.5M), part of the group-wide list of 35.

## Scenarios and the risk of waiting
- **A goes well:** Singapore, Saigon and Don Mueang sell like Bangkok (about 30k a flight), and the shorter ones like
  Haikou (22k). **Badly:** the new cities sell like Wuhan or Xiamen (16k). That's still above an A321neo's lease on
  two or three round trips.
- **B** opens Delhi, the biggest prize on offer, but the XLR costs more and India–China demand is unproven until
  Kolkata's loads come in.
- **C** is the cautious choice and refits everything today.
- **Waiting** for Kolkata's first loads (tomorrow night) would show how India–China sells before buying an XLR for
  Delhi. It doesn't affect the A321neo options. Each day an A321neo isn't flying gives up about 65k after lease.

## What would change the recommendation
- Wanting the refits done today: C.
- Kolkata selling out in its first week: an XLR for Delhi becomes the next China Eastern order (or B now).
- Wanting Delhi now as well as three new cities: two A321neos plus an XLR, refits on Friday (1.02M at the lowest point).

## Outcome
**14 Oct: A,** three A321neos at Shanghai PVG for new cities, with China Eastern's 13 old-cabin A321s refitted to the
new 321-LEI on Friday 16 Oct. Gitesh orders and refits in the game and tells Claude, who logs them (To-do board: the
order, and the group-wide refit list). Routes are decided when the aircraft land.

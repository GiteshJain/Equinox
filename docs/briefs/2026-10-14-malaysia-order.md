# Malaysia's next order, for new routes — 14 Oct 2026

**Decision:** what Malaysia orders now, aimed at new markets from Kuala Lumpur (Gitesh, 14 Oct: "order for new
routes"). An order is just the aircraft; routes are decided when each one lands (manual §3). Under hubs first, all go
to KUL.
**Recommendation:** B, two A321neos and one A321XLR, with 9M-AAA refitted to the new 321-LEI. Malaysia's best routes
are its longest five-star ones (Shanghai 40k a flight, Hangzhou and Mumbai 38k), and every five-star city it doesn't
fly yet is just beyond an A321neo's reach. The XLR opens one of them: Seoul, Beijing Daxing or Tokyo, none with a rival.
The two A321neos add about four new four-star cities. It leaves 1.21M at the lowest point, 1.02M after the refit.

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Three A321neos | ~6 new 4-star cities · KUL +~40 departures a week | ~1.2M | 1.63M (1.44M after the refit) | no new five-star city | low | no |
| **B. Two A321neos + one XLR** | **one new 5-star city (Seoul, Beijing Daxing or Tokyo) plus ~4 new 4-star ones · KUL +~35** | **~1.3M** | **1.21M (1.02M after the refit)** | **two fewer 4-star cities than A** | **the XLR is new to Malaysia; no loads beyond 3,800 km yet** | **no** |
| C. Two XLRs | two new 5-star cities · KUL +~20 | ~1.0M | 3.38M (3.19M after the refit) | the fewest new cities and departures | as B, twice | no |

The cash forecast is the database's `cash_forecast()` on the 14 Oct 03:12 UTC capture, with each order's lease counted
(manual §3). Malaysia had 9.40M and makes about 1.78M a day of flight profit, so its lowest point is now. Four
A321neos (−0.97M), one A321neo plus two XLRs (0.79M, 0.60M after the refit) and three XLRs (0.37M) were left out. The
refit of 9M-AAA (0.19M) is not in the forecast, so I took it off by hand.

Profit is an estimate (game_flights, 7–13 Oct). Malaysia's A321neos make 64–89k a day (median about 80k) on about 2.7
long flights a day. Its profit per flight rises with distance: about 30k at 2,600 km, 35k at 3,000 km and 40k at
3,800 km. So:
- **A321neo on new four-star routes** of 2,100–3,800 km (say Wuhan and Hanoi): about 90k a day, less a lease of
  about 34k.
- **XLR on Seoul (4,613 km) or Beijing Daxing (4,348 km)** at about 45k a flight, plus a short round trip: about 110k
  a day, less about 41k. Its Leisure Plus cabin has the same 166 seats as Malaysia's A321neos.

## Background
- **Loads and profit** (game_flights, 7–13 Oct): almost every Malaysia route sold out. The lowest were Semarang (93%),
  Kunming and Saigon (95%), Phuket (96%) and Chongqing (97%).
  - **Five-star, 2,500–3,800 km:** Shanghai 40k a flight, Hangzhou 38k, Mumbai 38k, Hyderabad 35k, Xi'an 35k,
    Guangzhou, Bangalore, Shenzhen and Chongqing 30–31k, Kolkata, Hong Kong and Chennai 29k, Kunming 25k.
  - **Shorter routes:** Jakarta 19k, Kuching 18k, Saigon 17k, Bangkok 17k; the three-star E195 routes 5–13k.
- **The five aircraft filed on 13 Oct** (9M-AAK to 9M-AAO) started flying yesterday. Their new routes (Delhi, Xiamen,
  Kota Kinabalu, Kochi and Thiruvananthapuram) show first loads from tomorrow night.
- **KUL** (flight_legs): 280 departures a week, of 750. In the 6 Oct scan Singapore Airlines had 315 departures a week
  there, all on the Singapore shuttle (45 a day). Our own KUL–Singapore makes 4.5k a flight. Next were Thai Airways (42)
  and Air China (14).
- **Open five-star markets from KUL** (routes list; rivals from the 6 Oct scan): all are beyond an A321neo's 4,192 km.
  - **XLR range, Asia:** Beijing Daxing (4,348 km) and Seoul (4,613) with no rival; Beijing Capital (4,414; Air China
    28 a week); Tokyo Haneda (5,351) and Narita (5,409) with no rival.
  - **Further:** the Gulf (Dubai, Abu Dhabi, Doha, 5,550–5,900 km) and Melbourne and Sydney (6,300–6,600). Those wait
    under Malaysia's feeder-first rule (manual §2).
- **Open four-star markets within an A321neo's reach,** all with no rival:
  - **China:** Sanya (1,923 km), Haikou, Nanning, Guiyang, Changsha, Fuzhou, Wuhan, Hefei, Nanjing, Zhengzhou,
    Lanzhou, Taiyuan and Qingdao (4,187); also Taipei (3,246).
  - **Southeast Asia:** Bangkok Don Mueang (1,248), Bali (1,964), Hanoi (2,102) and Manila (2,490).
  - **South Asia:** Colombo (2,467), Dhaka (2,642), Male (3,132), Kathmandu (3,273), Lucknow (3,471) and Ahmedabad
    (3,861).
  - **Australia:** Perth (4,140).
- **Ownership:** Malaysia pairs are Malaysia's under one airline per city pair, including KUL–China and KUL–India.
- **Cabins:** China, South Asia and North Asia routes sit in markets whose default is Leisure Plus (321-LP on an
  A321neo, XLR-LP on an XLR), as on Malaysia's existing China and India routes. Don Mueang, Bali, Hanoi and Manila
  default to 321-LEI. This gets settled at scheduling.
- **Rotation:** since the last big market (Shanghai and Saigon, 5 Oct) Malaysia has added frequency (6 and 8 Oct) and
  feeders (8 Oct), so a big market is next. New cities fit.
- **Reach first and feeder first:** the XLR is a narrowbody, and Seoul, Beijing and Tokyo sit in the game's "Asia &
  Australia" market, not its long-haul one. So B stays within the Asian network. (China Eastern's Delhi option was
  different: that route is in the long-haul market.)
- **Already on the board:** the refit of 9M-AAA, Malaysia's one old-cabin A321 (0.19M). It makes 59k a day against
  74–89k for its sister aircraft.

## Scenarios and the risk of waiting
- **B goes well:** Seoul or Beijing sells like Shanghai or better (about 45k a flight), and the four-star cities like
  Xi'an or Guangzhou (30–35k). **Badly:** the XLR's city sells like Kunming (25k), which still covers its lease on one
  round trip plus a short one, and the four-star cities like Jakarta (19k).
- **A** is all A321neos and the lowest risk, but adds no five-star city. Malaysia's five-star cities have earned the
  most so far.
- **C** puts most of the money into the longest routes, with the fewest new departures.
- **Waiting:** the new routes from 13 Oct (Delhi, Xiamen, Kota Kinabalu, Kochi, Thiruvananthapuram) report tomorrow
  night. That's useful for scheduling, but it doesn't change what to order. Each day a narrowbody isn't flying gives up
  about 55–70k after lease.

## What would change the recommendation
- Reading the XLR as starting long-haul early: A.
- Wanting the fastest climb to 750 at KUL: A.
- A rival appearing on KUL–Seoul, Beijing Daxing or Tokyo in the next scan: C, to take two of them first.

## Outcome
**14 Oct: C,** two A321XLRs at KUL, for two of the five-star cities beyond an A321neo's reach (Seoul, Beijing Daxing,
Tokyo), with 9M-AAA refitted to the new 321-LEI. About 3.19M stays at the lowest point after both. Gitesh orders and
refits in the game and tells Claude, who logs them (To-do board: the order, and the group-wide refit list). Which two
cities, and the cabin, are decided when the aircraft land.

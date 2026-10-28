# Connections: count only short waits? — 27 Oct 2026

*Scheduling chat. Gitesh asked whether the bank windows are too wide and whether we miss connections because of them.
Figures: every daily leg in the planner on 27 Oct, each hub's own airline, connections by manual §4 (the airport's
minimum connection time to 8 hours). The game (Gitesh, 27 Oct): passengers choose by the best mix of price, time,
cabin and service, so a long wait loses bookings to a shorter itinerary.*

## Decision and recommendation
**Recommendation: B.** Count a connection only up to **4 hours** of waiting (`settings.connection_max_wait_h` 8 → 4),
so the optimiser, the card check and the connection audit all aim for short connections; then a retime pass at the
five big hubs, Gatwick first, moving flights by up to 60 minutes to pull them into their banks. The Saturday audit's
retime limit goes from 10 to 30 minutes (§7).

## What we found
**The windows aren't the problem.** Each bank has a 60-minute arrival window and a 60-minute departure window, three
banks a day. A connection counts on its gap alone, so the windows' width neither adds nor loses a connection. Three
banks 8 hours apart also fit our round trips best (median 5.6 h; 47% of round trips leave in a bank and land back in
the next usable one, tied with six banks and ahead of four or five).

**But only a third of our flights sit in their banks:**

| Hub | Arrivals in window | Departures in window | Connections (8 h rule) | Missed by under 60 min |
|---|---|---|---|---|
| LGW (Virgin) | 31% | 29% | 1,580 | 217 |
| PVG (China Eastern) | 32% | 32% | 1,475 | 188 |
| KUL (Malaysia) | 40% | 59% | 1,289 | 90 |
| JFK (Pan Am) | 41% | 50% | 629 | 44 |
| DEL (Kingfisher) | 46% | 41% | 474 | 46 |

**So most connections are long:**

| Hub | ≤2 h | 2–3 h | 3–4 h | 4–6 h | 6–8 h |
|---|---|---|---|---|---|
| JFK | 11% | 22% | 13% | 24% | 29% |
| DEL | 18% | 13% | 11% | 27% | 31% |
| LGW | 11% | 14% | 12% | 32% | 30% |
| PVG | 14% | 14% | 11% | 28% | 33% |
| KUL | 28% | 13% | 6% | 27% | 25% |
| **All 5,447** | **17%** | **15%** | **10%** | **28%** | **30%** |

58% wait over 4 hours, and the average is about 4.5 hours. A flight in its bank connects in the minimum connection
time to about two hours more (1.3 to 3.5 hours), so 4 hours is "in a bank, or close".

## Options

| Option | Growth | Profit a week | Cash | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Keep the 8-hour rule; retime only the near misses | about 585 more pairs, mostly long waits | small: long connections sell poorly against rivals | none | the planner keeps rewarding 6–8 h connections | low | yes |
| **B. Count up to 4 h; retime pass at the big hubs (recommended)** | **every new card and retime aims at short, sellable connections** | **likely the largest: transfer passengers on short connections, where rivals compete** | **none** | **counted connections drop to about 42% on paper at first (no change in the game)** | **medium: the retime pass touches many flights; each is checked at both ends** | **yes (one setting)** |
| C. Weight connections by wait in the optimiser (shorter scores higher) | as B, finer | as B | none | a Building job first | low | yes |

## Background
- One setting decides the counting (`connection_max_wait_h`, manual §1: one source); the planner, the optimiser, the
  card check, the audit and the website's trip search read it.
- Departure time of day doesn't affect demand (§9); only the connection does, so retimes cost nothing but the
  check at both ends.
- How much a long wait costs in bookings isn't known; the game weighs it with price, cabin and service. B makes the
  planner prefer short waits without needing the exact weight.

## What would change the recommendation
- The connecting passengers on our long connections turn out to sell well: A.
- The retime pass finds that most flights can't move into their banks (aircraft days too full): keep 4 h for new
  cards only, and move the rest as aircraft are replaced.

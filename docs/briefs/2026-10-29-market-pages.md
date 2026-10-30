# Read the game's Market Analysis pages (rivals' fares and passenger share)? — 29 Oct 2026

*Building chat. Gitesh found the page on 29 Oct (to-do 188) and saved one: Commercial → Market Analysis, DUB→AMS
(`/app/com/markets/DUBAMS`), 30 Oct 04:51 UTC. Figures: the saved page; database size and the evening scan from live,
29 Oct; flown routes from `routes` and `rotations`. It folds in the route page proposal of the same evening (the right
half of every board is empty at 1280 px).*

## Decision and recommendation
**Decision:** whether the capture reads each of our pairs' Market Analysis page, how often, and what the planner shows
from it.

**Recommendation: C.** Once a week, the evening capture reads both directions of every pair we fly (686 pages, about
10 to 12 minutes more that evening), keeps only the figures, and the route page and Competition show rivals' fares and the
game's own passenger share. Once a week matches when fares move (the Saturday ladder); how often is a setting, so
moving to every evening (B) later is a data-only change. Two pull requests, about two hours of helper work.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Not now: the route page's four boards from what we already have | none | none | none | the Saturday review keeps pricing blind to rivals | none | — |
| B. Every evening, all 686 pages | fares and share fresh daily | indirect: better fare and route calls | none (free plan) | 10–12 minutes more every evening; about 7 times C's storage | low; the game may notice the extra pages | yes (a setting) |
| **C. Once a week, all 686 pages (recommended)** | **a weekly picture for the review, each pair's fares and share** | **indirect, as B** | **none** | **10–12 minutes more one evening a week; fares up to 7 days old** | **low** | **yes (a setting)** |
| D. Every evening, a seventh of the pairs (about 100 pages, 2 minutes) | each pair weekly, spread over the week | as C | none | the Saturday review sees pairs read 1 to 7 days ago, mixed | low | yes (a setting) |

## Background
**What one page gives** (one direction of one pair; the reverse is its own page):

| Section | What it holds | DUB→AMS, 30 Oct |
|---|---|---|
| Current Availability | Every airline's flights on the pair, finished (yesterday), booked and in flight (to about 3 days ahead): flight, aircraft, date, times, each class's price and seats left | KLM economy 120 AS$, business 245; Aer Lingus 156, 319, first 457; Ryanair 102 |
| Market Shares | Each airline's share of the pair's passengers (and cargo), this calendar week against last | KLM 68.46% (−10.32 pts), Aer Lingus 24.61% (+11.37), Ryanair 6.94% (−1.05) |
| Historic Capacities and Prices | The pair's seats offered and price per unit by calendar week, from week 20 (in the page's script, as data) | week 43: 9,616 seats, 122 AS$; week 44 so far: 6,268, 125 AS$ |
| Pricing and settings | Our own prices, the default price and our on-board service profile for the pair | economy 102 against a default of 120; service R |

**What's new to us:**
- **Rivals' fares,** by flight and class, in the same direction as the fare ladder (§5).
- **The game's passenger share.** Competition today works out share from departures in the world scan. On DUB→AMS
  the scan would say something else: we fly a smaller share of flights there than KLM.
- **Whether a rival sold out.** Seats left show at most 9 (economy on DUB→AMS reads 0 or 9), so it is not a load
  factor. A finished flight with 0 seats left did sell out.

**What it doesn't give:** rivals' loads beyond sold-out or not, connecting passengers, or pairs we don't fly (each page
is one pair; openings could be read later, below).

**Size:** 343 pairs flown, 686 pages counting both directions. Each page is about 290 KB, so raw pages can't be kept:
686 a night for 14 days would be about 2.8 GB, against the 350 MB trigger (§1; the database is 181 MB, raw pages
8.8 MB, on 29 Oct). The capture reads each page in the browser and sends only the figures (about 10 to 20 rows a page).
Stored per read, about 1 MB a night (B) or 1 MB a week (C).

**Time:** the evening scan read about 490 pages (179 schedules, 179 fleet pages, 128 airports) in about 8 minutes on
29 Oct. 686 market pages at the scan's pace is about 10 to 12 minutes.

**Allowed:** Gander is an exclusive world; every script Gitesh chooses to use is allowed there (§9). In a public world
it wouldn't be (terms §5.3).

## What gets built (C), in the Building chat
1. **Capture 1.9, the market pages:** when one is due (the latest finished read at least `settings.market_every_days`
   capture days old, 7, as the world scan's `scan_every_days`; 0 off),
   after the world scan, the userscript reads `/app/com/markets/<FROM><TO>` for both directions of each pair the
   database lists (`capture_airlines()` says what's due, as for the scan). The page belongs to the airline that is
   open (its airport lists are that airline's stations and its pricing is that airline's), so the pairs come grouped by
   the airline that flies them, and the userscript switches to each airline once
   (`/app/enterprise/dashboard?select=<game id>`, as the fares userscript does) and checks the page shows that airline
   before reading its pairs (one airline per pair, §2, so six switches). **The game keeps the page's filters between
   visits** (Gitesh, 30 Oct), and they are in each page's markup, so the userscript checks them on every page against
   the setup in the saved page: every service class and every flight status ticked, Ignore own flights off, Group by
   flight on. If one differs it sets it through that filter's own control and checks again (Gitesh, 30 Oct), stopping
   only if it won't take. **The filters are the only thing it changes:** the page also holds the Pricing and settings
   forms, which change our fares, and the userscript never submits them (its test checks it). It parses the four sections in the browser, and
   sends the figures with the capture key to a new `capture_market()`. Its panel shows "Market pages: 120 of 686…",
   with Stop; a reload carries on; a failed page is logged and skipped, as the scan does. Tested on Gitesh's saved
   DUB→AMS page (a dated sample in `tests/fixtures/`).
2. **Database:** a read per pair and direction (`market_reads`), each airline's fares there by class (lowest, average,
   highest, flights seen, finished flights sold out: `market_fares`), the passenger and cargo shares by calendar week
   (`market_shares`), and the pair's weekly seats and price (`market_weeks`). The weekly figures and shares are kept for
   good; anything per flight isn't stored at all. A figure in `competition()` and `route_story()`: each rival's fare
   against ours, by direction and class, and the game's passenger share.
3. **The planner:** the route page goes to two columns on wide screens (one on a phone, as now) with five new boards:
   **Rival fares** (each airline's economy and business fare each way against ours and our ladder level), **Market
   share** (the game's passenger share, this week against last), **Rivals over time** (each rival's departures a week at
   each scan, and the share at each read), **Load by direction** and **Loads by flight**. Competition's market cards show
   the game's passenger share next to the scan's. The pair's service profile in the game is checked against the
   planner's legs and the code its distance calls for (§4), and a pair set differently is an item to fix (Gitesh,
   30 Oct). The weekly report's competition section shows rivals' fares.
4. **Not changed:** the fare ladder's rules, the openings' order and the contested test. Using rivals' fares in the
   ladder (holding when a rival is cheaper, say) would be a rule change, a separate decision once a few weeks of
   figures are in.

Two pull requests: capture and database first, then the planner and the report.

## Scenarios and the risk of waiting
- **Goes well:** from the first Saturday after it's built, the review sees, route by route, whether we're priced above
  or below each rival and whether a rival's flights sell out, and the route page and Competition show the game's real
  share instead of our estimate from departures.
- **Goes badly:** the game changes the page and the parse fails. The capture logs it and skips; the rest of the evening
  is untouched, and the saved page's test shows what changed.
- **Waiting:** the fare ladder keeps moving on our own loads only, with no view of rivals' fares. On contested pairs
  (CDG–AMS: Air France added 14 a week on 23 Oct) we don't know whether we're the cheap or the dear option.

## What would change the recommendation
- **The evening it runs gets too long** (capture, scan and 686 pages): D, a seventh a night.
- **Rivals' fares move often between Saturdays** (seen in the first few weeks of reads): B.
- **We want rivals' fares before opening a route:** add the top openings' pairs to the list (more pages), a later
  decision.
- **The database nears 350 MB:** the per-read fares go to the monthly archive after a month, as the scan schedules do.

## Outcome
**30 Oct 2026, Gitesh: C, once a week when due** (every 7 capture days, as the world scan runs, not on a fixed
weekday): `settings.market_every_days`, 7. The capture sets the page's filters to the saved setup itself and never submits the Pricing or settings forms (above).
Manual: *Decided, not yet built* until the build merges, then §7.

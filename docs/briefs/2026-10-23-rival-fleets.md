# Rivals' fleets and aircraft on order in the world scan — 23 Oct 2026

**Decision:** how to add each rival's fleet and aircraft on order to the world scan (decided in the review chat on
23 Oct; this brief settles how often it's read and what gets flagged).

**Recommendation: B.** Read every enterprise's overview page **once a week**, when the latest fleet read is 7 or more
capture days old (`settings.fleet_scan_every_days` 7), as part of the evening's world scan. Store each rival's fleet by
type with every read, show the change since the previous read, and flag:
- **a big order book:** aircraft on order at **25% or more of its fleet, and at least 5 on order**;
- **a starting airline:** aircraft on order and no flights yet.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Every evening, all 171 enterprises | earliest warning (a day) | none | none | about 3 minutes more every evening | a long evening; 171 more pages to the game nightly | yes (one setting) |
| **B. Once a week, all 171, due when the last read is 7+ capture days old (recommended)** | **warning within a week, in time for every Saturday report** | **none** | **none** | **about 3 minutes more one evening a week** | **a missed evening delays it one day, not a week** | **yes (one setting)** |
| C. Every evening, only the 85 rivals flying at our airports | daily, for the rivals we meet | none | none | about 1.5 minutes every evening | misses airlines not flying yet, the ones a big order book matters most for | yes |

## Background
**What we miss today.** The scan reads every airline's schedule and the big airports' pages, never fleets. Icelandair
(enterprise 101) flies 186 flights a week in the 23 Oct scan (`game_scan_schedules`, scan 7), with 99 aircraft and 44
on order (Gitesh, from its overview page): 44% of its fleet again. Nothing in our data showed it.

**The page.** `https://gander.airlinesim.aero/app/info/enterprises/{id}`: its Fleet table gives each type with owned,
leased, overall, leased out, on offer, on order and average age. The capture runs in Gitesh's signed-in browser, so it
reads the page as it reads the schedules. Outside a browser it first redirects and needs the session cookie;
`gscan.py` (the fallback) already handles the game's session for the schedule pages and does the same here.

**The cost.** The 23 Oct scan read 171 enterprises and 127 airports, about 324 pages including the letter pages, in
about 5 minutes (manual §7). 171 overview pages at the same pace add about **3 minutes**. Only 97 of the 171 fly
(91 rivals); the other 74 may still have aircraft on order, which is how a new rival shows before its first flight, so
B reads them all.

**Nightly or weekly.** Fleets and order books change slowly, and every use (the Competition screen's week-on-week
change, the Saturday report's three competitors) reads them weekly. A weekly read due "7 or more capture days" after the
last means a missed or failed evening simply moves it to the next one.

**The flag's number.** 25% means a quarter more aircraft on the way. Icelandair at 44% is flagged; an airline
replacing a few old aircraft (5 on order of 40, 12%) isn't. "At least 5" keeps a 4-aircraft start-up ordering 1 from
showing. Both are settings (`rival_orders_flag_pct` 25, `rival_orders_flag_min` 5).

**What gets stored.** One row per rival, type and read: owned, leased, overall, leased out, on offer, on order, average
age, kept for good (about 170 airlines × 3–4 types a week: some 35,000 rows a year, small).

**Where it shows:**
- **Competition:** each rival profile gains its fleet by type, aircraft on order and the change since the previous read;
  the group page lists the flagged rivals (big order books and starting airlines).
- **The weekly report:** each of our airlines' three competitors gains fleet, on order and the week's change; flagged
  rivals in the risks.
- Not in Today's Needs attention; Competition and the report are where rivals are read.

**The build.** One helper build: the capture userscript (version 1.8) and `gscan.py` read the pages; a new table and
`capture_scan()` kind; `competition()` gains fleets and flags; the Competition screen and the report; tests on a saved
overview page. **It needs one saved copy of Icelandair's overview page** from Gitesh's browser for the test sample
(a to-do once he goes ahead), since the page can't be fetched without his session.

## Scenarios and the risk of waiting
- **A rival is ordering big at one of our hubs:** today we see it only once its flights appear in the scan, weeks after
  the order. With B, the next Saturday report names it.
- **Waiting:** costs nothing in money; every week without it is a week of rivals' orders unseen.

## What would change the recommendation
- **The evening scan grows long or the game slows the pages:** C, or read fleets every 14 days.
- **Order books move within days in practice** (seen after a few weeks of reads): A.
- **The 25% flag fires on many rivals at once:** raise it to 35%.

## Outcome
**A, 23 Oct (Gitesh, Building chat):** every evening, all enterprises, as part of the world scan; the flags as
recommended (25% of the fleet and at least 5 on order; aircraft on order with no flights yet). Found while saving the
test sample: the overview page reads signed out (the built-in browser, not signed in, showed the full Fleet table), so
the fallback `gscan.py` needs only the redirect and its session cookie, as for the schedule pages.

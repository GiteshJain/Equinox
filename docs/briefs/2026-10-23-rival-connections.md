# Rivals' connecting options on our pairs — 23 Oct 2026

**Decision:** how to count rivals' one-stop connections on our city pairs, and when to work them out (decided in the
review chat on 23 Oct: display only, same airline, minimum connection time to 8 hours; this brief settles the measure,
a detour limit and the timing).

**Recommendation: A.**
- **Worked out once a night,** when the evening's world scan finishes, from the schedules it just read. No extra game
  pages, and about 1 to 3 seconds in the database.
- **Counted as departures a week that connect:** each rival flight leaving one end of our pair counts once if it
  connects onward on the same airline to the other end, so the figure sits beside direct departures on the same scale.
  It is never added to them.
- **Only sensible routings:** the two legs together no longer than **1.25 times** the direct distance
  (`settings.rival_connection_detour_max` 1.25), so Gatwick–Paris via New York doesn't count.
- Kept for our airlines' flown pairs and the pairs on their route lists, by rival, pair, direction and connecting
  airport.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A. Nightly at the scan's finish, stored; departures that connect; 1.25 detour (recommended)** | **none (display)** | **none** | **none** | **one helper build** | **low: one figure beside direct, clearly labelled** | **yes** |
| B. As A, but every combination of arriving and departing flight counted (an "option" each) | none | none | none | as A | inflated: a hub with 5 arrivals and 5 departures in the window counts 25, against 5 directs | yes |
| C. Worked out live when Competition or the report asks | none | none | none | as A | the whole world's schedules joined on every call: about a second already before grouping, against 3 seconds for the website's role and 8 for staff | yes |

## Background
**What it shows, from last night's scan** (scan 7, 23 Oct; same airline, minimum connection time at the connecting
airport or 90 minutes where unknown, up to 8 hours, days approximated):

| | Our flown pairs reached | Rivals | Weekly |
|---|---|---|---|
| Rivals' direct flights | 123 of 302 | — | 7,063 departures |
| One-stop, detour up to 1.25 × direct | 163 of 302 | 43 | about 22,800 combinations |
| One-stop, detour up to 1.5 × | 190 | 48 | about 32,300 combinations |
| One-stop, no detour limit | 270 | 60 | about 75,700 combinations |

Two things follow:
- **Without a detour limit almost every pair "has" a connection,** mostly through hubs nowhere near the way: the limit
  is what keeps the figure meaningful. 1.25 keeps a real hub on the way (Kolkata–Shanghai via Kunming); 1.5 starts to
  let in long doglegs.
- **Combinations inflate** (B): counting each first flight once (A) puts connections on the same scale as direct
  departures, so "Icelandair: 0 direct, 14 a week connecting via KEF" reads straight.

**How it's worked out.** For each rival, each flight into an airport is joined to its own flights out of it on the
same day (the next day where the first leg lands after midnight local), the gap between the airport's minimum
connection time (`world_airports.mct_min`, 90 minutes where unknown, as the website's trip search) and
`connection_max_wait_h` (8 hours, manual §4). The schedules give local times at each airport, so the gap needs no time
zones. Then only the pairs we fly or have on a route list are kept.

**Where it shows (display only):**
- **Competition:** each rival profile and each market gain a "connecting" figure beside direct, with the connecting
  airports; a pair's rivals list them in their own column.
- **Performance → a route's page, Rivals on the pair:** the same column.
- **The weekly report:** each of our airlines' three competitors gains its connecting departures on our pairs, never
  summed with direct.
- **Nothing else:** the openings' ranking, the contested test, hubs first, the three biggest competitors (still chosen
  by direct departures) and the fare pause don't read it. Whether they should is Gitesh's later decision.

**Storage.** One row per scan, rival, pair, direction and connecting airport; a few thousand a night. It is detail, so
it follows the scan schedules: archived after a full calendar month by the monthly archive, with a weekly summary per
rival and pair kept for good.

## Scenarios and the risk of waiting
- **A rival's hub sits between two of our cities** (Icelandair between Europe and North America): today it shows as
  nobody on the pair; with A, its connecting departures sit beside our direct ones.
- **Waiting:** costs nothing in money; the Saturday report keeps understating competition on the pairs a hub serves.

## What would change the recommendation
- **The 1.25 limit misses routings Gitesh sees as real competition:** 1.5.
- **Interline connections between rivals turn out to matter** (a later step; same airline only to start).
- **The database time at the scan's finish grows past a few seconds:** work it out in the nightly backup job instead.

## Outcome
*Pending Gitesh's decision.*

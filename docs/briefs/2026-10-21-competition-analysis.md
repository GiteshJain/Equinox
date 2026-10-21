# Competition analysis, and how often to scan the world — 21 Oct 2026

**Decision:** how often the world scan runs, now that competition analysis (the planner's next step) and the evening
order proposal depend on it.

**Recommendation:** **B, twice a week: Wednesday evening with the capture, and Saturday as now.** Rivals grew about
17% in 11 days, so a week-old scan misses a lot by the time it's used. Twice a week halves that for about 10 minutes
more each week.

| Option | Freshness when used | Extra work | What it gives competition analysis | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Weekly, Saturday (as now) | Up to 7 days old by Friday's orders | None | Market share and openings refresh weekly; a rival's move is seen up to a week late | Rivals growing ~10% a week are seen late; the rival pause works only week to week | — |
| **B. Twice a week, Wednesday and Saturday** | Up to 3–4 days old | One more 5–10 minute scan on Wednesday evening, run with the capture | Openings and threats twice a week; the rival pause can act within days | A little more load on the game's servers (the scanner already waits between pages) | Yes: drop the Wednesday scan |
| C. Every evening, with the capture | Under a day old | 5–10 minutes every evening | Daily threats; most data | Doubles the evening's time; seven times the load on the game for little extra over B | Yes |

## Background
- **The scans so far:** two, on 6 Oct and 17 Oct (the Saturday in between was missed). Each reads every airline in
  Gander and its schedule (163 airlines on 17 Oct) and the airport pages for our hubs and the big rival hubs, with
  `gscan.py`, in 5 to 10 minutes. Gander's owner allows the scanner (`world_rules.world_scanner`, manual §9).
- **The world is growing fast:** 83,792 departures a week on 6 Oct, 97,960 on 17 Oct (+17% in 11 days). The biggest
  rivals grew faster: Air China 5,012 → 6,552 (+31%), US Airways 3,884 → 5,074 (+31%), ANA 2,506 → 3,290 (+31%),
  Qantas 2,134 → 2,772 (+30%), American 1,636 → 2,328 (+42%).
- **Our share:** 3,274 → 4,016 departures a week, 3.9% → 4.1% of the world. Air China alone flies 6.7%.
- **The openings are large:** rivals fly 523 city pairs that touch one of our bases. We fly 104 of them; **419 we
  don't**. That's the list competition analysis ranks for the evening order proposal (route first, then the airline).

## What competition analysis would build (step 3, after this decision)
1. **Market share:** in each of our markets, our weekly departures against each rival's, and the change since the last
   scan.
2. **Threats:** rivals who started on, or grew on, one of our city pairs since the last scan. They're shown on Today
   that evening, and they pause the route on the fare ladder (manual §5).
3. **Openings, ranked:** pairs we don't fly yet, by the existing rule (manual §3, market share first). Within each
   variant's reach, and respecting hubs first and one airline per pair:
   - the largest city pairs first (stars at both ends);
   - then the pairs rivals fly most;
   - shorter sectors first where they give an aircraft more departures a day.

   The evening proposal takes its routes from the top of this list.
4. **Rival profiles:** each big rival's network, its growth since the last scan, and where it overlaps with us.

## Scenarios and the risk of waiting
- With A, a rival who starts on one of our trunks on a Sunday isn't seen until the next Saturday. That's a week of fare
  climbs on a route that's about to lose passengers, and a week of openings ranked on stale data.
- With B, the Wednesday scan catches it mid-week. It runs on Wednesday evening, alongside the capture.
- Waiting costs nothing for the decision itself: the build uses whatever scans exist.

## What would change the recommendation
- If running the scanner on Wednesdays is a hassle, A still works; competition analysis just refreshes weekly.
- If rivals' growth slows down as the world matures, B can drop back to A.

## Outcome
Gitesh, 21 Oct: neither A, B nor C as written. **The world scan moves into Capture all airlines**: after our six
airlines, the capture also scans the world when one is due. How often is a setting (`scan_every_days`), starting at
**every evening (1)**, since it costs no extra work, only 3–5 minutes on the evening's capture; it can be raised to
3 (about twice a week) if the evening gets long. Spec `docs/specs/2026-10-21-scan-in-capture.md`; competition
analysis follows it. Manual "Decided, not yet built" updated the same day.

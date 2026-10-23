# Aircraft age check — 22 Oct 2026

**Decision:** how the planner tracks each aircraft's replacement date (manual §3, replacement by age: new at 3 years,
used at 10) and when it warns.
**Recommendation:** B, one small build now. Record on each aircraft whether it came new or used and the date it was
built, put the 3, 10 and the warning window in `settings`, and let `fleet_checks()` warn on Today 60 days ahead with an
"order by" date. A nightly cross-check against the game's age catches a used aircraft that was never marked used.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A** No build: a to-do for mid-2029, used aircraft found from the order notes | none | none | none | none now | High by 2029: by then hundreds of aircraft, many used, checked by hand from free-text notes; a missed one flies past its replacement age | Yes |
| **B** Build now: new/used and built date on each aircraft, settings, a warning 60 days ahead with an order-by date, and the cross-check with the game's age **(recommended)** | none directly; keeps the fleet young without effort | none directly | none | one helper build (about an hour) and one migration | Low: dormant until 2029, but tested on every pull request against saved answers | Yes (revert the pull request) |
| **C** Record now, warn later: the new/used and built date columns now, the warning built in 2029 | none | none | none | two builds instead of one; the second by a helper who has to relearn all this | Medium: the warning is the part that matters, and it's left for later | Yes |

## Background
- **Nothing is due for almost three years.** The game's clock runs at real time: EI-ABD (AMS), delivered 28 Sep, read
  0.1 years on 22 Oct (game_fleet, 22 Oct). Our first new aircraft reach 3 years around 28 Sep 2029. The first used
  ones reach 10 years earlier: 9M-AAY (KUL) and G-AAFB (LGW), both 7.2 years when bought, around August 2029; N023AW
  (JFK), 3.6 years, around March 2033 (aircraft.order_note, 22 Oct).
- **Used aircraft are only in free-text notes today.** N023AW (JFK), 9M-AAY (KUL) and G-AAFB (LGW), all ordered
  22 Oct and arriving 23 Oct, say "Used, ex …, 7.2 years" in `aircraft.order_note`. Nothing a check can read.
- **The game's age is coarse.** `game_fleet.age_years` comes in tenths of a year (about 36 days), so judging from it
  alone, a warning could be over a month off. A built date (delivery date for a new aircraft; delivery date minus the
  age at purchase for a used one, from the market listing) gives a replacement day, about ±18 days for a used one
  because the listing is in tenths too.
- **The 3 and 10 are not in `settings` yet.** Manual §1 says rule numbers live there (one source), so the build adds
  them: replacement age new (3), used (10), and the warning window (60 days).
- **How early is early enough.** One delivery-line interval (15 h E195, 21 h A320 family, 30 h A350) is the least a
  replacement takes, but a new order joins the end of its line (manual §3), and the lines are kept full, so it can be
  days. It also needs the cash forecast to allow it on that evening. 60 days covers both with room, and the warning
  shows an order-by date: the replacement day minus the line's current wait (Today → Orders' delivery lines) and one
  interval. From then the replacement is part of the evening proposal like any other order.
- **The cross-check:** each night, if the game's age for an aircraft differs from its built date by more than 0.2
  years, Today's Fleet group says so (for example "looks used, marked new"). That covers a used purchase logged without
  its flag, which is the gap in the request.

## What B would build (the spec would set the details)
- `aircraft`: `acquired` (new or used) and `built_on` (date); backfilled from delivery dates, with the three used
  aircraft from their notes. Logging a used order (manual §3, the used market) records both from the listing.
- `settings`: `replace_new_years` 3, `replace_used_years` 10, `replace_warn_days` 60.
- `fleet_checks()`: a new kind, `replace`: "N001AW (JFK): replace by 28 Sep 2029, order by 25 Sep", from 60 days
  before; and the cross-check above. Today's Fleet group and Systems' Fleet board show them; Tails shows each
  aircraft's replacement date.
- Tests on a dated sample, the map, the planner guide and the manual's pointer to the settings rows.

## Scenarios and the risk of waiting
- **If it goes well,** each replacement comes up on Today two months ahead, the Scheduling chat folds it into the
  evening order, and the old aircraft's routes move to the new one on its plan card.
- **If a used purchase is logged without its flag,** the cross-check catches it the first night it flies.
- **Waiting (A or C)** costs nothing until 2029, but every used purchase until then is recorded only in prose, and the
  build would be done by someone with none of today's context.
- What happens to the old aircraft at replacement (handing it back, moving its routes) is the Scheduling chat's
  procedure, not this check's; it isn't decided here.

## What would change the recommendation
- If the game clock turned out not to run at real time (ages climbing faster), the first replacements would come much
  sooner and B becomes urgent rather than tidy.
- If the replacement rule is likely to change before 2029, C becomes reasonable: record the facts now, build the
  warning against the rule in force then.
- If used purchases stay rare (three so far), A's hand check is less risky, but the fleet is set to grow every evening.

## Outcome
**B, 22 Oct 2026 (Gitesh), simplified:** "its fine to use games age, dont need to be so precise". No built date: the
check reads the game's age (`game_fleet.age_years`, tenths of a year) against the replacement age, and warns once the
aircraft is within the warning window of it. Each aircraft records whether it came new or used. The cross-check stays,
from the game's age against the delivery date. Spec: `docs/specs/2026-10-22-aircraft-age-check.md`. The manual's §3
bullet names the settings rows when the build merges.

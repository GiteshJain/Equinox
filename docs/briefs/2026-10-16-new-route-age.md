# When a new route can be marked losing — 16 Oct 2026

**Decision:** how long a new route is left alone before Home and Check mark it losing or to fix.
**Recommendation:** an age condition: no problem mark until the route has flown for 7 days.

## Options
| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| 1. Raise the minimum departures (2 to about 10) | none | none | none | a route that really is bad waits for 10 departures | a route with two daily rotations is judged after 5 days, one with a single after 10; the count isn't the age | yes: one setting |
| 2. Route-age condition, 7 days (chosen) | none | none | none | a bad new route is flagged a few days later than before | needs a code change (one function) | yes: set `growth_new_route_days` to 0 |
| 3. Leave it | none | none | none | Needs attention lists every new route on day one, which hides real problems | none | n/a |

## Background
- 16 Oct, Home: PVG–CCU and KUL–TRV "losing money". Source: `route_profit()` for China Eastern and Malaysia over 7 days.
  Each had 2 flights, both on 15 Oct (economy 4% and 3%, 9% and 2%; profit per flight about −4.7k and −2.6k).
- Both routes were launched in the planner on 13 Oct (`rotations.launched_on`), so they are 3 days old on 16 Oct.
- The mark needs `growth_losing_min_departures` = 2 departures; the other problem marks need 5 (`growth_fix_min_departures`).
- I expect loads to build after launch, but this wasn't checked against earlier launches in the data.

## Scenarios and the risk of waiting
- With the condition, a new route shows no problem mark for 7 days, then is judged on its last 7 days of flights (which by
  then are all after launch except the first day or two).
- Without it, each launch shows up as a problem on day one and the list stops being a signal.

## What would change the recommendation
If new routes in the data turn out to ramp slower or faster than a week, change the setting (one number, with the manual).

## Outcome
Option 2 with N = 7, decided by Gitesh on 16 Oct 2026 in the Building chat. One scope call made in the build, for
Gitesh to confirm or narrow: the gate covers `fix` as well as `losing` (and the thin-margin fix), since `fix` would
otherwise mark the same routes after three days. Manual §3 updated (new rule, since 16 Oct); no rule retired.

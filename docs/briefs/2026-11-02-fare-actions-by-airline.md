# Apply fare plan timing out: read one airline at a time

**Decision (Gitesh, 2 Nov 2026): option B.** The fares userscript reads this week's changes one airline at a time
(`capture_fare_actions_by_airline()`), each call well under its 30-second limit. To-do 194.

**Recommendation was B:** it works today with room to grow, is one pull request, and the only step for Gitesh is
reinstalling the fares userscript.

## Options

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo |
|---|---|---|---|---|---|---|
| A. Raise `capture_fare_actions()`'s limit to 120 s (first chosen) | none | none | none | the week's 311 fare moves stay unmade | **doesn't work**: calls through Supabase's API are cut off at 60 s whatever the function sets | yes |
| A2. Raise it to 60 s | none | none | none | as A | fails today (about 70 s needed) and more as routes grow | yes |
| **B. One call per airline** | none | the week's fare moves made tonight | none | about 45 minutes of building | low: the slowest airline took 14.8 s, half its limit; one airline would need to double before it matters | yes: revert, and the old userscript still works on a small world |
| C. Work the actions out when Put on the fare plan is pressed, store them | none | as B, a day later | none | about twice B's building; a planner change | stored actions can go stale between planning and applying | harder: a table and a planner change |
| D. Make `fare_ladder()` faster | none | unknown | none | investigation before anything is applied | no guarantee of under 30 s for all six | yes |

## Background
- 2 Nov, Saturday review chat: Apply fare plan stopped with "couldn't read the fare plan (canceling statement due to
  statement timeout)". `capture_fare_actions()` works out every airline's `fare_ladder()` in one call, under its own
  30-second limit (21 Oct). Timed on live, 2 Nov: Pan Am 11.4 s, Kingfisher 9.4, Ryanair 9.8, Virgin 12.5, China
  Eastern 14.8, Malaysia 12.1: about 70 s.
- Supabase's documentation (Database → Timeouts): "Dashboard and Client queries have a max-configurable timeout of 60
  seconds." The userscript calls through the API, so no function limit above 60 s takes effect. Option A was chosen
  before this was known; it was caught before anything was built.
- The week's fare plan: 311 directions, put on the plan 2 Nov 21:07–21:27 UTC, waiting.

## Scenarios and the risk of waiting
- Waiting a day: bookings open 3 days ahead (manual §9), so every day the plan isn't applied, a further day of flights
  sells at the old fares, and next Saturday's ladder judges a week that is partly at old prices.
- Growth: each airline's ladder grows with its own routes. At today's pace, the slowest (China Eastern, 14.8 s) would
  need about twice its routes before it reaches 30 s; then the same split can go per base.

## What would change the recommendation
- If reinstalling the userscript on each device were a burden: C needs no userscript change.
- If one airline's ladder alone nears 30 s: split further (by base), or D.

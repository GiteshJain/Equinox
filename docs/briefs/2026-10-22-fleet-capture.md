# The fleet in the evening capture — 22 Oct 2026

**Decision:** whether the evening capture reads each airline's fleet pages, and how much we build on it now.
**Recommendation:** B. Capture the fleet every evening and act on it at once: maintenance, crew and cabin alerts on
Today, and the planner kept in step with the game. Keep a night-by-night history so that, after about two weeks, the
planner's maintenance figure can be fitted to the game's real ratios (C) with data instead of guesses.

The money columns of the usual table don't apply; what's at stake is aircraft running below 100% maintenance unseen,
as N003AW (JFK) did from 18 to 22 Oct.

| Option | What it is | Build | Risk | Easy to undo? |
|---|---|---|---|---|
| A. Maintenance alert only | The capture reads every fleet page; Today flags any aircraft under 100% maintenance | About 2–3 hours | Low; nothing kept beyond tonight, so nothing to learn from | Yes |
| **B. The fleet captured and kept, with its checks** | **A, plus each aircraft's condition, seats as fitted, crew and location kept night by night; Today flags maintenance under 100%, no pilots, seats that don't match the planner's cabin, and aircraft in the game but not the planner (or the reverse)** | **About half a day** | **Low; one more capture page kind, tested like the others** | **Yes** |
| C. B, plus the maintenance figure fitted to the game | The planner's maintenance figure learns, per type and cabin, the ground time the game really keeps, from the captured ratios against the flown schedule | B, then about half a day once two weeks of nights are in | Fitting too early on too few aircraft would make the figure worse, not better | Yes |
| D. Leave it | Maintenance is checked by eye in the game | None | Another N003AW goes unseen until its condition shows it | — |

## Background
Sources: Gitesh's saved JFK fleet page (Pan Am, 22 Oct), the Scheduling chat (22 Oct), `lib/rules/src/maintenance.ts`
and the database (22 Oct).

- **What the fleet page shows, per aircraft:** registration and type, where it is and the flight it's on, age,
  condition and maintenance ratio (N003AW: 83% / 103.8% after the fix), seats as fitted (Y/C/F), whether it has pilots,
  owned or leased and the contract's state. Each airline's aircraft sit in fleets (Gitesh keeps one per hub), so the
  capture reads every fleet of every airline: about two dozen pages, about a minute more each evening.
- **N003AW (JFK):** the game showed 0.0% maintenance from 18 to 22 Oct while the planner showed 132%, and its condition
  fell to 83%. The 15 Oct refit (172 to 195 seats) lengthened its turnarounds, so its two 193-minute JFK gaps no longer
  fitted maintenance; N001AW, N013AW and N014AW got the same refit but kept gaps of 264 minutes or more. Moving
  AW1023/1024 71 minutes earlier fixed it (103.8%). The captured flights showed it too: no maintenance charge on any
  N003AW flight after 18 Oct, while every other aircraft had one a day.
- **Why the planner missed it:** its maintenance figure counts each ground gap's time beyond the type's
  `ground_keep_min`, one number per aircraft type. The game's turnaround grows with the seats fitted, so a refit to more
  seats eats into maintenance time the planner still counts. C fixes this from the game's own ratios; B's history is
  what C needs.
- **A blank location is not an idle aircraft:** N004AW (JFK) and N020AW (JFK) show no flight on the saved page but
  both flew on 22 Oct; they were on the ground between flights. An idle-aircraft check would use the schedule, not that
  column (not in this brief).
- **The one-week aircraft checks** were retired on 15 Oct (manual §1) and removed from the planner on 22 Oct (#75).
  B is what replaces them: every aircraft checked every night, by the game's own figures.

## Scenarios and the risk of waiting
- **B goes well:** a maintenance shortfall shows on Today the evening it starts; wrong cabins and missing aircraft show
  the same night; two weeks on, C has the data. **Goes badly:** a fleet page the capture misreads; each page is checked
  as it arrives like the other pages (#21), so a short or broken page shows that night.
- **A** catches maintenance only and keeps nothing, so C would have to wait for B anyway.
- **Waiting** leaves maintenance to the eye, with about one new aircraft a day per line across six airlines.

## What would change the recommendation
- If the fleet pages turn out to be slow to read (many pages per airline), the fleet capture could run every other
  evening; the alerts would then lag a day.
- If the game shows a turnaround per layout on another page, C could use that directly instead of fitting it.

## Outcome
22 Oct 2026, Gitesh: **B and C**, "as maintenance and turns can change as the world grows". B is built now. C follows once about two weeks of fleet nights are in, and refits on its own every week from the latest nights rather than once, so the planner's figure follows the game as it changes.

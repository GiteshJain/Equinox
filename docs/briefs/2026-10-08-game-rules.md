# Game-rules exposure — 8 Oct 2026 (decision #12)

**Decision:** what to do about the parts of how we play that AirlineSim's rules don't allow, or may not allow.
**Recommendation:** C.
- **Stop now the parts the written rules most clearly forbid:**
  - the interline agreements between your own six airlines;
  - the automatic salary step;
  - the world scanner.
- **Then ask AirlineSim support for a ruling** on what remains: the shared alliance, the read-only daily capture and
  the schedule check.

The downside of a penalty, which can fall on all six airlines at once, is far bigger than what these parts earn.

*Columns adapted for a non-game decision: exposure instead of growth.*

| Option | Exposure left | Cost to the airlines | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Carry on, ask nothing | All of it: the self-interlines (publicly visible), the automatic salary step, the world scan, the capture | None now | None | Any player can see the interlines and report them; penalties are listed below | — |
| B. Ask first, change nothing until AirlineSim answers | All of it until they answer, now known to them | None now | None | Disclosing an active breach while it runs; they may act on it | Yes |
| **C. Stop the clearest breaches, then ask** | **The alliance, the daily read-only capture and the schedule check, all asked about openly** | **Passengers connecting between your airlines lose the interline; salaries go back to a monthly hand review; the weekly competitor scan pauses** | **Connection strategy reworked in the Monthly chat** | **Low: only what we've asked about remains** | **Yes, if AirlineSim approves** |
| D. Strictest: C, and stop the capture too | None | As C, and the planner goes back to loads typed in by hand | The planner's numbers (forecast, route profit, load report) go stale | Lowest | Yes |

## Background
### What the rules say
*From Gander's rules page and the simulogics terms, both read on 8 Oct.*
- **Rule 2.3, Multiple Holdings:** "Only applies to game worlds allowing more than one holding per account. In some game
  worlds, a single player may control more than one holding, however co-operation between multiple holdings is
  expressly forbidden. This includes but is not limited to:" stock-market deals, providing services, and buying,
  leasing or selling aircraft between the holdings.
- **Rule 1.4, Hard Coding:** "Just because the game allows it, does not mean it is not against the rules."
- **Rule 2.2, Dummy Holdings:** a holding that barely flies and exists to give another holding traffic rights is
  prohibited.
- **Terms §5.3:** "The usage of applications, software, scripts or similar which allow for an automated usage or
  control of the game is prohibited." Also forbidden: scripts "which grant the user an advantage over other users who
  do not make use of such". simulogics "may explicitly approve of certain third-party software or scripts".
- **Penalties:**
  - **Rule 1.2:** they "can, but are not limited to, removal of in game resources (cash, aircraft, equity etc), removal
    of accounts, or banning from game worlds".
  - **Terms §9.7.2:** the account can be cancelled for conscious violations after a warning.
  - **Terms §9.8:** access can be barred for up to a month.

### How we play today
*From the game's public pages and the code, 8 Oct.*
- **Six holdings, one player.**
  - Kingfisher Airlines Limited, Ryanair Holdings PLC, Pan American Airways Corporation, Virgin Group, China Eastern
    Air Holding Company and Malaysia Aviation Group each list DevilsVengeance as managing director.
  - Each has one operating airline. All six airlines are in the alliance "equinox".
  - Gander evidently allows several holdings per account, so rule 2.3 applies.
- **They interline with each other.** Kingfisher's public "Contractual partners" page lists China Eastern, Malaysia,
  Pan Am, Ryanair and Virgin Atlantic as "Alliance · Interlining". The planner's own notes say "the group's airlines
  already interline with each other". Pan Am's British Caledonian interline is being cancelled because Virgin now
  carries Pan Am's UK connections "inside the group".
- **What players say.** In the AirlineSim forum (2013, posters not marked as staff), players said one person's
  holdings "can be in the same alliance" but are "not allowed to interline". That matches rule 2.3's "co-operation ...
  expressly forbidden". The rule's list says "not limited to", so interlining isn't named, but it isn't excluded either.
- **The capture.** One press, run by you in your signed-in browser. For each airline it opens about 20 game pages:
  events, up to 15 bank-statement pages, income statement, balance sheet and loads. It sends what it reads to our
  database. It changes nothing in the game, except the salary step.
- **The salary step.** Part of the same press. For every position it presses "adjust" to set the salary to 10% above
  the country average. That is the script acting in the game: "automated ... control" in §5.3's words.
- **The world scanner.** `scripts/scanner/gscan.py`, signed out. It reads about 314 pages: 26 directory pages, 161
  airlines' schedules and 127 airport pages. It ran once, on 6 Oct, for the weekly report and gander monthly. It is
  automated use, and it gives an advantage over players who don't scan.
- **The schedule check.** Reads one public schedule page per airline when the planner's Game check runs.
- **Not affected:** the planner, the website, the reports and Claude's advice. These are outside the game, and the
  rules don't cover planning tools you use yourself.

### What C would do
- **In the game (you):** cancel the interline agreements between your own airlines. Each airline's interlines with the
  other five, so up to 15 agreements. The alliance stays until AirlineSim answers.
- **In the code (a pull request):**
  - remove the salary step from the capture;
  - stop the scanner;
  - write the rules into the manual.
- **Back to the old way:** the monthly staff-salary review returns, by hand.
- **Ask AirlineSim support** (support@airlinesim.aero, the address the rules give). Claude drafts the message for you
  to send. It says plainly:
  - what the six holdings are;
  - that the self-interlines were cancelled;
  - and it asks:
    1. Is a shared alliance allowed?
    2. Is a once-a-day, read-only capture of your own pages allowed, or can it be approved under §5.3?
    3. Is the schedule check allowed?
    4. Could a weekly read of public pages be approved?
- **Hold the low-demand holdings plan** (Serbia and Kenya, on the To-do board) until the answer. As planned, both
  would "join the group interline", which is the same issue, and rule 2.2 applies to holdings with "grossly limited
  expansion".

## Scenarios and the risk of waiting
- **If AirlineSim looks and we've done nothing (A):** the self-interlines are on every airline's public page, and
  competing players in your markets can see them. The rules let AirlineSim remove cash or aircraft, or bar the account
  that runs all six airlines. One account means one penalty hits everything at once.
- **If we ask while everything still runs (B):** a good-faith question often gets "please change X". But it also tells
  them about a breach that's still running.
- **If we tidy up and then ask (C):** the question shows good faith, and only the uncertain parts remain. The cost is
  the connecting traffic between your airlines. The captures can't measure how many passengers connect between them,
  so the Monthly chat should rework the connection strategy with that in mind. Each airline's own connections at its
  own hubs are unaffected.
- **Waiting:** every day the interlines stay up is a day they're visible.

## What would change the recommendation
- **If AirlineSim says interlining between one player's holdings is allowed,** or approves it: restore the interlines.
  The cancellation is easy to undo.
- **If they approve the capture or the weekly scan under §5.3:** keep or restore them, and note the approval in the
  manual.
- **If they say the capture isn't allowed:** move to D, with loads typed in by hand, as before 7 Oct.

## Outcome
Open: waiting for Gitesh's decision.

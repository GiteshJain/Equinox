# The fare ladder timing out outside capture times

**Decision:** how to stop Performance's fare ladder hitting the database's 30-second limit.
**Decided 26 Oct 2026 (Gitesh): option E,** raised by Gitesh: no fare ladder overview on the group page; each airline's
page shows its own ladder. Spec: `docs/specs/2026-10-26-fare-ladder-one-airline.md`. (First recommended: B.)

## Options

| | A. Store each ladder once per capture | **B. One ladder at a time** | C. Make the ladder faster | D. Leave it |
|---|---|---|---|---|
| What changes | A table of each airline's ladder, written after each capture and after every fare-plan save | The planner gives `fare_ladder()` its own queue of one | A helper profiles the ladder's own queries (1.2 s of its 1.7 s) and reworks them | Nothing; the planner retries |
| The fare ladder board | Opens at once | Fills in about 8 to 10 s, one airline after another | Depends on the gain, unknown | Errors when anything else runs at once |
| Growth, profit a week, cash at lowest | None | None | None | None |
| Opportunity cost | Biggest build: a table, its writes, its staleness rules | Small planner change, about an hour with the checks | 1 to 3 hours of a helper, result unknown | Saturday's review may stall on the board |
| Risk | A stored ladder that's out of date: holds and pauses end by date, and every fare-plan save changes it | Slower board; other screens' figures still share the database | May find no big win | Errors on 31 Oct, the first per-direction Saturday |
| Easy to undo | Medium | Yes (revert) | Yes | — |

**E. Each airline's own page** (Gitesh's option, decided): the board leaves the group page, which keeps one link per
airline, and goes on each airline's page, where its ladder is already read for the route profit table's fare index.
The board loads in 1 to 2 s with no extra call, the group page gets lighter, and the overview of all six goes (links
only). About an hour's build; easy to undo. Better than B on every count but the overview.

## Background
- **26 Oct, 13:03 Chicago (18:03 UTC):** eight fare ladder calls cancelled at 30 s between 18:03 and 18:05 UTC, and the
  rest took 10 to 26 s. Also 24 to 26 s at 17:48–17:50 UTC. The last capture page was at 17:30 UTC, so no capture or
  scan was writing (postgres and edge logs). This is the trigger set this morning ("raise it again only if failures show
  outside capture times", handover 26 Oct).
- **Alone, each ladder takes 1.1 to 1.9 s** (all six one after another, 18:06 UTC, run as postgres): 7.5 s together.
  The database is 141 MB, all in memory (cache hits 100%).
- **Why it slows:** Performance asks for all six ladders together (four at a time through the planner's one queue, #97),
  with growth signals (15 s in the same minute) and the other figures. On the free plan's small shared processor,
  four heavy calls at once each run 10 to 20 times slower than alone. #107 (per direction, merged 26 Oct) doubled the
  rows each ladder works out (Virgin 252, China Eastern 272).
- Profile of one call (Virgin): 1.7 s, of which 1.2 s is the ladder's own queries, 0.4 s the rival threats.

## Scenarios and the risk of waiting
- Saturday 31 Oct is the first review with the per-direction ladder; Put on the fare plan needs the board to load.
- Waiting costs nothing in the game, only errors on the screen.

## What would change the recommendation
- If B still times out when the whole Performance screen loads, C next (and A only if C finds no win).
- If Gitesh would rather the board open at once, A.

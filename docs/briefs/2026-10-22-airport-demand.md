# Reading a new airport's passenger demand by itself — 22 Oct 2026

**Decision:** whether the evening capture reads the game's passenger demand for airports by itself, or it stays a
step a chat does by hand whenever an airport joins a list.
**Recommendation:** B. Keep each airport's demand in the database and have the capture's world scan read it, once, for
every airport on our lists that doesn't have it yet. The stars then follow from your scale without anyone having to
remember. Your rule doesn't change: stars stay written as each route's stars override, and a star typed by hand is
never overwritten.

The money columns of the usual table don't apply; what's at stake is new routes ranked and sized on the research's old
stars until someone reads the airport.

| Option | What it is | Build | Risk | Easy to undo? |
|---|---|---|---|---|
| A. By hand, as now | Whichever chat adds an airport reads its page and writes the stars | None | A chat forgets, and the opening is ranked and sized on the old rating (Shanghai Hongqiao sat at 2 stars at demand 10) | — |
| **B. The capture reads it, once per airport** | **A demand column per airport; the world scan reads the airport pages still missing it (a few a night once the backlog is done) and writes the route stars from your scale** | **About half a day** | **Low: read-only pages the scan already knows how to read; hand-typed stars kept** | **Yes** |
| C. B, and stars worked out from demand everywhere | Stars become a figure read from each airport's demand; overrides only for hand edits | About a day | Changes your 22 Oct choice of overrides; every screen and figure that reads stars changes | Yes, with more work |

## Background
Sources: the review chat (22 Oct), the manual §3 ("Size by city stars"), `capture/capture_all.user.js` and the database.

- **What the review chat did:** read every airport on our lists from its Gander page (1,346 of 1,364; 18 codes didn't
  match, mostly closed airports or codes the game spells differently) and wrote the stars from your scale (9–10 five,
  7–8 four, 5–6 three, 3–4 two, 0–2 one) into each route's stars override: 2,405 of 5,307 routes changed. The demand
  numbers themselves weren't kept in the database, only the stars.
- **The rule today:** demand doesn't change, so it's read once, "and read for every new airport when it joins a list".
  Nothing does that by itself yet.
- **What the capture can already do:** since 21 Oct its world scan reads airport pages (`/app/info/airports/<id>`, the
  same public page the review chat read) for our bases and the big rival hubs, and keeps each page's details. It
  doesn't read the demand bar yet.

## How B would work
1. A column on each airport in the world: its passenger demand (0–10), with when it was read. The 1,346 values the
   review chat read are loaded once from its notes, or read again by the scan over the first evenings.
2. The world scan adds, to the airports it already reads, up to about 30 airports a night that are on any of our lists
   and have no demand yet (a minute or two more). A new airport added in the afternoon is read that evening.
3. When an airport's demand arrives, every route to it whose stars aren't typed by hand gets its stars override from
   the scale; the change log records it as the capture's.
4. Systems shows how many listed airports still have no demand. The 18 codes the game doesn't know are listed there to
   fix by hand.

## Scenarios and the risk of waiting
- **B goes well:** a new airport's stars are right the evening it's added, and openings and aircraft sizing follow.
  **Goes badly:** an airport page the scan can't match to a code; it stays on the Systems list until fixed by hand.
- **A** works as long as every chat remembers; the review chat's new Kingfisher and Malaysia lists alone add dozens of
  airports this week.
- **Waiting** costs little until the next big list arrives.

## What would change the recommendation
- If you want stars to change when a city's demand does (the game says it doesn't), C.
- If no new airports are planned for a while, A is enough for now.

## Outcome
22 Oct 2026, Gitesh: **A**. "Every time we open a new airport, check the demand at that time; demand is constant, so no need for regular checks." The chat that adds an airport reads its page and writes the stars from the scale (manual §3, already so). Known limit: nothing flags an airport that was missed, since stars were written as overrides only where they changed; B's demand column is the fix if a miss ever matters.

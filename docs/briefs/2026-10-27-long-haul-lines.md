# Long haul in 7-day lines (circuits)? — 27 Oct 2026

*Scheduling chat. Discussed through 27 Oct (Gitesh), with the experienced players' view from the Gander Discord and
tonight's new default line (brief `2026-10-27-real-aircraft-reach.md`). Figures: block time 25 minutes plus distance
over the type's speed (manual §4), turns at the type's turnaround plus 10 minutes, one maintenance stop sized by the
planning library's model; the A350 sample line of 27 Oct checked with `check-card`.*

## Decision and recommendation
**Recommendation: B.** Routes whose round trip doesn't fit in a day, those beyond about **7,750 km** (nearly every
A321XLR route and every A350 route), are planned as **7-day rotating lines**: 7 aircraft of one type at one airline fly
one weekly pattern, each a day apart, so every route on the line flies daily at the same time. **XLR lines first**
(about 21M up front for 7); A350 lines wait for the narrowbody-against-A350 question. Everything shorter keeps the
24-hour day. Built properly before the first line (below), so nothing is done by hand.

## Why there
| Aircraft | Distance | Round trip with turns and maintenance | Day used |
|---|---|---|---|
| A321LR | 6,750 km | 21.6 h | 90% |
| A321LR | 7,700 km | 23.9 h | 99% |
| A321XLR | 7,750 km | about 24 h | the limit |
| A321XLR | 8,600 km | 26.0 h | doesn't fit |
| A350 | over 8,600 km | over 24 h | doesn't fit |

Up to about 7,750 km a 24-hour day is 90–99% used, and a line adds little (manual §3: the A320neo Heavy covers up to
6,750 km, so "LR and above" starts there). Beyond it, one aircraft can't fly a route daily, and a pair gives only 6 a
week (each leaves every other day, and the week's 7 days won't close) unless day 7 leaves one bank earlier. A line flies
every route daily at the same time, and lets arrivals sit in the banks at either end (the 4-hour planning target,
spec `2026-10-27-planning-connection-target.md`). Short and medium haul: under 2% to gain (days already end within
minutes of 24 hours), against routes opening a week later and every route change touching 7 aircraft, so not there.

**Enough routes:** 4- and 5-star routes on the lists, XLR band (7,700–8,600 km) and beyond 8,600 km:
Pan Am 48 and 208, Virgin 30 and 61, China Eastern 28 and 51, Kingfisher 12 and 33, Malaysia 8 and 42. Ryanair none.

**What players do** (Gander Discord, 27 Oct): 24-hour days for short and medium haul; 168-hour lines for long haul,
"7 planes for 5–6 routes daily".

## Options

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. 24-hour days and pairs (day 7 one bank earlier) | long haul daily, day 7 at another time | most of a line's use: a pair plus a medium route in its gaps | an order at a time | day 7's connections differ; pairs need a medium route to fill each gap | low | yes |
| **B. Lines beyond about 7,750 km, XLR first, built (recommended)** | **every long route daily, same time, in the banks** | **about 6–7 routes per 7 aircraft (players and our A350 sample: 6 routes, 17.7 h a day each)** | **about 21M per XLR line, over about 6 days of orders** | **routes on a line open when its 7th aircraft arrives, about a week after the first; the Building work first** | **medium: a wrong entry on one aircraft affects its day of the line; caught by the line check** | **yes, aircraft can go back to 24-hour days** |
| C. Lines, planned by hand now, built later | as B | as B | as B | Claude's script and Gitesh's care stand in for the checks | higher: nothing checks a line as a whole | yes |
| D. Lines from 6,750 km (the LR too) | a little more on LR routes | small: LR days are already 90–99% used | about 20M per LR line | as B, for little gain | as B | yes |

## What gets built (B), in the Building chat, before the first line
1. **Line optimiser** (planning library): from an airline, a type, its hubs and the candidate routes (long ones and
   medium fillers), the best 7-day rotating line: turns, night bans, the same-route gap, reach (§3), maintenance stops
   no more than 40 hours apart, arrivals in banks under the 4-hour target. Hands back the 7 plan cards.
2. **Lines in the planner:** the 7 cards grouped as one line (line and day), shown together on Tails; each aircraft's
   card written from the line, with its day offset, when it's ordered.
3. **Card check across a line:** every flight daily across the line, the same flight number on different days not a
   clash, and the maintenance spacing (a new setting, 40 hours).
4. **Filing, Game check and route profit that understand lines:** a flight's return on another day of the same
   aircraft, each aircraft compared day by day, aircraft hours across the line.
5. **Pool progress on Today → Orders:** "XLR line, Pan Am: 3 of 7 ordered".
6. **Tests:** a saved sample line through every check above.

Probably 3–4 pull requests over a day or two. In the game, Gitesh sets up each aircraft with the schedule editor's copy
and offset (no extra work against today).

## Scenarios and the risk of waiting
- Nothing needs a line before the first XLR route beyond about 7,750 km is ordered. November's trunks open shortest
  first, so those come late in the month; deciding now lets the build land before them.
- If an airline can't fund 7 XLRs within about a week of starting, its line flies some days short until the last
  aircraft arrives; the pool progress (item 5) shows it.

## What would change the recommendation
- The Building work turns out much larger than a day or two: C for the first line, B as it's built.
- A rival competes on frequency on a long route: two aircraft on that route alone, outside the line.
- The narrowbody-against-A350 question (waiting on this) says long haul waits altogether: B's build can wait with it.

## Outcome
**B, Gitesh, 27 Oct.** Spec `docs/specs/2026-10-27-long-haul-lines.md`, built after the short-connections target; manual lists it under Decided, not yet built.

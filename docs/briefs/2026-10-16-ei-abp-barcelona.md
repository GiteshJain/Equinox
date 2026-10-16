# EI-ABP opens Ryanair's Barcelona base: its routes — 16 Oct 2026

**Decision:** what EI-ABP, the first of the three A321neos opening Barcelona (14 Oct Ryanair brief, option C), flies.
It landed 16 Oct 01:33 UTC. A new base, so a full brief (manual §1). EI-ABQ lands tonight and EI-ABR on Saturday.
**Recommendation:** C, Dublin, Munich and Vienna. Dublin and Munich are five-star cities nobody flies from Barcelona;
Vienna is four-star with no rival and, from Paris, earns like a five-star (18.7k a flight). It's the longest day that
fits (11.9 hours, maintenance 147%) and the best estimated money. Zurich and Rome go on EI-ABQ tomorrow.

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Munich + Zurich + Dublin | 3 new 5-star routes, no rival · 33 links at both ends · 10.7 h a day | ~0.49M (~104k a day) | no change (bought) | Vienna waits | no Barcelona loads yet | yes |
| B. Munich + Dublin + Rome | 3 new 5-star (Rome: Alitalia 2 a week) · 10.7 h | ~0.47M (~102k a day) | no change | Zurich waits | as A | yes |
| **C. Dublin + Munich + Vienna** | **2 new 5-star + 1 new 4-star, no rival · 30 links · 11.9 h a day** | **~0.56M (~114k a day)** | **no change** | **Zurich waits a day** | **as A** | **yes** |
| D. Dublin + Zurich + Rome | 3 new 5-star · 10.1 h | ~0.43M (~96k a day) | no change | Munich waits | as A | yes |

Profit is estimated from Ryanair's own routes of similar length and stars (route profit, 7 days to 16 Oct, the
airline briefing): Amsterdam–Barcelona 20.2k a flight (1,241 km), Amsterdam–Rome 20.2k (1,297), Paris–Vienna 18.7k
(1,035), Paris–Rome 15.3k (1,100), Paris–Munich 14.2k (681), Paris–Dublin 13.8k (786). So Dublin (1,486 km) about 21k,
Munich (1,095) 17k, Vienna (1,370) 19k, Zurich (856) 14k and Rome (848) 13k. The lease is about 34k a day. Four
routes in a day don't fit: every try broke a night ban or maintenance.

## The plan card (option C)
Checked with the planning library's card check on the 16 Oct tables: no short turns, night bans or number clashes;
maintenance 147%; 11.9 block hours a day. Flight numbers from Barcelona's block, 1005 on (the base's record already
shows 1004 as its last number used, `airline_bases`; the library's next free pair).

| Flight | From | Leaves (local) | To | Arrives (local) |
|---|---|---|---|---|
| FR1005 | Barcelona | 02:35 | Dublin | 03:46 |
| FR1006 | Dublin | 05:02 | Barcelona | 08:13 |
| FR1007 | Barcelona | 09:29 | Munich | 11:12 |
| FR1008 | Munich | 12:28 | Barcelona | 14:11 |
| FR1009 | Barcelona | 15:27 | Vienna | 17:30 |
| FR1010 | Vienna | 18:46 | Barcelona | 20:49 |

Daily; service R; cabin 321-STD; fares 85% of standard, economy only (manual §5).

## Background
- **Ryanair** (briefing, 16 Oct 03:29 UTC): profit 1.01M a day, load 100%, cash 4.57M (its lowest point is now).
  Every route sells out; 24 are on the "ready for another flight" list.
- **Barcelona** (6 Oct scan): Air Europa 203 departures a week, Iberia 84. Nobody flies Barcelona–Dublin, Munich,
  Zurich or Vienna; Alitalia has 2 a week to Rome; Lufthansa 70 to Frankfurt; TAP 42 to Lisbon; Iberia 168 to Madrid.
  London is Virgin's under one airline per city pair.
- **Connections:** few at first; Barcelona's feed is Ryanair's Paris and Amsterdam flights and Virgin's Gatwick ones.
  The three aircraft together give the base its own network.
- **Ryanair is exempt from hubs first;** Barcelona is a focus base like Paris and Amsterdam.

## What would change the recommendation
- Opening with three five-star cities as the order brief put it: A.
- Barcelona's first loads (from Saturday night) weak: switch the third route to a shorter, proven-type route.

## Outcome
*Open.*

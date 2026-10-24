# Malaysia's aircraft: Sanya, Medan and Haikou on an A320neo SHARP — 24 Oct 2026

**Decision:** Malaysia's order this morning.
**Recommendation:** A. A new A320neo SHARP at KUL on openings 2 and 3, Sanya and Haikou (5-star, no rival), with
Medan (4-star, no rival) filling the day: 12.9 block hours a day, 129 connections.

| Option | Growth | Hours a day | Connections | Cash at the lowest point | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A Sanya, Medan, Haikou** | 3 new routes, 42 departures a week | **12.9** | **129** | 0.61M | New markets, no rivals | Yes |
| B Sanya, Haikou | 2 new routes, 28 departures | 11.3 | 88 | 0.61M | Same | Yes |
| C Sanya, Guiyang (ranks 2, 4) | 2 new routes, 28 departures | 12.7 | 91 | 0.61M | Leaves rank 3 | Yes |

## Background
- **Cash** (capture 24 Oct 10:10 UTC, all six "all good"): `cash_forecast(6)` had the A320neo SHARP and E195 safe now;
  with the SHARP and cabin (2.22M), 0.61M at the lowest point, right after ordering. The other five airlines can order
  from the next capture. Used market: only an A321LR at 2.2M down, dearer than this new SHARP and below the cushion.
- **Openings** (`competition(6)`): rank 1, Melbourne (6,315 km), needs an A321XLR and counts as long-haul, which waits
  for Malaysia's feeder-first trigger (manual §2). Ranks 2 to 4 (Sanya 1,923 km, Haikou 2,134, Guiyang 2,701) are
  within the SHARP's 3,355 km. All three don't fit one aircraft's turns; Medan (rank 66, 330 km) fits beside two.
- **Schedule** (`optimise` and `check-card`, trimmed `rules_input` for KUL), KUL local (UTC+8): MH1127/1128 Sanya
  11:00, back 17:40; MH1129/1130 Medan 18:56, back 21:50; MH1131/1132 Haikou 23:06, back 06:16. Maintenance 113%;
  service S3 (Sanya, Haikou), S1 (Medan). Cabin `320S-LEI`, no route over 65% of block time.

## What would change the recommendation
- Preferring the longest flying day over departures: C or Haikou with Guiyang (13.2 h, 91 connections).

## Outcome
**A, 24 Oct (Gitesh).** Ordered new; registered 9M-AAZ (KUL), arrives 25 Oct 07:53 UTC (delivered at Toulouse, flies
itself to KUL); plan card 143.

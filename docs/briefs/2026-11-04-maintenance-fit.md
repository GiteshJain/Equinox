# Maintenance fit (to-do 160) — 4 Nov 2026

**Decision:** whether to fit the planner's maintenance estimate to the game's figures (to-do 160, Fleet capture C).
**Recommendation:** C, close it without building: the estimate already matches the game, so a refit changes almost
nothing. Recheck by hand at the 5 Dec monthly session and whenever a new type joins the fleet.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Weekly automatic refit per type and cabin | none measurable | none | no effect | 2–3 hours of builds and a weekly job that can fail | one bad night's figures could skew the estimate | mostly |
| B. One-off correction of the few types that are off | none measurable | none | no effect | about 1 hour | low | yes |
| C. Close it; recheck by hand monthly | none | none | no effect | about 5 minutes a month | a drift unseen until the monthly check | yes |

## Background
Source: `game_fleet` (14 nights, 22 Oct to 4 Nov; the game's maintenance on the latest night, 4 Nov) against the
planning library's estimate (`node lib/rules/dist/cli.js aircraft` on `export_for_report('rules')`, 4 Nov), the same
schedule, 201 aircraft in service.

| Type | Aircraft | Game ÷ planner (median) | Middle half | Median gap |
|---|---|---|---|---|
| A321 NEO LIGHT | 89 | 0.99 | 0.99–1.00 | 1 point |
| E195-E2 | 49 | 1.02 | 1.01–1.02 | 3 points |
| A320neo SHARP | 34 | 1.01 | 0.99–1.02 | 2 points |
| A321XLR | 16 | 1.02 | 1.00–1.08 (range 0.99–1.13) | 8 points |
| A320NEO LIGHT | 6 | 1.02 | 1.01–1.03 | 3 points |
| E190-E2 | 3 | 1.08 | 1.08–1.11 | 13 points |
| A320neo Heavy | 2 | 0.97 | | 5 points |
| A350-900ULR | 1 | 1.01 | | 5 points |
| A321LR | 1 | 0.95 | | 5 points |

- No aircraft is on the wrong side of 100% (planner ok and game under, or the reverse).
- Most gaps are on the safe side (the game above the planner). The planner reads high on 9M-ABA (KUL), A321LR (111%
  planner, 106% game), and the two A320neo Heavies (VT-ABD (DEL) 178 against 174, N025AW (SFO) 220 against 214).
- The XLRs spread most, always the safe way; likely their 7-day lines, where the game's figure moves through the week.
- The E190-E2 is off the default line (manual §3): no new ones are ordered.
- Tails, the aircraft pop-up and Home's cards already show the game's own figure for every aircraft on the fleet pages
  (since 23 Oct); the estimate matters only on plan cards before an aircraft arrives.

## Scenarios and the risk of waiting
No cost to waiting: a drift shows first on Tails, which reads the game. A new type could be off when it first flies,
which the recheck on a new type catches.

## What would change the recommendation
A type off by more than 5 points, or any aircraft on the wrong side of 100%: then B for that type.

## Outcome
**4 Nov 2026, Gitesh: C.** To-do 160 closed; to-do 199 rechecks at the 5 Dec monthly session (Building chat).

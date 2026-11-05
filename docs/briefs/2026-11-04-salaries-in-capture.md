# Salaries inside the evening capture — 4 Nov 2026

**Decision:** whether the evening capture adjusts salaries itself, and to what level (Gitesh's proposal, 4 Nov).
**Recommendation:** A: in the capture, a position below its country average goes to 5% above it; at or above, it's left
alone. The "Salaries: this airline" button goes.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. In the capture: below average → 105% | salaries never below average | saves up to about 4–5% of a position's pay once it resets: up to about 0.4M a week across the group at today's size, gradually | slightly better | one build; a few seconds a capture | less headroom over the average (5%, not 10%) | yes, 5% is a setting |
| B. In the capture: below average → 110% | same | about as now | no change | one build | lowest staff risk | yes |
| C. Keep the button | positions can sit below average between presses | depends on how often it's pressed | no change | Gitesh's time, one airline at a time | below-average pay unnoticed | — |

## Background
- Weekly salary payments (`game_payments`, kind salaries), 29–30 Oct: Pan Am 1.32M, Kingfisher 1.14M, Ryanair 2.06M,
  Virgin 1.49M, China Eastern 1.56M, Malaysia 1.38M; about 9M a week together, rising with staff (Pan Am 0.80M on 9 Oct).
- Today's script (`capture/salary_adjust.user.js`, manual §7) sets every position to exactly 10% above the average,
  lowering ones above it. The new rule never lowers: positions now at 10% above stay until the average reaches them.
- Allowed: Gander's owner sets the rules, every script Gitesh chooses is permitted (manual §9); it runs inside the
  capture he presses and watches.

## Scenarios and the risk of waiting
The average moves as the world hires; between presses a position can fall below it unseen. A daily check closes that.

## What would change the recommendation
Signs in the game that pay under 10% above average hurts staff or service (satisfaction falling, a service warning): B.

## Outcome
**4 Nov 2026, Gitesh: A**, built after the shared-pairs build so the two don't overlap. Manual: *Decided, not yet built*;
§7 changes when it's merged. To-do 201.

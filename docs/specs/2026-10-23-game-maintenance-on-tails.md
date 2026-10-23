# Spec: the game's maintenance figure on Tails — 23 Oct 2026

Decided by Gitesh, 23 Oct ("ok with 1"): an aircraft flying in the game shows the game's maintenance figure, not the
planner's estimate. No brief (a display choice on data we already capture).

## What and why
Since 22 Oct the evening capture reads every aircraft's maintenance figure from the game's fleet pages
(`game_fleet.maintenance_pct`, read through `fleet_checks()`, which Today's Fleet group and the Tails pop-up already
use). Tails' board still shows the planner's own estimate ("≈106%", `maintenance.forAircraft` in the planning library,
`maintPill` in `app/planner/src/screens/tails/model.ts`), which can differ from the game. The game's figure is the true
one for an aircraft the game is flying.

## The change
- **Tails' board, Maint. column:** for an aircraft on the latest night's fleet pages (`fleet_checks()`'s airlines →
  aircraft, matched by `aircraft_id`), show the game's figure as "106%" with no ≈, its class from
  `settings.maintenance_min_pct` (100) and `maintenance_target_pct` (105) as the pill does now (bad under the minimum,
  warn under the target, good otherwise), "400+" above 400 as now, and a tooltip "In the game, last night's capture
  (22 Oct)". For any other aircraft (not yet on the fleet pages: on order, delivered and unfiled, or no capture yet),
  keep the estimate exactly as now, with its ≈ and its tooltip.
- **Tails' issue words** for maintenance (`issueWords`, "maintenance ≈P% — under …"): use the same source, so an
  aircraft in the game is judged on the game's figure (no ≈), the rest on the estimate.
- **Home's airline cards**, "lowest maintenance ≈P%" (`AirlineCards.tsx`): the lowest of the game's figures where the
  airline's aircraft are on the fleet pages, without ≈; the estimate only for aircraft without one.
- **Unchanged:** plan cards and any what-if (a retime being tried, the optimiser, the card check) keep the estimate:
  the game has no figure for a schedule it isn't flying yet. Fleet capture C (to-do #160) improves that estimate later.
- One read of `fleet_checks()` shared by the screens that need it (Tails already reads it for the pop-up); no new
  database function, no migration.

## Tests and documents
- Unit tests beside `tails/model.ts` and Home's: an aircraft on the fleet pages shows the game's figure and class, one
  not on them shows the estimate with ≈; the issue words follow; the lowest on the airline card uses the game's.
- Saved answers that move: say which and why in the pull request.
- `docs/planner-guide.md` (Tails and Home), `docs/architecture.md` if it describes the column.

## What the checks should show
All green: Checks and the Database rehearsal (every screen at 1280 and 380 px, no errors).

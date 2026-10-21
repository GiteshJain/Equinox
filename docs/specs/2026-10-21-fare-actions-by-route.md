# Build spec: the fare ladder's game changes, route by route (21 Oct 2026)

**Why:** Gitesh, 21 Oct (manual §5, as updated that morning). The fare ladder's changes are made **route by route
only, never a whole base**, so routes under 7 days old are never touched. Loads are high because the world is young.
He checked the game's **Ticket price adjustment**:
- each direction has to be changed on its own (From A to B, and From B to A);
- Economy and Business can be ticked together in one change.

The changes will be made by a fares userscript (a later spec, once the game page's HTML is in hand), so the list has
to be exact and in a form a script can read.

## The change
- **`private.fig_fare_ladder()`'s `actions`** (new migration; `CREATE OR REPLACE`, same arguments):
  - No base actions. For each route whose level changes in either cabin, there are two actions, From hub to dest and
    From dest to hub.
  - Each action names the classes it changes: `classes` is `["economy","business"]` when both cabins move to the same
    new level, otherwise one action per cabin.
  - A route whose level doesn't change gets no action. A held, new or capped route is never listed.
  - Keep `n`, `from`, `to`, `level`, `sign`, `pct`, `baseline` and `text`. `text` names the classes ("economy and
    business"). Drop `kind`/`base`, or keep `kind` always "route", whichever keeps the planner simplest; say which.
  - Order: by route (hub, dest), the two directions together.
  - Update `database/current/functions.sql`, and the comment on `public.fare_ladder()`.
- **`database/tests/fare_ladder_test.sql`:** the expected actions become route by route. Add a case where a route's
  two cabins move to the same level (one action per direction, both classes) and one where they differ (one per cabin
  per direction).
- **Performance's fare ladder** (`screens/performance/FareLadder.tsx`, `model.ts`): drop "the whole base"; show the
  classes; keep the cut to 10 with "show all N"; the count of changes in the board's heading. Unit tests updated.
- **Docs:** `docs/planner-guide.md` (the fare ladder), `docs/architecture.md` if it describes the base grouping,
  `docs/playbook.md`'s Saturday fare step if it mentions bases. `tests/README.md` if needed.

## Checks
- `bash tests/run_all.sh` green; the rehearsal green; `types.ts`, `data.md` and `functions.sql` from the rehearsal's
  artifacts if they move.
- The pull request lists, from the rehearsal's copy, each airline's number of changes (actions), against the base
  version's (Pan Am 50, Kingfisher 54, Ryanair 18, Virgin 76, China Eastern 60, Malaysia 56).

## Not in this build
- The fares userscript (its own spec).
- Any change to the ladder's moves, levels or settings.

# The fare ladder's hold after a step up

To-do #174. The rule is decided and already in the manual, §5 (since 26 Oct): a direction that went **up** a step holds
the next Saturday. Brief: `docs/briefs/2026-10-26-fare-ladder-hold-after-step-up.md` (why: bookings open 3 days ahead,
§9, so the week after a change mostly flies at the old price). Until this is built, the review chat holds those
directions by hand.

## What changes (database only)
1. **A new settings row,** `fare_ladder_up_hold_weeks`, value `1`, unit `weeks`, in every world, airline null, with a
   description (follow how `fare_ladder_hold_weeks` was added in `20261021120000_fare_ladder.sql` and
   `fare_ladder_capacity_hold_days` in `20261021230000_frequencies_and_fares.sql`).
2. **`private.fig_fare_ladder()`** (its current definition is in `database/current/functions.sql`, about line 3860 on):
   - read the setting with `private.fig_num(w, p_airline_id, 'fare_ladder_up_hold_weeks')`, as `v_hold` is read;
   - beside `dn` (the latest step **down** before this Saturday, by route, cabin and direction, from the fare plan's
     ladder rows `rec`), add the latest step **up**: `max(proposed_on)` where `ladder_move = 'up'` and `proposed_on <
     v_week`. Only `up`: a `revert` (back to launch), a `jump` and a set-back (`fix`) never start this hold. A
     both-directions row (direction null, written before 26 Oct) counts for both directions, exactly as `dn` treats it;
   - a new state, held after a step up, true when `v_week - up_on < up_hold_weeks * 7`, judged in the same place and
     order as the hold after a step down (`held`): after a new route and too few departures, before the sold-out share.
     A direction can't be held both ways; if both apply, the more recent move wins its reason;
   - its kind `held_up` (or a clear name of your choosing; keep `held` as it is for the step down) with the reason
     **"held after a step up on 26 Oct"** (the date of that move, `FMDD Mon`, as the step-down reason does). A held
     direction gets no move and no game action;
   - the answer's settings echo (where `hold_weeks` is given) also gives `up_hold_weeks`.
3. Nothing else changes: the capacity hold, the rival pause, the under-launch jumps and their own hold, the set-back of
   directions off their level, the 60% floor and the cap.

Example: Pan Am's directions put up on Mon 26 Oct are held on Sat 31 Oct (5 days < 7) and judged again on Sat 7 Nov.

## Who reads it
`fare_ladder()` feeds Performance's fare ladder (each airline's page), `capture_fare_actions()` (the fares script's
list), the plan card's fare levels and the briefing. Check the planner shows the new reason as it shows any other (the
reason is the database's words; if a screen maps kinds to words, e.g. a "held" pill, give `held_up` the same treatment).

## Tests
- A database test (beside the fare ladder's existing ones in `database/tests/`): a direction stepped up 5 days before
  the Saturday is held with the reason above and no action; at 7 days or more it's judged normally; a direction
  stepped down keeps its 2-week hold and reason; a `revert` or `fix` row doesn't hold; a both-directions up row holds
  both directions.
- Saved answers that move: say in the pull request which and why (the rehearsal's `figures-moved` artifact shows them).

## Lessons from earlier helpers (put them to use)
- Add the new setting to `rules_input_test.sql`'s list.
- Have `clean_up_test.sql` set aside exactly the new fields that reach `export_for_report('figures')`.
- A changed description needs its line in `docs/data.md`; a changed function its new definition in
  `database/current/functions.sql`.
- A test comparing whole JSON breaks when fields are added: compare what you mean.
- `(x -> 'a') - 'b'`, not `x #> '{a}' - 'b'`.
- The migration is large (the whole `fig_fare_ladder` again): that's expected; the Building chat applies it.
- A pull request with merge conflicts runs no checks at all: keep the branch up to date.

## Documents (same pull request)
- `docs/architecture.md`, the `fare_ladder()` paragraph: the hold after a step up (`fare_ladder_up_hold_weeks`).
- `docs/planner-guide.md`, the fare ladder: the new reason.
- Leave `docs/operating-manual.md` alone: the Building chat removes its *Decided, not yet built* entry after the merge.

## Done when
`bash tests/run_all.sh` passes locally, the pull request says what changed, why and how it was tested, and the checks on
GitHub (Checks and Database rehearsal) are green.

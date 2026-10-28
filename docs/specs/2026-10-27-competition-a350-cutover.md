# Spec: the openings' A350 cut-over as a setting, and the E190-E2 note gone — 27 Oct 2026

*Building chat, for a helper. To-do 178. Manual §3 (the default line, since 27 Oct; brief
`docs/briefs/2026-10-27-real-aircraft-reach.md`) and its "Decided, not yet built" item "The default line's reach in the
openings".*

## What and why
`competition()` ranks each airline's openings with the default line's variant. Two things in it are behind the
27 Oct default line:
1. **The A350-900 / -1000 cut-over is a constant in its code,** `v_wide_km constant int := 15000;`. The default line now
   says the -900 flies to 14,200 km with its full cabin and the -1000 takes routes beyond that. Manual §1 says rule
   numbers live in `settings`, so the cut-over becomes a setting.
2. **The thin 1-star city's alternative** (the `alt` lateral join, and `variant_alt` / `variant_note` "or the E190-E2
   if thin" in each opening) names a type that's off the line. On live it already shows nowhere, since no airline may
   buy the E190-E2 any more (`airline_aircraft_types`), but the code, its description and its readers remain.

## The build
- **One migration** (check the latest timestamp in `database/migrations/` just before naming it):
  - a world-level `settings` row `a350_1000_from_km`, value `14200`, unit `km`, with a description ("beyond this
    distance the openings take the A350 with the most seats, the A350-1000; up to it the cheapest per seat, the
    A350-900: its reach with a full cabin, manual §3"), `since` 2026-10-27, and a reason naming the brief. Insert it
    in every world as `20261027210000_aircraft_eval.sql` does for its setting.
  - `competition()` replaced with: `v_wide_km` read from that setting (the way the function reads its other settings;
    if the row is missing, fall back to 14200 and say so in a comment), the `alt` join and the `variant_alt` /
    `variant_note` output removed, its comments and its description updated (no 15,000 km, no E190-E2 note). Its
    `wide_full_cabin_km` output stays, now the setting's value. Nothing else in the function changes: diff the new
    definition against `database/current/functions.sql` and make sure only these lines move.
- **Readers of the removed fields:** `app/planner/src/screens/competition/model.ts` and its test,
  `scripts/briefing/brief.py`, `database/tests/competition_test.sql`, `tests/README.md`. Remove the alternative's
  display and cases; nothing should be left that reads `variant_alt` or `variant_note`.
- **Tests:** in `competition_test.sql`, an opening just past the setting gets the -1000 and one just under it the
  -900 (on the test's own airline and types, as its other cases build them), and changing the setting moves the
  cut-over without a code change; no opening has `variant_alt`.
- **Documents:** `database/current/functions.sql`, the map where it describes the openings' variant, `docs/data.md`
  through the rehearsal as usual. **Not the manual:** the Building chat updates §3 and "Decided, not yet built" after
  the merge.

## Checks
`bash tests/run_all.sh` green before the pull request; the database rehearsal on the pull request. The migration
replaces the whole function, so after the merge Gitesh pastes it into the SQL editor, and the Building chat checks it
by md5 against `database/current/functions.sql` and records the migration.

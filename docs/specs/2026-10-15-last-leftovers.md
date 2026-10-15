# Build spec: the last leftovers from the planner rebuild — 15 Oct 2026

**Why:** design §16 (`docs/design/2026-10-12-planner-app.md`) keeps three items open after the clean-up, and the small
fixes (pull request #43) found the database's reference file out of date. Gitesh asked for all of them now.

## 1. The cabin an order comes with, made data
Today `private.fig_order_cabin()` works out an order's cabin from the cabin names (the old planner kept a list,
`DEFAULT_CABIN`, in its code). Store it as data instead: each aircraft type's order cabin (per airline where an airline
differs), filled from exactly what `fig_order_cabin()` gives today for every type and airline, so nothing moves. The
function then reads the data. Reference shows it with the aircraft types and lets it be edited like the rest of
Reference (one `planner_save()` action). A database test: the data gives the same cabin as before for every type and
airline on the copy.

## 2. Photos' city-photo and name lists, made data
Which city's photo an airport takes, and the name the website gives it, are lists in the Photos screen's code and in the
website's code. Give them one home in the database (with the website's content, `site_content`, or a small table;
your choice, described), read by both the Photos screen and the website through what they already read
(`site_public()` for the website). Nothing visible changes: the website and Photos show the same as before (a check
compares the website's photo and name for every airport before and after).

## 3. Ryanair's main base: kept as it is
No change. Ryanair's home already falls back to CDG, and its hubs-first exemption is held by the setting
`hub_first_exempt`, not by the missing main base. Close the item in design §16 with that reason.

## 4. The database's reference file, kept in step
`database/current/functions.sql` has older versions of `airline_profit`, `route_profit`, `fig_group_today` and
`fig_route_loads`, and `rules_input_doc` written differently. Refresh every function in the file from the rehearsal's copy
after the migrations, and make the rehearsal's file check compare each function's body (ignoring whitespace), not only
the names, so it can't drift again. Correct the function counts in `docs/architecture.md`.

## Checks and proof
- `bash tests/run_all.sh` passes; the rehearsal passes; the recorded save answers still pass (a Reference edit of an
  order cabin is a new recorded save).
- **A deliberate failure,** seen to fail then removed: one function in the reference file a version behind (the new
  body check must go red).

## Docs
Design §16 (each item done or kept, with the reason), the map, `docs/data.md` (regenerated), `docs/planner-guide.md`
(Reference's order cabin), `tests/README.md`.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` for the migration.
- Migration: adds, or replaces with the same arguments, plus the data it fills; says it can be applied from the chat.
- **Work lean.** **Never connect to the live database or use the Supabase connector tools.** Never commit a key.
- Work on branch `last-leftovers`, open the pull request with the REST API, and don't merge.

## Done when
Every check is green and the deliberate failure was seen to fail, then removed. The pull request says what changed,
that nothing visible moved (with the checks that show it), the steps after "merge", and how to roll back.

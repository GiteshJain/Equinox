# Build spec: Interline, Photos, Reference, and what's left before the switch (#18 build, pull request 12) — 14 Oct 2026

**Why:** step 12 of the build order (`docs/design/2026-10-12-planner-app.md` §13), the last screens. With it, every
screen of the old planner is in the new one, and the items design §16 keeps for "before the switch" are done, so
Gitesh can try the new planner in full before the switch (pull request 13). The same pattern as Home to Review: same
features and look as the old screens, every figure from its one home, proven side by side.

The game runs again, with game changes made in the old planner only until the switch; **its code stays frozen
(manual §1): nothing in `web/planner/` changes.**

## Part 1: the three screens
**Outcome when done:** `/planner/next/interline`, `/planner/next/photos` and `/planner/next/reference` do everything the
old screens do, on a phone too.
- **Interline:** one row per airline and interline country it flies into or has planned, with the airports, round trips
  a day, status, partner in the game, since and notes; the airline and status filters; every edit the old screen has.
- **Photos:** airline logos and destination photos for the public website, with upload (resized for the web first, as
  the old one does) and whatever else the old screen lets you change. Uploads go live at once, as now.
- **Reference:** every section of the old Reference (hubs, focus cities and banks; constants; aircraft; configs; market
  defaults; service profiles; removed routes with restore and restore all; night bans; time zones; game schedules; data;
  storage), folding as the old one does, with every edit the old screen has.

### What to build
The design is the specification: §2, §4 to §7, §9 (these screens' rows), §10, §14. The old screens are the reference:
`renderInterline`, `interlineRows`, `renderPhotos` and its `eq*` helpers (`eqPhotosHTML`, `eqUpload`), `renderRef`,
`renderRefRaw` and the click and change handlers they use, in `web/planner/index.html`. Search for them; don't read the
file whole. Where the design and this spec disagree, stop and say so.

- **Saving:** one action each through `planner_save()`, each writing exactly the rows the old planner writes; photos
  through the same storage and `site_public` route the old screen uses (a preview never uploads). A constant or other
  rule number that is now a setting is edited as that setting's row; the screen says the manual must change with it
  (manual §1: rule changes are agreed in chat and the manual updated).
- **Shared parts** from `src/ui/`. The addresses above, with Reference's open section in the address.

## Part 2: before the switch (design §16)
1. **The header:** the search box (flights, aircraft, airports, as the old `searchAll`, with "/" to focus) and the
   Website button, as in the old header. Results open the new screens.
2. **Regions:** add `region` to `countries`, filled from the old planner's `REGION_OF` list (and its fallback: Europe
   for a country not listed, Other for none), with a description. Hubs' connections table and Check's hub readiness
   then name regions as the old ones did; their side by sides compare the words again.
3. **The suggested aircraft size:** the old `suggestSize` rule (stars to a type, Ryanair's own) as settings, a world
   value with Ryanair's override, read through `rules_input()`. Check's route options show it again, side by side.
4. **Airline card photos:** add `airlines.photo_city`, filled from the list in Home's airline cards, which then read it.
5. **Tails:** the aircraft pop-up opens from Routes too (a frequency's aircraft), and a delivery can be removed, writing
   exactly what the old `deldel` writes.

Migrations add only: new columns and their values, new settings. No drops, no changed function arguments; say whether
each can be applied from the chat.

## Checks
- **Unit tests:** the interline rows and filters, the search (flight number with and without the airline prefix, a
  registration, an airport), the regions and suggested-size rules.
- **In the rehearsal, `tests/reference_side_by_side_test.py`** (Interline and Photos may share it or have their own), at
  a frozen moment, both planners as the test staff user: every screen and section equals the old one; each edit made in
  the new planner writes exactly the old planner's rows and the old planner then shows it (a sample of each kind of
  edit is enough; say which); a photo upload of a small test image writes what the old one writes; restore a removed
  route. Search results for a sample of queries equal the old ones. Hubs and Check now match on regions and suggested
  size; Tails' delivery removal and Routes' aircraft pop-up are covered in their side by sides. A preview address sends
  no write and no upload. 380 px with screenshots (`reference-screens` artifact).
- `tests/planner_next_test.py`: no screen is a placeholder any more.
- Keep the run under 30 minutes; sample if needed and say so.

## Docs, in the same pull request
`docs/planner-guide.md` (the three screens, the header search), the map, `tests/README.md`, `docs/data.md`
(regenerated), and design §16 (mark each item done).

## Proving it
- `bash tests/run_all.sh` passes; the rehearsal passes with every step `ok`; screenshots attached.
- **A deliberate failure,** seen to fail then removed: the search drops the airline prefix's flights (a "KF 1008" query
  finds nothing) — a unit test and the side by side must go red.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` for the migration. Reuse the
  earlier screens' code (`app/planner/src/`) and their side-by-side tests.
- **Work lean:** check on GitHub runs every few minutes rather than continuously, and don't read beyond what the build
  needs.
- **Never connect to the live database or use the Supabase connector tools.** Don't change `web/planner/` or
  `web/assets/`. Never upload to the live storage; the rehearsal's local copy only.
- If anything differs from the old screens, find the cause; report a real difference as a finding.
- Work on branch `reference`, open the pull request with the REST API, and don't merge.

## Done when
Every proof is `ok` and the deliberate failure was seen to fail, then removed. The pull request says what changed, the
run time, any finding, the steps after "merge" (and whether each migration can be applied from the chat), and how to
roll back.

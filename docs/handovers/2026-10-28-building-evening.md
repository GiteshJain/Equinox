# Building chat handover — 28 Oct 2026, evening

For the next Building chat. Start as the project instructions say (the manual, `docs/decisions.md`, this note and the
map), then the planner's state. The manual wins over this note. Previous note: `docs/handovers/2026-10-28-building.md`.

## Nothing is open in the repository
No open pull requests. Every migration on main is applied to live and recorded, up to `20261028180000`. The two
functions `20261028180000_plan_lines.sql` replaces (`planner_save`, `private.rules_input_doc`) were checked by md5
against `database/current/functions.sql` (whitespace removed). Every project copy (`claude/*.md`) matches the
repository. The spare branch `docs/long-haul-lines-manual` couldn't be deleted from here (403); harmless.

## Built and live, 28 Oct: long haul in 7-day lines (to-do 180, done)
| PR | What |
|---|---|
| #118 | `optimise-line` (the line optimiser), the maintenance spacing on every card (`maintenance_max_gap_h`, 40 h), `check-card` across a line; settings `line_min_km` 7,750, `maintenance_max_gap_h` 40, `line_aircraft` 7 |
| #119 | `plan_lines`, `plan_line_legs`, `plan_cards.line_id` and `line_day_offset` (one card per place, trigger `private.plan_line_slot()`); `planner_save()` takes them; `rules_input()` carries `range_km`; Tails' slots and **Write the next card**; `card.fromLine` |
| #120 | Filing, Game check, Flights by day and the offset save read a line aircraft day by day (no database change: route and aircraft profit and the loads check already count each leg on its own days) |
| #121 | Today → Orders: each open line's progress and when its next aircraft can be ordered |

The manual's rule moved from *Decided, not yet built* to §4 (with the 40 hours in the maintenance rule) and §3 (a
line's aircraft ordered like any other); rule history and the playbook updated the same day.

## How it went, and lessons
- **Each PR was built by a fresh helper from the previous PR's branch,** so the four overlapped; after each merge the
  next branch was cherry-picked onto main and force-pushed (the squash merges otherwise leave the chain's old
  commits in its diff).
- **Old tests pinned data the Scheduling chat keeps.** On 28 Oct (04:02 UTC) it set `aircraft_types.range_km` to the
  §3 full-cabin reach and removed the types left off the default line from `airline_aircraft_types`. That broke
  `database/tests/default_line_variants_test.sql` (A321LR 5,809 km; every airline buying the E190-E2); it now checks
  the line's order and the types still on it. A test should check data a chat keeps by its shape, not its figures.
- **The map's guide check fails an example that returns no rows.** An example over a table that can be empty should
  aggregate into one row (`coalesce(jsonb_agg(...), '[]')`).
- **Applying from the chat gets "cancelled" for big changes, and for `create or replace` of the big functions even
  alone.** #119's migration went in two parts: part 1 (tables, columns, trigger) by `apply_migration`, part 2 (the two
  functions and descriptions) by Gitesh in the SQL editor from a file sent in the chat. Late on 28 Oct even small writes
  were cancelled for a while, then worked again. For a large migration, split it at the start: tables first from the
  chat, functions as a file for the SQL editor.

## Discussed, not decided
- **A world reset or a new world (28 Oct, "we'll come back to it"; probably a year away).** Exposure: no seed path
  for a new world's reference data, the rulebook is Gander's, the userscripts, the schedule check and `gscan.py`
  hard-code `gander.airlinesim.aero` (`worlds.game_host` unused), no world switcher, and `site_posts`, `site_reports`,
  `site_content` have no world. Ideas if it comes back: a world-seed script, the host from `worlds.game_host`, a world
  on the website's posts and reports. Not put on *Decided, not yet built* (Gitesh declined).

## Waiting on Gitesh
Nothing in this chat.

## For the next Building chat
- **Saturday 31 Oct:** the first review with the per-direction ladder and the hold after a step up (to-do 175).
- **#160, around 5 Nov:** fit the maintenance estimate per type and cabin to the game's figures (spec needed).
- **The first line:** when the Scheduling chat plans one, watch it through `optimise-line`, the SQL shapes in
  `scripts/README.md`, Write the next card, and filing day by day (nothing has been filed on a line yet).
- Noted in the PRs, not changed: Routes' frequency view and Reference's CSV show a line return on the outbound's day;
  editing a line rotation's days on Routes uses the old rule; Game check's Add to planner pairs as before (file line
  aircraft from their cards).
- Open ideas, not raised as decisions: the fare ladder's copy buttons; the evaluation script's request time limit.
- Working copy: `/home/claude/equinox`; a separate clone per helper.

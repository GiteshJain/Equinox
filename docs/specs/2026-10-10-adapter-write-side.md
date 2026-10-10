# Build spec: the adapter's write side, run beside the old storage (#13 build, pull request 5) — 10 Oct 2026

**Why:** step 5 of the build order in `docs/design/2026-10-09-data-model.md` (§10). The tables hold the planner's data
and the getters rebuild today's JSON from them (pull request 4). This pull request adds the functions that save into
the tables, and runs them beside the old storage on live: every save of the old planner row and every loads save is
copied into the tables, and the two are compared after each. The switch-over (pull request 9) waits for 3 clean days
in a row (§11, choice 1).

**Outcome when done:**
- `planner_state_put`, `save_loads` on the tables, `planner_item_put` and `planner_item_delete` exist and are proven.
- On live, each save of `planner_state` and of `planner_loads` is mirrored into the tables, and the getters are then
  compared with the old rows. Every mirror and comparison is one row in `job_runs`.
- The planner, website, capture and scripts behave exactly as before: the old rows stay the truth, and a mirror or
  comparison that fails never blocks or slows a save noticeably.

## What to build
The design is the specification: §6 (the change log and who made a change), §8 (the adapter: saving only what
changed, when a save meets a newer change, cash, loads), §9 ("Proving old and new are the same", "Side by side on
live"), §11 choices 1 and 4, and §3.11 (`job_runs`). Where the design and this spec disagree, stop and say so.

### 1. In this pull request
- **`planner_state_put(json text, saved_at bigint, base bigint, client text)`** as §8: a lock per world
  (`pg_advisory_xact_lock`); work out the rows the save would change; skip rows another actor or tab changed after
  `base` (choice 4); write the rest as actor `planner` with the tab in `actor_detail`; answer
  `{saved_at, applied, skipped, reload}`. A **mirror mode** for the side-by-side trigger: no skipping, since the old
  row is the truth.
- **`save_loads(month, days)`** keeps its name, arguments and answer, and keeps writing `planner_loads` exactly as
  today; it also writes `load_entries` and `load_days`.
- **`planner_item_put(section, key, value jsonb)`** and **`planner_item_delete(section, key)`**: one item in today's
  JSON shape, through the same code as a save (§8).
- **`job_runs`** as §3.11 (only the table and its rules; moving `backup_runs` into it stays in pull request 7). Jobs
  this pull request writes: `adapter_mirror` and `adapter_check`.
- **Side by side on live** (§9):
  - first, run `private.load_planner()` once more, so the tables catch up with every save since pull request 4;
  - a trigger on `planner_state` that, after each save, mirrors it into the tables (actor `planner`, detail
    `mirror`), then compares `planner_state_get()` with the row just saved, using exactly the allowed differences the
    tests use, including "cash/fixed7 captured after the planner last saved";
  - the same after each write of `planner_loads` (by `save_loads` or the capture), comparing `planner_loads_get()`;
  - each mirror and each comparison writes one `job_runs` row: `ok`, or `failed` with where it differed in `note`
    and the paths in `details`. Any error inside is caught and recorded; the save always goes through;
  - a view or function that answers "how many clean days in a row": capture days (§2) with at least one comparison
    and none failed. Pull request 9 reads it.
- **Speed:** the trigger must add no more than about 300 ms to a planner save on the copy. If it can't, stop and say
  so rather than shipping it slow.
- **Descriptions** on everything new, and `docs/data.md` regenerated.

### 2. Not in this pull request
- No change to the planner. It keeps reading and writing the old rows until pull request 9.
- `airline_days`, `route_days`, scans (6); `pg_cron`, clean-ups, archive, `backup_runs` into `job_runs`, Home's
  warnings (7); website and scripts (8); the switch-over and the freeze (9).

### 3. How to ship
- One migration that adds everything and starts side by side. If anything removes or revokes something that exists,
  it goes in a short separate file for Gitesh to run (manual §1). Say in the pull request how long the migration takes.
- It will be applied when no capture is running.

### 4. Proving it (the rehearsal, on last night's copy)
- **Round trip:** `planner_state_put(planner_state_get())` changes no rows and writes no change-log row.
- **Real saves through the adapter:** extend `tests/real_saves_test.py` so that, after each of its saves (tick a
  to-do, change a plan card's title, type a load), the mirrored tables changed in exactly the intended rows, the change
  log names actor `planner`, and the comparison row in `job_runs` is `ok`.
- **Each section of §8's table:** a SQL test that changes one item of each section through `planner_state_put` (an
  aircraft, a frequency including its return day, a plan card's legs, a to-do and its steps, a route edit, a capex and
  growth entry, an interline, a monthly check, a dismissal, a `ref` value, a typed cash figure) and reads it back
  through `planner_state_get()` unchanged.
- **A save meeting a newer change (choice 4):** two saves from different tabs with the same `base`; the second keeps
  its rows that don't clash, skips the one that does, and answers `reload: true`.
- **`planner_item_put`/`_delete`:** a plan card and a to-do added, changed and removed, each logged.
- **The trigger never blocks a save:** with the mirror made to fail on purpose, the old row still saves and a
  `failed` row lands in `job_runs`.
- **Clean days:** the clean-days answer counts correctly over hand-made `job_runs` rows (a clean day, a day with a
  failure, a day with no comparison).
- **Speed:** the trigger's added time on a planner save, best of 3.
- Everything earlier still passes: the getters equal today, the capture views unchanged, real saves.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` and its rule files (locking,
  triggers, security) before writing SQL. Read the previous builds' migrations and tests, especially
  `20261010120000_planner_data_load.sql` (the loader and getters you build on) and its allowed differences.
- The planner (`web/planner/index.html`) is the source of truth for the old JSON: grep it (`cloudWrite`,
  `cloudSavedAt`, `saveLoadsDays`, `commit`), never read it whole, and don't change it.
- **Never connect to the live database or use the Supabase connector tools.** Test by pushing and reading the
  *Database rehearsal* result. Docker is available here for trying SQL on an empty local Supabase.
- Work on branch `adapter-write`, open the pull request with the REST API (GraphQL is blocked), and don't merge.
- `bash tests/run_all.sh` and the *Database rehearsal* must pass before asking for a merge.

## Done when
- The rehearsal passes with every proof above `ok`, and a deliberate failure was seen to fail, then removed (for
  example, the mirror dropping one to-do step).
- The pull request says what changed, how long the migration takes, the trigger's added time per save, and anything in
  the design that turned out wrong or unclear.
- After "merge", the migration goes to live when no capture is running; the Building chat checks the first mirrored
  saves and comparisons in `job_runs`, and reports the clean-day count each day until it reaches 3.

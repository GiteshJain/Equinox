# Build spec: the switch-over — the planner reads and saves the tables (#13 build, pull request 9) — 10 Oct 2026

**Why:** step 9 of the build order (`docs/design/2026-10-09-data-model.md` §10). Gitesh dropped the wait for clean
days on 10 Oct, so this goes as soon as it's built, provided no side-by-side comparison has failed. The website and
scripts already read the tables (pull request 8). After this, the planner reads and saves the tables through the
adapter, and the old rows are frozen as the fallback until #18.

**Outcome when done:**
- The planner loads from `planner_state_get()` and `planner_loads_get()` and saves through `planner_state_put()` and
  `save_loads()`. On screen nothing changes; a save writes only what changed, and a clash keeps what doesn't clash.
- `planner_state` and `planner_loads` refuse writes ("frozen since <date>; write to the tables"). The side-by-side
  triggers are gone. The capture's loads go only to the tables.
- `private.unfreeze_planner_state()` undoes the switch in one step, rehearsed.
- The manual, the map, the table guide and the test sample describe the new way.

## What to build
The design is the specification: §8 (the adapter, "At the switch-over"), §9 ("Rollback"), §10 row 9, §11 choices 3
and 4. Where the design and this spec disagree, stop and say so.

### 1. The planner (`web/planner/index.html`)
Only its storage layer, as §8 says: the `dbAdapter` shim, `cloudSavedAt` and `cloudWrite`, about 20 lines. Grep for
them; don't read the file whole; change nothing on screen.
- `get` → `planner_state_get()`; `set` → `planner_state_put(json, saved_at, base, client)` with the tab's ID made once
  per page load and `base` = the `saved_at` the tab last loaded or saved; `collection("loads")` → `planner_loads_get()`;
  `cloudSavedAt` → `planner_state_version()`.
- `cloudWrite` keeps the `saved_at` the server returns. On `reload: true` it takes the existing reload path, with the
  existing message, naming what was skipped if the answer lists it.
- The three read functions join `READ_ONLY_RPCS`, so previews can read and still can't save.
- **It must work with the database both before and after this pull request's migration**, since Cloudflare publishes
  on merge and the migration is pasted afterwards. Test both.

### 2. The database (migration)
- **Freeze:** a trigger on `planner_state` and `planner_loads` that raises "frozen since <date>; write to the tables"
  on insert, update or delete, except inside `private.unfreeze_planner_state()`.
- **Side by side off:** drop the two mirror triggers (or disable them) and stop the comparison.
- **The capture's loads** go only to the tables: the loads step stops writing `planner_loads`.
- **`save_loads()`** writes only the tables.
- **A loads day's `done`** follows one rule, design §8's: true when all of the world's active airlines were captured
  for that date, or when typed. The getter and the capture agree; test the evening part-way through a capture.
- **The cash allowances end:** the getter is now the source, so no allowance is needed; remove them from the code paths
  that only served the side by side.
- **Rollback:** `private.unfreeze_planner_state()` writes `planner_state` and `planner_loads` from the getters, so
  nothing since the switch is lost, then lifts the freeze. It doesn't revert the planner code; the pull request says
  how to do both.
- **Rule numbers (§11 choice 3):** a check that fails if the old planner's built-in rule numbers (`ref.consts`,
  `ORDER_CUSHION` and the like, as listed in design §3.7) ever differ from `settings`/`world_rules`. It can be a test in
  `tests/` that reads both.
- Anything that removes or revokes something (the triggers, grants on the old rows) goes in a short separate file for
  Gitesh to run (manual §1). Keep it short; say the order in the pull request.

### 3. Docs, in the same pull request
- **Manual:** §1 (other chats' data-only changes now go through `planner_item_put` or SQL with the `equinox.actor`
  line, design §6, instead of editing `planner_state`; the old rule to *Retired rules*), §3, §4 and §9 point their rule
  numbers to `settings`/`world_rules` (one source), §7 as needed.
- The map (`docs/architecture.md`), the table guide (`docs/data.md`), `tests/README.md`.
- **A new test sample** made the new way (`tests/fixtures/make_sample.sh` from the tables), and the planner checks'
  stand-in (`tests/harness.py`) answering the new calls, with the saved answers updated and every moved number named.
- List anything outside this repository that needs a follow-up (for example the restore guide in `equinox-backups`,
  which restores `planner_state` after a bad save).

## Proving it
- **Planner checks** (`tests/planner_test.py`): every screen and pop-up opens with no errors on the new stand-in;
  previews save nothing; the live address saves through the adapter.
- **Real saves** (the rehearsal): the pull request's planner, after the migration, ticks a to-do, changes a plan card
  and types a load; the tables change in exactly those rows, logged as `planner`; `planner_state` and `planner_loads`
  are unchanged and refuse a direct write. The same planner against the database **before** the migration also saves.
- **Two tabs:** two pages save clashing and non-clashing changes; the second keeps its non-clashing change and reloads.
- **Rollback rehearsed:** after some saves, `private.unfreeze_planner_state()` gives a `planner_state` equal to the
  getter, and the old planner code can save it again.
- **Rule numbers:** the check passes today, and fails when one setting is changed.
- Every earlier test still passes.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` and its rule files. Read the
  previous builds' migrations and tests, especially `20261010210000_adapter_write_side.sql` and
  `20261010220000_website_and_scripts.sql`.
- **Never connect to the live database or use the Supabase connector tools.** Test by pushing and reading the
  *Database rehearsal* and *checks* results. Docker is available here.
- Work on branch `switch-over`, open the pull request with the REST API (GraphQL is blocked), and don't merge.
- `bash tests/run_all.sh` and the *Database rehearsal* must pass before asking for a merge.

## Done when
- Every proof above is `ok`, and a deliberate failure was seen to fail, then removed.
- The pull request says what changed, the exact steps after "merge" in order (Gitesh's file, the migration, reloading
  open planner tabs), how to roll back, every moved number, and any follow-up outside this repository.

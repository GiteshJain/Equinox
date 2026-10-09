# Build spec: the new tables, empty (#13 build, pull request 2) — 9 Oct 2026

**Why:** step 2 of the build order in `docs/design/2026-10-09-data-model.md` (§10). The design is approved; this pull
request creates its planner tables with their access rules, the change log and the `private` schema, plus the
reference rows for Gander, equinox. and our six airlines. Nothing reads or writes them yet: the capture moves in with
pull request 3 and the planner's data with pull request 4.

**Outcome when done:**
- The tables of design §3.1 to §3.7, and `change_log` (§3.10, §6), exist on a copy of live, empty apart from the
  reference rows.
- A signed-out visitor reads nothing; a signed-in account that isn't staff reads no rows; staff can read and write.
- Every change to them is logged with who made it.
- The planner, the website and the capture behave exactly as before (the real-saves step from pull request 1 still
  passes).

## What to build
Read the design first, in full: it is the specification for names, columns, types, keys and rules. This spec only
says which parts belong in this pull request and how to ship them. Where the design and this spec disagree, stop and
say so in the pull request.

### 1. In this pull request
- **Tables:** everything in design §3.1 (worlds, groups, airlines, airline_bases, airline_aircraft_types), §3.2
  (countries, airports, world_airports), §3.3 (aircraft_types, cabin_configs, aircraft, aircraft_cabin_keeps), §3.4
  (markets, service_profiles, routes, rotations, flight_legs), §3.5 (plan_cards, plan_card_legs), §3.6 (todos,
  todo_items, growth_log, spending_log, fare_plan, interline_agreements, monthly_checks, dismissals, cash_entries,
  load_entries, load_days), §3.7 (settings, world_rules), and `change_log` (§6).
- **Their rules:** the type conventions at the top of §3, `created_at`/`updated_at` with a trigger, the checks on
  enumerated columns, the keys and indexes the design lists, the two-column (world, airline) keys, and the
  `flight_legs` checks of §3.4 and §4 (`days_utc` sorted, unique, 1–7, at least one; `dep_utc_min` 0–1439; origin and
  destination matching the route in the leg's direction).
- **The view `flight_legs_local`** (§3.12) and **`flight_no_clashes`**, both `security_invoker`. The other views in
  §3.12 belong to later pull requests.
- **The `private` schema** (§5), not exposed by the data API, holding the trigger functions.
- **The change log** exactly as §6: one trigger function `private.log_change()` on every table listed there that this
  pull request creates; the `equinox.actor`/`equinox.actor_detail` settings; the fallback to `planner` or `unset`;
  `equinox.change_log = off` honoured only for the `postgres` session user; updates log only changed columns and no
  row when nothing changed. `private.restore_row(...)` too, with a test.
- **Access** exactly as §5: RLS on every table with one staff policy per action using
  `(select public.is_planner_user())`; `anon` gets nothing on any new table, view or function; `authenticated` gets
  `select` on the new tables and views and `insert, update, delete` only on the planner's own tables (not
  `change_log`, which stays read-only to it); functions revoked from `public` and `anon`, then granted where needed;
  `security definer` only for the change-log trigger, with `set search_path = ''`.
- **Reference rows** (§9 step 1): the world Gander (`gander.airlinesim.aero`, kind `exclusive` per manual §9,
  `is_default` true); the group equinox. (kind `ours`); our six airlines with their game IDs, codes, home airports,
  public names, colours, display order and website text, taken from `capture/capture_all.user.js`, the planner's
  constants (`CODE_AL`, `CAP_HOME`, `AIRLINE_ORDER`, `LIVERY`) and `web/assets/site.js`. Leave a value null where none
  of these says, and list those in the pull request. `groups.owner_user_id` is looked up in the migration from
  `auth.users` joined to `planner_users` by email; it is null on the rehearsal copy (no sign-in data in backups), so the
  column is nullable. Never write an email address into the repository.
- **Descriptions** on every new table, view and function, and on every column whose meaning isn't obvious from its
  name. Extend `database/describe.sql` (and `describe.py` if needed) so the guide also covers the `private` schema's
  functions, then regenerate `docs/data.md`.

### 2. Not in this pull request
- Capture and scan tables (§3.8, §3.9), `game_flights` and the compatibility views: pull request 3.
- Loading the planner's data, the adapter: pull requests 4 and 5.
- `airline_days`, `route_days`: pull request 6. `job_runs`, `pg_cron`: pull request 7.
- No change to `planner_state`, the planner, the website, the capture or any existing table, policy, grant or
  function.

### 3. How to ship the migrations
- **One migration for everything that only adds** (`database/migrations/<timestamp>_planner_tables.sql`): tables,
  views, functions, policies, grants, descriptions and reference rows. Revoking on the objects it creates itself
  belongs here too, so the new objects are closed whatever the order.
- **A separate migration for the one change that alters existing behaviour:** the default privileges for future
  tables, sequences and functions in `public` (today live gives `anon` and `authenticated` everything by default; §5
  revokes that so a forgotten grant fails closed). Manual §1: Gitesh runs this file himself in Supabase's SQL editor,
  so keep it short and say so at the top of the file and in the pull request.
- Both must apply cleanly, in either order, on last night's copy.

### 4. Tests (`database/tests/`)
Each runs on the copy in a transaction that is rolled back.
- **Access:** for every table and view in `public`, `anon` has no `select` (`has_table_privilege`); every new table has
  RLS on; every new view is `security_invoker`; as `authenticated` with a JWT email not in `planner_users`, every new
  table reads zero rows and an insert is refused; as staff, a read and a write work.
- **Change log:** an insert, an update and a delete each write the right row with the actor that was set; an update
  that changes nothing writes no row; with no actor set, a write as staff logs `planner` and one as `postgres` logs
  `unset`; `equinox.change_log = off` skips logging for `postgres` and is ignored for `authenticated`;
  `private.restore_row` puts a row back.
- **Rules:** the `flight_legs` checks refuse bad weekdays, times and a direction that doesn't match the route; the
  reference rows are there (one world marked default, one group, six airlines with distinct game IDs and codes).
- **Through the data API** (extend `tests/real_saves_test.py`'s guard step): signed out and as the not-staff user, a
  read of each new table returns no rows and a write is refused.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` and the rule files it points to
  (security and RLS, schema design, indexes) before writing SQL.
- **Never connect to the live database or use the Supabase connector tools.** Last night's backup is only reachable
  inside GitHub Actions: test by pushing to the branch and reading the *Database rehearsal* result. Docker is
  available here for trying SQL on an empty local Supabase. If you need the regenerated `docs/data.md` from the
  rehearsal, have the workflow print the diff or upload the file as a run artifact, and copy it in.
- Work on branch `planner-tables`, open a pull request with the REST API (`gh api repos/GiteshJain/Equinox/pulls …`;
  GraphQL is blocked), and don't merge.
- `bash tests/run_all.sh` and the *Database rehearsal* must pass before asking for a merge.

## Done when
- The rehearsal passes on the pull request: both migrations apply, every test is `ok`, the guide matches, and the
  real-saves step is still all `ok`.
- One deliberate failure was seen to fail, then removed (for example, a new table left readable by `anon`).
- The pull request says what changed, which file Gitesh runs himself, the reference-row values left null, how it was
  tested, and anything in the design that turned out wrong or unclear.
- After "merge", the Building chat applies the adding migration to live, Gitesh runs the other, and the Building chat
  checks the live tables against the copy.

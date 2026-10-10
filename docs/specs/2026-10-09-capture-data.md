# Build spec: the capture data in the new model (#13 build, pull request 3) — 9 Oct 2026

**Why:** step 3 of the build order in `docs/design/2026-10-09-data-model.md` (§10). The evening capture moves into the
new model: one row per flown flight with its money and loads (`game_flights`), payments not tied to a flight in their
own table, world and airline ids on every capture table, and airlines matched by the game's ID. The old planner,
website and scripts read exactly what they read today, through views with today's names.

**Outcome when done:**
- Each capture writes `game_flights` and `game_payments`, as well as the raw statement lines as today.
- Every captured flight since 6 Oct is in `game_flights`, and every non-flight statement line in `game_payments`.
- `game_loads`, `game_flight_pnl` and `game_ops_recent` give exactly today's rows, from `game_flights`.
- A day's loads count as complete when all of that world's airlines are in, not at 6 (the 7th-airline bug).
- The capture accepts a new userscript that asks the database for its airlines, and still accepts today's.
- `anon` holds no rights on any table or view in `public`, old tables included.

## What to build
The design is the specification: §2 (keys, "a day"), §3.8 (capture tables, `game_flights` columns and keys, matching
money to loads), §3.12 (compatibility views), §3.13, §5 (access), §9 step 2 (backfill) and §10 row 3. This spec says
what belongs in this pull request and how to ship it. Where the two disagree, stop and say so in the pull request.

### 1. In this pull request
- **New tables:** `game_flights` and `game_payments`, exactly as §3.8, with RLS and grants as §5 (staff read; nothing
  for `anon`; writes only through the capture's functions). Not logged by the change log (§6).
- **Ids on the existing capture tables:** `world_id` and `airline_id` on `game_statement` (plus `flight_id` →
  `game_flights`), `game_events` (plus `due_at`), `game_balance` and `game_pnl` (plus `capture_day`),
  `game_capture_raw`; `world_id` on `capture_keys`. Fill them for every existing row. `capture_day` follows §2 (the
  UTC date of capture time minus 10 hours). `due_at` needs the home airport's UTC offset, which isn't loaded until
  pull request 4: fill it where `airports.utc_offset` is known and leave it null otherwise; pull request 4 fills the
  rest.
- **`game_loads` becomes a view.** Its rows move into `game_flights`; the table is renamed `game_loads_before_13` and
  kept (§3.13). `game_loads`, `game_flight_pnl` and `game_ops_recent` are views over `game_flights` that return today's
  columns and rows, `security_invoker`, readable by staff only.
- **The capture writes the new model.** `capture_ingest` (same name and arguments, so today's userscript keeps
  working) and the parsing behind it:
  - find the airline by the game's ID when the new userscript sends it, and by today's names otherwise;
  - a key belongs to one world, and a page for an airline outside the key's world is refused;
  - fold statement blocks into `game_flights` and non-flight lines into `game_payments`, and fill `game_flights`' loads
    columns from the loads page, matching money to loads as §3.8 says (same airline and route, nearest `dep_at` within
    −30 minutes to +3 hours; a block with no partner stays a money-only row until its loads arrive);
  - `route_id` and `aircraft_id` stay null while `routes` and `aircraft` are empty; pull request 4 fills them;
  - completeness by world: a day is complete when every active airline of our groups in that world has all five pages
    (§7's definition), wherever today's code counts to 6;
  - keep writing `planner_loads` through `apply_loads_from_capture` exactly as today; the planner still reads it until
    the switch-over.
- **`capture_airlines()`**, called with the capture key: the world's active airlines of our groups, with game ID and
  name, so the userscript no longer lists them itself. Update `capture/capture_all.user.js` to read its airlines from it
  and send the game ID. Keep the `__CAPTURE_KEY__` placeholder.
- **Internal steps to `private`** (§5): the parsing and matching steps that this pull request rewrites live in
  `private`. The old `public.parse_capture` stops being callable by `authenticated` (see the removal file below).
- **Backfill** (§9 step 2): `game_flights` from every statement line since 6 Oct plus the loads rows; non-flight lines
  into `game_payments`. Logged as `migration`, with the change log off where it applies.
- **Closing the old grants:** revoke everything `anon` holds on the 22 tables and 2 views that existed before #13
  (they're protected by their row rules today, but the design says `anon` gets nothing). Check first that the website,
  the investor page, the capture and the scripts only reach those tables through functions; if anything signed out
  reads a table directly, stop and report it.
- **Descriptions** on everything new or changed, and `docs/data.md` regenerated.

### 2. Not in this pull request
- **The world-scan tables** (renaming and splitting `game_snapshot*`): moved to pull request 6, where their summaries
  are built, so the scan's ingest and report functions change once, in one place.
- Loading the planner's data, routes, aircraft and airports (pull request 4); the adapter (5); daily history (6);
  `job_runs`, `pg_cron` and the 14-day statement clean-up (7; it stays switched off).
- No change to the planner, the website or `planner_state`.

### 3. How to ship the migrations
- **One migration that adds and changes** (`…_capture_data.sql`): new tables, new columns, the rewritten functions,
  the views, the backfill and descriptions. It must run as one piece and apply cleanly on last night's copy.
- **One short removal file** that Gitesh runs himself in Supabase's SQL editor (manual §1): the revokes from `anon` on
  the old tables, revoking `public.parse_capture` and anything else this pull request retires, and any drop. Say at the
  top of the file what it removes and why. Both files must work in either order.
- **The table rename** (`game_loads` → `game_loads_before_13`) and the view taking its name must happen in the same
  transaction, so nothing ever sees neither.
- In the pull request, say how long the adding migration takes on the copy. It will be applied after an evening's
  capture has finished, so a capture never runs half-way through it.

### 4. Proving it (the rehearsal, on last night's copy)
- **Before and after:** add a way for the rehearsal to save chosen outputs before the pending migrations run, so a test
  can compare them afterwards. Then prove, row by row:
  - `game_loads`, `game_flight_pnl` and `game_ops_recent` return the same rows as before (every statement block since
    6 Oct included);
  - `export_capture()`, `export_for_report('planner')` and `site_public()` return the same as before, apart from
    timestamps they generate;
  - `planner_loads` is unchanged.
- **Replay:** run every raw page kept in the copy (`game_capture_raw`, 14 days) through the new capture path into an
  empty set of capture tables, inside a rolled-back transaction, and prove it produces the same `game_flights`,
  `game_payments`, `game_events`, `game_balance` and `game_pnl` rows as the backfill. Then replay with the new
  userscript's form (game IDs) and get the same rows again.
- **Completeness:** with a 7th active airline added to the group in a test, a day isn't complete until it's captured
  too.
- **Access:** no table or view in `public` grants `anon` anything once both files have run; the new tables read no
  rows for a signed-in account that isn't staff; the data-API guard in `tests/real_saves_test.py` covers the new
  tables and views.
- **Matching:** a test with hand-made rows for the edge cases: a flight posted late (up to +3 hours), a money-only
  block whose loads arrive the next capture, two flights on one route close together, and Kingfisher's 1001/1002
  flown on alternate days by two aircraft.
- The real-saves step still passes.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` and its rule files before writing
  SQL. Read the current capture code in `database/current/functions.sql` and `views.sql` and the migrations that made
  it, and `capture/capture_all.user.js`, before changing them.
- **Never connect to the live database or use the Supabase connector tools.** Last night's backup is only reachable
  inside GitHub Actions: test by pushing and reading the *Database rehearsal* result. Docker is available here for
  trying SQL on an empty local Supabase.
- Work on branch `capture-data`, open the pull request with the REST API (`gh api repos/GiteshJain/Equinox/pulls …`;
  GraphQL is blocked), and don't merge.
- `bash tests/run_all.sh` and the *Database rehearsal* must pass before asking for a merge.

## Done when
- The rehearsal passes with every proof above `ok`, and a deliberate failure was seen to fail, then removed (for
  example, one statement block left unmatched).
- The pull request says what changed, which file Gitesh runs himself, how long the migration takes, what Gitesh must
  do for the new userscript (it goes on the planner's To-do board after merge), and anything in the design that turned
  out wrong or unclear.
- After "merge", once that evening's capture is done: the adding migration goes to live, Gitesh runs the removal
  file, and the Building chat checks live against the copy and watches the next evening's capture land in
  `game_flights`.

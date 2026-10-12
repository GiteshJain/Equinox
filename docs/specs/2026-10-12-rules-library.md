# Build spec: the planning library (#18 build, pull request 2) — 12 Oct 2026

**Why:** step 2 of the build order (`docs/design/2026-10-12-planner-app.md` §13), decision #19. The planning rules
(times, block times, turns, connections, banks, maintenance, schedule checks, positions, the optimiser) get their one
home, so the new planner's screens, the website's trip search, the optimiser and Claude all give the same answer. The
game is paused and the old planner frozen (manual §1): **nothing in `web/planner/` or `web/assets/` changes.**

**Outcome when done:**
- `lib/rules/` is a TypeScript library with no screen code: plain data in, plain data out. It reads every number from
  the database's settings, world rules, aircraft types and airports; nothing is typed into code.
- A new database function, `rules_input(world)`, gives the library everything it needs in one call, and
  `export_for_report()` gains kind `rules` for the scripts.
- `node lib/rules/dist/cli.js <command> <input.json>` lets Claude and the scripts use it.
- On last night's copy, the library's figures equal the old planner's Tails and Hubs figures, except where the manual
  and the old planner disagree. Every such difference is listed in the pull request.
- Nothing changes for any user: no screen, the website and the scripts are untouched (pull request 4 moves them on).

## What to build
The design is the specification: §2 (principles), §3 (layout), §7 (the library), §10 (checks). Where the design, the
manual and this spec disagree, stop and say so. **The manual (§4) is the rulebook for every rule;** the old planner's
code is the reference for how it's worked out.

### 1. The library (`lib/rules/`, design §7)
TypeScript, strict, built with the root project's tools (add `lib/rules/tsconfig.json`; the root scripts `typecheck`,
`lint` and `test` cover it; `build` also writes `lib/rules/dist/`, gitignored). The new planner imports it from source
through a path alias; nothing in `app/planner/` uses it yet.

**Input:** one `Rules` object built from `rules_input()`'s answer (§2), with a typed builder. Times are minutes from
Monday 00:00 UTC across the week (0 to 10,079), as `flight_legs` stores them (`days_utc`, `dep_utc_min`,
`block_min`).

| Part | What it works out | The rule (manual) | The old code to follow |
|---|---|---|---|
| `time` | Local and UTC times for an airport (standard time all year), and local weekdays | §9; `world_airports.utc_offset_override`, else `airports.utc_offset` | `utcOf`; the optimiser's `off` |
| `block` | Block minutes for a leg not yet timed: `block_allowance_min` + distance ÷ the type's `cruise_kmh`, rounded. A leg with `block_min` stored uses that | §4 | `blockMin`, `estBlockFor` (see *Differences*); `plan.py`'s `block` |
| `turns` | Whether a turn fits: ground time ≥ the type's `min_turn_min` + `turn_margin_min`; flags short turns | §4 | The old planner's turn checks (search `minTurn`) |
| `connections` | For an arrival and a departure at the same airport, the days it connects and the tightest gap: gap ≥ `mct_min` + `connection_buffer_min` and ≤ `connection_max_wait_h`, across the week. Onward flights and feeders of a leg; connections at a hub across all our airlines; city pairs linked | §4 | `link`, `onward`, `feeders`, `hubBoard`; `plan.py`'s `conns` |
| `banks` | Bank windows from `airline_bases.bank_times` with `bank_arrival_window_min`, `bank_departure_window_min` and `bank_buffer_min`; which bank a departure collects and an arrival feeds. Focus cities have none | §4 | `bankWindows`, `waveAt` |
| `maintenance` | Per aircraft for the week: need = cycles × `maint_per_cycle` + block hours × `maint_per_hour`; have = each ground gap's time beyond `ground_keep_min`, counted when that is ≥ `maint_min_ground_min`. Ratio, need and have a day; below `maintenance_min_pct` is bad, below `maintenance_target_pct` a warning | §4 | `maintFor`, `legsForTail` |
| `aircraftWeek` | Per aircraft: legs a week, block hours a day, routes flown, its legs in order with ground gaps | — | The Tails screen (`renderTailsCore`) |
| `schedule` | Night bans (`world_airports.night_ban_from/to`) hit by a departure or arrival; a second daily closer than `second_daily_gap_h`; a flight number used twice; departures a week per airport against `world_rules` caps; the next free flight-number pair at a base (next odd above the highest in use, from `airline_bases.flight_no_from` and `last_flight_no`) | §4, §9 | The old planner's attention checks; `nextPair` |
| `positions` | Where each aircraft is at a given UTC moment: on the ground at an airport, or in the air between two with the share flown | — | The old planner's and the website's map code (search `terminator`, `positions`) |
| `optimiser` | The best day's schedule for one aircraft from a base and a set of destinations: every order and start time, each feasible against night bans, maintenance ≥ 100%, the second-daily gap and turns; best by connections at the base (and any extra hubs), then maintenance | §4 | `scripts/planning/plan.py` (stays until pull request 4) |

- **Nothing assumes six airlines or one world.** Airlines, bases and airports come from the input.
- **Pure functions** with no clock, network or global state: a moment is always an argument.
- **Exported names** are the ones above, with types for every input and answer. A short `lib/rules/README.md` says
  what each part does, in plain words, with one example each.

### 2. `rules_input(p_world_id bigint default null)` (a new migration)
Returns one JSON document for the world (the default world when null):
- `settings` (with each airline's overrides) and `world_rules`, as key → value;
- `aircraft_types` (name, cruise, minimum turn, maintenance per cycle and hour, ground keep, seats);
- `cabin_configs` (code, type, seats);
- `airports` for every airport any route, leg or base uses (code, city, country, lat, lon, UTC offset with the
  override applied, `mct_min`, night ban from and to);
- `airlines` (id, code, names, position, active) and `airline_bases` (airport, role, main, parent, bank times,
  flight-number range, last used);
- `aircraft` (id, registration, airline, type, cabin, base, status);
- `routes` that aren't removed (id, airline, hub, destination, distance with any override applied, market);
- `rotations` and `flight_legs` (every column the library needs).

Staff can call it (same check as the planner's getters); scripts through `export_for_report()` with kind `rules`
(ingest secret, as the other kinds). Runs as owner with an empty search path, with a description. A test in
`database/tests/` (`rules_input_test.sql`): the document's counts equal the tables'; one leg, one airport and one
setting read back exactly; an airline override wins over the world value; signed out and an account that isn't staff
are refused; `export_for_report('rules')` with the secret gives the same document and refuses a wrong secret.

### 3. The command (`lib/rules/src/cli.ts`)
`node lib/rules/dist/cli.js <command> <input.json> [options]`, answering JSON on standard output, errors on standard
error with a non-zero exit. `input.json` is `rules_input()`'s answer. Commands:
- `block <origin> <dest> <type>`;
- `connections <airport>` (every connection there, with days and gaps);
- `aircraft [registration]` (the `aircraft_week` and maintenance answers);
- `check-card <card.json>` (a plan card's legs checked against every rule above, at both ends);
- `optimise <base> <dest,dest,...> --type <type> [--start 05:00-11:00] [--hubs X,Y]`.

`scripts/README.md` gets a short section on how Claude runs it (fetch `rules_input` through `export_for_report`, then
the command).

### 4. Tests
- **Cases** (`lib/rules/cases/*.json`, inputs and answers), run by Vitest on every pull request. Hand-made, small,
  covering each part, with the edges:
  - a connection exactly at the minimum, one minute under, exactly at 8 hours and one over;
  - a leg across midnight UTC and across Sunday into Monday;
  - an airport with an override of its UTC offset;
  - a night ban that wraps past midnight;
  - a maintenance gap just under `maint_min_ground_min`;
  - a focus city with no banks;
  - a flight number used twice;
  - an optimiser case with a known best plan.

  The case format is plain JSON so pull request 3's database tests can reuse the cases that apply to both homes.
- **The optimiser against `plan.py`:** on one fixed input (a small JSON in `lib/rules/cases/`, made from the test
  sample's legs), the library's best plan equals `plan.py`'s: same order, start, connections and maintenance. `plan.py`
  stays unchanged.
- **Side by side on last night's copy (the rehearsal),** a new test `tests/rules_library_test.py`:
  1. `rules_input()` on the copy, saved to a file, run through the command;
  2. the old planner opened at the same frozen moment on the same copy, as `real_saves_test.py` opens it, signed in as
     the test staff user;
  3. **Tails:** for every aircraft, legs a week, block hours a day (to one decimal), maintenance % (whole) and routes
     must equal the old planner's Tails row;
  4. **Hubs:** for each hub, the connections and city pairs the old planner's Hubs screen shows must equal the
     library's;
  5. **block times:** for every leg with stored times, the library's estimate for its route and type, compared with
     the stored `block_min`. Print how many are exact, within 2 minutes and further out (this is information, not a
     pass or fail; `plan.py`'s note says about 93% exact and never more than 2 minutes out on 7 Oct).

  Any figure that differs fails the step, **unless it's on the list of known differences** below, kept in the test
  with the manual's rule beside it. Each one used is printed with how often.

### 5. Differences to expect (the manual wins)
- **Block estimates:** the old planner fits its estimate to the times typed in (`calibration`); the manual says
  25 minutes + distance ÷ speed. The library follows the manual. Only legs without stored times use an estimate, so
  Tails and Hubs shouldn't move. If they do, stop and report.
- **Minimum connection time:** the old planner uses its hub's figure, or 90 minutes elsewhere (`mctAt`); the manual
  says each airport's `mct_min`. The library follows the manual, using 90 minutes only where `mct_min` is empty. List
  any airport where the two differ.
- **Anything else** that differs is a finding: stop and report it in the pull request with the figures, rather than
  bending the library to match.

### 6. The rehearsal
`database-rehearsal.yml` also runs when `lib/**` changes. After the existing steps it builds the library and runs
`tests/rules_library_test.py`. The time limit stays 30 minutes; say in the pull request how long the run took.

### 7. Docs, in the same pull request
- **The map** (`docs/architecture.md`): the library, `rules_input()`, the command. Claude copies it into the project
  after the merge.
- **`lib/rules/README.md`** (above), **`scripts/README.md`** (the command), **`tests/README.md`** (the new test and
  cases), **`docs/data.md`** (regenerated by the rehearsal).
- **The manual:** no rule changes. If a known difference shows the manual is wrong about how the game works, say so in
  the pull request; Gitesh decides.

## Proving it
- `bash tests/run_all.sh` passes, with the library's type check, lint and cases.
- The rehearsal passes: `rules_input_test.sql` ok, every step of `tests/rules_library_test.py` ok, the block-time
  count printed, every known difference used listed.
- **A deliberate failure** is seen to fail, then removed: the connection rule with `>` in place of `>=` at the minimum
  (the case at exactly the minimum must fail, and the side by side should too if any connection sits exactly on it).

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` and its rule files for the
  migration. Read `tests/planner_next_test.py`, `tests/real_saves_test.py` and `database/rehearse.sh` before writing
  the new test.
- The old planner's code is one large file: search for the functions named above rather than reading it whole. Its
  pure logic starts at `// ---- Gander planner: pure logic (no DOM) ----`.
- **Never connect to the live database or use the Supabase connector tools.** Test by pushing and reading the *checks*
  and *Database rehearsal* results. Docker is available here.
- **Don't change `web/planner/`, `web/assets/` or `scripts/planning/plan.py`.**
- Work on branch `rules-library`, open the pull request with the REST API (GraphQL is blocked), and don't merge.

## Done when
- Every proof above is `ok`, and the deliberate failure was seen to fail, then removed.
- The pull request says: what changed; the rehearsal's run time; the block-time count; every known difference used,
  with how often; any finding; the steps after "merge" in order (Claude applies the migration to live, or gives Gitesh
  the file if it's cancelled twice, then sets the migration record); how to roll back (revert, then drop
  `rules_input()` and restore `export_for_report()`); anything outside the repository that needs a follow-up.

# Build spec: the website and scripts read the tables (#13 build, pull request 8) — 10 Oct 2026

**Why:** step 8 of the build order (`docs/design/2026-10-09-data-model.md` §10), brought forward on 10 Oct: Gitesh
dropped the wait for clean days, so the switch-over (pull request 9) comes next, and it freezes `planner_state` and
`planner_loads`. Everything else that reads those rows must read the tables first, or the website, the investor page
and the weekly-report scripts would go stale at the switch.

**Outcome when done:**
- `site_public()`, `site_investor()`, `site_report()`, `site_admin()`, `export_for_report()`, `planner_data_set()` and
  the Photos functions read and write the tables, not `planner_state` or `planner_loads`.
- Their outputs are exactly today's (apart from one addition below), so the website, investor page, gander monthly
  and Claude's scripts don't change.
- Nothing outside the planner reads `planner_state` or `planner_loads` any more.

## What to build
The design is the specification: §8 "The website and scripts keep their outputs exactly", §5 (access), §3.13. Where
the design and this spec disagree, stop and say so in the pull request.

### 1. In this pull request
- **Find every reader first.** List every function, view and script (`database/current/functions.sql`, `views.sql`,
  `scripts/`, `web/`) that reads or writes `planner_state`, `planner_loads`, `planner_data` or `site_content.mct`.
  Put the list in the pull request, each with what this pull request does about it.
- **`site_public()`** builds hubs, tails, compact frequencies, signed interlines and `content.mct` from the tables
  (§8), and adds one key, `airlines` (names, codes, colours, descriptions, display order), from `airlines`. The
  website (`web/assets/site.js`) reads airline names, colours, order and text from that key instead of its own copy,
  keeping its copy only as a fallback if the key is missing. The public feed's 6 Oct limits stay: no bank or transfer
  times, no cabin layouts, no aircraft on order.
- **`site_investor()`** and **`site_report()`** read cash and next-7-day costs as the getter does, spending from
  `spending_log`, loads through `planner_loads_get()`.
- **`site_admin()`**: any kind that reads or writes the planner's data uses the tables; `('content', 'mct')` writes
  `world_airports` (and `site_public()` still returns it under `content.mct`).
- **`export_for_report('planner')`** returns `{state, loads}` built from `planner_state_get()` and `planner_loads_get()`
  in exactly today's shapes (unwrap the getters' answers). Its scan kinds stay as they are (the scan tables change in
  pull request 6).
- **`planner_data_set()`** writes `routes`, `airports` and `countries` (changed rows only), **and keeps writing
  `planner_data` as today**, because the old planner reads its route research from `planner_data` directly until #18.
- **The Photos functions** check the airline against `airlines` instead of a list in their code.
- **Descriptions** on everything changed, and `docs/data.md` regenerated.

### 2. Not in this pull request
- No change to the planner, to `planner_state`'s or `planner_loads`' own storage, or to the side-by-side trigger
  (pull request 9 does the switch and the freeze).
- History, scans (6); jobs (7); report PDFs (10).

### 3. How to ship
- One migration. If anything removes or revokes something that exists, it goes in a short separate file for Gitesh
  (manual §1). The website change ships with it in the same pull request; say in the pull request which order is safe
  (the website must work with both the old and the new `site_public()`, since Cloudflare publishes on merge and the
  migration is applied by hand afterwards).

### 4. Proving it (the rehearsal, on last night's copy)
- **Before and after** (the mechanism from pull request 3): `site_public()`, `site_investor(<password>)` with a
  throwaway password, `site_report()` for one report, `export_for_report('planner')`, `export_capture()` and every
  `site_admin` read kind return exactly what they did before the migration, apart from `site_public()`'s new
  `airlines` key and `updated_at`. List any other difference and stop if there is one.
- **The website on the new feed:** `tests/site_test.py` passes with the sample's feed plus the `airlines` key, and
  with the old feed without it (the fallback).
- **Writers:** `planner_data_set` changes one route and one airport: the tables change in exactly those rows, and
  `planner_data` too; `site_admin('content', 'mct')` changes one connection time: `world_airports` changes and
  `site_public()` shows it.
- **No reader left:** a test that fails if any function outside the adapter and the side-by-side trigger names
  `planner_state` or `planner_loads` (from `pg_proc`), listing them.
- The real-saves step and every earlier test still pass.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` and its rule files before writing
  SQL. Read the previous builds' migrations and tests (`20261010120000_planner_data_load.sql`,
  `20261010210000_adapter_write_side.sql`) for the getters, the conventions and the before-and-after mechanism.
- The planner (`web/planner/index.html`) is not changed. The website is `web/index.html` and `web/assets/site.js`.
- **Never connect to the live database or use the Supabase connector tools.** Test by pushing and reading the
  *Database rehearsal* and *checks* results. Docker is available here.
- Work on branch `website-scripts`, open the pull request with the REST API (GraphQL is blocked), and don't merge.
- `bash tests/run_all.sh` and the *Database rehearsal* must pass before asking for a merge.

## Done when
- The rehearsal passes with every proof above `ok`, and a deliberate failure was seen to fail, then removed.
- The pull request says what changed, the list of readers, the safe order between the website and the migration, and
  anything in the design that turned out wrong or unclear.
- After "merge", the migration goes to live; the Building chat compares the live outputs before and after.

# Build spec: real saves on a local Supabase copy (#13 build, pull request 1) — 9 Oct 2026

**Why:** decision #17 (B). Before the #13 adapter can reach live, the planner's saves must be tried for real on a copy
of live: signed in, saving, and the tables read back afterwards. Today's checks only save into a stand-in
(`tests/harness.py`), and the rehearsal only runs SQL. This is step 1 of the build order in
`docs/design/2026-10-09-data-model.md` (§10); every later step relies on it.

**Outcome when done:**
- On every pull request that touches the database or the planner, the *Database rehearsal* check:
  1. restores last night's backup into a **full** local Supabase (database, data API and sign-in);
  2. applies the pull request's database changes and runs the SQL tests, as today;
  3. opens the pull request's own planner, signed in as a test staff user, and saves for real into that copy;
  4. reads the tables back and fails if anything other than the intended change was written.
- Nothing touches the live database. The copy and the test users exist only on the runner.
- The planner itself doesn't change.

## What to build

### 1. Full local Supabase in the rehearsal (`database/rehearse.sh`)
- Start the stack with `supabase start` instead of `supabase db start`, leaving out what isn't needed (Studio,
  Realtime, Storage, image proxy, Edge Functions, logs, mail and anything else the planner doesn't call). Keep
  Postgres 17, as today.
- Restore the backup exactly as today (roles, the default-privilege revokes, schema and data, migration history). The
  backup has no `auth` data, which is expected.
- After the restore and the pending migrations, tell the data API to reload its schema (`notify pgrst, 'reload schema'`)
  and wait until it answers.
- Everything that exists today stays, in the same order and with the same output: restore, pending changes, row
  counts, SQL tests, descriptions.
- Then a new last step, **real saves** (below). It runs only when the earlier steps passed, and its result counts
  towards the check's pass or fail.
- Keep the whole check inside 30 minutes. Raise the workflow's `timeout-minutes` to 30 if needed, not beyond.

### 2. Test users on the copy
- Create two users through the local sign-in's admin API, with throwaway passwords made on the runner:
  - **staff:** added to `planner_users`, so `public.is_planner_user()` is true for it;
  - **not staff:** a signed-in account that isn't in `planner_users`.
- Read the local URL and keys from `supabase status -o env`. Never print them. They are local and thrown away, but the
  log mustn't look like it holds keys (`tests/check_secrets.py` must still pass).

### 3. The real-saves test (`tests/real_saves_test.py`)
Python and Playwright 1.56, reusing `tests/harness.py` where it fits (`serve()`, the live-address mapping), but with
**no stand-in**: the planner's real Supabase library talks to the local copy.
- **Open the planner as live** (`equinox-alliance.com` mapped to the local server, as `open_planner(live=True)` does),
  so it saves; a look-only preview would refuse.
- **Point it at the copy:** rewrite every request for `https://ulecwsyedvwcxgdzmhoq.supabase.co` to the local data API,
  and swap the live publishable key for the local one in those requests. Abort any other outside request.
- **Load the planner's Supabase library for real:** the exact version the planner names
  (`@supabase/supabase-js@2.49.4`, UMD build), installed from npm on the runner and served in place of the CDN copy.
- **Sign in** through the planner's own sign-in form as the staff user (it uses `signInWithPassword`).
- **Saves to make** (one at a time, each followed by reading the tables with `psql`):
  1. tick an open to-do as done;
  2. change one plan card's title;
  3. type a load for one flight on the Review page (the manual loads entry, which goes through `save_loads`).

  Pick the items from the restored data at run time (the first open to-do, the first plan card, a flight on a recent
  day), so the test doesn't depend on one night's contents.
- **Prove each save:**
  - for 1 and 2: parse `planner_state.json` before and after. The only difference is the intended field, plus
    `savedAt`/`version`-style bookkeeping; `saved_at` moved forward;
  - for 3: the month's `planner_loads` row has the typed value for that day and flight, and every other day and
    flight is unchanged;
  - no other table's row count changed (reuse `database/backup/counts.sql`).
- **Prove the guard:** signed in as the not-staff user, reading `planner_state` through the data API returns no rows,
  and an attempt to write it is refused. Use the data API directly for this part, not the planner.
- **Prove nothing went outside:** the test fails if any request reached the live Supabase host or any address other
  than the local server, the local data API and the served library.
- Print one line per step (`ok    tick a to-do`, `FAIL  …` with the reason). Print no row contents beyond ids and the
  field names that changed: the log is posted on the pull request.

### 4. The workflow (`.github/workflows/database-rehearsal.yml`)
- Also run when a pull request changes `web/planner/**`, `tests/real_saves_test.py` or `tests/harness.py`, since a
  planner change can break saving.
- Install Python 3.12, Playwright 1.56 with Chromium, and Node 22 for the npm library, as `checks.yml` does.
- Keep the R2 reader keys exactly as today, and keep the comment that's posted on the pull request.

### 5. Docs, in the same pull request
- `tests/README.md`: a row for the real-saves test, and the rehearsal's row updated.
- `docs/architecture.md`: the rehearsal now starts a full local Supabase and tries real saves.
- `database/rehearse.sh` header comment: the new step.
- Nothing in the manual changes.

## Out of scope
- The #13 tables and the adapter (pull requests 2 onwards). This only builds the bench they will be tested on.
- Any change to `web/planner/index.html`. If the planner can't be pointed at the copy without changing it, stop and
  say why in the pull request instead.
- The `checks` workflow and `tests/run_all.sh`: the real-saves test needs Docker and the backup, so it runs only in the
  rehearsal.

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` before touching the database
  parts.
- **Never connect to the live database or use the Supabase connector tools.** Everything runs on GitHub's runner
  against the restored copy. The backup can only be read in GitHub Actions (the R2 reader keys are secrets there), so
  test by pushing to the branch and reading the *Database rehearsal* result.
- Work on branch `real-saves-check`, open a pull request, and don't merge. GitHub's GraphQL API isn't reachable from
  this environment: use the REST API (`gh api repos/GiteshJain/Equinox/pulls …`) to open and inspect the pull request.
- `bash tests/run_all.sh` must pass, and the *Database rehearsal* must pass on the pull request, before asking for a
  merge.

## Done when
- The *Database rehearsal* passes on the pull request, with the three saves, the guard and the outside-request check
  each reported `ok`.
- One deliberate failure was seen to fail, then removed: for example, the test expecting a different to-do flag. Say
  in the pull request how it failed.
- The pull request says what changed, why, how it was tested and how long the check now takes.

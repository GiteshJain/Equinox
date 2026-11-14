# Spec: a failed nightly rehearsal shows on Today

To-do 239 (Gitesh, 15 Nov, Main chat: brief `docs/briefs/2026-11-15-nightly-rehearsal-failure.md`, **option B**); it
settles to-do 234's steps 1 and 11. One small pull request: a migration, its test, the planner's two screens, the
documents.

## What it does, in one paragraph
Every hour the database asks GitHub how the nightly rehearsal on `main` went and writes each finished night into
`job_runs` (job `rehearsal`), as every other job does. A failed night then shows on Today's needs attention with the
other nightly jobs, and the Systems board gets a line for it. No result for 36 hours shows too, in amber, so a night
that never ran is seen. The run itself is unchanged: GitHub's timer still starts it (08:43 UTC, often 6 to 9 hours
late), and GitHub still emails when it fails.

## How the result reaches `job_runs`, and why this way
**The database reads it from GitHub's public API, on its own scheduler.** `private.rehearsal_read()` (pg_cron
`equinox-rehearsal-read`, every hour at :50) asks
`GET https://api.github.com/repos/GiteshJain/Equinox/actions/workflows/database-rehearsal.yml/runs?branch=main&per_page=10`
through `pg_net`, with no key (the repository is public). The next hour it notes the answer, as
`private.capture_dispatch_answer()` does for the unattended capture's start, and `private.rehearsal_record()` writes
one `job_runs` row per finished nightly run.

- **Gitesh does nothing.** No key in GitHub's secrets, no token, no change to the vault.
- **Nobody can write a result.** Only GitHub's own record of the run is read. A run counts only when it is this
  workflow, in `GiteshJain/Equinox`, on `main`, started by the timer (`schedule`) or by hand (`workflow_dispatch`). A
  pull request's run (event `pull_request`), a fork's or another branch's is never recorded, and only a person with
  write access can start a run on `main`.
- **A night that never ran is seen**, which a report sent by the run itself could never do.
- **Only GitHub's fixed words are kept**: the run's id, attempt, event, result word (`success`, `failure` …), times,
  address and commit. Never a commit message or any other free text from the answer.

**Considered and not taken: the workflow's last step reports.** This is how the nightly backup and the unattended
capture report, but they use the database's full address (`SUPABASE_DB_URL`) from the private `equinox-backups`
repository. In this public repository that key would be readable by every pull request's run, so it would need a new,
narrow key: a function that takes only a rehearsal result, a key issued by Gitesh in the SQL editor and pasted into a
new secret (his one step). It still could not report a run that never started. The read needs nothing from him and
can't be written to, so it was built; the Main chat can still choose the other.

## What each night looks like
| | Today's needs attention | Systems board, *Nightly rehearsal (main)* |
|---|---|---|
| No result yet (before the first read) | nothing | amber: "no result yet: GitHub starts it every night (08:43 UTC, often hours late) and the database reads it every hour" |
| A good night | nothing | green: "passed: every part on the latest backup, in 13 min · 20 hours ago" |
| A failed night | red, in Nightly jobs: "Nightly database rehearsal (main): the last run failed (Sun, Nov 15 16:10 UTC): failed (failure) after 21 min: the log is on GitHub's Actions page, run 43…" | red, with the same note and the last good run |
| No result for over 36 hours | amber: "Nightly database rehearsal: no result from main for 40 hours (the run didn't start, or the database couldn't read GitHub: see Systems)" | amber to 60 hours, red beyond, with the last failed read of GitHub's words |

A good night after a failed one clears Today's item (each job's last run counts, manual §7). A run GitHub re-runs
changes its row. A cancelled run writes nothing (the run that replaced it reports); a run still going waits for the
next read. A failed read of GitHub (`rehearsal_read` failed, e.g. "GitHub answered 403") is not a Today item on its own:
it shows on the board's line, and on Today only through the 36-hour warning. Read rows older than 14 days are deleted.

## Files
- `database/migrations/20261115120000_rehearsal_on_today.sql`: `job_runs.job` takes `rehearsal` and
  `rehearsal_read`; `private.rehearsal_record(jsonb)` and `private.rehearsal_read(timestamptz)` (postgres only);
  `private.schedule_jobs()` adds `equinox-rehearsal-read`; `system_status()` adds `rehearsal` (`last` with its note
  and address, `last_ok`, `read`). Nothing dropped or renamed, so it applies from the chat.
- `database/tests/rehearsal_on_today_test.sql`; `database/current/functions.sql`; `docs/data.md`.
- The planner: `app/planner/src/screens/home/reads.ts` (Today reads the `rehearsal` rows),
  `screens/today/attention.ts` (its name, the 36-hour warning), `screens/systems/systems.ts` and `reads.ts` (the
  line), with tests in `today/today.test.ts` and `systems/systems.test.ts`; `tests/planner_next_test.py` (the board's
  tiles on the copy).
- Documents: manual §1 *Automatic checks* and §7's two sentences, `docs/rule-history.md`, the map's *What runs when*
  row for 08:43 UTC, `docs/map/checks.md`, `docs/planner-guide.md`.
- Not changed: `.github/workflows/database-rehearsal.yml` (the timer stays GitHub's).

## What the checks should show
- `bash tests/run_all.sh`: all green; the planner's unit tests include the new cases (Today: no row, a good night, a
  failed one, a good night after a failed one, 40 hours with nothing; Systems: no result, green at 36 hours, amber at
  40 with a failed read, red at 61, a failed night with and without a good one before it).
- The database rehearsal (the migration changes the database, so every part runs): `rehearsal_on_today_test.sql`
  passes (the catalogue, the record on a hand-made answer, the read with answers made by hand in pg_net's table,
  `system_status()`'s part); the descriptions, `docs/data.md` and the reference file match; the planner on the copy
  shows the board's new tile, amber until the copy has a result.

## After "merge"
1. The Main chat applies the migration to live from the chat (nothing is removed) and records its version.
2. At the next :50 the first read is asked; at the one after, the 12 to 15 Nov runs land in `job_runs`. The Main chat
   checks: `select job, status, started_at, note from job_runs where job like 'rehearsal%' order by id desc limit 5;`
3. Gitesh does nothing.

## Outside the spec
- **GitHub turns off a public repository's scheduled runs after 60 days with no activity** (to-do 234 step 3). With
  this build Today would say so 36 hours later ("no result from main"), but switching the timer back on, or keeping
  the repository active, is not part of it.
- The timer's lateness (6 to 9 hours) is left as it is (the brief's option B; step 11).
- GitHub allows 60 unauthenticated calls an hour from one address. The read makes one an hour; if the database's
  address is shared and the limit is reached, the board says "GitHub answered 403" and Today warns only after 36 hours.
  Sending the vault's existing token with the read would lift the limit; it was left out on purpose (that token is for
  `equinox-backups` only).

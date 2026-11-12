# Spec: faster checks on a pull request

To-do 233 (decided by Gitesh, 11 Nov, Main chat: brief `docs/briefs/2026-11-11-faster-checks.md`, **option E**, in two
pull requests). Read `CLAUDE.md`, the map (`docs/architecture.md`, then `docs/map/checks.md`), manual §1 *Automatic
checks*, `tests/README.md` and the brief first.

## What it does, in one paragraph
A pull request waits only for the parts of the *Database rehearsal* that its change can affect. A planner change, the
glass look included, gets the planner's types, every screen at both widths and every kind of save on the copy, and no
database tests. A database change gets everything. Documents get nothing, and the rehearsal doesn't run. Anything the
rules don't know runs everything. Every night the whole rehearsal runs on `main`, so what a pull request skipped is still
checked within a day. The second pull request then runs the slow parts side by side.

## Measured on 11 Nov (the brief's figures, to compare against)
- Four rehearsals (runs 43019391073, 43002791037, 42988875238, 42984487997): 19.7 to 30.8 minutes each, documents
  included. Every part ran in every run.
- Database tests 8 to 15 minutes (capture replay 4 to 8, `briefing_test.sql` 1.6 to 3); the planner on the copy 3.3 to
  5.7; the saves 2.7 to 2.9; the briefing and map guide 1.6 to 2.8; restore 1.3 to 1.6; outputs before 1.2 to 1.8; backup
  and restore 0.6 to 0.7.
- Of the last 60 rehearsals, 27 failed and 4 were cancelled; 8 failures were the descriptions or types check, which ran
  about 18 minutes in.

## 1. The first pull request: only the parts a change can affect, and the nightly run

### The parts
`database/rehearse.sh` runs these, each only when `REHEARSE_PARTS` names it (unset or `all`: every part):

| Part | What runs |
|---|---|
| (always) | The backup restored, every migration live doesn't have yet applied (those already on `main` too, so the planner meets the database as live has it), the copy's jobs paused |
| `db` | The outputs saved before the changes, the database tests, the figures moved, the backup and restore |
| `reference` | The descriptions (`docs/data.md`) and the reference file (`database/current/functions.sql`) |
| `types` | The planner's types generated from the copy, against `app/planner/src/db/types.ts` |
| `planner` | The planner built and opened on the copy (`tests/planner_next_test.py`) |
| `saves` | Every kind of save (`tests/planner_saves_test.py`); always with `planner`, after it, since it imports its module |
| `briefing` | The airline briefing for every airline and the map's guide (`tests/briefing_copy_test.py`) |
| `samples` | A sample made from the copy; which ones, the workflow decides from the sample files themselves, as before |

The `reference` and `types` checks run straight after the migrations, before the samples and the database tests. They
need only the copy, and they were the most common red. Their failure fails the run but stops nothing after it, as
before.

### The groups (`database/rehearsal_parts.py`)
Each changed path starts the parts of every group it is in. The pull request runs the union.

| Paths | Parts |
|---|---|
| `database/**`, `.github/workflows/database-rehearsal.yml`, `tests/rehearsal_parts_test.py` | every part |
| `tests/fixtures/capture_pages_*.json.gz` | `db` |
| `docs/data.md` | `reference` |
| `app/**`, `web/_redirects`, `web/assets/**`, `package.json`, `package-lock.json`, `.nvmrc`, `tests/planner_next_test.py`, `tests/plan_card_cabins.mjs` | `types`, `planner`, `saves` |
| `lib/**`, `package.json`, `package-lock.json`, `.nvmrc` | `types`, `planner`, `saves`, `briefing` |
| `tests/harness.py`, `tests/local_copy.py`, `tests/fixtures/sample_*.json.gz`, `tests/fixtures/schedule_113.expected.json` | `types`, `planner`, `saves`, `briefing` |
| `tests/planner_saves_test.py`, `tests/planner_flights.mjs`, `tests/fixtures/planner_saves.expected.json`, `tests/fixtures/load_table_sample.tsv` | `types`, `planner`, `saves` |
| `scripts/briefing/**`, `scripts/report/analyze.py`, `tests/briefing_copy_test.py` | `briefing` |
| `tests/fixtures/{make_sample.sh,sample.sql,report_sample.sql,report_sample.py,capture_sample.sql}` | `samples` |
| `tests/fixtures/briefing_sample.{sql,py}` | `samples`, `briefing` |

**Outside** (starts nothing, unless a group above matches): `docs/**` (the map, `docs/architecture.md`, included: its
guide runs every night and with the briefing), any `*.md`, `capture/**`, `functions/**`, the rest of `web/**`,
`scripts/**` and `tests/**`, `.claude/**`, `.github/workflows/checks.yml`, `.gitignore`, `eslint.config.js`. These are
what didn't start the rehearsal before, minus the map, plus the website's assets, which the planner loads.

**A path on no list starts every part.** A path nobody thought of costs time, never protection.

A renamed file counts by both its names.

### The workflow
- Runs on every pull request, every night at 08:43 UTC (after the nightly backup at 07:17 UTC, which GitHub can start
  late; the run takes whatever backup is latest), and by hand (`workflow_dispatch`).
- First job, `parts` (seconds): on a pull request, `python3 database/rehearsal_parts.py --base origin/<base>`, one line
  per changed path with its parts and why, written to the run's summary; otherwise every part. Its last line,
  `parts=...`, is the job's output.
- Second job, `rehearse`, only when `parts` isn't empty, with `REHEARSE_PARTS` set from it. On a documents-only pull
  request it shows as skipped, which GitHub counts as passed.
- At night: every part, `REHEARSE_NIGHTLY=1`, so the figures moved and the backup and restore run even with nothing to
  apply; no samples; no comment (there is no pull request).
- The pull request comment and the artifacts are as before.

### Where a failed night shows
The manual's §7 rule (every job writes a `job_runs` row; Today warns when a job's last run failed) would need this
repository to hold a key that can write to the database. It holds only the R2 reader key. So, for now, a failed night
shows as GitHub's failure email, which goes to whoever last changed the workflow's schedule. Whether to give the nightly
run a `job_runs` row (a new key or secret, or a database change) is Gitesh's choice, not part of this build.

### What the checks show
- `tests/rehearsal_parts_test.py`, in `run_all.sh` (and so *Checks*): the grouping on hand-made lists of paths (a
  look-only planner change gives `types`, `planner`, `saves` and no `db`; a file under `database/` every part;
  documents nothing; `docs/architecture.md` alone nothing; a path on no list every part; a mix the union; and the other
  groups), and every file under `tests/` that the rehearsal's scripts name starts at least one part.
- The rehearsal's log starts with `== parts: ... (not run: ...)`, so a reader sees what was skipped.

### Expected minutes (the brief's)
A look-only planner change 8 to 11; a database change 20 to 31 (as before); documents none.

### Documents in the same pull request
`tests/README.md`, `docs/map/checks.md`, the map's rows (*Checks*, *What runs when*), manual §1 *Automatic checks* (the
sentence the brief quotes replaced, the nightly sentence added, the briefing and map guide named), and
`docs/rule-history.md`.

## 2. The second pull request: the slow parts side by side (to-do 235, built 12 Nov)
Built by the Main chat's worker on 12 Nov, after measuring first. Gitesh chose option E on 11 Nov; on 12 Nov he said to
start with what the Main chat thinks best.

### Measured first (minutes, from each run's log headings)
| Run | Machine | Set-up | of it, the browser | Restore | Outputs before | Database tests | of them, capture replay | of them, `briefing_test.sql` | Figures | Planner | Briefing | Saves | Backup and restore | Whole run |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 43019391073 (11 Nov, every part) | fast | 0.6 | 0.2 | 1.5 | 1.2 | 7.9 | 4.0 | 1.6 | 0.1 | 3.3 | 1.6 | 2.7 | 0.7 | 19.6 |
| 42984487997 (11 Nov, every part) | slow | 0.8 | 0.3 | 1.4 | 1.6 | 13.3 | 7.6 | 2.8 | 0.1 | 5.9 | 2.6 | 2.8 | 0.8 | 29.4 |
| 43031308564 (pull request 152, every part) | slow | 0.9 | 0.5 | 1.3 | 1.8 | 15.4 | 8.3 | 3.0 | 0.2 | 4.5 | 2.7 | 3.2 | 0.7 | 31.1 |
| 43142490246 (pull request 159, look-only) | fast | 0.7 | 0.2 | 1.3 | | | | | | 5.0 | | 2.7 | | 9.9 |
| 43128805562 (pull request 156, look-only) | slow | 0.7 | 0.3 | 1.3 | | | | | | 7.6 | | 3.3 | | 13.2 |

The seven look-only runs of pull requests 153 to 159 took 9.9 to 13.2 minutes (planner 5.0 to 7.6, the saves 2.7 to
3.3). The planner part has grown about 2 minutes since pull request 152 with the glass look's checks, so a whole run in
one job would now be about 22 to 34 minutes. Each extra job pays its own set-up and restore: 1.7 to 2.4 minutes. The
types, the descriptions and the reference file take seconds; building the planner about 10 seconds. The first nightly
run (12 Nov, 08:43 UTC) had not run when this was built.

### The jobs
`database/rehearsal_parts.py` gives the `parts` job, besides the parts, the jobs the run needs (`jobs=`, JSON); the
`rehearse` job runs one copy of itself for each (a matrix, `fail-fast: false`), each restoring its own copy:

| Job | Its parts | Its database tests | Also |
|---|---|---|---|
| the planner and the saves | types, planner, saves | none | the test browser; the backup and restore last, after the saves, when the run has the db part (as in one job) |
| the capture replay | db | `capture_data_replay_test.sql` only | no browser, no build |
| the briefing, its database test and the map's guide | briefing, db | `briefing_test.sql` only | no browser |
| the other database tests | db, reference, samples | every other test | the outputs saved before and the figures moved; the backup and restore when the planner's job doesn't run; no browser, no build |

A job starts only when the run needs one of its parts. A planner change starts one job; a database change, and every
night, all four. The planner's test and the saves stay one job: the saves import the planner's test module and run after
it on the same copy. The outputs saved before go only with the job whose tests read them (the replay and
`briefing_test.sql` don't).

`database/rehearse.sh` takes each job's share through four settings, all unset in a local run, which then runs as
before (one part or all): `REHEARSE_JOB`, `REHEARSE_DB_TESTS` (`all`, `only:` or `except:` a list of test files; a name
that isn't a file fails at once), `REHEARSE_DB_SAVED` and `REHEARSE_BACKUP`.

A last job, `result`, waits for them all (not when the run was cancelled by a newer push), reads each job's status and
log (each job uploads them, addresses taken out, as `rehearsal-result-<job>`, kept a day), and fails if any job failed,
was cancelled or left no result, or if GitHub says the jobs failed. It posts the one comment: passed or failed, the
parts run and not run, then each job with its parts and what it found (a passed job's last 12 lines; a failed one's
FAIL lines and last 40). The same goes to the run's summary. Each artifact comes from the job that makes it.

### What changes for the checks
Nothing a part checks. Two things now run that didn't: a red database test no longer stops the planner, the briefing,
the saves or the backup and restore, which run on their own copies (so a red run shows everything that's red); and the
briefing, the saves and the backup and restore run even when another job's part failed. The backup and restore still
dumps the copy after the saves when both run. No manual sentence changes: the manual says what runs, not how.

### What the checks show
`tests/rehearsal_parts_test.py`: for every one of the 127 mixes of parts, each part needed is run by a job and no job
runs a part the run doesn't need; each test in `database/tests/` is run by exactly one job, as `rehearse.sh`'s own
`test_wanted()` picks them (run in bash); the backup and restore and the figures in one job each, and the browser only
where the planner's or the saves' test runs; the planner's test and the saves in one job; `rehearse.sh` refuses a test
list it can't follow; the last job passes only when every job passed (a failed, cancelled or silent job fails it) and
says which parts weren't run; and the workflow is wired that way.

### Expected minutes (from the table)
- A look-only planner change: 10 to 14, as before (one job, the same work); the last job adds about 10 to 20 seconds.
- A database change: about 11 to 15, against 22 to 34 in one job. The planner's job sets the pace (2 to 2.4 set-up and
  restore, the planner 5 to 7.6, the saves 2.7 to 3.3, the backup and restore 0.7 to 0.9); the others finish in 5 to 11.
- The nightly run: the same as a database change, 11 to 15.

The brief's 5 to 8 and 6 to 10 assumed the planner and the saves could be two jobs; they can't.

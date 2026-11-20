# Statement lines kept 3 days, the scheduler's log trimmed to 7: 19 Nov 2026

To-do 252. Brief `docs/briefs/2026-11-18-database-growth.md`; Gitesh chose it on 19 Nov (16:34 India time): "keep
statement lines 3 days, trim the scheduler's log, then compact once" (the brief's B + D, then A once; to-do 252's
option C). Migration `20261119100000_statement_keep.sql`.

## What
1. **Statement lines kept 3 days, not 14.** A new world setting, `settings.statement_keep_days` (3), replaces the
   clean-up's fixed 14 days for statement lines. Nothing else about the statement clean-up changes: it still runs only
   while `statement_cleanup_enabled` is true. It still deletes lines only once every older line is in `game_flights` or
   `game_payments`; otherwise none goes and the run fails, saying how many aren't. With no setting (or one under 1 day),
   no line is deleted, and the note says so.
2. **The scheduler's log trimmed to 7 days.** The same 10:20 UTC job deletes `cron.job_run_details` rows older than
   `settings.cron_log_keep_days` (7). A row still running counts by its start time. This runs once a run, in the
   default world's row, because the log belongs to the database, not to a world. It runs in a block of its own, so a
   failure fails the run, says why, and undoes only this delete. With no setting, nothing is deleted.
3. **Each cut is reported on its own.** The `job_runs` row keeps `before` as the raw pages' cut (now less 14 days). It
   adds `statement_before` and `statement_keep_days`, plus `cron_log_before`, `cron_log_keep_days` and
   `cron_log_deleted` in the default world's row. The note gives the days used for each part.
4. **The archive's guard names the setting.** When statement lines still point at a month's flights,
   `private.archive_delete()`'s refusal now says the clean-up removes them "once older than
   settings.statement_keep_days, N days" instead of "after 14 days".
5. The descriptions of `job_cleanup()`, `archive_delete()`, `game_statement` and `statement_cleanup_enabled` are
   updated to match.

Unchanged: raw pages are kept 14 days, the world scans' clean-up and its `scan_keep_days`, the archive, and the job's
time (10:20 UTC).

## Why
The database is 246.8 MB (amber 245, trigger 350, manual §1). `game_statement`'s primary-key index is 30.4 MB against
an 18 MB table of about 110,000 lines, and it grew 1.9 MB in a day. About 10,300 lines arrive a day. With 3 days the
table holds about 31,000 lines instead of about 144,000. `cron.job_run_details` has 11,757 rows, grows about 1,470 a
day (the figures job runs every minute), and nothing trims it. On the brief's model, this plus one `VACUUM FULL` keeps
the database at about 250 MB on 31 Dec and about 310 MB on 31 Mar.

What Gitesh gives up: statement lines older than 3 days leave the database. Each line's money is already in
`game_flights` or `game_payments` before it is deleted. The raw pages keep 14 days and the nightly backups 30. A
flight's money can be re-linked from the table for 3 days only.

## Who reads `game_statement`, and why 3 days is safe
Every reader in `database/current/functions.sql`, plus `app/`, `scripts/`, `lib/`, `web/` and the views (none of
these last read it):
- **`private.capture_page()`**: inserts the page's lines, with an on-conflict on the primary key. A statement page
  lists the game's last 24 hours (the 13 Oct sample: 03:15 to 02:10 the next day), so it never meets a line older
  than 3 days.
- **`private.fold_statement()`** and **`private.statement_blocks()`**: read only the minutes on the page being folded
  (`ts = any (p_minutes)`), just after the page's own lines were written.
- **`private.fig_cabin_charges()`**: each airline's latest line as of the moment. It needs one line no older than the
  last capture. With captures twice a day, that line is under a day old. If no statement were captured for more than
  3 days, the latest line would be gone, and a first cabin fit with no charge would read "waiting" instead of "not
  charged yet" until the next capture. Under 14 days the same happened after 14 days. It is a softer answer, never a
  wrong charge.
- **`private.job_cleanup()`**: counts and deletes old lines.
- **`private.archive_delete()`**: refuses a month that lines still point at. It never reads the lines' contents.
- **The capture's statement check** (the median of recent nights) reads `game_capture_raw`, not this table.
- **Tests:** `capture_data_replay_test.sql` compares lines from the clean-up's last cut. It reads that cut from
  `details.statement_before` now (below).

## The first run
The first run after the merge (10:20 UTC) deletes about 11 days of lines at once, roughly 80,000 rows. It is one
`delete` statement, as before; nothing is split across runs. Why that is safe:
- Locally, on 201,600 lines (about twice live), the whole job deleted 158,400 lines in 0.8 seconds, the count first
  included.
- The `delete` uses the same indexes as every night's run: the primary key for the time range, and `game_payments`'
  unique key for the payment check.
- Supabase's free plan is slower than this machine, but even 50 times slower is under a minute. A scheduled job may
  run for up to 2 minutes, and a function's own `statement_timeout` does not hold inside `pg_cron`.
- The 6 Nov switch-on run deleted 71,482 lines in one statement, on the same job, without trouble.
- If it did fail, the run's own block undoes it, the run is marked failed, and nothing is half-deleted.

## Files
- `database/migrations/20261119100000_statement_keep.sql`: the two settings, `job_cleanup()`, `archive_delete()`, the
  descriptions.
- `database/tests/statement_keep_test.sql` (new); `jobs_test.sql` §4 reads the setting and checks the two cuts;
  `capture_data_replay_test.sql` reads `statement_before`; `rules_input_test.sql` lists the two new settings.
- `docs/operating-manual.md` §7 (the clean-ups), `docs/rule-history.md`, `docs/architecture.md` (one line),
  `docs/map/database.md`, `tests/README.md`, `database/current/functions.sql`, `docs/data.md`, and the brief's
  Outcome.

## What the checks show
- `statement_keep_test.sql`, in a world of its own with hand-made rows, runs the job as if at 10:20 UTC on each of the
  next seven days (every weekday once). Each time:
  - Raw pages 15 days old go; 13 days old stay.
  - Lines 4 days old go, both a flight's and a payment's. A line exactly 3 days old and younger ones stay.
    `game_flights` and `game_payments` are untouched.
  - The details give the statement's cut (now less 3 days) apart from the raw pages' (now less 14).
  - A line older than 3 days that is in neither table makes the run fail, and none goes.
  - Without the setting, none goes.
  - With 1 day, the younger lines go too.

  The scheduler's log part checks:
  - Rows older than 7 days go, a running row by its start, and a row 6 days old stays.
  - The count is in the default world's row only.
  - Without the setting, none goes.
  - postgres, which runs `equinox-cleanup`, may delete from `cron.job_run_details`. The rehearsal checks this on
    Supabase's own local copy.

  The test counts only the rows it adds, and it switches off the default world's statement part for that run. So
  nothing depends on the backup, the date or the weekday.
- The replay on a copy where the 3-day clean-up has already run: six evenings of statement pages, then the clean-up
  (1,390 lines older than 3 days deleted). The replay as on main compares from the raw pages' cut and fails with 945
  lines. The replay reading `statement_before` compares from the 3-day cut and passes. With 14 days it passes as
  before.
- Every database test, with and without the migration, on the same local copy gives the same results except
  `statement_keep_test.sql` (new) and `rules_input_test.sql`. Without the migration, `rules_input_test.sql` stops at the
  new settings it now lists; with the migration it passes those and stops at the same local data gap as the other
  failing tests. Those failures are local only: they need a real backup.

## What stays out
- The `VACUUM FULL` (the brief's A). Gitesh or the Building chat runs it once, after the first 3-day run. The steps
  are in the pull request.
- Raw pages' 14 days, the scans' keep, the archive, the statement's primary key (the brief's C), the report PDFs (E),
  and a mid-month archive (H).
- `history_snapshot_test.sql` replays salaries pages through `capture_store()` (pull request 168). It is left as it is.
- A daily row of table sizes in `job_runs` (the brief's suggestion).

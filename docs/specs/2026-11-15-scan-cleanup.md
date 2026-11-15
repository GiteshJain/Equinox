# Spec: the nightly clean-up of the world scans' connections and summaries

To-do 240. Gitesh, 15 Nov, Main chat: option C of `docs/briefs/2026-11-15-scan-connections-growth.md`. One small pull
request: a migration, its test, the documents. No planner change.

## What it does, in one paragraph
Every scan is kept in full for 14 days. After that its connection detail goes, and its two summary tables keep rows
only if it is the week's kept scan. The 10:20 UTC clean-ups do it, every night, with the raw pages and the statement
lines: the same job, the same `job_runs` row and the same line on the Systems board. The latest finished scan is never
touched, however old it is.

## Why
Each evening's scan adds about 3 MB to these three tables. The database is 218 MB, and 350 MB brings the paid-plan
brief (manual §1). Nothing reads these tables' history beyond the latest scan and the week-before scan (the brief lists
every reader, with its function). With this, the brief's model keeps the database under 350 MB through March.

## Which rows go and which stay
The 14 days are `settings.scan_keep_days` (14, unit days, one row per world; manual §1, rule numbers have one source).
A scan is "older" when it was taken more than 14 days before the run. **The latest finished scan of the world
(`status` done) and every scan taken at or after it are never older**, whatever their age.

| Table | A scan younger than 14 days, the latest finished scan, or any scan after it | An older scan that is the week's kept scan | Any other older scan |
|---|---|---|---|
| `scan_rival_connections` (the connection detail) | stays | **goes** | **goes** |
| `scan_rival_connections_week` | stays | stays, for good | **goes** |
| `scan_airline_airports` | stays | stays, for good | **goes** |

**The week's kept scan** is the first finished scan on or after each Saturday
(`docs/briefs/2026-10-23-rival-pairs-history.md`). A scan counts as kept when it has rows in `scan_pair_airlines` (which
keeps exactly those) **or** it is the first finished scan of its week (`private.scan_week()`). The second test catches
a week whose pair rows were never written; on live today the two give the same scans (3, 4, 9, 16, 21 and 26).

Nothing else is touched: not `game_scans`, `scan_pair_airlines`, `game_scan_schedules`, `scan_airline_markets`, the
fleet tables or anything outside the world scans.

- **Safe to run again:** it deletes only what is due, so a second run deletes nothing.
- **Safe when a night is missed:** the next run deletes everything due by then.
- **Without the setting row** the scan part deletes nothing and its note says so.
- **Deleted space is reused, not given back.** A one-off `VACUUM FULL` to bring the size down is a later offer to
  Gitesh, not part of this build.

## How it is built
- `database/migrations/20261115140000_scan_cleanup.sql`:
  1. the setting `scan_keep_days` (14) in every world, with its description and reason;
  2. `private.scan_cleanup(world, at)`: the three deletes, and their counts (postgres only, empty search path);
  3. `private.job_cleanup()`: runs `private.scan_cleanup()` for each world, in a block of its own. If the scan part
     fails, the run is marked failed with the error, the scan deletes are undone, and the raw pages and statement lines
     are still cleaned. The counts go in the note and the details;
  4. `private.fig_route_story()`: the route page's hidden per-scan list (`connecting_scans`) reads only scans that still
     have their connection detail. Without this, a week's kept scan older than 14 days (its by-week rows kept, its
     detail gone) would show as zero connections. Every figure for now is unchanged, since the latest scan is never
     cleaned. Its note text is left as it is;
  5. new descriptions for the three tables, the two changed functions and the new one.
- No new scheduled job: `private.schedule_jobs()` and `database/tests/jobs_test.sql`'s list are unchanged.
- Nothing is dropped or renamed, so the migration applies from the chat (manual §1). The deletes run inside the job,
  as the existing clean-ups' do.
- `database/current/functions.sql`, `docs/data.md`.

**The monthly archive's list.** `scan_rival_connections` stays on `private.archive_tables()`. Once the clean-up runs,
the table holds nothing older than 14 days except the latest scan, so the archive finds nothing due and does nothing.
Taking it off would mean changing the archive's functions (its list, what is due, its order and its month rule) and
its tests, all for no saving. One side effect is kept as it is: if scans stopped for over a full calendar month, the archive would export and
delete the latest scan's connections. It already does that today, and it does the same to that scan's schedules,
which competition reads. See *Outside the spec*.

The October rows the archive would have exported on 1 Dec (96,881) are deleted by the clean-up first, so they never
reach R2. That is option C as chosen: "no connection detail" after 14 days. The brief's "easy to undo" column says the
same: the rows can be worked out again from the schedules while those exist.

## What the Systems board and `job_runs` show
One `job_runs` row per world a night, as before (job `cleanup`). The note gets a third part, for example:

> raw pages: 30 deleted (older than 14 days); statement lines: 5210 deleted (older than 14 days; 5100 in game_flights,
> 110 in game_payments); world scans older than 14 days: 11164 connection, 5692 by-week and 4026 airport rows deleted
> (the weeks' kept scans keep their summaries)

That is under the board's 300 characters even with six-figure counts. The details add `scan_enabled`,
`scan_keep_days`, `scan_before` (the cut-off), `scan_kept` (the kept scans among the older ones),
`scan_connections_deleted`, `scan_week_deleted` and `scan_airports_deleted`. A failure reads
"…; world scans: failed, nothing deleted: <error>" and the run is red on the board and on Today, as any failed
clean-up already is. The planner is unchanged: the board shows the note as it is.

## The first night (from a SELECT on live, 14 Nov 22:03 UTC)
| Table | Rows today | Deleted on the first night, run 15 Nov 10:20 UTC | Run 16 Nov 10:20 UTC |
|---|---|---|---|
| `scan_rival_connections` | 201,322 | 106,480 (scans 3 to 16) | 106,480 |
| `scan_rival_connections_week` | 106,675 | 41,152 | 41,152 |
| `scan_airline_airports` | 84,396 | 31,655 | 35,521 (scan 17 too) |

After that, about one scan's worth goes each night (about 11,000, 5,600 and 4,000 rows), except on a week's kept scan,
where only its connection detail goes.

## What the checks should show
- `database/tests/scan_cleanup_test.sql` (new), on the copy of last night's backup:
  1. the setting in every world; the new function closed and described;
  2. on the copy, before and after the clean-up at now: `competition()` for each of our airlines, `hub_progress()`,
     the Systems board's scan line, the scan's airport list (`capture_scan_plan()`) and `route_story()` for six flown
     routes are the same. The one difference allowed is `connecting_scans`, which loses exactly the scans whose detail
     went. Then no connection detail is left older than 14 days except the latest scan's, and the summaries are left
     only for kept scans;
  3. a world of its own: each row of the table above, a stopped scan, a second run, a missed night, a world without
     the setting, and the latest finished scan 35 days old kept whole;
  4. the job's note and details, and a failing scan part (a trigger made in the test) failing the run, keeping the scan
     rows and still deleting raw pages.
- `jobs_test.sql` unchanged and passing (the job list and the statement clean-up's checks).
- The figures moved: none (the migration deletes nothing; the clean-up runs only in the job).

## Outside the spec
- The monthly archive would take the latest scan's connection detail, and its schedules, if scans stopped for over a
  full calendar month. That is today's behaviour, not changed here.
- Manual §7's list of what the archive takes ("each flight, payments ahead, world-scan schedules and airport pages")
  leaves out the connection detail, which it does take (noted in the brief). The sentence is left as it is.
- `route_story()`'s note on connecting still says "each scan read that has them worked out". It is still true in effect
  and was not reworded, so no stored answer moves.
- A one-off `VACUUM FULL` of the three tables, to give the space back, is a later offer to Gitesh.
- `docs/map/database.md`'s function counts (54 and 144) were already out of date, and are left as they are.

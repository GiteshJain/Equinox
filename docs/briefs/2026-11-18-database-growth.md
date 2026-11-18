# Database growth: where the 6 MB a day goes, and what to do before 350 MB — 18 Nov 2026

**Decision:** what to do about the database growing about 6 MB a day on Supabase's free plan (350 MB trigger, amber
245 MB; manual §1 and §7), now that the 15 Nov estimate ("under 350 MB through March") has turned out wrong.
**Recommendation (a recommendation, Gitesh decides):** B + D, then A once. Keep statement lines 3 days instead of 14
(nothing reads older lines; the raw pages and the backups still hold them), trim the scheduler's own log to 7 days, and
then run one `VACUUM FULL` to hand back the space. On this estimate that keeps the database at about 250 MB on 31 Dec
and about 310 MB on 31 Mar, with no money spent. Leaving it as it is reaches 350 MB between 11 Dec and 22 Jan
(central estimate 25 Dec).

| Option | What it gives | MB freed once | MB a day saved | Cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. One `VACUUM FULL` of `game_statement`, `game_flights` and the three scan tables | Hands back space that deleted and rewritten rows left behind | about 40 (estimate) | 0: buys about 2 to 3 weeks, then growth goes on | None. Gitesh or the Building chat runs it once in the SQL editor | Each table is locked for seconds while it is rewritten; a capture or a figures run waits. No data deleted | Nothing to undo |
| **B. Statement lines kept 3 days, not 14** (with A after the first clean-up) | Stops `game_statement` growing: about 31,000 lines instead of about 144,000 | about 60 with A (estimate) | about 1 to 3.4 (the statement's whole growth) | Small build: the clean-up's 14 days for statement lines becomes a setting; manual §7 and `rule-history.md` | Lines are only deleted once each is in `game_flights` or `game_payments` (unchanged). Lost: the chance to re-fold a line 4 to 14 days old from the table. Raw pages (14 days) and nightly backups (30 days) still hold them | Yes: set it back to 14 days; old lines come back only from raw pages or a backup |
| C. Slim `game_statement_pkey` (a short hash instead of the text key) or drop indexes little used | Smaller statement index; drops `game_statement_world_ts_idx` (158 reads) and `game_flights_world_dep_idx` (249 reads) | about 4 for the two indexes; the key change is unproven | about 0.1 to 0.2 | Medium build, with capture tests; the key is what the capture uses to spot repeated lines | Medium: a mistake makes the capture keep repeated lines | Partly: an index can be rebuilt; the key change needs its own rollback |
| **D. Trim `cron.job_run_details` to 7 days** | The scheduler's log stops growing (1,470 rows a day since the figures job started on 11 Nov; nothing trims it) | about 1.4 | about 0.2 | Small build: a daily delete in the clean-up job, a test | Low: `job_runs` is our own record; the cron log is only for debugging | Yes |
| E. Move the report PDFs out (#16, deferred) | `site_reports` out of the database | 3.8 | about 0.07 (one PDF a week) | Medium build (the rest of #16) | Low | Yes |
| H. Monthly archive also runs mid-month (keeps about 2 to 6 weeks of flight and world-scan detail, not 4 to 8) | Lowers the peak of `game_flights` and `game_scan_schedules` | 0 | about 0.4 on average | Medium build: archive functions, tests, manual §7 | Readers of flight detail older than 2 weeks lose it; `route_days` still holds the daily history | Yes, the rows are in R2 |
| F. Paid plan | 8 GB; the problem goes away | — | — | $25 a month, over the $10 limit | None technical | Yes, month to month |
| G. Leave it | Nothing | 0 | 0 | None until the trigger | 350 MB between 11 Dec and 22 Jan (central 25 Dec), then the paid-plan brief | — |

Every figure marked "estimate" is worked out from row counts and widths, not measured; see "What reads alone can't
show" below. The one-off and the daily figures don't add up across options: B removes most of what A would hand back
from the statement table.

## Background
Measured 18 Nov, about 13:47 UTC (19:17 India time), read-only `select` statements on the live database. Each figure's
query is given so the Main chat can check it.

### Where the 6 MB a day goes
The database went from 218 MB (15 Nov 02:00 India) to 242.3 MB (now): 24.3 MB in 3.7 days, **6.6 MB a day**
(`select pg_database_size(current_database())/1048576.0`). The three scan tables grew 2.8 MB of that, all before their
clean-up first ran on 15 Nov 10:20 UTC; they are flat since. The rest grew **about 5.8 MB a day**.

| Table | MB now | MB a day now | Real data or space not reused |
|---|---|---|---|
| `game_statement` | 53.9 (table 18.3, indexes 35.5, of which the primary key 28.5) | about 3.4 | Mostly not reused. The primary key grew from 21 MB (15 Nov brief) to 28.5 MB, about 2.1 MB a day, while live lines grew only about 2,300 a day (about 0.3 MB of real data). Real rows stop growing about 24 Nov (below) |
| `game_flights` | 26.0 (table 9.7, nine indexes 16.3) | about 1.0 | Real: 1,130 flights a day, kept until the archive takes them, so it holds 1 to 2 months (about 60 MB at each month's end from January) |
| `game_scan_schedules` + `game_scan_airports` | 12.8 | about 0.5 | Real: one scan a night, about 0.47 MB each, also archived after a full month, so they peak at about 29 MB |
| `change_log`, `route_days`, `site_reports`, `cron.job_run_details`, balances, P&L, events, fleet, markets | about 25 together | about 0.6 together | Real. The cron log is 0.2 MB a day of it and is never trimmed |
| `game_capture_raw` | 12.2 (8.0 of it the stored pages) | 0 | Flat: 14 days of pages in, 14 days out (about 0.7 MB a day each way) |
| `planner_figures` | 6.0 | 0 | Flat: the same 507 answers rewritten each run; space reused |
| The three scan tables | 58.6 | 0 since 15 Nov | About 15 to 20 MB of their files is space freed by the clean-up, reused as new scans come in |
| Outside `public` (`pg_catalog` 14.8, `cron` 1.7, `auth` 1.5, `net` 0.5, `supabase_migrations` 0.5, `storage` 0.5, `information_schema` 0.2) | 19.8 | about 0.2 (the cron log) | The "2 MB grew outside public" of the morning reading is most likely a counting difference: 17.9 MB is exactly `pg_catalog` + `cron` + `auth`, and the four small schemas add 1.8 MB |

Sources:
- Table, index and toast sizes: `pg_relation_size`, `pg_indexes_size` and `pg_total_relation_size` over `pg_class` for
  every relation over 1 MB in every schema; per schema, `sum(pg_total_relation_size(oid))` over tables grouped by
  namespace (242.55 MB in all against `pg_database_size` 242.30). The toast tables are `game_capture_raw` 8.0,
  `game_scan_schedules` 7.0, `planner_figures` 5.7 and `site_reports` 3.7.
- Lines and flights a day: `select (captured_at at time zone 'UTC')::date, count(*) from public.game_statement group by 1`
  (10,038 to 10,667 a day from 9 Nov; 13,382 on 11 Nov, a re-capture) and the same on `game_flights.created_at` and
  `coalesce(posted_at, dep_at)` (1,130 a day from 11 to 17 Nov, the same every day: the flight count has not grown
  since 11 Nov).
- Lines deleted a day: `job_runs` notes for `job = 'cleanup'`: 7,119 (15 Nov), 7,833, 8,046, 8,890 (18 Nov). 71,482 on
  6 Nov, the first run after it was switched on.
- Dead rows and vacuum: `pg_stat_all_tables`. `game_statement` 106,497 live, 0 dead, autovacuum 18 Nov 10:20 (right
  after the clean-up), 70 autovacuums; `game_flights` 29,768 live, 2,420 dead, autovacuum 18 Nov 09:32; the three scan
  tables 19,563 / 5,169 / 3,940 dead, autovacuum 16 and 17 Nov. Autovacuum is keeping up; dead rows are not the problem.
- Updates: `game_statement` has had 1,202,064 updates since the stats reset (25 Aug), only 12,678 of them in place
  ("HOT"). Before 11 Nov every line of every page was rewritten (spec `2026-11-11-statement-no-rewrite.md`). Each
  update that isn't in place adds an entry to every index; that is the likeliest origin of the primary key's size.
  Since 11 Nov a new line is still written twice: inserted, then given its `flight_id`, which is indexed, so that
  second write is not in place either (`private.fold_statement()` step 4).
- Average row width (`avg(pg_column_size(t.*))`): statement 138 bytes, flights 293, connections 68, connections by
  week 122, airport summaries 60, route days 124.
- Index use (`pg_stat_all_indexes`): `game_statement_pkey` 736,680 reads (the capture's repeat check),
  `game_statement_world_ts_idx` 158, `game_flights_world_dep_idx` 249, `route_days_world_day_idx` 170.
- The scheduler: `cron.job_run_details` 10,454 rows since 11 Oct, 1,446 to 1,470 a day since 12 Nov (the figures job
  every minute), 1.7 MB; no job trims it (`select * from cron.job`). `net._http_response` holds 7 rows (pg_net trims it
  itself). `job_runs` is under 0.2 MB.
- What the archive takes: `select * from private.archive_tables()`: `game_flights`, `game_events`,
  `game_scan_schedules`, `game_scan_airports`, `scan_rival_connections`, the three market tables (1 month each) and
  `change_log` (12 months). Not `game_statement` (the clean-up's) and not `cron.job_run_details`.

### Bloat, estimated (live rows × width, against the file)
An estimate: it ignores page headers, fill factor and alignment, so take it to within a few MB.
- `game_statement` table: 106,497 × (138 + 4) = 15.1 MB of rows in an 18.3 MB file, about 3 MB free.
- `game_statement_pkey`: about 76 bytes an entry (airline 13, ts 8, descr 29, amount, occ, entry header) × 106,497 =
  8 MB, about 9 MB when packed as a b-tree packs. The file is 28.5 MB: **about 19 MB not used by live entries.** The
  other three statement indexes (2.2 to 2.5 MB) look normal.
- `game_flights` indexes: nine of 0.3 to 2.7 MB for 29,768 rows, about 80 bytes an entry on keys of 20 to 30 bytes:
  roughly 6 to 8 MB not used. The table itself (9.7 MB for 8.8 MB of rows) is normal.
- The three scan tables: 120,069 × 72 = 8.6 MB of rows in 14.7; 78,184 × 126 = 9.9 in 13.3; 53,416 × 64 = 3.4 in 5.5,
  about 12 MB in the tables and a few more in their indexes: the Main chat's 20 MB is about right.

### What the 15 Nov model got wrong
1. **It treated `game_statement` as capped** (about 62 MB, the Main chat's figure) and as data. It is 53.9 MB and
   growing about 3.4 MB a day, two thirds of it in the primary key, faster than its rows.
2. **It took "keep one month" as one month.** The archive deletes a month only once a full calendar month has passed,
   so `game_flights` and the scan schedules hold one to two months: their peak is about twice what the model assumed.
   `game_flights` also grows about 1.0 MB a day (1,130 flights with nine indexes), not 0.56.
3. **It held everything else flat**: the scan schedules and airport pages (0.5 MB a day), the cron log (0.2), the change
   log, route days and reports. Together about 1.3 MB a day.
4. It noted that the database grew 59 MB between 10 and 15 Nov and that the model explained well under that, but went
   ahead. The gap was the statement and flights tables.

### Who reads statement lines, and how far back
From `database/current/functions.sql`: `private.capture_page()` and `private.fold_statement()` read only the minutes on
the page being captured (the last 24 hours). `private.fig_cabin_charges()` reads each airline's latest line. The
clean-up and the archive guard (`private.archive_delete()`, which refuses to archive a flight a line still points at)
read old lines only to delete or check them. The capture's statement check (the median of recent nights) reads
`game_capture_raw`, 7 nights, not `game_statement`. Nothing in `app/` or `scripts/` reads the table. So a 3-day keep
loses nothing any screen, report or job reads today.

## Scenarios and the risk of waiting
The model: `game_flights` at 1,130 flights a day and 0.87 MB per 1,000 rows, growing only past its earlier peak (deleted
space is reused, not given back), archive on each 1st; scan schedules and airports the same at 0.47 MB a night; the
small tables 0.6 MB a day; the three scan tables flat to 31 Dec, then 0.2 MB a day. `game_statement` grows 3.4 MB a day
until about 24 Nov, when its 14-day window fills (lines from 10 Nov on are 10,100 to 10,300 a day; 6 and 7 Nov have
none, so deletes reach today's insert rate on 24 Nov), and then by one of three cases: flat, 1.0 MB a day (central),
or 3.4 MB a day (its primary key never reuses space). Start 242.3 MB on 18 Nov.

| Scenario | 31 Dec | 31 Mar | Passes 350 MB |
|---|---|---|---|
| G, statement flat after 24 Nov | 333 | 412 | 22 Jan |
| **G, central** | **370** | **539** | **25 Dec** |
| G, statement keeps 3.4 a day | 458 | 844 | 11 Dec |
| A alone, central | 330 | 499 | 12 Jan |
| A alone, statement flat | 293 | 372 | 4 Mar |
| D alone, central | 361 | 512 | 28 Dec |
| H alone, central | 346 | 516 | 3 Jan |
| B with A (60 freed) | 256 | 335 | not by 31 Mar |
| **B + D with A** | **247** | **308** | **not by 31 Mar** |
| B + D + H with A | 224 | 285 | not by 31 Mar |

Arithmetic to check:
- **G central, 31 Dec:** 242.3 + statement 3.4 × 6 (to 24 Nov) + 1.0 × 37 = 57.4; flights 1,130 × 12 days to 30 Nov =
  13,560 rows × 0.87 = 11.8, then flat to 14 Dec (October's 14,744 rows freed on 1 Dec), then 17 days × 1,130 × 0.87
  = 16.7; scan schedules 0.47 × 12 = 5.6, then about 10.2 after 10 Dec; small 0.6 × 43 = 25.8. Total 242.3 + 20.4 + 37
  + 11.8 + 16.7 + 5.6 + 10.2 + 25.8 = **about 370**.
- **G, statement keeps 3.4 a day:** the same with 3.4 × 43 = 146 for the statement: about 458.
- **B + D with A, 31 Dec:** 242.3 − 60 + statement 3.4 (one day before the first 3-day clean-up) + flights 28.5 +
  scans 15.8 + small (0.6 − 0.2) × 43 = 17.2: **about 247**.

Risk of waiting:
- **Amber (245 MB) comes tomorrow, 19 Nov**, under every option, unless A runs first.
- **Each day costs about 6 MB** today; about 3.4 of it stops on its own only if the statement's primary key reuses
  space once rows stop growing (24 Nov), which reads can't show yet. Checking it after 24 Nov (below) settles which
  row of the table above is true.
- On 1 Dec October's flights and scan pages leave (archive): growth pauses for about two weeks, then goes on. The
  pause is not a fix.

## What would change the recommendation
- **If the primary key stops growing after 24 Nov** (the "flat" case), A alone holds to about 4 Mar, and B becomes a
  saving rather than a need.
- **If it keeps growing at 2 MB a day with flat rows**, the cause is in how the capture writes the table, not in how
  long it is kept: B still caps it (fewer rows, smaller index), and C (the key change, or leaving `flight_id`
  unindexed so its write stays in place) becomes worth its own review.
- **If the fleet's daily flights grow again** (1,130 has been flat since 11 Nov), `game_flights` and the statement
  grow with them: about +0.9 MB a day for each 1,000 more flights. H then matters more.
- **If Gitesh wants statement lines for 14 days** for reasons not in the code (checking by hand), keep 14 and choose A
  + D + H: about 330 on 31 Dec on the central case, and a new brief in January.
- **Rule changes:** B changes manual §7 ("Statement lines older than 14 days are deleted"), H changes §7's archive
  window; each with `rule-history.md`. A and D change no rule.

## How to run A, if chosen
Gitesh, or the Building chat once he says so, in Supabase's SQL editor, between 11:00 and 20:00
UTC, after the 10:20 clean-up and well clear of the 09:30 and 21:30 captures, and not while Gitesh presses the capture:
`vacuum full public.game_statement; vacuum full public.game_flights; vacuum full public.scan_rival_connections;
vacuum full public.scan_rival_connections_week; vacuum full public.scan_airline_airports;`. Each takes an exclusive lock
while it rewrites the table and its indexes; at these sizes (under 60 MB each) that should be seconds, under a minute in
all (an estimate). The figures job (every minute) reads these tables and will wait or fail one run; the next minute's
run catches up. A gentler variant for the statement table alone: `reindex index concurrently
public.game_statement_pkey;` frees the index's share (about 19 MB, estimated) without blocking writes. If B is chosen,
run A after the first 3-day clean-up, so it hands back the larger space.

## What reads alone can't show
- **Exact free space** in each table and index: `pgstattuple` / `pgstatindex` would give it, but the extension isn't
  installed (`pg_extension` lists plpgsql, pg_stat_statements, uuid-ossp, pgcrypto, supabase_vault, pg_cron, pg_net).
  Installing it is a change; a step for Gitesh or the Main chat if the estimates above need firming up.
- **What `VACUUM FULL` actually hands back, and how long it locks:** only running it shows.
- **Whether the primary key reuses space at steady state:** read `select pg_relation_size('public.game_statement_pkey')/1048576.0,
  count(*) from public.game_statement` each morning from 24 Nov. Flat MB with flat rows means the central or flat case;
  2 MB a day more means the high case.
- **Per-table sizes before today:** no job records them. A daily row of table sizes in `job_runs` (from the snapshot
  or the clean-up) would make the next review exact. Not an option here, a suggestion.

## Also found (not options)
- The nightly database rehearsal has failed on 15, 16 and 17 Nov, all on the same commit `a15e074` (`job_runs`,
  job `rehearsal`). Outside this job; there is a 15 Nov brief on it (`2026-11-15-nightly-rehearsal-failure.md`).

## Outcome
<Gitesh's decision and the date; rule changes made in the manual>

# Slowing the world scan's growth: rivals' connections and scan summaries — 15 Nov 2026

**Decision:** how much of each evening's world-scan results to keep in the database: `scan_rival_connections`, `scan_rival_connections_week` and `scan_airline_airports`.
**Recommendation:** C. Keep every scan's rows for 14 days. After that, keep only the week's kept scan for the two summary tables, and no connection detail. No screen, report or job reads anything older today, and the database stays under 350 MB through March on this estimate.

| Option | These 3 tables: MB a month, Feb to Mar | Database on 15 Dec / 15 Jan (rough) | What a screen or report loses | Build | Deletes data? | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Leave as is; take the 350 MB brief when it comes | +87 | 337 / 433. Passes 350 MB about 19 Dec | Nothing | None | No new deletes | Nothing to undo |
| B. The monthly archive also thins the two summary tables to the week's kept scan (old rows exported to R2, then deleted) | +34 (saves about 53) | 326 / 391. Passes 350 MB about 22 Dec | Nothing | Medium: migration to the archive's five functions and its guarded delete, archive and connection tests, manual §7 and data docs | Yes, on each 1st, through the archive (copied to R2 first) | Yes: the rows are in R2 and can be loaded back |
| **C. Nightly clean-up: everything kept 14 days; after that, connection detail none, and the two summary tables only the week's kept scan** | **+19 (saves about 68)** | **262 / 276. Not at 350 MB by mid-March** | Nothing. The route page's hidden per-scan connection list (`connecting_scans`) covers 14 days, not 1 to 2 months | Medium: a clean-up function and a `pg_cron` job with a `job_runs` row and a line on the Systems board, a test, manual §7 and data docs | Yes, every night. The first night drops about two thirds of today's connection rows and about half of the summary rows | Partly: rows can be worked out again from the scan schedules while they exist (one month in the database, then in the R2 archive), but with today's route list and settings |
| D. Store less: for every scan except the latest, keep connection rows (both tables) only on pairs we fly; summaries unchanged | +20 (saves about 67) | 274 / 294. Not at 350 MB by mid-March | Nothing today. Openings' connections are only ever read from the latest scan | Small to medium: change `private.scan_connections()`, a one-off thinning, a test that competition answers stay the same | Yes, about 87% of each older scan's connection rows | Partly, as C |

The money columns of the standard format don't apply: no option costs money until the 350 MB trigger. The paid plan is $25 a month (manual §1).

## Who reads these tables, and how far back
From `database/current/functions.sql`. The planner always asks for "now" (`asOf()` in `app/planner/src/screens/*/reads.ts`). The scripts never read these tables directly: they go through `export_for_report('figures')`, which also asks for now.

**`scan_rival_connections`** (26.6 MB, 201,322 rows)
- `private.fig_competition()`: the latest scan only (`cx`, `where c.scan_id = v_conn_scan`). Used by Competition, Today's rival moves, the weekly report and the briefing.
- `private.fig_route_story()` (`cn`): the latest scan and the week-before scan, plus every scan since the route launched that still has its schedules. The route page shows only the latest scan's figures (`rivalLines()` in `app/planner/src/screens/performance/model.ts`). The per-scan list `connecting_scans` is typed in `model.ts` line 1023 but no screen shows it.
- It is **already in the monthly archive** (`private.archive_tables()`, keep 1 month; migration `20261023140000_rival_connections.sql` §5). So the Main chat's first reading, that nothing deletes it (to-do 238), was wrong for this table. On 1 Dec, October's 96,881 rows go (`select * from private.archive_due(date '2026-12-01')`). Even so, the table holds one to two months of scans, so it peaks at about 90 to 100 MB at each month's end by January.

**`scan_rival_connections_week`** (19.5 MB, 106,675 rows; kept for good)
- Its figures are read by nothing. Only `private.scan_connections()` reads them, while writing the same scan's note.
- `fig_competition()` (line 4357) and `fig_route_story()` (`cs`, line 7655) only check that rows exist for a scan, as a mark that its connections were worked out. They check the latest scan and the scans the route page reads.

**`scan_airline_airports`** (9.7 MB, 84,396 rows; kept for good)
- Every reader uses the latest scan only:
  - `public.system_status()`: the scan line.
  - `private.capture_scan_plan()`: the 20 busiest airports.
  - `fig_competition()`'s `bt`: hubs first.
  - `private.fig_hub_progress()`: the top rival at each base.
  - `private.scan_order_flags()`: called with the latest scan.
- Its older history is read by nothing.

**Checked in the database.** No reader asks for an older moment. `planner_figures` stores answers already worked out, so it never needs old rows again. Index use (`pg_stat_all_indexes`) can't show which scans are read, so this rests on the code above.

## Background
- **Sizes**: measured 15 Nov, about 02:30 India time, with `pg_total_relation_size` on public tables. Database 218 MB. `scan_rival_connections` 26.6 MB, `scan_rival_connections_week` 19.5 MB, `scan_airline_airports` 9.7 MB, `scan_pair_airlines` 4.3 MB.
- **Size of one scan**, from table size ÷ live rows: connections about 138 bytes a row, connections by week about 192, airport summaries about 121. Scan 26 (14 Nov) has 11,164 + 5,692 + 4,026 rows, about **1.48 + 1.04 + 0.46 = 3.0 MB**. Row counts per scan come from `game_scans` joined to each table.
- **Rows per scan keep rising.** Connections went from 5,347 (6 Oct, scan 3) to 9,599 (1 Nov) to 11,164 (14 Nov). The model assumes about +100 a day for connections, +45 for the week table and +10 for airports.
- **87% of the connection rows are on pairs we only have listed, not on pairs we fly.** Scan 26 has 1,406 of 11,164 connection rows on the 419 flown pairs; the routes list has 6,498 pairs. In the week table it is 749 of 5,692 (13%). Those listed pairs feed Competition's openings, from the latest scan only.
- **The model**: the review worker's own script, not kept. It assumes one scan an evening (`settings.scan_every_days` = 1). Deleted space is reused but not given back, so a table's file stays at its highest size. Options C and D start on 20 Nov.
- **The rest of the database is a rough guess.** It is 162 MB today. The guess adds `game_statement` growing to about 62 MB (Main chat's figure), `game_flights` at about 0.56 MB a day (22.5 MB over 6 Oct to 14 Nov) until the archive caps it, and everything else flat. The database grew 59 MB between 10 and 15 Nov, and this model accounts for well under that. If the rest keeps growing faster, every date here comes sooner.
- **The model to copy**: `scan_pair_airlines` keeps the week's kept scan only (`docs/briefs/2026-10-23-rival-pairs-history.md`). The kept scans so far are 3, 4, 9, 16, 21 and 26.

## Scenarios and the risk of waiting
- **Amber comes in about a week whatever is chosen.** Every option passes 245 MB about 21 to 25 Nov, because deleted space isn't given back. To bring the size down, run `VACUUM FULL` on the cleaned tables once in Supabase's SQL editor. It takes a few seconds and briefly locks the table; it deletes no data.
- **Under A**, 350 MB comes about 19 Dec. That brings the paid-plan brief at the next weekly review, and growth goes on at about 90 MB a month.
- **Waiting costs about 3 MB an evening** under every option except A's connection detail, which the archive already caps.
- **B** changes little before January. It only acts on the 1st, and the biggest table (connection detail) is untouched.

## What would change the recommendation
- **If Gitesh wants connection trends over time** (for example in gander monthly), C still keeps one scan a week of connection totals for good. If he wants them every day, choose D.
- **If he wants every old row kept somewhere**, choose B, or C with an export to R2 like the archive's. Each makes the build bigger.
- **Any choice other than A changes a rule.** Manual §7 says "the scan summaries stay for good" (design §11 choice 2), so the manual and `rule-history.md` change with it. Deleting rows: the Building chat should say whether manual §1's removal rule applies. If it does, Gitesh runs the first clean-up in the SQL editor.

## Also found (not options)
- **`game_statement_pkey` is 21 MB**, on (airline, ts, descr, amount, occ), with 623,911 index scans. The capture uses it heavily to spot repeated lines, so it is no free saving. Swapping the long text column for a short hash could shrink it, but that needs its own build and is not proven.
- **`scan_rival_connections` has had 3,852 full-table reads (683 million rows read)** since the stats reset (`pg_stat_all_tables`). The likely cause is `fig_route_story()` filtering on `least()`/`greatest()` for each of about 419 routes in the stored-figures job. That is a speed issue, not size, and outside this job.
- **The manual's §7 list of what the archive takes** ("world-scan schedules and airport pages") leaves out `scan_rival_connections`, which the archive does take.

## Outcome
**C** (Gitesh, 15 Nov, Main chat). Every scan is kept in full for 14 days; after that the two summary tables keep only
the week's kept scan and the connection detail goes. Not in force until it is built: manual §7's "the scan summaries
stay for good" stands until the build's pull request replaces it, with the old wording in `rule-history.md`. The build
is to-do 240, after to-do 239's pull request is merged (one build at a time). The Main chat checked three of the
worker's figures against the database on 15 Nov: 96,881 October rows of `scan_rival_connections` due for the 1 Dec
archive (`private.archive_due`), 1,406 of scan 26's 11,164 connection rows on flown pairs, and the two summary tables
read only by existence checks and latest-scan readers (`database/current/functions.sql`).

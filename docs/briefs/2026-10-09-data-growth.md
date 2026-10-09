# Data growth — 9 Oct 2026 (decision #16)

**Decision:** how long the detailed game data stays in the database, and what happens to it after that. The detail is
every statement line, every flight's load and every world scan's full schedules.
**Recommendation:** B.
- **Summaries are kept for good:** per airline per day (#15), per route per day, and per world scan.
- **Detail stays in the database for 3 months.** Then it moves to monthly archive files in the private backups
  repository and is deleted from the database.
- **Reports' PDFs move to file storage.**
- **The nightly backup is split** by table and by month, so no file grows without limit.

The database stays well inside the free plan and the backups keep working. Nothing is lost: an archived month can be
loaded back when a question needs it.

*Columns adapted for a non-game decision. Sizes are estimates at today's fleet; they grow with the number of flights.*

| Option | What you get | Database size | Backups | Risk |
|---|---|---|---|---|
| A. Keep everything, as now | All detail always to hand | About 2 MB a day: the free plan's 500 MB is full between February and June 2027, depending on fleet growth | The single backup file passes GitHub's 50 MB warning around late November and its 100 MB block around January. The nightly backup then fails | Both limits are hit without warning. Then it's #17's paid plan plus a backup fix anyway |
| **B. Summaries for good, detail 3 months, then archived** | **Every trend, plus 3 months of full detail; older detail in monthly files, loadable on request** | **Levels off around 150 to 250 MB, growing slowly with the fleet** | **Split by table and month; closed months never change, so the backups repository stays small** | **Little. A question about detail older than 3 months takes a few minutes to load an archive** |
| C. As B, with 12 months of detail | More detail to hand | Around 500 to 700 MB: needs the paid plan (#17) | As B | Pays about $25 a month for detail that nothing uses after a quarter |
| D. Summaries for good, old detail deleted | Simplest | As B | Old detail only survives in old nightly backups | Detail is gone for good, or hard to dig out |

## Background
**Where the growth comes from** (live database, 9 Oct; full capture days were 7 and 8 Oct):
- **Bank statement lines** (`game_statement`): about 4,000 to 4,300 a day, one or more per flight and per cost. That's
  about 1.4 MB a day in the database. It's two thirds of all growth, and it grows with the fleet.
- **Flights with loads** (`game_loads`): about 300 a day, about 0.1 MB.
- **Income statement, balance sheet and payments ahead:** small, under 0.2 MB a day together.
- **World scans:** about 1.4 MB each (every airline's full schedule, plus the airport pages). Weekly scans (#22) add
  about 75 MB a year.
- **Report PDFs** (`site_reports`): five so far, about 0.5 MB each, stored inside the database.
- **Raw capture pages:** already kept for 14 days only.
- **The database today:** 21.8 MB of the free plan's 500 MB.

**The backups** (`equinox-backups`, 9 Oct):
- The whole database goes into one file, `db/data.sql`: 6.5 MB now, up about 1 MB in the last capture day.
- GitHub warns at 50 MB and blocks any file over 100 MB. GitHub recommends repositories stay under 1 GB, and strongly
  under 5 GB.
- Because the whole file changes every night, the repository keeps a slightly different full copy each night.

**What uses the detail:**
- The planner's route profit, cash forecast, growth signals and fare plan look back days or weeks.
- The weekly report covers last week; the monthly report covers last month.
- Anything longer is a trend, which the summaries answer.
- Nothing on screen or in a report needs statement lines older than a quarter.

## What B would hold
- **Kept for good** (small):
  - the daily airline snapshots (#15);
  - a daily route summary: flights, passengers, seats, revenue, costs and profit per route and direction;
  - each world scan's market summary;
  - the income statement and balance sheet (a few hundred rows a day);
  - the change log for 12 months, then archived like the detail.
- **Kept 3 months, then archived:**
  - statement lines;
  - per-flight loads;
  - world scans' full schedules;
  - payments-ahead pages.
- **Archive:** once a month, a job writes each month older than 3 months to a compressed file per table in
  `equinox-backups` (about 40 MB a year), checks it, then deletes those rows. Loading a month back is one command.
- **Report PDFs** move to Supabase file storage (1 GB free), out of the database. The library pages keep working.
- **Backups:** split by table, and by month for the big tables, so no file nears 50 MB. A closed month's file never
  changes, so the repository grows only by what's new.
- **The #13 design can also store statement lines more compactly.** The same long descriptions repeat on thousands of
  lines.

## Scenarios and the risk of waiting
- **The fleet doubles** (59 aircraft were delivered from 28 Sep to 9 Oct):
  - under A, the free plan fills in about four months and the backup breaks sooner;
  - under B, the database levels off higher, around 300 to 450 MB. That's when #17's paid plan comes in, by choice
    rather than in a hurry.
- **A question about July's statement lines next year:** under B, load July's archive (minutes). Under D, it's gone.
- **Waiting:** the backup file hits GitHub's warning in about seven weeks and its block in about three months, so the
  backup split can't wait long whatever is decided. The archive job can start any time after the #13 tables exist.

## What would change the recommendation
- **If you move to the paid plan anyway (#17):** C is affordable, but nothing uses the extra detail.
- **If you want detail older than 3 months on screen** (say, a year of flight-by-flight fare tests): lengthen B's
  window for that table only.
- **If fleet growth slows a lot:** A lasts longer, but the backup file still needs splitting.

## Sources
- Live database, 9 Oct: table sizes and rows per day (`game_statement`, `game_loads`, `game_pnl`, `game_balance`,
  `game_events`, `game_capture_raw`, `site_reports`, `game_snapshot_*`); database size 21.8 MB.
- `equinox-backups`, 8–9 Oct: `db/data.sql` 5.5 MB at 20:30 UTC on 8 Oct, 6.5 MB at 03:53 UTC on 9 Oct.
- GitHub, "About large files on GitHub" (blocks over 100 MiB, warns over 50 MiB; repositories ideally under 1 GB):
  https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github
- Supabase pricing (free plan 500 MB database and 1 GB file storage; paid plan from $25 a month with 8 GB):
  https://supabase.com/pricing

## Outcome
Open: waiting for Gitesh's decision.

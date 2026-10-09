# Data growth — 9 Oct 2026 (decision #16)

**Decision:** how long the detailed game data stays in the database, and what happens to it after that. The detail is
every statement line, every flight's load and every world scan's full schedules.
**Recommendation:** E (added below, after Gitesh asked for a permanent fix); B was the first recommendation.
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

## Option E: the permanent fix (added 9 Oct)
Gitesh asked for the best permanent fix, with up to $10 a month, and whether storage like OneDrive could be used. This
replaces B as the recommendation.

**E. Store smarter, keep a year, archive and back up to Cloudflare R2:**
1. **One row per flight for money and loads.** The bank statement has about 9 lines per flight (Pan Am, 8 Oct: 522 lines
   for 56 flights): fuel, passenger income, cargo income, handling and landing at each end, maintenance. Stored as one
   row per flight with those as columns, merged with the flight's loads, it's about 15 to 20 times smaller. The raw
   lines are kept 14 days for checking, like raw pages today.
2. **Summaries for good,** as in B.
3. **Per-flight detail for 12 months in the database** (affordable once it's compact), then archived.
4. **Archives and nightly backups go to Cloudflare R2** instead of the GitHub repository:
   - free up to 10 GB, then $0.015 per GB a month, with no download fees;
   - no file-size limits;
   - old nightly copies deleted automatically (keep 30 nightly copies and one a month for good);
   - you already have a Cloudflare account.

   GitHub keeps the code. This changes #6 (where backups live) and #8 (the rehearsal reads last night's backup from R2
   with a read-only key).
5. **Report PDFs** move to file storage (R2 or Supabase's), out of the database.

| | Database | Backups | Cost |
|---|---|---|---|
| E | About 0.1 MB a day of flight detail at today's fleet: about 35 MB for the 12 months kept, plus slowly growing summaries. Within the free plan up to roughly ten times today's flights; beyond that, keep 6 months or pay | No size limits; 30 nightly copies plus monthly ones | $0 expected for years; a few cents a month at most |

**Why not OneDrive or Google Drive:** they're built for people, not unattended jobs. An automatic upload needs a
sign-in token that renews itself on every use. Microsoft's answers say refresh tokens lapse after 90 days without
use, and each use hands back a new token the job must save. A nightly GitHub job can't easily keep that up, so the
backups would quietly stop one day. They would also mix backups with personal files. R2 (or Backblaze B2) uses fixed
keys made for machines.

**Why not a bigger database instead:** Supabase's paid plan is $25 a month, over the $10 limit. Moving the database to
another provider would mean redoing sign-in, access rules and the website's data, a big job for space E already makes
unnecessary.

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

## Benefits and risks in more detail
(Added 9 Oct at Gitesh's request.)

**What happens at the limits:**
- **Database over 500 MB on the free plan:** Supabase puts the project into read-only mode. The capture can't store
  anything and the planner can't save, so it's an outage. The ways out are upgrading on the spot, or deleting data by
  hand.
- **A backup file over 100 MB:** GitHub refuses the push and the nightly backup fails. The planner warns after 30
  hours, but there's no new copy until the file is split.
- **Restores get slower as the database grows:** the nightly restore check and the database rehearsal on every pull
  request both rebuild the whole database. The rehearsal's limit is 20 minutes.

**B, benefits:**
- Stays on the free plan; the upgrade becomes a choice (#17), not an emergency.
- Planner screens and reports read 3 months, not all history.
- Backups and restores stay quick.
- Nothing is thrown away.

**B, risks and how they're handled:**
- **The archive deletes rows before they're safe.** The job writes the file, reads it back, checks row counts, commits
  it to GitHub and confirms the commit before deleting anything. Last night's backup also still holds those rows.
- **The archive job doesn't run** (like this morning's skipped backup). The database just grows a little more until
  the next run. Monitoring (#23) shows it.
- **A question needs detail older than 3 months.** Claude loads that month back into a scratch table; it takes minutes,
  not seconds. The planner itself only shows 3 months of detail.
- **The summaries miss a question nobody thought of.** The archives keep everything, so a new summary can be worked out
  from them later.
- **One more job to look after.** It's about one pull request, and the backup split is needed anyway.

**The settings within B:**
- **Window:** 3 months keeps the database at about 150 to 250 MB at today's fleet. 6 months is about 300 to 350 MB,
  which runs over 500 MB once the fleet doubles. 12 months needs the paid plan.
- **Where archives live:** in the private backups repository (recommended: already private, already backed by GitHub,
  about 40 MB a year compressed), or in Supabase file storage (1 GB free, but then the same project holds data and
  archive).
- **Change log:** 12 months in the database, then archived the same way.

**A, benefits:** no archive job; every detail is always one query away.
**A, risks:** read-only mode some time between February and June 2027; the backup failing around January; slower
restores and rehearsals; then the upgrade and the backup fix in a hurry.

**C, benefits:** a full year of flight-by-flight detail on hand. **Risks:** about $25 a month from the point the
database passes 500 MB, for detail nothing reads today.

**D, benefits:** the simplest and smallest. **Risks:** it can't be undone. Old detail then lives only in old nightly
backups, which is awkward to search, and is gone if that history is ever trimmed.

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
- Cloudflare R2 pricing (10 GB a month free, then $0.015 per GB-month, no egress fees):
  https://developers.cloudflare.com/r2/pricing/ and lifecycle rules (delete after N days):
  https://developers.cloudflare.com/r2/buckets/object-lifecycles/
- Microsoft Q&A on refresh-token lifetime (90 days of inactivity):
  https://learn.microsoft.com/en-sg/answers/questions/1665481/when-and-how-is-a-refresh-token-extended
- Supabase, "Understanding database and disk size" (free plan projects go read-only over 500 MB):
  https://supabase.com/docs/guides/platform/database-size
- Supabase pricing (free plan 500 MB database and 1 GB file storage; paid plan from $25 a month with 8 GB):
  https://supabase.com/pricing

## Outcome
Open: waiting for Gitesh's decision.

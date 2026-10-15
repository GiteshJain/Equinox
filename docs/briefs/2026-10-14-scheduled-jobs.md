# Scheduled jobs — 14 Oct 2026 (decision #22)

**Decision:** which recurring work should run on its own schedule: the world scan, the report drafts and the backups.

**Recommendation:** B. Run the world scan every week on its own, early on Saturday morning, before the weekly review.
- **The backups already run on their own,** every night since 8 Oct, with the restore check, the monthly archive and
  the two database jobs. There's nothing left to decide there.
- **The world scan is the real gap.** There has been one, on 6 Oct. The weekly report's competition by market and gander
  monthly both read the latest scan, so every report since has used a week-old picture of the rivals. A scan needs a
  chat that can reach the game, and takes a while, so it gets skipped.
- **A free GitHub job can run the scanner we already have** (about 300 public game pages, 5 to 10 minutes, with pauses
  between pages) and save it the usual way. Home warns if it fails, like the other jobs.
- **The report itself stays in the Saturday chat.** Its numbers take a minute to pull, and they should be pulled at
  the moment of the review. Having Claude write a draft on its own belongs with #25 (unattended jobs and their spending
  cap).

One pull request, about 1 to 2 hours. $0 a month.

*Columns adapted for a non-game decision.*

| Option | What changes | Effort | Gain | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Keep as is | Nothing. The scan runs when a chat runs it; the report is pulled and written in the Saturday chat; backups and the database jobs run on their own as now | None | None | Reports keep reading an old scan (only one so far, 6 Oct) | — |
| **B. Weekly scan on a schedule** | **A GitHub job runs the existing scanner every Saturday at 06:00 UTC (01:00 in Chicago) and saves the scan; one `job_runs` row; Home warns if it failed or the latest scan is over 8 days old** | **1 pull request, about 1 to 2 hours** | **A fresh rivals' picture for every weekly report and gander monthly** | **The game could block or change its pages: the job fails and Home says so; the scan can still be run by hand** | **Yes: switch the job off** |
| C. B, plus the report's numbers prepared | B, plus the same job pulls and works out the report's numbers and charts after the scan, kept as a draft pack for the Saturday chat | 1 pull request, about 2 to 3 hours | Saves the chat a minute or two | Numbers from 01:00, not from the moment of the review; one more thing to keep working | Yes |
| D. C, plus a Claude-written draft | C, plus a Claude scheduled task writes the draft report each Saturday morning, ready for the review | C, plus a scheduled task | The report waiting for you on Saturday | Uses Claude every week; belongs with #25 | Yes |

## Background

### What already runs on its own
The manual §7 and the map's *What runs when*; `job_runs` and `backup_runs`, 14 Oct.
- **Every night, 07:17 UTC (GitHub):** the backup, its restore check and the upload to R2; then the monthly archive.
  Last good backup 14 Oct, 12:54 UTC (GitHub started it late, as it sometimes does).
- **10:00 UTC (in the database):** the snapshot fallback. **10:20 UTC:** the clean-ups.
- **Home** warns when a backup is over 30 hours old, a snapshot is late, the archive hasn't run by the 3rd, or any
  job's last run failed.

So #22's "backups" part is done (#6 on 8 Oct, #16 on 9 to 11 Oct).

### The world scan today
- **What it reads:** every airline in Gander and its schedule, then the airport pages for our hubs and the big rival
  hubs (`scripts/scanner/gscan.py`). These are the game's public information pages; it signs in to nothing. Scan 3, on
  6 Oct: 161 airlines and 127 airports. It waits 0.25 to 0.5 seconds between pages, so a full scan is about 300 pages
  and 5 to 10 minutes.
- **What reads it:** the weekly report's competition by market (`report/pull.py` takes the latest finished scan),
  gander monthly, and the market summaries (`report/scan_markets.py`).
- **How it runs now:** by hand, from a chat that can reach the game. This workspace can't (its network only reaches a
  short list of sites), so it depends on which chat runs it, and when. One scan in 8 days.

### How B would work
- A GitHub Action in the `equinox` repository, on a schedule, runs `gscan.py` and saves the scan through
  `ingest_snapshot()` with the ingest secret, kept in GitHub's settings like the backup's.
- It writes one `job_runs` row (job `scan`); Home's "Nightly jobs" shows a failure, and a scan over 8 days old.
- GitHub gives a private repository 2,000 free minutes a month. The backups and the checks use part of that; a weekly
  scan adds about 40 minutes a month.
- The scan's detail (each airline's schedule) goes to the monthly archive after a month, as now; the summaries stay.
- Running it by hand still works, for a scan in the middle of the week.

### Risks
- **The game blocks automated reads, or changes a page.** The job fails, Home says so, and the scanner gets fixed. The
  pace stays as gentle as today's.
- **GitHub starts scheduled jobs late,** sometimes by hours. Saturday 06:00 UTC leaves room before a morning review.
- **Database size:** each scan adds its schedules until the archive moves them out. That's small against the 350 MB
  trigger (§1).

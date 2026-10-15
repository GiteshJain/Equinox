# Monitoring — 14 Oct 2026 (decision #23)

**Decision:** whether to have one place that shows whether the captures, jobs, backups and deploys worked, and what it
shows.

**Recommendation:** B. A "Systems" board at the top of the planner's Check screen, one line each with a green, amber or
red mark.
- **Home already flags problems** (a late capture, an old backup, a failed job), but only problems. Nothing says "all
  good", and deploys and usage appear nowhere.
- **The board puts everything on one screen:** the evening capture (each airline, with #21's verdict once that's
  built), the daily snapshot, the nightly backup and its restore check, the monthly archive, the clean-ups, the world
  scan's age (#22's Saturday step), when the planner itself was last built and published, and the usage figures the
  database can measure itself, against their triggers.
- **Today's usage figures:** database 44 MB (trigger 350 MB), report PDFs 1.5 MB (trigger 50 MB), the website's data
  114 KB (trigger 500 KB). The monthly look at Supabase's usage page keeps only what the database can't see: egress and
  the website's calls a day.

One pull request, about 2 hours. $0 a month.

*Columns adapted for a non-game decision.*

| Option | What changes | Effort | Gain | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Keep as is | Nothing. Home lists problems; Check shows each airline's capture; usage is a monthly look by hand | None | None | Deploys and usage stay unseen; "nothing on Home" can mean all good, or that Home wasn't opened | — |
| **B. A Systems board on Check** | **One line each: capture, snapshot, backup, archive, clean-ups, scan, the planner's last build, and database size, report PDFs and the website's data against their triggers. Home keeps flagging problems** | **1 pull request, about 2 hours** | **One look says whether everything worked, deploys and usage included** | **Egress and the website's calls stay a monthly look by hand** | **Yes** |
| C. B, plus Supabase's own usage | B, plus a daily GitHub job that reads egress and calls a day from Supabase's account, so the monthly look goes away | 1 pull request, about 3 hours | Every trigger on the board | The job needs a Supabase account token that can change anything in the account, kept in GitHub's settings | Yes: delete the token |
| D. B, plus an outside alert | B, plus a free check-in service that emails you when a job misses its time | B, plus a service to set up | An alert when you're not looking | Another account and service; #21 chose no alerts outside the planner | Yes |

## Background

### What the planner shows today
Repository `main` and the live database, 14 Oct.
- **Home, "needs attention":** an airline not captured for 26 hours (red at 48), no good backup in 30 hours, no snapshot
  in 30 hours (or the 10:00 UTC job not run: the scheduler may have stopped), the archive not run by the 3rd, any job's
  last run failed (manual §7). It shows problems only, and only when Home is opened.
- **Check, "Capture":** what the capture collected for each airline and when.
- **Nowhere:** whether the latest merge was built and published (Cloudflare keeps the last good version when a build
  fails, so a failed deploy looks like nothing happened), and the usage figures. The manual's monthly step covers usage
  "until #23's monitoring shows it" (§7).

### The jobs, 14 Oct
| Job | Runs | Last run |
|---|---|---|
| Capture and daily snapshot | Each evening, by hand | 15 Oct 00:11 UTC, complete |
| Snapshot fallback | 10:00 UTC, in the database | 14 Oct, ok |
| Clean-ups | 10:20 UTC, in the database | 14 Oct, ok |
| Backup and restore check | 07:17 UTC, GitHub (can start hours late) | 14 Oct 12:54 UTC, ok |
| Monthly archive | After the backup; work only on the 1st | 11 Oct (first run) |
| World scan | Saturdays, from the chat (#22) | 6 Oct |

### What the board would read
- `job_runs`, `backup_runs` and `capture_status()`, as Home does now.
- The world scan's age from `game_scans`.
- **The planner's own build:** the build writes its time and the change it came from into the planner, and the board
  shows it. After a merge, a time that hasn't moved means the deploy failed.
- **Usage the database can measure:** its own size, the report PDFs' size in `site_reports`, and the size of
  `site_public()`, each against its trigger (§1, #16, #20), through one staff function.
- **Not on the board:** Supabase's egress and the website's calls a day, which only Supabase's account can see (option
  C). Both are far below their triggers (about 40 calls a day against 1,000).

### Risks
- **The board can only report what's recorded.** A job that never starts has no row; the board shows its last run
  getting old, and turns amber and then red at the same limits as Home.
- **The build time shows publishing, not that every page works.** The checks on each pull request cover that.

## Outcome
14 Oct 2026: Gitesh chose **B**: a Systems board at the top of Check, with the database's own usage figures against
their triggers; egress and the website's calls stay a monthly look by hand. Recorded in `docs/decisions.md` and the
manual's *Decided, not yet built*.

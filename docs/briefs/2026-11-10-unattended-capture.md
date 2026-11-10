# Unattended capture — 10 Nov 2026 (reopens #21 and #22)

Written in the Audit chat (Audit · 10 Nov), after its review of the whole system.

**Decision:** whether the capture runs on its own several times a day, without your laptop, and where.

**Recommendation:** C. A GitHub job runs the same capture script every 6 hours, reading only, started by the
database's scheduler and not by GitHub's own timer (see *Why GitHub's timer runs late*, added the same day).
- The game keeps both the loads and the bank statement for 24 hours only, so one capture a day has no slack: pressed
  an hour late, an hour of flights is gone for good. *(Corrected 10 Nov, after the decision: this said the statement
  stops at 1,500 lines and that Ryanair fills them in 16 hours. That stop is the capture script's own, not the game's;
  see* The 1,500 *under Background. It is lifted in the same build.)*
- 5 to 7 Nov went uncaptured: about 2,700 flights have no loads and no money, for good. On the captured days from
  27 Oct to 8 Nov, 362 flights have loads but no money, 267 of them Ryanair's (12% of its flights).
- It reuses the script you press now, costs $0, and GitHub can email you when a run fails.

One migration, one job, about 3 to 4 hours of building. $0 a month.

*Columns adapted for a non-game decision.*

| Option | What changes | Gain | Risk | Cost · undo |
|---|---|---|---|---|
| A. Keep as is | You press it, as now | None | Every missed evening is lost; Ryanair's money is short on any day with one capture | $0 |
| B. Keep pressing, add an alert | #21's option C: GitHub tells your phone when a capture is late. The iPhone's script brought up to date | Fewer missed evenings | Still needs you twice a day, every day; travel and sleep still cost data | $0 · one setting |
| **C. GitHub runs it every 6 hours** | **A hidden browser signs in, presses Capture all airlines with its own key, and checks every airline says "all good"** | **Complete loads and money without you; no evening capture to remember** | **The first script that runs unwatched; a GitHub token kept in the database, to renew when it expires; the sign-in could be refused one day** | **$0 · switch the job off** |
| D. The same on a small cloud server | As C, on an always-on machine with its own timer | As C, on time, from one steady address | A server to keep patched, with your sign-in on it | $5–12 a month · delete the server |

## How C would work
- **Its own capture key,** marked unattended. For that key the database answers "no salaries, no world scan, no market
  pages", so a run reads only our airlines' pages and fleets: about 140 pages in about 3 minutes. Your own press keeps
  doing the scan, the market pages and the salaries. The script itself doesn't change.
- **The job lives in `equinox-backups`:** private, so its logs are too, and it already holds the database's address.
  About 600 of the month's 2,000 free minutes, beside the backup's. It prints nothing from the game.
- **The database's scheduler starts each run,** every 6 hours, by asking GitHub to run the job (`workflow_dispatch`).
  It needs `pg_net` switched on (it's available, not yet on) and a GitHub token that can only start jobs in
  `equinox-backups`, kept in the database's vault. GitHub's own timer stays in the job once a day as a backstop; two
  runs can't overlap, and an extra capture does no harm.
- **You add the game sign-in as two GitHub secrets yourself,** and the token to the vault. Neither passes through a
  chat.
- **Every run writes a `job_runs` row,** so Today and the Systems board show the last unattended capture like any job.
  A run where any airline isn't "all good" fails, and GitHub emails you.
- **The first runs are watched,** to check three things: the sign-in works from GitHub; it doesn't sign you out
  elsewhere; and it doesn't change the airline open in your own browser.

## Background
Live database and repository `main`, 10 Nov.
- **The 24 hours:** every statement capture under 1,500 lines ends about 24 hours back (Pan Am, 9 Nov: 07:45 back to
  08:00 on 8 Nov), in every capture checked from 2 to 9 Nov (`game_capture_raw`). #21's brief assumed 3 days, and the
  map still says so.
- **The 1,500:** on 4 Nov Ryanair posted 2,204 lines, China Eastern 1,674 and Virgin 1,641; Pan Am, Kingfisher and
  Malaysia 1,100 to 1,220 (`game_statement`). The script also stops at 15 pages (`capture/capture_all.user.js`), so the
  data can't show whether the game does too. Gitesh, 10 Nov: he thinks it's the game's limit.
  **Corrected 10 Nov, after the decision:** Gitesh looked in the game. Page 15 has the ">" link, and Ryanair's
  statement ran to page 24. So the game shows the whole 24 hours, and the 1,500 is the script's stop at 15 pages
  (`pages < 15`). The build lifts it: the statement is read to its last page and sent in parts, so no call comes near
  its 30-second limit. That alone ends the short money on a day with one capture (the 362 flights above). The 24 hours
  with no slack and the missed evenings remain the case for C.
- **Why it mostly worked until now:** from 27 Oct to 4 Nov you captured 24 times in 9 days, 2 to 5 a day. On 8 and
  9 Nov, once a day.
- **What a missed day leaves:** `airline_days` has 119 flights for 5 Nov and none for 6 and 7 Nov, against about
  1,000 a day. #21's brief counted about 780 flights lost on 11 and 12 Oct.
- **What reads this data:** the cash forecast behind every order, the fare ladder (5 captured departures a direction),
  route profit, long haul's cash test and the weekly report.
- **The rules:** terms §5.3 forbids automated use, and #12 decided that Gander's owner allows your scripts. The manual
  says the fares script never runs on a schedule or unwatched; this would be the first script that does, and penalties
  (rule 1.2) can fall on the whole account. Four runs read about 560 pages a day, about what your own two to five
  captures a day read now, and change nothing. A one-line OK from Gander's owner would settle it.
- **GitHub's timer:** not relied on. The nightly backup starts 4 to 10 hours after its set time, every night; the
  section below says why.
- **Prices:** GitHub's standard runners are free for public repositories; a private one has 2,000 minutes a month
  (#1, 14 Oct). A 1 GB cloud server was $5 a month in June 2026, and a browser wants about 2 GB.

## Why GitHub's timer runs late
Looked into on 10 Nov, at Gitesh's request: GitHub's own run history for `equinox-backups` (all 51 runs), the job's
file, and the database's scheduler.
- **It's GitHub's timer, not our job.** The job is set for 07:17 UTC (`cron: "17 7 * * *"`, unchanged since 10 Oct).
  GitHub created each of the 32 scheduled runs 4.3 to 10.2 hours after that, the middle one 6.7 hours late. Once
  created, every run started within the same second and finished in about 4 minutes. Nothing waits for a machine, and
  nothing in the job is slow.
- **Only the timer is late.** The 19 runs started another way (a merge, a pull request, the Run workflow button)
  began at once, bar one.
- **Late, never missed, and getting later.** One scheduled run every day since 9 Oct, 21.8 to 27.2 hours apart. The
  middle lateness by week: 5.4 hours (12 and 19 Oct), 6.8 (26 Oct), 7.8 (2 Nov); 10.2 on 9 Nov.
- **Others report the same since early October 2026:** scheduled runs on GitHub's free plan created hours late,
  starting at once when created, manual runs fine (GitHub community discussions 210361, a private repository on the
  free plan, and 210888). GitHub hasn't answered either; one support request was closed without a diagnosis. One
  article says a paid plan ($4 a month) cures it; nobody in those threads confirms that.
- **The database's scheduler is on time.** Its two daily jobs have run 60 times since 11 Oct, none failed, none more
  than a quarter of a second after the minute (`cron.job_run_details`).
- **So:** the database starts the capture's runs (above). The same start would put the nightly backup back at 07:17,
  ahead of the 10:20 clean-ups and well inside Today's 30-hour warning, which the 9 Nov run came within 3 hours of. That
  is a separate, small decision.

## Scenarios and the risk of waiting
- **It works:** complete data from the first day, and your evening press becomes optional on days you don't play.
- **The sign-in is refused, or a run disturbs your own session:** switch the job off; nothing is worse than today.
  Then D, or B.
- **Waiting:** until the script's stop is lifted, every aircraft added shortens the reach. At 3,000 lines a day
  Ryanair's is 12 hours. Virgin and China Eastern are already past 1,500 a day; Pan Am, Kingfisher and Malaysia pass it
  after about a quarter more flying, and from then one capture a day loses money on all six.

## What would change the recommendation
- Page 15 of Ryanair's statement has a ">" link: the 1,500 is the script's, and its limit is raised as well. The
  24 hours still call for more than one capture a day. **This is the case (Gitesh, 10 Nov), so the build does both.**
- Runs started by the database also begin late in the trial, or GitHub starts refusing them: D.
- You'd rather have no unattended sign-in on the account: B.

## Sources
- GitHub, billing and usage for Actions: https://docs.github.com/en/actions/concepts/billing-and-usage
- GitHub's scheduled workflows, their delays and limits: https://cronuru.com/guides/github-actions-scheduled-workflows
- Small cloud servers' prices, June 2026: https://cloud-cost-557.pages.dev/compute-vps/
- Scheduled runs created hours late, a private repository on the free plan (15 Oct 2026):
  https://github.com/orgs/community/discussions/210361
- Scheduled runs over 5 hours late since early October 2026: https://github.com/orgs/community/discussions/210888
- The claim that a paid plan cures it (not GitHub's own statement):
  https://devactivity.com/insights/github-actions-cron-schedules-a-hidden-free-tier-hurdle-impacting-developer-productivity/

## Outcome
**C, with its runs started by the database's scheduler** (Gitesh, 10 Nov: "I love C", then, after the look at why
scheduled jobs run late, "Yes"). Not yet built: the manual lists it under *Decided, not yet built*, and §7's every
evening stands until the build merges. `decisions.md` notes the change to #21 and #22, and `rule-history.md` the why.
The build is the Building chat's (to-do on the planner's board).
Added the same day: the 1,500 lines turned out to be the script's stop, not the game's (above), so the same build
lifts it. C stands, as *What would change the recommendation* said it would.

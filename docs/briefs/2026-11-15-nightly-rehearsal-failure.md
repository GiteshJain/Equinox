# Where a failed nightly rehearsal shows, and what starts it

*Main chat, 15 Nov 2026. To-do 234, steps 1 and 11. A small decision, so a short brief.*

## Decision
The nightly database rehearsal on `main` (since 11 Nov, #152) is started by GitHub's own timer and reports a failure
only through GitHub's email. Should it start on time, and should a failed night show on the planner's Today?

**Recommended: A, leave both as they are.** Gitesh chose **B**.

## Options

| | A. Leave as is | B. Failure shows on Today | C. Start it from the database too, and show on Today |
|---|---|---|---|
| Starts | GitHub's timer (08:43 UTC), 6.5 to 8.5 hours late, but every day | Same | On time, from the database's scheduler |
| A failed night shows | GitHub's email to Gitesh | On Today, as other jobs do | On Today |
| Gitesh does | Nothing | Nothing, or adds one key to GitHub | Makes a new GitHub token that can start runs in the Equinox repository |
| Build | None | Small | Small to medium (database change, workflow, tests) |
| Risk | The email is missed; after 60 quiet days GitHub stops a public repository's timer without saying | Low | Low |
| Undo | Nothing to undo | Easy | Easy |

This choice moves no growth, profit or cash, so the brief's money columns are left out.

## Background
- The nightly run started at 17:05, 16:44 and 15:21 UTC on 12, 13 and 14 Nov (GitHub's Actions page) and passed each
  time. On 12 Nov it had not started by 09:31 UTC and the Main chat started one by hand.
- It checks that `main` still restores and passes on the latest backup. A late start loses nothing, and a failure
  breaks nothing live: the backup has its own nightly restore check, which Today watches (manual §7), and every pull
  request that changes the database runs its own rehearsal before "merge" (manual §1).
- The unattended capture was moved to the database's scheduler on 10 Nov because a late capture loses loads for good
  (`docs/briefs/2026-11-10-unattended-capture.md`). Nothing like that is at stake here.
- Manual §7: every job writes a row to `job_runs`, and Today warns when any job's last run failed. The nightly
  rehearsal writes none.

## If we wait
Nothing is lost by waiting. A failed night would be seen from GitHub's email, or at the next pull request.

## What would change the recommendation
If Gitesh doesn't read GitHub's failure emails, B is the cheap fix.

## Outcome
**B** (Gitesh, 15 Nov, Main chat). The timer stays GitHub's: step 11 of to-do 234 is settled as "leave it, late but
daily". The build is to-do 239; its spec says how the result reaches `job_runs`. Not in force until it is built, so the
manual is unchanged until the build's pull request.

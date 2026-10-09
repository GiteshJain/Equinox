# Database plan and testing saves — 9 Oct 2026 (decision #17)

**Decision:**
1. Whether to move Supabase to its paid plan, and when.
2. Widened by the 9 Oct consistency check: how the #13 adapter's saves get tried on real data before they reach live,
   since previews can't save.

**Recommendation:** B. Stay on the free plan, and test real saves for free: on every pull request, the rehearsal
starts a full local copy of Supabase (database, data API and sign-in), loads last night's backup into it, and the
planner checks save into that copy for real, then compare the tables. Move to the paid plan only when one of the
triggers below is reached. It costs $0, within the $10-a-month limit.

*Columns adapted for a non-game decision.*

| Option | How adapter saves are tested | Cost a month | Effort | Risk |
|---|---|---|---|---|
| A. Free plan, as now | Only against a stand-in in the planner checks, and SQL tests on the backup copy. The first real save of the new code happens on live | $0 | None | A save bug reaches live data. Undo then relies on the change log (#15) and the nightly backup |
| **B. Free plan + full local Supabase in the checks** | **Every pull request: last night's backup in a local Supabase, the planner signed in and saving for real, the tables checked afterwards** | **$0** | **About one pull request; each rehearsal takes a few minutes longer** | **Little. The local copy isn't the live platform (no Cloudflare in front, local sign-in), but the database, rules and data are the same** |
| C. Free plan + a second free Supabase project as staging | A copy of live you can click around in yourself, refreshed from the nightly backup | $0 | Medium: keep it in step, separate keys, the preview pointed at it | Two projects to keep alike. It pauses after a week unused. A preview that saves to the wrong project is a new way to break things |
| D. Paid plan, with test copies (branching) | Supabase makes a database copy for each pull request | $25 + about $0.32 a day per copy in use | Medium | Over the $10 limit. It buys space and backups we don't need (below) |

## Background
**Where we are against the free plan** (live, 9 Oct, and Supabase's pricing page):

| Free limit | Us | Note |
|---|---|---|
| Database 500 MB (read-only above it) | 21 MB | #16 keeps it small: one row per flight, one month of detail |
| File storage 1 GB | 2.9 MB (57 files) | Report PDFs move there under #16: a few MB a month |
| Egress 5 GB a month | Not measured here | The likeliest limit. Each planner opening downloads the whole planner row (194 KB), the route research (469 KB) and the capture tables. #13's tables shrink that. Check the usage page in the Supabase dashboard each month until #23's monitoring shows it |
| Pauses after a week without database activity | Daily activity | The capture and planner run most days, and the nightly backup connects every night. A paused project keeps its data and is resumed from the dashboard |
| No backups included | Our own | Nightly to Cloudflare R2, each one restored and checked, plus a monthly copy for good (#6, #16) |
| 2 active projects | 1 | Room for option C if ever needed |

**What the paid plan ($25 a month) adds, and whether we need it:**
- **8 GB of database:** not needed under #16.
- **Daily backups kept 7 days:** ours are better. They're kept 30 days plus monthly, restore-checked every night, and
  held outside Supabase.
- **No pausing:** our daily activity already prevents it.
- **250 GB of egress:** only matters if egress becomes the limit.
- **Test copies (branching):** option B gives the same safety for free.
- **Point-in-time recovery:** an extra $100 a month on top, far beyond this project.

**What the local copy can do:** the rehearsal already restores last night's backup into a local Supabase database on
GitHub's runners (#8). Starting the full local Supabase instead (`supabase start`) adds the data API and sign-in that
the planner talks to. The planner checks then run against it:
1. sign in as a test staff user created in the copy;
2. make real changes: tick a to-do, edit a plan card, type in loads;
3. read the tables back to prove the adapter wrote exactly what was meant, and nothing else.

Nothing leaves the runner, and the copy is thrown away afterwards.

## Scenarios and the risk of waiting
- **#13's adapter has a save bug:**
  - under B, the check fails on the pull request and nothing reaches live;
  - under A, it reaches live data, and the change log and backups are the way back.
- **Egress climbs past 4 GB a month** before #13 lands: that's a trigger (below). The fix is usually to load less, not
  to pay.
- **You're away for weeks:** the nightly backup keeps the database active. Even if it paused, the data stays and it
  resumes from the dashboard.
- **Waiting:** B needs to be in place before the #13 adapter pull requests, so it's built as the first #13 pull
  request.

## When to move to the paid plan (triggers)
- the database passes 350 MB (70% of the free limit);
- egress passes 4 GB in a month (80%);
- the free plan is paused or limited for any reason despite daily activity;
- a feature we decide we need is paid-only.

A trigger means a brief at the next weekly review, not an automatic upgrade.

## What would change the recommendation
- **If you'd like to click around a test planner yourself** before big changes go live: add C alongside B.
- **If Supabase changes the free plan** (pausing, limits): revisit.
- **If the $10 limit is lifted:** D's branching becomes convenient, but B still covers the risk.

## Sources
- Supabase pricing (free: 500 MB database, 5 GB egress, 1 GB files, 2 active projects, pauses after a week without
  activity, no backups; paid: from $25 a month, 8 GB, 250 GB egress, daily backups for 7 days, branching $0.01344 per
  hour, point-in-time recovery $100 a month): https://supabase.com/pricing
- Supabase, project pausing (inactivity, restoring): https://supabase.com/docs/guides/platform/free-project-pausing
- Supabase, database size (read-only over 500 MB): https://supabase.com/docs/guides/platform/database-size
- Supabase changelog, July to October 2026 (no changes to free-plan limits, pausing or branching):
  https://supabase.com/changelog
- Live database, 9 Oct: size 21 MB; 57 stored files, 2.9 MB.

## Outcome
9 Oct 2026: Gitesh chose **B**. The paid-plan triggers and the monthly usage check are in the manual (§1 and §7).

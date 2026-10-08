# Foundation decisions

Decided one at a time, in this order. Each decision is recorded here with the date and the reason.
Status: **decided**, **open**, or **dropped**.

## Step 1 — How we work (decide now)
| # | Decision | Status |
|---|---|---|
| 1 | Private GitHub repository `equinox` as the single home for code, database changes, scripts, tests and docs | **decided** 8 Oct 2026 |
| 2 | Building through Claude Code and the repository: every change as a reviewable pull request | **decided** 8 Oct 2026 |
| 3 | A claude.ai "Equinox" project with its own instructions and reference files | open |
| 4 | Operating manual and decision log: every rule and the reason behind each decision in one place | open |
| 5 | A standard decision brief (background, options, growth and profit side by side, risks, recommendation) | open |
| 6 | Backups now, and where they are kept (there are none on the current database plan) | open |

## Step 2 — Foundations (decide before any building)
| # | Decision | Status |
|---|---|---|
| 7 | Hosting: move to Cloudflare Pages or stay on Netlify (paid tier); and our own domain name | open |
| 8 | Preview before live: every change gets a preview link; database changes tried on a copy first | open |
| 9 | Automatic tests on every change, blocking anything that breaks | open |
| 10 | Documentation: README, architecture notes, what each table means | open |
| 11 | Proper roles (owner, staff, investors, public); no shared passwords; secrets out of scripts | open |
| 12 | Game-rules exposure: how the capture and the salary step act in the game | open |

## Step 3 — Data model (decide before the data-model build)
| # | Decision | Status |
|---|---|---|
| 13 | Planner data into proper tables, with a cleaner model (IDs, UTC times, each flight leg as a row) | open |
| 14 | Multi-world, multi-group: everything keyed by world, group and airline; settings as data, not code | open |
| 15 | History: every change kept, plus daily snapshots of fleet, departures, cash and market share | open |
| 16 | Data growth: daily summaries kept forever, detail archived after a few months | open |
| 17 | Database plan: when to move Supabase to its paid tier (backups, no pausing, branch databases) | open |

## Step 4 — Applications (decide before the planner rebuild)
| # | Decision | Status |
|---|---|---|
| 18 | Planner rebuilt as a proper app, screen by screen; which framework | open |
| 19 | One shared library for block times, connections, maintenance and the rules | open |
| 20 | Website data served in smaller pieces | open |

## Step 5 — Operations (decide before the jobs and monitoring build)
| # | Decision | Status |
|---|---|---|
| 21 | Capture safeguards: parsers tested on saved pages; alert when a capture looks short | open |
| 22 | Scheduled jobs: weekly scan, report drafts, backups | open |
| 23 | Monitoring: one place showing whether captures, jobs, backups and deploys worked | open |
| 24 | Ready-made data views for recurring questions (airline briefing, route profit, hub progress) | open |
| 25 | Using the $100 a month in API credits for unattended jobs, with a spending cap | open |

## Decision log
- **8 Oct 2026 · #1 Repository.** Private repository `equinox` on GitHub. Reason: the code's only copy was the live
  site, and a workspace reset wiped the working copy that morning.
- **8 Oct 2026 · Order.** Decide everything hard to undo up front, then build phase by phase with a review after each.
- **8 Oct 2026 · Tools.** Keep Supabase (standard Postgres, no lock-in) and a static host; no move to AWS or Vercel.
  Add GitHub, a domain name and an outside backup destination. Hosting and the database plan are decisions 7 and 17.
- **8 Oct 2026 · #2 How changes are made.** Every code change goes on its own branch as a pull request with what changed,
  why, test results and (once hosting is decided) a preview link. Gitesh approves by saying "merge" in chat; merging is
  what makes it live, replacing the old "ask before any deploy" step. Any change can be undone by reverting its pull
  request. Data-only changes (plan cards, to-dos, notes) still go straight into the planner. Decision-log entries for
  decisions already agreed in chat are committed directly.

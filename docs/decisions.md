# Foundation decisions

Decided one at a time, in this order. Each decision is recorded here with the date and the reason.
Status: **decided**, **open**, or **dropped**.

## Step 1 — How we work (decide now)
| # | Decision | Status |
|---|---|---|
| 1 | Private GitHub repository `equinox` as the single home for code, database changes, scripts, tests and docs | **decided** 8 Oct 2026 |
| 2 | Building through Claude Code and the repository: every change as a reviewable pull request | **decided** 8 Oct 2026 |
| 3 | A claude.ai "Equinox" project with its own instructions and reference files | **decided** 8 Oct 2026 |
| 4 | Operating manual and decision log: every rule and the reason behind each decision in one place | **decided** 8 Oct 2026 |
| 5 | A standard decision brief (background, options, growth and profit side by side, risks, recommendation) | **decided** 8 Oct 2026 |
| 6 | Backups now, and where they are kept (there are none on the current database plan) | **decided** 8 Oct 2026 |

## Step 2 — Foundations (decide before any building)
| # | Decision | Status |
|---|---|---|
| 7 | Hosting: move to Cloudflare Pages or stay on Netlify (paid tier); and our own domain name | **decided** 8 Oct 2026 |
| 8 | Preview before live: every change gets a preview link; database changes tried on a copy first | **decided** 8 Oct 2026 |
| 9 | Automatic tests on every change, blocking anything that breaks | **decided** 8 Oct 2026 |
| 10 | Documentation: README, architecture notes, what each table means | **decided** 8 Oct 2026 |
| 11 | Proper roles (owner, staff, investors, public); no shared passwords; secrets out of scripts | **decided** 8 Oct 2026 |
| 12 | Game-rules exposure: how the capture and the salary step act in the game | **decided** 8 Oct 2026 |

## Step 3 — Data model (decide before the data-model build)
| # | Decision | Status |
|---|---|---|
| 26 | Where building happens: Claude Code sessions for the rebuild, this chat for decisions (decide first, after a trial build) | open |
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
- **8 Oct 2026 · #3 Equinox project.** A claude.ai project named "Equinox" with memory connected, so everything already
  known about Equinox keeps applying. Existing Equinox chats are moved into it (Add to project) so they stay searchable;
  from then on, a new chat per kind of work: scheduling, the Saturday review, the monthly work, and building. The
  project's instructions are kept in `docs/project-instructions.md`.
- **8 Oct 2026 · #4 Operating manual.** Every rule in force lives in one file, `docs/operating-manual.md`, with the
  date it started and the reason, plus a list of retired rules so they don't come back. A copy sits in the Equinox
  project's files so every chat reads it. Where the manual and memory disagree, the manual wins; memory is background
  only. When a rule changes in any chat, that chat updates the manual (and the project copy) in the same turn and moves
  the old rule to Retired; agreed rule changes are committed directly, like decision-log entries. The project
  instructions become a short pointer to the manual. This file stays the log of foundation decisions. Reason: rules
  were spread across memory, the planner, to-do notes and the instructions; the main memory file was full and held
  old rules next to new ones, and a scheduling chat used the retired surplus method to recommend orders.
- **8 Oct 2026 · #5 Decision brief.** Every decision gets the full brief (option A), in every chat: decision and
  recommendation first, then an options table (growth, profit a week, cash at the lowest point, opportunity cost, risk,
  easy to undo), the background with sources and competition, scenarios and the risk of waiting, and what would change
  the recommendation. Each brief is saved in `docs/briefs/`. Applying an existing rule (a retime under the connection
  rule, logging an order, marking a to-do) is not a decision and gets no brief. Reason: almost every decision spends
  cash or opportunity (an aircraft's hours, a hub's slots), so each deserves full attention; leading with the answer
  keeps it readable on a phone.
- **8 Oct 2026 · #6 Backups.** A nightly copy of the whole database (every table except the key tables, plus the
  migration record; sign-in data is left out on purpose) and the site's files goes to a separate private repository,
  `equinox-backups`, run by a GitHub Action after the nightly capture. Each copy is restored into an empty database
  to prove it works, and each night's result is reported. The backup job lives in that repository (it holds the
  database secret); the code repository never holds live data. Supabase stays on the free plan; its paid plan stays
  decision #17. Reason: there were no backups at all, the whole planner is one overwritten row, and this costs
  nothing. Brief: `docs/briefs/2026-10-08-backups.md`.
- **8 Oct 2026 · #7 Hosting.** The website and planner move from Netlify to Cloudflare Pages (free plan), at our own
  domain `equinox-alliance.com` (option B), deployed from the repository: merging to `main` publishes, and every pull
  request gets a preview. The domain is registered at Cloudflare at cost (about $10.46 a year, renewing automatically);
  `equinox-alliance.pages.dev` keeps working. Netlify's $9-a-month plan is cancelled once the switch is done. Reason:
  free hosting with unlimited deploys and previews instead of 15 credits per deploy; with our own address, any future
  change of host is invisible to readers. Option D (no domain) was chosen first and changed the same evening, before
  any link was shared or the sign-in settings were changed, so the address is set only once.
  Brief: `docs/briefs/2026-10-08-hosting.md`.
- **8 Oct 2026 · #8 Preview before live.** Previews are look-only: they show the live data, but saving is switched
  off on every address except `equinox-alliance.com` (and `www`). Every pull request that changes the database is
  first rehearsed automatically: a GitHub Action restores last night's backup into a local copy, applies the change
  and reports the result on the pull request. Claude applies it to live only after "merge". The Action reads the
  backups with a read-only key that Gitesh holds as a GitHub secret. Reason: previews used the live database, so testing
  one could save into the live planner, and database changes were tried first on live. This costs nothing and needs no
  second database. A staging database or Supabase branching stays an option for the rebuild (#13, #17, #18).
  Brief: `docs/briefs/2026-10-08-previews.md`.
- **8 Oct 2026 · #9 Automatic tests.** Every pull request runs automatic checks: every planner screen opens with a
  saved day of data, key numbers match known answers (cash forecast and leases, route profit, fare plan, Review cards),
  the website pages and the schedule check work, no keys or passwords are in the code, plus the database rehearsal
  (#8). A red check blocks the merge by rule: Claude never asks for, or makes, a merge while one fails. Every bug fixed
  gets a test. Small dated samples of game data are allowed in `tests/fixtures/` for this, the one exception to "no
  game data in the code repository" (never the database, keys or sign-in data). Reason: nothing ran by itself, and 9 of
  the 11 tests depended on files lost in the reset. No lock on `main` (that needs GitHub Pro and would force every rule
  change through a pull request). Brief: `docs/briefs/2026-10-08-tests.md`.
- **8 Oct 2026 · #10 Documentation.** Five documents, kept current:
  1. a one-page map of how the pieces fit (`docs/architecture.md`, copied into the project files);
  2. a description on every database table, view and function, stored in the database, with a table guide generated
     from them (`docs/data.md`);
  3. how to run each script (`scripts/README.md`);
  4. the README as a front door;
  5. a plain-language guide to the planner's screens for Gitesh (`docs/planner-guide.md`).

  Every pull request that changes how something works updates the docs in the same pull request. The database
  rehearsal fails if a table, view or function has no description, or if the table guide no longer matches. Reason:
  nothing explained how the parts connect or what the tables hold, so every new chat or session rediscovered it, and
  #26's Claude Code sessions start with no memory. Brief: `docs/briefs/2026-10-08-documentation.md`.
- **8 Oct 2026 · #11 Roles and access.** Sign-ups are switched off in Supabase ("Allow new users to sign up"), so no
  one can create an account. The only account is Gitesh's, and a test sign-up is refused. Nothing else changes:
  - the capture key (hashed, revocable);
  - the one investor password (hashed);
  - the ingest secret for Claude's scripts;
  - the public website.

  Reason: there will never be other staff, and the only likely risk was a stray account reading every route's profit
  through the two views that skip the staff check. With sign-ups off, the only signed-in account is Gitesh's.
  Accepted as they are:
  - the plain-text ingest secret (reading it already needs database access);
  - the two views and the two internal capture steps open to any signed-in account;
  - Supabase's advisor warnings about functions callable without signing in. Each checks a key or password, or is
    public by design.

  Revisit with proper roles if a second person ever needs access, or at #14 if the planner-only version for other
  players goes ahead. Brief, with the fuller options: `docs/briefs/2026-10-08-roles.md`.
- **8 Oct 2026 · #12 Game rules.** Nothing changes. These all stay:
  - the interlines between the six airlines;
  - the capture and its salary step;
  - the world scanner and the schedule check.

  Reason: Gander is an exclusive world, where the owner sets the rules "to the extent they desire" and AirlineSim
  doesn't check game rules, only the limits built into the game (AirlineSim's page on exclusive worlds). In a public
  world they wouldn't be allowed:
  - rule 2.3 forbids co-operation between one player's holdings, and players read it as covering interlining;
  - simulogics terms §5.3 forbids scripts for "automated usage or control of the game".

  Revisit if the world's owner changes its rules, or if any of this is ever used in a public world.
  Brief: `docs/briefs/2026-10-08-game-rules.md`.
- **8 Oct 2026 · Added #26.** Whether building moves to Claude Code. Reason: from #13 the work is large and splits
  into many pull requests, and one long chat loses detail as it fills up. Decided before #13 with a full brief and one
  trial build done together. Until then, decisions and the small builds (#10 to #12) stay in this chat.

## Ideas to weigh when their decisions come up
- **A shared, planner-only version for other players** (raised 8 Oct 2026, not decided): no website, airlines across
  several worlds, often only one or two airlines per player, no AI required. To weigh at #11 (roles: separate accounts
  with their own data) and #14 (multi-world). Implication if adopted: design the data model for many players, worlds
  and small groups from the start, with Equinox as one account and the website as a layer on top. AirlineSim's
  permission would be needed before opening it to others.

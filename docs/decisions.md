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
| 26 | Where building happens: in this chat or in Claude Code sessions | **decided** 8 Oct 2026 |
| 13 | Planner data into proper tables, with a cleaner model (IDs, UTC times, each flight leg as a row) | **decided** 9 Oct 2026 |
| 14 | Multi-world, multi-group: everything keyed by world, group and airline; settings as data, not code | **decided** 9 Oct 2026 |
| 15 | History: every change kept, plus daily snapshots of fleet, departures, cash and market share | **decided** 9 Oct 2026 |
| 16 | Data growth: daily summaries kept forever, detail archived after a few months | **decided** 9 Oct 2026 |
| 17 | Database plan: when to move Supabase to its paid tier (backups, no pausing, branch databases) | **decided** 9 Oct 2026 |

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
  *Changes with #16 (9 Oct):* each night's copy goes to Cloudflare R2, kept 30 days; the month's first is kept for
  good, in R2 and as a GitHub release file in `equinox-backups`. The rehearsal reads the copies from R2. Built and
  complete on 9 Oct: `equinox-backups` #3 and #4, `Equinox` #11. Copies no longer go into git. Archives move to R2 with
  the rest of #16. Spec: `docs/specs/2026-10-09-backups-to-r2.md`.
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
  *Changes with #16 (9 Oct):* built. The rehearsal reads last night's backup from Cloudflare R2 with a read-only R2
  key: `latest.json` names the copy, and its SHA-256 is checked before use. The GitHub key (`BACKUPS_READ_TOKEN`) is
  no longer used.
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
- **8 Oct 2026 · #26 Where building happens.** Option C: building stays in the Equinox project.
  - Decisions and reviews happen in the Building chat.
  - Each sizeable build gets a written spec and goes to a helper that starts with a fresh memory. It reads
    `CLAUDE.md`, the map and the manual, writes the code, runs the checks and opens the pull request.
  - The Building chat reviews the pull request against the spec and the checks before asking for "merge".
  - A new Building chat starts at each step (4 and 5), once anything worth carrying is in the repository or the
    project files.
  - A short `CLAUDE.md` in the repository points every session to the map and the manual.

  No separate trial: the first #13 build is the trial, reviewed afterwards. Reason: the problem was memory, not tools.
  This chat already runs on the same cloud machinery as Claude Code, and the old Building chat lost detail when it
  filled. A fresh helper per build fixes that with no extra steps for Gitesh and no second place to follow. Claude Code
  sessions (option B) stay a 15-minute switch if C struggles; revisit Claude Code Projects (D) if it reaches the
  account. Brief: `docs/briefs/2026-10-08-building.md`.
- **9 Oct 2026 · #13 Planner data into proper tables.** Option C: the planner's data moves out of the one
  `planner_state` row into proper tables with a clean model now:
  - one copy of everything, stable IDs, airlines by code;
  - one row per flight leg, with times in UTC;
  - settings as data;
  - cash and loads read from the capture's tables instead of stored copies.

  The current planner keeps working unchanged through an adapter: one database function builds today's JSON from the
  tables, and one splits its saves back. Old and new are tested against each other, and the old row stays frozen as a
  fallback until #18 is done. A design document comes first for approval. The build starts once #14 to #17 are
  decided, since they shape the tables. Reason: the one-row model rebuilds flights seven different ways, keys on names,
  guesses return days and re-uploads 194 KB on every click. Today (87 aircraft, 17 days of data, one user) is the
  cheapest moment the fundamentals will ever be fixed, and the adapter avoids rewriting a planner that #18 replaces.
  Brief: `docs/briefs/2026-10-08-data-model.md`.
- **9 Oct 2026 · #14 Worlds, groups and airlines.** Option C, without accounts for other players. In the #13 tables:
  - every row carries its world, and its airline where it has one;
  - airlines are rows with a stable ID and the game's ID in that world. The same brand in two worlds is two airlines;
  - groups are rows in a world with an owner (Gitesh): ours, plus rival players' groups for competitor analysis.

  Settings are data, not code: hubs, banks, connection times, markets and fares, curfews, interline partners,
  aircraft each airline may buy, growth-rule thresholds and the website's airline descriptions.
  - **Each world's rules are data too,** because worlds differ (Gitesh, 9 Oct). That covers house rules (holdings
    allowed, low-demand and per-country limits, LCC limits, departures per airport) and game settings (demand model,
    treaties, starting capital). Gander's rules are the first set, and the planner's checks read them from there.
  - **A world can have a single airline.** Nothing may assume several: group screens, cross-airline connections and
    interline between our own airlines work with one.
  - **The capture** reads its airlines for the world it runs in and matches them by game ID. A day is complete when
    all of that world's airlines are in, not 6.
  - **On screen,** nothing changes until there's a second world; then a world switcher appears. The website shows one
    group.

  Reason: the group can grow past six in Gander (two low-demand holdings planned), worlds end or change (short-term
  worlds reset after 8 to 10 months; Gander runs as long as its owners keep it), and adding a world to tables already
  full of data would mean migrating every table and query. The shared planner-only version for other players is
  dropped, so no accounts or per-player access rules. Brief: `docs/briefs/2026-10-09-worlds-and-groups.md`.
- **9 Oct 2026 · #15 History.** Option C, built with #13:
  - **A change log:** every change to the planner's tables (aircraft, flights, routes, plans, to-dos, settings, world
    rules) is kept with old and new values, the time, and who made it (the planner, Claude, the capture or a script).
    The capture's own tables are left out, since they're dated already.
  - **Daily snapshots,** taken each night by a database job and kept for good:
    - per airline: aircraft by type, weekly departures and seats, destinations, cash, fixed costs for the next 7 days,
      average load, the day's profit;
    - per world scan: each airline's weekly departures and destinations, for market share. The summary is kept even
      when the scan's detail is cleared.
  - **Backfill** from what's kept: cash from 29 Sep, flights flown from 6 Oct, the 6 Oct scan, and the fleet from
    delivery dates.
  - **One condition on #13:** the adapter saves only the rows that actually changed.

  Reason: no history of plans, fleet or departures exists today, and history can't be made up later. With tables, a
  change is a few small rows, not a 194 KB copy. Brief: `docs/briefs/2026-10-09-history.md`.
- **9 Oct 2026 · #16 Data growth.** Option E, with one month of detail (Gitesh, 9 Oct: "after 1 month only summary
  is ok"):
  - **One row per flight** for money and loads, in place of about 9 statement lines per flight. Raw statement lines
    and raw pages are kept 14 days for checking.
  - **Summaries kept for good:** per airline per day (#15), per route per day (flights, passengers, seats, revenue,
    costs, profit), each world scan's market summary, and the income statement and balance sheet.
  - **Detail** (per-flight rows, full scan schedules, payments ahead) stays in the database until it's more than one
    full calendar month old, so the monthly report always has the whole previous month. October's detail stays until
    1 December. Then it's archived and deleted from the database.
  - **The change log** (#15, your edits) is kept 12 months, since it's small, then archived the same way.
  - **Archives and nightly backups move to Cloudflare R2:** free up to 10 GB, then $0.015 per GB a month; 30 nightly
    copies plus one a month kept. This changes #6 (backups leave the GitHub repository; GitHub keeps the code) and #8
    (the rehearsal reads last night's backup from R2 with a read-only key). The archive job checks each file before
    deleting anything.
  - **Report PDFs** move out of the database into file storage.
  - **Budget:** up to $10 a month (Gitesh). Expected cost is $0 for years.

  Reason: the bank statement is about 9 lines per flight and two thirds of all growth. At today's pace the free plan's
  500 MB would fill between February and June 2027 (the project then goes read-only), and the single backup file would
  pass GitHub's 100 MB limit around January. With one row per flight and one month of detail, the database stays small
  even at many times today's fleet. OneDrive and Google Drive were ruled out: their sign-in tokens need renewing, so
  unattended uploads quietly stop. Brief: `docs/briefs/2026-10-09-data-growth.md`.
- **9 Oct 2026 · #17 Database plan and testing saves.** Option B. Stay on Supabase's free plan. On every pull request,
  the rehearsal starts a full local Supabase (database, data API and sign-in), loads last night's backup and lets the
  planner checks save into it for real, then checks the tables. It's built as the first #13 pull request, before the
  adapter.
  - **Move to the paid plan only on a trigger,** each one meaning a brief at the next weekly review, not an automatic
    upgrade:
    - the database passes 350 MB;
    - egress passes 4 GB in a month;
    - the free plan gets paused or limited despite daily activity;
    - a feature we decide we need is paid-only.
  - **Until #23's monitoring shows it,** the first-Saturday monthly work includes a look at Supabase's usage page.

  Reason: the paid plan ($25 a month, over the $10 limit) adds space, backups, no pausing and test copies, which #16,
  our own backups, the nightly activity and the local copy already cover. Testing on a local copy catches a save bug
  before it reaches live data, which previews can't. Brief: `docs/briefs/2026-10-09-database-plan.md`.

## Found in the 9 Oct consistency check
An independent review of #1 to #16 and #26 together. Status of each point:

**Needs Gitesh's decision, before the #13 design:**
1. **Done 9 Oct:** backups moved to R2 (`equinox-backups` #3 and #4, `Equinox` #11). Report PDFs in a private bucket,
   and a second copy of archives, come with the rest of #16. As raised: **Move backups to R2 now, not with the
   rebuild.** The single backup file reaches GitHub's 50 MB warning around late
   November and its 100 MB block around December or January. The move also covers:
   - the rehearsal's scripts;
   - the test-sample maker;
   - the `backup_runs` commit field;
   - the 29 Dec key renewal to-do;
   - the old repository's history;
   - report PDFs in a private bucket the backup includes;
   - a second copy of archives outside Cloudflare.
2. **Settled 9 Oct as part of #15 and #16** (Gitesh: it's the how of decisions already made, so Claude's call):
   - the nightly snapshot and clean-ups run on Supabase's own scheduler (`pg_cron`), with a timed fallback at
     10:00 UTC marked incomplete;
   - the monthly archive runs in the nightly backup job with its existing keys, deleting only through a guarded
     function after both copies are checked;
   - every job writes to a `job_runs` table, and the planner warns on Home when one is late or failed.

   Brief: `docs/briefs/2026-10-09-jobs.md`. As raised: **Bring scheduled jobs (#22) and job monitoring (#23) forward.** #15's nightly snapshots and #16's monthly archive
   need something to run them (`pg_cron` is available but not switched on), credentials narrower than the full database
   address (#11 kept no automation account), and a warning when they don't run. The first archive is due 1 Dec.
3. **Done 9 Oct, in #17:** adapter saves are tried on a full local copy of Supabase in the checks. As raised: **Widen
   #17:** how the adapter's saves are tried before live, since previews can't save. That's either a second free
   Supabase project or the paid plan's test copies.
4. **Settled 9 Oct:** a note on the 31 Oct holdings to-do; if a 7th airline is added before #13 lands, that line is
   fixed first. As raised: **A 7th airline before #13 lands:** the old code marks a loads day complete at 6 airlines. Fix it now in one line,
   or put a note on the 31 Oct holdings to-do.

**Carried into the #13 design document** (no separate decision):
- **Who made a change (#15):** every writer (planner, Claude, capture, scripts) sets who it is for the session, since
  database roles alone can't tell them apart. The first data load runs with logging off.
- **What "a day" means:**
  - the game dates flights by local departure;
  - the evening capture crosses midnight UTC;
  - snapshots are taken when a world's capture is complete, with a timed fallback marked incomplete.
- **Backfill order:** per-flight rows and route summaries are built from the statement lines kept since 6 Oct before
  the 14-day limit starts. Lines not tied to a flight (leases, salaries, purchases, refits) get their own home.
- **One source for rule numbers:** at the #13 merge, the manual's §3, §4 and §9 figures point to the world's rules in
  the data, as §5 already does for fares.
- **World rules include #12's items:** interline between our own airlines, the salary step and the scanner, each
  allowed or not per world.
- **Access:** every new table and view follows the staff rule, with a test that a signed-out visitor reads nothing.
- **Cut-over:** `planner_state` stops accepting writes, and other chats' data-only changes (plan cards, to-dos) go to
  the new tables. Manual §1 is updated then.
- **Archives keep their table layout version,** since #18 will change the tables.

- **Dropped 9 Oct 2026 at #14: a shared, planner-only version for other players** (raised 8 Oct 2026): no
  website, airlines across several worlds, often only one or two airlines per player, no AI required. To weigh at #11 (roles: separate accounts
  with their own data) and #14 (multi-world). Implication if adopted: design the data model for many players, worlds
  and small groups from the start, with Equinox as one account and the website as a layer on top. AirlineSim's
  permission would be needed before opening it to others.

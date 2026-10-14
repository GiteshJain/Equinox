# equinox. operating manual

Every rule in force for the equinox. group, with the date it started and why. Decision #4, 8 Oct 2026.

**How to use it**
- This manual is the rulebook. Where it and memory disagree, **the manual wins**; memory is background only.
- When a rule changes in any chat, that chat updates this file (and the copy in the Equinox project's files) **in the
  same turn**, and moves the old rule to *Retired rules* at the bottom with the date it ended.
- Rule changes Gitesh agrees in chat are committed directly. Code changes still go through pull requests.
- Numbers that change often (prices per market, cabins, bank times, interline status, route lists) live in the planner;
  this manual says where. Foundation decisions are logged in `decisions.md`.

---

## Decided, not yet built
Until each is built and merged, the rules below stand as they are.
- **#13 to #17 are built** (9 to 11 Oct): the planner's data in proper tables, read and saved through an adapter until
  #18, with `planner_state` and `planner_loads` frozen as the fallback (§1); every row keyed by world and airline, with
  each world's rules as data; the change log and the daily history; one row per flight, a month of detail, then the
  monthly archive; backups and archives in Cloudflare R2; real saves tested on a local copy of last night's backup.
  The automatic jobs are in §7.
- **#18, decided 12 Oct:** the planner is rebuilt in React with TypeScript at `/planner/next/`, screen by screen, each
  checked against the old screen's numbers. Until `/planner/` switches over, the old planner and the adapter stay
  as they are.
- **#19, decided 12 Oct:** one home for each calculation. Planning rules (block times, turns, connections, maintenance)
  in one TypeScript library; figures from the capture (cash forecast, route profit, growth signals, hub progress) in
  the database. Until it's built, the figures in §3 and §4 are worked out as they are now. The weekly report is on the
  database's figures since build pull request 4 (13 Oct): each airline's money from the captured figures, with no
  surplus figure and no group totals.
- **Deferred, on a trigger:** moving the report PDFs out of the database (#16). They stay in `site_reports` until
  they reach 50 MB or the database passes 350 MB (§1). *Since 12 Oct · why (Gitesh): 1.5 MB today and about 50 MB a
  year; moving them now needs two new programs in Supabase and the backup copying private files, for no gain yet.*
- **Deferred, on a trigger:** Cloudflare's cache in front of the website's data (#20, option C). A brief in the
  Building chat when `site_public()` passes 500 KB (109 KB on 12 Oct), the website's calls pass 1,000 a day (about 40),
  or Supabase's egress passes 4 GB in a month with the website a large part of it. *Since 12 Oct · why (Gitesh): the
  call is small and the traffic light; splitting or caching it now gains nothing yet.*
Details and open points: `docs/decisions.md`.

## 1. How we work
- **The game runs while the new planner is built (#18).** Orders, scheduling, retimes and the rest go on as normal,
  and so do the Saturday review and the monthly work. Claude's data-only changes go in as usual (below).
  - **Until the switch, game changes are made in the old planner only.** The new one at `/planner/next/` is for building
    and review, so the two never save over each other.
  - **The old planner's code is frozen:** no changes at all to `web/planner/index.html`. Anything found while playing
    is fixed in the new planner. If a rule number has to change before the switch-over, the rule-number cross-check is
    removed instead.

  *Game running again since 14 Oct; code frozen since 12 Oct · why (Gitesh): the 15 A321neos were scheduled on 13 Oct,
  waiting was costing growth with the build close to done, and lifting the pause carried little risk. The code stays
  frozen so nothing is built twice.* The freeze ends when `/planner/` switches to the new planner.
- **Say first when something will take more than 5 minutes,** with roughly how long, before starting it (a helper's
  build, a long check run, a big data job). *Since 12 Oct (Gitesh).*
- **One item at a time.** Discuss a development or decision, Gitesh decides, then finish it (decided and set up)
  before raising the next. No building on Claude's initiative. *Since 7 Oct · why: keeps every build approved.*
- **Code changes are pull requests.** Each on its own branch, saying what changed, why and how it was tested. Gitesh
  approves by saying "merge"; merging is what makes it live. *Since 8 Oct (decision #2) · why: the code's only copy
  was the live site, and a workspace reset wiped the working copy.*
- **Hosting:** the website and planner are on Cloudflare Pages (free plan) at `equinox-alliance.com`, our own domain,
  registered at Cloudflare at cost and renewing automatically each October. `equinox-alliance.pages.dev` also works.
  Merging to `main` publishes them, and Cloudflare builds a preview of every pull request at a `pages.dev` address.
  The schedule check is a Pages Function (`functions/api/game-schedule.js`). *Since 8 Oct (#7) · why: free, with
  unlimited deploys and previews; our own address survives any future change of host.*
  - **The build:** Cloudflare runs `if [ -f package.json ]; then npm ci && npm run build; fi` before it publishes,
    output folder `web`, Node 22 (`.nvmrc`). It builds the new planner (`app/planner/`) into `web/app/`, served under
    `/app/` with its page at `/planner/next/`. A build that fails leaves the last good version live. *Since 12 Oct (#18,
    build pull request 1) · why: the new planner is a React app that has to be built; the checks run the same build.*
- **Supabase stays on the free plan.** We move to the paid plan ($25 a month) only on a trigger, and each trigger means a
  brief at the next weekly review, not an automatic upgrade:
  - the database passes 350 MB;
  - egress passes 4 GB in a month;
  - the free plan gets paused or limited despite daily activity;
  - a feature we decide we need is paid-only.

  The report PDFs move out of the database into private file storage when they reach 50 MB, or with the 350 MB
  trigger, whichever comes first (#16, deferred 12 Oct). The monthly usage check (§7) looks at their size too.

  *Since 9 Oct (#17) · why: our own backups, #16's small database, daily activity and the local test copy already cover
  what the paid plan adds, and it's over the $10-a-month limit.*
- **Preview before live:** previews are look-only. They show the live data, but saving works only on
  `equinox-alliance.com`; anywhere else the planner says "preview · not saved". Every pull request that changes the
  database is rehearsed by the *Database rehearsal* check on a copy of last night's backup, which posts the result on
  the pull request. Claude asks for "merge" only once it passes. After the merge, Claude applies the change to live and
  sets the live migration record to the file's version, so the repository and live keep the same list. A change that
  removes something (dropping a table, rule or column) can't be applied from the chat, because Supabase's approval
  never reaches Gitesh. He runs that file in Supabase's SQL editor, and Claude then records and checks it. *Since 9 Oct
  · why: the loads fix's two removed access rules were cancelled three times from the chat.* **If applying any change
  from the chat comes back "cancelled", Claude tries once more, then gives Gitesh the file's link to run in the SQL
  editor the same way.** *Since 12 Oct · why: `planner_save()`, which only adds a function, was cancelled twice.*
  *Since 8 Oct (#8) · why: previews used the live database, so testing one could save into the live planner; database
  changes were tried first on live.*
- **Automatic checks:** every pull request runs *Checks* (no keys or passwords; the schedule check on a saved game page;
  the new planner's install, type check, lint, unit tests and build; the planning library's cases and its optimiser
  against plan.py's saved answer; the weekly report end to end on a small sample, its money from the figures; every
  planner screen, look-only previews and the planner's key numbers against saved answers;
  every website page and the new planner's sign-in at `/planner/next/`; the old planner's rule numbers against
  `settings` and `world_rules`). When the database, either planner or the library changes, the *Database rehearsal*
  also generates the new planner's types again from the copy (they must match the committed
  `app/planner/src/db/types.ts`), has the new planner sign in, read and save on the copy, checks the library's
  Tails and Hubs figures against the old planner's on the same copy, and the captured figures against its Review and
  Check (#19).
  **Claude never asks for, or makes, a merge while any check is red.** Every bug fixed gets a test. When a change is
  meant to move a number, the pull request updates the saved answers and says which moved and why. How to run and
  update them: `tests/README.md`. *Since 8 Oct (#9) · why: nothing ran by itself, and 9 of 11 tests couldn't run.*
- **Documentation stays current:** every pull request that changes how something works updates the documents in the
  same pull request:
  - the map, `docs/architecture.md` (and its project copy, `claude/architecture.md`);
  - the planner guide, `docs/planner-guide.md`;
  - `scripts/README.md`;
  - `database/current/`, for a changed function or view;
  - the README.

  Every new table, view or function gets a description in its migration. The database rehearsal fails without one, and
  regenerates and checks the table guide, `docs/data.md`. A new chat or session starts from the map.
  *Since 8 Oct (#10) · why: nothing explained how the parts connect, so every new chat rediscovered it.*
- **Big builds go to a fresh helper.** Decisions and reviews stay in the Building chat. Each sizeable build gets a
  written spec (what, why, which files, what the checks should show) and goes to a helper that starts with a fresh
  memory: it reads `CLAUDE.md`, the map and the manual, writes the code, runs the checks and opens the pull request.
  Claude reviews it against the spec and the checks before asking for "merge". Small fixes can be made directly in the
  chat. A new Building chat starts at each step of the decision list, once anything worth carrying is in the
  repository or the project files. *Since 8 Oct (#26) · why: the old Building chat lost detail as it filled; a clean
  memory per build fixes that with no extra steps.*
- **Data-only changes go straight in, to the tables:** plan cards, to-dos, notes, logs. Either through
  `planner_item_put(section, key, value)` (or `planner_item_delete(section, key)`), in the planner's own JSON shape,
  plan-card and frequency times local as the planner shows them; or plain SQL on the tables. Either way the same call
  starts with `select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', '<chat>', true);`
  so the change log names the chat (design §6). `planner_state` and `planner_loads` are frozen and refuse every write;
  the planner shows a change the next time it loads. *Since 8 Oct (#2); to the tables since 10 Oct (#13, pull request
  9) · why: the planner reads the tables now, so a change to the old row would never be seen.*
- **Rule numbers have one source:** the database's `settings` (our own choices, with an airline's override where it
  has one) and `world_rules` (Gander's house rules, game settings and #12's permissions). The figures in §3, §4, §5 and
  §9 name their row; a rule change updates the row and this manual together. Until #18 the old planner also keeps
  copies in its code, and the automatic checks fail if the two ever differ (`tests/rule_numbers_test.py`), so a
  change to one of those needs a planner pull request too. *Since 10 Oct (#13, pull request 9; design §11, choice 3) ·
  why: the same number lived in the manual, the planner and the scripts, and drifted (the connection buffer, 9 Oct).*
- **To-do board:** anything Gitesh needs to check or do goes on the planner's To-do board; Claude marks it resolved when
  he reports back. *Since 30 Sep.*
- **One-week aircraft checks are Gitesh's,** done in the game (the flights really run as scheduled, no issues). Claude
  never marks them checked. *Since 2 Oct.*
- **Every decision gets the full brief** (format in `docs/briefs/README.md`): decision and recommendation first; then
  an options table with growth, profit a week, cash at the lowest point, opportunity cost, risk and whether it's easy to
  undo; then the background with sources and competition, scenarios and the risk of waiting, and what would change the
  recommendation. Save it in `docs/briefs/`. Applying an existing rule is not a decision and gets no brief.
  *Since 8 Oct (#5) · why: almost every decision spends cash or opportunity, so each deserves full attention.*
- **Facts first.** Pull the numbers from the database and captures before advising, and say where they came from.
  Never guess a current fact. *Since 8 Oct.*
- **No keys or passwords** in the repository, files or chat. Keys live in the database or as GitHub secrets.
  *Since 8 Oct.*
- **No one can sign up:** sign-ups are off in Supabase, and the only account is Gitesh's. Giving someone access means
  turning them on briefly, or inviting from Supabase's dashboard, and then proper roles (see #11's brief).
  *Since 8 Oct (#11) · why: there will never be other staff; a stray account could read every route's profit.*
- **Test samples are the one exception to "no game data in the code repository":** small, dated samples of game data
  in `tests/fixtures/` for the automatic checks. Never the database, keys or sign-in data. *Since 8 Oct (#9) · why:
  checks need fixed data to compare exact answers.*
- **Opus for everything,** business decisions included. *Since 8 Oct.*
- **One chat per kind of work,** all inside the Equinox project. *Since 8 Oct (#3).* If Gitesh asks a question that
  belongs to another chat, say which chat in one line and don't answer it there. *Since 8 Oct · why: each chat keeps
  its own thread of context.*

  | Chat | Covers |
  |---|---|
  | Scheduling | Aircraft that have arrived, plan cards, retimes, route choices, what and when to order, interline requests |
  | Saturday review | Weekly report, connection audit, newsroom roundup, fare plan, the weekly review |
  | Monthly | Monthly report, gander monthly, strategy (bases, focus cities, holdings, long-term direction) |
  | Building | Planner, website, database, capture, repository, foundation decisions, how the tools calculate things |
- **Each airline is its own business:** no group totals; finance looks at each airline's profit and growth.
  *Since early Oct.*

## 2. Group strategy
- **Roles:** each airline owns its home region, and one airline owns each intercontinental flow. Oceania goes via KUL,
  except China–Oceania (China Eastern direct) and US–Oceania (Pan Am). *Since 29 Sep.*
- **One airline per city pair.** No two of our airlines fly the same pair. Pairs within one airline go under the
  first-listed hub (DEL–BOM under DEL). Across airlines, by country pair: US/UK–India → Kingfisher; US–UK, Europe or
  China → Pan Am; UK–Europe, China or Malaysia → Virgin; Europe or India–China → China Eastern; Malaysia → Malaysia.
  Virgin doesn't fly JFK or Delhi. When merging Gitesh's route lists, add missing lanes only; never change ownership.
  *Since 23 and 26 Sep · why: our airlines shouldn't compete with each other.*
- **Destination shape:** in time, fly every route a real airline flies from each hub and focus city. Plan as if money
  isn't the limit, and grow at the group's own pace. *Since 23 and 29 Sep.*
- **Scale models** (each airline's counterpart in the Airbus world): Virgin → British Airways, Pan Am → Pan Am,
  China Eastern → China Eastern, Malaysia → Singapore Airlines; Kingfisher → Inter Connect (Ellinikon world). Ryanair
  covers the Europe the others can't. *Since 29 Sep.*
- **Malaysia:** make KUL a world transfer hub; build the Asian feeder network before any long-haul. *Since 29 Sep ·
  why: long-haul would have no loads without the feed.*
- **Kingfisher:** India is open; aim to capture all of it. *Since 2 Oct.*

**Bases** (main hub first):

| Airline | Hubs | Focus cities | Next |
|---|---|---|---|
| Pan Am | JFK | ORD, SFO, SEA | Dallas, then LAX (both on hold under hubs-first) |
| Kingfisher | Delhi | Hyderabad, Bengaluru, Chennai, Kolkata (on hold) | Mumbai |
| Ryanair | Paris CDG, Amsterdam (all bases are focus) | — | Barcelona, then Milan and Munich; no eastern base for now |
| Virgin Atlantic | Gatwick, Manchester | Edinburgh | — |
| China Eastern | Shanghai PVG, Xi'an, Kunming | Beijing Daxing, Shenzhen | — |
| Malaysia | KUL | — | — |

*Base roles from 29 Sep, Kingfisher from 2 Oct, holds from 5 Oct.*

## 3. Fleet and orders
- **Fleet families:** the five legacy airlines fly the A320 family (A320neo, A321neo, A321XLR), the A350 only where
  range demands it, and the E195-E2: three families at most, no 787, CRJ or A319. Ryanair flies the A321neo and E195
  only. *Since 28 Sep · why: three maintenance families are free; a fourth costs 15% more maintenance.*
- **Reach first:** new aircraft go into the short and medium-haul narrowbody network; long-haul comes later.
  Kingfisher's two Delhi–JFK A350s stay as they are. *Since 28 Sep.*
- **An order is just the aircraft.** Routes and cabin are decided when it arrives; the cabin is fitted after delivery.
  No plan card at order time. *Since 2 Oct.*
- **Who orders:** Claude recommends what to order; Gitesh orders in the game and says so; Claude logs it. *Since 2 Oct.*
- **When an airline can order: the cash forecast.** Planner → Review → "Cash, next 14 days": captured cash, plus flight
  profit from the last day's bank statement, minus every scheduled lease payment and week-end closing (the weekly salary
  payment). An order is safe when **0.5M stays in hand at the lowest point** after it (`settings.order_cushion`).
  Prices include the cabin.
  *Since 7 Oct · why: the old surplus rule ignored flight income during the week; on 7 Oct it said Kingfisher couldn't
  afford an A321neo when its real lowest point was 6.29M.*
  - **The order's own lease counts:** weekly, from 7 days after it arrives, taken as arriving the day it's ordered (the
    most it could cost inside the 14 days). Its income and its crew's pay are left out; the profit it makes over its
    crew pay is extra buffer. Several orders are tested together, each with its lease. A type never leased yet is
    taken at 10% of its price a week (`settings.lease_estimate_pct`). *Since 8 Oct · why: the cushion alone covered
    only one order's lease.*
  - Planned refits are not in the forecast; say so with each recommendation.
  - If an airline hasn't been captured, get the capture first. Never use the surplus figure.
  - The forecast is worked out by `cash_forecast()` in the database (several orders tested together with `p_orders`);
    the old planner's Review screen shows the same figures until the switch (#19, build pull request 3).
- **Order rotation:** each airline's orders rotate big market → more frequency → smaller feeders, kept flexible.
  *Since 2 Oct.*
- **Growth matters as much as profit:** every airline's batch includes new markets, not only more flights on proven
  routes. *Since 8 Oct.*
- **Hubs first:** until an airline's main hub reaches **750 weekly departures**, every new aircraft goes to the main hub.
  Any other base, whether new or already open (second hubs and focus cities alike), gets an aircraft only to fly
  contested routes: a rival with over 250 departures a week at that base, or over 2 a day on the route itself. A base
  that is contested for one route (Manchester for Amsterdam, say) doesn't open its other routes. Ryanair is exempt.
  Contested as of 5 Oct: Mumbai (Gulf routes), Manchester (Amsterdam), Daxing (Chengdu), Dallas if opening with ORD,
  Atlanta or Phoenix, SFO and SEA. The numbers are `settings.hub_first_departures` (750),
  `contested_rival_weekly` (250), `contested_rival_daily` (2) and Ryanair's `hub_first_exempt`; the growth signals'
  thresholds are the `growth_*` and `pattern_*` settings. *Since 5 Oct, confirmed 8 Oct as the only test for opening a
  new base; extended to bases already open 11 Oct · why: Gitesh: grow the main hub before any other base. G-AADU was
  nearly planned at Manchester on uncontested routes, which the old wording allowed.*

## 4. Scheduling
- **How it runs:** once aircraft have arrived, one airline at a time. Claude gives the background (loads, money,
  network, competition) and options; we decide the routes together; Claude writes the plan cards; Gitesh schedules in
  the game and presses File; the planner checks each card against the game. *Since 2 Oct.*
- **The planner mirrors the game.** Routes and aircraft enter the planner only once they're in the game; plans live on
  plan cards. *Since Sep.*
- **Maximise connections at both ends:** an arrival lands at least the airport's minimum connection time
  (`world_airports.mct_min`) before the departures it feeds, with no extra margin (`settings.connection_buffer_min`,
  0), and departures leave within 8 hours of the arrivals they collect (`connection_max_wait_h`). Every new plan card
  and every retime is checked at both ends. *Since 6 Oct, updated 7 Oct; margin dropped 9 Oct · why: Gitesh: as long as
  it's over the minimum connection time, it's good.*
- **Use each aircraft as much as possible.** No fixed floor on flying hours; options show hours a day next to
  connections, and check whether one more short rotation fits. *Since 7 Oct.*
- **Night slots are fine.** *Since 27 Sep · why: the game's demand ignores time of day, and captures show night
  departures sell as well as daytime ones.*
- **Maintenance at or above 100% is firm** (aim for 105%; `settings.maintenance_min_pct` and
  `maintenance_target_pct`). *Since 28 Sep.*
- **Turns:** the game's turnaround plus a 10–15 minute margin (`settings.turn_margin_min`, 10); 5 minutes is tolerated
  only on the busiest aircraft where 15 won't fit. *Since 25 Sep · why: room for delays and slot availability.*
- **A second daily** on a route sits at least 3 hours from the existing flight (`settings.second_daily_gap_h`). *Date
  not recorded.*
- **Block time** = 25 minutes (`settings.block_allowance_min`) + distance ÷ speed: A321neo and XLR 840 km/h, E195 831,
  A320neo 839, A350 911 (`aircraft_types.cruise_kmh`).
- **Three banks per hub;** bank times are in `airline_bases.bank_times` (the planner's Reference → hubs), the bank
  windows in `settings.bank_arrival_window_min` and `bank_departure_window_min`. Connections come first; an unbanked
  flight still earns. *Since 23 Sep.*
- **New airlines launch short-haul,** one daily rotation per route, breadth first. *Since 26 Sep.*
- **Everything flies direct:** no tag (fifth or eighth freedom) flights. *Since 20 Sep.*
- **Ryanair stays inside the game's EU zone:** EU-27, the UK, Norway, Switzerland and Iceland. Turkey, Morocco, the
  Balkans and long-haul are out. *Since 25 Sep.*
- **London:** for airlines other than Virgin, new London routes go to Gatwick before Heathrow; existing Heathrow flights
  stay. *Since 26 and 28 Sep.*

## 5. Cabins and fares
- **Cabin follows the market default,** whatever the aircraft. Defaults per market are in the planner
  (Reference → markets). A refit costs about 0.2M with no time out of service. *Since 2 Oct.*
- **Fares:** new routes launch at 100% of the standard fare in both cabins; Ryanair 85%, economy only
  (`settings.fare_launch_pct`, with Ryanair's override). Weak routes get cut rather than launched cheap. Prices per
  market are in the planner (`markets`). *Since 20–21 Sep · why: every lane ran full at lower fares, and launching low
  then raising across 50 routes is too much work.*
- **Fare changes are occasional tests** through the planner's fare plan, reviewed together once a week at the Saturday
  review. They never appear in Needs attention. *Since 28 Sep and 8 Oct.*

## 6. Interline
- **Our airlines interline with each other.**
- **Outside partners:** for each major airport the group flies to that isn't our base, an interline with that country's
  major airline, but only in countries with a real domestic market or that are the gateway to a region we can't fly to
  directly. *Since 25 and 28 Sep.*
- **Where not to:** nowhere in Ryanair's Europe zone; for Pan Am, not in Canada, Mexico, the Caribbean or Central
  America; each airline has its own skip list (in the planner's Interline tab). *Since 26 Sep.*
- **Gulf hub carriers are rivals:** decline their requests. *Since 5 Oct · why: they would carry our passengers through
  Dubai against Kingfisher and Malaysia.*

## 7. Recurring work
- **Every evening:** Gitesh presses "Capture all airlines" in the game. It captures loads, finances and payments, and
  nothing else, straight into the tables (`game_flights` and the rest); a day's loads count as complete once every
  active airline has been captured for it. Loads are typed in by hand (Review → Manual entry) only if a capture fails.
  *Since 7–8 Oct; salaries taken out 10 Oct; into the tables only since 10 Oct (#13, pull request 9).*
- **Salaries:** a separate script, "Salaries: this airline", which Gitesh runs by hand when he chooses. It changes only
  the airline he's on, setting each position to 10% above the country average. *Since 10 Oct · why: Gitesh suspects the
  nightly adjustment of all six airlines was inflating salaries.*
- **Every Saturday:**
  - the weekly report: a PDF briefing written for a CEO, no fixed template. It covers competition by market (for the
    group and each airline), risks, opportunities, our plan and progress, route profit, growth signals and fare-plan
    results;
  - the connection audit across all hubs (valid connections, near misses, and retimes of 10 minutes or less);
  - one newsroom roundup of the week's new routes;
  - the weekly review together, including the fare plan.

  *Since 5–8 Oct.*
- **Every night, after the capture:** an automatic backup copies the database and the site's files, restores the copy
  to prove it works, uploads it to Cloudflare R2 and reports the result. Each night's copy is kept 30 days. The
  month's first is kept for good, in R2 and as a file on a GitHub release in the private repository `equinox-backups`,
  where the backup job lives. Copies no longer go into git. Each run's R2 key is recorded in `backup_runs`. The
  database rehearsal reads last night's copy from R2 with a read-only key. Live data never goes into the
  code repository (small test samples aside, see §1). The planner warns on Home if there's no good copy from the last
  30 hours. To recover, see the README in `equinox-backups`. *Copies in R2 since 9 Oct (#16) · why: the single backup
  file would pass GitHub's 50 MB warning around late November and its 100 MB limit around December or January.*
  *Since 8 Oct (#6) · why: there were no backups, and the planner is one row.*
- **Every day, inside the database (Supabase's scheduler, `pg_cron`; no key leaves the database):**
  - **10:00 UTC, the snapshot fallback:** if no complete capture took the daily snapshot for the evening just ended, the
    job takes it anyway, marked incomplete, with each airline's cash from its latest balance; it also fills any day
    since the history began that has none.
  - **10:20 UTC, the clean-ups:** raw capture pages older than 14 days are deleted. Statement lines older than 14 days
    are deleted only while `settings.statement_cleanup_enabled` is true, and only once every one is in `game_flights`
    or `game_payments`. It ships switched off; the Building chat switches it on after checking the per-flight backfill
    on live.
- **Every night, after the backup: the monthly archive.** Detail more than one full calendar month old (each flight,
  payments ahead, world-scan schedules and airport pages; the change log after 12 months) is exported to R2 and to
  that month's release in `equinox-backups`, both copies are read back and checked, and only then deleted, through a
  guarded database function that refuses anything else. Only the first night on or after the 1st has work to do
  (October leaves on 1 December); a month that fails is tried again the next night. The daily history (`airline_days`,
  `route_days`) and the scan summaries stay for good.
- **Every job writes a row to `job_runs`,** and the planner's Home warns when the last good backup is more than 30 hours
  old, the latest snapshot is more than 30 hours old (or the 10:00 UTC job hasn't run for 30 hours: the scheduler may
  have stopped; restart it from Supabase's settings), the month's archive hasn't run by the 3rd, or any job's last run
  failed. *Since 11 Oct (#13 pull request 7, the jobs brief) · why: the daily record needs a fallback, the capture
  tables their clean-ups, #16 its archive before 1 Dec, and a job that fails must be seen.*
- **First Saturday of the month:** the monthly report (published to the investor library), gander monthly, the monthly
  strategy session. *Since 8 Oct.* Also, until #23's monitoring shows it: a look at Supabase's usage page (database
  size, egress, and the report PDFs' size in `site_reports`) against the triggers in §1, and the size of
  `site_public()` and the website's calls a day against #20's triggers (*Decided, not yet built*). *Since 9 Oct (#17);
  the PDFs and the website since 12 Oct.*

## 8. Writing, website and newsroom
- **Writing for Gitesh:** he mostly reads on his phone. Lead with the answer, keep it short, and use tables for options
  and comparisons.
- **Newsroom posts read like a real airline's:** no cabins, bank timings or other internal detail, and no references to
  the game. One weekly roundup of new routes, not a post per aircraft. *Since 5 and 7 Oct.*
- **gander monthly** covers the whole Gander world impartially, without claiming to be impartial. It is marked as made
  by AI and published openly on the website. *Since 5–6 Oct.*
- **Brand:** "equinox." — lowercase, with the full stop. Real airline names and logos, with a fan-project disclaimer in
  the first-visit window, the footer and the About page.
- **Investor relations** is locked behind an investor password (separate from staff login); reports download freely
  once inside. *Since 6 Oct.*

## 9. Game rules and mechanics (Gander)
Each figure here is a `world_rules` row for Gander (§1, one source): the house rules (kind `house`), the mechanics
(kind `game`) and #12's permissions (kind `permission`).

**House rules**
- Up to 8 holdings per player: 6, plus 2 in low-demand countries. At most 1 US, 1 China, 2 EU and 1 LCC. Holdings fly
  from their founding country (LCCs exempt); hubs can move within it. 45M starting capital per holding.
  (`holdings_max`, `low_demand_holdings`, `holdings_per_country`, `lcc_holdings_max`, `starting_capital`.)
- 5,000 departures a week per player per airport, rising to 8,000 after three months (`departures_per_airport_week`).
- At least 5 minutes between departures on the same route (`same_route_gap_min`).
- Fare floor: 60% of standard wherever another player flies the route, including our own airlines (`fare_floor_pct`).
- At most 30 fifth/eighth-freedom routes per airline; alliances capped at 30 (`freedom_routes_max`, `alliance_max`).
- A newly claimed brand must have a route flying within 14 days (`new_brand_route_days`).

**Mechanics** (`demand_model`, `time_zones`, `subsidiaries_work`; the world's traffic rights, `treaties`, are still to
be copied from the game's settings page)
- Demand is per airport, not per city: Heathrow, Gatwick and Stansted are separate markets.
- Departure time of day doesn't affect demand; it matters only for connections.
- Passengers book each direction separately; no location-based demand.
- Maintenance need depends on take-offs and landings as well as hours, and can be done at any airport with a long
  enough ground gap.
- An aircraft's first lease payment falls 7 days after it arrives, then weekly; an order needs only its price up front.
  Weekly leases seen in the captures: A321neo about 0.24M, XLR 0.29M, E195 0.18M, A350 0.72M.
- The week-end closing is the airline's weekly salary payment. The game's advance figure can lag when staff are added:
  Virgin's 8 Oct closing was listed at 0.56M and paid at 0.71M.
- Aircraft fly to their first departure automatically once scheduled.
- The game runs standard time all year: JFK −5, London 0, Paris and Amsterdam +1, Delhi +5:30.
- Subsidiaries don't work with the game's demand model, so we don't use them.
- **Gander is an exclusive world:** its owner sets the rules, and AirlineSim only enforces the limits built into the
  game. That's why the interlines between our six airlines, the capture and the salary script, and the world scanner are
  fine here (#12; the `permission` rows `interline_own_airlines`, `capture_salary_step`, `world_scanner`,
  `schedule_check`). In a public world they wouldn't be: rule 2.3 forbids co-operation between one player's holdings,
  and terms §5.3 forbids automated use. Read #12's brief before copying any of this to another world.

---

## Retired rules
Kept so they don't come back. Newest first.

| Ended | Old rule | Replaced by |
|---|---|---|
| 14 Oct | The game is paused until the new planner is done: the evening capture is the only game task (no scheduling, orders, retimes, fare changes, interline actions or salary runs), the Saturday review and monthly work wait, and Claude makes no data-only changes | The game runs again; game changes go through the old planner only until the switch, and its code stays frozen (§1). Why: Gitesh, once the 15 A321neos were flying, and with waiting costing growth at little risk |
| 11 Oct | Hubs first covers only opening a new hub; a base already open can grow on any route | Every new aircraft goes to the main hub until it reaches 750 weekly departures; other bases, open or new, only for contested routes (§3). Why: Gitesh, when G-AADU was nearly planned at Manchester on uncontested routes |
| 10 Oct | Data-only changes (plan cards, to-dos, notes, logs) go into `planner_state` | Into the tables, through `planner_item_put()` or plain SQL after the `equinox.actor` line (§1). Why: the switch-over (#13, pull request 9) froze `planner_state`; the planner reads the tables |
| 10 Oct | Rule numbers live in the planner (Reference, growth rules) and in this manual | One source: `settings` and `world_rules`, checked against the old planner's code (§1). Why: copies drifted |
| 10 Oct | The nightly capture sets every airline's salaries to 10% above the country average | A separate salary script, run by hand on one airline at a time (§7). Why: Gitesh suspects the nightly run on all six was inflating salaries |
| 9 Oct | A connection needs the minimum connection time + 10 minutes | The minimum connection time alone (§4). Why: the extra 10 minutes isn't needed; the planner already counted without it, while the manual and the optimiser added it |
| 9 Oct | Backups are kept as commits in the private repository `equinox-backups`, and the rehearsal reads them there with a GitHub key | Copies in Cloudflare R2: nightly for 30 days, monthly for good, plus a monthly GitHub release (§7, #16). Why: the single backup file was heading for GitHub's size limits |
| 8 Oct | No game data at all in the code repository | Small dated test samples allowed in `tests/fixtures/` (#9) |
| 8 Oct | Ask before every Netlify deploy | Pull requests; "merge" makes it live |
| 8 Oct | Fable for business decisions | Opus for everything |
| 8 Oct | Weekly report and roundup on Mondays | Saturdays |
| 8 Oct | Monthly staff-salary review | The nightly capture sets salaries to 10% above the country average |
| 8 Oct | Monthly Netlify credits check | The site moved to Cloudflare's free plan (#7) |
| 8 Oct | A new base waits until there's money for 2–3 aircraft | Hubs first: the main hub reaches 750 weekly departures (§3) |
| 7 Oct | Surplus = cash − fixed costs due in the next 7 days | The cash forecast (§3) |
| 7 Oct | Every aircraft flies at least 10 hours a day | As much as possible, no floor (§4) |
| 7 Oct | A newsroom post per aircraft | One weekly roundup |
| 7 Oct | Daily load screenshots typed in by Claude | The nightly capture |
| 2 Oct | The spending order and fill-before-spread | Order rotation (§3), then hubs first (5 Oct) |
| 1 Oct | Keep a 15% reserve of fleet value | The surplus rule, itself retired 7 Oct |
| 28 Sep | CRJ 700, A319 and 787 in the fleet plans | Three families, no CRJ, A319 or 787 (§3) |
| 26 Sep | Concentrate on hub airports | Demand is per airport (§9) |
| 26 Sep | Move Pan Am's and Kingfisher's Heathrow flights to Gatwick | Heathrow stays; new London routes go to Gatwick first |
| 25 Sep | A fixed 4-hour maintenance gap | Maintenance depends on flights as well as hours (§9) |
| 20 Sep | Contested and uncontested fare tiers | One flat fare per market (§5) |
| 20 Sep | Tag routes using freedom slots | Everything direct (§4) |
| Sep | One aircraft per route | Several aircraft and rotations where demand needs them |

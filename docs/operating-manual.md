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

## 1. How we work
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
- **Preview before live:** previews are look-only. They show the live data, but saving works only on
  `equinox-alliance.com`; anywhere else the planner says "preview · not saved". Every pull request that changes the
  database is rehearsed by the *Database rehearsal* check on a copy of last night's backup, which posts the result on
  the pull request. Claude asks for "merge" only once it passes. After the merge, Claude applies the change to live and
  sets the live migration record to the file's version, so the repository and live keep the same list.
  *Since 8 Oct (#8) · why: previews used the live database, so testing one could save into the live planner; database
  changes were tried first on live.*
- **Data-only changes go straight in:** plan cards, to-dos, notes, logs. *Since 8 Oct (#2).*
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
  payment). An order is safe when **0.5M stays in hand at the lowest point** after it. Prices include the cabin.
  *Since 7 Oct · why: the old surplus rule ignored flight income during the week; on 7 Oct it said Kingfisher couldn't
  afford an A321neo when its real lowest point was 6.29M.*
  - **The order's own lease counts:** weekly, from 7 days after it arrives, taken as arriving the day it's ordered (the
    most it could cost inside the 14 days). Its income and its crew's pay are left out; the profit it makes over its
    crew pay is extra buffer. Several orders are tested together, each with its lease. *Since 8 Oct · why: the cushion
    alone covered only one order's lease.*
  - Planned refits are not in the forecast; say so with each recommendation.
  - If an airline hasn't been captured, get the capture first. Never use the surplus figure.
- **Order rotation:** each airline's orders rotate big market → more frequency → smaller feeders, kept flexible.
  *Since 2 Oct.*
- **Growth matters as much as profit:** every airline's batch includes new markets, not only more flights on proven
  routes. *Since 8 Oct.*
- **Hubs first:** each main hub reaches **750 weekly departures** before the airline opens a new hub, unless the new
  hub is contested: a rival with over 250 departures a week there, or over 2 a day on a route we'd open with. Ryanair is
  exempt. Contested as of 5 Oct: Mumbai (Gulf routes), Manchester (Amsterdam), Daxing (Chengdu), Dallas if opening with ORD,
  Atlanta or Phoenix, SFO and SEA. *Since 5 Oct, confirmed 8 Oct as the only test for opening a new base · settings in
  the planner (growth rules).*

## 4. Scheduling
- **How it runs:** once aircraft have arrived, one airline at a time. Claude gives the background (loads, money,
  network, competition) and options; we decide the routes together; Claude writes the plan cards; Gitesh schedules in
  the game and presses File; the planner checks each card against the game. *Since 2 Oct.*
- **The planner mirrors the game.** Routes and aircraft enter the planner only once they're in the game; plans live on
  plan cards. *Since Sep.*
- **Maximise connections at both ends:** an arrival lands at least the airport's minimum connection time + 10 minutes
  before the departures it feeds, and departures leave within 8 hours of the arrivals they collect. Every new plan card
  and every retime is checked at both ends. *Since 6 Oct, updated 7 Oct.*
- **Use each aircraft as much as possible.** No fixed floor on flying hours; options show hours a day next to
  connections, and check whether one more short rotation fits. *Since 7 Oct.*
- **Night slots are fine.** *Since 27 Sep · why: the game's demand ignores time of day, and captures show night
  departures sell as well as daytime ones.*
- **Maintenance at or above 100% is firm** (aim for 105%). *Since 28 Sep.*
- **Turns:** the game's turnaround plus a 10–15 minute margin; 5 minutes is tolerated only on the busiest aircraft where
  15 won't fit. *Since 25 Sep · why: room for delays and slot availability.*
- **A second daily** on a route sits at least 3 hours from the existing flight. *Date not recorded.*
- **Block time** = 25 minutes + distance ÷ speed: A321neo and XLR 840 km/h, E195 831, A320neo 839, A350 911.
- **Three banks per hub;** bank times are in the planner (Reference → hubs). Connections come first; an unbanked flight
  still earns. *Since 23 Sep.*
- **New airlines launch short-haul,** one daily rotation per route, breadth first. *Since 26 Sep.*
- **Everything flies direct:** no tag (fifth or eighth freedom) flights. *Since 20 Sep.*
- **Ryanair stays inside the game's EU zone:** EU-27, the UK, Norway, Switzerland and Iceland. Turkey, Morocco, the
  Balkans and long-haul are out. *Since 25 Sep.*
- **London:** for airlines other than Virgin, new London routes go to Gatwick before Heathrow; existing Heathrow flights
  stay. *Since 26 and 28 Sep.*

## 5. Cabins and fares
- **Cabin follows the market default,** whatever the aircraft. Defaults per market are in the planner
  (Reference → markets). A refit costs about 0.2M with no time out of service. *Since 2 Oct.*
- **Fares:** new routes launch at 100% of the standard fare in both cabins; Ryanair 85%, economy only. Weak routes get
  cut rather than launched cheap. Prices per market are in the planner. *Since 20–21 Sep · why: every lane ran full at
  lower fares, and launching low then raising across 50 routes is too much work.*
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
  sets staff salaries to 10% above the country average. Loads are typed in by hand only if a capture fails.
  *Since 7–8 Oct.*
- **Every Saturday:**
  - the weekly report: a PDF briefing written for a CEO, no fixed template. It covers competition by market (for the
    group and each airline), risks, opportunities, our plan and progress, route profit, growth signals and fare-plan
    results;
  - the connection audit across all hubs (valid connections, near misses, and retimes of 10 minutes or less);
  - one newsroom roundup of the week's new routes;
  - the weekly review together, including the fare plan.

  *Since 5–8 Oct.*
- **Every night, after the capture:** an automatic backup copies the database and the site's files to the private
  repository `equinox-backups`, restores the copy to prove it works, and reports the result. Live data never goes into
  the code repository (small test samples aside, see §1). The planner warns on Home if there's no good copy from the last 30 hours. To recover, see the
  README in `equinox-backups`. *Since 8 Oct (#6) · why: there were no backups, and the planner is one row.*
- **First Saturday of the month:** the monthly report (published to the investor library), gander monthly, the monthly
  strategy session. *Since 8 Oct.*

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
**House rules**
- Up to 8 holdings per player: 6, plus 2 in low-demand countries. At most 1 US, 1 China, 2 EU and 1 LCC. Holdings fly
  from their founding country (LCCs exempt); hubs can move within it. 45M starting capital per holding.
- 5,000 departures a week per player per airport, rising to 8,000 after three months.
- At least 5 minutes between departures on the same route.
- Fare floor: 60% of standard wherever another player flies the route, including our own airlines.
- At most 30 fifth/eighth-freedom routes per airline; alliances capped at 30.
- A newly claimed brand must have a route flying within 14 days.

**Mechanics**
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

---

## Retired rules
Kept so they don't come back. Newest first.

| Ended | Old rule | Replaced by |
|---|---|---|
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

# equinox. operating manual

Every rule in force for the equinox. group, with the date it started. Decision #4, 8 Oct 2026.

**How to use it**
- This manual is the rulebook. It wins over memory and over every other document; memory is background only.
- It holds the rules in force only. Why each rule is as it is, its history and the retired rules are in
  `rule-history.md`, beside this file.
- When a rule changes in any chat, that chat **replaces** the old sentence here; it never adds the new rule beside the
  old one. In the same turn it moves the old wording and the why into `rule-history.md` with the date, and updates the
  copies in the Equinox project's files.
- Rule changes Gitesh agrees in chat are committed directly. Code changes still go through pull requests.
- Numbers that change often (fare levels, cabins, bank times, interline status) live in the planner; this manual says
  where. Foundation decisions are logged in `decisions.md`.
- `playbook.md`, the handover guide, gives the steps in the order we use them (the growth loop, daily, Saturday,
  monthly, every check and what to do when one fails) and points here for the rules; it never restates them. Where it
  and this manual differ, the manual wins and the playbook is corrected in the same turn.

---

## Decided, not yet built
Until each is built and merged, the rules below stand as they are.
- **Deferred, on a trigger:** moving the report PDFs out of the database (#16). They stay in `site_reports` until
  they reach 50 MB or the database passes 350 MB (§1). *(since 12 Oct; history: rule-history.md)*
- **Deferred, on a trigger:** Cloudflare's cache in front of the website's data (#20, option C). A brief in the
  Building chat when `site_public()` passes 500 KB (109 KB on 12 Oct), the website's calls pass 1,000 a day (about 40),
  or Supabase's egress passes 4 GB in a month with the website a large part of it. *(since 12 Oct; history:
  rule-history.md)*
- **Point-to-point routes away from our bases, for every airline (Kingfisher and Malaysia first):** stations, a third role in the airline's bases
  beside hubs and focus cities, for airports we fly to and from without making them a base (for example Lucknow for
  Lucknow–Patna): no banks, and flight numbers in 3 digits from one pool per airline, 100 to 999 (Gander's flights use
  up to 4 digits; the 21 Oct scan shows none with 5). Stations are never treated as hubs or focus cities (trunks, the
  website, reports). Malaysia's include Subang (its own market, 30 km from KUL) and Kota Kinabalu's pairs away from
  KUL. Brief `docs/briefs/2026-10-22-point-to-point-routes.md`, option A. Building now.
  *(decided 22 Oct; every airline since the same day; history: rule-history.md)*
- **Not tracked yet:** a frequency taken away (the fare ladder's capacity hold, §5, covers frequencies gained).
  *(since 21 Oct; history: rule-history.md)*

Details and open points: `docs/decisions.md`.

## 1. How we work
- **Game changes are made in the planner at `/planner/`,** the only planner. Orders, scheduling, retimes and the rest
  go on as normal, and so do the Saturday review and the monthly work. Claude's data-only changes go in as below.
  *(since 14 Oct; history: rule-history.md)*
- **Say first when something will take more than 5 minutes,** with roughly how long, before starting it (a helper's
  build, a long check run, a big data job). *(since 12 Oct; history: rule-history.md)*
- **One item at a time.** Discuss a development or decision, Gitesh decides, then finish it (decided and set up)
  before raising the next. No building on Claude's initiative. *(since 7 Oct; history: rule-history.md)*
- **Code changes are pull requests.** Each on its own branch, saying what changed, why and how it was tested. Gitesh
  approves by saying "merge"; merging is what makes it live. *(since 8 Oct; history: rule-history.md)*
- **Hosting:** the website and planner are on Cloudflare Pages (free plan) at `equinox-alliance.com`, our own domain,
  registered at Cloudflare at cost and renewing automatically each October. `equinox-alliance.pages.dev` also works.
  Merging to `main` publishes them, and Cloudflare builds a preview of every pull request at a `pages.dev` address.
  The schedule check is a Pages Function (`functions/api/game-schedule.js`). *(since 8 Oct; history: rule-history.md)*
  - **The build:** Cloudflare runs `if [ -f package.json ]; then npm ci && npm run build; fi` before it publishes,
    output folder `web`, Node 22 (`.nvmrc`). It builds the planner (`app/planner/`) into `web/app/`, served under
    `/app/` with its page at `/planner/` (`web/_redirects`). A build that fails leaves the last good version live.
    *(since 12 Oct; history: rule-history.md)*
- **Supabase stays on the free plan.** We move to the paid plan ($25 a month) only on a trigger, and each trigger means a
  brief at the next weekly review, not an automatic upgrade:
  - the database passes 350 MB;
  - egress passes 4 GB in a month;
  - the free plan gets paused or limited despite daily activity;
  - a feature we decide we need is paid-only.

  The report PDFs move out of the database into private file storage when they reach 50 MB, or with the 350 MB
  trigger, whichever comes first (#16, deferred 12 Oct). The monthly usage check (§7) looks at their size too.
  *(since 9 Oct; history: rule-history.md)*
- **Preview before live:** previews are look-only. They show the live data, but saving works only on
  `equinox-alliance.com`; anywhere else the planner says "preview · not saved". Every pull request that changes the
  database is rehearsed by the *Database rehearsal* check on a copy of last night's backup, which posts the result on
  the pull request. Claude asks for "merge" only once it passes. After the merge, Claude applies the change to live and
  sets the live migration record to the file's version, so the repository and live keep the same list. A change that
  removes something (dropping a table, rule or column) can't be applied from the chat, because Supabase's approval
  never reaches Gitesh. He runs that file in Supabase's SQL editor, and Claude then records and checks it. *(since
  8 Oct; removals since 9 Oct; history: rule-history.md)*
  **If applying any change from the chat comes back "cancelled", Claude tries once more, then gives Gitesh the file's
  link to run in the SQL editor the same way.** *(since 12 Oct; history: rule-history.md)*
- **Automatic checks:** every pull request runs *Checks* (no keys or passwords; the schedule check on a saved game page;
  the fares userscript on the saved fares form and answer; the capture's world scan against `gscan.py` on the same
  saved pages; the planner's install, type check, lint, unit tests and build; the planner's screen figures (Home, Tails,
  the planning library's schedule checks) on a dated sample against saved answers; the planning library's cases and its
  optimiser against plan.py's saved answer; the weekly report end to end on a small sample, its money from the figures;
  every website page, the planner's sign-in at `/planner/` and the planner's addresses). When the database, the planner
  or the library changes, the *Database rehearsal* also generates the planner's types again from the copy (they must
  match the committed `app/planner/src/db/types.ts`), has the planner sign in, read and save on the copy, open every
  screen at a frozen moment at 1280 and 380 px wide with no errors and no sideways scroll, and save through every kind
  of save each screen has, each checked against the rows recorded for it; reads a saved evening of each capture page
  kind and replays every kept capture page, each evening judged ok (#21); and when there are database changes, it backs
  the copy up and restores it as the nightly job does.
  **Claude never asks for, or makes, a merge while any check is red.** Every bug fixed gets a test. When a change is
  meant to move a number, the pull request updates the saved answers and says which moved and why. How to run and
  update them: `tests/README.md`. *(since 8 Oct; history: rule-history.md)*
- **Documentation stays current:** every pull request that changes how something works updates the documents in the
  same pull request:
  - the map, `docs/architecture.md` (and its project copy, `claude/architecture.md`);
  - the planner guide, `docs/planner-guide.md`;
  - the playbook, `docs/playbook.md` (and its project copy, `claude/playbook.md`), when a recurring step changes;
  - `scripts/README.md`;
  - `database/current/`, for a changed function or view;
  - the README.

  Every new table, view or function gets a description in its migration. The database rehearsal fails without one, and
  regenerates and checks the table guide, `docs/data.md`. A new chat or session starts from the map.
  *(since 8 Oct; history: rule-history.md)*
- **A new table grants its own access.** Tables created in `public` get no access for the website (`anon`) or staff
  (`authenticated`) by default, on live and on the rehearsal's copy, so each new table's migration grants exactly what
  the planner or website needs (`airline_order_cabins`: staff read and write), and nothing for a table only the
  database's own functions use (`capture_keys`). The rehearsal's checks fail on a table the planner can't reach.
  *(since 20 Oct; history: rule-history.md)*
- **Big builds go to a fresh helper.** Decisions and reviews stay in the Building chat. Each sizeable build gets a
  written spec (what, why, which files, what the checks should show) and goes to a helper that starts with a fresh
  memory: it reads `CLAUDE.md`, the map and the manual, writes the code, runs the checks and opens the pull request.
  Claude reviews it against the spec and the checks before asking for "merge". Small fixes can be made directly in the
  chat. A new Building chat starts at each step of the decision list, once anything worth carrying is in the
  repository or the project files. *(since 8 Oct; history: rule-history.md)*
- **Data-only changes go straight in, to the tables:** plan cards, to-dos, notes, logs. Either through
  `planner_save(changes, client)`, the planner's own way of saving (one call of row changes, each from the
  `updated_at` it was read at; logged as actor planner with the client named, e.g. `claude <chat>`), or plain SQL on
  the tables, starting with `select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail',
  '<chat>', true);` so the change log names the chat (design §6). Times on the tables are UTC (flight legs and
  plan-card legs); the planner shows a change the next time it reads the table. *(since 8 Oct; this way since 14 Oct;
  history: rule-history.md)*
- **Rule numbers have one source:** the database's `settings` (our own choices, with an airline's override where it
  has one) and `world_rules` (Gander's house rules, game settings and #12's permissions). The figures in §3, §4, §5 and
  §9 name their row; a rule change updates the row and this manual together, and nothing else holds a copy (the
  planner and the library read the tables). *(since 10 Oct; history: rule-history.md)*
- **To-do board:** anything Gitesh needs to check or do goes on the planner's To-do board (on Today); Claude marks it
  resolved when he reports back. *(since 30 Sep; on Today since 20 Oct)*
- **No one-week aircraft checks.** A new schedule is checked once, when it's filed (the planner checks each card
  against the game, §4), and the capture's page checks show each night whether it flies (§7). *(since 15 Oct; history:
  rule-history.md)*
- **Every decision gets the full brief** (format in `docs/briefs/README.md`): decision and recommendation first; then
  an options table with growth, profit a week, cash at the lowest point, opportunity cost, risk and whether it's easy to
  undo; then the background with sources and competition, scenarios and the risk of waiting, and what would change the
  recommendation. Save it in `docs/briefs/`. Applying an existing rule is not a decision and gets no brief.
  *(since 8 Oct; history: rule-history.md)*
  - **A new aircraft's routes get a full brief only when the choice is a real trade-off:** a new city, a new base,
    moving an aircraft off a route, or options that differ in more than timing. Adding frequency to routes that already
    sell out applies the growth rule (§3): its record is the plan card's note (the routes, connections, maintenance and
    hours, and the options set aside), shown to Gitesh in chat before he schedules. *(since 16 Oct; history:
    rule-history.md)*
- **Facts first.** Pull the numbers from the database and captures before advising, and say where they came from.
  Never guess a current fact. *(since 8 Oct)*
- **No keys or passwords** in the repository, files or chat. Keys live in the database or as GitHub secrets.
  *(since 8 Oct)*
- **No one can sign up:** sign-ups are off in Supabase, and the only account is Gitesh's. Giving someone access means
  turning them on briefly, or inviting from Supabase's dashboard, and then proper roles (see #11's brief).
  *(since 8 Oct; history: rule-history.md)*
- **Test samples are the one exception to "no game data in the code repository":** small, dated samples of game data
  in `tests/fixtures/` for the automatic checks. Never the database, keys or sign-in data. *(since 8 Oct; history:
  rule-history.md)*
- **Opus for everything,** business decisions included. *(since 8 Oct)*
- **One chat per kind of work,** all inside the Equinox project. If Gitesh asks a question that belongs to another
  chat, say which chat in one line and don't answer it there. *(since 8 Oct; history: rule-history.md)*

  | Chat | Covers |
  |---|---|
  | Scheduling | Aircraft that have arrived, plan cards, retimes, route choices, what and when to order, interline requests |
  | Saturday review | Every Saturday: the world scan's age (the scan runs with the evening capture; `gscan.py` by hand if it's old), weekly report, connection audit, the airlines' newsroom roundups, fare plan and the weekly review. On the first Saturday of the month also the weekly report's month page, gander monthly and strategy (bases, focus cities, holdings, long-term direction). One review chat for both since 15 Oct (Gitesh) |
  | Building | Planner, website, database, capture, repository, foundation decisions, how the tools calculate things |
- **Each airline is its own business:** no group totals; finance looks at each airline's profit and growth.
  *(since early Oct)*

## 2. Group strategy
- **Roles:** each airline owns its home region, and one airline owns each intercontinental flow. Oceania goes via KUL,
  except China–Oceania (China Eastern direct) and US–Oceania (Pan Am). *(since 29 Sep)*
- **One airline per city pair.** No two of our airlines fly the same pair. Pairs within one airline go under the
  first-listed hub (DEL–BOM under DEL). Across airlines, by country pair: US/UK–India → Kingfisher; US–UK, Europe or
  China → Pan Am; UK–Europe, China or Malaysia → Virgin; Europe or India–China → China Eastern; Malaysia → Malaysia.
  Virgin doesn't fly JFK or Delhi. When merging Gitesh's route lists, add missing lanes only; never change ownership.
  **The country rule applies where the rightful airline can fly the pair from one of its own bases.** Where it can't
  (Gatwick–Atlanta: Pan Am has no base at either end), the airline that has the pair on its list keeps it, so no market
  drops off the map. *(since 23 and 26 Sep; the base exception since 21 Oct; history: rule-history.md)*
- **Destination shape:** in time, fly every route a real airline flies from each hub and focus city. Plan as if money
  isn't the limit, and grow at the group's own pace. *(since 23 and 29 Sep)*
- **Scale models** (each airline's counterpart in the Airbus world): Virgin → British Airways, Pan Am → Pan Am,
  China Eastern → China Eastern, Malaysia → Singapore Airlines; Kingfisher → Inter Connect (Ellinikon world). Ryanair
  covers the Europe the others can't, with no model: the other worlds don't allow low-cost airlines; it competes on
  price. *(since 29 Sep; the reason written in 22 Oct)*
- **Malaysia:** make KUL a world transfer hub; build the Asian feeder network before any long-haul. **Long-haul starts
  once every 4- and 5-star opening on Malaysia's route list within the A320neo's reach (the A320neo Heavy, 4,708 km,
  §3) is flown.** November's trunks (§4) are the one exception. *(since 29 Sep; the trigger since 21 Oct; history:
  rule-history.md)*
- **Kingfisher:** India is open; aim to capture all of it. *(since 2 Oct)*
- **No new airlines before January 2027:** the two low-demand holdings the house rules allow (§9) wait until then.
  *(since 15 Oct; history: rule-history.md)*

**Bases** (main hub first):

| Airline | Hubs | Focus cities | Next |
|---|---|---|---|
| Pan Am | JFK, Los Angeles, Dallas | ORD, SFO, SEA | — (LAX and Dallas off hold 20 Oct; they open with November's trunks) |
| Kingfisher | Delhi | Hyderabad, Bengaluru, Chennai, Kolkata (all four wait for Delhi's 750 under hubs first, §3) | Mumbai |
| Ryanair | — (all bases are equal focus cities, point to point) | Paris CDG, Amsterdam, Barcelona (opening with the 14 Oct order) | Milan and Munich; no eastern base for now |
| Virgin Atlantic | Gatwick, Manchester | Edinburgh | — |
| China Eastern | Shanghai PVG, Xi'an, Kunming | Beijing Daxing, Shenzhen | — |
| Malaysia | KUL | — | — |

*(base roles since 29 Sep; history: rule-history.md)*

## 3. Fleet and orders
- **Fleet types, as the route needs:** every airline may fly any of our types where a route calls for it, sized by the
  city's stars and picked from the default line (both below), and the A350 where range demands it or, per the default line, on trunks where the A350-900 sells out. Ryanair flies
  the A320 family and the E195, no A350. The three families (A320 family, E195, A350) are the most any airline has; no
  787, CRJ or A319. Each family is its own delivery line (the order queues, below). *(since 17 Oct; history:
  rule-history.md)*
  - **Size by city stars:** 1- and 2-star cities get the E195; 3-star the E195 or the A320neo; 4-star any of the
    E195, A320neo and A321neo; 5-star the A320neo, A321neo or XLR (the XLR beyond an A321neo's reach). Within a band,
    the smaller type wins, heavy routes included: a busy pair gets more flights on more aircraft, not a bigger
    aircraft. A bigger variant only where the route needs its reach. The A320neo shares the A320-family line, the E195
    has its own. A cabin layout takes a couple of minutes to set up in the game, so a missing layout is never a reason
    to pick a type. *(since 18 Oct; history: rule-history.md)*
- **The default line: the cheapest variant that seats the market and reaches the city.** Stars set the size (above),
  smaller wins within the band, and distance picks the variant (list prices; range with a full load, from the game's
  aircraft pages, 18 Oct). The current fleet stays as it is; new orders pick from this line.

  | Size | Variant | Seats | Reach | List price | Use |
  |---|---|---|---|---|---|
  | Small | E195-E2 | 146 | 3,542 km | 35.4M | the default small aircraft |
  | Small | E190-E2 | 114 | 4,065 km | 33.7M | 3,542–4,065 km, or the thinnest 1-star city (the openings name it beside the E195-E2 on a 1-star city, "or the E190-E2 if thin", and the evening proposal decides: nothing in our data says how thin a city is; since 21 Oct) |
  | Mid | A320neo SHARP | 189 | 3,355 km | 41.2M | the default 189-seater |
  | Mid | A320neo LIGHT | 189 | 3,690 km | 42.9M | 3,355–3,690 km |
  | Mid | A320neo | 189 | 4,045 km | 43.4M | 3,690–4,045 km |
  | Mid | A320neo Heavy | 189 | 4,708 km | 44.8M | 4,045–4,708 km |
  | Large | A321neo LIGHT | 240 | 4,192 km | 48.0M | the default 240-seater, cheapest per seat |
  | Large | A321neo | 240 | 4,742 km | 50.6M | 4,192–4,742 km |
  | Large | A321LR | 240 | 5,809 km | 54.2M | 4,742–5,809 km |
  | Large | A321XLR | 240 | 6,939 km | 57.2M | 5,809–6,939 km |
  | Wide | A350-900 | 440 | flies to about 15,000 km with its full cabin | 140.1M | every long-haul route up to about 15,000 km |
  | Wide | A350-1000 | 480 | keeps the most seats beyond 15,000 km | 157.1M | beyond about 15,000 km, and trunks where the -900 sells out |

  The listed range is with a full load and is not a limit: the game flies longer routes with fewer seats. Left out
  because another variant beats them: the A350-900ULR (never the cheapest per seat), the A319neo (more per seat than
  the A320neo SHARP at every reach), the A321neo Medium, the A321XLR LIGHT and Heavy. Still three families: the A320
  family, the E-jet E2 and the A350. *(since 18 Oct; the A350 rows since 21 Oct; history: rule-history.md)*
  - **Turnaround of a new variant:** the game shows none, so a new variant takes its family's (A320 family 66 minutes,
    E-jet E2 67, A350 90). *(since 19 Oct; history: rule-history.md)*
  - **Reach is checked by the Scheduling chat** when it picks the variant for a route (§3), not by the plan card.
    *(since 19 Oct; history: rule-history.md)*
- **Order across both delivery lines:** A321neos go on the big routes that sell out, where seats absorb the demand;
  E195s go on short, thin and new markets, where departures count most. An E195 is ordered on an evening when the cash
  forecast covers an E195 (1.8M) but not yet an A321neo (2.4M), rather than waiting a day for the A321neo, so both
  lines keep delivering. Each evening's proposal (§4) says which type each route takes. *(since 18 Oct; history:
  rule-history.md)*
- **When cash doesn't cover the aircraft the top openings need, cash decides:** that evening the airline orders the
  biggest type the cash forecast allows, and it takes the best openings that type can fly (by the openings' order, among
  those its size band allows: an E195 takes the top 1- to 4-star openings). The openings that need a bigger type wait for
  an evening when cash covers it. A line is never left idle to wait for cash. *(since 21 Oct; history: rule-history.md)*
- **Reach first:** new aircraft go into the short and medium-haul narrowbody network; long-haul comes later.
  Kingfisher's two Delhi–JFK A350s stay as they are. *(since 28 Sep)*
- **Route first, then the airline, then the aircraft.** The Scheduling chat picks the routes the group should open
  next, then the airline that flies them (hubs first and one airline per city pair, below and §2), then the variant
  that seats the market and reaches the city (the default line, above) and its cabin. That is what gets ordered: the
  plan card, with its routes, variant and cabin (`plan_cards.config_id`), is written when the aircraft is ordered.
  *(since 19 Oct; history: rule-history.md)*
- **Who orders:** Claude recommends what to order; Gitesh orders in the game and says so; Claude logs it. *(since 2 Oct)*
- **Order every evening the forecast allows, not in batches; keeping the order queues full comes first:** after each
  evening's capture, the Scheduling chat looks at each airline's order queues (three delivery lines each, Ryanair two)
  and its cash forecast, and proposes the aircraft that can be ordered and the routes for each, with variant and
  cabin. Where cash allows more than one option, the route we most want to fly decides (market share first, below).
  The proposal goes one airline at a time: each airline's order is decided, ordered and logged before the next is
  shown. Gitesh orders that evening. *(since 18 Oct; history: rule-history.md)*
- **When an airline can order: the cash forecast.** Planner → Today → Orders says who can order now or from when, and
  the safe types; the detail is Performance → the airline → "Cash, next 14 days": captured cash, plus flight
  profit from the last day's bank statement, minus every scheduled lease payment and week-end closing (the weekly salary
  payment). An order is safe when **0.5M stays in hand at the lowest point** after it (`settings.order_cushion`).
  Prices include the cabin. *(since 7 Oct; history: rule-history.md)*
  - **The order's own lease counts:** weekly, from 7 days after it arrives, taken as arriving the day it's ordered (the
    most it could cost inside the 14 days). Its income and its crew's pay are left out; the profit it makes over its
    crew pay is extra buffer. Several orders are tested together, each with its lease. A type never leased yet is
    taken at 10% of its price a week (`settings.lease_estimate_pct`). *(since 8 Oct; history: rule-history.md)*
  - If an airline hasn't been captured, get the capture first. Never use the surplus figure.
  - The forecast is worked out by `cash_forecast()` in the database (several orders tested together with `p_orders`);
    the planner's Performance screen shows it, and Today's Orders the types safe now.
- **The order queues:** each airline has one delivery line per family, and the aircraft on a line arrive one after
  another: an A320-family aircraft (A320neo, A321neo and XLR share the line) every 21 hours, an E195 every 15 hours, an
  A350 every 30 hours. Order planning keeps the queues in mind (Today → Orders, each airline's delivery lines): what
  each airline still has to arrive on each line, when each line runs dry, and when a new order's aircraft would arrive.
  An empty line is a line standing idle. A new order joins the end of its line: on an idle line its first aircraft
  arrives one interval after the order, on a busy line one interval after the last aircraft already queued. *(since
  17 Oct; history: rule-history.md)*
- **Market share first, profit second:** every airline grows to take and hold the biggest markets, rivals' included.
  Route choices lead with the largest city pairs (5-star, and the pairs rivals fly most) and prefer shorter sectors where
  they give an aircraft more departures a day; going head to head with a rival is welcome. Profit still has to be
  there: the cash forecast and its cushion, the fare floor, the fix and losing-money marks, hubs first and one airline
  per city pair don't change. *(since 18 Oct; history: rule-history.md)*
- **The openings, ranked: `competition()`.** The routes we most want to fly next are each airline's openings: the pairs on
  its route list that no airline of ours flies (either way), ranked by the city's stars, then the rivals' departures a
  week on the pair (the latest world scan), then the shorter distance, then the pair's code. Each comes with the variant
  from the default line (the smallest size its stars allow, bigger only for reach, the cheapest per seat whose range
  covers it, among the types the airline may buy; an opening no type reaches is left out) and whether hubs first
  allows it (below), with the reason when it doesn't; those it doesn't are listed after the rest. The evening proposal
  (§4) takes its routes from the top of this list: the airline briefing carries the top 20, the planner's Competition
  screen shows them with the market share and the rivals' moves, and `select public.competition(<airline id>);` gives
  them all (`p_limit`). One airline per city pair (§2) still decides between airlines (an opening says which other
  airlines of ours have the pair on their list). **In November** (`settings.trunk_month_from` to `trunk_month_to`, 1 to
  30 Nov, §4) the trunks come first, shortest first, marked, with hubs first not applied to them and no distance
  leaving one out (the A350s beyond the A321XLR); the other openings follow as always. The list marks trunks; whether
  each makes sense stays the Scheduling chat's judgment. Freighters are no one's rivals: market share, threats and the
  openings' rivals count passenger flights only, by the weekly report's rule. *(since 21 Oct; history:
  rule-history.md)*
- **Add a flight or raise fares, by profit per aircraft hour:** a sold-out route is marked **add a flight** when its
  profit per aircraft hour is at or above its airline's middle route, and **raise fares** when it's below. An aircraft
  hour is the flight's block time plus the type's turnaround (`aircraft_types.min_turn_min`) and the turn margin
  (`settings.turn_margin_min`, 10 minutes): the hours the aircraft can't fly anything else. A route with no legs on
  record has no aircraft hours and is still compared by profit per flight. The fix, losing-money and cash rules don't
  change. Worked out by `route_profit()`, which gives each route's `aircraft_hours` and `profit_per_aircraft_hour`.
  *(since 17 Oct; history: rule-history.md)*
- **New routes aren't judged for a week:** a route launched fewer than **7 days** ago gets none of the problem marks
  (losing, fix or reduce), so Today's routes to fix and Performance's Fix or reduce skip it. Its launch day is its
  earliest rotation's (a second daily added later doesn't make an old route new). Sold-out marks (add a flight, raise
  fares) apply at any age. The number is `settings.growth_new_route_days` (7). *(since 16 Oct; history:
  rule-history.md)*
- **Hubs first:** until an airline's main hub reaches **750 weekly departures**, every new aircraft goes to the main hub.
  Any other base, whether new or already open (second hubs and focus cities alike), gets an aircraft only to fly
  contested routes: a rival with over 250 departures a week at that base, or over 2 a day on the route itself. A base
  that is contested for one route (Manchester for Amsterdam, say) doesn't open its other routes. **Stations open
  nothing** until the main hub reaches the 750, contested or not (since 22 Oct). Ryanair is exempt.
  Contested as of 5 Oct: Mumbai (Gulf routes), Manchester (Amsterdam), Daxing (Chengdu), Dallas if opening with ORD,
  Atlanta or Phoenix, SFO and SEA. The numbers are `settings.hub_first_departures` (750),
  `contested_rival_weekly` (250), `contested_rival_daily` (2) and Ryanair's `hub_first_exempt`; the growth signals'
  thresholds are the `growth_*` and `pattern_*` settings. *(since 5 Oct; stations since 22 Oct; history:
  rule-history.md)*

## 4. Scheduling
- **How it runs: every evening, from the order queues; a card with each order.** After the capture the Scheduling
  chat proposes the aircraft to order and the routes for each (§3, "Order every evening"). When Gitesh orders, Claude
  writes the plan card with its routes and cabin (`plan_cards.config_id`: filing fits it and logs its first fit at its
  price, and the planner checks the game's charge against that first fit: Systems → Cabin charges, with one item on
  Today when one doesn't match), checked at both ends. The card stands: when the aircraft arrives, Gitesh schedules it
  in the game as the card says and **files it within a day of arrival**, and the planner checks each card against the
  game. **The background starts from the airline's briefing** (`python3 scripts/briefing/brief.py <airline>`,
  `scripts/README.md`), which gathers its money, fleet, routes, hubs, deliveries and plan cards with their check,
  to-dos, fare plan, rivals from the latest scan (with its date) and the capture's state in one step; anything more
  comes from the call the map's guide names (`docs/architecture.md`, "Which call answers which question"), not from
  guessing at tables. *(since 19 Oct; the cabin charge check since 21 Oct; history: rule-history.md)*
- **Fly each aircraft as much as it fits:** the Saturday review lists every aircraft under **12 block hours a day** and
  whether one more short rotation fits it, Ryanair's and Virgin's first. Tails' own flag stays at
  `settings.aircraft_block_target_h` (10). *(since 18 Oct; history: rule-history.md)*
- **Every aircraft is named by its tail number and base:** whenever any chat mentions an aircraft or one of its
  flights (an order, a plan card, an arrival, a retime, the connection audit, a proposal), it gives the registration and
  the base it flies from, e.g. "N019AW (JFK)". For an order not yet registered, the airline, variant and base.
  *(since 19 Oct; history: rule-history.md)*
- **The planner mirrors the game.** Routes and aircraft enter the planner only once they're in the game; plans live on
  plan cards. *(since Sep)*
- **Until 31 October, only new routes (Pan Am exempt since 22 Oct):** every flight planned from 18 to 31 Oct opens a
  route the airline doesn't fly yet: no second dailies or extra frequency on existing routes, whatever the growth signals say; until 31 Oct this wins over §1 and §3's frequency rules. Plan cards made before
  18 Oct stay as they are, filed or not (EI-ABS and EI-ABT keep their second dailies). *(from 18 Oct to 31 Oct;
  history: rule-history.md)*
- **From 1 to 30 November, every new order fortifies the trunk routes:** a trunk route is any route between two of our
  bases (hubs and focus cities, any of our airlines). Orders that month add flights on trunk routes we fly, and open
  trunk routes we don't, until each is fortified. *(from 1 Nov to 30 Nov; history: rule-history.md)*
  - **Fortified** means it no longer sells out: flights are added while a trunk runs at 95% or more
    (`settings.growth_*`'s sold-out test), and stop once its loads fall below that.
  - **Flown and unflown trunks weigh equally:** adding to the trunks we fly and opening those we don't (within reach of
    the default line, §3) are chosen together, by profit per aircraft hour where flown and by market size where not.
  - **Hubs first is suspended for trunks in November:** any base can take an aircraft for a trunk route. One airline per
    city pair (§2) still applies, and so does the cash forecast's cushion.
  - **Only trunks that make sense:** a pair is opened only where the market is there and the route makes business sense
    (no Kolkata–US direct, say), within reach of the default line. Munich, Milan Malpensa, Mumbai, Los Angeles
    and Dallas count as bases; no base is on hold.
  - **Long-haul trunks are in too:** any trunk that makes sense, at any distance, on the default line's A350s where
    beyond the A321XLR. For November's trunks this sets aside reach first (§3) and Malaysia's feeder-first order
    (§2).
  - **Shortest to longest:** new trunks open in order of distance, shortest first, while keeping every delivery line
    filled (an idle line takes the shortest trunk its family can fly). This puts the narrowbody trunks first and the
    A350 trunks last. `competition()` lists them so from 1 to 30 Nov (`settings.trunk_month_from`, `trunk_month_to`).
  - **Narrowbody trunks first:** each evening's orders fill the short and medium trunks first (more departures per
    dollar); A350 trunks follow. The plan: `docs/briefs/2026-10-20-november-trunks.md`.
- **Maximise connections at both ends:** an arrival lands at least the airport's minimum connection time
  (`world_airports.mct_min`) before the departures it feeds, with no extra margin (`settings.connection_buffer_min`,
  0), and departures leave within 8 hours of the arrivals they collect (`connection_max_wait_h`). Every new plan card
  and every retime is checked at both ends. *(since 6 Oct; history: rule-history.md)*
- **Use each aircraft as much as possible.** No fixed floor on flying hours (the Saturday 12-hour list and Tails' 10-hour mark are flags, not floors); options show hours a day next to
  connections, and check whether one more short rotation fits. *(since 7 Oct)*
- **Night slots are fine.** *(since 27 Sep; history: rule-history.md)*
- **Maintenance at or above 100% is firm** (aim for 105%; `settings.maintenance_min_pct` and
  `maintenance_target_pct`). *(since 28 Sep)*
- **Turns:** the game's turnaround plus a 10–15 minute margin (`settings.turn_margin_min`, 10); 5 minutes is tolerated
  only on the busiest aircraft where 15 won't fit. *(since 25 Sep; history: rule-history.md)*
- **A second daily** goes wherever it makes the most connections, with no spread of our own: at least 5 minutes
  from the other flight on the route, Gander's house rule (`world_rules.same_route_gap_min`, §9), and further apart
  only when there's a business case. `settings.second_daily_gap_h` is 0, so the optimiser and Routes check only the
  house rule. *(since 15 Oct; history: rule-history.md)*
- **Service codes by distance:** every leg carries the service profile its route's distance calls for: S1 under 800 km,
  S2 from 800 to 1,500 km, S3 over 1,500 km; Ryanair R on every route (`service_profiles`, Reference → service
  profiles). The plan card's service check marks a wrong code in red, and it's fixed before the card is filed.
  *(since 10 Oct; written into the manual 21 Oct)*
- **Block time** = 25 minutes (`settings.block_allowance_min`) + distance ÷ speed: A321neo and XLR 840 km/h, E195 831,
  A320neo 839, A350 911 (`aircraft_types.cruise_kmh`).
- **Three banks per hub;** bank times are in `airline_bases.bank_times` (the planner's Reference → hubs), the bank
  windows in `settings.bank_arrival_window_min` and `bank_departure_window_min`. Connections come first; an unbanked
  flight still earns. *(since 23 Sep)*
- **New airlines launch short-haul,** one daily rotation per route, breadth first. *(since 26 Sep)*
- **Everything flies direct:** no tag (fifth or eighth freedom) flights. *(since 20 Sep)*
- **Ryanair stays inside the game's EU zone:** EU-27, the UK, Norway, Switzerland and Iceland. Turkey, Morocco, the
  Balkans and long-haul are out. *(since 25 Sep)*
- **London:** for airlines other than Virgin, new London routes go to Gatwick before Heathrow; existing Heathrow flights
  stay. *(since 26 and 28 Sep)*
  New Virgin Heathrow routes (Manchester and Edinburgh to Heathrow, as feeders for the group's long-haul there) are a
  late-game step, once the other hubs are built out. *(since 21 Oct; history: rule-history.md)*

## 5. Cabins and fares
- **The cabin is chosen with each order, recorded on its plan card and fitted in the game when the aircraft
  arrives,** among the layouts set up for its variant: if one route takes more than
  **65% of the aircraft's block time** (`settings.cabin_route_share_pct`), the layout that route's market calls for
  (`markets.layout`: Standard, Leisure, Leisure Plus or Comfort, in Reference → Markets; a route's own cabin choice wins
  over it); otherwise the layout with the most seats. Ryanair flies Standard only; Standard (economy only, no business)
  is Ryanair's, so the other airlines choose among the two-cabin layouts (Leisure, Leisure Plus, Comfort), and "the most
  seats" for them is Leisure. We don't refit. The plan card suggests its cabin by this rule (Tails → Deliveries, with
  **Use the suggestion**) and the card check flags a card whose cabin is missing or differs. *(since 20 Oct; wording
  clarified 22 Oct; history: rule-history.md)*
- **Fares:** new routes launch at 100% of the standard fare in both cabins; Ryanair 85%, economy only
  (`settings.fare_launch_pct`, with Ryanair's override). Weak routes get cut rather than launched cheap. **A new
  flight on a route already flown launches at that route's level** (the plan card shows it), not at launch fare.
  *(since 20–21 Sep; the new flight's rule since 21 Oct; history: rule-history.md)*
- **The fare ladder, every Saturday.** Each cabin of each route has a **level**: its fare as a % of the game's default
  price (launch: 100%, Ryanair 85%). At the Saturday review, from the week's captured flights in that cabin:
  - **up 5 points** (Pan Am 7) when every flight sold out (at least 5 departures in the 7 days);
  - **hold** when 90–99% sold out;
  - **down 5 points** (Pan Am 7) when under 90% sold out, then hold for 2 weeks before climbing again.

  New routes start after their first 7 days (§3), and **a route that gained a frequency in the last 7 days holds**
  for that week (`settings.fare_ladder_capacity_hold_days`, 7: its newest rotation under 7 days old, its first older),
  so the ladder judges it at its new size, not on the drop the extra seats cause. Every plan card shows the fare level
  of each route it flies, so a new flight is priced like the rest of its route. **A route whose captured fares don't
  match its level is set back to it:** when any flight of its latest captured day is more than a point off (against the
  route's fare on 21 Oct, when every route was at its launch level), the planner lists a change each way at its level,
  first, and the fares userscript makes it with the week's changes; not for a route on the fare plan this week, a new
  route, or one not captured since its newest flight launched.
  The level never goes under launch, nor under the 60% floor where another player flies the route. **For now it goes
  at most 20 points above launch** (120%, Ryanair 105%; **Pan Am 28 points, 128%**, since 22 Oct); the cap is lifted
  only once loads and image show it's safe. Pan Am's step and cap are its own `settings` rows.
  **A rival starting on the pair pauses that route for a week:** when a world scan of the last 7 days shows a rival
  that started on the pair (none in the scan before it) or added at least `settings.competition_threat_min_weekly` (7)
  departures a week, the route holds until 7 days after that scan ("rival Air China started here on 22 Oct: paused
  until 29 Oct"), checked after a new route, too few departures, the hold after a step down and a new frequency, and
  before the sold-out share; the threats are `competition()`'s (passenger flights only: a freighter never pauses a
  route), and Today lists the latest scan's.
  The planner works out each route's level and Saturday's moves, and lists the fewest changes to make in the game:
  **Ticket price adjustment** with the calculation baseline **default price**, so each change sets the level itself,
  **route by route only** (From A to B, and From B to A): never a whole base, so routes under 7 days old are never
  touched. The fare plan records them and the next capture ticks each off.
  **The fares userscript makes them** (`capture/fares_apply.user.js`): after **Put on the fare plan** in Performance,
  Gitesh presses **Apply fare plan** in the game and watches. It reads this week's planned changes the captures haven't
  seen yet (`capture_fare_actions()`, with the capture key), shows each airline's count and asks once, then makes them
  for every airline, one at a time, 2 seconds apart, changing prices only, and stops at the first problem, saying which
  change and why; run again, it reads only what's still unseen. Never on a schedule or without him watching. The
  simulogics terms (§4 II) forbid scripts in general, but Gander is an exclusive world whose owner sets the rules (§9):
  the capture, the salary script, the fares script and the scanner are allowed there; no need to ask the owner.
  Fare moves never appear in Needs attention. The numbers are settings (step, up, down, hold weeks, cap, and the hold
  after a new flight, `fare_ladder_capacity_hold_days`). *(since 21 Oct; history: rule-history.md)*

## 6. Interline
- **Our airlines interline with each other.**
- **Outside partners:** for each major airport the group flies to that isn't our base, an interline with that country's
  major airline, but only in countries with a real domestic market or that are the gateway to a region we can't fly to
  directly. *(since 25 and 28 Sep)*
- **Where not to:** nowhere in Ryanair's Europe zone; for Pan Am, not in Canada, Mexico, the Caribbean or Central
  America; each airline has its own skip list (in the planner's Interline tab). *(since 26 Sep)*
- **Gulf hub carriers are rivals:** decline their requests. *(since 5 Oct; history: rule-history.md)*

## 7. Recurring work
- **Every evening:** Gitesh presses "Capture all airlines" in the game. It captures loads, finances and payments straight
  into the tables, then runs the world scan when one is due (below) (`game_flights` and the rest); a day's loads count as complete once every
  active airline has been captured for it. Loads are typed in by hand (Systems → Manual entry) only if a capture fails.
  *(since 7–8 Oct; history: rule-history.md)*
  - **Then the world scan, when one is due:** after the last airline, the capture scans the world if the latest finished
    scan is at least `settings.scan_every_days` capture days old (1: every evening). It reads the same pages as
    `gscan.py`, at its pace (every airline in Gander with its schedule, then the airport pages for our bases, the big
    rival hubs and the latest scan's 20 busiest airports), and sends them with the capture key (`capture_scan()`). It
    takes a few minutes more (about 5); keep the tab open. The panel shows "World scan: 120 of 163 airlines…", then
    "World scan done", with a Stop button throughout; a page reload carries on where it was. No scan if a capture page
    failed that evening; a failed scan page is logged and skipped, and with more than 10% of the airlines failed the
    scan isn't finished, so the Systems board keeps the last finished one. Raise `scan_every_days` to 3 (about twice a
    week) if the evening gets long. *(since 21 Oct; history: rule-history.md)*
  - **Each page is checked as it arrives** (#21): ok, short or broken. Loads are short below 90% of the airline's
    flights scheduled in the page's window (the 24 hours before the capture, a new rotation counting from the day after
    it launched, and a new aircraft only once a capture has shown it flying; setting `capture_loads_min_share`); a bank
    statement is short with no lines, or below half the median of the airline's recent nights
    (`capture_statement_min_share`); events or an income statement with no rows are short; a balance sheet without the
    cash account (2800), or a page that doesn't read, is broken. The capture's panel ends each airline with "all good"
    or what came in short or broken ("loads 12 of 78 flights"); Today's capture line and needs attention show a short or
    broken page the same night, and the Systems board shows each airline's verdict. **If a page comes in short or
    broken, capture that airline again** while the game's last 24 hours still hold the loads. A saved evening of each
    page kind is tested on every pull request. No alert outside the planner: a missed evening still shows on Today after
    26 hours. *(since 14 Oct; history: rule-history.md)*
- **Salaries:** a separate script, "Salaries: this airline", which Gitesh runs by hand when he chooses. It changes only
  the airline he's on, setting each position to 10% above the country average. *(since 10 Oct; history:
  rule-history.md)*
- **Every Saturday:**
  - first, the document check (about 5 minutes): the project's copies of the manual, playbook, map and decisions
    match the repository; no document states a retired rule; the playbook refers to rules rather than stating them; and
    memory holds no game rules. Facts are fixed on the spot; anything needing a ruling goes to Gitesh one at a time.
    *(since 21 Oct; history: rule-history.md)*
  - the world scan runs with the evening capture (`scan_every_days`, above), so the report and gander monthly read
    this week's rivals; if the Systems board shows it old (amber over 8 days), run `scripts/scanner/gscan.py` by hand
    first (the Saturday chat; about 5 to 10 minutes). *(since 21 Oct; history: rule-history.md)*
  - the weekly report: a PDF briefing written for a CEO, no fixed template. It covers competition by market (for the
    group and each airline), risks, opportunities, our plan and progress, route profit, growth signals and fare-plan
    results, each airline's net cash a day (flight profit less leases and salaries) against the price of one aircraft,
    the pace towards an aircraft a day per airline, and each of our airlines against its three biggest competitors: the
    three outside airlines with the most weekly departures on its own city pairs in the latest scan, each with its size
    and growth against the week-before scan beside our airline's, read from `competition()` (its `competitors` and
    `self`, in the figures the report pulls; the scans run every evening, so growth is against the week-before scan,
    not the previous one). It is the only investor report: on the first Saturday of the month it adds a page on the
    month just ended (month-on-month figures and the month's decisions). *(since 5–8 Oct; history: rule-history.md)*
  - the connection audit across all hubs (valid connections, near misses, and retimes of 10 minutes or less);
  - one newsroom roundup per airline of its new routes and extra flights (§8);
  - the weekly review together: the fare ladder's moves (§5), aircraft under 12 block hours a day (§4), orders and
    hubs first.

  *(since 5–8 Oct)*
- **Every night, after the capture:** an automatic backup copies the database and the site's files, restores the copy
  to prove it works, uploads it to Cloudflare R2 and reports the result. Each night's copy is kept 30 days. The
  month's first is kept for good, in R2 and as a file on a GitHub release in the private repository `equinox-backups`,
  where the backup job lives. Copies no longer go into git. Each run's R2 key is recorded in `backup_runs`. The
  database rehearsal reads last night's copy from R2 with a read-only key. Live data never goes into the
  code repository (small test samples aside, see §1). The planner warns on Today if there's no good copy from the last
  30 hours. To recover, see the README in `equinox-backups`. *(since 8 Oct; history: rule-history.md)*
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
- **Every job writes a row to `job_runs`,** and the planner's Today warns when the last good backup is more than 30 hours
  old, the latest snapshot is more than 30 hours old (or the 10:00 UTC job hasn't run for 30 hours: the scheduler may
  have stopped; restart it from Supabase's settings), the month's archive hasn't run by the 3rd, or any job's last run
  failed. *(since 11 Oct; history: rule-history.md)*
- **The Systems board, at the top of Systems** (#23), is where "all good" shows: one line each, green, amber or red, for
  each airline's evening capture (when, and its verdict), the daily snapshot (taken by the capture, or by the fallback
  and so incomplete), the nightly backup (last good copy, restore check, size), the monthly archive (this month's
  state, due by the 3rd), the clean-ups, the world scan's age (amber over 8 days, red over 15), the planner's own build
  (the time and change it was built from: after a merge, a time that hasn't moved means the deploy failed), and the
  usage the database can measure against its triggers (§1): database size (350 MB), the report PDFs in `site_reports`
  (50 MB) and the size of `site_public()` (500 KB), amber from 70%, red at the trigger. The marks use needs attention's
  limits above (capture 26 and 48 hours, backup and snapshot 30 hours). Today's needs attention keeps listing the
  problems. *(since 14 Oct; history: rule-history.md)*
- **First Saturday of the month:** gander monthly and the monthly strategy session, and the weekly report adds its
  page on the month (above). Also a look at Supabase's usage page for what the database can't see: egress against §1's
  4 GB and the website's calls a day against #20's 1,000 (*Decided, not yet built*). The database's size, the report
  PDFs and the size of `site_public()` are on the Systems board. *(since 8 Oct; history: rule-history.md)*

## 8. Writing, website and newsroom
- **Writing for Gitesh:** he mostly reads on his phone. Lead with the answer, keep it short, and use tables for options
  and comparisons.
- **Newsroom posts read like a real airline's:** no cabins, bank timings or other internal detail, and no references to
  the game. *(since 5 Oct)*
- **What the newsroom posts:** one roundup per airline each Saturday, covering its new routes and extra flights since
  the last one (Saturday review chat). No post for an airline with nothing new. No posts for new aircraft. *(since
  17 Oct; history: rule-history.md)*
- **gander monthly** covers the whole Gander world impartially, without claiming to be impartial. It is marked as made
  by AI and published openly on the website. *(since 5–6 Oct)*
- **Brand:** "equinox." — lowercase, with the full stop. Real airline names and logos, with a fan-project disclaimer in
  the first-visit window, the footer and the About page.
- **Investor relations** is locked behind an investor password (separate from staff login); reports download freely
  once inside. *(since 6 Oct)*

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
- Bookings on a route are divided among the flights on offer, so more departures win more of a market than fewer,
  bigger flights. *(since 18 Oct; history: rule-history.md)*
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

Retired rules, and why each rule is as it is: `rule-history.md`.

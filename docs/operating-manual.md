# equinox. operating manual

Every rule in force for the equinox. group, with the date it started and why. Decision #4, 8 Oct 2026.

**How to use it**
- This manual is the rulebook. Where it and memory disagree, **the manual wins**; memory is background only.
- When a rule changes in any chat, that chat updates this file (and the copy in the Equinox project's files) **in the
  same turn**, and moves the old rule to *Retired rules* at the bottom with the date it ended.
- Rule changes Gitesh agrees in chat are committed directly. Code changes still go through pull requests.
- Numbers that change often (fare levels, cabins, bank times, interline status) live in the planner;
  this manual says where. Foundation decisions are logged in `decisions.md`.
- `playbook.md`, the handover guide, puts these rules in the order we use them (the growth loop, daily, Saturday,
  monthly, every check and what to do when one fails). Where it and
  this manual differ, the manual wins and the playbook is corrected in the same turn.

---

## Decided, not yet built
Until each is built and merged, the rules below stand as they are.
- **#13 to #17 are built** (9 to 11 Oct): the planner's data in proper tables; every row keyed by world and airline,
  with each world's rules as data; the change log and the daily history; one row per flight, a month of detail, then
  the monthly archive; backups and archives in Cloudflare R2; the planner tested on a local copy of last night's backup.
  The automatic jobs are in §7.
- **#18 and #19 are built** (12 to 14 Oct). #18: the planner rebuilt in React with TypeScript, screen by screen, each
  checked against the old screen's numbers; `/planner/` switched to it on 14 Oct (build pull request 13), and the old
  planner, its adapter and its documents went the same day (the clean-up, build pull request 14). #19: one home for
  each calculation, the planning rules (block times, turns, connections, maintenance) in one TypeScript library
  (`lib/rules/`) and the figures from the capture (cash forecast, route profit, growth signals, hub progress) in the
  database; the planner, the website's trip search, the optimiser and the weekly report all use them (the report's
  money from the captured figures since 13 Oct, with no surplus figure and no group totals). *Built 14 Oct.*
- **#21 and #23 are built** (14 Oct): each capture page is checked as it arrives, with its verdict in the capture panel,
  on Today the same night (Home until 20 Oct) and on Systems; and the Systems board at the top of Systems (of Check
  until 20 Oct) shows the capture, the jobs, the backups, the planner's own build and the database's usage against their
  triggers, each green, amber or red. Both are in §7. *Built 14 Oct.*
- **#24 is built** (15 Oct): the airline briefing (`python3 scripts/briefing/brief.py <airline>`: one airline's
  figures, planning figures, rivals from the latest scan, deliveries, plan cards with their check, to-dos and fare plan,
  in one step), and the map's guide to which call answers which question (`docs/architecture.md`), every example
  tested on the copy. The scheduling background (§4) starts from the briefing. *Built 15 Oct.*
- **Deferred, on a trigger:** moving the report PDFs out of the database (#16). They stay in `site_reports` until
  they reach 50 MB or the database passes 350 MB (§1). *Since 12 Oct · why (Gitesh): 1.5 MB today and about 50 MB a
  year; moving them now needs two new programs in Supabase and the backup copying private files, for no gain yet.*
- **Deferred, on a trigger:** Cloudflare's cache in front of the website's data (#20, option C). A brief in the
  Building chat when `site_public()` passes 500 KB (109 KB on 12 Oct), the website's calls pass 1,000 a day (about 40),
  or Supabase's egress passes 4 GB in a month with the website a large part of it. *Since 12 Oct · why (Gitesh): the
  call is small and the traffic light; splitting or caching it now gains nothing yet.*
- **Decided 17 Oct, for the Building chat:** route profit's add-a-flight or raise-fares mark by profit per aircraft
  hour (block time plus turnaround and margin) instead of profit per flight (§3). Until it's built, the mark compares
  profit per flight.
- **Decided 18 Oct, for the Building chat:** the planner learns the default line's variants (§3). *Built 19 Oct:* each
  variant is in `aircraft_types` with its seats, cruise speed, deposit (`price`) and range with a full load (`range_km`),
  from Gitesh's sheet of the game's pages, every airline may buy each (Ryanair no A350), so the cash forecast tests them,
  and their cabin layouts are in `cabin_configs`. The game shows no turnaround, so a new variant takes its family's (A320
  family 66 minutes, E-jet E2 67, A350 90). Reach is checked by the Scheduling chat when it picks the variant for a
  route (§3), not by the plan card (dropped 19 Oct, Gitesh: the routes are decided before the card).
- **The fare ladder is built** (21 Oct, pull request #56): `fare_ladder()` works out each route's level and Saturday's
  moves, and Performance lists the fewest game actions with **Put on the fare plan** (§5). A rival's pause waits for
  competition analysis; until then the Saturday review checks the scan by hand.
- **New frequencies and the fare ladder are built** (21 Oct, pull request #60; spec
  `docs/specs/2026-10-21-frequencies-and-fares.md`, §5): a route that gained a frequency in the last 7 days holds
  (`settings.fare_ladder_capacity_hold_days`); every plan card shows each route's fare level (Tails → Deliveries, the
  card check's `fares`, the airline briefing); and a route whose captured fares don't match its level gets a change
  that sets it back, first in Performance's fare ladder and made by the fares userscript (which also shows whether the
  game prices a new flight number at the default price, as Gitesh thinks). The fare index reads each flight of the
  latest captured day against its route's fare on 21 Oct 2026. A frequency taken away isn't tracked yet.
- **Next for the Building chat (Gitesh, 21 Oct):** the planner work's next big step is competition analysis with its
  ranked openings, before the route page.
- **Decided 18 Oct, for the Building chat:** the weekly report sets each of our airlines against its three biggest
  competitors (§7). Until it's built, the report shows the rivals on our routes as it does now.
Details and open points: `docs/decisions.md`.

## 1. How we work
- **Game changes are made in the planner at `/planner/`,** the only planner. Orders, scheduling, retimes and the rest
  go on as normal, and so do the Saturday review and the monthly work. Claude's data-only changes go in as below. The
  old planner, its way back at `/planner/old/` (which now goes to `/planner/`) and its code freeze went with the
  clean-up. *Since 14 Oct (#18, build pull requests 13 and 14) · why (Gitesh): the trial of the new planner passed
  ("all looks good"), and the clean-up was asked for the same day, so there is one planner, one way of saving and no
  copies to keep in step.*
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
    output folder `web`, Node 22 (`.nvmrc`). It builds the planner (`app/planner/`) into `web/app/`, served under
    `/app/` with its page at `/planner/` (since the switch, 14 Oct; `web/_redirects`). A build that fails leaves the
    last good version live. *Since 12 Oct (#18,
    build pull request 1) · why: the planner is a React app that has to be built; the checks run the same build.*
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
  the fares userscript on the saved fares form and answer (since 21 Oct); the capture's world scan against `gscan.py` on
  the same saved pages (since 21 Oct);
  the planner's install, type check, lint, unit tests and build; the planner's screen figures (Home, Tails, the
  planning library's schedule checks) on a dated sample against saved answers; the planning library's cases and its optimiser against
  plan.py's saved answer; the weekly report end to end on a small sample, its money from the figures; every website
  page, the planner's sign-in at `/planner/` and the planner's addresses). When the database, the planner or the
  library changes, the *Database rehearsal* also generates the planner's types again from the copy (they must match
  the committed `app/planner/src/db/types.ts`), has the planner sign in, read and save on the copy, open every screen
  at a frozen moment at 1280 and 380 px wide with no errors and no sideways scroll, and save through every kind of save
  each screen has, each checked against the rows recorded for it; reads a saved evening of each capture page kind and
  replays every kept capture page, each evening judged ok (#21); and when there are database changes, it backs the
  copy up and restores it as the nightly job does. *Since 14 Oct (the clean-up, build pull request 14) these replace
  the side by sides with the old planner.*
  **Claude never asks for, or makes, a merge while any check is red.** Every bug fixed gets a test. When a change is
  meant to move a number, the pull request updates the saved answers and says which moved and why. How to run and
  update them: `tests/README.md`. *Since 8 Oct (#9) · why: nothing ran by itself, and 9 of 11 tests couldn't run.*
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
  *Since 8 Oct (#10) · why: nothing explained how the parts connect, so every new chat rediscovered it.*
- **A new table grants its own access.** Tables created in `public` get no access for the website (`anon`) or staff
  (`authenticated`) by default, on live and on the rehearsal's copy, so each new table's migration grants exactly what
  the planner or website needs (`airline_order_cabins`: staff read and write), and nothing for a table only the
  database's own functions use (`capture_keys`). The rehearsal's checks fail on a table the planner can't reach.
  *Since 20 Oct · why (Gitesh, agreed): Supabase stops granting new tables to the Data API by default on 30 Oct; we
  already worked that way, but the rule wasn't written down.*
- **Big builds go to a fresh helper.** Decisions and reviews stay in the Building chat. Each sizeable build gets a
  written spec (what, why, which files, what the checks should show) and goes to a helper that starts with a fresh
  memory: it reads `CLAUDE.md`, the map and the manual, writes the code, runs the checks and opens the pull request.
  Claude reviews it against the spec and the checks before asking for "merge". Small fixes can be made directly in the
  chat. A new Building chat starts at each step of the decision list, once anything worth carrying is in the
  repository or the project files. *Since 8 Oct (#26) · why: the old Building chat lost detail as it filled; a clean
  memory per build fixes that with no extra steps.*
- **Data-only changes go straight in, to the tables:** plan cards, to-dos, notes, logs. Either through
  `planner_save(changes, client)`, the planner's own way of saving (one call of row changes, each from the
  `updated_at` it was read at; logged as actor planner with the client named, e.g. `claude <chat>`), or plain SQL on
  the tables, starting with `select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail',
  '<chat>', true);` so the change log names the chat (design §6). Times on the tables are UTC (flight legs and
  plan-card legs); the planner shows a change the next time it reads the table. *Since 8 Oct (#2); to the tables since
  10 Oct (#13, pull request 9); through `planner_save()` or plain SQL since 14 Oct (the clean-up removed
  `planner_item_put()` and `planner_item_delete()` with the adapter) · why: the planner reads and saves the tables
  directly.*
- **Rule numbers have one source:** the database's `settings` (our own choices, with an airline's override where it
  has one) and `world_rules` (Gander's house rules, game settings and #12's permissions). The figures in §3, §4, §5 and
  §9 name their row; a rule change updates the row and this manual together, and nothing else holds a copy (the
  planner and the library read the tables). *Since 10 Oct (#13, pull request 9; design §11, choice 3); the old
  planner's copies in its code, and the cross-check that kept them in step, went with it on 14 Oct (the clean-up) ·
  why: the same number lived in the manual, the planner and the scripts, and drifted (the connection buffer, 9 Oct).*
- **To-do board:** anything Gitesh needs to check or do goes on the planner's To-do board (on Today since 20 Oct);
  Claude marks it resolved when he reports back. *Since 30 Sep.*
- **No one-week aircraft checks.** A new schedule is checked once, when it's filed (the planner checks each card against
  the game, §4), and the capture's page checks show each night whether it flies (§7). *Since 15 Oct · why: Gitesh no longer wants them.*
- **Every decision gets the full brief** (format in `docs/briefs/README.md`): decision and recommendation first; then
  an options table with growth, profit a week, cash at the lowest point, opportunity cost, risk and whether it's easy to
  undo; then the background with sources and competition, scenarios and the risk of waiting, and what would change the
  recommendation. Save it in `docs/briefs/`. Applying an existing rule is not a decision and gets no brief.
  *Since 8 Oct (#5) · why: almost every decision spends cash or opportunity, so each deserves full attention.*
  - **A new aircraft's routes get a full brief only when the choice is a real trade-off:** a new city, a new base,
    moving an aircraft off a route, or options that differ in more than timing. Adding frequency to routes that already
    sell out applies the growth rule (§3): its record is the plan card's note (the routes, connections, maintenance and
    hours, and the options set aside), shown to Gitesh in chat before he schedules. *Since 16 Oct · why (Gitesh): a
    brief for every aircraft was heavy, and the real weighing was over new routes.*
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
  | Saturday review | Every Saturday: the world scan's age (the scan runs with the evening capture; `gscan.py` by hand if it's old), weekly report, connection audit, the airlines' newsroom roundups, fare plan and the weekly review. On the first Saturday of the month also the weekly report's month page, gander monthly and strategy (bases, focus cities, holdings, long-term direction). One review chat for both since 15 Oct (Gitesh) |
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
  **The country rule applies where the rightful airline can fly the pair from one of its own bases.** Where it can't
  (Gatwick–Atlanta: Pan Am has no base at either end), the airline that has the pair on its list keeps it, so no market
  drops off the map. *Since 21 Oct · why (Gitesh): applying the country rule literally removed 53 pairs no other airline
  could fly; they were restored the same night.*
  *Since 23 and 26 Sep · why: our airlines shouldn't compete with each other.*
- **Destination shape:** in time, fly every route a real airline flies from each hub and focus city. Plan as if money
  isn't the limit, and grow at the group's own pace. *Since 23 and 29 Sep.*
- **Scale models** (each airline's counterpart in the Airbus world): Virgin → British Airways, Pan Am → Pan Am,
  China Eastern → China Eastern, Malaysia → Singapore Airlines; Kingfisher → Inter Connect (Ellinikon world). Ryanair
  covers the Europe the others can't. *Since 29 Sep.*
- **Malaysia:** make KUL a world transfer hub; build the Asian feeder network before any long-haul. *Since 29 Sep ·
  why: long-haul would have no loads without the feed.*
- **Kingfisher:** India is open; aim to capture all of it. *Since 2 Oct.*
- **No new airlines before January 2027:** the two low-demand holdings the house rules allow (§9) wait until then.
  *Since 15 Oct (Gitesh).*

**Bases** (main hub first):

| Airline | Hubs | Focus cities | Next |
|---|---|---|---|
| Pan Am | JFK, Los Angeles, Dallas | ORD, SFO, SEA | — (LAX and Dallas off hold 20 Oct; they open with November's trunks) |
| Kingfisher | Delhi | Hyderabad, Bengaluru, Chennai, Kolkata (all four wait for Delhi's 750 under hubs first, §3) | Mumbai |
| Ryanair | — (all bases are equal focus cities, point to point) | Paris CDG, Amsterdam, Barcelona (opening with the 14 Oct order) | Milan and Munich; no eastern base for now |
| Virgin Atlantic | Gatwick, Manchester | Edinburgh | — |
| China Eastern | Shanghai PVG, Xi'an, Kunming | Beijing Daxing, Shenzhen | — |
| Malaysia | KUL | — | — |

*Base roles from 29 Sep, Kingfisher from 2 Oct, holds from 5 Oct; Ryanair's Barcelona decided 14 Oct (brief
`docs/briefs/2026-10-14-ryanair-order.md`); Ryanair's CDG and Amsterdam made focus in the data 15 Oct (Gitesh: none
less important than another, point to point rather than hubs).*

## 3. Fleet and orders
- **Fleet types, as the route needs:** every airline may fly any of our types where a route calls for it, sized by the
  city's stars and picked from the default line (both below), and the A350 only where range demands it. *(Wording
  aligned 21 Oct: "the A321neo by default" had been left standing after size by stars, 18 Oct, and smaller wins, 20
  Oct, replaced it.)* Ryanair
  flies the A320 family and the E195, no A350. The three families (A320 family, E195, A350) are the most any airline
  has; no 787, CRJ or A319. Each family is its own delivery line (the order queues, below). *Since 17 Oct · why
  (Gitesh): types are chosen per route, not fixed per airline; three maintenance families are free, a fourth costs 15%
  more maintenance (28 Sep).*
  - **Size by city stars:** 1- and 2-star cities get the E195; 3-star the E195 or the A320neo; 4-star any of the
    E195, A320neo and A321neo; 5-star the A320neo, A321neo or XLR (the XLR beyond an A321neo's reach). Within a band,
    the smaller type wins, heavy routes included: a busy pair gets more flights on more aircraft, not a bigger
    aircraft, since bookings are divided among the flights on offer and more flights give more connections. A bigger
    variant only where the route needs its reach. The game's markets point the same way
    (its secondary and small markets default to the E195's cabin). The A320neo shares the A320-family line, the E195 has
    its own. A cabin layout takes a couple of minutes to set up in the game, so a missing layout is never a reason to
    pick a type. *Since 18 Oct · why
    (Gitesh): bookings are divided among the flights on offer (§9), so more, smaller flights take more of a market than
    fewer big ones; the bigger types go where a city's demand is big enough to fill them.*
- **The default line: the cheapest variant that seats the market and reaches the city.** Stars set the size (above),
  smaller wins within the band, and distance picks the variant (list prices; range with a full load, from the game's
  aircraft pages, 18 Oct). The current fleet stays as it is; new orders pick from this line.

  | Size | Variant | Seats | Reach | List price | Use |
  |---|---|---|---|---|---|
  | Small | E195-E2 | 146 | 3,542 km | 35.4M | the default small aircraft |
  | Small | E190-E2 | 114 | 4,065 km | 33.7M | 3,542–4,065 km, or the thinnest 1-star city |
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

  The listed range is with a full load and is not a limit: the game flies longer routes with fewer seats. Tested 21 Oct
  (same cabin, the game's route evaluation): up to about 14,200 km every A350 keeps its full cabin and the -900 is the
  cheapest per seat (LA–Gatwick 334 against the ULR's 337 and the -1000's 342; Mumbai–LA 527, 535, 543); beyond about
  15,000 km the -900 loses seats fastest and the -1000 is the cheapest (Dallas–KL 566 against 618 and 680; Sydney–JFK 623,
  671, 744). The ULR is never the cheapest, so it is off the line. *Since 21 Oct (Gitesh).*
  Left out because another variant beats them: the A350-900ULR (above), the A319neo (more per seat than the A320neo SHARP at every reach), the
  A321neo Medium, the A321XLR LIGHT and Heavy. Still three families: the A320 family, the E-jet E2 and the A350.
  *Since 18 Oct · why (Gitesh, agreed): the LIGHT variants reach only 4,192 km (A321) and 3,690 km (A320); the LR
  reaches 5,809 km for 3M less than the XLR, and the SHARP is the cheapest 189-seater.*
- **Order across both delivery lines:** A321neos go on the big routes that sell out, where seats absorb the demand;
  E195s go on short, thin and new markets, where departures count most. An E195 is ordered on an evening when the cash
  forecast covers an E195 (1.8M) but not yet an A321neo (2.4M), rather than waiting a day for the A321neo, so both
  lines keep delivering. Each evening's proposal (§4) says which type each route takes. *Since 18 Oct · why (Gitesh, agreed):
  under market share first, an E195 buys about a third more departures for the money (about 310 a week per 10M against
  235) and comes sooner on its own line, while the A321neo buys more seats (about 1,000 per 10M against 810); cash, not
  the lines, limits orders (an aircraft every 2 to 2.5 days per airline against a line delivering every 15 or 21
  hours).*
- **Reach first:** new aircraft go into the short and medium-haul narrowbody network; long-haul comes later.
  Kingfisher's two Delhi–JFK A350s stay as they are. *Since 28 Sep.*
- **Route first, then the airline, then the aircraft.** The Scheduling chat picks the routes the group should open
  next, then the airline that flies them (hubs first and one airline per city pair, below and §2), then the variant
  that seats the market and reaches the city (the default line, above) and its cabin. That is what gets ordered: the
  plan card, with its routes, variant and cabin (`plan_cards.config_id`), is written when the aircraft is ordered.
  *Since 19 Oct · why (Gitesh): the variant can't be chosen without knowing where the aircraft will fly, so the routes
  are decided first.*
- **Who orders:** Claude recommends what to order; Gitesh orders in the game and says so; Claude logs it. *Since 2 Oct.*
- **Order every evening the forecast allows, not in batches; keeping the order queues full comes first:** after each
  evening's capture, the Scheduling chat looks at each airline's order queues (three delivery lines each, Ryanair two)
  and its cash forecast, and proposes the aircraft that can be ordered and the routes for each, with variant and
  cabin. Where cash allows more than one option, the route we most want to fly decides (market share first, below).
  The proposal goes one airline at a time: each airline's order is decided, ordered and logged before the next is
  shown. Gitesh orders that evening. *Since 18 Oct (option C); the order queues first and the choice by route since 19
  Oct; one airline at a time since 21 Oct · why (Gitesh): the group's cash supports about two aircraft a day; weekly
  batches left it waiting, and an empty line is an aircraft lost; one airline at a time keeps each decision in view.*
- **When an airline can order: the cash forecast.** Planner → Today → Orders says who can order now or from when, and
  the safe types; the detail is Performance → the airline → "Cash, next 14 days": captured cash, plus flight
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
  - If an airline hasn't been captured, get the capture first. Never use the surplus figure.
  - The forecast is worked out by `cash_forecast()` in the database (several orders tested together with `p_orders`);
    the planner's Performance screen shows it, and Today's Orders the types safe now (#19, build pull request 3).
- **The order queues:** each airline has one delivery line per family, and the aircraft on a line arrive one after
  another: an A320-family aircraft (A320neo, A321neo and XLR share the line) every 21 hours, an E195 every 15 hours, an
  A350 every 30 hours. Order planning keeps the queues in mind (Today → Orders, each airline's delivery lines): what each airline still
  has to arrive on each line, when each line runs dry, and when a new order's aircraft would arrive. An empty line is a
  line standing idle. A new order joins the end of its line: on an idle line its first aircraft arrives one interval
  after the order (the 18 Oct orders: A321neos 21 hours later, E195s 15), on a busy line one interval after the last
  aircraft already queued (EI-ABU, 21 hours after EI-ABT). *Since 17 Oct · why (Gitesh): plan future orders with the
  order queue in mind.*
- **Market share first, profit second:** every airline grows to take and hold the biggest markets, rivals' included.
  Route choices lead with the largest city pairs (5-star, and the pairs rivals fly most) and prefer shorter sectors where
  they give an aircraft more departures a day; going head to head with a rival is welcome. Capturing the demand and
  holding the departures leaves new competition little room to move in. Profit still has to be there: the cash forecast
  and its cushion, the fare floor, the fix and losing-money marks, hubs first and one airline per city pair don't
  change. *Since 18 Oct · why (Gitesh): market share first; if we capture the demand and block more slots, new
  competition can't move in.*
- **Add a flight or raise fares, by profit per aircraft hour:** a sold-out route is marked **add a flight** when its
  profit per aircraft hour is at or above its airline's middle route, and **raise fares** when it's below. An aircraft
  hour is the flight's block time plus the type's turnaround (`aircraft_types.min_turn_min`) and the turn margin
  (`settings.turn_margin_min`, 10 minutes): the hours the aircraft can't fly anything else. A route with no legs on
  record has no aircraft hours and is still compared by profit per flight. The fix, losing-money and cash rules don't
  change. Worked out by `route_profit()`, which gives each route's `aircraft_hours` and `profit_per_aircraft_hour`.
  *Since 17 Oct; built 17 Oct · why (Gitesh): profit per flight favours long routes because they take longer; per
  block hour alone would over-reward short hops, whose turns tie the aircraft up for nearly as long as they fly. Brief:
  `docs/briefs/2026-10-17-add-or-raise.md`.*
- **New routes aren't judged for a week:** a route launched fewer than **7 days** ago gets none of the problem marks
  (losing, fix or reduce), so Today's routes to fix and Performance's Fix or reduce skip it. Its launch day is its earliest
  rotation's (a second daily added later doesn't make an old route new). Sold-out marks (add a flight, raise fares) apply
  at any age. The number is `settings.growth_new_route_days` (7). *Since 16 Oct · why (Gitesh): PVG–CCU and KUL–TRV were
  marked losing after one round trip, on the day they launched; the losing mark needed only 2 departures.*
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
- **How it runs: every evening, from the order queues; a card with each order.** After the capture the Scheduling
  chat proposes the aircraft to order and the routes for each (§3, "Order every evening"). When Gitesh orders, Claude
  writes the plan card with its routes and cabin (`plan_cards.config_id`: filing fits it and logs its first fit at its
  price), checked at both ends. The card stands: when the aircraft arrives, Gitesh schedules it in the game as the card
  says and **files it within a day of arrival**, and the planner checks each card against the game. **The background
  starts
  from the airline's briefing** (`python3 scripts/briefing/brief.py <airline>`, `scripts/README.md`), which gathers its
  money, fleet, routes, hubs, deliveries and plan cards with their check, to-dos, fare plan, rivals from the latest scan
  (with its date) and the capture's state in one step; anything more comes from the call the map's guide names
  (`docs/architecture.md`, "Which call answers which question"), not from guessing at tables. *Since 19 Oct (each
  evening's proposal from the order queues, the card with the order: route first, then airline, Gitesh); daily orders
  since 18 Oct (option C) · why (Gitesh): to add aircraft every day. Cash supports about two a day; deciding each aircraft on its own, and
  aircraft waiting days to be filed, were the limit. Brief: `docs/briefs/2026-10-18-accelerate.md`. The briefing
  since 15 Oct (#24).*
- **Fly each aircraft as much as it fits:** the Saturday review lists every aircraft under **12 block hours a day** and
  whether one more short rotation fits it, Ryanair's and Virgin's first (11.0 and 11.2 hours a day on 17 Oct,
  against Malaysia's 13.3). Tails' own flag stays at `settings.aircraft_block_target_h` (10). *Since 18 Oct (option
  C) · why: more flying from aircraft already paid for raises profit per aircraft, and so the pace of orders.*
- **Every aircraft is named by its tail number and base:** whenever any chat mentions an aircraft or one of its
  flights (an order, a plan card, an arrival, a retime, the connection audit, a proposal), it gives the registration and
  the base it flies from, e.g. "N019AW (JFK)". For an order not yet registered, the airline, variant and base. *Since 19 Oct · why (Gitesh): so each
  aircraft can be found in the game at once.*
- **The planner mirrors the game.** Routes and aircraft enter the planner only once they're in the game; plans live on
  plan cards. *Since Sep.*
- **Until 31 October, only new routes:** every flight planned from 18 to 31 Oct opens a route the airline doesn't fly
  yet: no second dailies or extra frequency on existing routes, whatever the growth signals say. Plan cards made before
  18 Oct stay as they are, filed or not (EI-ABS and EI-ABT keep their second dailies). *From 18 Oct to 31 Oct · why:
  Gitesh, 18 Oct.*
- **From 1 to 30 November, every new order fortifies the trunk routes:** a trunk route is any route between two of our
  bases (hubs and focus cities, any of our airlines). Orders that month add flights on trunk routes we fly, and open
  trunk routes we don't, until each is fortified. *From 1 Nov to 30 Nov · why (Gitesh, 20 Oct): fortify the routes
  that connect our bases completely.*
  - **Fortified** means it no longer sells out: flights are added while a trunk runs at 95% or more
    (`settings.growth_*`'s sold-out test), and stop once its loads fall below that.
  - **Flown and unflown trunks weigh equally:** adding to the trunks we fly and opening those we don't (within reach of
    the default line, §3) are chosen together, by profit per aircraft hour where flown and by market size where not.
  - **Hubs first is suspended for trunks in November:** any base can take an aircraft for a trunk route. One airline per
    city pair (§2) still applies, and so does the cash forecast's cushion.
  - **Only trunks that make sense:** a pair is opened only where the market is there and the route makes business sense
    (no Kolkata–US direct, say), within reach of the default line. Munich, Milan Malpensa, Mumbai, Los Angeles
    and Dallas count as bases; no base is on hold (Gitesh, 20 Oct).
  - **Long-haul trunks are in too:** any trunk that makes sense, at any distance, on the default line's A350s where
    beyond the A321XLR. For November's trunks this sets aside reach first (below) and Malaysia's feeder-first order
    (§2). *Since 20 Oct (Gitesh): "for this plan, everything which makes sense."*
  - **Shortest to longest:** new trunks open in order of distance, shortest first, while keeping every delivery line
    filled (an idle line takes the shortest trunk its family can fly). This puts the narrowbody trunks first and the
    A350 trunks last. *Since 20 Oct (Gitesh).*
  - **Narrowbody trunks first:** each evening's orders fill the short and medium trunks first (more departures per
    dollar); A350 trunks follow. The plan: `docs/briefs/2026-10-20-november-trunks.md`.
    *Since 20 Oct (Gitesh).*
  *Details agreed 20 Oct (Gitesh).*
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
- **A second daily** goes wherever it makes the most connections, with no spread of our own: at least 5 minutes
  from the other flight on the route, Gander's house rule (`world_rules.same_route_gap_min`, §9), and further apart
  only when there's a business case. `settings.second_daily_gap_h` is 0, so the optimiser and Routes check only the
  house rule. *Since 15 Oct · why: Gitesh, the 3 hours had no business case; we maximise connections within the
  world's rule.*
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
  New Virgin Heathrow routes (Manchester and Edinburgh to Heathrow, as feeders for the group's long-haul there) are a
  late-game step, once the other hubs are built out. *Since 21 Oct (Gitesh).*

## 5. Cabins and fares
- **The cabin is chosen with each order,** among the layouts set up for its variant: if one route takes more than
  **65% of the aircraft's block time** (`settings.cabin_route_share_pct`), the layout that route's market calls for
  (`markets.layout`: Standard, Leisure, Leisure Plus or Comfort, in Reference → Markets; a route's own cabin choice wins
  over it); otherwise the layout with the most seats. Ryanair flies Standard only; Standard (economy only, no business)
  is Ryanair's, so the other airlines choose among the two-cabin layouts (Leisure, Leisure Plus, Comfort), and "the most
  seats" for them is Leisure (clarified 21 Oct, Gitesh). We don't refit. The plan card
  suggests its cabin by this rule (Tails → Deliveries, with **Use the suggestion**) and the card check flags a card whose
  cabin is missing or differs. *Since 20 Oct · why (Gitesh): the new layouts aren't captured by the defaults. Built 21 Oct
  (spec `docs/specs/2026-10-21-cabins-new-rule.md`): the Cabins board and its refit settings went, and each market keeps
  only its layout.*
- **Fares:** new routes launch at 100% of the standard fare in both cabins; Ryanair 85%, economy only
  (`settings.fare_launch_pct`, with Ryanair's override). Weak routes get cut rather than launched cheap. **A new
  flight on a route already flown launches at that route's level** (the plan card shows it), not at launch fare.
  *Since 20–21 Sep · why: every lane ran full at lower fares, and launching low then raising across 50 routes is too
  much work. The new flight's rule since 21 Oct (Gitesh).* As of 21 Oct every route is at its launch level: legacy
  airlines 100% of the default price, Ryanair 85% (Gitesh); the fare ladder's first moves start from there.
- **The fare ladder, every Saturday.** Each cabin of each route has a **level**: its fare as a % of the game's default
  price (launch: 100%, Ryanair 85%). At the Saturday review, from the week's captured flights in that cabin:
  - **up 5 points** when every flight sold out (at least 5 departures in the 7 days);
  - **hold** when 90–99% sold out;
  - **down 5 points** when under 90% sold out, then hold for 2 weeks before climbing again.

  New routes start after their first 7 days (§3), and **a route that gained a frequency in the last 7 days holds**
  for that week (`settings.fare_ladder_capacity_hold_days`, 7: its newest rotation under 7 days old, its first older),
  so the ladder judges it at its new size, not on the drop the extra seats cause (Gitesh, 21 Oct). Every
  plan card shows the fare level of each route it flies, so a new flight is priced like the rest of its route. **A
  route whose captured fares don't match its level is set back to it:** when any flight of its latest captured day is
  more than a point off (against the route's fare on 21 Oct, when every route was at its launch level), the planner
  lists a change each way at its level, first, and the fares userscript makes it with the week's changes; not for a
  route on the fare plan this week, a new route, or one not captured since its newest flight launched (since 21 Oct).
  The level never goes under launch, nor under the 60% floor where
  another player flies the route. **For now it goes at most 20 points above launch** (120%, Ryanair 105%): the game's
  passengers are price-sensitive and higher fares may hurt the airline's image, so the cap is lifted only once loads
  and image show it's safe. A rival starting on the pair (from the scan) pauses that route for a week. The planner
  works out each route's level and Saturday's moves, and lists the fewest changes to make in the game: **Ticket price
  adjustment** with the calculation baseline **default price**, so each change sets the level itself, **route by route
  only** (From A to B, and From B to A): never a whole base, so routes under 7 days old are never touched (Gitesh,
  21 Oct: loads are high because the world is young). The fare plan records them and the next capture ticks each off.
  **The fares userscript makes them** (`capture/fares_apply.user.js`): after **Put on the fare plan** in Performance,
  Gitesh presses **Apply fare plan** in the game and watches. It reads this week's planned changes the captures haven't
  seen yet (`capture_fare_actions()`, with the capture key), shows each airline's count and asks once, then makes them
  for every airline, one at a time, 2 seconds apart, changing prices only, and stops at the first problem, saying which
  change and why; run again, it reads only what's still unseen. Never on a schedule or without him watching. *Since
  21 Oct · why (Gitesh): the route-by-route changes are a few hundred on a Saturday; his decision. The simulogics terms (§4 II) forbid scripts in general, but Gander is an exclusive world whose owner
  sets the rules (§9): the capture, the salary script and the scanner are allowed there; the fares script is to be
  recorded the same way once Gitesh confirms it with the owner (spec `docs/specs/2026-10-21-fares-userscript.md`).* Fare moves never
  appear in Needs attention. The numbers are settings (step, up, down, hold weeks, cap, and since 21 Oct the hold
  after a new flight, `fare_ladder_capacity_hold_days`). *Since 21 Oct · why (Gitesh, option A
  of `docs/briefs/2026-10-21-fare-ladder.md`): 88–98% of economy flights and 98–100% of business flights sell out at
  launch fares, no fare had ever been raised, and each 5% step that holds is worth about 5M a week.*

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
  active airline has been captured for it. Loads are typed in by hand (Systems → Manual entry) only if a capture fails.
  *Since 7–8 Oct; salaries taken out 10 Oct; into the tables only since 10 Oct (#13, pull request 9).*
  - **Then the world scan, when one is due:** after the last airline, the capture scans the world if the latest finished
    scan is at least `settings.scan_every_days` capture days old (1: every evening). It reads the same pages as
    `gscan.py`, at its pace (every airline in Gander with its schedule, then the airport pages for our bases, the big
    rival hubs and the latest scan's 20 busiest airports), and sends them with the capture key (`capture_scan()`). It
    takes a few minutes more (about 5); keep the tab open. The panel shows "World scan: 120 of 163 airlines…", then
    "World scan done", with a Stop button throughout; a page reload carries on where it was. No scan if a capture page
    failed that evening; a failed scan page is logged and skipped, and with more than 10% of the airlines failed the
    scan isn't finished, so the Systems board keeps the last finished one. *Since 21 Oct (spec
    `docs/specs/2026-10-21-scan-in-capture.md`) · why (Gitesh): competition analysis and the evening order proposal need
    fresh rivals, and the scan in the capture costs no extra work; raise `scan_every_days` to 3 (about twice a week) if
    the evening gets long.*
  - **Each page is checked as it arrives** (#21): ok, short or broken. Loads are short below 90% of the airline's
    flights scheduled in the page's window (the 24 hours before the capture, a new rotation counting from the day after
    it launched, and a new aircraft only once a capture has shown it flying; setting `capture_loads_min_share`); a bank
    statement is short with no lines, or below half the median of the airline's recent nights
    (`capture_statement_min_share`); events or an income statement with no rows are short; a balance sheet without the
    cash account (2800), or a page that doesn't read, is broken. The capture's panel ends each airline with "all good"
    or what came in short or broken ("loads 12 of 78 flights"); Today's capture line and needs attention show a short or
    broken page the same night, and the Systems board shows each airline's verdict. **If a page comes in short or broken,
    capture that airline again** while the game's last 24 hours still hold the loads. A saved evening of each page kind is
    tested on every pull request. No alert outside the planner: a missed evening still shows on Today after 26 hours. *Since 14 Oct
    (#21) · why: 11 and 12 Oct were missed and nothing said so for two days; loads for about 780 flights were lost.*
- **Salaries:** a separate script, "Salaries: this airline", which Gitesh runs by hand when he chooses. It changes only
  the airline he's on, setting each position to 10% above the country average. *Since 10 Oct · why: Gitesh suspects the
  nightly adjustment of all six airlines was inflating salaries.*
- **Every Saturday:**
  - the world scan runs with the evening capture (`scan_every_days`, above), so the report and gander monthly read
    this week's rivals; if the Systems board shows it old (amber over 8 days), run `scripts/scanner/gscan.py` by hand
    first (the Saturday chat; about 5 to 10 minutes). *Since 21 Oct (spec `docs/specs/2026-10-21-scan-in-capture.md`);
    a Saturday step since 14 Oct (#22) · why (Gitesh): only one scan had been taken by 14 Oct, because no step called
    for it; since 21 Oct the capture takes it.*
  - the weekly report: a PDF briefing written for a CEO, no fixed template. It covers competition by market (for the
    group and each airline), risks, opportunities, our plan and progress, route profit, growth signals and fare-plan
    results, each airline's net cash a day (flight profit less leases and salaries) against the price of one aircraft, the
    pace towards an aircraft a day per airline (*since 20 Oct, Gitesh*), and each of our airlines against its three biggest competitors: the three outside airlines with the most
    weekly departures on its own city pairs in the latest scan, each with its size and growth since the previous scan
    beside our airline's (*since 18 Oct · why (Gitesh): to see whether each airline is gaining on its rivals*). It is
    the only investor report: on the first Saturday of the month it adds a page on the month just
    ended (month-on-month figures and the month's decisions). *The separate monthly report was dropped 15 Oct ·
    why: Gitesh, it repeated what four weekly reports already say;*
  - the connection audit across all hubs (valid connections, near misses, and retimes of 10 minutes or less);
  - one newsroom roundup per airline of its new routes and extra flights (§8);
  - the weekly review together: the fare ladder's moves (§5), aircraft under 12 block hours a day (§4), orders and
    hubs first.

  *Since 5–8 Oct.*
- **Every night, after the capture:** an automatic backup copies the database and the site's files, restores the copy
  to prove it works, uploads it to Cloudflare R2 and reports the result. Each night's copy is kept 30 days. The
  month's first is kept for good, in R2 and as a file on a GitHub release in the private repository `equinox-backups`,
  where the backup job lives. Copies no longer go into git. Each run's R2 key is recorded in `backup_runs`. The
  database rehearsal reads last night's copy from R2 with a read-only key. Live data never goes into the
  code repository (small test samples aside, see §1). The planner warns on Today if there's no good copy from the last
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
- **Every job writes a row to `job_runs`,** and the planner's Today warns when the last good backup is more than 30 hours
  old, the latest snapshot is more than 30 hours old (or the 10:00 UTC job hasn't run for 30 hours: the scheduler may
  have stopped; restart it from Supabase's settings), the month's archive hasn't run by the 3rd, or any job's last run
  failed. *Since 11 Oct (#13 pull request 7, the jobs brief) · why: the daily record needs a fallback, the capture
  tables their clean-ups, #16 its archive before 1 Dec, and a job that fails must be seen.*
- **The Systems board, at the top of Systems** (#23; of Check until 20 Oct), is where "all good" shows: one line
  each, green, amber or red, for each airline's evening capture (when, and its verdict), the daily snapshot (taken by
  the capture, or by the fallback and so incomplete), the nightly backup (last good copy, restore check, size), the
  monthly archive (this month's state, due by the 3rd), the clean-ups, the world scan's age (amber over 8 days, red over 15; it runs with the evening capture since 21 Oct), the planner's own build
  (the time and change it was built from: after a merge, a time that hasn't moved means the deploy failed), and the
  usage the database can measure against its triggers (§1): database size (350 MB), the report PDFs in `site_reports`
  (50 MB) and the size of `site_public()` (500 KB), amber from 70%, red at the trigger. The marks use needs attention's
  limits above (capture 26 and 48 hours, backup and snapshot 30 hours). Today's needs attention keeps listing the
  problems. *Since 14 Oct (#23) · why: Home showed problems only, and deploys and usage nowhere.*
- **First Saturday of the month:** gander monthly and the monthly strategy session, and the weekly report adds its
  page on the month (above). *Since 8 Oct; no separate monthly report since 15 Oct.* Also a look at Supabase's usage page for what the database can't see: egress
  against §1's 4 GB and the website's calls a day against #20's 1,000 (*Decided, not yet built*). The database's size,
  the report PDFs and the size of `site_public()` are on the Systems board. *Since 14 Oct (#23) · why: the board
  measures the rest every time Systems opens.*

## 8. Writing, website and newsroom
- **Writing for Gitesh:** he mostly reads on his phone. Lead with the answer, keep it short, and use tables for options
  and comparisons.
- **Newsroom posts read like a real airline's:** no cabins, bank timings or other internal detail, and no references to
  the game. *Since 5 Oct.*
- **What the newsroom posts:** one roundup per airline each Saturday, covering its new routes and extra flights since
  the last one (Saturday review chat). No post for an airline with nothing new. No posts for new aircraft. *Roundups
  per airline since 17 Oct · why (Gitesh): one post per airline reads like each airline's own news. No delivery posts
  since 20 Oct (Gitesh).*
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
- Bookings on a route are divided among the flights on offer, so more departures win more of a market than fewer,
  bigger flights (Gitesh, from playing the game, 18 Oct).
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
| 21 Oct | Every Saturday, first the world scan: `gscan.py`, run from the Saturday chat (since 14 Oct, #22) | The world scan runs with the evening capture when one is due (`scan_every_days`, 1: every evening); `gscan.py` by hand only when the Systems board shows it old (§7). Why: Gitesh, competition analysis and the evening order proposal need fresh rivals (brief `docs/briefs/2026-10-21-competition-analysis.md`) |
| 21 Oct | The evening proposal shows every airline that can order at once | One airline at a time, each decided, ordered and logged before the next (§3). Why: Gitesh |
| 21 Oct | The fare ladder's game changes: whole bases first, then single routes | Route by route only, so new routes are never touched (§5). Why: Gitesh, loads are high because the world is young; a base change moved new routes too |
| 21 Oct | Refits: a refit costs about 0.2M (`settings.cabin_refit_cost`) with no time out of service; Systems' Cabins board listed each aircraft whose cabin differed from what most of its flying wanted (a refit paying from 70%, `cabin_refit_share_pct`), with Refitted to, Keep as is and Show again; each market kept a default aircraft, default cabin and fares (Reference → market defaults), used only to tell which layout it called for | We don't refit: the cabin is chosen with each order, and the plan card suggests it by the 65% rule (`cabin_route_share_pct`), warning when the chosen one differs; each market keeps only its layout (`markets.layout`) (§5). Why: Gitesh, 21 Oct; the defaults didn't capture the new layouts |
| 21 Oct | Fare changes are occasional tests through the fare plan, reviewed on Saturdays | The fare ladder: each Saturday, up 5 points on every route and cabin that sold out all week, hold at 90–99%, down under 90%; at most 20 points above launch for now (§5). Why: Gitesh, option A of the fare ladder brief; almost every flight sells out and no fare had been raised |
| 20 Oct | Order rotation: each airline's orders rotate big market → more frequency → smaller feeders (Check → Growth → Next move, Log an order as) | Route first, then the airline: each evening's proposal picks by the route we most want to fly (§3). Why: Gitesh, 20 Oct; the board goes with the Today, Performance and Systems build |
| 20 Oct | Within a star band, the bigger type goes where a heavy rival flies the pair or the sector is long | The smaller type wins, heavy routes included: more flights on more aircraft; a bigger variant only for reach (§3). Why: Gitesh, bookings are divided among flights and more flights give more connections |
| 20 Oct | Cabin follows the market default, whatever the aircraft | The cabin is chosen with each order: the layout of the route flying over 65% of block time, else the layout with the most seats (§5). Why: Gitesh, the defaults don't capture the new layouts |
| 20 Oct | A newsroom post per airline on each day it takes delivery of aircraft (Scheduling chat) | No posts for new aircraft; the Saturday roundups of new routes stay (§8). Why: Gitesh, 20 Oct |
| 19 Oct | An order is just the aircraft: base, routes and cabin decided when it arrives, no plan card at order time | Route first, then the airline, then the aircraft: the plan card with routes, variant and cabin is written when it's ordered (§3). Why: Gitesh, the variant depends on where the aircraft flies |
| 19 Oct | A route list per airline agreed each Saturday; the card written when the aircraft arrives and checked against the list | Each evening the Scheduling chat proposes, from the order queues and the cash forecast, the aircraft to order and their routes; between options the route we most want to fly wins; the card is written with the order and stands on arrival (§3, §4). Why: Gitesh, route first, then airline; keeping the queues full comes first |
| 19 Oct | Plan cards to check each leg against the aircraft's reach (decided 18 Oct, not built) | The Scheduling chat checks reach when it picks the variant (§3). Why: Gitesh, the routes are decided before the card |
| 18 Oct | Size by city, as a guide: 4- and 5-star the A321neo; 3-star the A320neo (or A321neo where long or strong); 2-star and short thin routes the E195 | By stars: 1–2 E195; 3 E195 or A320neo; 4 any of the three; 5 A320neo, A321neo or XLR (§3). Why: Gitesh, bookings are divided among the flights on offer |
| 18 Oct | Order the type that earns most (the A321neo first), waiting for its cash rather than ordering an E195 sooner | Order across both lines: A321neos on big sold-out routes, E195s on short, thin and new markets when cash covers one but not an A321neo (§3). Why: Gitesh, market share first: more departures per dollar, sooner |
| 18 Oct | Growth matters as much as profit: every airline's batch includes new markets, not only more flights on proven routes | Market share first, profit second: the biggest markets and rivals' pairs lead the route lists (§3). Why: Gitesh, capturing the demand and holding the slots keeps new competition out |
| 18 Oct | One aircraft at a time, each decided and carded before the next; orders in batches | A route list per airline agreed each Saturday; arriving aircraft take its next routes and are filed within a day; orders every evening the forecast allows (§3, §4). Why: Gitesh, to add aircraft every day (option C) |
| 18 Oct | An order is just the aircraft: routes and cabin are decided when it arrives (the base was taken from the order) | Base, routes and cabin all decided when it arrives; the order's airport is a placeholder (§3). Why: Gitesh, 18 Oct |
| 18 Oct | Scheduling runs one airline at a time once aircraft have arrived | One aircraft at a time, each decided and carded before the next (§4). Why: Gitesh, 18 Oct |
| 17 Oct | A sold-out route is marked add a flight when its profit per flight is at or above its airline's middle route, raise fares when below | Profit per aircraft hour (block time, turnaround and turn margin) against the middle route (§3). Why: Gitesh, profit per flight favoured long routes (brief `docs/briefs/2026-10-17-add-or-raise.md`) |
| 17 Oct | One weekly newsroom roundup for the whole group, no delivery posts | A roundup per airline each Saturday, and a delivery post per airline on each day it takes aircraft (§8). Why: Gitesh |
| 17 Oct | Fleet families: the five legacy airlines fly the A320 family, the A350 only where range demands and the E195; Ryanair the A321neo and E195 only | Any of our types where the route needs it, every airline; Ryanair no A350; still three families at most (§3). Why: Gitesh, the old line read as a fixed list per airline that didn't match the fleets |
| 16 Oct | Every new aircraft's route choice gets a full brief | A brief only when the choice is a real trade-off (new city, new base, moving an aircraft, options beyond timing); frequency on sold-out routes is recorded on the plan card (§1). Why: Gitesh, a brief per aircraft was heavy |
| 15 Oct | Two investor reports: the weekly report every Saturday and a monthly report on the first Saturday, both published to the investor library | The weekly report only, with a page on the month just ended on the first Saturday (§7). Why: Gitesh, the monthly report repeated what four weekly reports already say |
| 15 Oct | A second daily on a route sits at least 3 hours from the existing flight (`second_daily_gap_h` 3) | Wherever it makes the most connections, at least Gander's 5 minutes from the other flight (house rule), spread further only with a business case; the setting is 0 (§4). Why: Gitesh, 15 Oct |
| 15 Oct | Four chats: Scheduling, Saturday review, Monthly (monthly report, gander monthly, strategy) and Building | Three: the Saturday review chat also does the first Saturday's monthly work (§1). Why: Gitesh, 15 Oct, one review chat for weekly and monthly |
| 15 Oct | One-week aircraft checks are Gitesh's, done in the game a week after an aircraft is scheduled or changed (the flights really run as scheduled, no issues); Claude never marks them checked | No one-week checks: the planner's check of each card when it's filed and the nightly capture checks cover it (§1). Why: Gitesh, 15 Oct, no longer wants to do them |
| 15 Oct | The scheduling background (loads, money, network, competition) is gathered by hand for each airline from the captured figures, the planning library, the world scan and the planner's tables | The airline briefing, one command per airline, and the map's guide for anything more (§4). Why: #24, about six calls and wrong column guesses each time |
| 14 Oct | First Saturday of the month: a look at Supabase's usage page (database size, egress, the report PDFs' size) against §1's triggers, and the size of `site_public()` and the website's calls a day against #20's | The look keeps only egress and the website's calls a day; the rest is on Check's Systems board (§7). Why: #23 built the board, which measures them itself |
| 14 Oct | The capture panel lists each page's rows without judging them, and Home warns only after 26 hours | Each page is checked as it arrives, with a verdict in the panel, on Home the same night and on Check (§7). Why: #21, after 11 and 12 Oct were missed unseen |
| 14 Oct | Game changes are made in the new planner at `/planner/`; the old planner at `/planner/old/` is the way back only, nothing is saved in it, and its code is frozen | One planner at `/planner/`; the old one, the way back and the freeze went with the clean-up (§1). Why: Gitesh asked for the clean-up after the switch (#18, build pull request 14) |
| 14 Oct | Data-only changes through `planner_item_put()` / `planner_item_delete()` in the planner's JSON shape, or plain SQL after the `equinox.actor` line | `planner_save()` or plain SQL after the `equinox.actor` line (§1). Why: the clean-up removed the adapter, those functions with it |
| 14 Oct | Until #18 the old planner keeps copies of the rule numbers in its code, and the rule-number cross-check (`tests/rule_numbers_test.py`) fails if they differ from `settings` and `world_rules` | A rule number changes in its setting and this manual together; nothing else holds a copy (§1). Why: the old planner's code went with the clean-up |
| 14 Oct | Until the switch, game changes are made in the old planner only; the new one at `/planner/next/` is for building and review, so the two never save over each other | Game changes are made in the new planner at `/planner/`; the old planner at `/planner/old/` is the way back only, and nothing is saved in it (§1). Why: Gitesh, the trial passed; the switch (#18, build pull request 13) |
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

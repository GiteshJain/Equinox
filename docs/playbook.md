# The equinox. handover guide

Everything someone taking over the game needs: what we're building, the tools, the evening routine, how a new aircraft
goes from order to flying, the Saturday and monthly work, every check and what to do when one fails.

- **The rules themselves are in the operating manual** (`docs/operating-manual.md`). Where this guide and the manual
  differ, **the manual wins**, and this guide is corrected the same day.
- **Detail on each screen:** `docs/planner-guide.md`. **How the system fits together and how to recover it:**
  `docs/architecture.md`. **Why things are the way they are:** `docs/decisions.md` and `docs/briefs/`.
- Written 15 Oct 2026, after the planner rebuild and decisions #21 to #25. "You" is the player. "Claude" is the Equinox
  project in Claude, with its three chats.

---

## 0. The five things that matter most
1. **Capture every evening.** The game keeps a flight's loads for only 24 hours. A missed evening loses them for good.
   On 11 and 12 Oct about 780 flights' loads were lost that way.
2. **Never put two of our airlines on the same city pair.** Each pair has one owner, and ownership never changes.
3. **Order only when the cash forecast says it's safe:** 0.5M left at the lowest point of the next 14 days, counting
   the new aircraft's own lease.
4. **Main hub first.** Every new aircraft goes to the airline's main hub until that hub has 750 departures a week.
   Another base gets an aircraft only for a contested route. Ryanair is the exception.
5. **One thing at a time, and the player decides.** Claude recommends and builds; nothing is built or changed without
   your yes. Code goes live only when you say "merge".

---

## 1. What you're taking over (15 Oct 2026)

**The group:** six airlines in AirlineSim's Gander world, run as one group called **equinox.** (lowercase, with the
full stop). Website and planner: **equinox-alliance.com** (planner at `/planner/`, staff sign-in).

| Airline | Code | Bases (main hub first) | Flying | On order | Routes |
|---|---|---|---|---|---|
| Pan Am | AW | Hubs JFK, Los Angeles, Dallas; focus ORD, SFO, SEA | 15 | 3 | 25 |
| Kingfisher | KF | Hub Delhi; focus Hyderabad, Bengaluru, Chennai, Kolkata (all four wait for Delhi's 750 under hubs first). Mumbai set up, next | 12 | 3 | 19 |
| Ryanair | FR | Five equal focus cities: Paris CDG, Amsterdam, Barcelona, Milan, Munich | 21 | 5 | 48 |
| Virgin Atlantic | VS | Hubs Gatwick, Manchester; focus Edinburgh | 18 | 2 | 38 |
| China Eastern | MU | Hubs Shanghai PVG, Xi'an, Kunming; focus Beijing Daxing, Shenzhen | 18 | 3 | 39 |
| Malaysia Airlines | MH | Hub Kuala Lumpur | 18 | 2 | 32 |

**Arriving now:** 18 aircraft between 16 and 19 Oct: 15 A321neos (all six airlines) and 3 A321XLRs (Pan Am 1,
Malaysia 2). Each one needs the growth loop in section 6 as it arrives.

**Open to-dos on the planner's board (15 Oct):**
- Decide the two low-demand holdings (new airlines): not before January 2027.
- Cancel Pan Am's interline with British Caledonian.
- (Dropped 21 Oct: refitting the 35 A321s still on the old 321-LEI layout. We no longer refit; manual §5.)
- Fix Delhi's early-morning connections when the next Kingfisher aircraft is planned.
- Run `scan_markets.py` once for the 6 Oct world scan (Saturday review chat).
- Review Kingfisher's two Delhi–JFK A350s at the Saturday review on 28 Nov.
- First Saturday of November (7 Nov): the weekly report with October's month page, gander monthly issue 2, strategy session.

**Also open:** two plan-card legs have the wrong service code (B-0162 KWE–PVG and G-AADL AGP–LGW, both should be S3),
and the capture should show Kingfisher's VT-AAE flying 1049/1050 from 16 Oct, not 1007/1008.

---

## 2. Your tools

| Tool | What it's for | Where |
|---|---|---|
| **The game** | Everything that actually happens: orders, routes, schedules, cabins, fares, interlines, salaries | gander.airlinesim.aero, one account with all six airlines |
| **Capture userscript** | One button, *Capture all airlines*, sends each airline's loads, bank statement, income statement, balance sheet and events to the database | `capture/capture_all.user.js`, installed in a userscript manager (such as Tampermonkey) in your browser, with your capture key in place of `__CAPTURE_KEY__` |
| **Salaries userscript** | One button sets every position of the airline you're on to 10% above the country average | `capture/salary_adjust.user.js`, installed the same way |
| **Fares userscript** | One button, *Apply fare plan*, makes the week's fare plan changes in the game for every airline, one every 2 seconds, while you watch (section 7) | `capture/fares_apply.user.js`, installed the same way (the Userscripts app on the Mac or iPhone), with the same capture key in place of `__CAPTURE_KEY__` |
| **The planner** | The staff tool: the network, aircraft, plan cards, checks, money and to-dos | equinox-alliance.com/planner/ |
| **The website** | The public airline site: flights, destinations, live network, newsroom, investors, gander monthly | equinox-alliance.com |
| **Claude (Equinox project)** | Three chats: **Scheduling** (new aircraft, routes, plan cards), **Saturday review** (scan, weekly report, audit, newsroom, review, and on the month's first Saturday the weekly report's month page, gander monthly and strategy), **Building** (code, database, specs, merges). The manual, decisions, map and this guide are in its files | claude.ai |
| **Supabase** | The database, sign-in and photo files. Free plan | project `ulecwsyedvwcxgdzmhoq` |
| **GitHub** | All code and documents (`GiteshJain/Equinox`); the nightly backup job and monthly copies (`equinox-backups`, private) | github.com |
| **Cloudflare** | Hosts the website and planner (Pages) and keeps the backups (R2). The domain renews each October | dash.cloudflare.com |

**Handing over the keys:** keys are never written in a document. The map (`docs/architecture.md`, "Where keys are kept")
names each one and where it lives. A new player needs their own planner sign-in, a new capture key for the userscript
(ask the Building chat to issue one), and access to the game account. If a key may have leaked, replace it (the map
says how).

**Which chat to ask:** a question in the wrong chat gets sent to the right one. New aircraft and routes → Scheduling.
Anything on a Saturday, weekly or monthly → Saturday review. Anything that changes code or the
database → Building.

---

## 3. What we're building: the strategy

### The shape of the group
- **Each airline owns its home region, and one airline owns each intercontinental flow.** Oceania goes via Kuala
  Lumpur, except China–Oceania (China Eastern direct) and US–Oceania (Pan Am).
- **One airline per city pair.** Who owns a pair between countries:

  | Flow | Owner |
  |---|---|
  | US or UK to India | Kingfisher |
  | US to UK, Europe or China | Pan Am |
  | UK to Europe, China or Malaysia | Virgin |
  | Europe or India to China | China Eastern |
  | Anything to Malaysia | Malaysia |
  | Within Europe, where the others don't fly | Ryanair |

  Within one airline, a pair goes under its first-listed hub (Delhi–Mumbai under Delhi). Virgin doesn't fly JFK or
  Delhi. When adding routes from a list, add missing lanes only and never change an owner.
- **The destination shape:** in time, fly every route a real airline flies from each of our hubs and focus cities. Plan
  as if money weren't the limit, and grow at the group's own pace.
- **Market share first, profit second.** Route choices lead with the biggest markets, rivals' pairs included, and
  shorter sectors where they give an aircraft more departures a day. Capturing the demand and holding the departures
  keeps new competition out. The cash forecast, the fare floor and the fix marks still apply.
- **Each airline has a real-world model to copy:** Virgin → British Airways, Pan Am → Pan Am, China Eastern → China
  Eastern, Malaysia → Singapore Airlines, Kingfisher → Inter Connect (another world). Ryanair covers the Europe the
  others can't.

### Each airline's plan
- **Pan Am (JFK, Los Angeles, Dallas):** grow JFK to 750 weekly departures first. LAX and Dallas are off hold (20 Oct)
  and open with November's trunks. No interlines in Canada, Mexico, the Caribbean or Central America.
- **Kingfisher (Delhi):** India is open, so aim to take all of it. Mumbai is next. The two Delhi–JFK A350s stay as they
  are (reviewed 28 Nov).
- **Ryanair (CDG, Amsterdam, Barcelona; Milan and Munich next):** five equal focus cities, point to point, no hub.
  Exempt from hubs first. Flies the A320 family and the E195, no A350. Stays inside the game's EU zone (EU-27, the UK, Norway,
  Switzerland, Iceland); Turkey, Morocco, the Balkans and long haul are out. Fares at 85%, economy only. No interlines
  in Europe. No eastern base for now.
- **Virgin Atlantic (Gatwick, Manchester, Edinburgh):** new London routes go to Gatwick before Heathrow (existing
  Heathrow flights stay). Manchester's contested route is Amsterdam.
- **China Eastern (PVG, Xi'an, Kunming; Daxing, Shenzhen):** China, and China to Europe, India and Oceania. Daxing's
  contested route is Chengdu.
- **Malaysia (KUL):** make Kuala Lumpur a world transfer hub. Build the Asian feeder network before any long haul,
  because long haul has no loads without the feed.
- **No new airlines before January 2027.** The house rules allow two more holdings in low-demand countries; that
  decision waits until then.

### Fleet
- **Types, as the route needs:** any airline may fly any of our types: the A321neo by default, the A320neo where an
  A321neo would fly part-empty, the A321XLR beyond an A321neo's reach, the E195-E2 for thin routes, the A350 only where
  range demands it (Ryanair: no A350). Three families at most (A320 family, E195, A350; a fourth costs 15% more
  maintenance). No 787, CRJ or A319. Each family is its own delivery line, one after another (Today → **Orders**, each
  airline's delivery lines); plan orders with the queues in mind.
- **Size by city stars:** 1–2-star the E195; 3-star the E195 or A320neo; 4-star any of the E195, A320neo and A321neo;
  5-star the A320neo, A321neo or XLR. The bigger type where a heavy rival flies the pair or the sector is long. Bookings
  are divided among the flights on offer, so more, smaller flights take more of a market.
  **Both delivery lines:** A321neos on big sold-out routes; E195s on short, thin and new markets, ordered the evening cash
  covers an E195 but not yet an A321neo.
- **The default line:** the cheapest variant that seats the market and reaches the city (manual §3's table): E195-E2,
  A320neo SHARP/LIGHT/standard/Heavy, A321neo LIGHT/standard, A321LR, A321XLR, then the A350-900 to about 15,000 km and
  the A350-1000 beyond (or where the -900 sells out). No ULR. Range is not a hard limit: the game cuts seats instead.
- **November: the trunks.** Every order from 1 to 30 November fortifies the routes between our bases, shortest first,
  keeping the delivery lines filled: `docs/briefs/2026-10-20-november-trunks.md` and Gitesh's decisions on all 325 pairs.
- **Every aircraft is named by its tail number and base**, e.g. "N019AW (JFK)", in every chat.
- **Reach first:** new aircraft go into the short and medium-haul narrowbody network. Long haul comes later.
- **New airlines launch short haul:** one daily rotation per route, as many routes as possible.

---

## 4. The planner, as you'll use it
The nine screens, in the order of the header, grouped by when they're used (since 20 Oct). The planner guide has every
button.

| Screen | Use it for | Look at it |
|---|---|---|
| **Home** | The network at a glance: the globe, the map, **Aircraft on order**, the airline cards | Whenever |
| **Today** | What to do now. At the top **All clear**, or what's waiting, and the capture in one line. Then **Orders** (who can order now or from when, the safe types, each delivery line), **Aircraft to file** (with **File into planner**), **Needs attention**, **Game check** (planner against the game), the **To-do** board and **Coming up** | Every evening after the capture |
| **Routes** | Every route by airline: stars, market, distance, load, round trips. Open a route to see or edit its frequencies, with every check (night bans, banks, turns, position, second-daily gap, connections at both ends) | When planning or retiming |
| **Tails** | Every aircraft: flights a week, block hours a day, maintenance, issues. **Deliveries** lists aircraft on order or arrived, with their plan cards, the service check and the cabin the rule calls for (**Use the suggestion**). Filing happens here | When an aircraft arrives; when something needs a look |
| **Performance** | How each airline is doing, and why. The scorecards (each figure against the same day last week), **Growth signals** (sold out, raise fares, fix or reduce, losing after lease), **Main hubs towards 750**, **Flights by day**. Tap a scorecard for the airline's page: profit, **Cash, next 14 days**, route profit with its aircraft and fare changes, the fare plan | Before every order; on Saturdays |
| **Interline** | One row per airline and foreign country it flies to: to sign, signed or declined, with the partner. The countries and the rules | When a route opens a new country; when an airline asks to interline |
| **Photos** | Logos and destination photos for the website | When a new destination has no photo |
| **Reference** | The rule numbers (settings), aircraft types and cabins, order cabins, markets and their layouts, service profiles, night bans, time zones, removed routes, exports | Rarely; a rule number changes here and in the manual together |
| **Systems** | The plumbing. The **Systems** board (is everything working?), then the capture's details, **Manual entry** if a capture fails, and the aircraft checks while they're on | When Today's capture line or needs attention points there |

Check, Review and Hubs went on 20 Oct: their boards are on Today, Performance and Systems, and their old addresses
lead there. A frequency's bank fit and its connections at both ends are on Routes.

**Saving:** each change saves on its own. **saved** means it's in. **not saved · retry** means tap it to send again
(closing the tab loses it). A preview address saves nothing.

---

## 5. Every evening

**When:** each evening, Chicago time, at about the same time each day. It must be done before 05:00 in Chicago
(10:00 UTC), when the database takes the day's snapshot itself if no full capture has come in.

**Steps:**
1. Sign in to the game.
2. Press **Capture all airlines** (the userscript's panel). It works through every airline in the world's list. Leave
   the tab open until it finishes.
3. **Read the panel.** Each airline ends with **all good**, or with what came in short or broken (for example "short:
   loads 12 of 78 flights").
4. **If a page is short or broken, capture that airline again** the same evening, while the game still holds its last
   24 hours of loads. If it keeps failing, enter that night's cash and loads by hand in Systems → **Manual entry** (loads
   under 95% only, or paste the game's load table).
5. **Open the planner on Today.** The top says **All clear**, or what's waiting. The capture line should read "All six
   airlines captured, all good" with the time; if not, it says what's missing, short or broken, and **Systems ›** has
   each page.
6. **Work down Today:** **Orders** (an airline that can order: the Scheduling chat proposes the aircraft and routes),
   **Aircraft to file** (**File into planner**), **Needs attention** (each item links to where it's fixed), **Game
   check** when something looks off, and the **To-do** board. When nothing is left, Today says **All clear**.
7. **Optional:** run the salaries script for one airline when you choose (section 9).

**What "short" means:**
- **Loads:** under 90% of the flights the airline had scheduled in the 24 hours before the capture. A new rotation
  counts from the day after it launched, and a new aircraft only once a capture has shown it flying.
- **Bank statement:** no lines, or under half the airline's usual night.
- **Events or income statement:** no rows.
- **Broken:** a balance sheet without the cash account, or a page that can't be read.

**Overnight, on its own:** the backup at 07:17 UTC (copied, restored to prove it works, sent to R2), the snapshot
fallback at 10:00 UTC, the clean-ups at 10:20 UTC and, on the first night of a month, the monthly archive. Nothing to
do unless Today or the Systems board shows red (section 11).

---

## 6. The growth loop: from order to flying
This is the heart of the game. It runs whenever an airline can afford an aircraft and whenever one arrives.

### Step 1: Can the airline order? (every evening after the capture)
- Planner → **Today** → **Orders** says which airlines can order now, or from when, and the types that are safe. The
  detail is Performance → the airline → **Cash, next 14 days**. It starts from today's captured cash, adds flight profit
  from the last day's bank statement, and takes away every scheduled lease and week-end closing (the weekly salary
  payment).
- An order is **safe** when **0.5M stays in hand at the lowest point** afterwards. The forecast counts the new
  aircraft's own weekly lease from 7 days after it arrives, and treats it as arriving the day it's ordered (the worst
  case). Several orders are tested together. A type never leased yet is taken at 10% of its price a week.
- Prices include the cabin.
- If the airline wasn't captured last night, capture it first. Never decide from an old figure.
- Today's Needs attention also says when an airline can safely order.

### Step 2: What and where?
- **Hubs first:** until the main hub has 750 departures a week, every new aircraft goes there. Any other base gets one
  only for a **contested** route: a rival with over 250 departures a week at that base, or over 2 flights a day on the
  route. A base contested for one route doesn't open its other routes. Performance → **Main hubs towards 750** shows
  progress, with each hub's readiness (the cities feeding each bank) folded into its line. Ryanair is exempt.
- **Growth signals** (Performance → Growth signals): **Ready for another flight** (sold out on most departures and
  earning at least the airline's middle route an aircraft hour: block time, turnaround and turn margin), **Raise fares**
  (sold out but earning less an aircraft hour), **Fix or reduce** (losing money, economy under 75%, or a thin margin; not
  for a route under 7 days old), **Aircraft losing money after their lease**. How long each delivery line has left is on
  Today → **Orders**.
- **Type:** whichever of our types the route needs (section 3). Ryanair: no A350.
- **A real decision gets a full brief** from Claude: the answer and an options table first (growth, profit a week, cash
  at the lowest point, opportunity cost, risk, how easy it is to undo), then the background. Applying an existing rule
  doesn't need one.

### Step 3: Order in the game
- **The order queues come first.** Each evening the Scheduling chat looks at each airline's delivery lines (A320
  family, E-jet and A350; Ryanair the first two) and its cash forecast, and proposes the aircraft that can be ordered
  and the routes for each: route first, then the airline, the variant that seats the market and reaches the city, and
  its cabin. Where cash allows more than one option, the route we most want to fly decides.
- **You order in the game** and tell the Scheduling chat. Claude logs it and writes the **plan card** with those routes
  and that cabin (Tails → Deliveries → **card**), following the rules in step 4.
- The aircraft appears in Home's **Aircraft on order** and Tails' **Deliveries** with its arrival time (UTC), and on
  Today's **Aircraft to file** once it arrives.

### Step 4: The plan card's rules
Every plan card, written with the order, follows these rules. When the aircraft arrives the card stands; go straight
to step 5.

| Rule | The number |
|---|---|
| Connections at both ends | Land at least the airport's minimum connection time before the departures it feeds; departures leave within 8 hours of the arrivals they collect |
| Use the aircraft as much as possible | No floor; 10 block hours a day is a flag on Tails, not a rule. Check whether one more short rotation fits |
| Turns | The game's turnaround plus 10 minutes (5 only on the busiest aircraft where 15 won't fit) |
| Maintenance | 100% or more is firm; aim for 105% |
| A second daily on a route | Wherever it makes the most connections, at least 5 minutes from the other flight (Gander's house rule); spread further only with a business case |
| Block time | 25 minutes plus distance ÷ cruise speed (A321neo and XLR 840 km/h, E195 831, A320neo 839, A350 911) |
| Banks | Three banks per hub, timed in Reference → hubs. Connections come first; an unbanked flight still earns |
| Service code | By distance: S1 under 800 km, S2 800 to 1,500 km, S3 over 1,500 km. Ryanair uses R everywhere. A wrong code shows in red on the card ("S1, wants S3") |
| Night slots | Fine: the game's demand ignores the time of day |
| Direct only | No fifth- or eighth-freedom (tag) flights |
| Game limits | 5,000 departures a week per player per airport (8,000 after three months); at least 5 minutes between departures on one route (Gander's house rule) |

### Step 5: Set it up in the game (you)
1. Create the routes and schedule the aircraft **exactly as the card says**: flight numbers, days, times. Aircraft fly
   to their first departure on their own.
2. **Cabin:** the plan card's cabin, as the rule calls for it (manual §5: the layout of the route flying over 65% of the
   block time, else the most seats; Ryanair Standard). The card shows it (**suggested: …**, with **Use the suggestion**),
   and the card check flags a card whose cabin differs. We don't refit.
3. **Fares:** set each new flight's fare to its route's level from the card (Tails → Deliveries → **card**, its **Fare
   level** column: **Ticket price adjustment**, baseline **default price**), or leave it to the fares userscript's next
   run, which sets back any route whose fares are off its level (since 21 Oct, manual §5). A route not flown yet
   launches at 100% of the default price in both cabins (Ryanair 85%, economy only); a new flight on a route already
   flown launches at that route's level. Don't launch cheap; cut a weak route instead. Where another player (or another
   of our airlines) flies the route, never go under 60% of standard.

### Step 6: File it in the planner (you)
1. Today → Aircraft to file → **File into planner**, or Tails → Deliveries → the aircraft's card.
2. The planner reads the airline's schedule from the game and compares each flight with the card.
   - **All the same:** it files at once.
   - **Differences:** each flight shows the card's time and the game's (**same**, **different**, **not in the game**).
     File with **the game's times** if the game is right, or fix the game and file with **the plan card's times**.
3. Filing puts the aircraft in service, fits the plan card's cabin (else the order's) and logs its first fit at that
   cabin's price, and adds each flight with its return as a round trip, launched today. With no cabin on the card or the
   order it sets none and says so: choose it on the card (**Cabin**, or **Use the suggestion**) before filing.

### Step 7: Interline, if the route opens a new country
- Planner → **Interline** shows the new airline–country row as **to sign**. Our airlines always interline with each
  other.
- Outside partners: the country's major airline, at major airports, only in countries with a real domestic market or
  that are a gateway to a region we can't fly to. Not in Ryanair's Europe. Not for Pan Am in Canada, Mexico, the
  Caribbean or Central America. Each airline has its own skip list on the Interline screen.
- Send the request in the game, then set the row to signed with the partner. When another airline asks us, accept or
  decline by the same rules. **Decline Gulf hub carriers:** they'd carry our passengers through Dubai against Kingfisher
  and Malaysia.

### Step 8: Confirm it flies
- The next evening's capture should show the new flights. The loads check only counts a new aircraft once it has
  flown, so a new aircraft won't make the night show "short".
- If anything looks off, Today → **Game check** → **Check against the game** compares every airline's live schedule with
  the planner and offers **Use the game's times**, **Fix all from the game** or **Add to planner**.
- There are no one-week aircraft checks any more (retired 15 Oct).

---

## 7. Every Saturday
Run in the **Saturday review chat**, in this order. It takes most of the morning. Capture as normal on Friday evening
first.

1. **World scan** (`gscan.py`, 5 to 10 minutes): every airline in Gander with its schedule, and the airport pages for
   our hubs and the big rival hubs. Everything after reads this week's rivals. The Systems board turns amber when the scan
   is over 8 days old.
2. **The weekly report:** a PDF written like a briefing for a CEO, with no fixed template. It covers:
   - competition by market, for the group and for each airline;
   - risks and opportunities;
   - our plan and progress (what's coming);
   - route profit, growth signals and fare-plan results;
   - each airline's net cash a day against the price of one aircraft (the pace towards an aircraft a day);
   - each airline against its three biggest competitors.

   Claude pulls the figures from the database, you agree the week's words, and Claude publishes the PDF to the investor
   library on the website. It's the only investor report; on the first Saturday of the month it adds a page on the
   month just ended.
3. **The connection audit** across all hubs: valid connections, near misses, and retimes of 10 minutes or less that
   would make more connect.
4. **The newsroom roundups:** one post per airline of its new routes and extra flights since the last one, written
   like a real airline's news. No cabins, bank times or other internal detail, and no mention of the game. (Delivery
   posts go out on the day, from the Scheduling chat: one per airline per day of deliveries.)
5. **The weekly review together:**
   - **The fare ladder:** each route and cabin goes up 5 points if it sold out all week, holds at 90–99%, and goes down
     under 90%, at most 20 points above launch for now, and holds a week after a route gains a flight (manual §5).
     Performance → **The fare ladder** lists each airline's moves and the game actions that make them, in order, and
     first, since 21 Oct, the routes off their level with the changes that set them back (in this chat, `select
     public.fare_ladder(<airline id>);` gives the same). Press **Put on the fare plan**, then in the game press **Apply
     fare plan** (the fares userscript) and watch it: it shows each airline's count (and how many set a route back) and
     asks once, then makes every planned change and every set-back for every airline (**Ticket price adjustment**,
     baseline **default price**, route by route, each direction on its own), one every 2 seconds. It stops at the first problem and says which change and why; what's done stays done, and pressing
     it again makes only what the captures haven't seen yet (a change made twice does no harm). The next capture ticks
     the changes off on the fare plan. A rival starting on a pair isn't paused by the planner yet (step 4): check the
     scan by hand. Fare moves are only ever reviewed here, never as Needs attention.
   - **Route profit:** routes marked **add a flight**, **raise fares** or **hold** (Performance → the airline); anything
     under **Fix or reduce** (Performance → Growth signals). The scorecards say how each airline moved since last week.
   - **Flying hours:** aircraft under 12 block hours a day, and whether one more short rotation fits.
   - **Orders:** each airline's cash forecast. Orders themselves go in every evening the forecast allows (section 6,
     step 1), not in a Saturday batch.
   - **Hubs first:** each main hub's progress towards 750 (Performance → Main hubs).
   - **To-dos:** go through the board (Today).
   - **Triggers:** anything that needs a decision brief (Supabase's plan, a new base).

---

## 8. First Saturday of the month (as well as Saturday's work)
Run in the **Saturday review chat**, after the usual Saturday work. The next one is **7 Nov 2026**.

1. **The month page** in that day's weekly report: month-on-month figures and the month's decisions. There is no separate
   monthly report; the weekly report is the only investor report.
2. **gander monthly:** a newsletter on the whole Gander world, written impartially (without claiming to be), marked as
   made by AI and published on the website.
3. **The strategy session:** bases and holds, each airline's next step, fleet and long haul, the decision list.
4. **Supabase's usage page:** egress against 4 GB a month, and the website's calls a day against 1,000. The database's
   size, the report PDFs and the website's data are on the Systems board already.
5. **The archive:** by the 3rd, the Systems board should show the month archived (detail over a month old moves to R2 and
   GitHub). The first one runs on 1 December.

---

## 9. Now and then
- **Salaries:** go to the airline in the game and press the salaries script's button. It sets every position to 10%
  above the country average, for that airline only. Run it when you choose, not every night (the old nightly run
  across all six seemed to inflate salaries).
- **Retimes:** change times on Routes (local time at each end; each box saves when you leave it), make the same change in
  the game, and check both ends' connections.
- **Cutting a route:** remove its frequencies in the game and on Routes; an unflown route can be removed and restored
  later from Reference.
- **Rule numbers:** a change goes in Reference → Constants and in the manual together. Nothing else holds a copy.
- **Photos:** Photos → **Missing a photo only** shows destinations without one. **Upload photo** puts it live at once.

---

## 10. The checks, in one table

| When | Check | Green means | If not |
|---|---|---|---|
| Every evening | The capture panel | Every airline "all good" | Capture that airline again tonight; Manual entry if it keeps failing |
| Every evening | Today | **All clear**, and the capture line "all good" | Work down Today; each item links to where it's fixed |
| Every evening | Systems → the Systems board | "all good": capture, snapshot, backup, archive, clean-ups, scan, build, usage | Section 11 |
| After filing an aircraft | The filing comparison | Every flight **same** | Fix the game or file with the game's times |
| The evening after filing | The capture | The new flights appear | Today → Game check |
| After a merge | Systems → the Systems board → Planner build | Its time moved within minutes | Cloudflare's build failed; the last good version stays live (section 11) |
| Before an order | Today → Orders, then Performance → the airline → Cash, next 14 days | **safe**, 0.5M at the lowest point | Wait, or order a smaller or cheaper type |
| Saturday | World scan age | Under 8 days | Run the scan first |
| Saturday | Fare ladder, route profit, growth signals | Reviewed together | Make the fare moves; decide orders |
| Saturday | Connection audit | Near misses fixed where a 10-minute retime does it | Retime on Routes and in the game |
| First Saturday | Supabase usage page | Egress under 4 GB; website under 1,000 calls a day | A brief at the next review (paid plan is $25 a month) |
| By the 3rd | Systems → the Systems board → Monthly archive | Ran this month | Ask the Building chat |
| Any time | Database size, report PDFs, website data (Systems) | Under 70% of 350 MB, 50 MB, 500 KB | Amber means plan; red means a brief |

---

## 11. When something goes wrong

| What you see | What to do |
|---|---|
| An airline's capture came in short or broken | Capture it again the same evening. If every evening comes in short the same way, a game page may have changed: tell the Building chat (the raw page is kept 14 days) |
| No capture for 26 hours (amber) or 48 (red) | Capture now. Loads older than 24 hours are gone; enter what you can in Manual entry |
| Daily snapshot late, or the 10:00 UTC job hasn't run for 30 hours | The database's scheduler may have stopped. Ask the Building chat; it can take the snapshot by hand and restart the jobs |
| Backup red (no good copy for 30 hours, or the last run failed) | Ask the Building chat. GitHub sometimes starts the job hours late; one late night isn't a failure |
| Planner build time didn't move after a merge | Cloudflare's build failed; the last good version stays live. The build log is in Cloudflare's dashboard; the Building chat fixes it |
| The site or planner broke after a change | Revert that pull request on GitHub; Cloudflare republishes the previous version within minutes |
| A planner row was changed or deleted by mistake | One row can be put back from the change log; many from last night's backup. Ask the Building chat |
| The planner and the game disagree | Today → Game check; the game is the truth |
| The whole database is lost | Restore from R2 (or the month's GitHub copy) into a new Supabase project, then issue new keys and schedule the jobs again. The steps are in `equinox-backups`' README |
| A key may have leaked | Issue a new one and replace it where it lives (the map's key table); for the capture key, update the userscript |
| A check on a pull request is red | Don't merge. The pull request says which check and why |

---

## 12. How changes are made
- **Game changes** (orders, schedules, fares, cabins, interlines) are made in the game by you, and mirrored in the
  planner. The planner shows a route or aircraft only once it's in the game; plans live on plan cards. The fare ladder's
  changes are made by the fares userscript while you watch (section 7).
- **Data-only changes** (plan cards, to-dos, notes, logs) go straight in, by you in the planner or by Claude, and every
  change is logged with who made it.
- **Code changes** are pull requests on GitHub. A helper builds from a written spec, every check must be green, Claude
  reviews it, and **you say "merge"** to make it live. Database changes are applied after the merge. Anything that
  removes something from the database is run by you in Supabase's SQL editor.
- **Rule changes:** agreed in chat, then written into the manual the same day, with the date and why; the old rule moves
  to *Retired rules*.
- **Decisions:** one at a time, each with a full brief, and you decide. Nothing is built on Claude's initiative.
- **Claude says first** when something will take more than 5 minutes, and gives manual steps one at a time.
- **Things for you to check or do** go on the planner's To-do board; Claude ticks them when you report back.

---

## 13. Game mechanics worth knowing (Gander)
- **Gander is an exclusive world:** its owner sets the rules. That's why interlining our own airlines, the capture and
  salary scripts, and the world scanner are allowed here. They wouldn't be in a public world.
- **Holdings:** up to 8 per player (6, plus 2 in low-demand countries); at most 1 US, 1 China, 2 EU and 1 low-cost.
  45M starting capital each. A new brand must have a route flying within 14 days.
- **Demand is per airport, not per city:** Heathrow, Gatwick and Stansted are separate markets.
- **Time of day doesn't affect demand;** it matters only for connections. Passengers book each direction separately.
- **Maintenance** depends on take-offs and landings as well as hours, and happens at any airport with a long enough
  ground gap.
- **Money:** an order needs only its price up front. The first lease payment falls 7 days after arrival, then weekly
  (about 0.24M for an A321neo, 0.29M for an XLR, 0.18M for an E195, 0.72M for an A350). The week-end closing is the
  weekly salary payment, and the game's advance figure can lag when staff are added.
- **Time:** the game runs standard time all year (JFK −5, London 0, Paris and Amsterdam +1, Delhi +5:30). The planner
  shows Local or UTC (header switch); plan-card times are UTC.
- **Fare floor:** 60% of standard wherever another player flies the route, our own airlines included.
- **Limits:** 5,000 departures a week per player per airport (8,000 after three months); 5 minutes between departures
  on one route; at most 30 fifth/eighth-freedom routes per airline (we fly none).
- **Subsidiaries** don't work with the game's demand model, so we don't use them.

---

## 14. Words you'll see
| Word | Meaning |
|---|---|
| **Hub** | A base that runs banks, so arrivals connect onto departures |
| **Focus city** | A base that serves its own market (and, for the legacy airlines, feeds a hub). Ryanair has only focus cities |
| **Bank** | A window when arrivals land, followed by a window when departures leave (60 minutes each), so passengers connect |
| **Minimum connection time** | The shortest connection an airport allows; ours land at least that long before the flight they feed |
| **Block time** | Gate to gate: 25 minutes plus distance ÷ cruise speed |
| **Turn** | The ground time between an arrival and the aircraft's next departure |
| **Frequency / round trip** | A flight out and its return, on the days it flies |
| **Plan card** | Claude's plan for an arrived aircraft: each flight's number, route, days, times, block and service code |
| **Filing** | Putting an arrived aircraft into the planner once the game matches its card |
| **Capture** | The evening button that sends the game's pages to the database; each page gets a verdict (all good, short, broken) |
| **Cash forecast / cushion** | The 14-day cash outlook; an order must leave 0.5M at its lowest point |
| **Contested route** | One where a rival has over 250 departures a week at the base, or over 2 a day on the route |
| **Hubs first** | Every new aircraft to the main hub until it reaches 750 departures a week |
| **Service code** | The on-board service level by distance: S1, S2, S3, or R for Ryanair |
| **Market layout** | The cabin layout a market calls for (Standard, Leisure, Leisure Plus or Comfort; Reference → Markets): a plan card takes it where one route of the market flies over 65% of the block time (its market default until 21 Oct) |
| **Fare plan** | The list of fare tests to make in the game, reviewed on Saturdays |
| **Week-end closing** | The game's weekly salary payment |
| **Interline** | An agreement to sell connections on another airline's flights |
| **Systems board** | The top of Systems: one line per thing that must work, green, amber or red |
| **All clear** | What Today says when nothing is waiting: no order possible, nothing to file, nothing in needs attention, no Game check differences |

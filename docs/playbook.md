# The equinox. handover guide

Everything someone taking over the game needs to do: the tools, the evening routine, how a new aircraft goes from
order to flying, the Saturday and monthly work, every check and what to do when one fails.

- **This guide gives steps and points to the manual for every rule; it never restates them.** The rules are in the
  operating manual (`docs/operating-manual.md`), each pointer names the rule and its section, and where this guide and
  the manual differ, **the manual wins** and this guide is corrected in the same turn.
- **Detail on each screen:** `docs/planner-guide.md`. **How the system fits together and how to recover it:**
  `docs/architecture.md`. **Why things are the way they are:** `docs/decisions.md`, `docs/rule-history.md` and
  `docs/briefs/`.
- Written 15 Oct 2026, after the planner rebuild and decisions #21 to #25; rewritten as steps only on 21 Oct. "You" is
  the player. "Claude" is the Equinox project in Claude, with its three chats.

---

## 0. The five things that matter most
1. **Capture every evening.** The game keeps a flight's loads only briefly, so a missed evening loses them for good
   (rule: manual §7, every evening). On 11 and 12 Oct about 780 flights' loads were lost that way.
2. **Before opening a route, check no other airline of ours has the pair.** Competition's openings say which other
   airlines of ours have it on their list (rule: manual §2, one airline per city pair).
3. **Order only when the cash forecast says it's safe:** Today → **Orders** (rule: manual §3, the cash forecast).
4. **Send each new aircraft where hubs first allows.** The openings say whether it does, and why not (rule: manual §3,
   hubs first).
5. **One thing at a time, and the player decides.** Claude recommends and builds; nothing is built or changed without
   your yes. Code goes live only when you say "merge" (rule: manual §1, one item at a time; code changes are pull
   requests).

---

## 1. What you're taking over

**The group:** six airlines in AirlineSim's Gander world, run as one group called **equinox.** (lowercase, with the
full stop; manual §8, brand). Website and planner: **equinox-alliance.com** (planner at `/planner/`, staff sign-in).

| Airline | Code | Database id |
|---|---|---|
| Pan Am | AW | 1 |
| Kingfisher | KF | 2 |
| Ryanair | FR | 3 |
| Virgin Atlantic | VS | 4 |
| China Eastern | MU | 5 |
| Malaysia Airlines | MH | 6 |

**Where to find the current state** (this guide holds no figures, so it can't go out of date):
- **Bases, hubs and focus cities:** manual §2, bases.
- **Fleet, routes and aircraft on order:** the planner's Home (the airline cards), Today (**Orders**: each delivery line) and Tails (**Deliveries**).
- **Arrivals waiting to be filed, orders possible tonight, open to-dos:** the planner's Today (the **To-do** board).
- **Money and route performance:** Performance; rivals and openings: Competition.

---

## 2. Your tools

| Tool | What it's for | Where |
|---|---|---|
| **The game** | Everything that actually happens: orders, routes, schedules, cabins, fares, interlines, salaries | gander.airlinesim.aero, one account with all six airlines |
| **Capture userscript** | One button, *Capture all airlines*, sends each airline's loads, bank statement, income statement, balance sheet and events to the database; then each airline's fleet pages (each aircraft's condition, maintenance, seats and pilots; since 22 Oct, version 1.6); then, when a world scan is due, scans the world (every airline's schedule and the airport pages; since 21 Oct) | `capture/capture_all.user.js`, installed in a userscript manager (such as Tampermonkey) in your browser, with your capture key in place of `__CAPTURE_KEY__` |
| **Salaries userscript** | One button sets every position of the airline you're on to the level the rule sets (rule: manual §7, salaries) | `capture/salary_adjust.user.js`, installed the same way |
| **Fares userscript** | One button, *Apply fare plan*, makes the week's fare plan changes in the game for every airline, one at a time, while you watch (section 7; rule: manual §5, the fare ladder) | `capture/fares_apply.user.js`, installed the same way (the Userscripts app on the Mac or iPhone), with the same capture key in place of `__CAPTURE_KEY__` |
| **The planner** | The staff tool: the network, aircraft, plan cards, checks, money and to-dos | equinox-alliance.com/planner/ |
| **The website** | The public airline site: flights, destinations, live network, newsroom, investors, gander monthly | equinox-alliance.com |
| **Claude (Equinox project)** | Three chats: **Scheduling**, **Saturday review**, **Building** (rule: manual §1, one chat per kind of work, which says what each covers). The manual, decisions, map and this guide are in its files | claude.ai |
| **Supabase** | The database, sign-in and photo files (rule: manual §1, Supabase stays on the free plan) | project `ulecwsyedvwcxgdzmhoq` |
| **GitHub** | All code and documents (`GiteshJain/Equinox`); the nightly backup job and monthly copies (`equinox-backups`, private) | github.com |
| **Cloudflare** | Hosts the website and planner (Pages) and keeps the backups (R2). The domain renews each October (manual §1, hosting) | dash.cloudflare.com |

**Handing over the keys:** keys are never written in a document (rule: manual §1, no keys or passwords). The map
(`docs/architecture.md`, "Where keys are kept") names each one and where it lives. A new player needs their own planner
sign-in (manual §1, no one can sign up), a new capture key for the userscript (ask the Building chat to issue one), and
access to the game account. If a key may have leaked, replace it (the map says how).

**Which chat to ask:** a question in the wrong chat gets sent to the right one. New aircraft and routes → Scheduling.
Anything on a Saturday, weekly or monthly → Saturday review. Anything that changes code or the database → Building.

---

## 3. What we're building: the strategy
The strategy is all in the manual. What each rule covers:

### The shape of the group (manual §2)
- **Roles:** which airline owns which region and which intercontinental flow, Oceania included.
- **One airline per city pair:** who owns a pair, by country pair, and the exception where the rightful airline has
  no base at either end. When adding routes from a list, add missing lanes only.
- **Destination shape:** where the network is heading in time, and at what pace.
- **Scale models:** each airline's real-world model to copy.
- **Malaysia:** Kuala Lumpur's role, and what gets built before long haul.
- **Kingfisher:** India's role.
- **No new airlines before January 2027:** when the remaining holdings are decided.
- **Bases:** each airline's hubs, focus cities and what's next.

### Fleet and growth (manual §3)
- **Fleet types, as the route needs:** which types and families any airline may fly, and Ryanair's limits.
- **Size by city stars:** which sizes a city's stars allow, and which wins within a band.
- **The default line:** which variant to pick for a size and a distance.
- **Order across both delivery lines:** which type goes on which kind of route, and when to order the smaller one.
- **When cash doesn't cover the aircraft the top openings need, cash decides.**
- **Reach first:** short and medium haul before long haul.
- **Route first, then the airline, then the aircraft:** the order of choosing.
- **Market share first, profit second:** what route choices lead with, and what still has to hold.
- **The openings, ranked:** where the next routes come from.
- **Hubs first:** where new aircraft go until the main hub is built out, and the contested-route exception.

### Scheduling (manual §4)
- **Every aircraft is named by its tail number and base**, in every chat.
- **Until 31 October, only new routes**, and **from 1 to 30 November, every new order fortifies the trunk routes**
  (the plan: `docs/briefs/2026-10-20-november-trunks.md`).
- **New airlines launch short-haul.**
- **Ryanair stays inside the game's EU zone.**
- **London:** which London airport new routes go to.
- Interlines: manual §6.

---

## 4. The planner, as you'll use it
The nine screens, in the order of the header, grouped by when they're used (since 20 Oct). The planner guide has every
button.

| Screen | Use it for | Look at it |
|---|---|---|
| **Home** | The network at a glance and what needs attention: the globe, needs attention's cards (each opens its section on Today), the map, the airline cards | Whenever |
| **Today** | What to do now. At the top **All clear**, or what's waiting, and the capture in one line. Then **Orders** (who can order now or from when, the safe types, each delivery line), **Aircraft to file** (with **File into planner**), **Needs attention**, **Game check** (planner against the game), the **To-do** board and **Coming up** | Every evening after the capture |
| **Routes** | Every route by airline: stars, market, distance, load, round trips. Open a route to see or edit its frequencies, with every check (night bans, banks, turns, position, second-daily gap, connections at both ends) | When planning or retiming |
| **Tails** | Every aircraft: flights a week, block hours a day, maintenance, issues. **Deliveries** lists aircraft on order or arrived, with their plan cards, the service check and the cabin the rule calls for (**Use the suggestion**). Filing happens here | When an aircraft arrives; when something needs a look |
| **Performance** | How each airline is doing, and why. The scorecards (each figure against the same day last week), **Growth signals** (sold out, raise fares, fix or reduce, losing after lease), **Main hubs**, **Flights by day**. Tap a scorecard for the airline's page: profit, **Cash, next 14 days**, route profit with its aircraft and fare changes, the fare plan; a route's name there opens its **route page**, its story since launch (since 22 Oct) | Before every order; on Saturdays |
| **Competition** | Who we're up against and where to open next (since 21 Oct). The scans' dates and the group line on top; for each airline its **Market share** by market (our share, its arrow, the top rivals as a bar), **Threats** (rivals who started on or grew on our pairs), **Openings** ranked (stars, rivals, distance; variant and hubs first) and **Rival profiles** | Each evening before an order; on Saturdays |
| **Interline** | One row per airline and foreign country it flies to: to sign, signed or declined, with the partner. The countries and each airline's skip list | When a route opens a new country; when an airline asks to interline |
| **Photos** | Logos and destination photos for the website | When a new destination has no photo |
| **Reference** | The rule numbers (Constants), aircraft types and cabins, order cabins, markets and their layouts, service profiles, night bans, time zones, removed routes, exports | Rarely; a rule number changes here and in the manual together (manual §1, rule numbers have one source) |
| **Systems** | The plumbing. The **Systems** board (is everything working?), then the capture's details, and **Manual entry** if a capture fails | When Today's capture line or needs attention points there |

Check, Review and Hubs went on 20 Oct: their boards are on Today, Performance and Systems, and their old addresses
lead there. A frequency's bank fit and its connections at both ends are on Routes.

**Saving:** each change saves on its own. **saved** means it's in. **not saved · retry** means tap it to send again
(closing the tab loses it). A preview address saves nothing (manual §1, preview before live).

---

## 5. Every evening

**When:** each evening, Chicago time, at about the same time each day. It must be done before 05:00 in Chicago
(10:00 UTC), when the database takes the day's snapshot itself if no full capture has come in (manual §7, every day,
inside the database).

**Steps:**
1. Sign in to the game.
2. Press **Capture all airlines** (the userscript's panel). It works through every airline in the world's list. Leave
   the tab open until it finishes. Since 22 Oct each airline ends with its fleet pages, one more page kind ("Pan Am:
   fleet 2 of 3"), about a minute more in all (what they're checked for: manual §7). **When a world scan is due it then scans the world** (how often: manual §7, the
   world scan; Reference → Constants, `scan_every_days`). It takes a few minutes longer, so **keep the page open**. The
   panel shows "World scan: 120 of 163 airlines…", then "World scan done"; **Stop** ends it early (the scan isn't
   finished, and the next evening's capture scans again). If the page reloads, it carries on where it was. No scan
   follows a capture page that failed: capture again, and the scan follows.
3. **Read the panel.** Each airline ends with **all good**, or with what came in short or broken (for example "short:
   loads 12 of 78 flights"). What counts as short or broken is in manual §7, each page is checked as it arrives. The
   last line says whether the world scan ran ("World scan done"), wasn't due, or why it didn't finish.
4. **If a page is short or broken, capture that airline again** the same evening, while the game still holds the loads
   (manual §7). If it keeps failing, enter that night's cash and loads by hand in Systems → **Manual entry** (or paste
   the game's load table).
5. **Open the planner on Today.** The top says **All clear**, or what's waiting. The capture line should read "All six
   airlines captured, all good" with the time; if not, it says what's missing, short or broken, and **Systems ›** has
   each page. Since 22 Oct needs attention's **Fleet** group lists what the game's fleet pages showed that needs a look
   (what counts: manual §4 and §7); the game's maintenance under the limit has its own card. Fix it in the game or the
   planner that evening.
6. **Work down Today:** **Orders** (an airline that can order: the Scheduling chat proposes the aircraft and routes,
   section 6), **Aircraft to file** (**File into planner**), **Needs attention** (each item links to where it's fixed),
   **Game check** when something looks off, and the **To-do** board. When nothing is left, Today says **All clear**.
7. **Optional:** run the salaries script for one airline when you choose (section 9).

**Overnight, on its own:** the backup at 07:17 UTC (copied, restored to prove it works, sent to R2), the snapshot
fallback at 10:00 UTC, the clean-ups at 10:20 UTC and, on the first night of a month, the monthly archive (manual §7).
Nothing to do unless Today or the Systems board shows red (section 11).

---

## 6. The growth loop: from order to flying
This is the heart of the game. It runs whenever an airline can afford an aircraft and whenever one arrives.

### Step 1: Can the airline order? (every evening after the capture)
- Planner → **Today** → **Orders** says which airlines can order now, or from when, and the types that are **safe**.
  The detail is Performance → the airline → **Cash, next 14 days**. What the forecast counts and what makes an order
  safe: manual §3, when an airline can order: the cash forecast.
- If the airline wasn't captured last night, capture it first. Never decide from an old figure (manual §3).
- Today's Needs attention also says when an airline can safely order.

### Step 2: What and where?
- **Hubs first:** Performance → **Main hubs** shows each main hub's progress, with its readiness (the cities feeding
  each bank) folded into its line, and each opening says whether hubs first allows it (rule: manual §3, hubs first).
- **Growth signals** (Performance → Growth signals): **Ready for another flight**, **Raise fares**, **Fix or reduce**
  and **Aircraft losing money after their lease** (rules: manual §3, add a flight or raise fares; new routes aren't
  judged for a week). How long each delivery line has left is on Today → **Orders**.
- **Type:** the one the route needs (rules: manual §3, fleet types; size by city stars; the default line).
- **A real decision gets a full brief** from Claude; applying an existing rule doesn't need one (rule: manual §1,
  every decision gets the full brief, and its note on a new aircraft's routes).

### Step 3: Order in the game
- **The order queues come first.** Each evening the Scheduling chat looks at each airline's delivery lines on Today →
  **Orders** and its cash forecast, and proposes the aircraft that can be ordered and the routes for each, with variant
  and cabin, one airline at a time (rules: manual §3, order every evening the forecast allows; route first, then the
  airline, then the aircraft; the order queues; when cash doesn't cover the aircraft the top openings need).
- **Look at the used offers too** (since 22 Oct): the game's Aircraft Market, each evening, for one on the default
  line that flies the chosen routes for less than new. You place the bid and say when the auction closes (rule:
  manual §3, the used market too; how auctions work: manual §9). When it's won, Claude logs the order with
  `aircraft.acquired` set to `used`, so its replacement comes at 10 years, not 3 (manual §3, replacement by age); a
  used aircraft logged without it shows on Today's Fleet group as "looks used, marked new" the first night it flies.
- **The routes come from the top of the openings** (since 21 Oct): Competition → the airline → **Openings**, or the
  airline briefing, or `select public.competition(<airline id>);` for the rest (rule: manual §3, the openings, ranked).
  In November the trunks are listed first and marked; whether each makes sense stays the Scheduling chat's call (rule:
  manual §4, from 1 to 30 November).
- **You order in the game** and tell the Scheduling chat (rule: manual §3, who orders). Claude logs it and writes the
  **plan card** with those routes and that cabin (Tails → Deliveries → **card**), following step 4.
- The aircraft appears in Tails' **Deliveries** with its arrival time (UTC), counts on its delivery line in Today's
  **Orders**, and shows on Today's **Aircraft to file** (and Home's **To file** card) once it arrives.

### Step 4: The plan card's rules
Every plan card, written with the order, follows these rules. When the aircraft arrives the card stands; go straight
to step 5. The planner checks each card against them.

- **Connections at both ends:** manual §4, maximise connections at both ends.
- **Use the aircraft as much as possible:** manual §4, use each aircraft as much as possible (Tails' block-hours flag
  is a flag, not a floor).
- **Turns:** manual §4, turns; a new variant's turnaround: manual §3, turnaround of a new variant.
- **Maintenance:** manual §4, maintenance.
- **A second daily on a route:** manual §4, a second daily.
- **Block time:** manual §4, block time.
- **Banks:** manual §4, three banks per hub (times in Reference → hubs).
- **Service code:** the card shows a wrong code in red ("S1, wants S3"); fix it before the card is filed (rule: manual §4, service codes by distance).
- **Night slots:** manual §4, night slots are fine.
- **Direct only:** manual §4, everything flies direct.
- **Game limits:** manual §9, house rules.
- **Cabin:** manual §5, the cabin is chosen with each order.
- **Fare level of each route:** manual §5, the fare ladder.

### Step 5: Set it up in the game (you)
1. Create the routes and schedule the aircraft **exactly as the card says**: flight numbers, days, times. Aircraft fly
   to their first departure on their own (manual §9, mechanics).
2. **Cabin:** the plan card's cabin. The card shows it (**suggested: …**, with **Use the suggestion**), and the card
   check flags a card whose cabin is missing or differs (rule: manual §5, the cabin is chosen with each order).
3. **Fares:** set each new flight's fare from the card (Tails → Deliveries → **card**, its **Fare level** column:
   **Ticket price adjustment**, baseline **default price**), or leave it to the fares userscript's next run, which sets
   back any route whose fares are off its level (rules: manual §5, fares; the fare ladder; manual §9, house rules, the
   fare floor).

### Step 6: File it in the planner (you)
File it as soon as it arrives (rule: manual §4, how it runs).
1. Today → Aircraft to file → **File into planner**, or Tails → Deliveries → the aircraft's card.
2. The planner reads the airline's schedule from the game and compares each flight with the card.
   - **All the same:** it files at once.
   - **Differences:** each flight shows the card's time and the game's (**same**, **different**, **not in the game**).
     File with **the game's times** if the game is right, or fix the game and file with **the plan card's times**.
3. Filing puts the aircraft in service, fits the plan card's cabin (else the order's) and logs its first fit at that
   cabin's price, and adds each flight with its return as a round trip, launched today. With no cabin on the card or the
   order it sets none and says so: choose it on the card (**Cabin**, or **Use the suggestion**) before filing.

### Step 7: Interline, if the route opens a new country
- Planner → **Interline** shows the new airline–country row as **to sign**.
- Decide whether to sign, and with whom, by the interline rules (manual §6: our airlines interline with each other;
  outside partners; where not to). Each airline's skip list is on the Interline screen.
- Send the request in the game, then set the row to signed with the partner. When another airline asks us, accept or
  decline by the same rules (manual §6, Gulf hub carriers are rivals).

### Step 8: Confirm it flies
- The next evening's capture should show the new flights. The loads check counts a new aircraft only once it has
  flown, so a new aircraft won't make the night show "short" (manual §7, each page is checked as it arrives).
- If anything looks off, Today → **Game check** → **Check against the game** compares every airline's live schedule with
  the planner and offers **Use the game's times**, **Fix all from the game** or **Add to planner**.
- There are no one-week aircraft checks (manual §1, no one-week aircraft checks).

---

## 7. Every Saturday
Run in the **Saturday review chat**, in this order (manual §7, every Saturday). It takes most of the morning. Capture
as normal on Friday evening first.

0. **The document check** (about 5 minutes): the project's copies of the manual, playbook, map and decisions match the
   repository; no document states a retired rule; the playbook refers to rules rather than stating them; memory holds
   no game rules. Fix facts on the spot; anything needing a ruling goes to Gitesh one at a time.
1. **World scan:** it runs with the evening capture (section 5), so there's nothing to run. Check its age on the
   Systems board: if it isn't green, the captures haven't scanned (the capture panel said why); run `gscan.py` by hand
   first then (5 to 10 minutes, the fallback; `scripts/README.md`). Everything after reads this week's rivals.
2. **The weekly report:** a PDF written like a briefing for a CEO, with no fixed template; what it covers is in manual
   §7. Claude pulls the figures from the database, you agree the week's words, and Claude publishes the PDF to the
   investor library on the website. On the first Saturday of the month it adds a page on the month just ended.
3. **The connection audit** across all hubs: valid connections, near misses, and the small retimes that would make
   more connect (how small: manual §7).
4. **The newsroom roundups:** one post per airline of its new routes and extra flights since the last one, written by
   the newsroom rules (manual §8, newsroom posts read like a real airline's; what the newsroom posts). No posts for new
   aircraft.
5. **The weekly review together:**
   - **The fare ladder** (rule: manual §5, the fare ladder): Performance → **The fare ladder** lists each airline's
     moves and the game actions that make them, in order, and first, since 21 Oct, the routes off their level with the
     changes that set them back (in this chat, `select public.fare_ladder(<airline id>);` gives the same). Press **Put
     on the fare plan**, then in the game press **Apply fare plan** (the fares userscript) and watch it: it shows each
     airline's count (and how many set a route back) and asks once, then makes every planned change and every set-back
     for every airline (**Ticket price adjustment**, baseline **default price**, route by route, each direction on its
     own), one at a time. It stops at the first problem and says which change and why; what's done stays done, and
     pressing it again makes only what the captures haven't seen yet (a change made twice does no harm). The next
     capture ticks the changes off on the fare plan. A route a rival started on or grew on holds on its own, and the
     ladder says so ("rival Air China started here on 22 Oct: paused until 29 Oct"). Since 23 Oct the ladder may jump a
     cabin under launch, and lists the **cut-or-keep decisions** (the card's "1 decision", the row's **cut or keep?**):
     decide each one here, cut the route or keep it (rules: manual §5, the fare ladder; weak routes get cut, manual §5,
     fares). Fare moves are only ever reviewed here, never as Needs attention.
   - **Competition** (since 21 Oct): each airline's market share against last week's scan, the threats of the week
     (Today listed each evening's), and the top openings the evening proposals are working down (Competition → the
     airline). The weekly report's competition by market reads the same scans.
   - **Route profit:** routes marked **add a flight**, **raise fares** or **hold** (Performance → the airline); anything
     under **Fix or reduce** (Performance → Growth signals). The scorecards say how each airline moved since last week.
   - **A route we're unsure about** (since 22 Oct): open its route page (Performance → the airline → the route's name,
     or `/planner/performance/<code>/<route>`; in this chat `select public.route_story(<route id>);`). It tells the
     route's story since launch: the last week against the one before, loads by cabin with the fare level and every
     event (a fare move, a new frequency, a rival) on one chart, profit an aircraft hour by week, the rivals on the pair
     and the connections at each end. Judge a fare move, a new frequency or a rival by what happened after it.
   - **Flying hours:** the aircraft the review lists as under the daily block-hours mark, and whether one more short
     rotation fits (rule: manual §4, fly each aircraft as much as it fits).
   - **Orders:** each airline's cash forecast. Orders themselves go in every evening the forecast allows (section 6,
     step 1), not in a Saturday batch.
   - **Hubs first:** each main hub's progress (Performance → **Main hubs**).
   - **To-dos:** go through the board (Today).
   - **Triggers:** anything that needs a decision brief (Supabase's plan, a new base; manual §1, Supabase stays on the
     free plan).

---

## 8. First Saturday of the month (as well as Saturday's work)
Run in the **Saturday review chat**, after the usual Saturday work (manual §7, first Saturday of the month). The next
one is **7 Nov 2026**.

1. **The month page** in that day's weekly report: month-on-month figures and the month's decisions. There is no separate
   monthly report; the weekly report is the only investor report.
2. **gander monthly:** the newsletter on the whole Gander world, written and published by its rules (manual §8, gander
   monthly).
3. **The strategy session:** bases and holds, each airline's next step, fleet and long haul, the decision list.
4. **Supabase's usage page:** egress and the website's calls a day, against their triggers (manual §1, Supabase stays
   on the free plan; *Decided, not yet built*). The database's size, the report PDFs and the website's data are on the
   Systems board already.
5. **The archive:** the Systems board should show the month archived (detail over a month old moves to R2 and GitHub;
   manual §7, the monthly archive). The first one runs on 1 December.

---

## 9. Now and then
- **Salaries:** go to the airline in the game and press the salaries script's button. It changes that airline only.
  Run it when you choose, not every night (rule: manual §7, salaries).
- **Retimes:** change times on Routes (local time at each end; each box saves when you leave it), make the same change in
  the game, and check both ends' connections (manual §4, maximise connections at both ends).
- **Cutting a route:** remove its frequencies in the game and on Routes; an unflown route can be removed and restored
  later from Reference.
- **Rule numbers:** a change goes in Reference → Constants and in the manual together. Nothing else holds a copy (rule:
  manual §1, rule numbers have one source).
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
| Before an order | Today → Orders, then Performance → the airline → Cash, next 14 days | **safe** (manual §3, the cash forecast) | Wait, or order a smaller or cheaper type (manual §3, when cash doesn't cover) |
| Saturday | World scan age on the Systems board (the evening capture runs it) | Green (ages: manual §7, the Systems board) | Run `gscan.py` by hand first (Saturday chat) |
| Saturday | Fare ladder, route profit, growth signals | Reviewed together | Make the fare moves; decide orders |
| Saturday | Connection audit | Near misses fixed where a small retime does it (manual §7) | Retime on Routes and in the game |
| First Saturday | Supabase usage page | Egress and the website's calls under their triggers (manual §1; *Decided, not yet built*) | A brief at the next review (manual §1, Supabase stays on the free plan) |
| Early each month | Systems → the Systems board → Monthly archive | Ran this month (when it's due: manual §7) | Ask the Building chat |
| Any time | Database size, report PDFs, website data (Systems board) | Green (marks and triggers: manual §7, the Systems board; §1) | Amber means plan; red means a brief |

---

## 11. When something goes wrong

| What you see | What to do |
|---|---|
| An airline's capture came in short or broken | Capture it again the same evening. If every evening comes in short the same way, a game page may have changed: tell the Building chat (the raw page is kept for a while: manual §7, the clean-ups) |
| The capture line on Today or the Systems board is amber or red (no recent capture; limits: manual §7) | Capture now. Loads the game no longer holds are gone; enter what you can in Manual entry |
| Today warns the daily snapshot is late, or the 10:00 UTC job hasn't run (limits: manual §7, every job writes a row) | The database's scheduler may have stopped. Ask the Building chat; it can take the snapshot by hand and restart the jobs |
| Backup red on the Systems board (no recent good copy, or the last run failed) | Ask the Building chat. GitHub sometimes starts the job hours late; one late night isn't a failure |
| Planner build time didn't move after a merge | Cloudflare's build failed; the last good version stays live. The build log is in Cloudflare's dashboard; the Building chat fixes it |
| The site or planner broke after a change | Revert that pull request on GitHub; Cloudflare republishes the previous version within minutes |
| A planner row was changed or deleted by mistake | One row can be put back from the change log; many from last night's backup. Ask the Building chat |
| The planner and the game disagree | Today → Game check; the game is the truth (manual §4, the planner mirrors the game) |
| The whole database is lost | Restore from R2 (or the month's GitHub copy) into a new Supabase project, then issue new keys and schedule the jobs again. The steps are in `equinox-backups`' README |
| A key may have leaked | Issue a new one and replace it where it lives (the map's key table); for the capture key, update the userscript |
| A check on a pull request is red | Don't merge. The pull request says which check and why (manual §1, automatic checks) |

---

## 12. How changes are made
- **Game changes** (orders, schedules, fares, cabins, interlines) are made in the game by you, and mirrored in the
  planner. The planner shows a route or aircraft only once it's in the game; plans live on plan cards (manual §4, the
  planner mirrors the game). The fare ladder's changes are made by the fares userscript while you watch (section 7).
- **Data-only changes** (plan cards, to-dos, notes, logs) go straight in, by you in the planner or by Claude, and every
  change is logged with who made it (manual §1, data-only changes go straight in).
- **Code changes** are pull requests on GitHub. A helper builds from a written spec, every check must be green, Claude
  reviews it, and **you say "merge"** to make it live. Database changes are applied after the merge. Anything that
  removes something from the database is run by you in Supabase's SQL editor (manual §1, code changes are pull
  requests; preview before live; big builds go to a fresh helper).
- **Rule changes:** agreed in chat, then committed straight to the manual in the same turn: the new rule **replaces**
  the old sentence, and the old wording and why are logged in `docs/rule-history.md` with the date. The project's copies
  are updated in the same turn, and so is this guide where a step changes.
- **Decisions:** one at a time, each with a full brief, and you decide. Nothing is built on Claude's initiative (manual
  §1, one item at a time; every decision gets the full brief).
- **Claude says first** when something will take a while, with roughly how long, and gives manual steps one at a time
  (manual §1, say first).
- **Things for you to check or do** go on the planner's To-do board; Claude ticks them when you report back (manual §1,
  to-do board).

---

## 13. Game mechanics worth knowing (Gander)
All in manual §9. What each covers:
- **Gander is an exclusive world:** why interlining our own airlines, the capture and salary scripts, and the world
  scanner are allowed here, and not in a public world.
- **House rules:** holdings per player and per country, starting capital, departures per airport, the gap between
  departures on one route, the fare floor, freedom-route and alliance caps, and a new brand's first route.
- **Mechanics:** demand is per airport, not per city; how bookings split among flights; time of day and demand;
  direction of bookings; what drives maintenance and where it happens; when leases are paid and what they cost; the
  week-end closing; aircraft positioning themselves; the game's time zones; why we don't use subsidiaries.
- The planner shows Local or UTC (header switch); plan-card times are UTC (manual §1, data-only changes).

---

## 14. Words you'll see
| Word | Meaning |
|---|---|
| **Hub** | A base that runs banks, so arrivals connect onto departures |
| **Focus city** | A base that serves its own market (and, for the legacy airlines, feeds a hub). Ryanair has only focus cities |
| **Bank** | A window when arrivals land, followed by a window when departures leave, so passengers connect (manual §4, three banks per hub) |
| **Minimum connection time** | The shortest connection an airport allows (manual §4, maximise connections at both ends) |
| **Block time** | Gate to gate (manual §4, block time) |
| **Turn** | The ground time between an arrival and the aircraft's next departure (manual §4, turns) |
| **Frequency / round trip** | A flight out and its return, on the days it flies |
| **Plan card** | Claude's plan for an aircraft, written when it's ordered: each flight's number, route, days, times, block and service code |
| **Filing** | Putting an arrived aircraft into the planner once the game matches its card |
| **Capture** | The evening button that sends the game's pages to the database; each page gets a verdict (all good, short, broken) |
| **Cash forecast / cushion** | The cash outlook Today and Performance show, and what an order must leave at its lowest point (manual §3, the cash forecast) |
| **Contested route** | A route where a rival is strong enough at the base or on the route for hubs first to let another base take it (manual §3, hubs first) |
| **Hubs first** | New aircraft go to the main hub until it is built out (manual §3, hubs first) |
| **Service code** | The on-board service level a flight carries by distance, shown on the plan card |
| **Fare plan** | The fare changes to make in the game this week, from the fare ladder (**Put on the fare plan**); the next capture ticks each off |
| **Week-end closing** | The game's weekly salary payment (manual §9, mechanics) |
| **Interline** | An agreement to sell connections on another airline's flights |
| **Systems board** | The top of Systems: one line per thing that must work, green, amber or red |
| **All clear** | What Today says when nothing is waiting: no order possible, nothing to file, nothing in needs attention, no Game check differences |

# equinox. rule history

The reasons and history behind the rules in `operating-manual.md`. The manual has the rules in force; this file
says why each is as it is, what was built from the decision list, and which rules were retired. Text moved from the
manual is kept word for word.

---

## 21 Oct 2026: the manual split, and wording aligned
*Gitesh, 21 Oct (document review, items 6 and 9, option A each).* The manual now holds the rules in force only; their
reasons, the built decision items and the retired rules moved here word for word. A rule change replaces the old
sentence in the manual and logs it here. A document check runs first every Saturday (§7) · why: stale copies of the
rules in the playbook, the project files and memory led to the 21 Oct contradictions.
Wording aligned in the split, no rule changed:
- "Decided, not yet built" no longer lists profit per aircraft hour, built 17 Oct (§3).
- §7: the evening capture also runs the world scan when one is due (it had said "nothing else").
- §4: until 31 Oct the new-routes-only rule wins over §1 and §3's frequency rules.
- §3: the A350 where range demands it, or on trunks where the A350-900 sells out, as the default line says.
- The E190-E2 note, the cabin charge check and the weekly report's three competitors were built 21 Oct (written as 22 Oct).
- §4: the Saturday 12-hour list and Tails' 10-hour mark are flags, not floors.
- §4: service codes by distance written in (Gitesh, 21 Oct, option A); they had been in the planner's `service_profiles`
  and the playbook since 10 Oct, with no line in the manual.
- The playbook gives steps only and points here for every rule (Gitesh, 21 Oct, item 7, option A).

## Why each rule is as it is

### The manual's opening line (before the split, 21 Oct)
Every rule in force for the equinox. group, with the date it started and why. Decision #4, 8 Oct 2026.

### How to use it (wording before the split, 21 Oct)
- This manual is the rulebook. Where it and memory disagree, **the manual wins**; memory is background only.
- When a rule changes in any chat, that chat updates this file (and the copy in the Equinox project's files) **in the
  same turn**, and moves the old rule to *Retired rules* at the bottom with the date it ended.
- Rule changes Gitesh agrees in chat are committed directly. Code changes still go through pull requests.
- Numbers that change often (fare levels, cabins, bank times, interline status) live in the planner;
  this manual says where. Foundation decisions are logged in `decisions.md`.
- `playbook.md`, the handover guide, puts these rules in the order we use them (the growth loop, daily, Saturday,
  monthly, every check and what to do when one fails). Where it and
  this manual differ, the manual wins and the playbook is corrected in the same turn.

### Decided, not yet built

#### Report PDFs stay in the database until a trigger
*Since 12 Oct · why (Gitesh): 1.5 MB today and about 50 MB a year; moving them now needs two new programs in Supabase and the backup copying private files, for no gain yet.*

#### Cloudflare's cache waits for a trigger
*Since 12 Oct · why (Gitesh): the call is small and the traffic light; splitting or caching it now gains nothing yet.*

#### A frequency taken away isn't tracked yet
From the built item "New frequencies and the fare ladder are built" (below, *Built from the decision list*).

### Decided, not yet built: rivals' fleets in the world scan
*Decided 23 Oct (Gitesh: raised in the review chat, option A of `docs/briefs/2026-10-23-rival-fleets.md` chosen in
the Building chat).* Why: the scan read schedules only, so Icelandair's 99 aircraft and 44 on order showed nowhere.
Every evening rather than weekly (the brief recommended weekly): the earliest warning, for about 3 minutes more an
evening. The 25% flag: a quarter more aircraft on the way; at least 5 keeps a small start-up's single order off it.

*Built 23 Oct (`Equinox` #93, spec `docs/specs/2026-10-23-rival-fleets.md`) and moved into §7.* The *Decided, not yet
built* entry, retired with the build: "- **To build: rivals' fleets in the world scan** (brief `docs/briefs/2026-10-23-rival-fleets.md`, option A, Gitesh 23 Oct). Each evening's scan also reads every enterprise's overview page (its Fleet table, about 171 pages, about 3 minutes more) and keeps each rival's fleet and aircraft on order by type with the scan. Competition and the weekly report's three competitors show them with the change since the week-before scan, and flag a rival whose aircraft on order reach 25% of its fleet with at least 5 on order (`rival_orders_flag_pct`, `rival_orders_flag_min`), and one with aircraft on order and no flights yet. Until it's built, §7's scan reads schedules and airports only. *(decided 23 Oct; history: rule-history.md)*"

### Decided, not yet built: rivals' connecting options
*Decided 23 Oct (Gitesh: raised in the review chat, option A of `docs/briefs/2026-10-23-rival-connections.md` chosen in
the Building chat with a 1.5 detour limit).* Why: `competition()` counted a rival only where it flies our pair direct,
so connections through a rival's hub (Icelandair via Keflavik) were invisible. In the 23 Oct scan rivals flew 123 of
our 302 flown pairs direct, while one-stop options within 1.5 times the direct distance reached 190. Each connecting
flight counts once so the figure sits on the same scale as direct departures; the detour limit keeps routings far off
the way out (with none, 270 pairs "had" one). Display only until Gitesh decides whether connections count in the
openings, the contested test or the fare pause.

### Decided, not yet built: each week's rivals by pair, kept for good
*Decided 23 Oct (Gitesh, Building chat, option C of `docs/briefs/2026-10-23-rival-pairs-history.md`).* Why: the
monthly archive deletes the scans' full schedules after a full calendar month, and the route page's rival line reads
them, so it would reach back only one to two months. Every pair, so a pair added to a route list later already has its
history; one scan a week, about 20 MB a year against about 155 MB for every scan.

### Decided, not yet built: point-to-point routes away from our bases
*Decided 22 Oct (Gitesh, review chat) · why: Kingfisher's list now holds Inter Connect's network in Ellinikon (the
manual's scale model), about 214 of whose pairs touch none of our bases; every route on our lists is filed under a base
(`routes.hub_code`), so those pairs can't be listed. Gitesh: build it now, fly it after Delhi reaches 750 (hubs first
unchanged). Bases at secondary cities (Lucknow, Ahmedabad, Pune and others) stay a question for a full brief.*

*Every airline since the same day (Gitesh, review chat), not Kingfisher alone · why: the Airbus world's AirAsia flies 52
routes from Kota Kinabalu that don't touch Kuala Lumpur, and Subang is its own market (Tigerair Singapore–Subang 78 a
week, AirAsia Kota Kinabalu–Subang 56) that only pairs away from KUL can serve. The station role is per airline, so the
build already covers it. Earlier wording: "Point-to-point routes away from our bases (Kingfisher first)".*

### 1. How we work

#### Game changes are made in the planner at /planner/
The old planner, its way back at `/planner/old/` (which now goes to `/planner/`) and its code freeze went with the clean-up. *Since 14 Oct (#18, build pull requests 13 and 14) · why (Gitesh): the trial of the new planner passed ("all looks good"), and the clean-up was asked for the same day, so there is one planner, one way of saving and no copies to keep in step.*

#### Say first when something will take more than 5 minutes
*Since 12 Oct (Gitesh).*

#### One item at a time
*Since 7 Oct · why: keeps every build approved.*

#### Code changes are pull requests
*Since 8 Oct (decision #2) · why: the code's only copy was the live site, and a workspace reset wiped the working copy.*

*The new look's exception since 22 Oct (Gitesh: "keep merging if all is good") · why: the redesign runs in four steps over several days, and waiting for a "merge" between each added days for no review he needed beyond the checks and the screenshots. It ended with step 4: the four steps were merged on 22 Oct (#71 to #74), and the exception was taken out of the manual the same day.*

#### Hosting
*Since 8 Oct (#7) · why: free, with unlimited deploys and previews; our own address survives any future change of host.*

#### The build
Served under `/app/` with its page at `/planner/` (since the switch, 14 Oct; `web/_redirects`). *Since 12 Oct (#18, build pull request 1) · why: the planner is a React app that has to be built; the checks run the same build.*

#### Supabase stays on the free plan
*Since 9 Oct (#17) · why: our own backups, #16's small database, daily activity and the local test copy already cover what the paid plan adds, and it's over the $10-a-month limit.*

#### Preview before live
*Since 9 Oct · why: the loads fix's two removed access rules were cancelled three times from the chat.* (On removals applied in Supabase's SQL editor.)

*Since 12 Oct · why: `planner_save()`, which only adds a function, was cancelled twice.* (On trying once more after "cancelled".)

*Since 8 Oct (#8) · why: previews used the live database, so testing one could save into the live planner; database changes were tried first on live.*

#### Automatic checks
The checks' dates: the fares userscript on the saved fares form and answer (since 21 Oct); the capture's world scan against `gscan.py` on the same saved pages (since 21 Oct);

*Since 14 Oct (the clean-up, build pull request 14) these replace the side by sides with the old planner.*

*Since 8 Oct (#9) · why: nothing ran by itself, and 9 of 11 tests couldn't run.*

#### Documentation stays current
*Since 8 Oct (#10) · why: nothing explained how the parts connect, so every new chat rediscovered it.*

#### A new table grants its own access
*Since 20 Oct · why (Gitesh, agreed): Supabase stops granting new tables to the Data API by default on 30 Oct; we already worked that way, but the rule wasn't written down.*

#### Big builds go to a fresh helper
*Since 8 Oct (#26) · why: the old Building chat lost detail as it filled; a clean memory per build fixes that with no extra steps.*

*No polling since 22 Oct (Gitesh: "stop the polling") · why: helpers checked the pull request's checks every minute or so while the database rehearsal ran (20–40 minutes a round), which used most of a build's Claude usage and time. Earlier wording: the helper "runs the checks and opens the pull request", and watched them until green. The checks themselves are unchanged.*

#### Data-only changes go straight in, to the tables
*Since 8 Oct (#2); to the tables since 10 Oct (#13, pull request 9); through `planner_save()` or plain SQL since 14 Oct (the clean-up removed `planner_item_put()` and `planner_item_delete()` with the adapter) · why: the planner reads and saves the tables directly.*

#### Rule numbers have one source
*Since 10 Oct (#13, pull request 9; design §11, choice 3); the old planner's copies in its code, and the cross-check that kept them in step, went with it on 14 Oct (the clean-up) · why: the same number lived in the manual, the planner and the scripts, and drifted (the connection buffer, 9 Oct).*

#### No one-week aircraft checks
*Since 15 Oct · why: Gitesh no longer wants them.*

#### Every decision gets the full brief
*Since 8 Oct (#5) · why: almost every decision spends cash or opportunity, so each deserves full attention.*

#### A new aircraft's routes get a full brief only when the choice is a real trade-off
*Since 16 Oct · why (Gitesh): a brief for every aircraft was heavy, and the real weighing was over new routes.*

#### No one can sign up
*Since 8 Oct (#11) · why: there will never be other staff; a stray account could read every route's profit.*

#### Test samples are the one exception
*Since 8 Oct (#9) · why: checks need fixed data to compare exact answers.*

#### One chat per kind of work
*Since 8 Oct (#3).* *Since 8 Oct · why: each chat keeps its own thread of context.*

### 2. Group strategy

#### One airline per city pair
*Since 21 Oct · why (Gitesh): applying the country rule literally removed 53 pairs no other airline could fly; they were restored the same night.* (On the base exception.)

*Since 23 and 26 Sep · why: our airlines shouldn't compete with each other.*

*US and Canada to China since 22 Oct (Gitesh, review chat, option C of three).* Where Pan Am has no base at either
end, the base exception would have given these pairs to China Eastern. The only record against that was the earlier
removal of Shanghai–Toronto, Vancouver and Detroit from China Eastern's list. The options were: A, keep them off for
good; B, give the 10 pairs the Chinese model airlines fly (Shanghai to Boston, Portland, Toronto, Vancouver, Atlanta,
Houston, Las Vegas and Detroit; Daxing to Portland and Vancouver) to China Eastern; C, Pan Am flies them as stations
once those are built · why C: US–China is Pan Am's flow, and China Eastern needs no widebodies before Shanghai's short
haul is full. Before, the manual said nothing about these pairs; the base exception sentence ended at "so no market
drops off the map."

#### Malaysia
*Since 29 Sep · why: long-haul would have no loads without the feed.*

*The long-haul trigger since 21 Oct (Gitesh, review chat): long-haul starts once every 4- and 5-star opening within the
A320neo's reach is flown. Asked whether that meant the A320neo alone (about 4,700 km) or the whole A320 family with the
A321XLR (about 6,900 km), he chose the A320neo. Before, the manual said only "build the Asian feeder network before
any long-haul", with no point at which feeder-first ended · why: base-case growth gives Malaysia about 58 more aircraft
by 31 Dec, more than its short and medium openings can take, so the end of feeder-first needed a test. On 21 Oct, 27
such openings were unflown (Bali and Taipei on a plan card). Openings beyond 4,708 km (Tokyo Narita, Melbourne, the
Gulf, Brisbane, Adelaide) count as long-haul for this rule. November's trunks keep their exception (§4).*
Old wording: "**Malaysia:** make KUL a world transfer hub; build the Asian feeder network before any long-haul.

#### No new airlines before January 2027
*Since 15 Oct (Gitesh).*

#### Bases
*Base roles from 29 Sep, Kingfisher from 2 Oct, holds from 5 Oct; Ryanair's Barcelona decided 14 Oct (brief `docs/briefs/2026-10-14-ryanair-order.md`); Ryanair's CDG and Amsterdam made focus in the data 15 Oct (Gitesh: none less important than another, point to point rather than hubs).*

### 3. Fleet and orders

#### Kingfisher's A350s handed back
*Since 23 Oct (Gitesh, review chat, brief `docs/briefs/2026-10-23-kingfisher-a350s.md`, option C).* Earlier wording:
"Kingfisher's two Delhi–JFK A350s stay as they are." · why: Delhi–JFK earned about its two leases (1.45M of flight profit
a week against 1.44M) while the pair held 14.39M of security deposits, which come back on return. That money buys about
six A321neo Lights for Delhi's sold-out network, about +2.5 to +3.1M a week after leases, and about 250 more departures
a week towards Delhi's 750. The cost is Kingfisher's only US route until long-haul's turn. The 28 Nov Delhi–JFK review
(to-do #3) is no longer needed.
The sentence was then taken out of the manual the same night (Gitesh): a decision about two aircraft isn't a rule; the
decision lives in its brief. Wording removed: "Kingfisher's two Delhi–JFK A350s (VT-AAA and VT-AAB, DEL) are handed back
and their security deposits go into narrowbodies for Delhi (brief `docs/briefs/2026-10-23-kingfisher-a350s.md`, option
C); Kingfisher's US flying waits for long-haul's turn."

#### Used aircraft: at least a year left
*Since 22 Oct (Gitesh, Scheduling chat).* A used aircraft is taken only with at least a year to fly before its
replacement at 10 years, so 9 years old at most · why: Gitesh: "it's fine as long as it can fly at least 1 year".
Before, the used-market rule set no age ("on the default line").

#### Replacement by age
*Since 22 Oct (Gitesh, Scheduling chat), replacing the 3.5-year limit set an hour earlier.* Aircraft ordered new are
replaced at 3 years; aircraft taken from the used market, at 10 years. N023AW (3.6 years) and 5Y-AAC (7.2 years, a
bid that couldn't be withdrawn) are kept under it · why: used aircraft are taken because they're cheaper, and Gitesh
chose to fly them longer than new ones. The wording it replaced, in §3:
"- **No leased aircraft older than 3.5 years:** an aircraft is replaced when it reaches 3.5 years, and a used aircraft
is taken only under that age." The used-market rule's "on the default line, under 3.5 years old" went back to "on
the default line".

#### No leased aircraft older than 3.5 years
*Since 22 Oct (Gitesh, Scheduling chat).* Leased aircraft fly until they are 3.5 years old and are then replaced; a
used aircraft is taken only under that age. Before, the manual set no age limit, and the evening of 22 Oct took
N023AW (3.6 years) and bid for 5Y-AAC (7.2 years) and proposed VH-AGP (9.0 years) under the used-market rule as first
written · why: Gitesh doesn't want old aircraft flying (he had meant to say so with the used-market rule). The used
market rule's "on the default line" became "on the default line, under 3.5 years old".

#### The used aircraft market in each evening's proposal
*Since 22 Oct (Gitesh, Scheduling chat).* The first used aircraft, 5Y-AAD (A320neo Light, 3.6 years), was bid for as
Pan Am's aircraft at the opening bid instead of a new A320neo SHARP: the same routes, 12% less a week and 0.24M less
down (brief `docs/briefs/2026-10-22-used-aircraft.md`, option B). Gitesh then asked for the used offers to be checked
every day · why: at the opening bid used aircraft lease for 8–37% less than new, few players bid, and a used aircraft
leaves the airline's delivery line free. Before, the manual said nothing about the used market. The ceiling (the new
aircraft's own price) is the brief's; how much age adds to maintenance is still to be seen in the captures.

#### Stars from the game's passenger demand
*Since 22 Oct (Gitesh, review chat).* Every airport on our lists was read from its page in Gander (1,346 of 1,364; 18
codes had no match: AYN, BFU, BIH, BKB, BSL, DAX, IXK, IXV, IXX, JLG, NMB, PAB, PBI, PNH, REW, RUP, SDW, SSE, mostly
closed airports or codes the game spells differently). Gitesh chose the scale (9–10 five stars, 7–8 four, 5–6 three,
3–4 two, 0–2 one) and overrides rather than a new column, since demand doesn't change. 2,405 of the 5,307 routes on
the lists changed: 1,578 up, 827 down · why: the research's ratings were often far off the game's demand (Shanghai
Hongqiao 2 stars at demand 10, Seoul Gimpo 1 at 9, Madurai 3 at 4); the airport-size label was set aside because it
doesn't follow demand (Kyiv "small" at demand 8). Before, the manual had no source for stars; `routes.stars` was the
research's rating.

#### Fleet types, as the route needs
*(Wording aligned 21 Oct: "the A321neo by default" had been left standing after size by stars, 18 Oct, and smaller wins, 20 Oct, replaced it.)*

*Since 17 Oct · why (Gitesh): types are chosen per route, not fixed per airline; three maintenance families are free, a fourth costs 15% more maintenance (28 Sep).*

#### Size by city stars
Within a band, the smaller type wins, heavy routes included: a busy pair gets more flights on more aircraft, not a bigger aircraft, since bookings are divided among the flights on offer and more flights give more connections. The game's markets point the same way (its secondary and small markets default to the E195's cabin).

*Since 18 Oct · why (Gitesh): bookings are divided among the flights on offer (§9), so more, smaller flights take more of a market than fewer big ones; the bigger types go where a city's demand is big enough to fill them.*

#### The default line
Tested 21 Oct (same cabin, the game's route evaluation): up to about 14,200 km every A350 keeps its full cabin and the -900 is the cheapest per seat (LA–Gatwick 334 against the ULR's 337 and the -1000's 342; Mumbai–LA 527, 535, 543); beyond about 15,000 km the -900 loses seats fastest and the -1000 is the cheapest (Dallas–KL 566 against 618 and 680; Sydney–JFK 623, 671, 744). The ULR is never the cheapest, so it is off the line. *Since 21 Oct (Gitesh).*

Left out because another variant beats them: the A350-900ULR (above), the A319neo (more per seat than the A320neo SHARP at every reach), the A321neo Medium, the A321XLR LIGHT and Heavy.

*Since 18 Oct · why (Gitesh, agreed): the LIGHT variants reach only 4,192 km (A321) and 3,690 km (A320); the LR reaches 5,809 km for 3M less than the XLR, and the SHARP is the cheapest 189-seater.*

#### Turnaround of a new variant; reach checked by the Scheduling chat
Both rules came from the built item "#18 and #19 ... Decided 18 Oct, for the Building chat: the planner learns the default line's variants" (below, *Built from the decision list*): "The game shows no turnaround, so a new variant takes its family's (A320 family 66 minutes, E-jet E2 67, A350 90). Reach is checked by the Scheduling chat when it picks the variant for a route (§3), not by the plan card (dropped 19 Oct, Gitesh: the routes are decided before the card)."

#### Order across both delivery lines
*Since 18 Oct · why (Gitesh, agreed): under market share first, an E195 buys about a third more departures for the money (about 310 a week per 10M against 235) and comes sooner on its own line, while the A321neo buys more seats (about 1,000 per 10M against 810); cash, not the lines, limits orders (an aircraft every 2 to 2.5 days per airline against a line delivering every 15 or 21 hours).*

#### When cash doesn't cover the aircraft the top openings need, cash decides
*Since 21 Oct · why (Gitesh, option B): keeping the order queues full comes first; on 21 Oct Pan Am's top openings were 5-star cities needing an A320neo, cash covered only an E195, and it took the best 4-star openings instead.*

#### Route first, then the airline, then the aircraft
*Since 19 Oct · why (Gitesh): the variant can't be chosen without knowing where the aircraft will fly, so the routes are decided first.*

#### Order every evening the forecast allows
*Since 18 Oct (option C); the order queues first and the choice by route since 19 Oct; one airline at a time since 21 Oct · why (Gitesh): the group's cash supports about two aircraft a day; weekly batches left it waiting, and an empty line is an aircraft lost; one airline at a time keeps each decision in view.*

#### When an airline can order: the cash forecast
*Since 7 Oct · why: the old surplus rule ignored flight income during the week; on 7 Oct it said Kingfisher couldn't afford an A321neo when its real lowest point was 6.29M.*

The order's own lease counts: *Since 8 Oct · why: the cushion alone covered only one order's lease.*

The forecast: the planner's Performance screen shows it, and Today's Orders the types safe now (#19, build pull request 3).

#### The order queues
A new order joins the end of its line: on an idle line its first aircraft arrives one interval after the order (the 18 Oct orders: A321neos 21 hours later, E195s 15), on a busy line one interval after the last aircraft already queued (EI-ABU, 21 hours after EI-ABT). *Since 17 Oct · why (Gitesh): plan future orders with the order queue in mind.*

#### Market share first, profit second
Capturing the demand and holding the departures leaves new competition little room to move in. *Since 18 Oct · why (Gitesh): market share first; if we capture the demand and block more slots, new competition can't move in.*

#### The openings, ranked: competition()
Each comes with the variant from the default line (below: the smallest size its stars allow, bigger only for reach, the cheapest per seat whose range covers it, among the types the airline may buy; an opening no type reaches is left out). *Since 21 Oct (spec `docs/specs/2026-10-21-competition-analysis.md`) · why (Gitesh): route first, then the airline: each evening's proposal needs a ranked list.*

#### Add a flight or raise fares, by profit per aircraft hour
*Since 17 Oct; built 17 Oct · why (Gitesh): profit per flight favours long routes because they take longer; per block hour alone would over-reward short hops, whose turns tie the aircraft up for nearly as long as they fly. Brief: `docs/briefs/2026-10-17-add-or-raise.md`.*

#### New routes aren't judged for a week
*Since 16 Oct · why (Gitesh): PVG–CCU and KUL–TRV were marked losing after one round trip, on the day they launched; the losing mark needed only 2 departures.*

#### Hubs first
*Since 5 Oct, confirmed 8 Oct as the only test for opening a new base; extended to bases already open 11 Oct · why: Gitesh: grow the main hub before any other base. G-AADU was nearly planned at Manchester on uncontested routes, which the old wording allowed.*

*Stations open nothing until the main hub reaches the 750, contested or not: since 22 Oct (Gitesh, with the station role, brief `docs/briefs/2026-10-22-point-to-point-routes.md`) · why: under the contested test a station would count as "any other base", so a rival at a station airport would open point-to-point flying before the 7 Nov strategy session decides on it. None of Kingfisher's likely stations is contested in Gander today (21 Oct scan: Ahmedabad 28 rival departures a week, the others none).*

### 4. Scheduling

#### How it runs: every evening, from the order queues
The cabin charge check: Systems → Cabin charges, with one item on Today when one doesn't match, since 22 Oct.

*Since 19 Oct (each evening's proposal from the order queues, the card with the order: route first, then airline, Gitesh); daily orders since 18 Oct (option C) · why (Gitesh): to add aircraft every day. Cash supports about two a day; deciding each aircraft on its own, and aircraft waiting days to be filed, were the limit. Brief: `docs/briefs/2026-10-18-accelerate.md`. The briefing since 15 Oct (#24).*

#### Fly each aircraft as much as it fits
Ryanair's and Virgin's first (11.0 and 11.2 hours a day on 17 Oct, against Malaysia's 13.3). *Since 18 Oct (option C) · why: more flying from aircraft already paid for raises profit per aircraft, and so the pace of orders.*

#### Every aircraft is named by its tail number and base
*Since 19 Oct · why (Gitesh): so each aircraft can be found in the game at once.*

#### Until 31 October, only new routes
*From 18 Oct to 31 Oct · why: Gitesh, 18 Oct.*

*Pan Am exempt since 22 Oct (Gitesh, review chat, brief `docs/briefs/2026-10-22-pan-am-speed.md`, option C) · why: Pan
Am needs to move quickly; 19 of its routes sell out and are marked add a flight while United and American add hundreds
of flights a week on its pairs. Earlier wording: "Until 31 October, only new routes:" with no exemption.*

*China Eastern exempt too, the same day (Gitesh: "apply same exemptions as Pan Am") · why: JAL and ANA started
Shanghai–Haneda (70 a week against our 14) and Air China is moving onto its domestic pairs.*

#### From 1 to 30 November, every new order fortifies the trunk routes
*From 1 Nov to 30 Nov · why (Gitesh, 20 Oct): fortify the routes that connect our bases completely.*

Only trunks that make sense: no base is on hold (Gitesh, 20 Oct).

Long-haul trunks are in too: for November's trunks this sets aside reach first (below) and Malaysia's feeder-first order (§2). *Since 20 Oct (Gitesh): "for this plan, everything which makes sense."*

Shortest to longest: *Since 20 Oct (Gitesh).*

Narrowbody trunks first: *Since 20 Oct (Gitesh).*

*Details agreed 20 Oct (Gitesh).*

#### Maximise connections at both ends
*Since 6 Oct, updated 7 Oct; margin dropped 9 Oct · why: Gitesh: as long as it's over the minimum connection time, it's good.*

#### Night slots are fine
*Since 27 Sep · why: the game's demand ignores time of day, and captures show night departures sell as well as daytime ones.*

#### Turns
*Since 25 Sep · why: room for delays and slot availability.*

#### A second daily
*Since 15 Oct · why: Gitesh, the 3 hours had no business case; we maximise connections within the world's rule.*

#### London: new Virgin Heathrow routes
*Since 21 Oct (Gitesh).*

### 5. Cabins and fares

#### The cabin is chosen with each order
"The most seats" for them is Leisure (clarified 21 Oct, Gitesh).

Wording clarified 22 Oct (Gitesh): the old sentence read "The cabin is chosen with each order", which a chat took to mean the cabin is set on the game's order screen. It isn't: the game takes only the aircraft; the cabin is recorded on the plan card and fitted when the aircraft arrives and is filed. The rule itself did not change.

*Since 20 Oct · why (Gitesh): the new layouts aren't captured by the defaults. Built 21 Oct (spec `docs/specs/2026-10-21-cabins-new-rule.md`): the Cabins board and its refit settings went, and each market keeps only its layout.*

#### Fares
*Since 20–21 Sep · why: every lane ran full at lower fares, and launching low then raising across 50 routes is too much work. The new flight's rule since 21 Oct (Gitesh).* As of 21 Oct every route is at its launch level: legacy airlines 100% of the default price, Ryanair 85% (Gitesh); the fare ladder's first moves start from there.

#### The fare ladder, every Saturday
*Under launch, decided 23 Oct, not yet built (Gitesh, review chat, brief
`docs/briefs/2026-10-23-fare-ladder-under-launch.md`, option C with the revenue check and 2-point steps instead of the
brief's 10).* Why: a cabin that doesn't sell out held at launch for ever, so a weak route's only path was a cut; a
lower fare is tried first. The 80% load limit keeps cuts off nearly full cabins, where they lose revenue; the 60%
floor is the house rule's (§9). The rule in force until it's built: "The level never goes under launch, nor under the
60% floor where another player flies the route."

*Changed 23 Oct, before any build (Gitesh, Building chat): two jumps, to 80% then 60%, each held 2 weeks, in place of
2-point steps.* The wording replaced: "A cabin averaging under 80% full may go under launch, **2 points a step**,
judged each Saturday, down to a 60% floor. A step that lowers the cabin's revenue a flight is undone. A cabin at the
floor and still under 60% full goes to Gitesh as a cut-or-keep decision." Why: a 2-point step moves revenue a flight
by about 2%, while on the cabins it touches revenue a flight swings 23–43% from flight to flight and a week's average
by a median 13% from the week before (`route_days`, 9–22 Oct), so no per-step check could tell a real fall from
noise. A 20-point jump moves revenue by up to 20%, which two weeks can show, and reaches the floor in 4 weeks instead
of about 20. "Paid off" is revenue a flight not falling, not just higher loads (a 32% cabin needs about 40% full at
80% to break even). Under launch the ladder only climbs or holds, so its 5-point cuts don't add to the jumps; each
judgement needs 10 flights so thin routes aren't judged on a handful.

*Ryanair's first jump to 75%, 23 Oct (Gitesh, Building chat).* The entry had said 80% for every airline. Why: Ryanair
launches at 85%, so a jump to 80% would be only 5 points, too small for two weeks to show; 75% then 60%.

*Built 23 Oct (`Equinox` #92, spec `docs/specs/2026-10-23-fare-ladder-under-launch.md`) and moved into §5.* The §5
sentence it replaced: "The level never goes under launch, nor under the 60% floor where another player flies the
route." (now the rule's "otherwise"). The *Decided, not yet built* entry, retired with the build: "- **To build: the fare ladder under launch** (brief `docs/briefs/2026-10-23-fare-ladder-under-launch.md`, Gitesh 23 Oct, its steps changed the same day). A cabin under 80% full over 2 weeks at launch goes to **80%** of the default price (Ryanair, launching at 85%, to **75%**) and holds 2 weeks. If its revenue a flight didn't fall, the normal ladder carries on from there; if it fell, the cabin goes to **60%** and holds 2 weeks the same way. A cabin at 60% still under 60% full, or whose revenue a flight fell, goes back to the last level that paid and to Gitesh as a cut-or-keep decision. Each 2-week judgement needs at least 10 flights, else it waits a week. Under launch the ladder only climbs or holds (no 5-point cuts). The numbers become `settings` rows (`fare_under_launch_*`, Ryanair's levels its own row). Until it's built, §5's 'never under launch' stands. *(decided 23 Oct, these steps the same day, Ryanair's 75% the same day; history: rule-history.md)*"

A route that gained a frequency in the last 7 days holds for that week, so the ladder judges it at its new size, not on the drop the extra seats cause (Gitesh, 21 Oct).

A route whose captured fares don't match its level is set back to it: not for a route on the fare plan this week, a new route, or one not captured since its newest flight launched (since 21 Oct).

**For now it goes at most 20 points above launch** (120%, Ryanair 105%): the game's passengers are price-sensitive and higher fares may hurt the airline's image, so the cap is lifted only once loads and image show it's safe.

*Pan Am's step 7 points and cap 28 points (128%) since 22 Oct (Gitesh, review chat, brief
`docs/briefs/2026-10-22-pan-am-speed.md`, option B with 7 points and a 28-point cap instead of the brief's 10 and 40) ·
why: cash is Pan Am's limit (about 1.27M a day to order with on 22 Oct) and every route sells out at the default fare;
fares are the one lever that adds cash. Earlier wording: "up 5 points", "down 5 points", "at most 20 points above
launch (120%, Ryanair 105%)", for every airline.*

*China Eastern given the same step (7) and cap (28 points, 128%) the same day (Gitesh, review chat: "apply same
exemptions as Pan Am") · why: the group's best cash earner (about 1.75M a day to order with) and nearly every route sells
out. Earlier wording: "(Pan Am 7)", "Pan Am 28 points, 128%".*

A rival starting on the pair pauses that route for a week: Today lists the latest scan's (built 21 Oct with competition analysis).

Route by route only (From A to B, and From B to A): never a whole base, so routes under 7 days old are never touched (Gitesh, 21 Oct: loads are high because the world is young).

*Since 21 Oct · why (Gitesh): the route-by-route changes are a few hundred on a Saturday; his decision. The simulogics terms (§4 II) forbid scripts in general, but Gander is an exclusive world whose owner sets the rules (§9): the capture, the salary script and the scanner are allowed there; the fares script is to be recorded the same way once Gitesh confirms it with the owner (spec `docs/specs/2026-10-21-fares-userscript.md`).*

*Changed 21 Oct (Gitesh: "no need to speak to owner"): the manual used to say the fares script "is to be recorded the same way once Gitesh confirms it with the owner". It is now allowed in Gander like the capture, the salary script and the scanner, with no confirmation step.*

The numbers are settings (step, up, down, hold weeks, cap, and since 21 Oct the hold after a new flight, `fare_ladder_capacity_hold_days`).

*Since 21 Oct · why (Gitesh, option A of `docs/briefs/2026-10-21-fare-ladder.md`): 88–98% of economy flights and 98–100% of business flights sell out at launch fares, no fare had ever been raised, and each 5% step that holds is worth about 5M a week.*

### 6. Interline

#### Gulf hub carriers are rivals
*Since 5 Oct · why: they would carry our passengers through Dubai against Kingfisher and Malaysia.*

### 7. Recurring work

#### Every evening: the capture
*Since 7–8 Oct; salaries taken out 10 Oct; into the tables only since 10 Oct (#13, pull request 9).*

#### Then the world scan, when one is due
*Since 21 Oct (spec `docs/specs/2026-10-21-scan-in-capture.md`) · why (Gitesh): competition analysis and the evening order proposal need fresh rivals, and the scan in the capture costs no extra work; raise `scan_every_days` to 3 (about twice a week) if the evening gets long.*

#### Each page is checked as it arrives
*Since 14 Oct (#21) · why: 11 and 12 Oct were missed and nothing said so for two days; loads for about 780 flights were lost.*

#### Salaries
*Since 10 Oct · why: Gitesh suspects the nightly adjustment of all six airlines was inflating salaries.*

#### Every Saturday: the world scan
*Since 21 Oct (spec `docs/specs/2026-10-21-scan-in-capture.md`); a Saturday step since 14 Oct (#22) · why (Gitesh): only one scan had been taken by 14 Oct, because no step called for it; since 21 Oct the capture takes it.*

#### Every Saturday: the weekly report
The pace towards an aircraft a day per airline (*since 20 Oct, Gitesh*).

Each of our airlines against its three biggest competitors (*since 18 Oct; built 22 Oct, spec `docs/specs/2026-10-21-report-three-competitors.md` · why (Gitesh): to see whether each airline is gaining on its rivals*).

The only investor report: *The separate monthly report was dropped 15 Oct · why: Gitesh, it repeated what four weekly reports already say;*

#### Every night, after the capture: the backup
*Copies in R2 since 9 Oct (#16) · why: the single backup file would pass GitHub's 50 MB warning around late November and its 100 MB limit around December or January.* *Since 8 Oct (#6) · why: there were no backups, and the planner is one row.*

#### Every job writes a row to job_runs
*Since 11 Oct (#13 pull request 7, the jobs brief) · why: the daily record needs a fallback, the capture tables their clean-ups, #16 its archive before 1 Dec, and a job that fails must be seen.*

#### The Systems board
The Systems board, at the top of Systems (#23; of Check until 20 Oct). The world scan's age (amber over 8 days, red over 15; it runs with the evening capture since 21 Oct).

*Since 14 Oct (#23) · why: Home showed problems only, and deploys and usage nowhere.*

#### First Saturday of the month
*Since 8 Oct; no separate monthly report since 15 Oct.* *Since 14 Oct (#23) · why: the board measures the rest every time Systems opens.*

### 8. Writing, website and newsroom

#### What the newsroom posts
*Roundups per airline since 17 Oct · why (Gitesh): one post per airline reads like each airline's own news. No delivery posts since 20 Oct (Gitesh).*

### 9. Game rules and mechanics (Gander)

#### Used aircraft auctions
How the auction ends, the 110% immediate purchase and the cost of age are from AirlineSim's documentation (the 2012
aircraft market announcement and the Handbook's building your fleet); that a used aircraft gets cheaper the longer it
stays unsold, and that the ferry from the factory costs nothing, are from Gitesh, from playing the game (22 Oct).

#### Bookings are divided among the flights on offer
Bookings on a route are divided among the flights on offer, so more departures win more of a market than fewer, bigger flights (Gitesh, from playing the game, 18 Oct).

---

## Built from the decision list
Moved from the manual's *Decided, not yet built* on 21 Oct, word for word.

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
- **Decided 18 Oct, for the Building chat:** the planner learns the default line's variants (§3). *Built 19 Oct:* each
  variant is in `aircraft_types` with its seats, cruise speed, deposit (`price`) and range with a full load (`range_km`),
  from Gitesh's sheet of the game's pages, every airline may buy each (Ryanair no A350), so the cash forecast tests them,
  and their cabin layouts are in `cabin_configs`. The game shows no turnaround, so a new variant takes its family's (A320
  family 66 minutes, E-jet E2 67, A350 90). Reach is checked by the Scheduling chat when it picks the variant for a
  route (§3), not by the plan card (dropped 19 Oct, Gitesh: the routes are decided before the card).
- **The fare ladder is built** (21 Oct, pull request #56): `fare_ladder()` works out each route's level and Saturday's
  moves, and Performance lists the fewest game actions with **Put on the fare plan** (§5). A rival's pause is built
  with competition analysis (below).
- **New frequencies and the fare ladder are built** (21 Oct, pull request #60; spec
  `docs/specs/2026-10-21-frequencies-and-fares.md`, §5): a route that gained a frequency in the last 7 days holds
  (`settings.fare_ladder_capacity_hold_days`); every plan card shows each route's fare level (Tails → Deliveries, the
  card check's `fares`, the airline briefing); and a route whose captured fares don't match its level gets a change
  that sets it back, first in Performance's fare ladder and made by the fares userscript (which also shows whether the
  game prices a new flight number at the default price, as Gitesh thinks). The fare index reads each flight of the
  latest captured day against its route's fare on 21 Oct 2026. A frequency taken away isn't tracked yet.
- **Competition analysis is built** (21 Oct, pull request #62; spec `docs/specs/2026-10-21-competition-analysis.md`,
  brief `docs/briefs/2026-10-21-competition-analysis.md`): `competition()` gives each airline's market share by market,
  the rivals' threats, its openings ranked (§3) and the rival profiles from the world scans; the planner's
  **Competition** screen shows them, Today lists the latest scan's threats, the fare ladder's rival pause works (§5),
  and the airline briefing carries the top 20 openings for the evening proposal.
- **The route page is built** (21 Oct, pull request #65; spec `docs/specs/2026-10-21-route-page.md`): `route_story()`
  tells a route's story since launch (loads and fares by cabin, profit an aircraft hour, the events on it: fare moves,
  frequencies, cabin changes and rivals, who else flies the pair), shown at `/planner/performance/<code>/<route>` and
  linked from Routes, Performance, Today and Competition. The daily history (`route_days`) now keeps each cabin's
  passengers, seats and fares and the hours flown. With it the four steps of the 20 Oct planner work are done.
- **The tidy-ups are built** (21 Oct, pull request #64; spec `docs/specs/2026-10-21-tidy-ups.md`): a world scan that
  stops part-way is marked stopped and Systems says so; a 1-star opening on the E195-E2 also names the E190-E2 "if
  thin" (the evening proposal decides, §3); and Systems → **Cabin charges** checks each first cabin fit logged since
  18 Oct against the game's charge, with one Today item when any doesn't match (§4).
- **Stations are built** (22 Oct; spec `docs/specs/2026-10-22-station-role.md`, brief
  `docs/briefs/2026-10-22-point-to-point-routes.md`, option A). The manual's *Decided, not yet built* entry, word for
  word, before it moved into §2 as built: "**Point-to-point routes away from our bases, for every airline (Kingfisher
  and Malaysia first):** stations, a third role in the airline's bases beside hubs and focus cities, for airports we fly
  to and from without making them a base (for example Lucknow for Lucknow–Patna): no banks, and flight numbers in 3
  digits from one pool per airline, 100 to 999 (Gander's flights use up to 4 digits; the 21 Oct scan shows none with 5).
  Stations are never treated as hubs or focus cities (trunks, the website, reports). Malaysia's include Subang (its own
  market, 30 km from KUL) and Kota Kinabalu's pairs away from KUL. Brief `docs/briefs/2026-10-22-point-to-point-routes.md`,
  option A. Building now. *(decided 22 Oct; every airline since the same day; history: rule-history.md)*"

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

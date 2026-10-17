# The planner, screen by screen

A plain-language guide to equinox-alliance.com/planner/: what each screen shows, where its numbers come from, and what
you'd do there (decision #10). The words in **bold** are what the screen itself says.

Most numbers come from **last night's capture**, the *Capture all airlines* button you press in the game each evening.
The plans (plan cards, frequencies, aircraft, to-dos) are what you and Claude entered. Each change is saved on its own,
as you make it. On a preview address the planner saves nothing and says **preview · not saved** (#8).

## The planner
- **The planner is at /planner/** since the switch on 14 Oct (#18, build pull request 13): rebuilt in React with
  TypeScript, screen by screen, each checked against the old screen's figures on the same data before it was merged.
  **Game changes are made here** (manual §1). It's the only planner: the old one went with the clean-up the same day
  (build pull request 14), and its address, /planner/old/, now opens this one.
- **Every screen has its own address** (/planner/routes, /planner/tails/N001AW, /planner/review/VS …), so a link or the
  back button reopens it. Links from the build (/planner/next/…) still work: they move to the same address under
  /planner/.

## Signing in and the header
- **Signing in:** the same email and password as before. An account that isn't staff is signed out with **This account
  doesn't have access to the planner.**
- **The header:** the nine screens in the old order, the **search** box, **Local** / **UTC** (it starts as the planner's
  setting and remembers your choice on this device), the save state, **Website** (the public site) and **Sign out**. On
  a phone the screens sit on their own row, which you swipe sideways. Under it, on every screen, the **game clocks**:
  one per time zone of our bases, west to east, with the time there, a dot for day or night and the bases' codes. (The
  old planner also has a band of the UTC day under its header, but keeps it hidden; this one does the same.)
- **The save state:** **saved**, **saving**, **not saved · retry** (tap it to send again; nothing is kept on the device,
  so closing the tab loses an unsaved change) or **preview · not saved**.
- **The search** (press **/** to jump to it): type a flight number, with or without the airline's code (**1008**,
  **KF 1008**), part of a registration, two airports (**DEL-BOM**), an airport or the start of a city. It finds what the
  old planner's search found, at most 14 results; **Enter** opens the first. A flight opens its route, an aircraft its
  page on Tails, an aircraft on order (or a flight on its plan card) its card on Tails, an airport the airline's routes
  there. On a phone the box is hidden, as on the old planner.
- **Saving:** each change is saved on its own. If someone changed the same thing since you opened it, nothing in that
  change is saved; the screen shows what's there now and says what changed.
- Every screen works at phone width, with no sideways scrolling. Previews save nothing.

## Home: Overview
*The whole network at a glance.* It looks and works as the old Home.
- **At the top, the globe:** the earth lit as it is now, every route, each aircraft in the air as a light, "**N aircraft
  in the air.**" and four tiles: **flights today**, **departing in the next hour**, **aircraft on N routes** and the
  **average load, last 7 days**. It moves on each minute and turns slowly (not if your device asks for less motion);
  drag it to turn it. The planning library works out the aircraft in the air and the flights from each leg's own times,
  so near midnight UTC the counts can differ slightly from the old planner's, which read each route's local days.
- **The key figures** (aircraft, routes flying, flights a day, seats a day, the average economy load over 7 days) are in
  the page but hidden, as on the old Home, where the globe's tiles stand in for them. The average load is the
  database's: every flight the loads pages captured in the last 7 days, averaged (or, with none captured, every flight
  the load reports cover).
- **The network right now:** the map of every route in its airline's colour (wider the more flights a day), our bases
  and the airports they reach, with night shaded as it is now. **+**, **−** and **⟲** zoom; the wheel zooms where it
  points, and a zoomed map drags. An airline's button shows that airline, centred on its busiest base, with its routes
  coloured by economy load over 7 days (green 95%+, amber 85–95, orange 70–85, red under 70, grey without loads).
  **Planned** adds, dashed, the routes on the plan cards of aircraft not yet in service. Hover over a line or a dot to
  name it; a route opens its pop-up (its distance, demand, flights a day, loads, the load pattern's signal and each
  frequency, with **Open in Routes**), a planned route its aircraft in Aircraft on order.
- **Aircraft on order:** each aircraft not yet in service, by airline: its type, when it arrives (UTC), its base and
  plan. **File into planner** appears once one has arrived with a plan card, and files it on Tails (below).
- **Needs attention:** things to act on, grouped by kind as on the old Home, each item linking to where it's fixed; an
  item about one aircraft (its maintenance, turns or positions) opens its pop-up.
  - the capture (an airline not captured for 26 hours, red at 48) and the backup (no good copy for 30 hours, or the
    last run failed);
  - **a capture page that came in short or broken** (#21), the same night: "Kingfisher's capture came in short: loads
    12 of 78 flights", in the Capture group, linking to Check. Capture that airline again; the line goes once its pages
    are all good;
  - **Nightly jobs** (#13): the daily snapshot more than 30 hours old, the 10:00 UTC job not run for 30 hours (the
    database's scheduler may have stopped), the month's archive not run by the 3rd, or any job whose last run failed,
    with its note;
  - to-dos and one-week checks due (a week after an aircraft's latest launch or schedule change, the setting
    *aircraft_check_after_days*; at 0 the checks are off and none are listed, manual §1 since 15 Oct);
  - maintenance, turns and positions, night bans, flight numbers used twice;
  - airports from 80% of the game's departure cap (the setting *airport_cap_warning_pct*);
  - **Interline:** how many airline–country pairs on Interline have no agreement yet (not signed, declined or without
    a partner in the game), from the same rows and rules as Interline (the setting *interline_rules*);
  - routes to fix, from the captured profit (with none captured, from the load patterns, as on the old Home);
  - when an airline can safely order.

  **×** dismisses an item and **show again** brings every dismissed item back. Fare-plan items aren't listed here;
  they're reviewed weekly.
- **Coming up:** the next 14 days, meaning one-week checks and to-dos. While the checks are off there are none, and
  no **One-week checks** button.
- **To-do:** the board where Claude puts anything you need to do or check (with steps). Tick an item when it's done, or
  tell Claude and it ticks it; add one with its steps, one a line; **×** deletes one after asking you in the page.
- **The airline cards** at the foot: each airline's logo, whether it's flying, its hubs and focus cities (filled once a
  route flies from them), aircraft, routes, flights and block hours a day, its lowest maintenance, short and tight
  turns (or **clean**), with its home city's photo behind when the website has one (the city is the airline's own,
  *airlines.photo_city*). **Open fleet ›** opens the airline on Tails.

## Routes
*Every route in the network. Pick one to schedule its flights.*
- **The list:** one airline at a time (its buttons at the top); search by destination; **Active only**; sort by stars,
  distance up or down, destination or load; **km from** and **km to**; and the chips for **Bases** (with a focus city,
  **All routes** or **Trunks only**, its routes to the airline's hubs), **Demand** (★ to ★★★★★, from the route
  research) and **Markets** (for example Transatlantic – dense). The filters are in the address, so a link (or the
  back button) brings them back. Each row has its stars, market, distance, its load over 7 days, round trips a day
  (green when every frequency fits the banks), aircraft and numbers. **Add route** adds one by its destination code
  (city and distance from the airport list, or typed); **Remove N unflown routes shown** removes those after asking in
  the page. Removed routes can be restored from Reference.
- **A route** (its own address, such as /planner/routes/PA/JFK-ORD): stars, airline, market, distance and the two UTC
  offsets; the estimated block on the market's aircraft, its plan and prices, the service profile and the hub's banks;
  **edit route** (stars, market, distance, city, the offsets) and **remove route** (only once it has no frequencies,
  after asking in the page). Not flown yet, it shows the next free flight numbers; flown, its loads over 7 days.
- **Each frequency:** the outbound and the return with their times (local, or UTC as the header says, the other shown
  small), the block time (typed, or **est** from the planning library's estimate), **+1** where a time falls on a later
  day, and each flight's load. Then every check: night bans, a number used twice, the bank fit at both ends, the turn at
  the destination, the aircraft's position and the second-daily gap (the last two new: the old Routes didn't show
  them); then the connections at both ends, in all six airlines' flights. Type days (such as 135) and times in local
  time at each end; each box saves when you leave it. **Add frequency** takes the next free numbers; **Remove** asks in
  the page first. The aircraft's registration beside its box (**N001AW ›**) opens its pop-up, as Home's does, with the
  address (?aircraft=N001AW) so a link reopens it.
- **Changing an offset** keeps the local times, as the old planner did: the page first lists every flight whose UTC time
  moves and asks. Empty the box to go back to the game's offset.
- **Estimates:** where an arrival isn't typed, the planning library's estimate (25 minutes plus the distance at the
  type's speed, manual §4) is used, so it can differ by a few minutes from the old planner's, which it fitted to the
  times typed in.

## Tails
*Every aircraft: what it flies each week and how hard it works.*
- **The list:** one airline at a time; filters for **Base**, **Type** and **Flying**, **No flights** or **Needs a look**
  (a short turn, a leg starting where the aircraft isn't, or maintenance under 105%), kept in the address. Each
  aircraft's type, cabin, base, **Legs/wk** (flights a week), **Block h/day** (hours flown a day), **Maint.** (usable
  ground time against the maintenance time the aircraft needs: 100% or more is enough; hover or tap for the hours) and
  **Routes**; a red dot marks a short turn or a leg starting elsewhere. **Add a tail** adds one by hand at the end of
  the list; **remove** retires one (never deleted, so its history stays) after asking in the page, and not while it
  flies a route. On a phone the list is a column of cards.
- **An aircraft** (its own address, such as /planner/tails/N001AW): its type, cabin, legs a week, block hours a day, gap
  target, minimum turn, gaps at the target this week and maintenance; the fields that change it (registration, type,
  base, cabin, the maintenance gap, notes; each saves when you leave it), **Delete aircraft…** (its round trips go and
  it's retired, after asking in the page); every issue (under the block-hours target, short and tight turns,
  maintenance, legs starting elsewhere, the longest gap, rotations off wave), or **schedule clean**; its week as bars in
  its base's local time, red where a turn is short or the next leg starts elsewhere; and its legs by flight number with
  days, times, duration, the ground time to the next and the turn or gap. The types offered are the ones the airline
  may have (Reference), and the cabins its kind of airline's.
- **Deliveries:** every aircraft with a delivery, for the airline and the base and type picked above: **Open** (on
  order, or arrived and not scheduled), **On order**, **Arrived** or **Flying**, each with its date and time (UTC),
  base, plan and status; **card** shows its plan card (title, base, each flight's number, route, times, block and
  service). **remove** takes an aircraft off the list of deliveries at once: one not yet in service, with nothing that
  points at it, goes; one that has flown or been paid for is retired; one in service just leaves the list.
- **File into planner** (on an arrived aircraft's plan card, or from Home): the planner reads the airline's schedule
  from the game and compares each flight on the card. When every one is the same, it files at once. Otherwise it shows
  each flight, the card's times and the game's, **same**, **different** or **not in the game**, and you file with **the
  game's times** (the card takes them too) or **the plan card's times**. Filing puts the aircraft in service, logs its
  first cabin fit (its order's cabin, or the one an order of its type comes with, from the database), and adds each
  flight with its return as a round trip, launched today. It then opens the aircraft.
- **The aircraft pop-up** (from Home's needs attention, or a frequency's aircraft on Routes): its base, block hours a
  day, legs a week, maintenance, the one-week check, every issue and its flights, with **Mark checked** and **Open in
  Tails**. While the checks are off (*aircraft_check_after_days* 0), there's no check line and no **Mark checked**.
- The block-hours target (10 h a day) is a setting, *aircraft_block_target_h*: a flag on the screen, not a floor.
- **The plan card's service check** (14 Oct): a flight on a plan card whose service code isn't the one its route's
  distance calls for shows it beside the code, in red: **S1, wants S3**, or **none, wants S2** when it has no code.
  Ryanair takes its own **R** on every route. The distance is the route's (the airline's own, either way round, with any
  override), as filing takes it, else the great circle.

## Hubs
*Each base's day: banks, arrivals and departures, and which flights connect.* It only shows; nothing on it saves. Times
are local at the airport, whichever way the header's **Local** / **UTC** is set, as on the old Hubs.
- **The address** names the airport and the day (/planner/hubs/DEL?day=2, Monday being 0), so a link reopens the same
  board. /planner/hubs opens the first base on Monday.
- **The toolbar:** every base and focus city, the seven days, and the count line: departures and arrivals that day,
  departures a week (every airline's) against the game's cap per airport (**over cap** past it), and the base's next
  free flight-number pair with the last one used.
- **A focus city** says it has no banks of its own and is timed to its hub's.
- **The day:** the strip with each bank's arrival window (green) and departure window (orange, **B1**, **B2** …), a tick
  for every flight (red for a departure off wave), and the bars hour by hour.
- **The week:** 15-minute slots in local time, departures over arrivals, shaded by the bank windows. On a phone it
  scrolls inside its own box, as the day strip does.
- **The flights** that day: time, direction, flight, to or from, aircraft and the bank pill (**bank N**; **off wave**
  for a departure in no bank, **outside the banks** for an arrival that can't make one; none for an airline with no base
  there or a focus city). An arrival is named with a bank only when it connects onto that bank's departures within the
  connection rules (from the airport's minimum connection time to 8 hours); since the clean-up (14 Oct, design §16) the
  329 arrivals a week the old Hubs named with a bank they could only reach after a longer wait say **outside the
  banks**.
- **Connections at [airport]:** by bank and outside the banks, the airports arriving and leaving, the city pairs (each
  once, at its shortest connection, from the airport's minimum connection time to 8 hours, never back where it came
  from) and the tightest eight as examples, across all our airlines. Beside each count of airports, the flights by
  region (**North America 7 · South Asia 2**), as on the old Hubs; each country's region is in the database
  (*countries.region*, 14 Oct), where the old Hubs kept the list in its own code.

## Check
*Last night's capture, aircraft checks, growth signals, Game check and the daily load report.* The Systems board at the
top, then the same six boards as the old Check, each folded on arrival. Click a board's title to open or fold it, or use
**Expand all** and **Collapse all**. Each button is saved on its own, as one change.
- **Systems** (#23): one look says whether everything worked. It stays open, one line each with a green, amber or red
  mark and when, and its title says "all good" or how many lines are amber or red:
  - **Evening capture**, one line per airline: when its latest page came, and its pages' verdict (#21): "all good", or
    what came in short or broken ("short: loads 12 of 78 flights"). Amber after 26 hours or when a page was short, red
    after 48 hours or when a page was broken. Pages stored before 14 Oct's checks say "not checked".
  - **Daily snapshot:** the latest day in the daily history, taken by the capture (green) or by the 10:00 UTC fallback
    and so incomplete (amber); amber after 30 hours, red after 54 or when its last run failed; amber too when the 10:00
    UTC job hasn't run for 30 hours (the database's scheduler may have stopped).
  - **Nightly backup:** the last good copy (its restore check passed), its size and rows; amber after 30 hours, red after
    54 or when the last run failed.
  - **Monthly archive:** whether it ran this month; amber from the 3rd if it hasn't, red if a table and month failed.
  - **Clean-ups (10:20 UTC):** the last run; amber after 30 hours, red after 54 or when it failed.
  - **World scan:** its age (the Saturday review runs it first); amber over 8 days, red over 15.
  - **Planner build:** when this planner was built and the change it came from. After a merge the time moves within
    minutes; if it doesn't, Cloudflare's build failed (its log is in Cloudflare's dashboard).
  - **Database size, Report PDFs, The website's data:** each against its trigger (350 MB, 50 MB, 500 KB; manual §1),
    amber from 70%, red at the trigger. Supabase's egress and the website's calls a day stay the monthly look by hand.

  Home still lists the problems; this board is where "all good" shows. **Reload** on the Capture board reads it again.
- **The address** keeps the daily load report's day (/planner/check?day=2026-10-12), so a link reopens that day.
  /planner/check opens today (UTC). An aircraft's pop-up adds ?aircraft=REG.
- **Capture:** what the capture collected for each airline, and when (UTC), with **Reload** and the backup's line. If
  an airline is missing, press the capture again. Each page is checked as it arrives (#21): the capture's panel in the
  game ends each airline with "all good" or what came in short or broken, and the Systems board above shows the same.
- **Growth:** where each airline should grow next.
  - **Main hubs towards 750 departures a week:** hubs first. Each main hub reaches 750 before another opens, unless the
    new one is contested.
  - **Next move for each airline:** each airline rotates its orders, big market → frequency → smaller feeder. It names
    each route, its stars and the suggested aircraft size (the setting *suggested_size*, with Ryanair's own). **Log an
    order as** (**Big**, **Frequency**, **Feeder**) records an order so the rotation moves on.
  - **Ready for another flight:** routes that sold out on most departures in the last 7 days and make at least as
    much an aircraft hour as the airline's middle route. An aircraft hour is the flight's block time plus the type's
    turnaround and the 10-minute turn margin: the time the aircraft can't fly anything else. **An aircraft hour** is
    its own column, beside profit a flight.
  - **Raise fares:** sold out, but earning less an aircraft hour than the middle route.
  - **Fix or reduce:** losing money, economy under 75%, or a thin margin. A route isn't listed until it has been
    flying for 7 days (the setting `growth_new_route_days`); a new route that sells out is still listed above.
  - **Aircraft losing money after their lease.**
  - **Order queues:** how long each delivery line has before it runs dry, for the families each airline may have (from
    the database).
  - **Hub readiness:** how many cities feed each bank, counted by region (*countries.region*).
- **Aircraft checks:** one check a week after an aircraft is scheduled, with the aircraft's issues and its routes' load
  pills; the ones coming up by day. You do these in the game, and only you mark them checked (**Mark checked**). The
  board isn't shown while the checks are off: the setting *aircraft_check_after_days* at 0 (manual §1, none since
  15 Oct). Any number above 0 brings it back.
- **Cabins:** each aircraft's cabin against the usual cabin of the markets it flies. **Refitted to …** records a refit
  done in the game: the aircraft takes the cabin and the refit's cost (0.2M, the setting *cabin_refit_cost*) counts as a
  loss that day. **Keep as is** takes an aircraft off the list; **Show again**, under "kept as is", brings it back.
- **Game check:** **Check against the game** reads each airline's live schedule from the game. Each airline's line says
  how many flights are in each and the differences. **Review** lists them, with **Use the game's times** where it's only
  a time or a day change, **Fix all from the game**, and the game's flights the planner hasn't got, each with an
  aircraft and **Add to planner** (for a new aircraft, pick **new tail…** and type its registration in the box). After a
  fix or an add the differences are worked out again from the planner as it is now.
- **Daily load report:** **‹** and **›** move a day. Every departure by airline, with its loads by class from the
  capture (the last 9 days), or the day's summary from loads typed by hand.

## Review
*How each airline is doing: cash, the 14-day forecast, and profit by route and by aircraft.* Its boards fold as Check's
do (all folded on arrival; click a title, or **Expand all**). Every money figure is the database's.
- **The address** names the airline: /planner/review/VS. /planner/review opens the first airline, as the old Review
  did. A link from Home's needs attention (/planner/review/AW/JFK-ORD) opens the airline with the route profit table
  filtered to that route.
- **The group today:** each airline's row, from last night's capture: flight profit a day (before leases), leases and
  the week-end closing a day (this week's scheduled payments), and net. The old board's six group totals are gone:
  each airline is its own business (manual §5).
- **One card per airline:** **profit a day** over the last 7 days; **per aircraft** (profit a day ÷ aircraft flying);
  **return on fleet** (a week's profit ÷ the value of the aircraft flying); **an aircraft pays back in** (average
  aircraft price ÷ profit per aircraft a day); **funds a new aircraft every** (average aircraft price ÷ the airline's
  profit a day); fleet, flights a day, average load; **next order**, from the cash forecast. Tap one to open its page.
- **The airline's page:**
  - **[Airline] profit:** profit for each of the last 14 intervals between captures (the change in cash plus that
    day's order payments), with the 7-day average and the table of reported days. Cash moves on payment days, so read
    the average.
  - **Cash, next 14 days:** today's captured cash, plus flight profit from the last day's bank statement, minus every
    scheduled lease and week-end closing. An order is **safe** when 0.5M stays in hand at the lowest point afterwards,
    counting the new aircraft's own weekly lease from 7 days after it arrives. This is how ordering is decided (manual
    §3). The types safe to order are listed by type.
  - **Route profit:** each captured flight's income minus its flight costs (fuel, handling, on-board, landing and
    air-traffic fees, maintenance), from the bank statement, for the last day, 3 days or 7 days, with the filters,
    both charts and the table; each route is marked **add a flight**, **raise fares** or **hold**. **+ fare plan** plans
    a 5% economy rise (the setting *fare_plan_raise_pct*) from the route's latest captured fare. Under it, the
    **aircraft** (each one's flight profit a day, less its lease) and the **fare changes** spotted in the captures,
    with the load the day before and after.
  - **Fare plan:** the fare changes to make in the game, with **remove**. The next capture spots each one. It's
    reviewed together on Saturdays.
  - **Manual entry:** only if a night's capture failed. Cash and fixed costs for today (**Save** keeps a figure only
    where it differs from the capture's), the nightly log, and **Loads by hand**: type each airline's flights under
    95%, or paste the game's load table, **Read paste**, check it and save, ticking each day that is complete. Loads
    typed or pasted change only the days and flights you enter; captured days stay as they are. A typed figure wins
    over the capture's where it is newer.

## Interline
*Which foreign countries each airline flies into, and whether it has an interline agreement there.*
- **Interline agreements:** one row per airline and interline country it flies to or has planned (on a plan card not
  yet filed), with the airports, round trips a day (or **planned**), the status (still to sign, signed or declined),
  the partner in the game, since when and notes. Each saves as you change it (a box when you leave it). The **Airline**
  and **Status** chips filter the rows and are in the address (/planner/interline?airline=KF&status=open). Home's
  needs attention counts the rows still without an agreement.
- **The interline countries:** the countries with a real domestic network or a regional gateway, why each one is, the
  partners that exist in Gander (each a link to its page in the game) and our airlines flying or planned there; then
  what to do when another airline asks, and the countries each of our airlines covers. Each airline signs its own
  partner, and the group's airlines already interline with each other. The countries, partners and rules are a setting
  (*interline_rules*), where the old planner kept them in its code.

## Photos
*Airline logos and destination photos for the public website.*
- A card for each of our airlines' logos (in the airlines' order) and for each destination, busiest first, **Missing a
  photo only** to start with.
- **Upload photo** or **Replace** (with a credit) and **Upload logo** resize the picture in the browser and put it live
  on the website at once. **Remove** and **Use the in-game logo** ask in the page first, and go back to the in-game logo
  or the plain card. A preview uploads nothing.
- Each destination's name, and the city photo it shows when it has none of its own, are the website's, from the same
  data the website reads (since 15 Oct; before, each kept its own copy of the lists).

## Reference
*Banks, aircraft, configs, markets and time zones.* Each section is folded on arrival; opening one puts it in the
address (/planner/reference/night-bans), so a link reopens it. Each box saves when you leave it, as one change.
- **Hubs, focus cities and banks:** a hub runs banks and connections. A focus city is a base that serves its own market
  and feeds a hub.
- **Constants** are rule numbers (the settings, the departures cap in the world's rules): only numbers are taken, and a
  change to one goes in the operating manual too.
- **Aircraft** and **Configs:** block estimates are the block allowance plus the distance at the type's cruise speed
  (manual §4); seats per cabin config.
- **Order cabin** (in Aircraft, since 15 Oct): the layout a new order of each type comes with, picked from the type's
  own layouts (— for none). Tails files an arrived aircraft with it when the order names no cabin of its own, and the
  cash forecast prices an order with it. **An airline's own order cabin**, below the table, is for an airline whose orders
  come with another layout (Ryanair's Standard cabins): pick the airline and type and **Add** (it starts as the type's),
  then pick its layout; **remove** gives it the type's again. Each pick saves as one change.
- **Market defaults** and **Service profiles:** what a new frequency starts with.
- **Removed routes:** **restore** (or **restore all**) any route removed from Routes.
- **Night bans:** airports that close overnight (find, change, remove, **Add**). Flights inside a ban are flagged on
  their route.
- **Game schedules:** each airline's public schedule page, used by Check → Game check, worked out from its game ID.
- **Time zones:** the game runs standard time all year. Override an airport only if the game disagrees; **Set** lists
  the flights whose UTC time moves and asks first, as Routes does.
- **Storage:** whether saving works, with **Save now**; nothing is kept on the device.
- **Data:** **Export backup (JSON)** (every planner table) and **Export flights (CSV)**. Importing a backup and clearing
  everything are gone with the tables (design §14): the nightly backup and the change log are the safety net.

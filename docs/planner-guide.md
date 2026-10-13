# The planner, screen by screen

A plain-language guide to equinox-alliance.com/planner/: what each screen shows, where its numbers come from, and what
you'd do there (decision #10). The words in **bold** are what the screen itself says.

Most numbers come from **last night's capture**, the *Capture all airlines* button you press in the game each evening.
The plans (plan cards, frequencies, aircraft, to-dos) are what you and Claude entered. The planner saves itself a moment
after every change. On a preview address it saves nothing and says **preview · not saved** (#8).

## The new planner, at /planner/next/
*Being rebuilt screen by screen (#18). Use the planner at /planner/ until you say switch.*
- **What's there so far:** sign in with the same email and password as the planner. An account that isn't staff is
  signed out with **This account doesn't have access to the planner.**
- **The header:** the nine screens in the same order, **Local** / **UTC** (it starts as the planner's setting and
  remembers your choice on this device), the save state and **Sign out**. On a phone the screens sit on their own row,
  which you swipe sideways. Under it, on every screen, the **game clocks**: one per time zone of our bases, west to
  east, with the time there, a dot for day or night and the bases' codes. (The old planner also has a band of the UTC
  day under its header, but keeps it hidden; the new one does the same.)
- **The save state:** **saved**, **saving**, **not saved · retry** (tap it to send again; nothing is kept on the device,
  so closing the tab loses an unsaved change) or **preview · not saved**.
- **Home, Routes and Tails are rebuilt** (13 Oct, build pull requests 5 to 7); each shows what the old screen shows,
  from the same data and with the same figures (below). **The other six screens** still say they're in the old planner,
  with a link there, and a link from Home to one of them (a needs-attention item, say) lands on that line.
- **Home in the new planner** looks and works as the old Home (13 Oct, after the Building chat's review):
  - **At the top, the globe:** the earth lit as it is now, every route, each aircraft in the air as a light, "**N
    aircraft in the air.**" and four tiles: **flights today**, **departing in the next hour**, **aircraft on N routes**
    and the **average load, last 7 days**. It moves on each minute and turns slowly (not if your device asks for less
    motion); drag it to turn it. The planning library works out the aircraft in the air and the flights from each
    leg's own times, so near midnight UTC the counts can differ slightly from the old planner's, which reads each
    route's local days.
  - **The key figures** (aircraft, routes flying, flights a day, seats a day, the average economy load over 7 days) are
    in the page but hidden, as on the old Home, where the globe's tiles stand in for them. The average load is the
    database's: every flight the loads pages captured in the last 7 days, averaged, as the old Home works it out (or,
    with none captured, every flight the load reports cover).
  - **The network right now:** the map of every route in its airline's colour (wider the more flights a day), our bases
    and the airports they reach, with night shaded as it is now. **+**, **−** and **⟲** zoom; the wheel zooms where it
    points, and a zoomed map drags. An airline's button shows that airline, centred on its busiest base, with its routes
    coloured by economy load over 7 days (green 95%+, amber 85–95, orange 70–85, red under 70, grey without loads).
    **Planned** adds, dashed, the routes on the plan cards of aircraft not yet in service. Hover over a line or a dot to
    name it; a route opens its pop-up (its distance, demand, flights a day, loads, the load pattern's signal and each
    frequency, with **Open in Routes**), a planned route its aircraft in Aircraft on order.
  - **Aircraft on order:** each aircraft not yet in service, by airline: its type, when it arrives (UTC), its base and
    plan. **File into planner** appears once one has arrived with a plan card, and files it on Tails (below).
  - **Needs attention:** grouped as on the old Home, each item linking to where it's fixed; an item about one aircraft
    (its maintenance, turns or positions) opens its pop-up, as on the old Home. **×** dismisses an item and
    **show again** brings every dismissed item back; a dismissal shows in both planners. Airports are flagged from
    80% of the game's departure cap (a setting, *airport_cap_warning_pct*). Routes to fix come from the captured profit;
    with none captured, from the load patterns, as on the old Home. The interline line isn't there yet: its list of
    countries is still only in the old planner, and comes with the Interline screen.
  - **Coming up** (the next 14 days) and the **To-do** board, as on the old Home. One-week checks fall due a week after
    an aircraft's latest launch or schedule change (a setting, *aircraft_check_after_days*). Tick a to-do when it's done;
    add one with its steps, one a line; **×** deletes one after asking you in the page.
  - **The airline cards** at the foot: each airline's logo, whether it's flying, its hubs and focus cities (filled once a
    route flies from them), aircraft, routes, flights and block hours a day, its lowest maintenance, short and tight
    turns (or **clean**), with its home city's photo behind when the website has one. **Open fleet ›** opens the
    airline on Tails.
- **Routes in the new planner** looks and works as the old Routes:
  - **The list:** one airline at a time (its buttons at the top); search by destination; **Active only**; sort by
    stars, distance up or down, destination or load; **km from** and **km to**; and the chips for **Bases** (with a
    focus city, **All routes** or **Trunks only**, its routes to the airline's hubs), **Demand** and **Markets**. The
    filters are in the address, so a link (or the back button) brings them back. Each row has its stars, market,
    distance, its load over 7 days, round trips a day (green when every frequency fits the banks), aircraft and
    numbers. **Add route** adds one by its destination code (city and distance from the airport list, or typed);
    **Remove N unflown routes shown** removes those after asking in the page. Removed routes can be restored from
    Reference.
  - **A route** (its own address, such as /planner/next/routes/PA/JFK-ORD): stars, airline, market, distance and the two
    UTC offsets; the estimated block on the market's aircraft, its plan and prices, the service profile and the hub's
    banks; **edit route** (stars, market, distance, city, the offsets) and **remove route** (only once it has no
    frequencies, after asking in the page). Not flown yet, it shows the next free flight numbers; flown, its loads over
    7 days.
  - **Each frequency:** the outbound and the return with their times (local, or UTC as the header says, the other shown
    small), the block time (typed, or **est** from the planning library's estimate), **+1** where a time falls on a later
    day, and each flight's load. Then every check: night bans, a number used twice, the bank fit at both ends, the turn
    at the destination, and (new, the old Routes didn't show them) the aircraft's position and the second-daily gap;
    then the connections at both ends, in all six airlines' flights. Type days (such as 135) and times in local time at
    each end; each box saves when you leave it. **Add frequency** takes the next free numbers; **Remove** asks in the
    page first.
  - **Changing an offset** keeps the local times, as the old planner does: the page first lists every flight whose UTC
    time moves and asks. Empty the box to go back to the game's offset.
  - **Estimates:** where an arrival isn't typed, the planning library's estimate (25 minutes plus the distance at the
    type's speed, manual §4) is used, so it can differ by a few minutes from the old planner's, which it fitted to the
    times typed in.
- **Tails in the new planner** looks and works as the old Tails:
  - **The list:** one airline at a time; filters for **Base**, **Type** and **Flying**, **No flights** or **Needs a
    look** (a short turn, a leg starting where the aircraft isn't, or maintenance under 105%), kept in the address. Each
    aircraft's type, cabin, base, **Legs/wk**, **Block h/day**, **Maint.** (hover or tap for the hours) and **Routes**;
    a red dot marks a short turn or a leg starting elsewhere. **Add a tail** adds one by hand at the end of the list;
    **remove** retires one (never deleted, so its history stays) after asking in the page, and not while it flies a
    route. On a phone the list is a column of cards.
  - **An aircraft** (its own address, such as /planner/next/tails/N001AW): its type, cabin, legs a week, block hours a
    day, gap target, minimum turn, gaps at the target this week and maintenance; the fields that change it
    (registration, type, base, cabin, the maintenance gap, notes; each saves when you leave it), **Delete aircraft…**
    (its round trips go and it's retired, after asking in the page); every issue (as the old aircraft pop-up lists them:
    under the block-hours target, short and tight turns, maintenance, legs starting elsewhere, the longest gap, rotations
    off wave), or **schedule clean**; its week as bars in its base's local time, red where a turn is short or the next
    leg starts elsewhere; and its legs by flight number with days, times, duration, the ground time to the next and the
    turn or gap. The types offered are the ones the airline may have (Reference), and the cabins its kind of airline's.
  - **Deliveries:** every aircraft with a delivery, for the airline and the base and type picked above: **Open** (on
    order, or arrived and not scheduled), **On order**, **Arrived** or **Flying**, each with its date and time (UTC),
    base, plan and status; **card** shows its plan card (title, base, each flight's number, route, times, block and
    service).
  - **File into planner** (on an arrived aircraft's plan card, or from Home): the planner reads the airline's schedule
    from the game and compares each flight on the card. When every one is the same, it files at once. Otherwise it shows
    each flight, the card's times and the game's, **same**, **different** or **not in the game**, and you file with
    **the game's times** (the card takes them too) or **the plan card's times**. Filing puts the aircraft in service,
    logs its first cabin fit (its order's cabin, or the one an order of its type comes with, from the database), and
    adds each flight with its return as a round trip, launched today. It then opens the aircraft.
  - **The aircraft pop-up** (from Home's needs attention): its base, block hours a day, legs a week, maintenance, the
    one-week check, every issue and its flights, with **Mark checked** and **Open in Tails**.
  - The block-hours target (10 h a day) is a setting, *aircraft_block_target_h*: a flag on the screen, not a floor.
- **Saving:** each change is saved on its own. If someone changed the same thing since you opened it, nothing in that
  change is saved; the screen shows what's there now and says what changed.
- Every screen works at phone width, with no sideways scrolling. Previews save nothing, as here.

## Home: Overview
*The whole network at a glance.*
- **Key figures:** aircraft, routes flying, flights a day, seats a day, and the **average economy load** over the last
  7 days of captures.
- **The network right now:** a live map of every route and where each aircraft is, by airline, as of the current time
  in UTC.
- **Aircraft on order:** aircraft not yet delivered and when each arrives. **File into planner** appears once one has
  arrived.
- **Needs attention:** things to act on, grouped by kind:
  - the capture and the backup (no good copy for 30 hours, or the last run failed);
  - **Nightly jobs** (#13): the daily snapshot more than 30 hours old, the 10:00 UTC job not run for 30 hours (the
    database's scheduler may have stopped), the month's archive not run by the 3rd, or any job whose last run failed,
    with its note;
  - to-dos and one-week checks due;
  - maintenance, turns and positions, night bans;
  - flight numbers used twice, airport departure caps, routes to fix;
  - when an airline can order, monthly checks, interline.

  Dismiss an item with **×**, and bring dismissed items back with **show again**. Fare-plan items aren't listed here;
  they're reviewed weekly.
- **Coming up:** the next 14 days, meaning one-week checks and to-dos.
- **To-do:** the board where Claude puts anything you need to do or check (with steps). Tick an item when it's done,
  or tell Claude and it ticks it.

## Routes
*Every route in the network. Pick one to schedule its flights.*
- Choose an airline, then filter by **base**, **demand** (★ to ★★★★★, from the route research) and **market** (for
  example Transatlantic – dense).
- Sort by stars, distance, destination or load.
- Open a route to set its frequencies, times and aircraft. **Add route** adds one that isn't in the research.
- **Remove unflown routes** tidies the list. Removed routes can be restored from Reference.

## Tails
*Every aircraft: what it flies each week and how hard it works.*
- **Legs/wk:** flights a week.
- **Block h/day:** hours flown a day.
- **Maint.:** usable ground time against the maintenance time the aircraft needs. 100% or more is enough; hover over
  it for the hours.
- **Routes:** how many routes it flies.
- Filter by base, type, and **Flying**, **No flights** or **Needs a look**. **Add a tail** adds an aircraft by hand.
- Aircraft on order and filing them are on Home (**Aircraft on order**); in the new planner they're on Tails too.

## Hubs
*Each base's day: banks, arrivals and departures, and which flights connect.*
- Pick a hub and a day. The grid shows arrivals and departures hour by hour, and the list below shows each flight.
- **Connections at [hub]:** flights flying now, across all six airlines, that connect at that airport. That means a
  gap between the airport's minimum connection time and 8 hours. It also counts how many city pairs that links.

## Check
*Last night's capture, aircraft checks, growth signals, Game check and the daily load report.*
- **Capture:** what the capture collected for each airline, and when (UTC). If an airline is missing, press the capture
  again.
- **Growth:** where each airline should grow next.
  - **Main hubs towards 750 departures a week:** hubs first. Each main hub reaches 750 before another opens, unless the
    new one is contested.
  - **Next move for each airline:** each airline rotates its orders, big market → frequency → smaller feeder.
  - **Ready for another flight:** routes that sold out on most departures in the last 7 days and make more a flight
    than the airline's middle route.
  - **Raise fares:** sold out, but earning less a flight than the middle route.
  - **Fix or reduce:** losing money, economy under 75%, or a thin margin.
  - **Aircraft losing money after their lease.**
  - **Order queues:** how long each delivery line has before it runs dry.
  - **Hub readiness:** how many cities feed each bank.
- **Aircraft checks:** one check a week after an aircraft is scheduled. You do these in the game, and only you mark
  them checked.
- **Cabins:** each aircraft's cabin against the usual cabin of the markets it flies. A refit costs about 0.2M.
- **Game check:** compares the planner with each airline's live schedule in the game, through the schedule check.
- **Daily load report:** every flight flown, from the capture, with loads by class.

## Review
*How the group and each airline are doing: cash, the 14-day forecast, and profit by route and by aircraft.*
- **One card per airline:**
  - **profit a day** over the last 7 days;
  - **per aircraft** (profit a day ÷ aircraft flying);
  - **return on fleet** (a week's profit ÷ the value of the aircraft flying);
  - **an aircraft pays back in** (average aircraft price ÷ profit per aircraft a day);
  - **funds a new aircraft every** (average aircraft price ÷ the airline's profit a day);
  - fleet, flights a day, average load;
  - **next order**, from the cash forecast.
- **The group today:** from last night's capture. Flight profit is before leases. Leases and the week-end closing are
  this week's scheduled payments, per day.

Open an airline for its own page:
- **[Airline] profit:** profit for each day between captures, worked out as the change in cash plus that day's order
  payments. Cash moves on payment days, so read the average.
- **Cash, next 14 days:** today's captured cash, plus flight profit from the last day's bank statement, minus every
  scheduled lease and week-end closing. An order is **safe** when 0.5M stays in hand at the lowest point afterwards,
  counting the new aircraft's own weekly lease from 7 days after it arrives. This is how ordering is decided (manual
  §3).
- **Route profit:** each captured flight's income minus its flight costs (fuel, handling, on-board, landing and
  air-traffic fees, maintenance), from the bank statement.
  - Pick the last day, 3 days or 7 days.
  - Each route is marked **add a flight**, **raise fares** or **hold**.
- **Aircraft:** each aircraft's flight profit a day, less its lease.
- **Fare changes:** fare changes spotted in the captures, with the load the day before and after.
- **Fare plan:** the fare changes to make in the game. The next capture spots each one. It's reviewed together on
  Saturdays.
- **Manual entry:** only if a night's capture failed. Type the cash, fixed costs and loads by hand.
  Loads typed or pasted here change only the days and flights you enter; captured days stay as they are.

## Interline
*Which foreign countries each airline flies into, and whether it has an interline agreement there.*
- **Interline agreements:** each airline–country pair, and whether its agreement is still to sign, signed or declined.
- **The interline countries:** the countries with a real domestic network or a regional gateway, and partners that
  exist in Gander. Each airline signs its own partner, and the group's airlines already interline with each other.

## Photos
*Airline logos and destination photos for the public website.*
- Upload a logo or a destination photo (with its credit). It goes live on the website straight away, resized for the
  web first.
- **Remove** goes back to the in-game logo or the plain card.

## Reference
*Banks, aircraft, configs, markets and time zones.*
- **Hubs, focus cities and banks:** a hub runs banks and connections. A focus city is a base that serves its own
  market and feeds a hub.
- **Constants, Aircraft, Configs:** block-time estimates (learned from the times typed in), and seats per cabin
  config.
- **Market defaults, Service profiles:** what a new frequency starts with.
- **Removed routes:** restore any route removed from Routes.
- **Night bans:** airports that close overnight. Flights inside a ban are flagged on their route.
- **Game schedules:** each airline's public schedule page, used by Check → Game check.
- **Time zones:** the game runs standard time all year. Override an airport only if the game disagrees.
- **Storage:** whether saving to the database and to this device is working.
- **Data:** export the whole planner (JSON) or its flights (CSV), and import or clear it. Clearing is for emergencies
  only; the nightly backup is the real safety net.

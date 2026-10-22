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
- **Every screen has its own address** (/planner/today, /planner/tails/N001AW, /planner/performance/VS …), so a link or
  the back button reopens it. Links from the build (/planner/next/…) still work: they move to the same address under
  /planner/.
- **The screens are grouped by when they're used** (since 20 Oct, spec
  docs/specs/2026-10-20-today-performance-systems.md): **Today** answers "what do I do now?", **Performance** "how are
  we doing, and why?", **Competition** (since 21 Oct) "who are we up against, and where do we open next?", and
  **Systems** holds the plumbing. Check, Review and Hubs went: their boards are on those three,
  and their old addresses lead there (/planner/check to Today, a load report's day to Performance's Flights by day;
  /planner/review/VS to /planner/performance/VS; /planner/hubs to Performance). Each screen answers its question at the
  top; colour is only on what needs doing, red and amber; nothing that's fine gets a pill.

## Signing in and the header
- **Signing in:** the same email and password as before. An account that isn't staff is signed out with **This account
  doesn't have access to the planner.**
- **The top bar** (since 22 Oct, the website's look): one slim bar on night with **equinox. planner**, the screens
  **Home**, **Today**, **Routes**, **Tails**, **Performance** and **Competition**, and **More** (a menu with
  **Interline**, **Photos**, **Reference** and **Systems**); the **search** box; the **clock button**, showing UTC now;
  and the round **account button**. Under the bar, the website's twilight line. On a narrow window or a phone the
  screens go into the menu button at the left, all ten in one list; nothing scrolls sideways.
  - **The clock button** opens the **game clocks**: one per time zone of our bases, west to east, with the time there,
    a dot for day or night and the bases' codes. They're no longer under the bar on every screen, and the hidden band of
    the UTC day went with them.
  - **The account button** opens the save state, **Times in Local** / **Times in UTC** (it starts as the planner's
    setting and remembers your choice on this device), **Website** (the public site) and **Sign out**. Its dot shows the
    save state: green saved, amber saving or preview, red not saved.
- **Each screen's head:** a small uppercase line saying where you are, the screen's title in large type on the light
  ground, and its one-line description. (Each screen opened with a dark banner until 22 Oct.) Home keeps its globe.
- **The save state:** **saved**, **saving**, **not saved · retry** (in the account menu: tap it to send again; nothing is kept on the device,
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
*The whole network at a glance.* It looks and works as the old Home, without the boards that moved to Today on 20 Oct
(needs attention, coming up and the to-do board), so each thing lives in one place.
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
  A station (since 22 Oct) is drawn as an ordinary airport dot, never a hub ring.
- **Aircraft on order:** each aircraft not yet in service, by airline: its type, when it arrives (UTC), its base and
  plan. One that has arrived with a plan card says **to file on Today**: its **File into planner** is on Today.
- **The airline cards** at the foot: each airline's logo, whether it's flying, its hubs and focus cities (filled once a
  route flies from them; never its stations), aircraft, routes, flights and block hours a day, its lowest maintenance, short and tight
  turns (or **clean**), with its home city's photo behind when the website has one (the city is the airline's own,
  *airlines.photo_city*). **Open fleet ›** opens the airline on Tails.

## Today
*What do I do now?* The evening after a capture, or whenever one lands (since 20 Oct). Laid out since 22 Oct as the
approved mockup (spec docs/specs/2026-10-22-planner-look-today.md): the answer, the things waiting as cards, the orders
as one table, then counts you tap for detail. Nothing folds on arrival.
- **The answer is the title:** **All clear** when nothing is waiting (no airline can order, nothing to file, nothing in
  needs attention, no Game check differences), or how many things are waiting ("2 things waiting"), with what under it
  ("Pan Am can order · 2 aircraft to file · 5 items in needs attention"). Game check counts only once you've pressed
  **Check against the game**.
- **The capture, as a pill beside the title** (below it on a phone; from *capture_status()*): "**All six airlines
  captured, all good, 17:08 UTC**", or what's missing (an airline not captured for over a day; red after 48 hours),
  short (amber) or broken (red), with what came in ("short: Kingfisher (loads 12 of 78 flights)"). **Systems ›** has
  each page.
- **The things waiting, as big cards** (two a row; one on a phone), each with a small coloured kind line, a heading in
  the item's own words, a line of detail and its button:
  - **Order now:** each airline that can order now ("Virgin can safely order: A321neo, E195"), with **Cash, next 14
    days**. The first is the one dark card with the amber button: the thing to do first;
  - **Fleet · maintenance** (since 22 Oct): when the game's fleet pages show an aircraft's maintenance under the limit
    (100%, *maintenance_min_pct*), the Fleet group's card comes next, the most urgent kind after order now ("N003AW
    (JFK): maintenance 0.0%, condition 83%"); the dark card when nothing can order;
  - **Due** a day (or **Overdue**): each to-do due today or before, with **Open the to-do**;
  - **To file:** each aircraft that has arrived with a plan card, with **File into planner**;
  - **Needs attention:** the rest, a card per kind: one item says its words and opens where it's fixed; more say the
    first item and how many more, and **See all** opens that kind's tile below. Game check's differences, once it has
    run, have a card that goes to Game check.

  With nothing waiting, one card says all clear.
- **Orders, as one table:** a row per airline (its colour and name, **Can order now** in amber or **Safe from** a day,
  **Needs a capture** or **Not within 14 days**, from the cash forecast: *cash_forecast()*, through *airline_cards()*),
  a column per delivery line (A320 family, E195, A350; "—" where the airline has no such line). Each cell: when the
  line's first type is safe to order (**Safe now** as an amber pill, **Safe from** a day, or **Not safe within 14
  days**: the earliest safe day of the line's types, by the same family the order queues use), how many are on order
  and when it runs dry (UTC), with how soon in amber when that's within *order_queue_warn_h* (48 hours), or **Nothing
  on order**. A line with no type in the forecast (no capture yet) says only what's on order. The row of an airline
  that can order now is tinted. Each row ends with **Cash, next 14 days ›** (the airline on Performance) and **all
  safe types**, folded, listing every safe type by when: **now** first, then each day from which more are safe, each
  short name once ("Safe now: A321neo, E195 · from Thu, Oct 22: XLR, A320neo"). On a phone each airline is one compact
  row with its order status on the right; tap it to see its lines. (Check → Growth's can order and order queues until
  20 Oct.)
- **Counts, then detail:** a tile for **Aircraft to file** and one for each kind in needs attention (routes to fix,
  rival moves and the rest, the most serious first), three a row (two on a phone): the number, the kind and how serious
  its items are ("1 urgent · 2 to look at"). Tap a tile to open its list right below the tiles; tap it again to close
  it. Home's **to file on Today** opens Aircraft to file.
- **Aircraft to file** (its tile's list): each aircraft that has arrived in the game with a plan card, with **File into
  planner**, which files it on Tails (below). Home's Aircraft on order had the button until 20 Oct.
- **Needs attention** (moved whole from Home on 20 Oct; its tiles' lists): things to act on, by kind as on the old
  Home, each item linking to where it's fixed; an item about one aircraft (its maintenance, turns or positions) opens its pop-up.
  - the capture (an airline not captured for 26 hours, red at 48) and the backup (no good copy for 30 hours, or the
    last run failed), linking to Systems;
  - **a capture page that came in short or broken** (#21), the same night: "Kingfisher's capture came in short: loads
    12 of 78 flights", in the Capture group, linking to Systems. Capture that airline again; the line goes once its
    pages are all good;
  - **Nightly jobs** (#13): the daily snapshot more than 30 hours old, the 10:00 UTC job not run for 30 hours (the
    database's scheduler may have stopped), the month's archive not run by the 3rd, or any job whose last run failed,
    with its note;
  - to-dos due or overdue (the one-week aircraft checks went on 22 Oct: manual §1 has none since 15 Oct);
  - maintenance, turns and positions, night bans, flight numbers used twice;
  - airports from 80% of the game's departure cap (the setting *airport_cap_warning_pct*);
  - **Interline:** how many airline–country pairs on Interline have no agreement yet (not signed, declined or without
    a partner in the game), from the same rows and rules as Interline (the setting *interline_rules*);
  - routes to fix, from the captured profit (with none captured, from the load patterns, as on the old Home), linking
    to the route's page on Performance (since 22 Oct; the load patterns' to the route on Routes);
  - when an airline can safely order, linking to its Performance page;
  - **Rival moves** (since 21 Oct): each rival that started on, or added a daily flight or more to, one of our city
    pairs in the latest world scan, against the scan before it: "Air China started on PVG–CAN, 14 a week", linking to
    its airline's Competition page. They aren't fare moves, so they're listed here; the route's fares hold for a week
    on their own (Performance's fare ladder).
  - **Cabin charges** (since 22 Oct): one amber item when a cabin charge on the game's bank statement doesn't match the
    first fit filing logged ("2 cabin charges don't match what we logged"), linking to Systems' Cabin charges board,
    which opens on arrival. Dismissed, it comes back when a new one appears.
  - **Fleet** (since 22 Oct): what the evening capture's fleet pages showed on the latest night (*fleet_checks()*),
    one item per aircraft, worst first: the game's maintenance under the limit, with its condition, and no pilots (red),
    then seats that don't match the aircraft's cabin in the planner or no cabin in the planner, an aircraft in the game
    the planner doesn't have, and an aircraft in service in the planner missing from the game's fleet pages (listed only
    when every fleet page of that airline came in ok that night; amber). An aircraft the planner has opens its pop-up;
    one it doesn't opens Systems' Fleet board. Dismissed, a problem comes back the next night while it lasts.

  **×** dismisses an item and **show again** (under the tiles) brings every dismissed item back. Fare-plan items aren't listed here;
  they're reviewed weekly. An aircraft's pop-up keeps its address (/planner/today?aircraft=N001AW).
- **Game check** (Check's until 20 Oct): **Check against the game** reads each airline's live schedule from the game.
  Each airline's line says how many flights are in each and the differences. **Review** lists them, with **Use the
  game's times** where it's only a time or a day change, **Fix all from the game**, and the game's flights the planner
  hasn't got, each with an aircraft and **Add to planner** (for a new aircraft, pick **new tail…** and type its
  registration in the box). After a fix or an add the differences are worked out again from the planner as it is now.
- **To-do:** the board where Claude puts anything you need to do or check (with steps). Tick an item when it's done, or
  tell Claude and it ticks it; add one with its steps, one a line; **×** deletes one after asking you in the page.
- **Coming up:** the to-dos due in the next 14 days, with **All** and **To-dos** buttons.
- **An old address:** /planner/check opens Today; /planner/check?day=2026-10-12 (the old daily load report on a day)
  opens Performance's Flights by day on that day.

## Routes
*Every route in the network. Pick one to schedule its flights.*
- **The layout** (since 22 Oct, spec `docs/specs/2026-10-22-planner-look-routes.md`): the title with the airline switch
  beside it (each airline's colour dot and name; under 1100 px wide it sits under the title) and **Add route**; then the
  list (about 440 px) beside the open route, each scrolling inside its own panel, so the page itself stays the height
  of the window. The open route is marked in the list with a violet bar. On a phone (under 760 px) the list fills the
  screen; tapping a route opens it full screen, with **← Routes** at the top (the browser's back button does the same).
- **The list:** one airline at a time. One row of tools on top: **Find a destination** (search), the base picker
  (**From JFK**, each of the airline's bases, then its stations marked **(station)**, such as **From LKO (station)**, or
  **All bases**) and **Filters**, which opens a panel with everything else:
  **Demand** (★ to ★★★★★, from the route research), **Markets** (for example Transatlantic – dense), with a focus city
  picked **All routes** or **Trunks only** (its routes to the airline's hubs), **km from** and **km to**, **Active only**,
  the sort (stars, distance up or down, destination or load) and **Remove N unflown routes shown** (it asks in the page
  first). The button shows how many of these are set. Under the tools, the count: "32 flying · 243 to open". The
  filters are in the address, so a link (or the back button) brings them back. Each row has the destination city and
  its code (the pair, such as ORD–MIA, when the row leaves another base), its distance and round trips a day (red when a
  frequency is off the banks) or "not flown", the **trunk** tag where it is one (never on a pair with a station end), and on the right its load over 7 days.
  **Add route** adds one by its destination code (city and distance from the airport list, or typed), from any of the
  airline's bases or stations. Removed routes can be restored from Reference.
- **Stations** (since 22 Oct, manual §2): airports the airline flies point-to-point routes from without making them a
  base (Lucknow for Lucknow–Patna). A station route shows "station · no banks" where a hub's route shows its banks, its
  frequencies are never off wave, and its flight numbers come from the airline's one station pool, 3 digits from
  *station_flight_no_from* (100) to *station_flight_no_to* (999), above the highest any of its stations uses; when the
  pool is full the route says "station numbers 100–999 all used" and a new frequency gets no numbers.
- **A route** (its own address, such as /planner/routes/PA/JFK-ORD): its name, such as "New York → Atlanta", with its
  codes; a muted line with the airline, distance, stars and market; then its figures as big numbers: the estimated block
  on the airline's most-flown type, round trips a day (and how many frequencies) and the load over 7 days; then the
  **layout** the route calls for (its market's, or its own cabin choice, which wins: manual §5; since 21 Oct, in place of
  the market's aircraft, plan and prices), the service profile, the hub's banks ("station · no banks" from a station) and
  the two UTC offsets; **edit route**
  (stars, market, distance, city, the offsets) and **remove route** (only once it has no frequencies, after asking in
  the page). Not flown yet, it shows the next free flight numbers. Flown, its frequencies, **Add frequency**, its loads
  over 7 days and **The route's story ›**, which opens its route page on Performance (since 22 Oct).
- **Each frequency:** its aircraft, named by tail and the base it flies from ("N003AW (JFK)"), its flight numbers and
  days; the outbound and the return with their times (local, or UTC as the account menu's Local / UTC says, the other shown
  small), the block time (typed, or **est** from the planning library's estimate), **+1** where a time falls on a later
  day, and each flight's load. Then every check: night bans, a number used twice, the bank fit at both ends, the turn at
  the destination, the aircraft's position and the second-daily gap (the last two new: the old Routes didn't show
  them); then the connections at both ends, in all six airlines' flights. Type days (such as 135) and times in local
  time at each end; each box saves when you leave it. **Add frequency** takes the next free numbers; **Remove** asks in
  the page first. The aircraft's registration beside its box (**N001AW ›**) opens its pop-up, as Today's needs
  attention does, with the address (?aircraft=N001AW) so a link reopens it.
- **Changing an offset** keeps the local times, as the old planner did: the page first lists every flight whose UTC time
  moves and asks. Empty the box to go back to the game's offset.
- **Estimates:** where an arrival isn't typed, the planning library's estimate (25 minutes plus the distance at the
  type's speed, manual §4) is used, so it can differ by a few minutes from the old planner's, which it fitted to the
  times typed in. A frequency with no aircraft is estimated on the airline's most-flown type (its market's aircraft
  until 21 Oct). A new frequency's price is the airline's launch fare (*fare_launch_pct*: 100%, Ryanair 85%).

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
  base, plan and status; **card** opens its plan card in its own window, the rest of the screen dimmed (title, base,
  its cabin, each flight's number, route, times, block and service; × or Escape closes it). An airport where the
  airline has no station yet (none of its flights or bases touch it) is highlighted on the card. The card's cabin is chosen with its routes: until the aircraft is filed, the card's **Cabin** box sets
  it, and the card says **no cabin chosen** while neither the card nor the order names one. Beside the box (since
  21 Oct, manual §5) the card says which cabin the rule calls for, **suggested: 321-LP**, with the reason ("JFK–LHR is
  72% of block time: Leisure Plus", or "no route over 65%: the most seats"; Ryanair Standard only), and **Use the
  suggestion** sets it in one tap; a cabin that differs from the suggestion shows in amber. Since 21 Oct (manual §5)
  the card's **Fare level** column gives the fare level of each route it flies, once per route on its first leg, from
  the fare ladder: "economy +10%, business +5% of the default price" for a route the airline flies (this week's new
  level once the move is on the fare plan), "launch (+0% of the default price)" for one it doesn't yet (Ryanair
  −15%). In the game, set each new flight's fare to it (Ticket price adjustment, default price), or leave it to the
  fares userscript's next run, which sets back a route whose fares are off its level. **remove** takes an aircraft off the list of deliveries at once: one not yet in service, with nothing that
  points at it, goes; one that has flown or been paid for is retired; one in service just leaves the list.
- **File into planner** (on an arrived aircraft's plan card, or from Today's Aircraft to file): the planner reads the
  airline's schedule from the game and compares each flight on the card. When every one is the same, it files at once.
  Otherwise it shows each flight, the card's times and the game's, **same**, **different** or **not in the game**, and you file with **the
  game's times** (the card takes them too) or **the plan card's times**. Filing puts the aircraft in service, fits its
  cabin and logs the first fit at that cabin's price: the plan card's cabin, else the order's. With neither, it sets no
  cabin, logs nothing and says so (it never takes the type's default, since 18 Oct). It adds each flight with its return
  as a round trip, launched today, and then opens the aircraft.
- **The aircraft pop-up** (from Today's needs attention or a frequency's aircraft on Routes): its base, block hours a
  day, legs a week, maintenance, every issue and its flights, with **Open in Tails**. Since 22 Oct **In the game**
  beside the maintenance: the game's own maintenance and condition from the latest night's fleet pages ("103.8%
  maintenance · 83% condition · 22 Oct", red under the limit), so the planner's figure can be compared with the game's.
- The block-hours target (10 h a day) is a setting, *aircraft_block_target_h*: a flag on the screen, not a floor.
- **The plan card's service check** (14 Oct): a flight on a plan card whose service code isn't the one its route's
  distance calls for shows it beside the code, in red: **S1, wants S3**, or **none, wants S2** when it has no code.
  Ryanair takes its own **R** on every route. The distance is the route's (the airline's own, either way round, with any
  override), as filing takes it, else the great circle.

## Performance
*How are we doing, and why?* (since 20 Oct: Review's screen, with Check's growth boards and daily load report). Every
money figure is the database's. Since 22 Oct (spec docs/specs/2026-10-22-planner-look-performance.md) it's laid out
as the new Today, Routes and Systems: the group page's title is the answer, how many airlines are in profit ("Six
airlines, all in profit", or "5 of 6 airlines in profit"; never a group total, manual §1); then the scorecards, the
fare ladder's cards, and **The details**: the other boards as rows that open, each with a one-line note and its count or
state, all closed on arrival (Flights by day open when the address names a day). **Collapse all** and **Expand all**
fold them, and a row's title opens or closes it.
- **The address:** /planner/performance is the group; /planner/performance/VS one airline's page;
  /planner/performance/PA/JFK-ORD a route's page (since 22 Oct, below; until then that address opened the airline with
  the route profit table filtered to the route, which its search box still does). Old Review addresses
  (/planner/review/VS) lead here.
- **The scorecards, one per airline:** Review's cards, with every figure: **profit a day** over the last 7 days, with
  its sparkline; **per aircraft** (profit a day ÷ aircraft flying); **return on fleet** (a week's profit ÷ the value of
  the aircraft flying); **an aircraft pays back in** (average aircraft price ÷ profit per aircraft a day); **funds a new
  aircraft every** (average aircraft price ÷ the airline's profit a day); fleet, flights a day, average load; **next
  order**, from the cash forecast (amber when it can order now). Beside the fleet, flights a day and average load, the
  change against the same day last week from the daily history (*airline_days*), with an arrow: the latest day of the
  history against that day a week before (fleet: aircraft flying; flights a day: the schedule's departures a week ÷ 7;
  average load: the economy load averaged over the 7 days to each day). One change a line: with the arrows, the card's
  own "+N this week" (counted from the schedule's flights that day, so it can differ) isn't shown. An airline with no
  day a week ago says so, shows no arrow and keeps the card's "+N this week". The money figures have no such change: the
  history keeps no profit a day, and their trend is the sparkline. Tap a scorecard to open the airline. The card's head
  is the name with the sparkline and the big profit figure; its rows are two columns (the label, then the value with
  its change); **Next order** is its footer, with its pill.
- **The fare ladder** (since 21 Oct, manual §5): this Saturday's fare moves, one section per airline. Each cabin of
  each route has a **level**, its fare as a % of the game's default price (the latest the fare plan recorded, else the
  launch level: 100%, Ryanair 85%). From the week's captured flights in that cabin it goes **up** 5 points when every
  flight sold out (at least 5 departures), **holds** at 90–99%, and goes **down** 5 points under 90%, then holds 2
  weeks. It holds while a route is under 7 days old, and (since 21 Oct) for 7 days after a route gains a flight ("a
  flight added on 2 Nov: judged at its new size from 9 Nov"; the setting *fare_ladder_capacity_hold_days*), never goes
  more than 20 points above launch for now, and never under launch (nor under the 60% floor where another player flies
  the pair). Each airline has a card (two a row, one on a phone): its moves as three counts (up, hold, down; the down
  count amber when there is one), how many changes to make in the game ("24 changes in the game": the set-back changes
  and the moves), **Put on the fare plan (n)** and **See the changes**, which opens the long lists in the row under the
  card (**Hide the changes** closes them):
  - since 21 Oct, first, **the routes off their level** ("3 routes off their level"), when there are any: a route
    whose captured fares don't match its level (any flight of its latest captured day more than a point off, against
    the route's fare on 21 Oct, when every route was at its launch level) gets a change each way that sets it back to
    its level, with why ("captured fare at 100%, level 110%") and **copy**. Not for a route on the fare plan this week, a
    new route, or one not captured since its newest flight launched. They need no fare plan row: the fares userscript
    makes them on its next run, and the index matching again is the proof;
  - **the game actions**, numbered, each with **copy**: in the game, **Ticket price adjustment** with the calculation
    baseline **default price** (each action sets the level itself), **route by route only**, never a whole base, so a
    route under 7 days old is never touched (since 21 Oct). Each route whose level changes has two actions, From the hub
    to the destination and back (the game changes each direction on its own), and each names the classes to tick:
    "economy and business" when both cabins move to the same level, otherwise one action each way for each cabin that
    moves, economy first. A route that holds (held, new, capped) has none. The first 10 show, with **show all N** for
    the rest;
  - **Put on the fare plan:** one tap writes a fare plan row for each level that changes, and for a hold that follows a
    step down (so the hold has a record). The button then says **On the fare plan**, with how many the captures show
    in the game; the next capture ticks each off (the Fare plan board on the airline's page);
  - the routes table: route, cabin, level with its steps above launch, the sold-out share, the move (a step down in
    amber) and its reason. **Sort** by the moves (first), route, level or sold-out share. It shows its first 10 rows,
    with **show all N**, as the growth lists do. A level the captured fares don't match shows its fare index beside it
    ("· index 100 · set back" when it's set back).

  **A rival's pause** (since 21 Oct, manual §5): a route whose pair a rival started on, or added a daily flight or more
  to (*competition_threat_min_weekly*, 7), in a world scan of the last 7 days holds, with why: "rival Air China started
  here on 22 Oct: paused until 29 Oct". The threats are Competition's. Fare moves never appear on Today or in Needs
  attention (a rival's move does, as itself). In a chat, `select public.fare_ladder(<airline id>);` gives the same list.
- **The group today:** each airline's row, from last night's capture: flight profit a day (before leases), leases and
  the week-end closing a day (this week's scheduled payments), and net. No group totals: each airline is its own
  business (manual §5).
- **Growth signals:** where each airline should grow next, and what to trim (Check → Growth until 20 Oct).
  - **Ready for another flight:** routes that sold out on most departures in the last 7 days and make at least as
    much an aircraft hour as the airline's middle route. An aircraft hour is the flight's block time plus the type's
    turnaround and the 10-minute turn margin: the time the aircraft can't fly anything else. **An aircraft hour** is
    its own column, beside profit a flight.
  - **Raise fares:** sold out, but earning less an aircraft hour than the middle route.
  - **Fix or reduce:** losing money, economy under 75%, or a thin margin. A route isn't listed until it has been
    flying for 7 days (the setting `growth_new_route_days`); a new route that sells out is still listed above.
  - **Aircraft losing money after their lease.**
  - With no profit captured yet: ready for another flight from the load reports, and the routes to reduce from the
    load patterns.

  Each list shows its first 10 rows, in its own order, with **show all N** under it to open the rest in place and
  **show fewer** to close them again (21 Oct: the screen ran to almost 12,000 px with every row). The count stays in
  each list's heading.

  The order rotation's **Next move for each airline** and **Log an order as** went on 20 Oct (spec decision 2): each
  evening's proposal picks by the route we most want to fly (manual §3). The moves logged stay in `growth_log`.
- **Main hubs towards 750 departures a week:** hubs first, one bar per main hub (the plan cards not yet filed
  lighter). Each main hub reaches 750 before another opens, unless the new one is contested. **Hub readiness** is
  folded into each line: open it for how many cities feed each of the airline's banks, flying now and with the plan
  cards, counted by region (*countries.region*).
- **Flights by day** (Check's daily load report, renamed): **‹** and **›** move a day, and the day is in the address
  (/planner/performance?day=2026-10-12). Every departure by airline, with its loads by class from the capture (the last
  9 days), or the day's summary from loads typed by hand.
- **The airline's page:** its name as the title with **‹ All airlines**, the airline switch (one segmented control, as
  on Routes), and its scorecard as four big numbers: profit a day, per aircraft (with when an aircraft pays back),
  return on fleet (with how often it funds a new aircraft) and next order; the fleet, flights a day and average load
  with their changes in a line under them. Then its boards as rows that open, Route profit open on arrival:
  - **[Airline] profit:** profit for each of the last 14 intervals between captures (the change in cash plus that
    day's order payments), with the 7-day average and the table of reported days. Cash moves on payment days, so read
    the average.
  - **Cash, next 14 days:** today's captured cash, plus flight profit from the last day's bank statement, minus every
    scheduled lease and week-end closing. An order is **safe** when 0.5M stays in hand at the lowest point afterwards,
    counting the new aircraft's own weekly lease from 7 days after it arrives. This is how ordering is decided (manual
    §3). The types safe to order are listed by type.
  - **Route profit:** each captured flight's income minus its flight costs (fuel, handling, on-board, landing and
    air-traffic fees, maintenance), from the bank statement, for the last day, 3 days or 7 days, with the filters,
    both charts and the table. **Load against profit** zooms its load axis to the routes shown (from the lowest load,
    rounded down to 5%, never below 40%, to 100%) and labels only the five routes with the most profit a week and the
    ones marked fix, raise fares or add a flight, each beside its dot where it overlaps no other label (else none).
    **An average flight** (its profit and margin, income and costs as two bars, each part's amount) sits beside it at
    the same height, or under it on a narrower screen. Each route is marked **add a flight**, **raise fares** or **hold**. **+ fare plan** plans
    a 5% economy rise (the setting *fare_plan_raise_pct*) from the route's latest captured fare. Since 21 Oct each route
    also has its **fare index** (each flight of the latest captured day against the route's fare on 21 Oct, when every
    route was at its launch level, or its first fare for a route launched later, times the launch level: a route still
    at launch reads 100, Ryanair's 85; a level on the fare ladder the fares don't match is named beside it) and a
    **14-day** sparkline of its loads, a bar a day from the daily history (*route_days*: passengers ÷ seats, both
    directions; lighter under 85%). Each route's name opens its route page (since 22 Oct; Routes until then).
  - **Aircraft:** each one's flight profit a day, less its lease, for the period Route profit picks, with its table.
  - **Fare changes:** the fare changes spotted in the captures, with the load the day before and after.
  - **Fare plan:** the fare changes to make in the game, with **remove**: fare tests, and since 21 Oct the fare ladder's
    moves, each with its move and level ("+5% · up to 105%"). The next capture spots each one: a fare test once half
    its change shows, a ladder's move once its fare moves by the change, within 1%, in its own cabin. It's reviewed
    together on Saturdays.

- **A route's page** (since 22 Oct, spec docs/specs/2026-10-21-route-page.md; /planner/performance/PA/JFK-ORD): its
  story since launch, so a fare move, a new frequency or a rival can be judged by what happened after it. Both
  directions count together; every figure is *route_story()*'s, from the daily history. Read only.
  - **The header:** the route and its city, stars, airline, distance, market and the cabin it calls for (its own, else
    its market's), **launched** (the first frequency's launch day, and how many days ago), departures a week each way,
    the types flying it, and each cabin's fare level with this Saturday's move. **‹ <airline>** goes back to the
    airline's page; **Schedule in Routes** opens the route on Routes.
  - **The last 7 days against the 7 before:** load, passengers, profit, profit an aircraft hour and the economy and
    business fares, each with its arrow (the week ending on the latest captured day; nothing to compare without a week
    before it).
  - **Since launch:** one chart: the economy and business loads a day, the fare level as a dashed step (its scale on the
    right: the launch level, then each level the fare ladder put on the fare plan), and a dot under each day with an
    event. Point at a day for its figures and events. Under 14 days of flights it says so instead.
  - **Profit an aircraft hour:** a bar a week (profit ÷ the block hours flown), up to 13 weeks. The airline's average
    isn't drawn: route profit covers only the last few days.
  - **Events,** newest first, 10 shown with **show all**: launched; a frequency added or removed, an aircraft changed or
    a retime (each save on Routes, Tails or Today's Game check, from the change log; a data fix made by a migration isn't
    one); each fare plan row (a fare test, or the ladder's move, and whether it was dropped); the route's own cabin
    changed; and a rival who started on the pair, or added a daily flight or more, between two world scans
    (*competition_threat_min_weekly*; passenger flights only).
  - **Rivals on the pair:** every other airline flying it either way in the latest scan, with its departures a week and
    its change since the week-before scan; ours and our share, and our share at each scan since launch as a small line.
    "No rival flies this pair" when none does.
  - **Connections:** at each end, how many city pairs its flights connect to and the top 10 with how many times a week,
    onward (from the far end through this one) and feeding (into the far end), from the minimum connection time up to
    8 hours across all our airlines (the plan card's rule).
  - **Links to it:** each route's name in the route profit table, **The route's story ›** on a flown route on Routes,
    Today's routes to fix, and Competition's threats. In a chat, `select public.route_story(<route id>);` gives the
    same.

## Competition
*Who are we up against, and where do we open next?* (Since 21 Oct, spec docs/specs/2026-10-21-competition-analysis.md;
manual §3, market share first.) Every figure is *competition()*'s, from the world scans the evening capture takes
(`scan_every_days`). Rivals are every airline in the scan that isn't one of ours; departures a week count each
flight's days, as *gscan.py* counts them, passenger flights only: freighters (a type ending in F, or ATF, ABX, 74Y,
77X, 76X, or none, the weekly report's rule) are no one's rivals, anywhere here. Read only: nothing here saves.
- **At the top:** the scans' dates ("latest scan 17 Oct, compared with 6 Oct": the latest finished scan, against the
  latest one at least 6 days older, else the oldest there is) and the group line: our airlines' departures a week
  against the world's, our share and its arrow.
- **The group** (/planner/competition): a card per airline with its share across its markets and its arrow, its
  threats in the last 7 days (amber) and its openings with the top 3; tap one to open it. Under them, **Threats**, every
  airline's.
- **An airline** (/planner/competition/MU), with the airlines along the top:
  - **Market share:** a card per market (the airline's routes, flown or not, either direction): our share with its
    arrow against the week-before scan, and the top rivals as a bar (ours dark, the rivals grey) and a list with their
    departures, share and change. Our own departures are the live schedule's; a week before, the scan's.
  - **Threats:** each rival who started on a pair the airline flies (none in the scan before) or added at least 7
    departures a week (*competition_threat_min_weekly*), with the numbers then and now, ours, the day and until when
    the route's fares hold (7 days on), and since 22 Oct a link to the route's page on Performance.
  - **Openings:** the pairs on its list no airline of ours flies, ranked: stars, then the rivals' departures a week on
    the pair, then the shorter distance, then the pair's code. Each with its stars, distance, the rivals and their
    departures, the **variant** from the default line (manual §3: the smallest size the stars allow, bigger only "for
    reach", the cheapest per seat whose range covers it, among the types the airline may buy; since 22 Oct a 1-star
    city on the E195-E2 says "or the E190-E2 if thin" under it: the default line gives the E190-E2 to the thinnest
    1-star city, nothing in our data says how thin a city is, so the evening proposal decides) and **Hubs first**:
    **yes** with why (main hub, contested base or route, main hub at its target, exempt), or **not yet** with the
    reason, listed after the allowed ones. The first 10, with **show all** (the top 50; a chat reads more with
    *competition()*'s *p_limit*). An opening no type the airline may buy reaches is left out and counted. A pair
    another airline of ours has on its list says so ("also on VS's list"): one airline per city pair decides.
  - **In November** (*trunk_month_from* to *trunk_month_to*, 1 to 30 Nov; manual §4) a line over the openings says the
    trunks come first: each pair between two of our bases is marked **trunk**, listed first, shortest first, allowed
    with hubs first suspended ("November trunk"), and never left out for reach (a type the airline can't buy says "not
    on its list"). The list marks trunks; whether each makes sense stays the Scheduling chat's call. Outside those days
    nothing changes.
  - **Rival profiles:** the 10 rivals who fly most of its city pairs: their size and growth since the week-before
    scan, airports, the pairs shared (theirs and ours a week) and their biggest airports.
- **No scan, or one:** with none, the openings rank by stars and distance and only the main hub's are allowed; with
  one, nothing is compared and there are no threats.
- In a chat, `select public.competition(<airline id>);` gives the same, and the airline briefing carries the top 20
  openings and the threats (the evening proposal reads them, manual §3).

## Interline
*Which foreign countries each airline flies into, and whether it has an interline agreement there.*
- **Interline agreements:** one row per airline (its logo on every row) and interline country it flies to or has planned (on a plan card not
  yet filed), with the airports, round trips a day (or **planned**), the status (still to sign, signed or declined),
  the partner in the game, since when and notes. Each saves as you change it (a box when you leave it). The **Airline**
  and **Status** chips filter the rows and are in the address (/planner/interline?airline=KF&status=open). Today's
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
  and feeds a hub. A **station** (since 22 Oct, manual §2) is an airport flown point-to-point from without making it a
  base: the role picker has **Hub**, **Focus city** and **Station** (not for the main hub), and making a base a station
  clears its bank times, the hub it feeds and its block. A station row has no bank or block boxes; its next pair comes
  from the airline's station pool, or says the pool is full.
- **Constants** are rule numbers (the settings, the departures cap in the world's rules): only numbers are taken, and a
  change to one goes in the operating manual too. Since 21 Oct **World scan every** (*scan_every_days*: 1 is every
  evening, 3 about twice a week) is one of them.
- **Aircraft** and **Configs:** block estimates are the block allowance plus the distance at the type's cruise speed
  (manual §4); seats per cabin config.
- **Order cabin** (in Aircraft, since 15 Oct): the layout a new order of each type comes with, picked from the type's
  own layouts (— for none). Tails files an arrived aircraft with it when the order names no cabin of its own, and the
  cash forecast prices an order with it. **An airline's own order cabin**, below the table, is for an airline whose orders
  come with another layout (Ryanair's Standard cabins): pick the airline and type and **Add** (it starts as the type's),
  then pick its layout; **remove** gives it the type's again. Each pick saves as one change.
- **Markets** (Market defaults until 21 Oct): each market's **layout**, the cabin it calls for (Standard, Leisure,
  Leisure Plus or Comfort; manual §5): a plan card takes it where one route of the market flies more than 65% of the
  aircraft's block time, unless the route has its own choice. Pick it from the box; it saves as one change. A market
  keeps nothing else since 21 Oct: its default aircraft, cabin and fares went (a new frequency launches at the airline's
  launch fare).
- **Service profiles:** what a new frequency starts with.
- **Removed routes:** **restore** (or **restore all**) any route removed from Routes.
- **Night bans:** airports that close overnight (find, change, remove, **Add**). Flights inside a ban are flagged on
  their route.
- **Game schedules:** each airline's public schedule page, used by Today → Game check, worked out from its game ID.
- **Time zones:** the game runs standard time all year. Override an airport only if the game disagrees; **Set** lists
  the flights whose UTC time moves and asks first, as Routes does.
- **Storage:** whether saving works, with **Save now**; nothing is kept on the device.
- **Data:** **Export backup (JSON)** (every planner table) and **Export flights (CSV)**, whose last column (since 21 Oct)
  is the layout each flight's route calls for (its own choice, else its market's). Importing a backup and clearing
  everything are gone with the tables (design §14): the nightly backup and the change log are the safety net.

## Systems
*Did everything work?* The plumbing, rarely opened (since 20 Oct: Check's Systems board and Capture, and Review's
Manual entry; Check's Cabins board went on 21 Oct: we don't refit, and the plan card suggests the cabin on Tails;
Cabin charges and Fleet came on 22 Oct, and the Aircraft checks board went that day: manual §1 has no one-week checks). Laid
out since 22 Oct short and answer-first, as Today (spec docs/specs/2026-10-22-planner-look-systems.md):
- **The answer is the title:** **All systems good** when every line of the board is green, else how many need a look
  ("2 need a look"), with how many are red and amber under it. **checked at 04:25 UTC** sits beside it as a small pill.
- **The board's lines as tiles** (three a row, two in a narrow window, one on a phone), red first, then amber, then
  green: each with its mark as a dot and a word (**good**, **check**, **problem**), its name, its words and when.
- **The evening capture as one table:** a row per airline with its mark, when its latest page came, and its verdict
  (**all good**, **short**, **broken**, **not checked**) with what came in short or broken; since 22 Oct its fleet pages
  too ("fleet 3 pages, 21 aircraft", or the fleet page that came in short or broken).
- **The details** under them, as large rows: Capture, Fleet, Cabin charges and Manual entry, each with a one-line note and
  its count or state ("all 6 complete", "27 fits, no problems", "2 to look at"). Tap a
  row to open its board right below it; all start closed, except Cabin charges or Fleet when Today's item sent you
  (#cabin-charges, #fleet). **Expand all** and **Collapse all** open or close every one.

Each button is saved on its own, as one change.
- **Systems** (#23): one look says whether everything worked. One line each with a green, amber or red mark and when:
  - **Evening capture**, one row per airline: when its latest page came, and its pages' verdict (#21): "all good", or
    what came in short or broken ("short loads 12 of 78 flights"). Amber after 26 hours or when a page was short, red
    after 48 hours or when a page was broken. Pages stored before 14 Oct's checks say "not checked".
  - **Daily snapshot:** the latest day in the daily history, taken by the capture (green) or by the 10:00 UTC fallback
    and so incomplete (amber); amber after 30 hours, red after 54 or when its last run failed; amber too when the 10:00
    UTC job hasn't run for 30 hours (the database's scheduler may have stopped).
  - **Nightly backup:** the last good copy (its restore check passed), its size and rows; amber after 30 hours, red after
    54 or when the last run failed.
  - **Monthly archive:** whether it ran this month; amber from the 3rd if it hasn't, red if a table and month failed.
  - **Clean-ups (10:20 UTC):** the last run; amber after 30 hours, red after 54 or when it failed.
  - **World scan:** its age, and that it runs with the evening capture when one is due ("every evening
    (scan_every_days 1)", since 21 Oct; Reference → Constants changes it); amber over 8 days, red over 15, when it
    adds "capture again while it's due, or gscan.py by hand". Since 22 Oct, when a scan stopped part-way (the phone
    closed, the tab went away) and no finished scan came after it, it adds "the scan of 21 Oct stopped after 812 of
    1,040 airlines" (of the finished scan before it) in amber, not red: the next capture scans again. A scan left
    unfinished for over an hour is marked stopped when the next one starts, with a note of how far it got.
  - **Planner build:** when this planner was built and the change it came from. After a merge the time moves within
    minutes; if it doesn't, Cloudflare's build failed (its log is in Cloudflare's dashboard).
  - **Database size, Report PDFs, The website's data:** each against its trigger (350 MB, 50 MB, 500 KB; manual §1),
    amber from 70%, red at the trigger. Supabase's egress and the website's calls a day stay the monthly look by hand.

  Today's capture line and needs attention list the problems; this board is where "all good" shows.
- **Capture:** what the capture collected for each airline, and when (UTC), with **Reload** and the backup's line. If
  an airline is missing, press the capture again. Each page is checked as it arrives (#21): the capture's panel in the
  game ends each airline with "all good" or what came in short or broken, and the Systems board above shows the same.
- **Fleet** (since 22 Oct; spec docs/specs/2026-10-22-fleet-capture.md): the latest night's fleet of each airline as the
  game's fleet pages showed it (*fleet_checks()*, from *game_fleet*). Its title says the night and what needs a look
  ("the night of 22 Oct: 1 maintenance · 1 cabin"). Per airline a table: each aircraft's registration and base, type,
  where it was ("ORD → JFK · AW 1003", or "at FRA" between flights), condition, maintenance, seats Y/C/F and pilots,
  with the maintenance under the limit, the seats that don't match the planner's cabin and no pilots marked, and an
  aircraft the planner doesn't have marked **not in the planner**; under it, an aircraft in service the pages didn't
  have (only when every fleet page of the airline came in ok), and how many of its fleet pages came in ok.
- **Cabin charges** (since 22 Oct; manual §4): each first cabin fit filing logged since *cabin_charge_check_from* (18
  Oct, the first day the plan card chose the cabin; earlier fits include refits), against the game's "Installation of
  cabin interior (<reg>)" line on the bank statement (pilot training, which comes with an order, is left out). Its title
  says how they came out ("first fits since 18 Oct: 14 match · 2 waiting for the game's charge"), with an amber count
  when any needs a look. Matches are counted, not listed; each other one is a row with the airline, aircraft, what we
  logged (day, amount, cabin), what the game charged (each line) and the difference: **differs** (one line at another
  amount, with **Use the game's amount**, which changes the logged fit to the game's, one change), **charged twice**
  (more than one line), **not charged yet** (no line, and the airline's latest statement more than 2 days after the
  fit was logged; until then it's waiting) and **not logged** (the game charged a cabin for an aircraft with no first
  fit logged). Today's needs attention has one item while any is there, and opens this board.
- **Manual entry:** only if a night's capture failed. Cash and fixed costs for today (**Save** keeps a figure only
  where it differs from the capture's), the nightly log, and **Loads by hand**: type each airline's flights under 95%,
  or paste the game's load table, **Read paste**, check it and save, ticking each day that is complete. Loads typed or
  pasted change only the days and flights you enter; captured days stay as they are. A typed figure wins over the
  capture's where it is newer.

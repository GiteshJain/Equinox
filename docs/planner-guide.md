# The planner, screen by screen

A plain-language guide to equinox-alliance.com/planner/: what each screen shows, where its numbers come from, and what
you'd do there (decision #10). The words in **bold** are what the screen itself says.

Most numbers come from **last night's capture**, the *Capture all airlines* button you press in the game each evening.
The plans (plan cards, frequencies, aircraft, to-dos) are what you and Claude entered. The planner saves itself a moment
after every change. On a preview address it saves nothing and says **preview · not saved** (#8).

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

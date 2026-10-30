# The database, table by table

Generated from the database's own descriptions by `database/describe.py`. Don't edit by hand: change the
description in a migration (`comment on table ...`), and the database rehearsal regenerates and checks this
file. How the parts fit together: `docs/architecture.md`.

73 tables, 7 views and 49 functions, all in Supabase's `public` schema, plus 131 internal functions in `private`. Website photos and logos are files in the `site-photos` storage bucket, not tables.

## Contents

- [`aircraft`](#aircraft) (table): Each aircraft from order to delivery to service to retirement, one row each
- [`aircraft_cabin_keeps`](#aircraft-cabin-keeps) (table): Retired 21 Oct (manual §5; spec docs/specs/2026-10-21-cabins-new-rule.md): the Cabins board's "Keep as is" decisions, kept as history; nothing writes to it since the board went (we no longer refit; the cabin is chosen with each order)
- [`aircraft_eval_results`](#aircraft-eval-results) (table): What the game's aircraft evaluation tool showed for each aircraft type on a run (spec docs/specs/2026-10-27-aircraft-evaluation-script.md): one row per run and type, every figure of its row in the tool's table, parsed as numbers and as the page showed them (cells), so nothing needs re-running if another figure turns out to matter
- [`aircraft_eval_runs`](#aircraft-eval-runs) (table): The aircraft evaluation script's run list (spec docs/specs/2026-10-27-aircraft-evaluation-script.md): one row per route and economy seat type to run through the game's aircraft evaluation tool (/app/aircraft/evaluation), in order (pass, then seq), about 520 in all
- [`aircraft_types`](#aircraft-types) (table): Aircraft types and their figures in a world: seats, cruise speed, turns, maintenance, price
- [`airline_aircraft_types`](#airline-aircraft-types) (table): The aircraft types each airline may buy
- [`airline_bases`](#airline-bases) (table): Each airline's hubs and focus cities, with bank times and flight-number blocks, and since 22 Oct its stations (role station, manual §2): airports it flies point-to-point routes from without making them a base, with no banks, no block of their own (their numbers come from the airline's station pool, settings station_flight_no_from to station_flight_no_to) and never treated as hubs or focus cities
- [`airline_days`](#airline-days) (table): The daily history (decision #15, design §3.10, §7): one row per airline of our groups per capture day (design §2: the evening it was taken, 10:00 to 10:00 UTC), kept for good
- [`airline_order_cabins`](#airline-order-cabins) (table): An airline's own order cabin for an aircraft type, where it differs from the type's (aircraft_types.order_config_id): Ryanair's Standard layouts, as a low-cost airline
- [`airlines`](#airlines) (table): Every airline we track in a world: our own, and from #13's capture work the rivals the world scan sees (their columns about our airlines stay null)
- [`airports`](#airports) (table): Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world's own corrections are in world_airports)
- [`backup_runs`](#backup-runs) (view): The nightly backup's runs (decision #6), in the shape the backup job and the planner have always used: when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied, with the copy's R2 key
- [`cabin_configs`](#cabin-configs) (table): Cabin layouts (e.g
- [`capture_cash`](#capture-cash) (view): Cash and the next 7 days' payments per airline and capture date, from the capture, worked out as the planner does today: the latest balance of account 2800 that date, and the debits the events page lists for the 7 days after it was captured
- [`capture_keys`](#capture-keys) (table): Hashed keys that let the in-game capture send data
- [`cash_entries`](#cash-entries) (table): Cash and the next 7 days' fixed costs, in AS$, typed by hand or kept from before the capture: only figures the capture doesn't give
- [`change_log`](#change-log) (table): Every change to the planner's tables (decision #15): which row, added, changed or removed, the old and new values (for a change, only the columns that changed), when, and who
- [`countries`](#countries) (table): Country names by ISO code (-- for unknown), with the region the planner names for each
- [`dismissals`](#dismissals) (table): Alerts dismissed on the planner's Home, by the old planner's key (e.g
- [`fare_plan`](#fare-plan) (table): Fare changes to make in the game, and whether each is still planned or was dropped: fare tests (Performance's + fare plan), and since 21 Oct the fare ladder's moves (a row with level_pct, written by Performance's Put on the fare plan; manual §5)
- [`flight_legs`](#flight-legs) (table): One row per flight in the schedule, in UTC (design §4): departure minute, UTC weekdays and block time
- [`flight_legs_local`](#flight-legs-local) (view): Each flight leg with its flight code (KF 1001) and its times as the game shows them: local departure and arrival and local weekdays, plus the arrival in UTC and its day offset
- [`flight_no_clashes`](#flight-no-clashes) (view): An airline's flight number used by two or more legs departing on the same weekday (local at the origin, as the planner's check counts it)
- [`game_balance`](#game-balance) (table): The balance-sheet page from the nightly capture: one row per airline, account and UTC date, each with the figures and capture time of that date's latest capture
- [`game_capture_raw`](#game-capture-raw) (table): Every page the capture sent, as rows of cells before parsing (a fleet page, since 22 Oct, as the capture read it: its fleet, the airline's fleets and its aircraft), with its world and airline, and its check as it arrived (verdict, #21)
- [`game_events`](#game-events) (table): Payments the game lists ahead on the events page: leases, salaries and deliveries
- [`game_fleet`](#game-fleet) (table): The fleet as the game shows it (spec docs/specs/2026-10-22-fleet-capture.md; manual §7): one row per aircraft per capture day (design §2: the evening it was taken, 10:00 to 10:00 UTC), from the evening capture's fleet pages (Capture all airlines 1.6, page kind fleet), the latest capture of the day winning
- [`game_flight_pnl`](#game-flight-pnl) (view): Each statement block's income and costs by type and its profit, as before #13, from game_flights only: payments that aren't flights (salaries, leases and the like) are left out
- [`game_flights`](#game-flights) (table): One row per flown flight (decision #16, design §3.8): its loads from the loads page and its money from the bank statement, matched by route and time
- [`game_loads`](#game-loads) (view): Today's game_loads, from game_flights: every captured flight with passengers, seats, fares and loads by class and cargo, in the columns the planner (Check: daily load report, growth signals; Review: fare changes) and export_capture() read
- [`game_ops_recent`](#game-ops-recent) (view): Each airline's last 24 hours before its latest statement line, as before #13: flights, income, costs and hours, from game_flights and the statement lines the capture couldn't name (game_payments of kind other); salaries, leases, purchases, deposits, cabins and refits are left out
- [`game_payments`](#game-payments) (table): Bank-statement lines not tied to a flight: leases, salaries, purchases, deposits, cabins, refits, and lines in a minute with no flight
- [`game_pnl`](#game-pnl) (table): The game's income statement per airline and UTC date, for the current, last and total periods, with the figures and capture time of that date's latest capture
- [`game_scan_airlines`](#game-scan-airlines) (table): Each airline's totals in a world scan (design §3.9; was game_snapshot_airlines): flights, weekly departures and airports, with its airlines row
- [`game_scan_airports`](#game-scan-airports) (table): Each scanned airport's page in a world scan (design §3.9; was game_snapshot_airports): its details, the airlines stationed there and its news
- [`game_scan_schedules`](#game-scan-schedules) (table): Each airline's full schedule in a world scan (design §3.9): one JSON list per airline, each flight as [code, number, from, to, weekdays, departure, arrival, aircraft type, operator]
- [`game_scans`](#game-scans) (table): One row per world scan (design §3.9; was game_snapshots): when it ran, the week, its status and a note, with its world
- [`game_statement`](#game-statement) (table): Bank-statement lines from the capture, as the game lists them
- [`groups`](#groups) (table): A player's airlines in a world: ours (equinox.) and rival players' groups
- [`growth_log`](#growth-log) (table): Moves logged under the order rotation: big, freq or feeder
- [`ingest_secret`](#ingest-secret) (table): The shared secret that Claude's scripts send to the export, ingest, script and site-admin functions
- [`interline_agreements`](#interline-agreements) (table): Interline status per airline and country: not contacted yet, to sign, signed, declined, or no partner there
- [`job_runs`](#job-runs) (table): One row per run of every job (design §3.11): when it started and finished, ok or failed, the day or month it was for, a note and the details
- [`load_days`](#load-days) (table): A load day's flags typed in the planner (whether the day is complete)
- [`load_entries`](#load-entries) (table): Economy loads typed by hand, per flight and game date (the planner's Loads by hand, through planner_save())
- [`market_fares`](#market-fares) (table): Each airline's fares on a page the market pages read, by class (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per read, flight prefix and class (Y, C, F, Cargo), over the flights the page's Current Availability lists (finished yesterday, booked and in flight to about three days ahead): how many flights, the lowest, average and highest price in AS$, how many had finished and how many of those finished with no seat left (sold out; the page shows at most 9 seats left for a rival's passengers, so it is not a load factor)
- [`market_reads`](#market-reads) (table): Each Market Analysis page a market run read (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one direction of one pair, read with our airline that flies it open (the page's prices and its service profile are that airline's), ok or failed with the error, the week of its market shares and our service profile on the pair
- [`market_runs`](#market-runs) (table): One row per run of the market pages (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): Capture all airlines (capture/capture_all.user.js 1.9) reading the game's Market Analysis page of both directions of every pair our airlines fly, once every settings.market_every_days capture days, after the evening's capture and world scan
- [`market_shares`](#market-shares) (table): Each airline's share of a pair's passengers and cargo, as a page the market pages read shows it (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per read, kind (passengers, cargo) and airline, for the calendar week the page shows, with the change in points against the week before
- [`market_weeks`](#market-weeks) (table): A pair's seats offered and price per unit by calendar week, as the market pages read them from each page's Historic Capacities and Prices (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per world, direction (origin to dest) and week with figures, the latest read winning (a week read again replaces its figures)
- [`markets`](#markets) (table): Each airline's markets
- [`monthly_checks`](#monthly-checks) (table): When each monthly check was last done, per airline or for the group as a whole (airline_id null)
- [`plan_card_legs`](#plan-card-legs) (table): A plan card's flights, with the same time rules as flight_legs (UTC)
- [`plan_cards`](#plan-cards) (table): A plan for one aircraft's flying, on order or flying, kept after it is filed as the record of what was planned (whether it is filed is worked out, not stored)
- [`plan_line_legs`](#plan-line-legs) (table): A line's flights in flying order, with the same time rules as plan_card_legs (UTC): each departs on its line day, and the aircraft at offset k flies line day d on UTC weekday ((d + k − 1) mod 7) + 1 (the library's card.fromLine)
- [`plan_lines`](#plan-lines) (table): A 7-day rotating line (manual §4, long haul in lines; spec docs/specs/2026-10-27-long-haul-lines.md §2): 7 aircraft of one type at one airline fly one weekly pattern, each a day apart, so every flight on it operates daily at the same time
- [`planner_scripts`](#planner-scripts) (table): Copies of Claude's scripts from before the repository existed
- [`planner_users`](#planner-users) (table): Email addresses allowed into the planner (staff)
- [`report_access`](#report-access) (table): The password hash for the investor page and investor reports
- [`rotations`](#rotations) (table): An aircraft's out-and-back pair on a route: what the old planner calls a frequency
- [`route_days`](#route-days) (table): The daily history per route, direction and UTC day (design §3.10, §7): each airline's flights, passengers, seats, money and average economy fare, from game_flights (a flight's day is the UTC date it departs), kept for good after game_flights is archived
- [`routes`](#routes) (table): Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner's overrides (null = the research value; research refreshes never touch them)
- [`scan_airline_airports`](#scan-airline-airports) (table): Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and airport, its departures a week from there and how many destinations it flies to from there
- [`scan_airline_fleet`](#scan-airline-fleet) (table): Each airline's fleet by aircraft type in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §3): one row per scan, airline and type as its overview page's Fleet table shows it (/app/info/enterprises/<game id>), every enterprise the scan lists, flying or not
- [`scan_airline_markets`](#scan-airline-markets) (table): Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and market (the weekly report's market names, e.g
- [`scan_airline_profile`](#scan-airline-profile) (table): Each airline's overview page in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §3): one row per scan and airline read, with the Fleet table's totals (fleet_size, on_order, avg_age_years, from its tfoot) and the page's General Information and General statistics, or read_ok false with the reason in note when the page didn't read (a failed page never stops the scan)
- [`scan_pair_airlines`](#scan-pair-airlines) (table): Each airline's departures a week on every city pair in the world, from the week's kept world scan, kept for good (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §1, §2): the first finished scan of the world on or after each Saturday (UTC date), written by private.scan_pairs_keep() at the scan's finish, and filled back once from the scans still holding their schedules
- [`scan_rival_connections`](#scan-rival-connections) (table): Rivals' one-stop connections on our city pairs in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §1, §2): one row per scan, rival, direction (origin to dest) and connecting airport (via), worked out from the scan's schedules by private.scan_connections() when the scan finishes
- [`scan_rival_connections_week`](#scan-rival-connections-week) (table): Rivals' connecting departures on our city pairs by scan, kept for good (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §2): one row per scan, rival and pair (airport_a, airport_b, the codes in order), each direction's total and both, and the top 3 connecting airports; written with scan_rival_connections by private.scan_connections(), and its rows mark the scans whose connections were worked out (competition() and route_story() show none for a scan without)
- [`service_profiles`](#service-profiles) (table): On-board service by distance (S1, S2, …)
- [`settings`](#settings) (table): Our own planning choices as data (decision #14): the manual's rule numbers, thresholds and display choices for a world, with per-airline overrides
- [`site_content`](#site-content) (table): Website content kept as data, one row per key: media (destination photos and airline logos), airport_cities (since 15 Oct: name, the name the website gives an airport, and photo, the city whose photo an airport without its own takes; the website and the planner's Photos screen read them through site_public(), where each kept them in its code before), markets, and mct (minimum connection times, also used by the schedule optimiser; since #13's pull request 8 site_admin() writes them to world_airports too, and site_public() reads them from there; this copy is kept for the planner's Reference, which shows it)
- [`site_posts`](#site-posts) (table): Newsroom posts on the website
- [`site_reports`](#site-reports) (table): Investor reports and gander monthly issues, each with its status (upcoming or published) and its PDF
- [`spending_log`](#spending-log) (table): Money spent, in AS$: aircraft orders, cabins and refits, losses
- [`todo_items`](#todo-items) (table): A to-do's steps, in order
- [`todos`](#todos) (table): The planner's To-do board
- [`world_airports`](#world-airports) (table): What a world says about an airport, only where there is something to say: minimum connection time, night ban, a corrected UTC offset, closure
- [`world_rules`](#world-rules) (table): The world's own rules as data (decision #14): house rules, game settings, and whether #12's items (interlines between our airlines, the capture's salary step, the world scanner, the schedule check) are allowed there
- [`worlds`](#worlds) (table): One row per AirlineSim world we play in (decision #14)
- [Functions](#functions)
- [Internal functions](#internal-functions)

## aircraft

*Table.* Each aircraft from order to delivery to service to retirement, one row each. Replaced the old planner's tails and deliveries: status active is a tail (on the planner's Tails), and one with a delivery that isn't retired is on the deliveries board.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `registration` | text | e.g. N001AW; a field, not the key, so a re-registration touches one row |
| `aircraft_type_id` | bigint | Today's type |
| `cabin_config_id` | bigint | Today's cabin |
| `base_code` | text | Today's base |
| `status` | text | on_order, delivered (arrived, not yet filed into the planner), active (in service: a tail) or retired |
| `ordered_on` | date |  |
| `delivery_at` | timestamp with time zone | Arrival in the game (the planner's deliveries[].utc) |
| `order_base_code` | text | Base as ordered |
| `order_config_id` | bigint | Cabin as ordered; can differ from today's after a refit |
| `order_note` | text |  |
| `checked_on` | date | Was the one-week check, Gitesh's to mark; the check went on 22 Oct (manual §1). Kept, read by nothing (filing clears it) |
| `schedule_changed_on` | date | Was when its schedule last changed, which restarted the one-week check; the check went on 22 Oct. Kept, read by nothing (filing clears it) |
| `maintenance_note` | text | The planner's maint |
| `retired_on` | date |  |
| `extra` | jsonb | What the old planner kept on a tail that the table has no column for, under tail (its notes, which Tails shows). The old lists' places and delivery items went with the clean-up (build pull request 14). Expected otherwise empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `acquired` | text | How the aircraft came: new (ordered from the factory) or used (bought on the used market). Decides its replacement age (manual §3: settings.replace_new_years, replace_used_years) and the fleet check's looks-used cross-check. Since 26 Oct it has no default: every new row must say which. |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, plan_line_slot, set_updated_at.

## aircraft_cabin_keeps

*Table.* Retired 21 Oct (manual §5; spec docs/specs/2026-10-21-cabins-new-rule.md): the Cabins board's "Keep as is" decisions, kept as history; nothing writes to it since the board went (we no longer refit; the cabin is chosen with each order). Each row: the aircraft kept its cabin although its routes called for this one. Replaced the planner's cabinKeep.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `aircraft_id` | bigint |  |
| `cabin` | text | The cabin its routes call for, which it keeps not having |
| `decided_on` | date |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## aircraft_eval_results

*Table.* What the game's aircraft evaluation tool showed for each aircraft type on a run (spec docs/specs/2026-10-27-aircraft-evaluation-script.md): one row per run and type, every figure of its row in the tool's table, parsed as numbers and as the page showed them (cells), so nothing needs re-running if another figure turns out to matter. A type that can't fly the route has can_operate false, the game's message and no figures. Money is in AS$ a week, as the tool shows it. Written only by capture_eval_result(), which replaces a run's rows when it is saved again; rows for types beyond settings.aircraft_eval_types are kept too. Staff read it; the Scheduling chat reads it as postgres.

| Column | Type | Notes |
|---|---|---|
| `run_id` | bigint | The run (aircraft_eval_runs); its rows go with it |
| `type_name` | text | The type by the tool's name, e.g. Airbus A350-900 |
| `game_type_id` | bigint | The game's id of the type, from the link in the tool's first cell (aircraftsType?id=3921) |
| `can_operate` | boolean | Whether the type can fly the route; false when the tool says "This type cannot operate on the selected relation." |
| `message` | text | The tool's text for a type that cannot operate; null otherwise |
| `flights_week` | numeric | Flights per week one aircraft can fly on the route (6.00) |
| `seats` | numeric | Available seats with the run's settings (the class and seat type) |
| `fuel` | numeric | Fuel, AS$ a week |
| `handling` | numeric | Aircraft handling, AS$ a week |
| `atc` | numeric | ATC, AS$ a week |
| `landing` | numeric | Landing fees, AS$ a week |
| `maintenance` | numeric | Maintenance, AS$ a week |
| `capital` | numeric | Capital cost, AS$ a week |
| `crew` | numeric | Crew, AS$ a week |
| `fixed_total` | numeric | Fixed costs total, AS$ a week |
| `per_seat` | numeric | Fixed costs per seat, AS$ (539 AS$) |
| `profit_50` | numeric | Profit at 50% load, AS$ a week |
| `profit_60` | numeric | Profit at 60% load, AS$ a week |
| `profit_70` | numeric | Profit at 70% load, AS$ a week |
| `profit_80` | numeric | Profit at 80% load, AS$ a week |
| `profit_90` | numeric | Profit at 90% load, AS$ a week |
| `profit_100` | numeric | Profit at 100% load, AS$ a week |
| `margin_50` | numeric | Margin at 50% load, % (the bracket beside the profit) |
| `margin_60` | numeric | Margin at 60% load, % |
| `margin_70` | numeric | Margin at 70% load, % |
| `margin_80` | numeric | Margin at 80% load, % |
| `margin_90` | numeric | Margin at 90% load, % |
| `margin_100` | numeric | Margin at 100% load, % |
| `cells` | jsonb | Every cell of the type's row as the page showed it, as text, the type's cell first |
| `saved_at` | timestamp with time zone | When the row was saved |

**Access:** staff read: select for authenticated.

## aircraft_eval_runs

*Table.* The aircraft evaluation script's run list (spec docs/specs/2026-10-27-aircraft-evaluation-script.md): one row per route and economy seat type to run through the game's aircraft evaluation tool (/app/aircraft/evaluation), in order (pass, then seq), about 520 in all. The Scheduling chat writes the list with plain SQL (manual §1's actor line); the script (capture/aircraft_eval.user.js) reads the runs without a result through capture_eval_runs() and writes each result's header here through capture_eval_result(). Staff read it; not in the change log. Its results are aircraft_eval_results.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | The run's own number, which capture_eval_result() is given |
| `world_id` | bigint | The world whose capture key may run and save it |
| `pass` | integer | The pass, 1 to 4: 1 the distance ladder, 2 a second region at each ladder distance, 3 real decisions (the November trunks and each airline's top openings), 4 Ryanair on Standard seats |
| `seq` | integer | The order within the world (unique): the script runs pass by pass, then by seq, shortest first within passes 1 to 3, so the seat type changes only twice |
| `from_code` | text | The route's first airport, IATA, as typed into the tool's From box |
| `to_code` | text | The route's second airport, IATA, as typed into the tool's To box |
| `distance_km` | integer | The route's distance, km, for the Scheduling chat; optional, the script doesn't use it |
| `seat` | text | The economy seat type to run with, by the tool's name: Standard, Leisure, Leisure Plus or Comfort (manual §5: by distance; Standard for Ryanair). The script sets the tool's Seat to it before the run when it differs |
| `note` | text | A note from the Scheduling chat (why this route is on the list); optional |
| `from_name` | text | The first airport's name as the tool resolved the code (written with the result) |
| `to_name` | text | The second airport's name as the tool resolved the code (written with the result) |
| `settings` | jsonb | The tool's settings as the result page showed them, by their texts: age ("0 year(s)"), class ("Economy"), seat ("Comfort") and price_factor ("100%") |
| `done_at` | timestamp with time zone | When its result was saved; null while it has none (capture_eval_runs() lists only those). A run saved again moves it on |
| `created_at` | timestamp with time zone | When the run was put on the list |

**Access:** staff read: select for authenticated.

## aircraft_types

*Table.* Aircraft types and their figures in a world: seats, cruise speed, turns, maintenance, price. Replaces the planner's ref.types.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `name` | text | Unique in a world, except a blank one (the planner's New type for a new row, or empty), which may repeat |
| `family_no` | integer | The game's aircraft family number |
| `seats_max` | integer |  |
| `cruise_kmh` | integer |  |
| `min_turn_min` | smallint | Shortest turn, minutes |
| `gap_target_h` | numeric(4,1) | Target maintenance gap, hours |
| `maint_per_hour` | numeric(5,2) | Maintenance need per flight hour |
| `maint_per_cycle` | numeric(5,2) | Maintenance need per take-off and landing |
| `ground_keep_min` | smallint | The turn the game keeps at each end, minutes (the planner's greens) |
| `price` | numeric(14,2) | AS$ |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `order_config_id` | bigint | The cabin layout an order of the type comes with (private.fig_order_cabin(): Tails, the cash forecast, the briefing), for every airline without its own in airline_order_cabins; empty for none. Filled on 15 Oct from the old rule (the old planner's DEFAULT_CABIN), changed in Reference |
| `range_km` | integer | Range with a full load, km, from the game's aircraft page (manual §3, the default line) |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## airline_aircraft_types

*Table.* The aircraft types each airline may buy. Replaces the planner's BUY_TYPES.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `aircraft_type_id` | bigint |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## airline_bases

*Table.* Each airline's hubs and focus cities, with bank times and flight-number blocks, and since 22 Oct its stations (role station, manual §2): airports it flies point-to-point routes from without making them a base, with no banks, no block of their own (their numbers come from the airline's station pool, settings station_flight_no_from to station_flight_no_to) and never treated as hubs or focus cities. Replaces the planner's ref.hubs and MAIN_HUB.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `airport_code` | text |  |
| `role` | text | hub, focus or station (since 22 Oct: point-to-point routes only; no banks, no block, never the main hub) |
| `is_main` | boolean | The airline's main hub; one per airline |
| `parent_base_id` | bigint | A focus city's hub |
| `bank_times` | time without time zone[] | Bank times, local clock time; 4 slots, null = empty |
| `flight_no_from` | integer | First flight number of the base's block, e.g. 1000 |
| `last_flight_no` | integer |  |
| `hold_note` | text | Why the base is on hold, if it is |
| `position` | integer |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## airline_days

*Table.* The daily history (decision #15, design §3.10, §7): one row per airline of our groups per capture day (design §2: the evening it was taken, 10:00 to 10:00 UTC), kept for good. Point-in-time figures (fleet, schedule, cash) are fixed when the snapshot is taken (private.take_snapshot, by the capture when a world's capture for the day is complete) and replaced by a later complete capture of the same day; the flows are for the UTC day of the same date and recomputed for the two days after, as late captures fill them in. Filled back from 29 Sep (source backfill). Not in the change log. Staff read it; only the database writes it.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `day` | date | The capture day (design §2); the flows are for the UTC day of this date |
| `complete` | boolean | True when that day's capture was complete for the whole world (every active airline of our groups, all five pages) |
| `source` | text | capture (taken when the day's capture was complete), fallback (the 10:00 UTC job, #13 pull request 7) or backfill (filled back by 20261011120000_history) |
| `taken_at` | timestamp with time zone | The moment the point-in-time figures stand for: when the capture's last page arrived, the job's time, or for a backfilled day the end of that capture day |
| `aircraft_by_type` | jsonb | Aircraft flying, by type: {"A321 NEO LIGHT": 50, ...}. Flying from arrival in the game (delivery) until retired; backfilled days from delivery dates (an aircraft with no delivery record from the start) |
| `aircraft_total` | integer | Aircraft flying (the sum of aircraft_by_type) |
| `on_order` | integer | Aircraft ordered and not yet arrived |
| `weekly_departures` | integer | Departures a week in the schedule (flight_legs, each leg's weekdays), counting rotations launched by that day (backfilled days assume nothing was dropped) |
| `weekly_seats` | integer | Seats a week in the schedule: each leg's departures times its aircraft's seats (its cabin, or its type's maximum) |
| `destinations` | integer | Distinct destinations in the schedule (the far end of each route flown) |
| `cash` | numeric(14,2) | Cash, AS$: the day's latest balance of account 2800 (game_balance), or with no capture the figure typed or kept from before the capture (cash_entries) |
| `fixed_next7` | numeric(14,2) | Payments the events page lists for the 7 days after that balance, AS$ (as capture_cash works them out); typed figures from cash_entries |
| `cash_at` | timestamp with time zone | The balance's capture time; null when the cash was typed or kept from before the capture |
| `flights_flown` | integer | Flights that departed that UTC day (game_flights rows with loads or with passenger income) |
| `passengers` | integer | Passengers on those flights: from the loads page, or the statement's count where the loads weren't captured |
| `seats_flown` | integer | Seats on the flights whose loads were captured |
| `load_pct` | numeric(5,1) | Passengers ÷ seats on the flights whose loads were captured, percent |
| `eco_load_pct` | numeric(5,1) | Economy passengers ÷ economy seats, percent |
| `revenue` | numeric(14,2) | Income of every statement block that day, AS$ |
| `flight_costs` | numeric(14,2) | Costs of every statement block that day, AS$ (fuel, fees, handling, maintenance ...) |
| `flight_profit` | numeric(14,2) | revenue − flight_costs, before leases, salaries and purchases, AS$ |
| `leases_paid` | numeric(14,2) | Lease payments posted that UTC day (game_payments kind lease), AS$ |
| `salaries_paid` | numeric(14,2) | Salaries posted that UTC day (kind salaries: the week-end closing), AS$ |
| `purchases_paid` | numeric(14,2) | Aircraft, deposits, cabins and refits paid that UTC day (kinds purchase, deposit, cabin, refit), AS$ |

**Access:** staff read: select for authenticated.

## airline_order_cabins

*Table.* An airline's own order cabin for an aircraft type, where it differs from the type's (aircraft_types.order_config_id): Ryanair's Standard layouts, as a low-cost airline. Filled on 15 Oct from the old rule (the old planner's DEFAULT_CABIN), changed in Reference. One of the planner tables.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `aircraft_type_id` | bigint |  |
| `order_config_id` | bigint | The cabin layout this airline's orders of the type come with; empty for none |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## airlines

*Table.* Every airline we track in a world: our own, and from #13's capture work the rivals the world scan sees (their columns about our airlines stay null). Game ID, codes, home airport, colours and the website's text, which today are copied in the planner (CODE_AL, CAP_HOME, AIRLINE_ORDER, LIVERY) and the capture. The website reads them from site_public().airlines (its own copy is only a fallback), and the Photos screen checks airlines against them. The game link is worked out from worlds.game_host and game_id.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `group_id` | bigint | Null for a rival not yet placed in a group |
| `game_id` | integer | The game's enterprise ID, e.g. 114 |
| `game_name` | text | The name as the game shows it |
| `planner_name` | text | The old planner's key, e.g. Pan American |
| `public_name` | text | The name on the website, e.g. Pan Am |
| `iata_code` | text | The airline code in flight numbers, e.g. AW |
| `country_code` | text |  |
| `home_airport_code` | text | Where the game's events page shows the airline's times |
| `is_lcc` | boolean | A low-cost carrier, for the house rules |
| `low_demand` | boolean | Held as a low-demand-country holding, for the house rules |
| `active` | boolean |  |
| `founded_on` | date |  |
| `position` | integer | Display order, 1 first |
| `livery_color` | text | Brand colour, #RRGGBB |
| `slug` | text | The website's address part, e.g. pan-am |
| `region_text` | text | Website text: where it flies |
| `role_text` | text | Website text: its role in the group |
| `blurb` | text | Website text: the description on Our airlines |
| `photo_city` | text | The city whose photo stands for the airline (site_content media photos, by city): on the website, and behind the airline's card on the planner's Home |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## airports

*Table.* Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world's own corrections are in world_airports). Loaded from planner_data.coords and planner_data.utc, plus code-only rows for any other airport the planner names (#13, pull request 4); kept in step with the research by planner_data_set() since pull request 8.

| Column | Type | Notes |
|---|---|---|
| `code` | text |  |
| `city` | text |  |
| `country_code` | text |  |
| `lat` | numeric(8,5) |  |
| `lon` | numeric(8,5) |  |
| `utc_offset` | numeric(4,2) | Hours from UTC, e.g. 5.50, 5.75, -5.00; the game runs standard time all year |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## backup_runs

*View.* The nightly backup's runs (decision #6), in the shape the backup job and the planner have always used: when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied, with the copy's R2 key. Since #13 pull request 7 a view of job_runs (job backup); an insert (scripts/report.sh in equinox-backups) becomes a job_runs row, so the job works whatever the deploy order. The old table is backup_runs_before_13. Read by the planner's Capture board and the backup warnings on Home. Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | The job_runs row's id |
| `ran_at` | timestamp with time zone | When the run reported (job_runs.started_at) |
| `kind` | text | nightly, manual or test (a pull request's dry run) |
| `ok` | boolean | Whether the whole run worked (job_runs.status ok) |
| `tables` | integer | Tables copied (job_runs.details) |
| `rows` | bigint | Rows copied (job_runs.details) |
| `files` | integer | Site files copied (job_runs.details) |
| `bytes` | bigint | Size of the copy before packing (job_runs.details) |
| `commit_sha` | text | The equinox-backups commit holding that night's copy (8 and 9 Oct, before R2) |
| `note` | text | For a failed run, the end of its log (job_runs.note) |
| `object_key` | text | R2 key of that run's copy (from 9 Oct; earlier runs have commit_sha) |

**Triggers:** backup_runs_insert.

## cabin_configs

*Table.* Cabin layouts (e.g. 321-LEI) with their seats and cost. Replaces the planner's ref.configs.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `code` | text | e.g. 321-LEI. Unique in a world, except a blank one (the planner's NEW for a new row, or empty), which may repeat |
| `aircraft_type_id` | bigint |  |
| `cabin` | text | As typed in the planner: Standard, Leisure, Leisure Plus or Comfort, or anything else |
| `seats` | integer |  |
| `business_seats` | integer |  |
| `economy_seats` | integer |  |
| `cost` | numeric(14,2) | AS$ |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## capture_cash

*View.* Cash and the next 7 days' payments per airline and capture date, from the capture, worked out as the planner does today: the latest balance of account 2800 that date, and the debits the events page lists for the 7 days after it was captured. What planner_state_get() shows unless cash_entries says otherwise. Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `day` | date | The capture date as the planner keys it: game_balance.captured_on, the UTC date |
| `cash` | numeric | Cash, AS$: the balance of account 2800 |
| `fixed_next7` | numeric | AS$ the events page lists as payments in the 7 days after the balance was captured; null when none |
| `cash_at` | timestamp with time zone | When the balance was captured |

## capture_keys

*Table.* Hashed keys that let the in-game capture send data. Only hashes are stored. Each key belongs to one world (world_id): a page for an airline outside it is refused. Written by hand when a key is issued. Read by capture_ingest(), capture_airlines(), capture_fare_actions() and capture_scan().

Never leaves the database: left out of the nightly backup on purpose.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `label` | text |  |
| `key_hash` | text |  |
| `created_at` | timestamp with time zone |  |
| `world_id` | bigint | The world the key captures; name it when issuing a key |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## cash_entries

*Table.* Cash and the next 7 days' fixed costs, in AS$, typed by hand or kept from before the capture: only figures the capture doesn't give. Replaces the hand-typed part of the planner's cash and fixed7.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `day` | date | The planner's date key |
| `cash` | numeric(14,2) | AS$ |
| `fixed_next7` | numeric(14,2) | Fixed costs in the next 7 days, AS$ |
| `entered_at` | timestamp with time zone |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## change_log

*Table.* Every change to the planner's tables (decision #15): which row, added, changed or removed, the old and new values (for a change, only the columns that changed), when, and who. Written only by private.log_change(); staff can read it, nobody can edit it. Kept 12 months, then archived.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `changed_at` | timestamp with time zone | When, to the microsecond (clock_timestamp()) |
| `world_id` | bigint | The changed row's world; null for countries and airports |
| `table_name` | text |  |
| `row_key` | jsonb | The changed row's primary key, e.g. {"id": 812} |
| `op` | text | insert, update or delete |
| `old_values` | jsonb | Before: the whole row for a delete, only the changed columns for an update |
| `new_values` | jsonb | After: the whole row for an insert, only the changed columns for an update |
| `actor` | text | Who: planner, claude, capture, script, job, migration, or unset when the writer didn't say |
| `actor_detail` | text | Which one: a tab ID, a script or chat name |
| `db_role` | text | The database role the change was made as |
| `txid` | bigint | The transaction, so one save's changes can be grouped |

**Access:** staff read: select for authenticated.

## countries

*Table.* Country names by ISO code (-- for unknown), with the region the planner names for each. The same in every world. Replaces planner_data.countries; kept in step with the research by planner_data_set().

| Column | Type | Notes |
|---|---|---|
| `code` | text |  |
| `name` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `region` | text | The region the planner names for the country (Hubs' connections table, Check's hub readiness): South Asia, China & North-East Asia, South-East Asia, Oceania, Middle East, Russia & Central Asia, North America, South America or Africa as the old planner's list had them; Europe for any other country (the default, so a country the research adds takes it); Other for the unknown country (--) |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## dismissals

*Table.* Alerts dismissed on the planner's Home, by the old planner's key (e.g. maint|B-0162). Replaces the planner's dismissed.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `alert_key` | text | The old planner's key, e.g. maint|B-0162 |
| `dismissed_on` | date |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## fare_plan

*Table.* Fare changes to make in the game, and whether each is still planned or was dropped: fare tests (Performance's + fare plan), and since 21 Oct the fare ladder's moves (a row with level_pct, written by Performance's Put on the fare plan; manual §5). Replaces the planner's farePlan.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `route_id` | bigint |  |
| `legacy_key` | text | The old planner's fare-plan id; new rows get one too |
| `cabin_class` | text | economy, business or first |
| `change_pct` | numeric(5,1) | The fare change to make, percent |
| `fare_from` | numeric(14,2) | The fare before the change, AS$ |
| `proposed_on` | date |  |
| `status` | text | planned or dropped |
| `reason` | text |  |
| `extra` | jsonb | Fields the table doesn't know; the old planner's were cleared at the clean-up (build pull request 14). Expected empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `level_pct` | numeric(5,1) | The fare ladder's level the row sets, as a % of the game's default price (manual §5): the latest one for a route and cabin is its level. Null on a fare test that isn't the ladder's |
| `ladder_move` | text | The fare ladder's move: up, down or hold (a hold is recorded when it follows a step down, so the hold has a record; from 23 to 26 Oct when a jump under launch was judged to have paid; since 26 Oct when a cabin at the last jump level holds there, marked cut or keep?); since 23 Oct also jump (a jump under launch, to a level of settings.fare_under_launch_levels); revert (back to launch from the last jump level) was written from 23 to 26 Oct only: since then a cabin under launch is judged on its loads and never reverts. Null on a fare test that isn't the ladder's |
| `direction` | text | The fare ladder's direction (since 26 Oct, manual §5): out (from the route's hub) or back (to it); null for both directions, as every row written before the ladder went per direction. A direction's level is its latest row, or the latest both-directions row if that is later |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## flight_legs

*Table.* One row per flight in the schedule, in UTC (design §4): departure minute, UTC weekdays and block time. Leg 1 leaves the hub, leg 2 returns, and the airports must match the route that way. A flight number can repeat on other days, so flight_no_clashes lists real clashes. Local times are in flight_legs_local.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `rotation_id` | bigint |  |
| `leg_no` | smallint | 1 = out from the hub, 2 = back |
| `flight_no` | integer | e.g. 1001, shown with the airline's code as KF 1001 |
| `origin_code` | text |  |
| `dest_code` | text |  |
| `aircraft_id` | bigint | Null only while being typed |
| `days_utc` | smallint[] | UTC weekdays it departs, ISO (1 = Monday): sorted, no repeats, at least one |
| `dep_utc_min` | smallint | Departure, minutes after 00:00 UTC (0 to 1439); null only while being typed |
| `block_min` | smallint | Block time, minutes, from the game's times; null = arrival not typed (the planner estimates it) |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** check_leg_route, log_change, set_updated_at.

## flight_legs_local

*View.* Each flight leg with its flight code (KF 1001) and its times as the game shows them: local departure and arrival and local weekdays, plus the arrival in UTC and its day offset. Worked out from the UTC schedule with each airport's offset in the leg's world; null where an offset or the block time is missing. Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `rotation_id` | bigint |  |
| `leg_no` | smallint |  |
| `flight_no` | integer |  |
| `flight_code` | text | e.g. KF 1001 |
| `origin_code` | text |  |
| `dest_code` | text |  |
| `aircraft_id` | bigint |  |
| `days_utc` | smallint[] |  |
| `dep_utc_min` | smallint |  |
| `block_min` | smallint |  |
| `dep_local_min` | integer | Departure, minutes after local midnight at the origin |
| `dep_local` | text | Departure, local clock time at the origin, as the game shows it |
| `days_local` | smallint[] | Local weekdays it departs at the origin, ISO (1 = Monday) |
| `arr_local_min` | integer | Arrival, minutes after local midnight at the destination |
| `arr_local` | text | Arrival, local clock time at the destination |
| `arr_local_day_offset` | integer | Local arrival day minus local departure day: 0 = the same day, 1 = the next |
| `arr_utc_min` | integer | Arrival, minutes after 00:00 UTC |
| `arr_utc_day_offset` | integer | UTC arrival day minus UTC departure day |

## flight_no_clashes

*View.* An airline's flight number used by two or more legs departing on the same weekday (local at the origin, as the planner's check counts it). Numbers may repeat on other days, so only real clashes are listed. Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `flight_no` | integer |  |
| `flight_code` | text |  |
| `weekday` | smallint | Departure weekday, local at the origin, ISO (1 = Monday); UTC where the origin's offset isn't known |
| `legs` | integer | How many legs use the number that day |
| `leg_ids` | bigint[] |  |
| `aircraft_ids` | bigint[] |  |

## game_balance

*Table.* The balance-sheet page from the nightly capture: one row per airline, account and UTC date, each with the figures and capture time of that date's latest capture. Account 2800 is cash. Written by the capture (private.capture_page). Read by the planner (Review: the group today, Cash next 14 days), capture_cash, the daily history and export_capture().

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `captured_on` | date | The UTC date of the capture, as the old planner reads it (an evening's capture can fall on the next UTC date) |
| `account` | text | Account number and name as the game shows them; 2800 is cash |
| `amount` | numeric |  |
| `captured_at` | timestamp with time zone | When the capture that gave the figures was taken (the latest capture that UTC date, since #13 pull request 6) |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `capture_day` | date | The capture day (design §2): the evening of the capture that gave the figures |

**Access:** planner staff read game_balance: select for authenticated.

## game_capture_raw

*Table.* Every page the capture sent, as rows of cells before parsing (a fleet page, since 22 Oct, as the capture read it: its fleet, the airline's fleets and its aircraft), with its world and airline, and its check as it arrived (verdict, #21). Kept 14 days: the 10:20 UTC clean-up (private.job_cleanup, #13 pull request 7) deletes older pages. Written by capture_ingest(). Read by private.capture_page(), completeness (private.capture_day_complete), capture_status() and system_status() (each airline's latest verdicts), fleet_checks() (whether every fleet page came in ok) and the planner's Capture board.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `airline` | text |  |
| `kind` | text | statement, events, loads, pnl, balance, fleet (since 22 Oct: one fleet page) or html |
| `page_url` | text |  |
| `captured_at` | timestamp with time zone |  |
| `rows` | jsonb | The page's table rows, each a list of cell texts; for a fleet page (since 22 Oct) the page as Capture all airlines read it: {run, page, of, fleet: {id, name}, fleets: [{id, name, aircraft}], aircraft: [...]}, or error in place of aircraft when it didn't read |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `verdict` | text | The page's check as it arrived (#21): ok, short (fewer rows than expected; a fleet page with no aircraft rows) or broken (didn't read, or a balance sheet without the cash account); null for page inspection (html) and pages stored before 14 Oct's checks |
| `verdict_note` | text | The verdict in words: what was expected and what came, e.g. loads 12 of 78 flights (#21) |
| `verdict_facts` | jsonb | The numbers behind the verdict (#21): read (rows the reader took), and per kind scheduled and share (loads), median_lines and nights (statement), cash (balance), fleet, fleet_id, page, of and listed (fleet), the limit used, or the error |

**Access:** planner staff read game_capture_raw: select for authenticated.

## game_events

*Table.* Payments the game lists ahead on the events page: leases, salaries and deliveries. Written by the capture (private.capture_page). Read by the planner's cash forecast (Review: Cash, next 14 days), which also takes each type's lease from here.

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `event_date` | date |  |
| `event_time` | text | As the game's events page shows it, at the airline's home airport |
| `descr` | text |  |
| `debit` | numeric |  |
| `credit` | numeric |  |
| `balance` | numeric |  |
| `captured_at` | timestamp with time zone |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `due_at` | timestamp with time zone | When it falls due, from the local time at the airline's home airport; null while that airport's offset isn't known (filled once the airports are loaded) |

**Access:** planner staff read game_events: select for authenticated.

## game_fleet

*Table.* The fleet as the game shows it (spec docs/specs/2026-10-22-fleet-capture.md; manual §7): one row per aircraft per capture day (design §2: the evening it was taken, 10:00 to 10:00 UTC), from the evening capture's fleet pages (Capture all airlines 1.6, page kind fleet), the latest capture of the day winning. Kept for good (about 140 rows a night): the history the planner's maintenance figure will be fitted to (the brief's option C). Written only by the capture (capture_ingest(), private.capture_fleet()); staff read it. Read by fleet_checks() (Today, Systems' Fleet, the Tails pop-up).

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | The row's own number |
| `world_id` | bigint | The world |
| `airline_id` | bigint | The airline whose fleet page it was on |
| `capture_day` | date | The capture day it was read (private.capture_day(): 10:00 to 10:00 UTC, the day the evening started) |
| `aircraft_id` | bigint | The planner's aircraft with this registration in the airline when it was read; null when the planner didn't know it (set to null if that aircraft is removed). fleet_checks() matches by registration as the planner stands |
| `registration` | text | The registration as the game shows it, in capitals, e.g. N003AW |
| `type_name` | text | The game's name for the aircraft's model, e.g. Airbus A321NEO Light |
| `nickname` | text | The aircraft's nickname in the game; null when it has none |
| `location_from` | text | Where it is: the airport it's at on the ground, or the airport it left when flying (then location_to is set) |
| `location_to` | text | Where it's flying to; null on the ground. A blank location on the page is an aircraft between flights, not an idle one |
| `flight` | text | The flight it's on, as the game writes it (AW 1003); null on the ground |
| `age_years` | numeric(5,1) | Its age in years, as the game rounds it |
| `condition_pct` | numeric(5,1) | Its condition, %, as the game shows it |
| `maintenance_pct` | numeric(7,1) | Its maintenance ratio, %, as the game shows it: under settings.maintenance_min_pct (100) the condition falls |
| `seats_y` | integer | Economy seats as fitted (the Y of Y/C/F) |
| `seats_c` | integer | Business seats as fitted (the C of Y/C/F) |
| `seats_f` | integer | First-class seats as fitted (the F of Y/C/F) |
| `pilots` | boolean | Whether it has pilots (the game's yes or no) |
| `owned` | boolean | Whether we own it (yes) or lease it (no) |
| `contract_status` | text | Its contract's state as the game words it, e.g. active |
| `fleet_game_id` | integer | The game's id of the fleet it was in (/app/fleets/<id>; Gitesh keeps one per hub); null for the Default fleet |
| `fleet_name` | text | The name of the fleet it was in, e.g. JFK, or Default |
| `captured_at` | timestamp with time zone | When the page this row came from was captured (the latest of the day wins) |

**Access:** staff read: select for authenticated.

## game_flight_pnl

*View.* Each statement block's income and costs by type and its profit, as before #13, from game_flights only: payments that aren't flights (salaries, leases and the like) are left out. Read by the planner (Review: route profit, aircraft) and export_capture(). Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `ts` | timestamp with time zone |  |
| `blk` | integer |  |
| `route` | text |  |
| `routes_n` | bigint |  |
| `pax` | integer |  |
| `tail` | text |  |
| `pax_income` | numeric |  |
| `cargo_income` | numeric |  |
| `fuel` | numeric |  |
| `onboard` | numeric |  |
| `handling` | numeric |  |
| `landing` | numeric |  |
| `atc` | numeric |  |
| `maintenance` | numeric |  |
| `profit` | numeric |  |

## game_flights

*Table.* One row per flown flight (decision #16, design §3.8): its loads from the loads page and its money from the bank statement, matched by route and time. Until a block and a loads row are matched (or when one never comes), a row holds only one side: money-only rows have no flight number, loads-only rows no statement time. Written by the capture (private.capture_page); read through game_loads and game_flight_pnl. Kept one full calendar month, then archived.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `game_date` | date | The local date at departure, as the loads page shows it |
| `flight_no` | integer | From the loads page, e.g. 1001 (shown as KF 1001); null on a money-only row, since the statement names no flight |
| `origin_code` | text |  |
| `dest_code` | text |  |
| `dep_local` | text | Departure, local clock time as the game shows it, e.g. 07:30 |
| `arr_local` | text | Arrival, local clock time as the game shows it |
| `dep_at` | timestamp with time zone | Scheduled departure, from the local time and the origin's offset (null while the offset isn't known); on a money-only row, the statement time |
| `arr_at` | timestamp with time zone | Scheduled arrival: departure plus the block from the local times (null while an offset isn't known) |
| `posted_at` | timestamp with time zone | The statement's time for the flight, its actual departure, UTC; null on a loads-only row |
| `statement_blk` | smallint | The statement's block number in that minute (game_statement.blk) |
| `statement_routes` | smallint | How many routes the block's lines name; 1 for a normal flight, and only those are matched to loads |
| `route_id` | bigint | The route, by the schedule's leg with that number and direction, else by its airports, either way round, one that isn't removed first (filled by private.fill_flight_links after each statement and loads page since 22 Oct, and filled back that day) |
| `aircraft_id` | bigint | The aircraft, by the registration the loads page or the statement names (filled by private.fill_flight_links after each statement and loads page since 22 Oct, and filled back that day) |
| `registration` | text | The aircraft as the loads page names it |
| `maint_registration` | text | The aircraft named by the statement's maintenance line (only some flights have one): game_flight_pnl.tail |
| `status` | text | As the loads page shows it: finished or inflight so far |
| `eco_pax` | integer |  |
| `eco_seats` | integer |  |
| `eco_fare` | numeric(14,2) | AS$ (bus_fare, fst_fare and cargo_rate likewise) |
| `eco_pct` | smallint | Economy load, percent, as the game shows it (bus_pct, fst_pct and cargo_pct likewise). Stored, not worked out: the game's cargo figure differs from units ÷ capacity on some flights |
| `bus_pax` | integer |  |
| `bus_seats` | integer |  |
| `bus_fare` | numeric(14,2) |  |
| `bus_pct` | smallint |  |
| `fst_pax` | integer |  |
| `fst_seats` | integer |  |
| `fst_fare` | numeric(14,2) |  |
| `fst_pct` | smallint |  |
| `cargo_units` | integer |  |
| `cargo_cap` | integer |  |
| `cargo_rate` | numeric(14,2) |  |
| `cargo_pct` | smallint |  |
| `pax_income` | numeric(14,2) | AS$, from the statement (cargo_income, fuel, onboard, handling, landing, atc and maintenance likewise); null when the block has no such line |
| `cargo_income` | numeric(14,2) |  |
| `fuel` | numeric(14,2) |  |
| `onboard` | numeric(14,2) |  |
| `handling` | numeric(14,2) |  |
| `landing` | numeric(14,2) |  |
| `atc` | numeric(14,2) |  |
| `maintenance` | numeric(14,2) |  |
| `income_total` | numeric(14,2) | Every line of the block on the income side, AS$ |
| `cost_total` | numeric(14,2) | Every line of the block on the cost side, AS$ |
| `profit` | numeric(14,2) | income_total − cost_total, AS$ |
| `statement_pax` | integer | Passengers named on the statement (passenger handling) |
| `loads_captured_at` | timestamp with time zone | When the loads page last wrote the row |
| `money_captured_at` | timestamp with time zone | When the block's newest statement line was first captured |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff read: select for authenticated.

**Triggers:** set_updated_at.

## game_loads

*View.* Today's game_loads, from game_flights: every captured flight with passengers, seats, fares and loads by class and cargo, in the columns the planner (Check: daily load report, growth signals; Review: fare changes) and export_capture() read. Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `flight_date` | date |  |
| `code` | text |  |
| `dep_time` | text |  |
| `tail` | text |  |
| `origin` | text |  |
| `dest` | text |  |
| `arr_time` | text |  |
| `eco` | numeric |  |
| `bus` | numeric |  |
| `fst` | numeric |  |
| `cargo` | numeric |  |
| `status` | text |  |
| `captured_at` | timestamp with time zone |  |
| `eco_pax` | integer |  |
| `eco_seats` | integer |  |
| `eco_fare` | numeric |  |
| `bus_pax` | integer |  |
| `bus_seats` | integer |  |
| `bus_fare` | numeric |  |
| `fst_pax` | integer |  |
| `fst_seats` | integer |  |
| `fst_fare` | numeric |  |
| `cargo_units` | integer |  |
| `cargo_cap` | integer |  |
| `cargo_rate` | numeric |  |

## game_ops_recent

*View.* Each airline's last 24 hours before its latest statement line, as before #13: flights, income, costs and hours, from game_flights and the statement lines the capture couldn't name (game_payments of kind other); salaries, leases, purchases, deposits, cabins and refits are left out. Read by the planner (Review: the group today; the cash forecast's flight profit) and export_capture(). Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `last_ts` | timestamp with time zone |  |
| `flights` | bigint |  |
| `income` | numeric |  |
| `costs` | numeric |  |
| `hours` | numeric |  |

## game_payments

*Table.* Bank-statement lines not tied to a flight: leases, salaries, purchases, deposits, cabins, refits, and lines in a minute with no flight. One row per statement line. Written by the capture (private.fold_statement). Kept for good.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `paid_at` | timestamp with time zone | The statement's time, UTC |
| `kind` | text | lease, salaries, purchase, deposit, cabin (a cabin, or the pilot training that comes with an order, since 15 Oct), refit or other |
| `registration` | text | The aircraft the line names, e.g. from "Leasing rate for B-0161", or since 22 Oct from the game's "Installation of cabin interior (9M-AAV)" |
| `aircraft_id` | bigint | The aircraft: since 22 Oct, a cabin installation's ("Installation of cabin interior (<reg>)"), the airline's aircraft with that registration (private.payment_aircraft()), for the cabin charge check; empty on every other line |
| `descr` | text |  |
| `amount` | numeric(14,2) | AS$ |
| `side` | text | D for a cost, C for income |
| `occ` | integer | Tells apart identical lines posted in the same minute |
| `statement_blk` | smallint | The statement's block number (game_statement.blk), so game_flight_pnl and game_ops_recent count the payments they always counted (salaries) where they always did |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff read: select for authenticated.

**Triggers:** set_updated_at.

## game_pnl

*Table.* The game's income statement per airline and UTC date, for the current, last and total periods, with the figures and capture time of that date's latest capture. Written by the capture (private.capture_page). Not read by any screen yet; kept for reports.

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `captured_on` | date |  |
| `line` | text |  |
| `current_p` | numeric |  |
| `last_p` | numeric |  |
| `total_p` | numeric |  |
| `captured_at` | timestamp with time zone | When the capture that gave the figures was taken (the latest capture that UTC date, since #13 pull request 6) |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `capture_day` | date | The capture day (design §2): the evening of the capture that gave the figures |

**Access:** planner staff read game_pnl: select for authenticated.

## game_scan_airlines

*Table.* Each airline's totals in a world scan (design §3.9; was game_snapshot_airlines): flights, weekly departures and airports, with its airlines row. Kept for good; the full schedule is in game_scan_schedules. Written by capture_scan() and ingest_snapshot() (private.scan_ingest()). Read by export_for_report().

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint | The scan (game_scans) |
| `enterprise_id` | integer | The airline's game ID as the scan read it (airlines.game_id) |
| `name` | text | The airline's name as the scan read it |
| `n_flights` | integer | Flights in its schedule |
| `n_weekly` | integer | Departures a week |
| `n_airports` | integer | Airports it serves |
| `world_id` | bigint |  |
| `airline_id` | bigint | The airline (airlines, by game ID): every airline a scan sees has a row |
| `position` | integer | The order the scan stored the airline in; export_for_report() lists a scan's airlines in it, as it always has |

**Access:** staff read: select for authenticated.

## game_scan_airports

*Table.* Each scanned airport's page in a world scan (design §3.9; was game_snapshot_airports): its details, the airlines stationed there and its news. Kept one month, then archived (#13 pull request 7). Written by capture_scan() and ingest_snapshot() (private.scan_ingest()). Read by export_for_report().

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `airport_code` | text | IATA code |
| `game_airport_id` | integer | The game's ID for the airport |
| `info` | jsonb |  |
| `stations` | jsonb | The airlines stationed there with their departures a week: [{enterprise_id, name, weekly, alliance, interline}] |
| `news` | jsonb |  |
| `world_id` | bigint |  |
| `position` | integer | The order the scan stored the airport in; export_for_report() lists a scan's airports in it, as it always has |

**Access:** staff read: select for authenticated.

## game_scan_schedules

*Table.* Each airline's full schedule in a world scan (design §3.9): one JSON list per airline, each flight as [code, number, from, to, weekdays, departure, arrival, aircraft type, operator]. Kept one month, then archived (#13 pull request 7). Written by capture_scan() and ingest_snapshot() (private.scan_ingest()). Read by export_for_report() and the airport summaries (private.scan_summarise).

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `flights` | jsonb |  |

**Access:** staff read: select for authenticated.

## game_scans

*Table.* One row per world scan (design §3.9; was game_snapshots): when it ran, the week, its status and a note, with its world. Kept for good. Written by capture_scan() (Capture all airlines, when settings.scan_every_days says one is due; since 21 Oct) and by ingest_snapshot() (scripts/scanner/gscan.py, the fallback run by hand), both through private.scan_ingest(). Read by export_for_report() for the weekly report and gander monthly, and by the captured figures (competition(), fare_ladder(), hub_progress()), capture_airlines() and system_status(): only finished scans, but for a stopped one on the Systems board.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `taken_at` | timestamp with time zone |  |
| `week` | text |  |
| `note` | text |  |
| `status` | text | running (being read: the scanner or the capture is sending its pages), done (finished: the only scans the readers use) or stopped (since 22 Oct: left unfinished more than an hour, marked when the next scan starts, with a note of how far it got; private.scan_stop_unfinished()) |
| `world_id` | bigint | The world scanned |

**Access:** staff read: select for authenticated.

## game_statement

*Table.* Bank-statement lines from the capture, as the game lists them. Each line is folded into a flight (flight_id) in game_flights or into game_payments. Kept 14 days for checking once the statement clean-up is switched on (settings.statement_cleanup_enabled; the 10:20 UTC job deletes older lines only once every one is in game_flights or game_payments). Written by the capture (private.capture_page).

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `ts` | timestamp with time zone |  |
| `descr` | text |  |
| `amount` | numeric |  |
| `side` | text | D for a cost, C for income |
| `route` | text |  |
| `pax` | integer |  |
| `captured_at` | timestamp with time zone |  |
| `occ` | integer | Tells apart identical lines posted in the same minute |
| `blk` | integer | Groups the lines of one flight when several flights post in the same minute |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `flight_id` | bigint | The game_flights row the line was folded into; null for a payment (game_payments) |

**Access:** planner staff read game_statement: select for authenticated.

## groups

*Table.* A player's airlines in a world: ours (equinox.) and rival players' groups. owner_user_id is the sign-in account that owns a group of ours.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `name` | text |  |
| `kind` | text | ours or rival |
| `player_name` | text | The player's name in the game |
| `owner_user_id` | uuid | The sign-in account that owns this group (ours only) |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## growth_log

*Table.* Moves logged under the order rotation: big, freq or feeder. Replaces the planner's growthLog.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `logged_on` | date |  |
| `move` | text | big, freq or feeder |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## ingest_secret

*Table.* The shared secret that Claude's scripts send to the export, ingest, script and site-admin functions. To be replaced by proper roles (decision #11).

Never leaves the database: left out of the nightly backup on purpose.

| Column | Type | Notes |
|---|---|---|
| `secret` | text |  |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## interline_agreements

*Table.* Interline status per airline and country: not contacted yet, to sign, signed, declined, or no partner there. Replaces the planner's interline.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `country_code` | text |  |
| `status` | text | to_sign, signed, declined or nopartner; empty = not contacted yet (the planner's record has no status) |
| `partner` | text | The partner as the game names it, e.g. Emirates (41) |
| `partner_airline_id` | bigint | The partner, once it is in airlines |
| `decided_on` | date |  |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## job_runs

*Table.* One row per run of every job (design §3.11): when it started and finished, ok or failed, the day or month it was for, a note and the details. The nightly backup (backup, through the backup_runs view, since #13 pull request 7, with every earlier run moved in), the daily snapshot (snapshot, by the capture; snapshot_fallback, the 10:00 UTC job), the 10:20 UTC clean-ups (cleanup) and the monthly archive (archive, one row per table and month, from the backup job); from #13's pull request 5 to the switch-over, the side by side (adapter_mirror, adapter_check). The planner's Home warns from it. Staff read it; only the database's own functions and postgres write it. Not in the change log.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `job` | text | backup, snapshot, snapshot_fallback, cleanup or archive; adapter_mirror and adapter_check are the old adapter's runs, until the clean-up (build pull request 14) |
| `world_id` | bigint | The world it ran for, if any |
| `started_at` | timestamp with time zone |  |
| `finished_at` | timestamp with time zone |  |
| `status` | text | running, ok, failed or incomplete |
| `for_day` | date | The day it was for: a snapshot's capture day (design §2: 10:00 to 10:00 UTC), or the capture day it ran in |
| `for_month` | date | The month it was for (its first day): an archive's, the month archived |
| `note` | text | What happened, in a line: for a failed comparison, where it differed (paths with list places as [] and keys as {}) |
| `details` | jsonb | What a job records about itself: for backup its kind, tables, rows, files, bytes and the copy's R2 key; for snapshot_fallback the day, whether it took the snapshot, and the missed days it filled; for cleanup what it deleted; for archive the table, rows, checksum, the files in R2 and on the release, and the layout version; for adapter_check the paths that differed (up to 200), why a cash or next-7-day figure wasn't allowed, the allowed differences used and how long it took; for adapter_mirror the rows written |

**Access:** staff read: select for authenticated.

## load_days

*Table.* A load day's flags typed in the planner (whether the day is complete). Replaced the day flags in the old planner_loads.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `game_date` | date |  |
| `done` | boolean | The day is complete |
| `saved_at_ms` | bigint | When the planner saved it, milliseconds since 1970 (UTC) |
| `entered_at` | timestamp with time zone |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## load_entries

*Table.* Economy loads typed by hand, per flight and game date (the planner's Loads by hand, through planner_save()). Replaced the typed part of the old planner_loads.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `game_date` | date | The local date at departure, as the game's loads page shows it |
| `flight_no` | integer |  |
| `eco_pct` | numeric(5,1) | Economy load, percent; null = cleared |
| `entered_at` | timestamp with time zone |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## market_fares

*Table.* Each airline's fares on a page the market pages read, by class (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per read, flight prefix and class (Y, C, F, Cargo), over the flights the page's Current Availability lists (finished yesterday, booked and in flight to about three days ahead): how many flights, the lowest, average and highest price in AS$, how many had finished and how many of those finished with no seat left (sold out; the page shows at most 9 seats left for a rival's passengers, so it is not a load factor). The airline: airlines matched by the flight's prefix where the latest finished world scan's schedules give one airline that prefix, else an airline on the page's share list with that IATA code, else none (airline_id null, the prefix kept). Nothing per flight is stored. Detail: the monthly archive exports and deletes it with its read after a full calendar month. Written only by capture_market() (private.market_ingest()). Staff read it.

| Column | Type | Notes |
|---|---|---|
| `read_id` | bigint | The page it came from (market_reads) |
| `world_id` | bigint | The read's world |
| `airline_code` | text | The flight number's prefix as the page shows it (KL in KL 8) |
| `service_class` | text | The class as the page shows it: Y, C, F or Cargo |
| `airline_id` | bigint | The airline flying it (airlines), by the prefix as the table says; null when no airline could be told by it |
| `flights` | integer | The flights with this prefix and class on the page |
| `price_low` | numeric | The lowest price among them, AS$ |
| `price_avg` | numeric | The average price over them, AS$, to the cent |
| `price_high` | numeric | The highest price among them, AS$ |
| `finished` | integer | Of them, the flights already finished (status finished) |
| `sold_out` | integer | Of the finished ones, those with 0 seats left in the class: sold out |

**Access:** staff read: select for authenticated.

## market_reads

*Table.* Each Market Analysis page a market run read (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one direction of one pair, read with our airline that flies it open (the page's prices and its service profile are that airline's), ok or failed with the error, the week of its market shares and our service profile on the pair. The page itself is never kept (about 290 KB). Its figures are market_fares and market_shares; the pair's weekly seats and price go to market_weeks. Detail: the monthly archive exports and deletes it after a full calendar month, after its fares and shares (private.archive_tables()). Written only by capture_market() (private.market_ingest()); a page sent again in the same run replaces the earlier one. Staff read it.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | The read's own number |
| `run_id` | bigint | The market run (market_runs) |
| `world_id` | bigint | The run's world |
| `airline_id` | bigint | Our airline that flies the pair, open in the game when the page was read (airlines) |
| `origin` | text | The page's origin airport, IATA (the first three letters of /app/com/markets/DUBAMS) |
| `dest` | text | The page's destination airport, IATA |
| `read_at` | timestamp with time zone | When the database stored the page; decides its month for the archive |
| `ok` | boolean | True when the page read; false when it didn't, with the reason in error (no figures then) |
| `error` | text | Why the page didn't read, as the capture sent it; null when it read |
| `share_week` | text | The calendar week the page's Market Shares show, as 2026-44 (the page's 44/2026) |
| `service_code` | text | Our service profile on the pair as the page's settings form shows it selected (On-Board Service, e.g. R); null when none is selected. The pair's setting: a per-flight-number setting the game may hold isn't on this page. Read only; the form is never sent. Since 31 Oct the code's leading token (S2, as the planner writes it); the reads of 30 Oct hold the game's whole name ("S2 (min 800km)"), which the service check reads by its token |
| `service_profile_game_id` | integer | The game's value of that service profile (318 for R on the saved page); null when none is selected |

**Access:** staff read: select for authenticated.

## market_runs

*Table.* One row per run of the market pages (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): Capture all airlines (capture/capture_all.user.js 1.9) reading the game's Market Analysis page of both directions of every pair our airlines fly, once every settings.market_every_days capture days, after the evening's capture and world scan. Status open (pages being sent), done (finished: the runs the readers use) or stopped (left open more than an hour, marked when the next run starts). Kept for good, as game_scans. Written only by capture_market() (private.market_ingest()); read by capture_airlines() (whether the pages are due) and system_status() (the Systems board's market line). Staff read it.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | The run's own number, which the capture sends with each page and the finish |
| `world_id` | bigint | The world read (the capture key's) |
| `started_at` | timestamp with time zone | When the run started (its start call) |
| `finished_at` | timestamp with time zone | When it was finished; null while open or once stopped |
| `status` | text | open (being read: the capture is sending its pages; one started within the hour is carried on), done (finished, with 10% or fewer of its pages failed) or stopped (left open more than an hour; marked by private.market_stop_unfinished() when the next run starts, with a note of how far it got) |
| `pages_expected` | integer | The pages the capture meant to read when it started (both directions of every pair, capture_airlines()'s market_total); null when not sent |
| `pages_read` | integer | Pages read and stored (market_reads ok), kept here when the reads are archived |
| `pages_failed` | integer | Pages that didn't read (market_reads not ok), kept here when the reads are archived |
| `note` | text | The capture's note (its version, the pages and failed at the finish), or how far a stopped run got |
| `capture_version` | text | The capture userscript's version that read it (1.9) |

**Access:** staff read: select for authenticated.

## market_shares

*Table.* Each airline's share of a pair's passengers and cargo, as a page the market pages read shows it (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per read, kind (passengers, cargo) and airline, for the calendar week the page shows, with the change in points against the week before. The game's own share, for one direction of the pair. The airline by the enterprise's game id; one the database didn't know gets an airlines row (change log actor capture), as the world scan does. Detail: the monthly archive exports and deletes it with its read after a full calendar month. Written only by capture_market() (private.market_ingest()). Staff read it.

| Column | Type | Notes |
|---|---|---|
| `read_id` | bigint | The page it came from (market_reads) |
| `world_id` | bigint | The read's world |
| `kind` | text | passengers or cargo (the page's two tables) |
| `airline_id` | bigint | The airline (airlines), by the enterprise's game id in the page's link |
| `week` | text | The calendar week the share is for, as 2026-44 |
| `share_pct` | numeric(6,2) | Its share, % (68.46) |
| `change_pts` | numeric(7,2) | The change against the week before, in points (−10.32); null when the page shows none |

**Access:** staff read: select for authenticated.

## market_weeks

*Table.* A pair's seats offered and price per unit by calendar week, as the market pages read them from each page's Historic Capacities and Prices (since 30 Oct; spec docs/specs/2026-10-30-market-pages.md): one row per world, direction (origin to dest) and week with figures, the latest read winning (a week read again replaces its figures). For every airline on the pair together, as the game gives it. Kept for good: the archive leaves it alone. Written only by capture_market() (private.market_ingest()). Staff read it.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint | The world |
| `origin` | text | The direction's origin airport, IATA |
| `dest` | text | The direction's destination airport, IATA |
| `week` | text | The calendar week, as 2026-44 (the page's period 202644); the current week is so far |
| `seats` | integer | Seats offered that week (the page's capacities) |
| `price_per_unit` | numeric | Price per unit that week, AS$ (the page's prices) |
| `run_id` | bigint | The market run whose read gave the figures (market_runs) |
| `read_at` | timestamp with time zone | When that page was read; a later read of the week wins |

**Access:** staff read: select for authenticated.

## markets

*Table.* Each airline's markets. Since 21 Oct a market keeps only its layout: its default aircraft, default cabin and fares went (spec docs/specs/2026-10-21-cabins-new-rule.md). Since 26 Oct the layout is kept but no longer decides the cabin (manual §5: the cabin by distance). Replaces the planner's ref.markets.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `name` | text | e.g. Transatlantic – dense |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `layout` | text | Since 26 Oct no longer read by the cabin rule (manual §5: the cabin by distance). Was: the cabin layout the market calls for (Standard, Leisure, Leisure Plus or Comfort), taken by a plan card where one route of the market flew more than cabin_route_share_pct of the aircraft's block time. Kept as history; no longer shown or changed in Reference → Markets (#105) |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## monthly_checks

*Table.* When each monthly check was last done, per airline or for the group as a whole (airline_id null). Replaces the planner's monthly.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint | Null = the group as a whole |
| `task` | text | e.g. salaries |
| `last_done_on` | date |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## plan_card_legs

*Table.* A plan card's flights, with the same time rules as flight_legs (UTC). Replaces plans[].legs.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `plan_card_id` | bigint |  |
| `position` | integer | Order on the card |
| `flight_no` | integer |  |
| `origin_code` | text |  |
| `dest_code` | text |  |
| `days_utc` | smallint[] | UTC weekdays it departs, ISO; every day unless set |
| `dep_utc_min` | smallint | Departure, minutes after 00:00 UTC |
| `block_min` | smallint | Block time, minutes |
| `service_code` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## plan_cards

*Table.* A plan for one aircraft's flying, on order or flying, kept after it is filed as the record of what was planned (whether it is filed is worked out, not stored). Replaces the planner's plans.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `aircraft_id` | bigint | The aircraft the card plans, on order or flying |
| `base_code` | text |  |
| `title` | text | e.g. HYD + CKG |
| `note` | text |  |
| `extra` | jsonb | Fields the table doesn't know; the old planner's (the hidden copy of the legs among them) were cleared at the clean-up (build pull request 14). Expected empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `config_id` | bigint | The cabin the aircraft is fitted with, chosen with its routes; filing gives the aircraft this cabin and logs its first fit at its price (null = not chosen yet) |
| `line_id` | bigint | The 7-day line the aircraft flies (plan_lines), or empty for a card of its own |
| `line_day_offset` | smallint | Its place on the line, 0 to 6 (aircraft k of the spec's formula is offset k − 1): it flies line day d on UTC weekday ((d + offset − 1) mod 7) + 1. Set with line_id; one card per line and offset among aircraft that aren't retired |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, plan_line_slot, set_updated_at.

## plan_line_legs

*Table.* A line's flights in flying order, with the same time rules as plan_card_legs (UTC): each departs on its line day, and the aircraft at offset k flies line day d on UTC weekday ((d + k − 1) mod 7) + 1 (the library's card.fromLine). One of the planner tables.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `line_id` | bigint | The line (plan_lines) |
| `position` | integer | Order on the line, as it is flown, from 1 |
| `line_day` | smallint | The line day it departs on, 1 to 7: the UTC weekday on the card of the aircraft at offset 0 |
| `flight_no` | integer | Flight number, the same every day it operates |
| `origin_code` | text | Where it leaves from |
| `dest_code` | text | Where it lands |
| `dep_utc_min` | smallint | Departure, minutes after 00:00 UTC on its line day |
| `block_min` | smallint | Block time, minutes |
| `service_code` | text | Service code: S1, S2, …, or Ryanair's R |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## plan_lines

*Table.* A 7-day rotating line (manual §4, long haul in lines; spec docs/specs/2026-10-27-long-haul-lines.md §2): 7 aircraft of one type at one airline fly one weekly pattern, each a day apart, so every flight on it operates daily at the same time. Its legs are plan_line_legs; each aircraft's plan card names the line and its offset (plan_cards.line_id, line_day_offset). Its size is settings.line_aircraft (7). Written by the Scheduling chat from optimise-line's answer (scripts/README.md). One of the planner tables.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint | The airline whose aircraft fly the line |
| `aircraft_type_id` | bigint | The aircraft type every aircraft on the line is |
| `name` | text | What the planner calls it, e.g. "XLR line JFK 1"; unique within the airline |
| `note` | text | Anything worth keeping about the line; empty for none |
| `optimiser_answer` | jsonb | The optimise-line answer the line came from, whole (the run's settings, search and best line with its 7 cards), kept as the record of the run; the legs are plan_line_legs, not this. Empty for a line built by hand |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## planner_scripts

*Table.* Copies of Claude's scripts from before the repository existed. The repository is now the source (decision #1). Written by save_script(). Read by export_repo_bootstrap().

| Column | Type | Notes |
|---|---|---|
| `name` | text |  |
| `content` | text |  |
| `updated_at` | timestamp with time zone |  |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## planner_users

*Table.* Email addresses allowed into the planner (staff). Read by is_planner_user() and auto_confirm_planner_user().

| Column | Type | Notes |
|---|---|---|
| `email` | text |  |

**Access:** planner users see themselves: select for authenticated.

## report_access

*Table.* The password hash for the investor page and investor reports. Read by site_investor() and site_report().

Never leaves the database: left out of the nightly backup on purpose.

| Column | Type | Notes |
|---|---|---|
| `pass_hash` | text |  |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## rotations

*Table.* An aircraft's out-and-back pair on a route: what the old planner calls a frequency. Its flights are in flight_legs. Replaces the planner's freqs.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `route_id` | bigint |  |
| `legacy_key` | text | The old planner's frequency id, e.g. z5qbaeg, by which Routes names a frequency; new ones get one too |
| `service_code` | text | On-board service, e.g. S3 |
| `fare_pct` | numeric(5,1) | Fare, percent of standard (100; Ryanair 85) |
| `launched_on` | date |  |
| `note` | text |  |
| `extra` | jsonb | Fields the table doesn't know: the old planner's SLF figures (slfOut, slfBack), which Routes edits and the flights export lists. Expected otherwise empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** check_route_legs, log_change, set_updated_at.

## route_days

*Table.* The daily history per route, direction and UTC day (design §3.10, §7): each airline's flights, passengers, seats, money and average economy fare, from game_flights (a flight's day is the UTC date it departs), kept for good after game_flights is archived. Recomputed for the snapshot's day and the two before; filled back from 6 Oct. Not in the change log. Staff read it; only the database writes it.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `route_id` | bigint | The route: the day's flights' (game_flights.route_id, linked before the snapshot writes the day since 22 Oct), else the airline's route on the airports, either way round, one that isn't removed first (filled back 22 Oct); set to null if the route row is deleted later (the airports keep the history) |
| `origin_code` | text |  |
| `dest_code` | text |  |
| `day` | date | The UTC date the flights departed |
| `flights` | integer | Flights (game_flights rows with loads or passenger income) |
| `passengers` | integer | From the loads page, or the statement's count where the loads weren't captured |
| `seats` | integer | Seats on the flights whose loads were captured; null when none were |
| `revenue` | numeric(14,2) | AS$, from the statement (costs and profit likewise; profit = revenue − costs) |
| `costs` | numeric(14,2) |  |
| `profit` | numeric(14,2) |  |
| `eco_fare_avg` | numeric(14,2) | Average economy fare, AS$, weighted by economy passengers |
| `eco_pax` | integer | Economy passengers on the flights whose loads were captured (game_flights.eco_pax); null when none were. Since 22 Oct, filled back to the first day game_flights held (6 Oct) |
| `eco_seats` | integer | Economy seats on the flights whose loads were captured, as seats is; null when none were |
| `bus_pax` | integer | Business passengers on the flights whose loads were captured; null when none had business (the economy-only layouts) |
| `bus_seats` | integer | Business seats on the flights whose loads were captured, as seats is; null when none had business |
| `bus_fare_avg` | numeric(14,2) | Average business fare, AS$, weighted by business passengers (as eco_fare_avg), from the flights with business seats; null with none |
| `block_min` | integer | The flights' scheduled block, minutes: arr_at − dep_at summed over the flights that have both (game_flights); null when none has. Hours flown, for profit per aircraft hour (route_story()) |

**Access:** staff read: select for authenticated.

## routes

*Table.* Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner's overrides (null = the research value; research refreshes never touch them). Replaces planner_data.routes, routesAdded, routeEdits and routeCabin. The research's own figures are kept in step by planner_data_set().

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `hub_code` | text | Where the route starts: the airline's hub or focus city |
| `dest_code` | text |  |
| `city` | text | A label, e.g. Shanghai (Pudong) |
| `country_label` | text | The country as the research gave it: a name or a code |
| `distance_km` | integer |  |
| `market_id` | bigint |  |
| `stars` | smallint | The research's rating |
| `source` | text | research or added (in the planner) |
| `removed` | boolean | Taken off the airline's list |
| `removed_note` | text |  |
| `city_override` | text | Typed in the planner; null = the research value |
| `distance_override_km` | integer | Typed in the planner; null = the research value |
| `market_override_id` | bigint | Chosen in the planner; null = the research value, or no market when market_cleared |
| `stars_override` | smallint | The game's passenger demand as stars (manual §3, since 22 Oct), or typed in the planner; null = the research value |
| `cabin_choice` | text | Since 26 Oct no longer used by the cabin rule (manual §5: distance alone decides). Was: the route's own cabin layout, which won over its market's. Kept as history |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `market_cleared` | boolean | The planner's route edit clears the market (its market ""): the route has no market, whatever the research says. market_override_id is then empty |
| `edit_kept` | boolean | The planner keeps an edit for this route that changes nothing (routeEdits {}, as restoring a removed route leaves it) |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** check_route_legs, log_change, set_updated_at.

## scan_airline_airports

*Table.* Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and airport, its departures a week from there and how many destinations it flies to from there. Built from the scan's schedules when it finishes (private.scan_summarise); filled for every scan stored before 11 Oct.

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `airport_code` | text |  |
| `weekly_departures` | integer | Departures a week from the airport |
| `destinations` | integer | Distinct airports it flies to from there |

**Access:** staff read: select for authenticated.

## scan_airline_fleet

*Table.* Each airline's fleet by aircraft type in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §3): one row per scan, airline and type as its overview page's Fleet table shows it (/app/info/enterprises/<game id>), every enterprise the scan lists, flying or not. Kept for good, with the scan summaries (the monthly archive leaves it alone). Written by capture_scan() (Capture all airlines 1.8) and ingest_snapshot() (scripts/scanner/gscan.py, the fallback), kind fleet, through private.scan_ingest(); a later read in the same scan replaces the airline's rows. Read by competition() (private.scan_fleet(), private.scan_order_flags()). RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `type_name` | text | The aircraft type as the page names it (the link's text), e.g. Airbus A321XLR |
| `game_type_id` | integer | The game's id for the type (the link's aircraftsType?id=) |
| `owned` | integer | Aircraft of the type it owns |
| `leased` | integer | Aircraft of the type it leases |
| `overall` | integer | Aircraft of the type in its fleet (owned and leased) |
| `leased_out` | integer | Aircraft of the type it leases out to others |
| `on_offer` | integer | Aircraft of the type it offers for sale or lease |
| `on_order` | integer | Aircraft of the type on order, not yet delivered |
| `avg_age_years` | numeric(5,1) | The average age of the type's aircraft, years (the page's Ø age, "0.1 yrs") |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## scan_airline_markets

*Table.* Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and market (the weekly report's market names, e.g. Transatlantic, Intra-Europe), its passenger departures a week and city pairs. Sent by the weekly report's script (scripts/report/analyze.py, which owns the market definitions) through ingest_snapshot() kind markets, replacing that scan's earlier ones; scripts/report/scan_markets.py fills past scans.

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `market` | text | The weekly report's market name |
| `weekly_departures` | integer | Passenger departures a week in the market (freighters left out, as the report counts them) |
| `city_pairs` | integer | Distinct city pairs (either direction) it flies in the market |

**Access:** staff read: select for authenticated.

## scan_airline_profile

*Table.* Each airline's overview page in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §3): one row per scan and airline read, with the Fleet table's totals (fleet_size, on_order, avg_age_years, from its tfoot) and the page's General Information and General statistics, or read_ok false with the reason in note when the page didn't read (a failed page never stops the scan). Kept for good, with the scan summaries. Written by capture_scan() and ingest_snapshot(), kind fleet, through private.scan_ingest(). Read by competition() (each rival's fleet and the order flags) and system_status() (the fleet pages the latest scan read). RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `fleet_size` | integer | Aircraft in its fleet: the Fleet table's overall total (the page's Fleet size when the table has no totals) |
| `on_order` | integer | Aircraft on order: the Fleet table's on order total |
| `avg_age_years` | numeric(5,1) | Its fleet's average age, years (the totals' Ø age) |
| `stations` | integer | Stations (General statistics) |
| `staff` | integer | Staff (General statistics) |
| `passengers` | bigint | Transported passengers, since it was founded (General statistics) |
| `alliance` | text | Its alliance's name (General Information), null when in none |
| `parent_game_id` | integer | Its parent company's game (enterprise) id (General Information), null when it has none |
| `founded` | date | The day it was founded in the game (General Information) |
| `read_ok` | boolean | True when the page read; false when it didn't, with the reason in note (no other figures then) |
| `note` | text | Why the page didn't read, as the capture or gscan.py sent it |
| `read_at` | timestamp with time zone | When the database stored the page |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## scan_pair_airlines

*Table.* Each airline's departures a week on every city pair in the world, from the week's kept world scan, kept for good (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §1, §2): the first finished scan of the world on or after each Saturday (UTC date), written by private.scan_pairs_keep() at the scan's finish, and filled back once from the scans still holding their schedules. One row per kept scan, airline (ours included, for our share), pair (a, b, the codes in order) and kind (passenger or not). So a route's rivals reach back past the monthly archive: route_story() reads it for a scan whose schedules have gone (weekly points). The monthly archive leaves it alone. RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint | The week's kept scan (game_scans) |
| `world_id` | bigint | The scan's world |
| `airline_id` | bigint | The airline flying the pair in the scan, any airline of the world, ours included |
| `a` | text | The pair's first airport, in code order |
| `b` | text | The pair's second airport, in code order |
| `weekly_a_to_b` | integer | Departures a week from a to b in the scan's schedule (each flight's days counted, as gscan.py counts n_weekly) |
| `weekly_b_to_a` | integer | Departures a week from b to a |
| `passenger` | boolean | True for passenger flights, false for freighters (private.scan_passenger()); route_story() reads the passenger rows, as it reads the schedules |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## scan_rival_connections

*Table.* Rivals' one-stop connections on our city pairs in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §1, §2): one row per scan, rival, direction (origin to dest) and connecting airport (via), worked out from the scan's schedules by private.scan_connections() when the scan finishes. A rival's flight origin→via joined to its own flights via→dest on the same day (the next where the first lands after midnight local), from the connecting airport's minimum connection time (world_airports.mct_min, 90 minutes where unknown) to connection_max_wait_h after it lands, both legs together at most rival_connection_detour_max times the direct distance; passenger flights only, our airlines left out; kept only for pairs any of our airlines flies or has on its route list, either way round. Detail: the monthly archive exports and deletes it with the scan schedules after a full calendar month (private.archive_tables()). Read by competition() and route_story(). RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint | The rival (an airline that isn't one of ours) whose two flights connect |
| `origin` | text | Where the first flight leaves: one end of our pair |
| `dest` | text | Where the second flight lands: the pair's other end |
| `via` | text | The connecting airport, where the first flight lands and the second leaves |
| `weekly_departures` | integer | Departures a week from origin that connect onward to dest through via: each first flight once on each day any onward flight connects, so the figure sits beside direct departures on the same scale (never added to them) |
| `best_gap_min` | integer | The shortest gap at via between landing and the onward departure, minutes (local times at via) |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## scan_rival_connections_week

*Table.* Rivals' connecting departures on our city pairs by scan, kept for good (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §2): one row per scan, rival and pair (airport_a, airport_b, the codes in order), each direction's total and both, and the top 3 connecting airports; written with scan_rival_connections by private.scan_connections(), and its rows mark the scans whose connections were worked out (competition() and route_story() show none for a scan without). The monthly archive leaves it alone. RLS on with no rule: no access for anon or authenticated, read through functions (manual §1).

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint | The rival whose connections these are |
| `airport_a` | text | The pair's first airport, in code order |
| `airport_b` | text | The pair's second airport, in code order |
| `weekly_a_to_b` | integer | Connecting departures a week from airport_a to airport_b |
| `weekly_b_to_a` | integer | Connecting departures a week from airport_b to airport_a |
| `weekly_departures` | integer | Both directions together |
| `vias` | jsonb | The top 3 connecting airports, [{via, weekly}], biggest first |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## service_profiles

*Table.* On-board service by distance (S1, S2, …). airline_id null means every airline without its own. Replaces the planner's ref.services.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `code` | text | S1, S2, …; unique in a world, except a blank one (the planner's S5 for a new row, or empty), which may repeat |
| `up_to_km` | integer | Used for routes up to this distance |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## settings

*Table.* Our own planning choices as data (decision #14): the manual's rule numbers, thresholds and display choices for a world, with per-airline overrides.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint | Null = the whole world; set = that airline's override |
| `key` | text |  |
| `value` | jsonb |  |
| `unit` | text |  |
| `description` | text |  |
| `since` | date | When the rule started |
| `reason` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## site_content

*Table.* Website content kept as data, one row per key: media (destination photos and airline logos), airport_cities (since 15 Oct: name, the name the website gives an airport, and photo, the city whose photo an airport without its own takes; the website and the planner's Photos screen read them through site_public(), where each kept them in its code before), markets, and mct (minimum connection times, also used by the schedule optimiser; since #13's pull request 8 site_admin() writes them to world_airports too, and site_public() reads them from there; this copy is kept for the planner's Reference, which shows it). Written by site_admin() and the planner's Photos screen. Read by site_public() and site_investor().

| Column | Type | Notes |
|---|---|---|
| `key` | text |  |
| `value` | jsonb |  |
| `updated_at` | timestamp with time zone |  |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## site_posts

*Table.* Newsroom posts on the website. Written by site_admin(). Read by site_public().

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `slug` | text |  |
| `published_at` | timestamp with time zone |  |
| `title` | text |  |
| `summary` | text |  |
| `body` | text |  |
| `tag` | text |  |
| `airline` | text |  |
| `image` | text |  |
| `image_credit` | text |  |
| `auto` | boolean |  |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## site_reports

*Table.* Investor reports and gander monthly issues, each with its status (upcoming or published) and its PDF. Written by site_admin(). Read by site_public() (the list), site_report() (investor PDFs, with the password) and site_newsletter() (published issues).

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `kind` | text |  |
| `period` | text |  |
| `title` | text |  |
| `summary` | text |  |
| `published_at` | timestamp with time zone |  |
| `status` | text |  |
| `pdf_b64` | text | The PDF, base64-encoded |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## spending_log

*Table.* Money spent, in AS$: aircraft orders, cabins and refits, losses. Replaces the planner's capex. Read by site_investor() and, since 22 Oct, cabin_charges() (each first cabin fit against the game's charge; Systems → Cabin charges' Use the game's amount changes a fit's amount through planner_save()).

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `spent_on` | date |  |
| `amount` | numeric(14,2) | AS$ |
| `kind` | text | order, cabin or loss |
| `aircraft_id` | bigint |  |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## todo_items

*Table.* A to-do's steps, in order. Replaces todos[].items.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `todo_id` | bigint |  |
| `position` | integer | Order in the to-do |
| `body` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## todos

*Table.* The planner's To-do board. created_at is the item's own creation time. Replaces the planner's todos.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `legacy_key` | text | The old planner's to-do id, the to-do's key on Home and in a dismissal (todo|<id>); new to-dos get one too |
| `title` | text |  |
| `due_on` | date |  |
| `done` | boolean |  |
| `done_at` | timestamp with time zone |  |
| `note` | text |  |
| `extra` | jsonb | Fields the table doesn't know; the old planner's were cleared at the clean-up (build pull request 14). Expected empty |
| `created_at` | timestamp with time zone | When the to-do was made (its own time, not the row's) |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## world_airports

*Table.* What a world says about an airport, only where there is something to say: minimum connection time, night ban, a corrected UTC offset, closure. An airport's offset in a world is coalesce(utc_offset_override, airports.utc_offset). Replaces site_content.mct, ref.hubs[].mct, ref.curfews and ref.utcOverrides. Connection times are written by the planner (a hub's) and by site_admin() (the whole map), and read by site_public() as content.mct.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `airport_code` | text |  |
| `game_airport_id` | integer | The game's own airport ID |
| `mct_min` | smallint | Minimum connection time, minutes |
| `night_ban_from` | time without time zone | Night ban start, local clock time |
| `night_ban_to` | time without time zone | Night ban end, local clock time |
| `utc_offset_override` | numeric(4,2) | A correction to airports.utc_offset for this world, in hours |
| `closed` | boolean | The airport is closed in this world (e.g. PNH) |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## world_rules

*Table.* The world's own rules as data (decision #14): house rules, game settings, and whether #12's items (interlines between our airlines, the capture's salary step, the world scanner, the schedule check) are allowed there.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `key` | text |  |
| `value` | jsonb |  |
| `kind` | text | house, game or permission |
| `unit` | text |  |
| `description` | text |  |
| `since` | date | When the rule started |
| `source` | text | Where the rule comes from |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## worlds

*Table.* One row per AirlineSim world we play in (decision #14). Gander is the only one; is_default marks the world the planner and the website show. Every planner table carries its world_id.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `name` | text |  |
| `game_host` | text | The world's address, e.g. gander.airlinesim.aero |
| `kind` | text | exclusive, long_term or short_term |
| `started_on` | date |  |
| `ended_on` | date |  |
| `is_default` | boolean | The world the planner and the website show; at most one |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## Functions

*Runs as owner* means the function can do what its caller couldn't do directly, so it checks permission itself.

| Function | Returns | Who can call it | What it does |
|---|---|---|---|
| `aircraft_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Each aircraft's flight profit a day over the last p_days (decision #19, design §8; routeProfit's aircraft): its average captured flight × its scheduled flights a day, plus its statement lines with no route spread over the days captured, its lease a day (the last leasing payment the events page lists for it ÷ 7) and the net, with its type and routes, most profitable after lease first. Money in millions of AS$. Staff only; runs as owner and checks the caller itself. |
| `airline_cards(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Performance's scorecards and Today's orders: a card for each of our active airlines in a world (the default world when null), in display order (decision #19, design §8; the old planner's finStats, renderFinance and fcNext): profit a day over the last 7 days of reported cash (an early read over fewer, early true), per aircraft, return on fleet a week, an aircraft pays back in and funds a new aircraft every (days), fleet, on order, flights a day and how many more than a week ago, average load over 7 days, next_order and can_order_now (cash_forecast()); and group_today (groupOverviewHtml): per airline cash, flight profit a day, this week's leases and week-end closing per day (each, and together), net, and aircraft arrived but not yet flying with their leases a day (group_today_shown once any airline has flight profit). No group totals (manual §1). Money in millions of AS$. And the group's average economy load over 7 days, the old Home's key figure (avgLF): load_7_days, the average of every flight the loads pages captured departing from 7 days before p_as_of's UTC date on (one per airline, date and flight number), with load_7_days_flights and load_7_days_from captures; with none captured, every flight the last 7 days' load reports cover (route_loads()), from reports; with neither, null. Staff only; runs as owner and checks the caller itself. |
| `airline_profit(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Profit for each day between captures for one airline (decision #19, design §8; the old planner's finSeries, finStats, capexIn and dayOps): each reported cash date (the capture's balance rounded to 0.01M, or a figure typed in cash_entries) with the change in cash plus that period's order payments (orders and cabins; losses stay in profit), per day over the days between, the aircraft, flights and average load flown that day, and the profit a day per aircraft flying that day (per_aircraft_day, #18 build pull request 10); with the 7-day profit a day. Money in millions of AS$. Staff only; runs as owner and checks the caller itself. |
| `as_num(p text)` | numeric | anon, authenticated | Turns game text such as 1,234.5 AS$ into a number (null when there is none). |
| `auto_confirm_planner_user()` | trigger | internal only · runs as owner | Trigger on sign-up: confirms the email straight away when it is on planner_users. |
| `cabin_charges(p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The cabin charge check (spec docs/specs/2026-10-21-tidy-ups.md §3; manual §4: filing fits the plan card's cabin and logs its first fit at its price), in the default world, as of p_as_of (now by default), using only what was recorded by then: each first cabin fit logged from settings.cabin_charge_check_from on (2026-10-18, check_from: the first day the plan card chose the cabin; earlier fits include refits), from spending_log (kind cabin, note "<reg> first cabin fit (<config>)"), against the game's installation lines for its registration in its airline from that day on (game_payments kind cabin, "Installation of cabin interior (<reg>)"; pilot training, the same kind, left out; a credit counts against). counts: checked, matches (one line at the logged amount, to the dollar: counted, not listed), differs (one line at another amount), charged_twice (more than one line), not_charged (no line, and the airline's latest captured statement line more than 2 days after the day it was logged), waiting (no line yet, within those 2 days), not_logged (a registration with installation lines and no first fit logged on any day) and problems. problems: every one that isn't a match or waiting, by airline (our order), then differs, charged twice, not charged yet and not logged, each with its state, airline_id, code, airline, registration, aircraft_id, logged (the spending_log row: id, spent_on, amount, config and updated_at, which a change to its amount is made from; null when not logged), lines (each game line: id, paid_at UTC, amount, descr), game_amount and difference (game less logged, AS$) where there is one line. latest_statement: each airline's latest captured statement line. Today lists one item when there are problems, and Systems → Cabin charges lists them, with Use the game's amount on a differing one. Staff only; runs as owner and checks the caller itself. Read with GET. |
| `capture_airlines(p_key text)` | jsonb | anon, authenticated · runs as owner | For the capture userscript, with the capture key: the key's world and its active airlines of our groups (game ID, name, code), in display order, so the userscript doesn't keep its own list. Since 21 Oct also the world scan (private.capture_scan_plan(), spec docs/specs/2026-10-21-scan-in-capture.md): scan_every_days, scan_due, scan_open, scan_latest and scan_airports, so the capture scans the world after our airlines when one is due. A wrong or missing key gets {"ok": false, "error": "bad key"}. Since 30 Oct also the market pages (private.capture_market_plan(), spec docs/specs/2026-10-30-market-pages.md): market_every_days, market_due, market_open, market_latest, market_total, market_done and market_pages, airline by airline, so the capture reads them after the world scan when they're due. |
| `capture_eval_result(p_key text, p_run bigint, p_doc jsonb)` | jsonb | anon, authenticated · runs as owner | For the aircraft evaluation script (capture/aircraft_eval.user.js; spec docs/specs/2026-10-27-aircraft-evaluation-script.md), with the capture key: saves one run's result. p_doc is {from_name, to_name, settings: {age, class, seat, price_factor}, rows: [{type_name, game_type_id, can_operate, message, flights_week, seats, fuel, handling, atc, landing, maintenance, capital, crew, fixed_total, per_seat, profit_50 to profit_100, margin_50 to margin_100, cells}]}. Refuses, saving nothing ({"ok": false, "error": why}): a wrong key, a run not on the key's world's list, no route names, a seat other than the run's, a row without its type, a type twice, no row for one of settings.aircraft_eval_types, a figure that isn't a number for a type that can operate, or any figure for one that can't. Saves rows for extra types too. Replaces any earlier result for the run (saving twice is no harm), writes the run's from_name, to_name, settings and done_at, and answers {ok, run, saved (rows), done, total}. Runs as owner with an empty search path, callable signed out and signed in, as capture_fare_actions(). |
| `capture_eval_runs(p_key text)` | jsonb | anon, authenticated · runs as owner | For the aircraft evaluation script (capture/aircraft_eval.user.js; spec docs/specs/2026-10-27-aircraft-evaluation-script.md), with the capture key: the runs of the key's world without a result (aircraft_eval_runs, done_at null) in pass, then seq order, each {id, pass, seq, from, to, seat}; types, the world's settings.aircraft_eval_types (the tool's names of the types every run compares); total, the runs on the list, and done, those with a result. {ok, world, types, total, done, runs}. A wrong or missing key gets {"ok": false, "error": "bad key"}, a world without the setting {"ok": false, "error": "no aircraft_eval_types setting in this world"}. Read only; runs as owner with an empty search path, callable signed out and signed in, as capture_fare_actions(). |
| `capture_fare_actions(p_key text)` | jsonb | anon, authenticated · runs as owner | For the fares userscript (capture/fares_apply.user.js; manual §5, since 21 Oct; specs docs/specs/2026-10-21-fares-userscript.md and docs/specs/2026-10-21-frequencies-and-fares.md §3), with the capture key: the game's Ticket price adjustments still to make. For each active airline of our groups in the key's world, in display order (as capture_airlines()), its fare_ladder() actions that set a route back to its level (fix true: they need no fare plan row, and the index matching again is the proof), and those whose route is on the fare plan this week and not yet seen in the captures (every class the action names is a route row of the action's direction, since 26 Oct, with planned true and applied false), in fare_ladder()'s order (the set-back changes first). airlines: each airline's game_id, name (the website's, else the planner's), game_name, code, count of actions and fixes (how many of them set a route back); actions: each with game_id and airline (its name), n (the action's number in fare_ladder()), route (HUB–DEST), from and to (IATA), level (% of the default price), sign (+ or -) and pct (the game's percent, a whole number), classes (economy and/or business), plan_ids (the fare plan rows, one per class in the same order; none for a set-back change), fix and reason (a set-back's, "captured fare at 100%, level 110%") and text (the action in words); week_of (this Saturday) and as_of. A wrong or missing key gets {"ok": false, "error": "bad key"} and nothing else. Runs as owner with an empty search path and its own statement limit of 30 seconds (it works out every airline's fare ladder in one call, signed out). |
| `capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)` | jsonb | anon, authenticated · runs as owner | Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game's ID or, from older userscripts, by name, and refuses one outside the key's world; keeps the raw page (the 10:20 UTC clean-up deletes it after 14 days), parses it (private.capture_store, private.capture_page): bank statement into game_flights and game_payments, loads into game_flights, and since 22 Oct a fleet page (kind fleet, Capture all airlines 1.6) into game_fleet; and checks it (#21: the verdict under verdict). After the loads page, rows holds the capture panel's words (what was read, and the airline's verdict: "all good" or what came in short or broken) and count the rows read. Answers with the capture day and whether it is complete; the page that completes the world's capture for the day also takes the daily snapshot (airline_days, route_days) and answers with it. Fleet pages take no part in completeness or the snapshot. |
| `capture_market(p_key text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | The market pages in Capture all airlines (capture/capture_all.user.js 1.9; spec docs/specs/2026-10-30-market-pages.md), with the capture key: kinds start, page and finish (private.market_ingest()), in the key's world. start answers {ok, run_id, carried_on}: a run of the world left open more than an hour is marked stopped first (private.market_stop_unfinished()), and an open run started within the hour (private.market_open()) is carried on instead of starting another (one start at a time per world); page answers {ok, run_id, read_id, fares, shares, weeks, pages_read, pages_failed}; finish {ok, run_id, pages_read, pages_failed}, refused while more than 10% of the run's pages failed. A wrong or missing key gets {"ok": false, "error": "bad key"}, an unknown kind {"ok": false, "error": "bad kind"}, and a payload that doesn't read {"ok": false, "error": ...}, writing nothing. Never takes a page's HTML: the capture sends only the figures. Every airline a page's share list names gets an airlines row (change log actor capture, detail capture_market). Runs as owner with an empty search path, 30 seconds at most and each call planned afresh, as export_for_report(). |
| `capture_scan(p_key text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | The world scan in Capture all airlines (capture/capture_all.user.js 1.5, 1.8 with the fleet pages; spec docs/specs/2026-10-21-scan-in-capture.md; manual §7), with the capture key: kinds start, airline, airport, fleet (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §2: an airline's overview page, its fleet by type and its general figures, or its error) and finish, with the payloads scripts/scanner/gscan.py sends ingest_snapshot(), stored exactly as ingest_snapshot() stores them (private.scan_ingest()), in the key's world. start answers {ok, snapshot_id, carried_on}: an unfinished scan of the world started within the hour (private.scan_open()) is carried on instead of starting another (one start at a time per world); the other kinds answer {ok, snapshot_id} (fleet with read_ok and rows) and take only a scan of the key's world. A wrong or missing key gets {"ok": false, "error": "bad key"}, an unknown kind {"ok": false, "error": "bad kind"}, and a payload that doesn't read {"ok": false, "error": ...}, writing nothing. Every airline the scan sees gets an airlines row (change log actor capture, detail capture_scan). Runs as owner with an empty search path. |
| `capture_status(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | What the capture collected for each of our airlines in a world (the default world when null; decision #19, design §8; the old planner's captureBoard): for today and yesterday (UTC dates of p_as_of), when each page kind (loads, statement, events, pnl, balance) last came, how many flights the loads page held for each date (flight numbers, by departure date as the game lists them), which kinds are missing today, and complete, missing or not captured; each airline's latest verdicts (#21), and since 22 Oct its fleet pages (fleet: their verdict, note, time, pages, ok pages and aircraft) when that capture day has some. Moments in UTC. Staff only; runs as owner and checks the caller itself. |
| `cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Cash, next 14 days, and when an airline can order (manual §3; decision #19, design §8; the old planner's cashForecast, flightsPerDay, leaseM, orderNow and fcNext). From the airline's latest balance captured in the 7 days to p_as_of (cash, cash_at): flight profit a day (profit a flight over the last 24 hours of the bank statement × planned flights a day; status missing with fewer than 5 flights, no capture without a balance); every payment the events page lists for the 14 days after the capture, each in the first week repeated a week later beyond what the game lists (payments, repeat true), at the airline's home airport (its main base); the balance at each payment and on each of the 14 days (points), the lowest point and the payment that makes it; for each type the airline may buy (airline_aircraft_types) its price with the cabin it would get, its weekly lease (the highest leasing payment seen for the type, else lease_estimate_pct of its price) and the first day it can be ordered keeping order_cushion in hand with its own lease from 7 days after it is ordered (safe_day 0 to 14, or null; count_today: how many at once today, up to 9); can_order_now and next_order. p_orders, a list of {"type" or "aircraft_type_id", "count"}: whether ordering them all now stays safe, each with its own lease, and the lowest point after (orders_tested). Money in millions of AS$, moments in UTC. Staff only; runs as owner and checks the caller itself. |
| `cash_log(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Systems → Manual entry's nightly log and its cash entry form for our active airlines in a world (the default world when null), in display order (#18 build pull request 10; the old planner's finSeries, applyCaptureCash and cashEntryHtml): per airline each reported date (airline_profit()'s, the first included) with its cash and its fixed costs for the next 7 days as the old planner shows them (for a capture day in the 7 days to p_as_of's UTC date, the events' payments in the 7 days after that day's latest balance, when there are any; otherwise a typed figure, else the capture's, above zero only); and for today (p_as_of's UTC date) the figures a typed one is saved against: shown (the form's), stored (what the tables give the old planner: a typed figure, else the capture's rounded to 0.01M), captured (capture_cash rounded) and the typed row (cash_entries: cash and fixed_next7 in AS$, updated_at) when there is one. Money in millions of AS$ unless named. Staff only; runs as owner and checks the caller itself. |
| `competition(p_airline_id bigint, p_as_of timestamp with time zone, p_limit integer)` | jsonb | authenticated · runs as owner | Competition analysis for one airline (manual §3, market share first; spec docs/specs/2026-10-21-competition-analysis.md §1), as of p_as_of, from the world scans. scans: latest (the latest finished scan by then that still has its schedules), week_before (the latest at least 6 days older, else the oldest there is; null with one scan) and previous (the latest before latest), each with id and taken_at (UTC). group: our airlines' passenger departures a week against the world's (every airline's schedule in the scan, freighters left out by private.scan_passenger(), the weekly report's rule) and our share, now, in the week-before scan and the change. Freighters are no one's rivals anywhere here: market share, threats, the openings' rivals and the profiles count passenger flights only. markets: each of the airline's markets (its routes not removed, flown or not, by market; No market for routes with none) with its city pairs (either direction) and how many it flies, ours (the airline's live legs, both ways), ours_before (its flights in the week-before scan), every rival's (every airline in the scan that isn't one of ours) departures a week on the same pairs from the latest scan (rivals, rivals_before), our share (ours over ours and the rivals', percent) and its change, and the top 5 rivals with their departures, change and share; biggest first. threats: private.competition_threats(), each with the rival, the route as the airline flies it, kind (started or added), then, added, now and ours, the scan's day (on), until (7 days on), latest (shown by the latest scan) and words ("Air China started on PVG–CAN, 14 a week"). openings: each pair on the airline's list (routes not removed; one route each, from the main hub first) that no airline of ours flies either way, with its stars, distance, the rivals flying it and their departures a week in the latest scan (both ways), the variant from the default line (manual §3: the smallest size the stars allow (1–2 small, 3 small or mid, 4 small to large, 5 mid or large; small up to 150 seats, mid 200, large 300, wide above), bigger only for reach (for_reach), the cheapest per seat whose range_km covers the distance, among the types the airline may buy (airline_aircraft_types); beyond every narrowbody the A350 cheapest per seat (the A350-900), beyond settings.a350_1000_from_km (since 27 Oct; wide_full_cabin_km under settings) the one with the most seats (the A350-1000); an opening no type reaches is left out and counted in openings_left_out), and hubs first (allowed, allowed_by and the reason when it isn't: from the main hub always; from another base while the main hub is under hub_first_departures only if a rival has over contested_rival_weekly departures a week there (scan_airline_airports) or over contested_rival_daily a day from it to the destination; hub_first_exempt allows all). Ranked by stars, then rivals' departures a week on the pair, then the shorter distance, then the route's code, those hubs first doesn't allow after the allowed ones; the top p_limit (50 by default; openings_count and openings_allowed count them all). From settings.trunk_month_from to trunk_month_to (1 to 30 November 2026, manual §4; trunk_month gives on, from and to): each trunk (a pair between two of our bases, any of our airlines' hubs and focus cities in airline_bases) is marked trunk, allowed with allowed_by 'November trunk' (hubs first suspended for trunks), never left out for reach (the world's types when none the airline may buy reaches, variant.own false), and the trunks come first, shortest first, then the other openings as always (openings_trunks counts them); outside those days trunk is false and nothing changes. other_lists: our other airlines that have the pair on their own list (one airline per city pair, manual §2, decides). profiles: the 10 rivals who fly most of the airline's city pairs (latest scan), each with its passenger departures a week (latest and week before), its airports and its 3 biggest by passenger departures, from its schedule, and the pairs shared with their departures and ours. competitors (since 22 Oct; manual §7, the weekly report; spec docs/specs/2026-10-21-report-three-competitors.md): the three rivals with the most departures a week on the city pairs the airline flies (its live legs, both ways) in the latest scan, ties by name, each with rank, airline_id, name, on_pairs (its departures a week on those pairs), pairs (how many of them it flies), weekly and airports (its whole passenger network in the latest scan), weekly_before (in the week-before scan; null when that scan holds no schedule for it), change and change_pct (against weekly_before, a number and a percent to one decimal); empty without a scan. self: the airline on the same terms from the same scans' schedules (on_pairs, pairs, weekly, airports, weekly_before, change, change_pct), with pairs_flown (how many pairs its live legs fly) and its code and name; null without a scan. hubs_first, settings and notes say what was used. Staff only; runs as owner and checks the caller itself. Read with GET. Stations (since 22 Oct; manual §2 and §3 hubs first; spec docs/specs/2026-10-22-station-role.md): a station (airline_bases.role station) is no base, so a pair with a station end is never a trunk and a station is never a contested base; an opening from one of the airline's stations is listed and ranked like any other, and hubs first allows it only once the main hub reaches hub_first_departures (reason "hubs first: stations wait for DEL's 750"), contested or not; hub_first_exempt still allows all. Fleets (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §4): each competitor and each rival profile has fleet, from its overview page in the latest scan (scan_airline_fleet, scan_airline_profile, through private.scan_fleet()): overall, on_order, avg_age_years, types_count and types (its 5 biggest by overall, each with on_order), and overall_before, on_order_before, overall_change and on_order_change against the week-before scan (null when either scan didn't read its page); fleet is null when the latest scan didn't read it. order_flags (private.scan_order_flags()): the same world-wide list in every airline's answer, every airline in the latest scan that isn't one of ours, freighter-only airlines left out (private.scan_passenger()), with aircraft on order at least settings.rival_orders_flag_pct of its fleet and at least rival_orders_flag_min (kind orders), or on order and no flights in the scan (kind starting); each with airline_id, name, kind, fleet, on_order, share (percent of its fleet), weekly (its departures a week in the scan), on_order_change and fleet_change against the week-before scan, on_pairs (it flies one of this airline's city pairs), at_bases (it departs from one of its hubs or focus cities), meets (either) and words; biggest share first. No flag feeds the openings, the contested test or the fare pause. Connecting (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): each rival's one-stop departures a week on the airline's city pairs in the latest scan, from scan_rival_connections (private.scan_connections(), at the scan's finish: same airline, from the connecting airport's minimum connection time to connection_max_wait_h, both legs together at most rival_connection_detour_max times the direct distance, each first flight once). Each market has connecting_weekly and connecting_via (its top 3 connecting airports); each opening connecting_weekly, connecting_via and connecting (each rival's, with its airports); each rival profile and each competitor connecting_weekly, connecting_pairs and connecting_via. Shown beside direct, never added: total, share, rivals_weekly, on_pairs, the three biggest competitors (still chosen by direct departures), the openings' order, the contested test, hubs first, the threats and the fare pause are as without them. The fields are absent when the latest scan has no connections worked out. Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §4, §5): each market has game_share, the game's own passenger share from the market pages (share, share_before, change, pairs_read of pairs, seats, week, run_id, read_at; the airline's share on each direction of the market's pairs read in the latest finished market run, weighted by the direction's seats offered in the latest week read), beside the scan's departures share and never replacing it; null when none of its pairs has been read. market_run is that run (id, started_at, finished_at; null with none), and contested lists each city pair the airline flies where a rival has at least as many departures a week as ours in the latest scan (pair, route_id, hub, dest, ours, rival_id, rival, rival_weekly), with market: each way our economy fare against the cheapest rival's and the game's passenger share this week and last (private.fig_market_pair(); null without a read). |
| `export_capture(p_secret text, p_days integer)` | jsonb | anon, authenticated · runs as owner | Exports recent capture data for Claude's scripts, exactly as before #13: profit per flight, loads, payments ahead, cash, the last 24 hours and capture runs, from the compatibility views. Needs the ingest secret. |
| `export_for_report(p_secret text, p_kind text, p_arg text)` | jsonb | anon, authenticated · runs as owner | Exports for the weekly report, gander monthly, the airline briefing and the planning library: the world scans (snapshots), a scan's airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19, and since 22 Oct competition()'s competitors, self and scans, the weekly report's three biggest competitors); and one airline's briefing rows (kind briefing, p_arg {"airline": its id, code or name, "as_of", "world"}, the airline required: its deliveries with their plan cards and legs, open to-dos of the airline and the group, fare_plan_status(), each route's fare level from fare_ladder() (since 21 Oct), competition()'s threats and top 20 openings (since 21 Oct) and route_loads() for it, private.briefing_doc(), #24; read only). Kind planner (the old planner's documents) is refused since the clean-up (build pull request 14). Needs the ingest secret. Since 23 Oct (spec docs/specs/2026-10-23-rival-fleets.md) kind figures also gives each airline competition()'s order_flags and each competitor's fleet, and the scan kinds take fleet (an airline's overview page) through ingest_snapshot(). Since 23 Oct (spec docs/specs/2026-10-23-rival-connections.md) kind figures also gives each competitor its connecting departures on the airline's pairs (connecting_weekly, connecting_pairs, connecting_via), beside direct and never added to it. Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §5) figures also carry, per airline, contested (competition()'s contested pairs with rivals' fares and the game's passenger share each way, from the latest market run) and market_run. |
| `export_repo_bootstrap(p_secret text)` | jsonb | anon, authenticated · runs as owner | Exported the stored scripts when the repository was created (decision #1). Needs the ingest secret. |
| `fare_changes(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Economy fare changes seen in an airline's captures (decision #19, design §8; routeProfit's fare changes): for each route flown in the last 9 days, each date whose average captured economy fare is more than 1% from the date before, with both fares and the economy load the day before and after, newest first. Staff only; runs as owner and checks the caller itself. |
| `fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md, docs/specs/2026-10-21-fare-actions-by-route.md, docs/specs/2026-10-21-frequencies-and-fares.md and docs/specs/2026-10-21-competition-analysis.md §2, and since 23 Oct docs/specs/2026-10-23-fare-ladder-under-launch.md, judged by loads since 26 Oct): this Saturday's move for each route, cabin and direction (since 26 Oct, spec docs/specs/2026-10-26-fare-ladder-per-direction.md), the changes that set a direction back to its level, and the game actions that make them. routes: one row per route, cabin and direction (out from the route's hub, then back to it; direction, and from and to, its airports that way round), for each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin's load at 100%), the sold-out share, the average load (load) and the average fare over those 7 days, that direction's flights only (game_flights, matched to the route either way round); its level as a % of the game's default price (the latest the fare plan recorded before this Saturday for that direction, or for both directions (direction null) if that is later, else settings.fare_launch_pct) and steps above launch; the fare index: each flight of the latest captured day (latest_on, its average latest_fare) against its direction's baseline, times the launch level, the baseline being the direction's fare on the latest captured day on or before 21 Oct 2026, when every route was at its launch level (Gitesh), or for a route launched later its first captured fare if captured in its first growth_new_route_days days (a day's fare: its flights' lowest, else route_days' average fare in that cabin, eco_fare_avg and, since 22 Oct, bus_fare_avg on a day with business passengers, so a baseline survives the flights' archiving in both cabins; baseline_fare and baseline_on, the directions' average and latest day); fare_index the flights' average, index_matches false when any flight is more than 1 point off the level the game should show (this week's new level once the captures see it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, for fare_ladder_hold_weeks after a recorded step down, and since 26 Oct for fare_ladder_up_hold_weeks after a recorded step up (a fare plan row with ladder_move up; a revert, a jump or a set-back never starts it; "held after a step up on 26 Oct"; held both ways, the more recent move's reason), while the newest rotation is under fare_ladder_capacity_hold_days old on a route older than that (a flight added: "judged at its new size from ..."; a frequency taken away isn't tracked, its rotation is deleted), and, since 21 Oct, while a rival threatens the pair (private.competition_threats(), as competition() lists them: a rival who started there or added competition_threat_min_weekly departures a week in a scan of the 7 days before the moment; "rival Air China started here on 22 Oct: paused until 29 Oct", the one paused longest), checked after planned, new, few, held (either hold) and added and before the sold-out share; never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes; fix, a change that sets it back to its level (index_matches false, not on the fare plan this week, not a new route, and captured since its newest rotation launched), with fix_reason ("captured fare at 100%, level 110%"). moves, to_plan and planned count the rows (directions), off_level the directions set back. actions: the Ticket price adjustments (baseline default price), route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): first the set-back changes (fix true, with the reason), then the week's moves, each in the rows' order (hub, dest, out before back), one action per direction (From and To its airports; since 26 Oct) with classes ["economy","business"] when both cabins go to the same level, otherwise one for each cabin, economy first; a direction whose levels don't change gets no action. Each action has n, route, classes, from, to, level, sign, pct, baseline, fix, reason (a set-back's) and text, the text in the game's words naming the classes. settings: the numbers used, with capacity_hold_days, up_hold_weeks (since 26 Oct) and baseline_day. notes: how the index reads. Since 23 Oct, under launch: a cabin at launch never jumped whose ladder result is to hold at launch (under fare_ladder_down_share sold out), with at least fare_under_launch_min_flights flights in the fare_under_launch_days before the moment, all at launch (no level change recorded in them), averaging under fare_under_launch_load_pct full, jumps to the first of fare_under_launch_levels (move down, ladder_kind jump; "41% full over 14 days at launch: to 80% for 2 weeks"); fewer flights, it waits, saying how many. It holds fare_under_launch_days from the day the captures saw the jump (fare_plan_status()'s rule, else the day proposed; "at 80% since 25 Oct: judged on 8 Nov"). Since 26 Oct (spec docs/specs/2026-10-26-under-launch-by-loads.md) it is then judged on the week's loads as any direction, with the same minimum departures, step and holds: sold out, it steps up (a normal up, so the hold after a step up applies) and carries on through launch to the cap; fare_ladder_down_share to 99% sold out, it holds; under fare_ladder_down_share sold out, at the first jump level it jumps to the next ("at 80% since 12 Jan: sold out 0 of 7: to 60% for 2 weeks") and holds as before; at the last level it holds there with decide true ("at 60% since 5 Jan: sold out 0 of 7: holds at 60%; cut or keep? (Saturday review)"), a hold Put on the fare plan writes once, after which the cabin stays marked (decide true, whatever holds it) until it climbs. No revenue test and no revert since 26 Oct (settings.fare_under_launch_decide_load_pct is no longer read). A step recorded after the latest jump, a revert recorded before 26 Oct, or a cabin back at launch marks it done: no more jumps. Under launch, the ladder only climbs or holds ("under launch: climbs or holds only"). Each route row has ladder_kind (up, down, hold or jump: what Put on the fare plan writes as ladder_move; revert only for a row on the fare plan recorded before 26 Oct), under_launch (state launch, holding, due or done; window_load and window_flights, the 14 days at launch or the flights since the latest jump; jumped_on and judge_on, where they apply) and decide; moves counts jumps and decisions too; settings.under_launch the numbers used. Staff only; runs as owner and checks the caller itself. Per direction (since 26 Oct): each direction's level, move, the hold after a step down (and since 26 Oct after a step up, spec docs/specs/2026-10-26-fare-ladder-hold-after-step-up.md), under launch's jumps (window, launch baseline and judgement on that direction's flights) and the set-back are its own; a new route, the capacity hold after a new frequency, the rival pause and whether the pair is contested (the 60% floor) are the whole route's, given on both its directions' rows. |
| `fare_plan_status(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Performance's fare plan for one airline (#18 build pull request 10, Review's until 20 Oct; the old planner's routeFares and farePlanStatus), from the fares and loads its captures give for each of its routes, both directions (the last 9 days' loads, one per date and flight number): plan, each fare change not dropped (fare_plan, by id) with its row's fields and updated_at, the fare now (the latest captured day's average), the target (fare then × (1 + change)), applied and seen_on and the average load before and after that day. A fare test (no level_pct) is read in economy and seen on the first captured day on or after it was proposed whose average fare shows at least half the change; a fare ladder's row (level_pct and ladder_move, since 21 Oct, manual §5) is read in its own cabin (business on flights with business seats) and seen when the day's average fare is the fare then times (1 + change), within 1%. And fares: each route's latest captured day with its average economy fare (what "+ fare plan" starts from). Since 26 Oct a row with a direction (out from the route's hub, back to it) is read and seen on that direction's flights only, and plan gives each row's direction (null for both). Staff only; runs as owner and checks the caller itself. |
| `fleet_checks(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The fleet checks (spec docs/specs/2026-10-22-fleet-capture.md §2; manual §7), in a world (the default when null), as of p_as_of (now by default), from the latest night's game_fleet for our airlines (night: the latest capture day any of them has, captured by the moment). problems, worst first (maintenance, crew, cabin, not in the planner, not in the game, then since 22 Oct replace and age; then by airline and registration), each with its kind, airline, registration, base (the planner's, else the fleet's), aircraft and words: maintenance, the game's maintenance under settings.maintenance_min_pct (100; an airline's own where it has one), with the condition beside it ("N003AW (JFK): maintenance 0.0%, condition 83%"); crew, pilots no; cabin, seats Y/C/F that don't match the aircraft's cabin in the planner (aircraft.cabin_config_id, cabin_configs' economy and business seats, first class 0), or no cabin in the planner; not_in_planner, a registration on the game's fleet pages that no aircraft row of the airline has; not_in_game, an active aircraft of ours missing from that night's fleet pages, only when every fleet page of its airline's latest run that night came in ok. Since 22 Oct (spec docs/specs/2026-10-22-aircraft-age-check.md; manual §3, replacement by age): replace, an aircraft within settings.replace_warn_days (60) of its replacement age by the game's age (age_years >= replace_at_years - replace_warn_days / 365.25; replace_at_years is settings.replace_new_years, 3, for one marked new in aircraft.acquired, replace_used_years, 10, for one marked used): "N001AW (JFK): replace at 3 years (now 2.9): order its replacement", and once at or past it "N001AW (JFK): past its replacement age (3 years, now 3.0)"; age, the cross-check, an aircraft marked new that is older in the game than its time with us (the night less its delivery_at) by more than 0.2 years: "N023AW (JFK): looks used (3.6 years in the game), marked new" (none without a delivery_at). counts: each kind's and problems in all. airlines: each of ours with its maintenance limit, its latest run's pages (read, ok, expected, all_ok), when its fleet was read and its aircraft that night (registration, planner aircraft, base, fleet, type, nickname, location, flight, age, since 22 Oct acquired (new or used) and replace_at_years, condition, maintenance, seats, pilots, owned, contract, captured_at and its problems). Staff only, read with GET; runs as owner with its own 30 second limit, as the other figures. |
| `growth_signals(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Performance's growth signals and Today's routes to fix, across our airlines in a world (the default world when null; decision #19, design §8; the old planner's capSignalsHtml and patterns): from route_profit() and aircraft_profit() over growth_window_days, ready for another flight (mark add, by profit a week), raise fares (by flights), fix or reduce (losing or fix, by profit a flight) and aircraft losing money after their lease (by net); and the load patterns: each route's departures over the load window (load_window_days, ending two days ahead, leaving out each rotation's first load_leeway_days) by load band, marked cut, watch, add or hold from the pattern_* settings. profit_captured: whether any bank-statement line was posted since midnight UTC 8 days before p_as_of (the old Home lists the routes the load patterns mark cut when none was). Staff only; runs as owner and checks the caller itself. |
| `hub_progress(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Hubs first (manual §3; decision #19, design §8; the old planner's hubProgressHtml): for each of our active airlines in a world (the default world when null), its main hub's departures a week flying and those on plan cards of aircraft not yet filed, against hub_first_departures, and whether it is exempt (hub_first_exempt); and for each of its other bases, from the latest world scan by p_as_of, the busiest rival there and whether it is contested: a rival with more than contested_rival_weekly departures a week at the base, or more than contested_rival_daily a day on a route from it (listed). Staff only; runs as owner and checks the caller itself. Stations (since 22 Oct, manual §2: airline_bases.role station) are no bases: they are never listed or read as contested. |
| `ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Receives the world scanner's results (start, airlines, airports, finish) into game_scans, game_scan_airlines, game_scan_schedules and game_scan_airports; finish builds the scan's airport summaries. Kind markets takes the weekly report's market summaries for a scan (scan_airline_markets), and since 23 Oct kind fleet an airline's overview page (scan_airline_fleet, scan_airline_profile; spec docs/specs/2026-10-23-rival-fleets.md). Every airline a scan sees gets an airlines row (change log actor script). Same kinds, payloads and answers as before #13; a start scans the default world. Since 21 Oct the work is private.scan_ingest(), which the evening capture's scan (capture_scan()) shares; this stays for scripts/scanner/gscan.py, the fallback run by hand. Needs the ingest secret. |
| `is_planner_user()` | boolean | authenticated · runs as owner | True when the signed-in email is on planner_users. Used by the access rules, the planner and the Photos functions. |
| `loads_by_day(p_world_id bigint, p_from date, p_to date)` | jsonb | authenticated · runs as owner | The loads days from p_from to p_to (at most 62 days apart) in a world (the default when null), as the planner's Loads by hand reads them (#18 build pull request 14; until then through planner_loads_get()): {date: {done, f: {"Airline|flight": economy %}, source: capture when a capture reached the day, savedAt: when it was last saved by hand (ms), entries: the typed load_entries rows with their updated_at, flags: the load_days row or null}}. The loads and the complete mark by the captured figures' rules as of now (private.fig_load_values(), private.fig_load_days()): a typed figure wins where it is newer than the day's capture. A day with nothing captured or typed isn't there. Staff only; runs as owner. |
| `market_service_checks(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The service check (since 30 Oct; spec docs/specs/2026-10-30-market-pages-planner.md §3), a captured figure: for each pair and direction read in the latest finished market run (the game's Market Analysis pages, capture 1.9), our service profile in the game (market_reads.service_code) against (a) the code the route's distance calls for (manual §4: S1 under 800 km, S2 800 to 1,500, S3 over 1,500, Ryanair R; from service_profiles as the planning library reads them) and (b) the service codes of the planner's legs that way (the route's rotations). A row for every mismatch, the game against the distance first, then the game against the planner: the pair, direction, airline, the game's code, the distance's code and the planner's codes, with the route to link to (private.fig_market_service_checks()). p_airline_id: one airline's pairs, or every airline's in the default world when null. With no finished run (none read yet), run is null and mismatches empty. Read by Today (needs attention's Service in the game), the Systems board's market line and the route page's header. Staff only; runs as owner and checks the caller itself, 30 seconds at most and each call planned afresh, as the other captured figures. Read with GET. The game's code is compared by its leading token (since 31 Oct: "S2 (min 800km)" is S2). |
| `order_cabin(p_airline_id bigint, p_type_id bigint)` | jsonb | authenticated · runs as owner | The cabin layout an order of a type comes with for an airline (decision #18, build pull request 7; private.fig_order_cabin(), since 15 Oct the data Reference changes: the airline's own in airline_order_cabins, else the type's aircraft_types.order_config_id, filled from the old planner's DEFAULT_CABIN): {id, code, cabin, cost, aircraft_type_id}, or null when there is none. The planner doesn't call it: filing takes the plan card's cabin, else the aircraft's order_config_id. Staff only; runs as owner and checks the caller itself. |
| `parse_capture(p_id bigint)` | jsonb | internal only · runs as owner | Retired by #13 (pull request 3): the parsing is private.capture_page(), which this now calls. No longer callable by signed-in accounts once 20261009230100_capture_data_removals.sql has run; kept until #18. |
| `planner_data_set(p_secret text, p_key text, p_value jsonb)` | jsonb | anon, authenticated · runs as owner | Writes the route research (key DATA: routes, coords, utc, countries) to the countries, airports and routes tables, only the rows that change (private.research_apply(); change log actor script unless the caller named itself), and answers what changed under tables. Any other key is refused: the old planner's planner_data went with it at the clean-up (build pull request 14). Needs the ingest secret. |
| `planner_save(p_changes jsonb, p_client text)` | jsonb | authenticated · runs as owner | The new planner's one way to write (decision #18, design §6): one call per action, with every row it changes, as a list of {table, op (insert, update or delete), key (the primary key, e.g. {"id": 812}), base (the row's updated_at as loaded; needed for an update or delete), values (the columns to set)}. An insert may name the row it makes (as: a name), and a later change in the same call may take a column's value from that row's key (from: {column: name}), so a to-do and its steps are one action. All or nothing: if any row to update or delete was changed or removed since it was loaded, nothing is written and the answer is {ok: false, clashes: [{table, key, current (the row now, or null if it's gone)}]}; otherwise {ok: true, rows: [{table, op, key, updated_at}]}, inserts included. Only the 35 planner tables the change log covers (airline_order_cabins since 15 Oct, plan_lines and plan_line_legs since 28 Oct), and only their own columns; their checks still apply. Written as actor planner with p_client (the tab's ID) as the detail. Staff only; runs as owner and checks the caller itself. |
| `route_loads(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Each route's and each flight's economy loads over the last 7 days for our airlines in a world (the default world when null; decision #19, design §9: Home's map and Routes' loads; the old planner's loadStats): every flight each day's load report covers on the 7 days to p_as_of's UTC date (from and to), done days only, on a captured day only the flights the capture has a load for, none before its rotation's launch, a flight without a load counting as 97.5%: departures, their sum and average, how many at 95% or more (or not reported), under 95, under 85 and under 70, and the days seen. routes: by route, in airline position, hub and destination order; flights (#18 build pull request 6, the Routes screen's lines): the same by airline and flight number, in airline position and number order. Staff only; runs as owner and checks the caller itself. |
| `route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Each route's profit over the last p_days (1, 3 or 7; decision #19, design §8; the old planner's routeProfit): every bank-statement block with one route, matched to the nearest loads row of that route departing within 31 minutes, grouped by the route as the airline has it: flights, profit, income, margin, profit a flight and a week (× flights a week planned), average economy, business and cargo load and economy fare, departures sold out and their share, and the mark (add a flight, raise fares, fix or reduce, losing money, hold) from the growth_* settings, with why; plus how many flights, how many matched to loads, blocks with several routes (mixed), and the average flight's income and costs, with their sums, its profit and its margin (#18 build pull request 10, the old rpCost). Money in millions of AS$. Staff only; runs as owner and checks the caller itself. |
| `route_story(p_route_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | A route's story since launch (spec docs/specs/2026-10-21-route-page.md §2), as of p_as_of: the planner's route page (/planner/performance/<code>/<route>), and the Scheduling chat's "how has this route done since launch, and what changed on it". The route is its airline's hub and destination; both directions are counted together. route: id, hub, dest, pair, city, stars, distance_km (overrides applied), market (id, name, layout), removed, airline (id, code, name), launched (its earliest rotation's launch day, as route profit and the fare ladder find a route's age, else its first day in route_days; launched_from rotation or history; launched_days). now: departures a week each way from the live schedule (out from the hub, back), rotations, the aircraft types flying it with how many aircraft, fares (fare_ladder()'s rows for the route, since 26 Oct one per direction and cabin, out before back and economy first, each with direction, from and to: level, steps, this Saturday's move, new_level, reason, planned, applied, to_plan, fix, fare_index and the rest), launch_pct and week_of. latest_day: the airline's latest day in the daily history by the moment. days: one row per UTC day with flights, from launch or the last 90 days if longer to latest_day (route_days, both directions; rows of no route matched by the airports): flights, passengers, seats, load_pct (passengers on the flights whose loads were captured ÷ their seats), eco_ and bus_ passengers, seats and load_pct, eco_fare and bus_fare (weighted by passengers), revenue, costs and profit (millions of AS$), block_hours and profit_per_hour (profit ÷ block hours). weeks: the same in 7-day blocks ending on latest_day (from, to, days with flights), newest first, at most 13. events, newest first, each with day, kind and words: launched; frequency added, frequency removed, aircraft changed and retimed from change_log on rotations and flight_legs (one per save, its txid; a save's rotations that are the launch itself and a migration's changes left out); fare, each fare_plan row (cabin, level or change_pct, move, dropped, and since 26 Oct its direction, named first in its words, "out: economy up to 105%"); rival, a rival that started on the pair or added settings.competition_threat_min_weekly departures a week between consecutive finished scans since launch with their schedules (private.scan_pair_flights(), passenger flights only, as competition_threats()). rivals: from the latest finished scan (scan) with the week-before scan (week_before, as competition() picks it), every rival flying the pair either way with its departures a week, before and change; ours (the live schedule, both ways), rivals_weekly and our share; ours_before, rivals_before and share_before (the airline's flights in the week-before scan, as competition()'s me_then); shares, our share at each finished scan since launch (scan_id, taken_at, ours, rivals, share). scans: latest, week_before and since_launch with their dates. notes say how it reads. Staff only; runs as owner and checks the caller itself. Read with GET. Connecting (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): in rivals, each rival on the pair has connecting_weekly and connecting_via (its one-stop departures a week on the pair in the latest scan, both ways, and its top 3 connecting airports), beside weekly and never added to it, rivals_weekly or the share; rivals also has connecting_weekly (every rival's), connecting_only (the rivals with no direct flight that connect) and connecting_scans (each rival's connecting departures and airports at each scan read that has them worked out). Absent when the latest scan has none worked out. Weekly points (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §3): a scan whose schedules the monthly archive has taken is read from scan_pair_airlines (the week's kept scan, kept for good; passenger rows), the same figures, and marked weekly true in rivals.shares, scans.since_launch and the scan refs; rivals.weekly_points counts them and rivals.daily_from is the first point read from full schedules. Connections only on the scans with their schedules. No cabin (since 26 Oct, manual §5): the route's layout is its distance's, worked out by the planner with the planning library (card.cabinRange), and a change to routes.cabin_choice is no event. Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §2) also: days_by_direction (each UTC day and direction, out from the hub and back to it: flights, eco_ and bus_ passengers, seats and load_pct, from route_days, the same days as days); rivals.history (at each scan in rivals.shares: scan_id, taken_at, weekly, and airlines, each airline's direct departures a week on the pair, this airline with ours true and every rival, passenger flights only, none with 0); market (null when neither direction of the pair has been read; else run, the latest finished market run read, out and back, each direction's latest page read in a finished run by the moment: from, to, read_id, run_id, read_at, week, service_code, service_profile_game_id, read_by, fares (market_fares by airline and class: airline_id, code, name, ours, class, flights, low, avg, high, finished, sold_out; ours first) and shares (market_shares, passengers: airline_id, name, ours, share, change, before), or null; and weeks, the pair's seats and price_per_unit by calendar week, both directions, from market_weeks). |
| `rules_input(p_world_id bigint, p_routes text)` | jsonb | authenticated · runs as owner | Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world's values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats and, since 28 Oct, reach: range_km, for the line optimiser); cabin_configs (code, type, seats and, since 21 Oct, the layout's name, cabin); every airport any route, leg or base uses (position, country and its region, UTC offset with the world's correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name, whether low cost: is_lcc), each with its settings as they apply to it (its own overrides in place of the world's values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren't removed (distance and market with any override applied, and since 21 Oct the market's layout, market_layout, and the route's own cabin_choice, for the plan card's cabin); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg; and service_profiles (code, airline or none for the shared ones, up to km), for the plan card's service check (#18 build pull request 10). p_routes: all (the default) or flown, the new planner's lighter start (#18, design §5): only the routes that have rotations, and only the airports they, the legs, the bases and the aircraft use; the rest of the document is the same. The new planner (flown), the scripts (export_for_report('rules'), all) and Claude's command (node lib/rules/dist/cli.js) build the library's Rules object from it. Staff only; runs as owner and checks the caller itself. |
| `save_script(p_secret text, p_name text, p_content text)` | jsonb | anon, authenticated · runs as owner | Stores a copy of a script in planner_scripts, from before the repository existed. Needs the ingest secret. |
| `site_admin(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Publishes website content: newsroom posts, reports and site content. Content mct (minimum connection times, {airport code: minutes}) also sets world_airports, which site_public() reads (private.world_mct_set(); change log actor script unless the caller named itself); site_content.mct is kept too (the planner's Reference shows it). Needs the ingest secret. |
| `site_investor(p_password text)` | jsonb | anon, authenticated · runs as owner | The investor page's data, when the password matches report_access: cash and next-7-day costs by date and airline in millions (the capture's figure unless typed by hand in cash_entries, as the planner rounds them), money spent from spending_log, markets from site_content, and the investor reports list. Runs as owner. |
| `site_newsletter(p_id bigint)` | jsonb | anon, authenticated · runs as owner | A published gander monthly issue, with its PDF. |
| `site_public()` | jsonb | anon, authenticated · runs as owner | Everything the public website shows, in one call: hubs and focus cities an airline flies from, aircraft flying (status active, in the order they were added, as the planner's Tails lists them, since the clean-up), the week's frequencies (local times), signed interlines, posts, the reports list, site_content (photos, logos, and since 15 Oct the airports' website names and city photos, content.airport_cities), the minimum connection times (content.mct) and the longest wait for a connection (content.connection_max_wait_h, hours, from settings; the trip search's window with the planning library, #19), built from the tables (#13, pull request 8), plus our airlines (names, codes, colours, the website's text, display order) from airlines. updated_at: when the planner's data last changed (the latest change in the change log for the world, or to airports and countries). No bank or transfer times, cabin layouts or aircraft on order (6 Oct). Anyone may call it; runs as owner. Since 22 Oct hubs leaves stations out (airline_bases.role station, manual §2), so the website never shows one as a hub and the trip search never connects through one. |
| `site_remove_airline_logo(p_airline text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: goes back to the in-game logo for an airline. Staff only. |
| `site_remove_airport_photo(p_code text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: removes a destination photo. Staff only. |
| `site_report(p_id bigint, p_password text)` | jsonb | anon, authenticated · runs as owner | One investor report with its PDF, when the password matches report_access. |
| `site_set_airline_logo(p_airline text, p_url text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets an airline's logo after the upload, for one of our airlines in airlines (by the planner's name for it). Staff only. |
| `site_set_airport_photo(p_code text, p_url text, p_credit text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets a destination photo and its credit after the upload. Staff only. |
| `system_status(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The Systems board at the top of the planner's Systems screen (#23; Check's until 20 Oct), read only, as of p_as_of (now by default) in a world (the default when null): capture, each airline's latest page and verdicts (capture_status()'s airlines); snapshot, the latest day in airline_days with how it was taken (source capture, or fallback and so incomplete), the latest snapshot job and when the 10:00 UTC job last ran; backup, its latest run and latest good copy (restore check passed) with its size; archive, its runs this month, its latest run and any table and month whose latest run failed; cleanup, its latest run; scan, the latest world scan with its airport summary; scan_stopped (since 22 Oct, spec docs/specs/2026-10-21-tidy-ups.md §1), the latest scan after the latest finished one that stopped part-way (marked stopped, or left unfinished over an hour, which nothing carries on), with its id, taken_at, status, note and private.scan_progress() (airlines and airports read, and what the finished scan before it read), or null; usage, the database's size, the report PDFs in site_reports (three quarters of their base64 text) and the size of site_public(), each with its trigger (manual §1: 350 MB, 50 MB, 500 KB), measured now. The board marks them. Staff only; runs as owner. Since 23 Oct (spec docs/specs/2026-10-23-rival-fleets.md §5) scan also has fleet_pages and fleet_failed: the overview pages the latest scan read and failed (scan_airline_profile). Since 30 Oct (spec docs/specs/2026-10-30-market-pages.md) also market: the latest finished market run started by p_as_of, with its id, started_at, finished_at, age_days, pages_read, pages_failed and note, or null. |

## Internal functions

In the `private` schema, which the data API doesn't expose (#13): trigger functions and helpers that only the database itself and postgres use.

| Function | Returns | Who can call it | What it does |
|---|---|---|---|
| `private.airport_offset_min(p_world_id bigint, p_code text)` | integer | internal only | An airport's UTC offset in a world, in minutes: coalesce(world_airports.utc_offset_override, airports.utc_offset). Null while it isn't known (the airports are loaded by #13's pull request 4). |
| `private.archive_check_args(p_month date, p_table text)` | void | internal only | Refuses a table the archive may not touch, or a month not given as its first day. Used by every archive function. |
| `private.archive_checksum(p_month date, p_table text, OUT rows bigint, OUT checksum text)` | record | internal only | A table's month: its row count and the md5 of every row as Postgres prints it (timezone UTC, ISO dates), joined by newlines, in primary-key order. |
| `private.archive_delete(p_month date, p_table text, p_expected_count bigint, p_checksum text)` | jsonb | internal only | The guarded delete (design §7), the only way the archive removes rows: refuses a table not listed, a month inside the kept window, a count or checksum that no longer matches, for game_flights a month whose flights aren't all in route_days or that statement lines still point at, and (since 30 Oct) for market_reads a month whose reads market_fares or market_shares still point at, naming every reason in one refusal. Otherwise deletes exactly those rows (checked again as they go), records the run in job_runs (job archive, for_month) and answers with what it deleted and the row's id. Locks the table against writes while it works. postgres only. |
| `private.archive_due(p_as_of date)` | TABLE(table_name text, month date, rows bigint) | internal only | What the monthly archive has to do (design §7): each table's months older than its kept window that still have rows, with their row counts, oldest first; within a month market_reads comes after the other tables (since 30 Oct: its fares and shares point at it, so they go first). Called by the archive step in equinox-backups every night (it runs on the first night on or after the 1st, and again each night until nothing is due). p_as_of: the day, default today in UTC (for the checks). postgres only. |
| `private.archive_kept_from(p_table text, p_as_of date)` | date | internal only | The first month a table still keeps on a day (design §7): everything before it may be archived. For one month kept, on any day of December it is November, so October may go. |
| `private.archive_manifest(p_month date, p_table text)` | jsonb | internal only | The manifest the archive step stores beside a table's month (design §7): row count, checksum (private.archive_checksum), the table's layout (columns and types) and the latest migration version, whether the month is due, and the export query. postgres only. |
| `private.archive_order(p_table text, p_as text)` | text | internal only | A table's primary key as an order for the archive, text columns in byte order (collate "C"), so the order and the checksum are the same on any database. |
| `private.archive_select(p_month date, p_table text)` | text | internal only | The query the archive step (equinox-backups) exports a table's month with, in the same transaction as the manifest: every column, in primary-key order. postgres only. |
| `private.archive_tables()` | TABLE(table_name text, month_of text, keep_months integer) | internal only | The tables the monthly archive may delete from (design §7), what decides a row's month, and how many full calendar months each keeps: game_flights, game_events, game_scan_schedules, game_scan_airports, (since 23 Oct, spec docs/specs/2026-10-23-rival-connections.md §2) scan_rival_connections and (since 30 Oct, spec docs/specs/2026-10-30-market-pages.md) market_reads, market_fares and market_shares one; change_log 12. |
| `private.archive_where(p_month date, p_table text, p_as text)` | text | internal only | A table's month as a condition on the table under an alias: one rule for the manifest, the export and the delete. game_flights by dep_at in UTC (by the game's date where dep_at isn't known, as the daily history counts it), game_events by event_date, the scan tables (game_scan_schedules, game_scan_airports and since 23 Oct scan_rival_connections) by their scan's time, market_reads by read_at and (since 30 Oct) market_fares and market_shares by their read's, change_log by changed_at. |
| `private.backup_runs_insert()` | trigger | internal only | Instead-of-insert trigger on the backup_runs view (design §3.12): turns the backup job's row into a job_runs row (job backup; ok or failed; its kind, counts, R2 key and commit in details) and answers with its id and time. Refuses a kind other than nightly, manual or test, or no ok, as the old table did. |
| `private.briefing_doc(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The airline briefing (#24): one airline's document for export_for_report('briefing'), read only, with no check of its own: the airline (id, world, code, names, game ID); deliveries, its aircraft not yet filed (status on_order or delivered) with type, cabin as ordered and now, bases, order date and note, delivery time and whether it has arrived by p_as_of, and each one's plan cards (with the card's cabin, config_id, since 21 Oct) with their legs in order (UTC weekdays and minute, block, service code); todos, the open to-dos (not done) of the airline and of the group (no airline), with their steps; fare_plan, fare_plan_status()'s document (private.fig_fare_plan()); fare_ladder, each route and cabin's fare level from fare_ladder() (route_id, hub, dest, cabin, level, new_level and planned: the new level is the one to show once this week's move is on the fare plan) with week_of and settings.launch_pct (the level of a route not flown yet), for the plan card check's fare line (since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §2); competition (since 21 Oct; spec docs/specs/2026-10-21-competition-analysis.md §4), competition()'s scans, group line, hubs first, threats and top 20 openings with their counts (private.fig_competition(), p_limit 20); route_loads, route_loads()'s routes and flights for this airline only (private.fig_route_loads()). Deliveries, plan cards and to-dos are the tables as they are now; the fare plan, the fare levels, competition and the loads are as of p_as_of. |
| `private.caller_is_staff()` | boolean | internal only | True for planner staff (their sign-in) and for postgres itself (Claude, jobs, migrations), the way the getters decide. Used by the write functions that run as owner. |
| `private.capture_airline_verdict(p_airline_id bigint, p_at timestamp with time zone)` | jsonb | internal only | An airline's capture as at a moment (#21): the latest page of each kind in that moment's capture day (10:00 to 10:00 UTC) up to the moment, with its verdict, and the airline's verdict: broken if any page is, short if any is or a kind wasn't captured, ok when every page is; null when no page was judged (stored before the checks). words: "all good", or what came in short or broken. Since 22 Oct also the day's fleet pages, when it has some (the latest page of each fleet): a short or broken one makes the airline short or broken and is named in words, and pages.fleet gives their verdict, note ("fleet 3 pages, 21 aircraft", or what came in short or broken), latest time, pages, ok pages and aircraft read. An airline with no fleet pages is judged as before. |
| `private.capture_check(p_raw_id bigint, p_parse jsonb, p_expect jsonb)` | jsonb | internal only | Judges one stored capture page and keeps the verdict on it (game_capture_raw.verdict, verdict_note, verdict_facts; #21), fleet pages included since 22 Oct. p_parse is private.capture_page()'s answer (its rows read) or the parse error; p_expect what to expect (private.capture_expect() when null; the tests give their own). The limits are settings: capture_loads_min_share and capture_statement_min_share. Answers the verdict with its facts; null for page inspection (html). |
| `private.capture_day(p_world_id bigint, p_at timestamp with time zone)` | date | internal only | The capture day a moment belongs to (design §2): the UTC date of the moment minus capture_day_starts_utc (10:00 until set), so one evening's capture is one day, named after the evening. |
| `private.capture_day_complete(p_world_id bigint, p_day date)` | boolean | internal only | Completeness by world (design §7): true when every active airline of our groups in that world has all five pages (statement, events, income statement, balance sheet, loads) in that capture day. Not a count to 6, so a 7th airline must be captured too. |
| `private.capture_day_start(p_world_id bigint, p_day date)` | timestamp with time zone | internal only | When a world's capture day starts, in UTC: the day plus the setting capture_day_starts_utc (10:00 until it is set), design §2. |
| `private.capture_expect(p_raw_id bigint)` | jsonb | internal only | What to expect of one stored capture page, from what the database knows at the page's moment (#21). Loads: scheduled, the airline's flights departing in the page's window (the game's -24h: the 24 hours before the capture), from its flight legs and their UTC weekdays, each rotation from the day after it launched, and a leg with an aircraft only once that aircraft has flown (its registration named by the airline's captured loads before the page; since 15 Oct, as a new aircraft can start flying days after it's filed). Statement: median_lines, the median of the lines on the airline's latest statement page on each of up to 7 earlier capture days, and nights, how many. Fleet (since 22 Oct): the fleet's name and id, which page of how many, and listed, the aircraft the airline's fleet list gave it. Other kinds: nothing. |
| `private.capture_fare_actions_doc(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The fares userscript's list (specs docs/specs/2026-10-21-fares-userscript.md and docs/specs/2026-10-21-frequencies-and-fares.md §3): builds capture_fare_actions()'s document for one world at a moment, with no check of its own. See capture_fare_actions(). |
| `private.capture_find_airline(p_world_id bigint, p_airline text)` | bigint | internal only | The airline a capture page is for, among the airlines of our groups in the key's world: by the game's ID (the userscript from version 1.3), or by name as the older userscript and the bookmark send it (the names matched since 7 Oct). Null when none or more than one fits, so the page is refused. |
| `private.capture_fleet(p_raw_id bigint)` | integer | internal only | Reads one stored fleet page (game_capture_raw kind fleet, since 22 Oct; spec docs/specs/2026-10-22-fleet-capture.md) into game_fleet: each aircraft on it, matched to the planner's aircraft by registration within the airline, for the page's capture day, the latest capture of the day winning. Raises an error, writing nothing, when the page didn't read (its error, no aircraft list, or a row without its registration), which judges it broken. Answers how many aircraft it read. No check of its own. |
| `private.capture_judge(p_kind text, p_read integer, p_error text, p_cash boolean, p_expect jsonb, p_loads_min numeric, p_statement_min numeric)` | jsonb | internal only | The verdict on one capture page (#21), from what was read and what was expected; reads no table. Broken: the page didn't read (p_error), or a balance sheet without the cash account (2800). Short: loads fewer than p_loads_min of the flights scheduled; a statement with no lines, or fewer than p_statement_min of the recent median; events or an income statement with no rows; a fleet page (since 22 Oct) with no aircraft rows, named by its fleet ("fleet JFK"). Otherwise ok. Answers {verdict, note (in words), facts}; null for a kind it doesn't judge (html). |
| `private.capture_key_world(p_key text)` | bigint | internal only | The world a capture key belongs to (capture_keys.world_id), or null for a key that doesn't match. |
| `private.capture_market_plan(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The market pages in Capture all airlines (spec docs/specs/2026-10-30-market-pages.md), for capture_airlines(), with no check of its own: market_every_days (the setting; null when the world has none), market_due (true when the setting is above 0 and the world's latest finished market run started by p_as_of is at least that many capture days old by its start, by private.capture_day(), as the world scan's, or there is none), market_open (private.market_open()), market_latest (that run's id, started_at and finished_at, UTC), market_total (every page: both directions of every pair), market_done (pages the open run has read) and market_pages: for each of our active airlines in display order {game_id, code, name, game_name, pages}, pages being [origin, dest] for both directions of each pair it flies (a route with rotations, not removed), by pair, the way out first; a pair two of our airlines fly is listed once, under the first; the pages the open run has read left out, and airlines with none left out. The open run's pages left out are those read ok (since 31 Oct): a page that failed is listed again, and market_done counts the pages read ok. |
| `private.capture_page(p_raw_id bigint)` | jsonb | internal only | Parses one stored capture page into the capture tables, using the page's own capture time throughout: statement lines into game_statement, folded into game_flights and game_payments; events into game_events (with due_at where known); loads into game_flights; the income statement and balance sheet into game_pnl and game_balance (with capture_day), each row's figures and capture time from the same capture, the latest (#13 pull request 6); since 22 Oct a fleet page into game_fleet (private.capture_fleet()). Then money and loads are matched, and since 22 Oct, after a statement or loads page, each captured flight of the world still without them gets its route and aircraft (private.fill_flight_links()). |
| `private.capture_panel_words(p_reply jsonb)` | text | internal only | The capture panel's words after an airline's loads page (#21): what was read, then one line for the airline: "all good", or what came in short or broken, ending on the loads as "12 of 78" because the userscript adds " flights". capture_ingest() puts them in its reply's rows, so the userscript needs no change. |
| `private.capture_refresh(p_world_id bigint)` | jsonb | internal only | For every airline of our groups in a world: fills flight times and events' due_at that have become known, then matches money to loads, and since 22 Oct fills the route and aircraft of every captured flight still without them (private.fill_flight_links(); links in its answer). Run once after the airports are loaded (#13, pull request 4); the capture does the same for one airline after each page. |
| `private.capture_scan_plan(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The world scan in Capture all airlines (spec docs/specs/2026-10-21-scan-in-capture.md; manual §7), for capture_airlines(), with no check of its own: scan_every_days (the setting; null when the world has none), scan_due (true when the world's latest finished scan by p_as_of is at least scan_every_days capture days old, by private.capture_day(), or there is none; false without the setting), scan_open (private.scan_open()), scan_latest (that scan's id and taken_at, UTC) and scan_airports, the airport codes the scan reads: our active airlines' bases (in display order, each main hub first), the big rival hubs (scripts/scanner/gscan.py's list) and the latest finished scan's 20 busiest airports by departures a week (scan_airline_airports), each once, where it first comes. |
| `private.capture_statement_lines(p_rows jsonb)` | integer | internal only | The lines a bank statement page holds, as the reader takes them: rows whose first filled cell is a date and time (DD.MM. HH:MI). The recent nights a statement page is checked against are counted with it (#21). |
| `private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean)` | jsonb | internal only | Stores one page for an airline of the given world and parses it, at the given capture time, checks it (private.capture_check(), #21: its verdict kept on the raw page and given under verdict; after the loads page, the airline's capture as it stands under airline_verdict), and says whether that capture day is now complete. When the page completes the world's capture for the day (private.snapshot_due), takes the daily snapshot (private.take_snapshot, one job_runs row, ok or failed; a failure never loses the page) and answers with it under snapshot. Refuses a page for an airline outside the world. capture_ingest() calls it with now(); the tests replay saved pages with their own times. p_loads_step is no longer used: the old planner's loads step went with the clean-up (build pull request 14). |
| `private.check_leg_route()` | trigger | internal only | Trigger on flight_legs: refuses a leg whose airports don't match its rotation's route in its direction (leg 1 from the hub to the destination, leg 2 back). |
| `private.check_route_legs()` | trigger | internal only | Trigger on routes and rotations: refuses changing a route's airports, or a rotation's route, when its flight legs would no longer match. |
| `private.competition_threats(p_airline_id bigint, p_as_of timestamp with time zone)` | TABLE(a text, b text, rival_id bigint, rival text, kind text, then_weekly integer, added_weekly integer, now_weekly integer, ours_weekly integer, scan_id bigint, scan_at timestamp with time zone, previous_id bigint, previous_at timestamp with time zone, until timestamp with time zone) | internal only | The threats (spec docs/specs/2026-10-21-competition-analysis.md §1b): on each city pair the airline flies (its live legs, private.fig_freqs()), each rival (every airline that isn't one of ours, groups kind ours; passenger flights only, private.scan_pair_flights()) who started (no departures in the scan before) or added at least settings.competition_threat_min_weekly departures a week, in a finished world scan with its schedules taken in the 7 days before p_as_of, against the finished scan before it; each rival and pair once, from the scan that first showed it (scan_id, scan_at; previous_id, previous_at), listed until 7 days after it (until). a and b are the pair's codes in order; kind started or added; then_weekly (the scan before), added_weekly (what that scan added), now_weekly (the latest finished scan by p_as_of) and ours_weekly (the airline's live legs, both ways). No rows with no scan or one scan. One home for competition() and the fare ladder's rival pause (private.fig_fare_ladder()), with no check of its own. |
| `private.fig_airline_cards(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds airline_cards()'s document with no check of its own. See airline_cards(). |
| `private.fig_airline_world(p_airline_id bigint)` | bigint | internal only | The captured figures (#19): an airline's world; refuses an airline that doesn't exist. |
| `private.fig_airlines(p_world_id bigint)` | TABLE(airline_id bigint, ord integer, iata_code text, name text, home_code text, main_code text) | internal only | The captured figures (#19): our active airlines in a world, in display order, each with its code, name, home airport (fig_home) and main base (null for none). |
| `private.fig_cabin_charges(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds cabin_charges()'s document with no check of its own. See cabin_charges(). |
| `private.fig_capex(p_airline_id bigint, p_d0 date, p_d1 date)` | numeric | internal only | The captured figures: the money put back into the fleet between two reported days (millions), which profit a day adds back to the change in cash. From the bank statement between the two days' balance captures (deposits, cabins and pilot training, bid provisions; refunds count against them), else the spending log (since 26 Oct). |
| `private.fig_capture_status(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): the capture board's document (captureBoard), each airline's pages today and yesterday (UTC), flights by departure date, what is missing today and its status; since #21 also its latest page (last_at) and that capture's verdicts (private.capture_airline_verdict(): verdict, verdict_words, verdict_at, verdict_day and each kind's under verdicts); since 22 Oct its fleet pages count as pages for last_at, and fleet gives that capture day's fleet pages (verdicts.fleet), only when it has some. See capture_status(). |
| `private.fig_cash_days(p_airline_id bigint, p_as_of timestamp with time zone)` | TABLE(day date, cash numeric) | internal only | The captured figures (#19): the old planner's finSeries(), an airline's cash by date in millions: each capture date's latest balance rounded to 0.01M (a figure typed in cash_entries wins before the last 7 days), up to p_as_of. |
| `private.fig_cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone, p_lease_map jsonb)` | jsonb | internal only | The captured figures (#19): builds cash_forecast()'s document with no check of its own; p_lease_map: fig_lease_map() for the world when the caller has it already. See cash_forecast(). |
| `private.fig_cash_log(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds cash_log()'s document with no check of its own. See cash_log(). |
| `private.fig_competition(p_airline_id bigint, p_as_of timestamp with time zone, p_limit integer)` | jsonb | internal only | The captured figures (#19): builds competition()'s document with no check of its own. See competition(). Since 30 Oct also game_share on each market, market_run and contested (spec docs/specs/2026-10-30-market-pages-planner.md §4, §5). |
| `private.fig_day_captured(p_world_id bigint, p_day date, p_as_of timestamp with time zone)` | boolean | internal only | The captured figures (#19): loads_day_captured() as of p_as_of, whether every active airline of ours in the world had been captured for that date by then. |
| `private.fig_day_ops(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)` | TABLE(day date, airline_id bigint, flights integer, aircraft integer, load numeric) | internal only | The captured figures (#19): the old planner's dayOps(), per local date and airline, the flights flown (rotations launched by then), the aircraft, and the average load once the day is done (a flight without a load counts as 97.5%; on a captured day only the flights it has). |
| `private.fig_events(p_world_id bigint, p_as_of timestamp with time zone, p_airline_id bigint)` | TABLE(airline_id bigint, at timestamp with time zone, amount numeric, descr text, event_date date, event_time text) | internal only | The captured figures (#19): the events page's payments as the old planner loads them (CAP.events): debits from the first balance date of the 7 days to p_as_of to 16 days ahead, each at its UTC moment from the airline's home airport's offset in the world (private.airport_offset_min(), with the world's correction, since the clean-up; the old planner's eqOff had none), in millions. p_airline_id: one airline's, or null for all. |
| `private.fig_export(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): every figure for every airline of a world in one document, for export_for_report('figures'), with no check of its own. Since 22 Oct each airline also carries competition()'s competitors, self and scans (private.fig_competition() with p_limit 0), for the weekly report's three biggest competitors (manual §7), and since 23 Oct its order_flags and each competitor's fleet (spec docs/specs/2026-10-23-rival-fleets.md §5). Since 23 Oct each competitor also has its connecting departures on the airline's pairs (connecting_weekly, connecting_pairs, connecting_via; spec docs/specs/2026-10-23-rival-connections.md §4), never added to on_pairs. Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §5) each airline also carries competition()'s contested (its contested pairs with rivals' fares and the game's share each way) and market_run, for the weekly report's competition section; money untouched. |
| `private.fig_fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds fare_ladder()'s document with no check of its own. See fare_ladder(). |
| `private.fig_fare_plan(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds fare_plan_status()'s document with no check of its own. See fare_plan_status(). |
| `private.fig_fin_stats(p_airline_id bigint, p_as_of timestamp with time zone, p_ops jsonb)` | jsonb | internal only | The captured figures (#19): builds the old planner's finStats() for one airline (its card and its profit for each day between captures) with no check of its own; p_ops: dayOps for the world when the caller has it. See airline_cards() and airline_profit(). |
| `private.fig_fits(p_t timestamp with time zone[], p_v numeric[], p_td timestamp with time zone, p_n integer, p_price numeric, p_lease numeric, p_cushion numeric)` | boolean | internal only | The captured figures (#19): cashForecast()'s fits(), whether orders placed at a moment keep the cushion at every forecast point from then on, counting their price and their own weekly lease from 7 days after they are ordered (manual §3). |
| `private.fig_flag(p_world_id bigint, p_airline_id bigint, p_key text)` | boolean | internal only | The captured figures (#19): a true-or-false setting, the airline's own value where it has one, else the world's; false when neither is set (hub_first_exempt). |
| `private.fig_fleet_checks(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds fleet_checks()'s document with no check of its own. See fleet_checks(). |
| `private.fig_flights_on(p_world_id bigint, p_from date, p_to date)` | TABLE(day date, airline_id bigint, flight_no integer, route_id bigint, tail text, launched_on date) | internal only | The captured figures (#19): the old planner's flightsOn(), every scheduled flight departing on each local date in the range, with its airline, number, route, aircraft and its rotation's launch date. |
| `private.fig_freqs(p_world_id bigint, p_airline_id bigint)` | TABLE(rotation_id bigint, airline_id bigint, route_id bigint, hub_code text, dest_code text, live boolean, days_n integer, flights_week integer, has_back boolean, tail text, launched_on date, no_out integer, no_back integer, out_days smallint[], back_days smallint[]) | internal only | The captured figures (#19): each rotation as the old planner read it (planner_state_get(), until the clean-up): its airline, route (live when the route is on the airline's list), the outbound's local weekdays at the hub and the return's at the destination, flights a week (flightsPerDay: 2 with a return number, else 1, × the outbound's days; 7 days with no outbound), its aircraft, launch date and flight numbers. p_airline_id: one airline's, or null for all. |
| `private.fig_group_today(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): one airline's row of the group today (groupOverviewHtml), with no check of its own: cash, flight profit a day, this week's leases and week-end closing per day (each, and together since #18 build pull request 10), net, and the aircraft arrived but not yet flying with their leases a day. See airline_cards(). |
| `private.fig_growth_signals(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds growth_signals()'s document with no check of its own. See growth_signals(). |
| `private.fig_home(p_airline_id bigint)` | text | internal only | The captured figures (#19): an airline's home airport, where the game's events page shows its times (the old planner's CAP_HOME): its main base, or for an airline with none (Ryanair, exempt from hubs first) airlines.home_airport_code, as the capture uses it. |
| `private.fig_hub_progress(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds hub_progress()'s document with no check of its own. See hub_progress(). |
| `private.fig_lease_map(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): the old planner's leaseM() table, each aircraft type's highest weekly leasing payment in the world's captured events by p_as_of (fig_events), keyed as fig_type_key() keys a type. See cash_forecast(). |
| `private.fig_lease_weeks(p_t timestamp with time zone, p_td timestamp with time zone)` | integer | internal only | The captured figures (#19): an order's own lease (manual §3), weekly from 7 days after it arrives, taken as arriving the moment it is ordered: how many of its payments have fallen by a moment. |
| `private.fig_load_days(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)` | TABLE(day date, done boolean, captured boolean) | internal only | The captured figures (#19): each loads day's flags for local dates in the range as of p_as_of, as the old planner's loads document had them: done (the one rule, unless a flag typed after the day's last capture says otherwise) and captured (the day's source is the capture). loads_by_day() reads it. |
| `private.fig_load_values(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)` | TABLE(day date, airline_id bigint, flight_no integer, v numeric) | internal only | The captured figures (#19): the economy loads per flight for local dates in the range, using only the captures and typed entries made by p_as_of (a typed figure wins where it is newer than the day's capture), as the old planner's loads document had them. loads_by_day() reads it. |
| `private.fig_market_pair(p_world_id bigint, p_airline_id bigint, p_hub text, p_dest text, p_run_id bigint)` | jsonb | internal only | The market pages, part 2 (spec docs/specs/2026-10-30-market-pages-planner.md §5), for competition()'s contested pairs, with no check of its own: for one pair (p_hub, p_dest) and one market run, each direction's page read (out from p_hub, back to it): the airline's economy fare (its Y price_avg in market_fares), the cheapest rival's (the lowest Y price_avg of any airline that isn't one of ours; a prefix no airline was matched to counts as a rival; with airline_id, code, name, eco), vs_cheapest_pct (ours against it, %), and the airline's passenger share this week (0 when the page doesn't list it), share_before (share − change) and change in points, with the read's time and week. Answers {out, back}, either null when that direction wasn't read; null when neither was. |
| `private.fig_market_service_checks(p_world_id bigint, p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The service check's builder (spec docs/specs/2026-10-30-market-pages-planner.md §3), for market_service_checks(), with no check of its own: in p_world_id's latest finished market run by p_as_of, each page read (of p_airline_id's pairs, or every airline's when null) against the code its route's distance calls for (manual §4, service_profiles as the planning library reads them) and the planner's codes on the legs that way (the route's rotations). Answers world_id, airline_id, as_of, run (id, started_at, finished_at, age_days, pages_read, pages_failed; null with no finished run), checked, mismatches (one row per direction where the game differs: route_id, airline_id, code, airline, pair, hub, dest, from, to, direction, game_code, distance_code, distance_km, planner_codes, kind distance or planner, off_distance, off_planner, read_at; distance first) and notes. game_code is the code's leading token (since 31 Oct, private.market_service_token(): the game names its profiles "S2 (min 800km)", the planner S2), so reads stored with the game's whole name check right. |
| `private.fig_num(p_world_id bigint, p_airline_id bigint, p_key text)` | numeric | internal only | The captured figures (#19): a rule number from settings, the airline's own value where it has one, else the world's; refuses one that is missing or not a number. |
| `private.fig_ops_recent(p_airline_id bigint, p_as_of timestamp with time zone)` | TABLE(flights bigint, income numeric, costs numeric, last_ts timestamp with time zone) | internal only | The captured figures (#19): game_ops_recent as of p_as_of, the airline's flights, income and costs in the 24 hours before its latest statement line. |
| `private.fig_order_cabin(p_airline_id bigint, p_type_id bigint)` | bigint | internal only | The captured figures (#19): the cabin layout an order of a type comes with for an airline, as data since 15 Oct (spec 2026-10-15 last leftovers §1): the airline's own (airline_order_cabins), else the type's (aircraft_types.order_config_id); null for an airline or type that isn't there. Before, worked out from the cabin names (the old planner's DEFAULT_CABIN: Standard for a low-cost airline, else Leisure, else Comfort; the airline's market default among two of the same cabin, then the newest), which filled the data. |
| `private.fig_patterns(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): the old planner's patterns(), each route's departures over the load window by load band and its mark (cut, watch, add, hold) from the pattern_* settings. See growth_signals(). |
| `private.fig_route_loads(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): the old planner's loadStats() over the last 7 days, for each route and each flight number, with no check of its own. See route_loads(). |
| `private.fig_route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds routeProfit()'s document (routes, aircraft, fare changes, the average flight) with no check of its own; each flight's departure in UTC from its origin's offset in the world, with its correction (since the clean-up). See route_profit(), aircraft_profit() and fare_changes(). |
| `private.fig_route_story(p_route_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds route_story()'s document with no check of its own. See route_story(). Since 30 Oct also days_by_direction, rivals.history and market (spec docs/specs/2026-10-30-market-pages-planner.md §2). |
| `private.fig_ts(p timestamp with time zone)` | text | internal only | The captured figures (#19): a moment as they give it, UTC to the millisecond (2026-10-12T21:05:00.000Z). |
| `private.fig_type_key(p text)` | text | internal only | The captured figures (#19): an aircraft type's name as the old planner's leaseM() compares names: upper case, AIRBUS dropped, EMBRAER as E, letters and digits only. |
| `private.fig_world(p_world_id bigint)` | bigint | internal only | The captured figures (#19): the world asked for, or the default world when null; refuses one that doesn't exist. |
| `private.fill_due_at(p_airline_id bigint)` | integer | internal only | Fills an airline's game_events.due_at once its home airport's offset is known. |
| `private.fill_flight_links(p_world_id bigint)` | jsonb | internal only | The route and aircraft of a world's captured flights that don't have them yet (no other row is touched): the route by the schedule's leg with that number and direction, else the airline's route on its airports, either way round, one that isn't removed first (since 22 Oct), then the one that way round; the aircraft by the registration the loads page or the statement names. Since 22 Oct called after every statement and loads page (private.capture_page()), by private.capture_refresh() and by the daily snapshot before its flows (private.take_snapshot()), so each flight has its links from the evening it is captured and each route day its route. Returns how many routes and aircraft it filled. |
| `private.fill_flight_times(p_airline_id bigint)` | integer | internal only | Fills an airline's loads rows' dep_at and arr_at where the airports' offsets have become known since they were captured. |
| `private.fold_statement(p_airline_id bigint, p_minutes timestamp with time zone[])` | integer | internal only | Folds an airline's statement lines in the given minutes into game_flights (one row per flight block, matched by minute and block) and game_payments (every other line), and ties each flight line to its flight (game_statement.flight_id). Blocks that changed since are taken apart and folded again; a flight already matched keeps its loads. A payment names its aircraft's registration (private.payment_registration()), and since 22 Oct a cabin installation line its aircraft too (private.payment_aircraft(); one found once stays). Run after every statement page, and by the backfill for every minute. |
| `private.history_cash(p_world_id bigint, p_day date, p_at timestamp with time zone)` | TABLE(airline_id bigint, cash numeric, fixed_next7 numeric, cash_at timestamp with time zone) | internal only | The daily history's cash for a capture day, per active airline of our groups (design §7): the day's latest balance of account 2800 up to the moment, with the payments due in the 7 days after it (as capture_cash); with no balance that day, cash_entries by the planner's date. |
| `private.history_fleet(p_world_id bigint, p_at timestamp with time zone)` | TABLE(airline_id bigint, aircraft_by_type jsonb, aircraft_total integer, on_order integer) | internal only | The daily history's fleet at a moment, per active airline of our groups (design §7, §9 step 4): aircraft flying (by type, and the total) from arrival in the game (delivery_at; one with no delivery record from the start) until retired, unless still marked on order; on order from the order date until then. With the moment now it agrees with aircraft.status. |
| `private.history_flows(p_world_id bigint, p_from date, p_to date)` | jsonb | internal only | The daily history's flows for a span of UTC days (design §7): route_days replaced for those days, and each airline_days row of those days given its flights, passengers, seats, loads, money and payments, from game_flights and game_payments. Since 22 Oct each route day also keeps its economy and business passengers and seats, the average business fare and the flights' scheduled block (eco_pax, eco_seats, bus_pax, bus_seats, bus_fare_avg, block_min). Returns how many rows of each it wrote. |
| `private.history_schedule(p_world_id bigint, p_day date)` | TABLE(airline_id bigint, weekly_departures integer, weekly_seats integer, destinations integer) | internal only | The daily history's schedule as it stood on a day, per airline: departures and seats a week and destinations, from the flight legs of every rotation launched by that day (one with no launch date from the start), assuming nothing was dropped. |
| `private.is_payment_line(p_descr text, p_blk integer)` | boolean | internal only | True for a statement line that never belongs to a flight: a lease, salaries, a deposit, a purchase, a refit, a cabin or pilot training (private.payment_kind() names it), or a line the parser put in block 0. |
| `private.is_weekday_set(p_days smallint[])` | boolean | authenticated | True for a set of ISO weekdays as the schedule stores them: 1 (Monday) to 7 (Sunday), sorted, no repeats, at least one. Used by the checks on flight_legs.days_utc and plan_card_legs.days_utc. |
| `private.job_cleanup(p_at timestamp with time zone)` | jsonb | internal only | The 10:20 UTC job (pg_cron equinox-cleanup; design §7): per world, deletes raw pages (game_capture_raw) older than 14 days, and, while settings.statement_cleanup_enabled is true, statement lines older than 14 days, only once every one is in game_flights or game_payments (counted first; otherwise none goes and the run fails, saying how many aren't). One job_runs row per world (cleanup), failed with the error rather than raised. p_at: the run's moment, default now (for the checks). |
| `private.job_run_add(p_job text, p_world_id bigint, p_started_at timestamp with time zone, p_status text, p_note text, p_details jsonb)` | bigint | internal only | Adds one finished job_runs row: the job, its world, when it started (and finished: now), ok or failed, the note and details; for_day is the capture day it started in. |
| `private.job_snapshot_fallback(p_at timestamp with time zone)` | jsonb | internal only | The 10:00 UTC job (pg_cron equinox-snapshot-fallback; design §7): for each world with active airlines of ours, takes the snapshot of the capture day just ended if it has none (private.take_snapshot, source fallback; cash with no balance that capture day and none typed from the latest balance before it), and of any earlier day since the history began that has none. A day with a snapshot is left alone. One job_runs row per world (snapshot_fallback), failed with the error rather than raised. p_at: the run's moment, default now (for the checks). |
| `private.json_int(p jsonb)` | bigint | internal only | A whole number from JSON (a flight number, seats, minutes); null when it isn't one. Used by research_apply() and world_mct_set(). |
| `private.json_num(p jsonb)` | numeric | internal only | A number from JSON: a JSON number, or text that is plainly a number; null for anything else. Used by research_apply() and world_mct_set(). |
| `private.loads_times(p_world_id bigint, p_game_date date, p_dep_local text, p_arr_local text, p_origin text, p_dest text, OUT dep_at timestamp with time zone, OUT arr_at timestamp with time zone)` | record | internal only | A loads row's scheduled departure and arrival as moments, from the local times and the airports' offsets (design §3.8, §4): arrival is departure plus the block worked out from the local times. Null while an offset isn't known. |
| `private.local_to_utc(p_date date, p_time text, p_offset_min integer)` | timestamp with time zone | internal only | A local date and clock time ("07:30") at a fixed offset in minutes, as a moment. Null if any part is missing. |
| `private.log_change()` | trigger | internal only · runs as owner | Trigger on every planner table (decision #15): writes one change_log row per row added, changed or removed, naming the writer from equinox.actor and equinox.actor_detail, or planner for a signed-in user and unset otherwise. An update logs only the columns that changed, and nothing when nothing changed. Skipped when equinox.change_log is off, which only postgres can do. Runs as owner, so the log can be written while it stays read-only. |
| `private.market_ingest(p_world_id bigint, p_kind text, p_payload jsonb)` | jsonb | internal only | The market pages' writes (spec docs/specs/2026-10-30-market-pages.md), for capture_market(), with no check of its own. Kinds: start (a market_runs row in p_world_id, with the payload's note, version and total; answers run_id), page (one Market Analysis page of an open run of the world: {run_id, airline (our airline's game id), origin, dest, ok, error | week, previous_week, service {code, game_id}, fares [{code, cls, flights, low, avg, high, finished, sold_out}], shares [{kind, enterprise_id, name, share, change}], weeks [{week, seats, price}]}; replaces the run's earlier read of the same page; writes market_reads, market_fares (the airline by prefix: the latest finished world scan's schedules, else the share list's airline with that IATA code), market_shares (unknown enterprises placed in airlines by private.scan_airline()) and market_weeks (weeks with figures, the latest read winning), and sets the run's pages read and failed) and finish (status done; refused while more than 10% of the run's pages failed). Raises an error for an unknown kind, a run that isn't open in the world, an airline that isn't ours, or figures that don't read. The service code is stored as its leading token (since 31 Oct, private.market_service_token(): "S2 (min 800km)" → S2). |
| `private.market_open(p_world_id bigint, p_as_of timestamp with time zone)` | bigint | internal only | The market pages (spec docs/specs/2026-10-30-market-pages.md): the latest open market run of the world started in the hour up to p_as_of, or null. capture_market() carries on with it instead of starting another; capture_airlines() gives it as market_open. |
| `private.market_service_token(p text)` | text | internal only | A service profile's code as the planner and service_profiles write it (since 31 Oct): the game's name up to " (", trimmed ("S2 (min 800km)" → S2, "R" → R); null when empty. Used by private.market_ingest() (market_reads.service_code) and private.fig_market_service_checks() (game_code), so the reads stored before capture 1.10 check right. |
| `private.market_stop_unfinished(p_world_id bigint, p_as_of timestamp with time zone)` | integer | internal only | The market pages (spec docs/specs/2026-10-30-market-pages.md): marks the world's market runs left open more than an hour before p_as_of as stopped, with a note of how far each got ("stopped part-way after 120 of 686 pages, 2 failed (marked 30 Oct 21:40 UTC)"), as private.scan_stop_unfinished() does for scans; answers how many. Called by capture_market()'s start. |
| `private.match_flights(p_airline_id bigint)` | integer | internal only | Matches an airline's money-only and loads-only game_flights rows (design §3.8): per route, in time order so two flights on one route never swap, a block pairs with a loads row whose scheduled departure is 30 minutes after to 3 hours before the statement time, of the same aircraft where the statement names one; the most pairs win, then the smallest total gap. Unpaired rows wait for their partner. Needs the airports' offsets. |
| `private.merge_flight(p_money_id bigint, p_loads_id bigint)` | boolean | internal only | Joins one money-only game_flights row and one loads-only row into one flight: the loads columns move into the money row, and the loads row goes. Since 22 Oct the joined flight takes the loads row's route (by its flight number), or none until the capture fills the links right after the matching (private.fill_flight_links()), never the route its money-only row took by its airports; its aircraft is either side's. |
| `private.payment_aircraft(p_world_id bigint, p_airline_id bigint, p_descr text)` | bigint | internal only | The cabin charge check (spec docs/specs/2026-10-21-tidy-ups.md §3): the aircraft a cabin installation line names ("Installation of cabin interior (9M-AAV)"), the airline's own aircraft with that registration in the world (private.payment_registration()); null for any other line, or a registration the airline has no aircraft for. Read by private.fold_statement() for game_payments.aircraft_id. |
| `private.payment_kind(p_descr text)` | text | internal only | The kind of a statement line that isn't tied to a flight (game_payments.kind): lease, salaries ("Payment of employee salaries", the week-end closing), deposit, purchase, refit (a configuration), cabin (a cabin, and since 15 Oct the pilot training that comes with an order: "Pilot training", 20261015200000), or other. |
| `private.payment_registration(p_descr text)` | text | internal only | The aircraft a payment names, e.g. B-0161 from "Leasing rate for B-0161", and since 22 Oct 9M-AAV from the game's "Installation of cabin interior (9M-AAV)" (spec docs/specs/2026-10-21-tidy-ups.md §3). Null when it names none. |
| `private.plan_line_slot()` | trigger | internal only | Trigger on plan_cards and aircraft (spec 2026-10-27 long-haul lines §2): refuses a second card at a line's offset while the aircraft of the first isn't retired. A retired aircraft's card holds no place, so its replacement can take it; an aircraft coming back from retired is refused if its place was taken. Takes a lock on the line so two writers can't both take a place. |
| `private.research_apply(p_world_id bigint, p_doc jsonb)` | jsonb | internal only | planner_data_set()'s step for the route research (key DATA: routes, coords, utc, countries): writes countries, airports and a world's research routes, only the rows that change, by the loader's rules. Added routes and the planner's overrides are never touched; a research route no longer listed goes unless something points at it or it carries an edit. A new UTC offset for an airport that flights or plan-card legs use (with no world correction) is held back and named, since their UTC times were worked out with the old one (design §4). A part missing from the document leaves its rows alone. Returns how many rows each part changed. |
| `private.restore_row(p_table text, p_row_key jsonb, p_as_of timestamp with time zone)` | jsonb | internal only | Puts one row of a logged table back as it was at a moment, by replaying change_log backwards: re-adds a removed row with its own key, undoes changes, or removes a row added since. The restore is logged like any change. For Claude, as postgres: start with the equinox.actor line (design §6). |
| `private.rules_input_doc(p_world_id bigint, p_routes text)` | jsonb | internal only | The planning library's input for a world (decision #19, design §7), with no check of its own: what rules_input() gives staff and export_for_report('rules') gives the scripts (always 'all'). See rules_input(). p_world_id: the world, or null for the default world; p_routes: all (every route that isn't removed) or flown (only routes with rotations, and only the airports they, the legs, the bases and the aircraft use). |
| `private.scan_airline(p_world_id bigint, p_game_id integer, p_name text)` | bigint | internal only | The airlines row of an airline a world scan saw, by game ID, added when new (design §3.9: rivals can then be placed in groups); a rival's game_name follows the game, ours are left alone. Null without a game ID. |
| `private.scan_connection_via(p jsonb)` | jsonb | internal only | The top 3 connecting airports of a list of {via, weekly} (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): each airport's departures added up, biggest first, ties by code; an empty list for none. For private.scan_connections(), competition() and route_story(). |
| `private.scan_connections(p_scan_id bigint)` | jsonb | internal only | Works out every rival's one-stop connections on our city pairs in one world scan, from its schedules (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §1), replacing the scan's rows in scan_rival_connections and scan_rival_connections_week. A rival's passenger flight (private.scan_passenger(); our airlines left out) A→H joined to its own flights H→B, B not A, on a weekday the first runs (the next day when its local arrival is earlier than its departure), the gap in local time at H at least world_airports.mct_min (90 minutes where unknown) and at most settings.connection_max_wait_h; both legs together at most settings.rival_connection_detour_max times A–B, great-circle from airports.lat and lon (a routing with an airport lacking coordinates is left out and counted); kept only for pairs any of our airlines flies (a route with rotations) or has on its list (not removed), either way round. Each first flight counts once a day however many onward flights it meets, its shortest gap kept. Run by private.scan_ingest() kind finish after the airport summaries; also by hand for a past scan (select private.scan_connections(<scan id>)). Answers {scan_id, rows, rivals, pairs, weekly, left_out_no_coordinates, ms, words}. Nested loops are off inside it (the schedules' row estimates make them very slow). postgres only. |
| `private.scan_fleet(p_scan_id bigint, p_before_id bigint, p_airline_id bigint)` | jsonb | internal only | An airline's fleet in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §4), for competition(), with no check of its own: from p_scan_id's overview page (scan_airline_profile, scan_airline_fleet) overall, on_order, avg_age_years, types_count and types (its 5 biggest by overall, then on order, each with on_order and avg_age_years), and against p_before_id's overall_before, on_order_before, overall_change and on_order_change (null when that scan didn't read its page). Null when p_scan_id didn't read it. |
| `private.scan_ingest(p_world_id bigint, p_kind text, p_payload jsonb)` | jsonb | internal only | The world scan's writes (spec docs/specs/2026-10-21-scan-in-capture.md): ingest_snapshot()'s body, shared by ingest_snapshot() (scripts/scanner/gscan.py, the fallback) and capture_scan() (Capture all airlines), with no check of its own. Kinds: start (a game_scans row in p_world_id, the default world when null; answers snapshot_id; the world's scans left unfinished more than an hour ago are stopped first), airline (its totals in game_scan_airlines and its schedule in game_scan_schedules, the airline placed in airlines by game ID through private.scan_airline()), airport (its page in game_scan_airports, the airlines stationed there placed too), fleet (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §3: an airline's overview page, its types in scan_airline_fleet and its totals and general figures in scan_airline_profile, replacing the same scan's earlier read; a page sent with error, or without a types list, is kept as read_ok false with the reason, and never replaces a page the same scan read; answers {ok, read_ok, rows}), finish (status done and the airport summaries, private.scan_summarise(); since 23 Oct then the rivals' connections on our pairs, private.scan_connections(), spec docs/specs/2026-10-23-rival-connections.md §1, its note "connections: N rivals on M of our pairs" added to the scan's note, and a calculation that fails or runs out of time noted without stopping the finish; since 23 Oct then the week's pairs kept for good when it is the week's kept scan, private.scan_pairs_keep(), spec docs/specs/2026-10-23-rival-pairs-history.md §2, a write that fails noted as "pairs not kept" without stopping the finish; a scan that isn't there is ignored) and markets (the weekly report's market summaries, replacing the scan's earlier ones). Every kind but start takes its scan's own world. An unknown kind, or a scan that isn't there, raises an error. |
| `private.scan_open(p_world_id bigint, p_as_of timestamp with time zone)` | bigint | internal only | The world scan (spec docs/specs/2026-10-21-scan-in-capture.md): the latest unfinished scan (status not done) of the world started in the hour up to p_as_of, or null. capture_scan() carries on with it instead of starting another; capture_airlines() gives it as scan_open. |
| `private.scan_order_flags(p_airline_id bigint, p_scan_id bigint, p_before_id bigint, p_pairs text[])` | jsonb | internal only | The world's rival order books in a world scan (since 23 Oct; spec docs/specs/2026-10-23-rival-fleets.md §4), for competition()'s order_flags, with no check of its own: every airline whose overview page p_scan_id read with aircraft on order, that isn't one of ours, freighter-only airlines left out (flights in the scan, none of them passenger flights by private.scan_passenger()), flagged starting (on order and no flights in the scan) or orders (on order at least the world's settings.rival_orders_flag_pct of its fleet and at least rival_orders_flag_min); each with airline_id, name, kind, fleet, on_order, share, weekly, on_order_change and fleet_change (against p_before_id, private.scan_fleet()), on_pairs (a passenger flight on one of p_pairs, 'AAA-BBB' with the codes in order), at_bases (departures from one of p_airline_id's hubs or focus cities in scan_airline_airports), meets and words; the biggest share first. The list is the same for every airline; only on_pairs, at_bases and meets depend on it. An empty list with no scan. |
| `private.scan_pair_flights(p_scan_ids bigint[], p_pairs text[])` | TABLE(scan_id bigint, airline_id bigint, origin text, dest text, weekly integer) | internal only | Competition analysis (spec docs/specs/2026-10-21-competition-analysis.md): each airline's passenger departures a week from origin to dest in each world scan asked for (game_scan_schedules), on the city pairs asked for, either direction (each pair as 'AAA-BBB', its codes in order); each flight's days counted as scripts/scanner/gscan.py counts n_weekly, freighters left out (private.scan_passenger(), the weekly report's rule), a direction with none left out. Every airline, ours included: the callers tell rivals apart. Read by private.competition_threats() and private.fig_competition(), with no check of its own. |
| `private.scan_pairs_fill_back()` | jsonb | internal only | Fills scan_pair_airlines back from the scans still holding their schedules (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §2): every finished scan in order of time, through private.scan_pairs_keep(), so each week with none kept gets its first. Run once by the migration 20261023160000_rival_pairs_history; safe to run again (writes nothing for a week already kept). Answers the scans it kept, each {scan_id, week, kept, rows}. postgres only. |
| `private.scan_pairs_keep(p_scan_id bigint)` | jsonb | internal only | Keeps a finished world scan's pairs for good when it is its week's kept scan (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §1, §2): if no scan of the same world in the same week (Saturday to Friday, UTC, private.scan_week()) has rows in scan_pair_airlines yet, writes each airline's departures a week on every pair from the scan's schedules (both ways, passenger and freighter apart), else nothing (a second scan the same week, or the same finish twice). A scan not finished, or without its schedules, writes nothing. Run by private.scan_ingest() kind finish after the connections; also by hand. Answers {scan_id, week, kept, rows} and why when nothing was written. postgres only. |
| `private.scan_passenger(p_type text)` | boolean | internal only | Competition analysis (spec docs/specs/2026-10-21-competition-analysis.md): whether a world scan's flight is a passenger flight, from its aircraft type (the schedule's 8th field), by the weekly report's rule, scripts/report/analyze.py's seats(): no type, a type ending in F, or ATF, ABX, 74Y, 77X or 76X is a freighter (false). Freighters are no one's rivals for passengers: private.scan_pair_flights() and private.fig_competition() leave them out. Immutable, internal, with an empty search path. |
| `private.scan_progress(p_scan_id bigint)` | jsonb | internal only | The world scan (spec docs/specs/2026-10-21-tidy-ups.md §1): how far a scan got, with no check of its own: airlines and airports, the rows it holds in game_scan_airlines and game_scan_airports; before_id and before_at, the latest finished scan of its world before it; airlines_expected and airports_expected, what that one read (null without one), so a stopped scan says "812 of 1,040 airlines". Read by private.scan_stop_unfinished() and system_status(). |
| `private.scan_stop_unfinished(p_world_id bigint, p_as_of timestamp with time zone)` | integer | internal only | The world scan (spec docs/specs/2026-10-21-tidy-ups.md §1): marks every unfinished scan of the world (status neither done nor stopped) started more than an hour before p_as_of as stopped, its note starting "stopped part-way after 812 of 1,040 airlines and 0 of 97 airports (marked 22 Oct 01:10 UTC)" (private.scan_progress(), against the latest finished scan before it), its old note kept after a dot. Nothing carries such a scan on (private.scan_open() looks back an hour), and the scans' readers use finished scans only. Answers how many it marked. Called by private.scan_ingest()'s start and by migration 20261022010000. |
| `private.scan_summarise(p_scan_id bigint)` | integer | internal only | Builds a world scan's airport summaries (scan_airline_airports) from its schedules: per airline and airport, departures a week and destinations. Run when a scan finishes; a scan whose schedules were archived keeps what it has. Returns the rows written. |
| `private.scan_week(p_at timestamp with time zone)` | date | internal only | The week a world scan belongs to (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §2): the Saturday on or before its time's UTC date. For private.scan_pairs_keep(). |
| `private.schedule_jobs()` | jsonb | internal only | Schedules the two database jobs with pg_cron, by name, so it can run again safely: equinox-snapshot-fallback at 10:00 UTC (private.job_snapshot_fallback) and equinox-cleanup at 10:20 UTC (private.job_cleanup). Run by migration 20261011150000_jobs, and again after a full restore (the backup copies no schedules). Answers with the jobs as the scheduler has them. |
| `private.set_updated_at()` | trigger | internal only | Trigger on every planner table: sets updated_at when a row is added or really changes, and leaves it as it was when an update changes nothing. |
| `private.shift_weekdays(p smallint[], p_days integer)` | smallint[] | internal only | ISO weekdays moved by whole days (−1: each a day earlier, Monday becomes Sunday), sorted. Turns local weekdays into UTC ones and back (design §4). |
| `private.snapshot_due(p_world_id bigint, p_day date, p_at timestamp with time zone)` | boolean | internal only | Whether a page at p_at completes a world's capture for the day: every active airline of our groups has all five pages since the day started, or since the last snapshot taken from a complete capture that day. So one snapshot per complete capture, taken by its last page. |
| `private.statement_blocks(p_airline_id bigint, p_minutes timestamp with time zone[])` | TABLE(ts timestamp with time zone, blk integer, is_flight boolean, route text, routes_n integer, pax integer, tail text, pax_income numeric, cargo_income numeric, fuel numeric, onboard numeric, handling numeric, landing numeric, atc numeric, maintenance numeric, income_total numeric, cost_total numeric, captured_at timestamp with time zone) | internal only | An airline's statement lines in the given minutes, grouped by minute and block (blk) as game_flight_pnl has always grouped them, leaving out payments: money by type, the route, passengers, the maintenance line's aircraft, and whether the block is a flight (any flight line or route) or only payments. |
| `private.statement_category(p_descr text)` | text | internal only | The type of a bank-statement line (pax_income, cargo_income, fuel, onboard, handling, landing, atc, maintenance or other), as game_flight_pnl has always counted them. |
| `private.take_snapshot(p_world_id bigint, p_day date, p_at timestamp with time zone, p_source text, p_flows boolean)` | jsonb | internal only | The daily snapshot of a world's capture day (design §7): point-in-time figures (fleet, schedule, cash) as at p_at (default now) into airline_days for each active airline of our groups, with source (capture, fallback or backfill) and whether the day's capture was complete; then (p_flows), once each captured flight still without them has its route and aircraft (private.fill_flight_links(), since 22 Oct, so each route day written has its route; links in its answer), the flows of that UTC day and the two before. A later snapshot replaces the point-in-time figures, but a fallback or backfill never replaces one from a complete capture. Called by the capture when a day completes; pull request 7's 10:00 UTC fallback calls it too. |
| `private.world_mct_set(p_world_id bigint, p_mct jsonb)` | jsonb | internal only | site_admin()'s step for content mct: a world's minimum connection times from the whole map {airport code: minutes}, into world_airports.mct_min; times of airports the map no longer lists are cleared, and a row nothing else describes goes. Refuses anything but airport codes with whole minutes, 0 to 1440. Returns how many were set, cleared and removed. |

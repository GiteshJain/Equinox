# The database, table by table

Generated from the database's own descriptions by `database/describe.py`. Don't edit by hand: change the
description in a migration (`comment on table ...`), and the database rehearsal regenerates and checks this
file. How the parts fit together: `docs/architecture.md`.

58 tables, 7 views and 40 functions, all in Supabase's `public` schema, plus 102 internal functions in `private`. Website photos and logos are files in the `site-photos` storage bucket, not tables.

## Contents

- [`aircraft`](#aircraft) (table): Each aircraft from order to delivery to service to retirement, one row each
- [`aircraft_cabin_keeps`](#aircraft-cabin-keeps) (table): Retired 21 Oct (manual §5; spec docs/specs/2026-10-21-cabins-new-rule.md): the Cabins board's "Keep as is" decisions, kept as history; nothing writes to it since the board went (we no longer refit; the cabin is chosen with each order)
- [`aircraft_types`](#aircraft-types) (table): Aircraft types and their figures in a world: seats, cruise speed, turns, maintenance, price
- [`airline_aircraft_types`](#airline-aircraft-types) (table): The aircraft types each airline may buy
- [`airline_bases`](#airline-bases) (table): Each airline's hubs and focus cities, with bank times and flight-number blocks
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
- [`game_capture_raw`](#game-capture-raw) (table): Every page the capture sent, as rows of cells before parsing, with its world and airline, and its check as it arrived (verdict, #21)
- [`game_events`](#game-events) (table): Payments the game lists ahead on the events page: leases, salaries and deliveries
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
- [`markets`](#markets) (table): Each airline's markets, with the cabin layout each calls for (layout; manual §5)
- [`monthly_checks`](#monthly-checks) (table): When each monthly check was last done, per airline or for the group as a whole (airline_id null)
- [`plan_card_legs`](#plan-card-legs) (table): A plan card's flights, with the same time rules as flight_legs (UTC)
- [`plan_cards`](#plan-cards) (table): A plan for one aircraft's flying, on order or flying, kept after it is filed as the record of what was planned (whether it is filed is worked out, not stored)
- [`planner_scripts`](#planner-scripts) (table): Copies of Claude's scripts from before the repository existed
- [`planner_users`](#planner-users) (table): Email addresses allowed into the planner (staff)
- [`report_access`](#report-access) (table): The password hash for the investor page and investor reports
- [`rotations`](#rotations) (table): An aircraft's out-and-back pair on a route: what the old planner calls a frequency
- [`route_days`](#route-days) (table): The daily history per route, direction and UTC day (design §3.10, §7): each airline's flights, passengers, seats, money and average economy fare, from game_flights (a flight's day is the UTC date it departs), kept for good after game_flights is archived
- [`routes`](#routes) (table): Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner's overrides (null = the research value; research refreshes never touch them)
- [`scan_airline_airports`](#scan-airline-airports) (table): Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and airport, its departures a week from there and how many destinations it flies to from there
- [`scan_airline_markets`](#scan-airline-markets) (table): Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and market (the weekly report's market names, e.g
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
| `checked_on` | date | The one-week check, Gitesh's to mark (manual §1) |
| `schedule_changed_on` | date | When its schedule last changed, which restarts the one-week check |
| `maintenance_note` | text | The planner's maint |
| `retired_on` | date |  |
| `extra` | jsonb | What the old planner kept on a tail that the table has no column for, under tail (its notes, which Tails shows). The old lists' places and delivery items went with the clean-up (build pull request 14). Expected otherwise empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

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

*Table.* Each airline's hubs and focus cities, with bank times and flight-number blocks. Replaces the planner's ref.hubs and MAIN_HUB.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `airport_code` | text |  |
| `role` | text | hub or focus |
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

*Table.* Hashed keys that let the in-game capture send data. Only hashes are stored. Each key belongs to one world (world_id): a page for an airline outside it is refused. Written by hand when a key is issued. Read by capture_ingest() and capture_airlines().

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
| `ladder_move` | text | The fare ladder's move: up, down or hold (a hold is recorded when it follows a step down, so the hold has a record). Null on a fare test that isn't the ladder's |

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

*Table.* Every page the capture sent, as rows of cells before parsing, with its world and airline, and its check as it arrived (verdict, #21). Kept 14 days: the 10:20 UTC clean-up (private.job_cleanup, #13 pull request 7) deletes older pages. Written by capture_ingest(). Read by private.capture_page(), completeness (private.capture_day_complete), capture_status() and system_status() (each airline's latest verdicts) and the planner's Capture board.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `airline` | text |  |
| `kind` | text | statement, events, loads, pnl, balance or html |
| `page_url` | text |  |
| `captured_at` | timestamp with time zone |  |
| `rows` | jsonb | The page's table rows, each a list of cell texts |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `verdict` | text | The page's check as it arrived (#21): ok, short (fewer rows than expected) or broken (didn't read, or a balance sheet without the cash account); null for page inspection (html) and pages stored before 14 Oct's checks |
| `verdict_note` | text | The verdict in words: what was expected and what came, e.g. loads 12 of 78 flights (#21) |
| `verdict_facts` | jsonb | The numbers behind the verdict (#21): read (rows the reader took), and per kind scheduled and share (loads), median_lines and nights (statement), cash (balance), the limit used, or the error |

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
| `route_id` | bigint | The route, by the schedule's leg with that number and direction, else by its airports (filled by private.fill_flight_links) |
| `aircraft_id` | bigint | The aircraft, by the registration the loads page or the statement names (filled by private.fill_flight_links) |
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
| `registration` | text | The aircraft the line names, e.g. from "Leasing rate for B-0161" |
| `aircraft_id` | bigint | The aircraft, once aircraft are loaded (#13, pull request 4) |
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

*Table.* Each airline's totals in a world scan (design §3.9; was game_snapshot_airlines): flights, weekly departures and airports, with its airlines row. Kept for good; the full schedule is in game_scan_schedules. Written by ingest_snapshot(). Read by export_for_report().

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

*Table.* Each scanned airport's page in a world scan (design §3.9; was game_snapshot_airports): its details, the airlines stationed there and its news. Kept one month, then archived (#13 pull request 7). Written by ingest_snapshot(). Read by export_for_report().

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

*Table.* Each airline's full schedule in a world scan (design §3.9): one JSON list per airline, each flight as [code, number, from, to, weekdays, departure, arrival, aircraft type, operator]. Kept one month, then archived (#13 pull request 7). Written by ingest_snapshot(). Read by export_for_report() and the airport summaries (private.scan_summarise).

| Column | Type | Notes |
|---|---|---|
| `scan_id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `flights` | jsonb |  |

**Access:** staff read: select for authenticated.

## game_scans

*Table.* One row per world scan (design §3.9; was game_snapshots): when it ran, the week, its status and a note, with its world. Kept for good. Written by ingest_snapshot(), from scripts/scanner/gscan.py. Read by export_for_report() for the weekly report and gander monthly.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `taken_at` | timestamp with time zone |  |
| `week` | text |  |
| `note` | text |  |
| `status` | text |  |
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

## markets

*Table.* Each airline's markets, with the cabin layout each calls for (layout; manual §5). Since 21 Oct a market keeps only its layout: its default aircraft, default cabin and fares went (spec docs/specs/2026-10-21-cabins-new-rule.md). Replaces the planner's ref.markets.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `name` | text | e.g. Transatlantic – dense |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |
| `layout` | text | The cabin layout the market calls for: Standard, Leisure, Leisure Plus or Comfort (manual §5). A plan card's cabin takes it where one route of the market flies more than cabin_route_share_pct of the aircraft's block time, unless the route has its own choice (routes.cabin_choice). Filled on 21 Oct from the cabin of the market's old default layout; changed in Reference → Markets |

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
| `route_id` | bigint | The route, when the flights were matched to one; set to null if the planner removes the route later (the airports keep the history) |
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
| `stars_override` | smallint | Typed in the planner; null = the research value |
| `cabin_choice` | text | The cabin chosen for the route (the planner's routeCabin) |
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

*Table.* Money spent, in AS$: aircraft orders, cabins and refits, losses. Replaces the planner's capex. Read by site_investor().

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
| `airline_cards(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Review's card for each of our active airlines in a world (the default world when null), in display order (decision #19, design §8; the old planner's finStats, renderFinance and fcNext): profit a day over the last 7 days of reported cash (an early read over fewer, early true), per aircraft, return on fleet a week, an aircraft pays back in and funds a new aircraft every (days), fleet, on order, flights a day and how many more than a week ago, average load over 7 days, next_order and can_order_now (cash_forecast()); and group_today (groupOverviewHtml): per airline cash, flight profit a day, this week's leases and week-end closing per day (each, and together), net, and aircraft arrived but not yet flying with their leases a day (group_today_shown once any airline has flight profit). No group totals (manual §1). Money in millions of AS$. And the group's average economy load over 7 days, the old Home's key figure (avgLF): load_7_days, the average of every flight the loads pages captured departing from 7 days before p_as_of's UTC date on (one per airline, date and flight number), with load_7_days_flights and load_7_days_from captures; with none captured, every flight the last 7 days' load reports cover (route_loads()), from reports; with neither, null. Staff only; runs as owner and checks the caller itself. |
| `airline_profit(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Profit for each day between captures for one airline (decision #19, design §8; the old planner's finSeries, finStats, capexIn and dayOps): each reported cash date (the capture's balance rounded to 0.01M, or a figure typed in cash_entries) with the change in cash plus that period's order payments (orders and cabins; losses stay in profit), per day over the days between, the aircraft, flights and average load flown that day, and the profit a day per aircraft flying that day (per_aircraft_day, #18 build pull request 10); with the 7-day profit a day. Money in millions of AS$. Staff only; runs as owner and checks the caller itself. |
| `as_num(p text)` | numeric | anon, authenticated | Turns game text such as 1,234.5 AS$ into a number (null when there is none). |
| `auto_confirm_planner_user()` | trigger | internal only · runs as owner | Trigger on sign-up: confirms the email straight away when it is on planner_users. |
| `capture_airlines(p_key text)` | jsonb | anon, authenticated · runs as owner | For the capture userscript, with the capture key: the key's world and its active airlines of our groups (game ID, name, code), in display order, so the userscript doesn't keep its own list. |
| `capture_fare_actions(p_key text)` | jsonb | anon, authenticated · runs as owner | For the fares userscript (capture/fares_apply.user.js; manual §5, since 21 Oct; specs docs/specs/2026-10-21-fares-userscript.md and docs/specs/2026-10-21-frequencies-and-fares.md §3), with the capture key: the game's Ticket price adjustments still to make. For each active airline of our groups in the key's world, in display order (as capture_airlines()), its fare_ladder() actions that set a route back to its level (fix true: they need no fare plan row, and the index matching again is the proof), and those whose route is on the fare plan this week and not yet seen in the captures (every class the action names is a route row with planned true and applied false), in fare_ladder()'s order (the set-back changes first). airlines: each airline's game_id, name (the website's, else the planner's), game_name, code, count of actions and fixes (how many of them set a route back); actions: each with game_id and airline (its name), n (the action's number in fare_ladder()), route (HUB–DEST), from and to (IATA), level (% of the default price), sign (+ or -) and pct (the game's percent, a whole number), classes (economy and/or business), plan_ids (the fare plan rows, one per class in the same order; none for a set-back change), fix and reason (a set-back's, "captured fare at 100%, level 110%") and text (the action in words); week_of (this Saturday) and as_of. A wrong or missing key gets {"ok": false, "error": "bad key"} and nothing else. Runs as owner with an empty search path and its own statement limit of 30 seconds (it works out every airline's fare ladder in one call, signed out). |
| `capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)` | jsonb | anon, authenticated · runs as owner | Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game's ID or, from older userscripts, by name, and refuses one outside the key's world; keeps the raw page (the 10:20 UTC clean-up deletes it after 14 days), parses it (private.capture_store, private.capture_page): bank statement into game_flights and game_payments, loads into game_flights; and checks it (#21: the verdict under verdict). After the loads page, rows holds the capture panel's words (what was read, and the airline's verdict: "all good" or what came in short or broken) and count the rows read. Answers with the capture day and whether it is complete; the page that completes the world's capture for the day also takes the daily snapshot (airline_days, route_days) and answers with it. |
| `capture_status(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | What the capture collected for each of our airlines in a world (the default world when null; decision #19, design §8; the old planner's captureBoard): for today and yesterday (UTC dates of p_as_of), when each page kind (loads, statement, events, pnl, balance) last came, how many flights the loads page held for each date (flight numbers, by departure date as the game lists them), which kinds are missing today, and complete, missing or not captured. Moments in UTC. Staff only; runs as owner and checks the caller itself. |
| `cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Cash, next 14 days, and when an airline can order (manual §3; decision #19, design §8; the old planner's cashForecast, flightsPerDay, leaseM, orderNow and fcNext). From the airline's latest balance captured in the 7 days to p_as_of (cash, cash_at): flight profit a day (profit a flight over the last 24 hours of the bank statement × planned flights a day; status missing with fewer than 5 flights, no capture without a balance); every payment the events page lists for the 14 days after the capture, each in the first week repeated a week later beyond what the game lists (payments, repeat true), at the airline's home airport (its main base); the balance at each payment and on each of the 14 days (points), the lowest point and the payment that makes it; for each type the airline may buy (airline_aircraft_types) its price with the cabin it would get, its weekly lease (the highest leasing payment seen for the type, else lease_estimate_pct of its price) and the first day it can be ordered keeping order_cushion in hand with its own lease from 7 days after it is ordered (safe_day 0 to 14, or null; count_today: how many at once today, up to 9); can_order_now and next_order. p_orders, a list of {"type" or "aircraft_type_id", "count"}: whether ordering them all now stays safe, each with its own lease, and the lowest point after (orders_tested). Money in millions of AS$, moments in UTC. Staff only; runs as owner and checks the caller itself. |
| `cash_log(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Review's nightly log and its cash entry form for our active airlines in a world (the default world when null), in display order (#18 build pull request 10; the old planner's finSeries, applyCaptureCash and cashEntryHtml): per airline each reported date (airline_profit()'s, the first included) with its cash and its fixed costs for the next 7 days as the old planner shows them (for a capture day in the 7 days to p_as_of's UTC date, the events' payments in the 7 days after that day's latest balance, when there are any; otherwise a typed figure, else the capture's, above zero only); and for today (p_as_of's UTC date) the figures a typed one is saved against: shown (the form's), stored (what the tables give the old planner: a typed figure, else the capture's rounded to 0.01M), captured (capture_cash rounded) and the typed row (cash_entries: cash and fixed_next7 in AS$, updated_at) when there is one. Money in millions of AS$ unless named. Staff only; runs as owner and checks the caller itself. |
| `export_capture(p_secret text, p_days integer)` | jsonb | anon, authenticated · runs as owner | Exports recent capture data for Claude's scripts, exactly as before #13: profit per flight, loads, payments ahead, cash, the last 24 hours and capture runs, from the compatibility views. Needs the ingest secret. |
| `export_for_report(p_secret text, p_kind text, p_arg text)` | jsonb | anon, authenticated · runs as owner | Exports for the weekly report, gander monthly, the airline briefing and the planning library: the world scans (snapshots), a scan's airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19); and one airline's briefing rows (kind briefing, p_arg {"airline": its id, code or name, "as_of", "world"}, the airline required: its deliveries with their plan cards and legs, open to-dos of the airline and the group, fare_plan_status(), each route's fare level from fare_ladder() (since 21 Oct) and route_loads() for it, private.briefing_doc(), #24; read only). Kind planner (the old planner's documents) is refused since the clean-up (build pull request 14). Needs the ingest secret. |
| `export_repo_bootstrap(p_secret text)` | jsonb | anon, authenticated · runs as owner | Exported the stored scripts when the repository was created (decision #1). Needs the ingest secret. |
| `fare_changes(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Economy fare changes seen in an airline's captures (decision #19, design §8; routeProfit's fare changes): for each route flown in the last 9 days, each date whose average captured economy fare is more than 1% from the date before, with both fares and the economy load the day before and after, newest first. Staff only; runs as owner and checks the caller itself. |
| `fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md, docs/specs/2026-10-21-fare-actions-by-route.md and docs/specs/2026-10-21-frequencies-and-fares.md): this Saturday's move for each route and cabin, the changes that set a route back to its level, and the game actions that make them. routes: each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin's load at 100%), the sold-out share and the average fare over those 7 days (game_flights, matched to the route either way round); its level as a % of the game's default price (the latest the fare plan recorded before this Saturday, else settings.fare_launch_pct) and steps above launch; the fare index: each flight of the latest captured day (latest_on, its average latest_fare) against its direction's baseline, times the launch level, the baseline being the direction's fare on the latest captured day on or before 21 Oct 2026, when every route was at its launch level (Gitesh), or for a route launched later its first captured fare if captured in its first growth_new_route_days days (a day's fare: its flights' lowest, else route_days' average economy fare; baseline_fare and baseline_on, the directions' average and latest day); fare_index the flights' average, index_matches false when any flight is more than 1 point off the level the game should show (this week's new level once the captures see it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, for fare_ladder_hold_weeks after a recorded step down, and while the newest rotation is under fare_ladder_capacity_hold_days old on a route older than that (a flight added: "judged at its new size from ..."; a frequency taken away isn't tracked, its rotation is deleted); never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes; fix, a change that sets it back to its level (index_matches false, not on the fare plan this week, not a new route, and captured since its newest rotation launched), with fix_reason ("captured fare at 100%, level 110%"). moves counts the moves, off_level the routes set back. actions: the Ticket price adjustments (baseline default price), route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): first the set-back changes (fix true, with the reason), then the week's moves, each in the routes' order (hub, dest), one action each way (From hub to dest, then From dest to hub) with classes ["economy","business"] when both cabins go to the same level, otherwise one each way for each cabin, economy first; a route whose levels don't change gets no move. Each action has n, route, classes, from, to, level, sign, pct, baseline, fix, reason (a set-back's) and text, the text in the game's words naming the classes. settings: the numbers used, with capacity_hold_days and baseline_day. notes: what it doesn't do yet (a rival's pause, step 4) and how the index reads. Staff only; runs as owner and checks the caller itself. |
| `fare_plan_status(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Performance's fare plan for one airline (#18 build pull request 10, Review's until 20 Oct; the old planner's routeFares and farePlanStatus), from the fares and loads its captures give for each of its routes, both directions (the last 9 days' loads, one per date and flight number): plan, each fare change not dropped (fare_plan, by id) with its row's fields and updated_at, the fare now (the latest captured day's average), the target (fare then × (1 + change)), applied and seen_on and the average load before and after that day. A fare test (no level_pct) is read in economy and seen on the first captured day on or after it was proposed whose average fare shows at least half the change; a fare ladder's row (level_pct and ladder_move, since 21 Oct, manual §5) is read in its own cabin (business on flights with business seats) and seen when the day's average fare is the fare then times (1 + change), within 1%. And fares: each route's latest captured day with its average economy fare (what "+ fare plan" starts from). Staff only; runs as owner and checks the caller itself. |
| `growth_signals(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The Check screen's growth lists across our airlines in a world (the default world when null; decision #19, design §8; the old planner's capSignalsHtml and patterns): from route_profit() and aircraft_profit() over growth_window_days, ready for another flight (mark add, by profit a week), raise fares (by flights), fix or reduce (losing or fix, by profit a flight) and aircraft losing money after their lease (by net); and the load patterns: each route's departures over the load window (load_window_days, ending two days ahead, leaving out each rotation's first load_leeway_days) by load band, marked cut, watch, add or hold from the pattern_* settings. profit_captured: whether any bank-statement line was posted since midnight UTC 8 days before p_as_of (the old Home lists the routes the load patterns mark cut when none was). Staff only; runs as owner and checks the caller itself. |
| `hub_progress(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Hubs first (manual §3; decision #19, design §8; the old planner's hubProgressHtml): for each of our active airlines in a world (the default world when null), its main hub's departures a week flying and those on plan cards of aircraft not yet filed, against hub_first_departures, and whether it is exempt (hub_first_exempt); and for each of its other bases, from the latest world scan by p_as_of, the busiest rival there and whether it is contested: a rival with more than contested_rival_weekly departures a week at the base, or more than contested_rival_daily a day on a route from it (listed). Staff only; runs as owner and checks the caller itself. |
| `ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Receives the world scanner's results (start, airlines, airports, finish) into game_scans, game_scan_airlines, game_scan_schedules and game_scan_airports; finish builds the scan's airport summaries. Kind markets takes the weekly report's market summaries for a scan (scan_airline_markets). Every airline a scan sees gets an airlines row (change log actor script). Same kinds, payloads and answers as before #13. Needs the ingest secret. |
| `is_planner_user()` | boolean | authenticated · runs as owner | True when the signed-in email is on planner_users. Used by the access rules, the planner and the Photos functions. |
| `loads_by_day(p_world_id bigint, p_from date, p_to date)` | jsonb | authenticated · runs as owner | The loads days from p_from to p_to (at most 62 days apart) in a world (the default when null), as the planner's Loads by hand reads them (#18 build pull request 14; until then through planner_loads_get()): {date: {done, f: {"Airline|flight": economy %}, source: capture when a capture reached the day, savedAt: when it was last saved by hand (ms), entries: the typed load_entries rows with their updated_at, flags: the load_days row or null}}. The loads and the complete mark by the captured figures' rules as of now (private.fig_load_values(), private.fig_load_days()): a typed figure wins where it is newer than the day's capture. A day with nothing captured or typed isn't there. Staff only; runs as owner. |
| `order_cabin(p_airline_id bigint, p_type_id bigint)` | jsonb | authenticated · runs as owner | The cabin layout an order of a type comes with for an airline (decision #18, build pull request 7; private.fig_order_cabin(), since 15 Oct the data Reference changes: the airline's own in airline_order_cabins, else the type's aircraft_types.order_config_id, filled from the old planner's DEFAULT_CABIN): {id, code, cabin, cost, aircraft_type_id}, or null when there is none. Filing an aircraft into the planner logs its first cabin fit at this cost when the order names no cabin of its own (the old filePlan and cabinCostM). Staff only; runs as owner and checks the caller itself. |
| `parse_capture(p_id bigint)` | jsonb | internal only · runs as owner | Retired by #13 (pull request 3): the parsing is private.capture_page(), which this now calls. No longer callable by signed-in accounts once 20261009230100_capture_data_removals.sql has run; kept until #18. |
| `planner_data_set(p_secret text, p_key text, p_value jsonb)` | jsonb | anon, authenticated · runs as owner | Writes the route research (key DATA: routes, coords, utc, countries) to the countries, airports and routes tables, only the rows that change (private.research_apply(); change log actor script unless the caller named itself), and answers what changed under tables. Any other key is refused: the old planner's planner_data went with it at the clean-up (build pull request 14). Needs the ingest secret. |
| `planner_save(p_changes jsonb, p_client text)` | jsonb | authenticated · runs as owner | The new planner's one way to write (decision #18, design §6): one call per action, with every row it changes, as a list of {table, op (insert, update or delete), key (the primary key, e.g. {"id": 812}), base (the row's updated_at as loaded; needed for an update or delete), values (the columns to set)}. An insert may name the row it makes (as: a name), and a later change in the same call may take a column's value from that row's key (from: {column: name}), so a to-do and its steps are one action. All or nothing: if any row to update or delete was changed or removed since it was loaded, nothing is written and the answer is {ok: false, clashes: [{table, key, current (the row now, or null if it's gone)}]}; otherwise {ok: true, rows: [{table, op, key, updated_at}]}, inserts included. Only the 33 planner tables the change log covers (airline_order_cabins since 15 Oct), and only their own columns; their checks still apply. Written as actor planner with p_client (the tab's ID) as the detail. Staff only; runs as owner and checks the caller itself. |
| `route_loads(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Each route's and each flight's economy loads over the last 7 days for our airlines in a world (the default world when null; decision #19, design §9: Home's map and Routes' loads; the old planner's loadStats): every flight each day's load report covers on the 7 days to p_as_of's UTC date (from and to), done days only, on a captured day only the flights the capture has a load for, none before its rotation's launch, a flight without a load counting as 97.5%: departures, their sum and average, how many at 95% or more (or not reported), under 95, under 85 and under 70, and the days seen. routes: by route, in airline position, hub and destination order; flights (#18 build pull request 6, the Routes screen's lines): the same by airline and flight number, in airline position and number order. Staff only; runs as owner and checks the caller itself. |
| `route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | Each route's profit over the last p_days (1, 3 or 7; decision #19, design §8; the old planner's routeProfit): every bank-statement block with one route, matched to the nearest loads row of that route departing within 31 minutes, grouped by the route as the airline has it: flights, profit, income, margin, profit a flight and a week (× flights a week planned), average economy, business and cargo load and economy fare, departures sold out and their share, and the mark (add a flight, raise fares, fix or reduce, losing money, hold) from the growth_* settings, with why; plus how many flights, how many matched to loads, blocks with several routes (mixed), and the average flight's income and costs, with their sums, its profit and its margin (#18 build pull request 10, the old rpCost). Money in millions of AS$. Staff only; runs as owner and checks the caller itself. |
| `rules_input(p_world_id bigint, p_routes text)` | jsonb | authenticated · runs as owner | Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world's values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats); cabin_configs (code, type, seats and, since 21 Oct, the layout's name, cabin); every airport any route, leg or base uses (position, country and its region, UTC offset with the world's correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name, whether low cost: is_lcc), each with its settings as they apply to it (its own overrides in place of the world's values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren't removed (distance and market with any override applied, and since 21 Oct the market's layout, market_layout, and the route's own cabin_choice, for the plan card's cabin); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg; and service_profiles (code, airline or none for the shared ones, up to km), for the plan card's service check (#18 build pull request 10). p_routes: all (the default) or flown, the new planner's lighter start (#18, design §5): only the routes that have rotations, and only the airports they, the legs, the bases and the aircraft use; the rest of the document is the same. The new planner (flown), the scripts (export_for_report('rules'), all) and Claude's command (node lib/rules/dist/cli.js) build the library's Rules object from it. Staff only; runs as owner and checks the caller itself. |
| `save_script(p_secret text, p_name text, p_content text)` | jsonb | anon, authenticated · runs as owner | Stores a copy of a script in planner_scripts, from before the repository existed. Needs the ingest secret. |
| `site_admin(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Publishes website content: newsroom posts, reports and site content. Content mct (minimum connection times, {airport code: minutes}) also sets world_airports, which site_public() reads (private.world_mct_set(); change log actor script unless the caller named itself); site_content.mct is kept too (the planner's Reference shows it). Needs the ingest secret. |
| `site_investor(p_password text)` | jsonb | anon, authenticated · runs as owner | The investor page's data, when the password matches report_access: cash and next-7-day costs by date and airline in millions (the capture's figure unless typed by hand in cash_entries, as the planner rounds them), money spent from spending_log, markets from site_content, and the investor reports list. Runs as owner. |
| `site_newsletter(p_id bigint)` | jsonb | anon, authenticated · runs as owner | A published gander monthly issue, with its PDF. |
| `site_public()` | jsonb | anon, authenticated · runs as owner | Everything the public website shows, in one call: hubs and focus cities an airline flies from, aircraft flying (status active, in the order they were added, as the planner's Tails lists them, since the clean-up), the week's frequencies (local times), signed interlines, posts, the reports list, site_content (photos, logos, and since 15 Oct the airports' website names and city photos, content.airport_cities), the minimum connection times (content.mct) and the longest wait for a connection (content.connection_max_wait_h, hours, from settings; the trip search's window with the planning library, #19), built from the tables (#13, pull request 8), plus our airlines (names, codes, colours, the website's text, display order) from airlines. updated_at: when the planner's data last changed (the latest change in the change log for the world, or to airports and countries). No bank or transfer times, cabin layouts or aircraft on order (6 Oct). Anyone may call it; runs as owner. |
| `site_remove_airline_logo(p_airline text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: goes back to the in-game logo for an airline. Staff only. |
| `site_remove_airport_photo(p_code text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: removes a destination photo. Staff only. |
| `site_report(p_id bigint, p_password text)` | jsonb | anon, authenticated · runs as owner | One investor report with its PDF, when the password matches report_access. |
| `site_set_airline_logo(p_airline text, p_url text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets an airline's logo after the upload, for one of our airlines in airlines (by the planner's name for it). Staff only. |
| `site_set_airport_photo(p_code text, p_url text, p_credit text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets a destination photo and its credit after the upload. Staff only. |
| `system_status(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | authenticated · runs as owner | The Systems board on the planner's Check screen (#23), read only, as of p_as_of (now by default) in a world (the default when null): capture, each airline's latest page and verdicts (capture_status()'s airlines); snapshot, the latest day in airline_days with how it was taken (source capture, or fallback and so incomplete), the latest snapshot job and when the 10:00 UTC job last ran; backup, its latest run and latest good copy (restore check passed) with its size; archive, its runs this month, its latest run and any table and month whose latest run failed; cleanup, its latest run; scan, the latest world scan with its airport summary; usage, the database's size, the report PDFs in site_reports (three quarters of their base64 text) and the size of site_public(), each with its trigger (manual §1: 350 MB, 50 MB, 500 KB), measured now. The board marks them. Staff only; runs as owner. |

## Internal functions

In the `private` schema, which the data API doesn't expose (#13): trigger functions and helpers that only the database itself and postgres use.

| Function | Returns | Who can call it | What it does |
|---|---|---|---|
| `private.airport_offset_min(p_world_id bigint, p_code text)` | integer | internal only | An airport's UTC offset in a world, in minutes: coalesce(world_airports.utc_offset_override, airports.utc_offset). Null while it isn't known (the airports are loaded by #13's pull request 4). |
| `private.archive_check_args(p_month date, p_table text)` | void | internal only | Refuses a table the archive may not touch, or a month not given as its first day. Used by every archive function. |
| `private.archive_checksum(p_month date, p_table text, OUT rows bigint, OUT checksum text)` | record | internal only | A table's month: its row count and the md5 of every row as Postgres prints it (timezone UTC, ISO dates), joined by newlines, in primary-key order. |
| `private.archive_delete(p_month date, p_table text, p_expected_count bigint, p_checksum text)` | jsonb | internal only | The guarded delete (design §7), the only way the archive removes rows: refuses a table not listed, a month inside the kept window, a count or checksum that no longer matches, and for game_flights a month whose flights aren't all in route_days or that statement lines still point at, naming every reason in one refusal. Otherwise deletes exactly those rows (checked again as they go), records the run in job_runs (job archive, for_month) and answers with what it deleted and the row's id. Locks the table against writes while it works. postgres only. |
| `private.archive_due(p_as_of date)` | TABLE(table_name text, month date, rows bigint) | internal only | What the monthly archive has to do (design §7): each table's months older than its kept window that still have rows, with their row counts, oldest first. Called by the archive step in equinox-backups every night (it runs on the first night on or after the 1st, and again each night until nothing is due). p_as_of: the day, default today in UTC (for the checks). postgres only. |
| `private.archive_kept_from(p_table text, p_as_of date)` | date | internal only | The first month a table still keeps on a day (design §7): everything before it may be archived. For one month kept, on any day of December it is November, so October may go. |
| `private.archive_manifest(p_month date, p_table text)` | jsonb | internal only | The manifest the archive step stores beside a table's month (design §7): row count, checksum (private.archive_checksum), the table's layout (columns and types) and the latest migration version, whether the month is due, and the export query. postgres only. |
| `private.archive_order(p_table text, p_as text)` | text | internal only | A table's primary key as an order for the archive, text columns in byte order (collate "C"), so the order and the checksum are the same on any database. |
| `private.archive_select(p_month date, p_table text)` | text | internal only | The query the archive step (equinox-backups) exports a table's month with, in the same transaction as the manifest: every column, in primary-key order. postgres only. |
| `private.archive_tables()` | TABLE(table_name text, month_of text, keep_months integer) | internal only | The tables the monthly archive may delete from (design §7), what decides a row's month, and how many full calendar months each keeps: game_flights, game_events, game_scan_schedules and game_scan_airports one; change_log 12. |
| `private.archive_where(p_month date, p_table text, p_as text)` | text | internal only | A table's month as a condition on the table under an alias: one rule for the manifest, the export and the delete. game_flights by dep_at in UTC (by the game's date where dep_at isn't known, as the daily history counts it), game_events by event_date, the scan tables by their scan's time, change_log by changed_at. |
| `private.backup_runs_insert()` | trigger | internal only | Instead-of-insert trigger on the backup_runs view (design §3.12): turns the backup job's row into a job_runs row (job backup; ok or failed; its kind, counts, R2 key and commit in details) and answers with its id and time. Refuses a kind other than nightly, manual or test, or no ok, as the old table did. |
| `private.briefing_doc(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The airline briefing (#24): one airline's document for export_for_report('briefing'), read only, with no check of its own: the airline (id, world, code, names, game ID); deliveries, its aircraft not yet filed (status on_order or delivered) with type, cabin as ordered and now, bases, order date and note, delivery time and whether it has arrived by p_as_of, and each one's plan cards (with the card's cabin, config_id, since 21 Oct) with their legs in order (UTC weekdays and minute, block, service code); todos, the open to-dos (not done) of the airline and of the group (no airline), with their steps; fare_plan, fare_plan_status()'s document (private.fig_fare_plan()); fare_ladder, each route and cabin's fare level from fare_ladder() (route_id, hub, dest, cabin, level, new_level and planned: the new level is the one to show once this week's move is on the fare plan) with week_of and settings.launch_pct (the level of a route not flown yet), for the plan card check's fare line (since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §2); route_loads, route_loads()'s routes and flights for this airline only (private.fig_route_loads()). Deliveries, plan cards and to-dos are the tables as they are now; the fare plan, the fare levels and the loads are as of p_as_of. |
| `private.caller_is_staff()` | boolean | internal only | True for planner staff (their sign-in) and for postgres itself (Claude, jobs, migrations), the way the getters decide. Used by the write functions that run as owner. |
| `private.capture_airline_verdict(p_airline_id bigint, p_at timestamp with time zone)` | jsonb | internal only | An airline's capture as at a moment (#21): the latest page of each kind in that moment's capture day (10:00 to 10:00 UTC) up to the moment, with its verdict, and the airline's verdict: broken if any page is, short if any is or a kind wasn't captured, ok when every page is; null when no page was judged (stored before the checks). words: "all good", or what came in short or broken. |
| `private.capture_check(p_raw_id bigint, p_parse jsonb, p_expect jsonb)` | jsonb | internal only | Judges one stored capture page and keeps the verdict on it (game_capture_raw.verdict, verdict_note, verdict_facts; #21). p_parse is private.capture_page()'s answer (its rows read) or the parse error; p_expect what to expect (private.capture_expect() when null; the tests give their own). The limits are settings: capture_loads_min_share and capture_statement_min_share. Answers the verdict with its facts; null for page inspection (html). |
| `private.capture_day(p_world_id bigint, p_at timestamp with time zone)` | date | internal only | The capture day a moment belongs to (design §2): the UTC date of the moment minus capture_day_starts_utc (10:00 until set), so one evening's capture is one day, named after the evening. |
| `private.capture_day_complete(p_world_id bigint, p_day date)` | boolean | internal only | Completeness by world (design §7): true when every active airline of our groups in that world has all five pages (statement, events, income statement, balance sheet, loads) in that capture day. Not a count to 6, so a 7th airline must be captured too. |
| `private.capture_day_start(p_world_id bigint, p_day date)` | timestamp with time zone | internal only | When a world's capture day starts, in UTC: the day plus the setting capture_day_starts_utc (10:00 until it is set), design §2. |
| `private.capture_expect(p_raw_id bigint)` | jsonb | internal only | What to expect of one stored capture page, from what the database knows at the page's moment (#21). Loads: scheduled, the airline's flights departing in the page's window (the game's -24h: the 24 hours before the capture), from its flight legs and their UTC weekdays, each rotation from the day after it launched, and a leg with an aircraft only once that aircraft has flown (its registration named by the airline's captured loads before the page; since 15 Oct, as a new aircraft can start flying days after it's filed). Statement: median_lines, the median of the lines on the airline's latest statement page on each of up to 7 earlier capture days, and nights, how many. Other kinds: nothing. |
| `private.capture_fare_actions_doc(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The fares userscript's list (specs docs/specs/2026-10-21-fares-userscript.md and docs/specs/2026-10-21-frequencies-and-fares.md §3): builds capture_fare_actions()'s document for one world at a moment, with no check of its own. See capture_fare_actions(). |
| `private.capture_find_airline(p_world_id bigint, p_airline text)` | bigint | internal only | The airline a capture page is for, among the airlines of our groups in the key's world: by the game's ID (the userscript from version 1.3), or by name as the older userscript and the bookmark send it (the names matched since 7 Oct). Null when none or more than one fits, so the page is refused. |
| `private.capture_judge(p_kind text, p_read integer, p_error text, p_cash boolean, p_expect jsonb, p_loads_min numeric, p_statement_min numeric)` | jsonb | internal only | The verdict on one capture page (#21), from what was read and what was expected; reads no table. Broken: the page didn't read (p_error), or a balance sheet without the cash account (2800). Short: loads fewer than p_loads_min of the flights scheduled; a statement with no lines, or fewer than p_statement_min of the recent median; events or an income statement with no rows. Otherwise ok. Answers {verdict, note (in words), facts}; null for a kind it doesn't judge (html). |
| `private.capture_key_world(p_key text)` | bigint | internal only | The world a capture key belongs to (capture_keys.world_id), or null for a key that doesn't match. |
| `private.capture_page(p_raw_id bigint)` | jsonb | internal only | Parses one stored capture page into the capture tables, using the page's own capture time throughout: statement lines into game_statement, folded into game_flights and game_payments; events into game_events (with due_at where known); loads into game_flights; the income statement and balance sheet into game_pnl and game_balance (with capture_day), each row's figures and capture time from the same capture, the latest (#13 pull request 6). Then money and loads are matched. |
| `private.capture_panel_words(p_reply jsonb)` | text | internal only | The capture panel's words after an airline's loads page (#21): what was read, then one line for the airline: "all good", or what came in short or broken, ending on the loads as "12 of 78" because the userscript adds " flights". capture_ingest() puts them in its reply's rows, so the userscript needs no change. |
| `private.capture_refresh(p_world_id bigint)` | jsonb | internal only | For every airline of our groups in a world: fills flight times and events' due_at that have become known, then matches money to loads. Run once after the airports are loaded (#13, pull request 4); the capture does the same for one airline after each page. |
| `private.capture_statement_lines(p_rows jsonb)` | integer | internal only | The lines a bank statement page holds, as the reader takes them: rows whose first filled cell is a date and time (DD.MM. HH:MI). The recent nights a statement page is checked against are counted with it (#21). |
| `private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean)` | jsonb | internal only | Stores one page for an airline of the given world and parses it, at the given capture time, checks it (private.capture_check(), #21: its verdict kept on the raw page and given under verdict; after the loads page, the airline's capture as it stands under airline_verdict), and says whether that capture day is now complete. When the page completes the world's capture for the day (private.snapshot_due), takes the daily snapshot (private.take_snapshot, one job_runs row, ok or failed; a failure never loses the page) and answers with it under snapshot. Refuses a page for an airline outside the world. capture_ingest() calls it with now(); the tests replay saved pages with their own times. p_loads_step is no longer used: the old planner's loads step went with the clean-up (build pull request 14). |
| `private.check_leg_route()` | trigger | internal only | Trigger on flight_legs: refuses a leg whose airports don't match its rotation's route in its direction (leg 1 from the hub to the destination, leg 2 back). |
| `private.check_route_legs()` | trigger | internal only | Trigger on routes and rotations: refuses changing a route's airports, or a rotation's route, when its flight legs would no longer match. |
| `private.fig_airline_cards(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds airline_cards()'s document with no check of its own. See airline_cards(). |
| `private.fig_airline_world(p_airline_id bigint)` | bigint | internal only | The captured figures (#19): an airline's world; refuses an airline that doesn't exist. |
| `private.fig_airlines(p_world_id bigint)` | TABLE(airline_id bigint, ord integer, iata_code text, name text, home_code text, main_code text) | internal only | The captured figures (#19): our active airlines in a world, in display order, each with its code, name, home airport (fig_home) and main base (null for none). |
| `private.fig_capex(p_airline_id bigint, p_d0 date, p_d1 date)` | numeric | internal only | The captured figures (#19): the old planner's capexIn(), order payments (orders and cabins, not losses) logged after the first date up to the second, in millions. |
| `private.fig_capture_status(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): the capture board's document (captureBoard), each airline's pages today and yesterday (UTC), flights by departure date, what is missing today and its status; since #21 also its latest page (last_at) and that capture's verdicts (private.capture_airline_verdict(): verdict, verdict_words, verdict_at, verdict_day and each kind's under verdicts). See capture_status(). |
| `private.fig_cash_days(p_airline_id bigint, p_as_of timestamp with time zone)` | TABLE(day date, cash numeric) | internal only | The captured figures (#19): the old planner's finSeries(), an airline's cash by date in millions: each capture date's latest balance rounded to 0.01M (a figure typed in cash_entries wins before the last 7 days), up to p_as_of. |
| `private.fig_cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone, p_lease_map jsonb)` | jsonb | internal only | The captured figures (#19): builds cash_forecast()'s document with no check of its own; p_lease_map: fig_lease_map() for the world when the caller has it already. See cash_forecast(). |
| `private.fig_cash_log(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds cash_log()'s document with no check of its own. See cash_log(). |
| `private.fig_day_captured(p_world_id bigint, p_day date, p_as_of timestamp with time zone)` | boolean | internal only | The captured figures (#19): loads_day_captured() as of p_as_of, whether every active airline of ours in the world had been captured for that date by then. |
| `private.fig_day_ops(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)` | TABLE(day date, airline_id bigint, flights integer, aircraft integer, load numeric) | internal only | The captured figures (#19): the old planner's dayOps(), per local date and airline, the flights flown (rotations launched by then), the aircraft, and the average load once the day is done (a flight without a load counts as 97.5%; on a captured day only the flights it has). |
| `private.fig_events(p_world_id bigint, p_as_of timestamp with time zone, p_airline_id bigint)` | TABLE(airline_id bigint, at timestamp with time zone, amount numeric, descr text, event_date date, event_time text) | internal only | The captured figures (#19): the events page's payments as the old planner loads them (CAP.events): debits from the first balance date of the 7 days to p_as_of to 16 days ahead, each at its UTC moment from the airline's home airport's offset in the world (private.airport_offset_min(), with the world's correction, since the clean-up; the old planner's eqOff had none), in millions. p_airline_id: one airline's, or null for all. |
| `private.fig_export(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): every figure for every airline of a world in one document, for export_for_report('figures'), with no check of its own. |
| `private.fig_fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds fare_ladder()'s document with no check of its own. See fare_ladder(). |
| `private.fig_fare_plan(p_airline_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds fare_plan_status()'s document with no check of its own. See fare_plan_status(). |
| `private.fig_fin_stats(p_airline_id bigint, p_as_of timestamp with time zone, p_ops jsonb)` | jsonb | internal only | The captured figures (#19): builds the old planner's finStats() for one airline (its card and its profit for each day between captures) with no check of its own; p_ops: dayOps for the world when the caller has it. See airline_cards() and airline_profit(). |
| `private.fig_fits(p_t timestamp with time zone[], p_v numeric[], p_td timestamp with time zone, p_n integer, p_price numeric, p_lease numeric, p_cushion numeric)` | boolean | internal only | The captured figures (#19): cashForecast()'s fits(), whether orders placed at a moment keep the cushion at every forecast point from then on, counting their price and their own weekly lease from 7 days after they are ordered (manual §3). |
| `private.fig_flag(p_world_id bigint, p_airline_id bigint, p_key text)` | boolean | internal only | The captured figures (#19): a true-or-false setting, the airline's own value where it has one, else the world's; false when neither is set (hub_first_exempt). |
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
| `private.fig_num(p_world_id bigint, p_airline_id bigint, p_key text)` | numeric | internal only | The captured figures (#19): a rule number from settings, the airline's own value where it has one, else the world's; refuses one that is missing or not a number. |
| `private.fig_ops_recent(p_airline_id bigint, p_as_of timestamp with time zone)` | TABLE(flights bigint, income numeric, costs numeric, last_ts timestamp with time zone) | internal only | The captured figures (#19): game_ops_recent as of p_as_of, the airline's flights, income and costs in the 24 hours before its latest statement line. |
| `private.fig_order_cabin(p_airline_id bigint, p_type_id bigint)` | bigint | internal only | The captured figures (#19): the cabin layout an order of a type comes with for an airline, as data since 15 Oct (spec 2026-10-15 last leftovers §1): the airline's own (airline_order_cabins), else the type's (aircraft_types.order_config_id); null for an airline or type that isn't there. Before, worked out from the cabin names (the old planner's DEFAULT_CABIN: Standard for a low-cost airline, else Leisure, else Comfort; the airline's market default among two of the same cabin, then the newest), which filled the data. |
| `private.fig_patterns(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): the old planner's patterns(), each route's departures over the load window by load band and its mark (cut, watch, add, hold) from the pattern_* settings. See growth_signals(). |
| `private.fig_route_loads(p_world_id bigint, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): the old planner's loadStats() over the last 7 days, for each route and each flight number, with no check of its own. See route_loads(). |
| `private.fig_route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)` | jsonb | internal only | The captured figures (#19): builds routeProfit()'s document (routes, aircraft, fare changes, the average flight) with no check of its own; each flight's departure in UTC from its origin's offset in the world, with its correction (since the clean-up). See route_profit(), aircraft_profit() and fare_changes(). |
| `private.fig_ts(p timestamp with time zone)` | text | internal only | The captured figures (#19): a moment as they give it, UTC to the millisecond (2026-10-12T21:05:00.000Z). |
| `private.fig_type_key(p text)` | text | internal only | The captured figures (#19): an aircraft type's name as the old planner's leaseM() compares names: upper case, AIRBUS dropped, EMBRAER as E, letters and digits only. |
| `private.fig_world(p_world_id bigint)` | bigint | internal only | The captured figures (#19): the world asked for, or the default world when null; refuses one that doesn't exist. |
| `private.fill_due_at(p_airline_id bigint)` | integer | internal only | Fills an airline's game_events.due_at once its home airport's offset is known. |
| `private.fill_flight_links(p_world_id bigint)` | jsonb | internal only | The route and aircraft of a world's captured flights that don't have them yet: the route by the schedule's leg with that number and direction, else the airline's route that way or the other way; the aircraft by the registration the loads page or the statement names. |
| `private.fill_flight_times(p_airline_id bigint)` | integer | internal only | Fills an airline's loads rows' dep_at and arr_at where the airports' offsets have become known since they were captured. |
| `private.fold_statement(p_airline_id bigint, p_minutes timestamp with time zone[])` | integer | internal only | Folds an airline's statement lines in the given minutes into game_flights (one row per flight block, matched by minute and block) and game_payments (every other line), and ties each flight line to its flight (game_statement.flight_id). Blocks that changed since are taken apart and folded again; a flight already matched keeps its loads. Run after every statement page, and by the backfill for every minute. |
| `private.history_cash(p_world_id bigint, p_day date, p_at timestamp with time zone)` | TABLE(airline_id bigint, cash numeric, fixed_next7 numeric, cash_at timestamp with time zone) | internal only | The daily history's cash for a capture day, per active airline of our groups (design §7): the day's latest balance of account 2800 up to the moment, with the payments due in the 7 days after it (as capture_cash); with no balance that day, cash_entries by the planner's date. |
| `private.history_fleet(p_world_id bigint, p_at timestamp with time zone)` | TABLE(airline_id bigint, aircraft_by_type jsonb, aircraft_total integer, on_order integer) | internal only | The daily history's fleet at a moment, per active airline of our groups (design §7, §9 step 4): aircraft flying (by type, and the total) from arrival in the game (delivery_at; one with no delivery record from the start) until retired, unless still marked on order; on order from the order date until then. With the moment now it agrees with aircraft.status. |
| `private.history_flows(p_world_id bigint, p_from date, p_to date)` | jsonb | internal only | The daily history's flows for a span of UTC days (design §7): route_days replaced for those days, and each airline_days row of those days given its flights, passengers, seats, loads, money and payments, from game_flights and game_payments. Returns how many rows of each it wrote. |
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
| `private.match_flights(p_airline_id bigint)` | integer | internal only | Matches an airline's money-only and loads-only game_flights rows (design §3.8): per route, in time order so two flights on one route never swap, a block pairs with a loads row whose scheduled departure is 30 minutes after to 3 hours before the statement time, of the same aircraft where the statement names one; the most pairs win, then the smallest total gap. Unpaired rows wait for their partner. Needs the airports' offsets. |
| `private.merge_flight(p_money_id bigint, p_loads_id bigint)` | boolean | internal only | Joins one money-only game_flights row and one loads-only row into one flight: the loads columns move into the money row, and the loads row goes. |
| `private.payment_kind(p_descr text)` | text | internal only | The kind of a statement line that isn't tied to a flight (game_payments.kind): lease, salaries ("Payment of employee salaries", the week-end closing), deposit, purchase, refit (a configuration), cabin (a cabin, and since 15 Oct the pilot training that comes with an order: "Pilot training", 20261015200000), or other. |
| `private.payment_registration(p_descr text)` | text | internal only | The aircraft a payment names, e.g. B-0161 from "Leasing rate for B-0161". Null when it names none. |
| `private.research_apply(p_world_id bigint, p_doc jsonb)` | jsonb | internal only | planner_data_set()'s step for the route research (key DATA: routes, coords, utc, countries): writes countries, airports and a world's research routes, only the rows that change, by the loader's rules. Added routes and the planner's overrides are never touched; a research route no longer listed goes unless something points at it or it carries an edit. A new UTC offset for an airport that flights or plan-card legs use (with no world correction) is held back and named, since their UTC times were worked out with the old one (design §4). A part missing from the document leaves its rows alone. Returns how many rows each part changed. |
| `private.restore_row(p_table text, p_row_key jsonb, p_as_of timestamp with time zone)` | jsonb | internal only | Puts one row of a logged table back as it was at a moment, by replaying change_log backwards: re-adds a removed row with its own key, undoes changes, or removes a row added since. The restore is logged like any change. For Claude, as postgres: start with the equinox.actor line (design §6). |
| `private.rules_input_doc(p_world_id bigint, p_routes text)` | jsonb | internal only | The planning library's input for a world (decision #19, design §7), with no check of its own: what rules_input() gives staff and export_for_report('rules') gives the scripts (always 'all'). See rules_input(). p_world_id: the world, or null for the default world; p_routes: all (every route that isn't removed) or flown (only routes with rotations, and only the airports they, the legs, the bases and the aircraft use). |
| `private.scan_airline(p_world_id bigint, p_game_id integer, p_name text)` | bigint | internal only | The airlines row of an airline a world scan saw, by game ID, added when new (design §3.9: rivals can then be placed in groups); a rival's game_name follows the game, ours are left alone. Null without a game ID. |
| `private.scan_summarise(p_scan_id bigint)` | integer | internal only | Builds a world scan's airport summaries (scan_airline_airports) from its schedules: per airline and airport, departures a week and destinations. Run when a scan finishes; a scan whose schedules were archived keeps what it has. Returns the rows written. |
| `private.schedule_jobs()` | jsonb | internal only | Schedules the two database jobs with pg_cron, by name, so it can run again safely: equinox-snapshot-fallback at 10:00 UTC (private.job_snapshot_fallback) and equinox-cleanup at 10:20 UTC (private.job_cleanup). Run by migration 20261011150000_jobs, and again after a full restore (the backup copies no schedules). Answers with the jobs as the scheduler has them. |
| `private.set_updated_at()` | trigger | internal only | Trigger on every planner table: sets updated_at when a row is added or really changes, and leaves it as it was when an update changes nothing. |
| `private.shift_weekdays(p smallint[], p_days integer)` | smallint[] | internal only | ISO weekdays moved by whole days (−1: each a day earlier, Monday becomes Sunday), sorted. Turns local weekdays into UTC ones and back (design §4). |
| `private.snapshot_due(p_world_id bigint, p_day date, p_at timestamp with time zone)` | boolean | internal only | Whether a page at p_at completes a world's capture for the day: every active airline of our groups has all five pages since the day started, or since the last snapshot taken from a complete capture that day. So one snapshot per complete capture, taken by its last page. |
| `private.statement_blocks(p_airline_id bigint, p_minutes timestamp with time zone[])` | TABLE(ts timestamp with time zone, blk integer, is_flight boolean, route text, routes_n integer, pax integer, tail text, pax_income numeric, cargo_income numeric, fuel numeric, onboard numeric, handling numeric, landing numeric, atc numeric, maintenance numeric, income_total numeric, cost_total numeric, captured_at timestamp with time zone) | internal only | An airline's statement lines in the given minutes, grouped by minute and block (blk) as game_flight_pnl has always grouped them, leaving out payments: money by type, the route, passengers, the maintenance line's aircraft, and whether the block is a flight (any flight line or route) or only payments. |
| `private.statement_category(p_descr text)` | text | internal only | The type of a bank-statement line (pax_income, cargo_income, fuel, onboard, handling, landing, atc, maintenance or other), as game_flight_pnl has always counted them. |
| `private.take_snapshot(p_world_id bigint, p_day date, p_at timestamp with time zone, p_source text, p_flows boolean)` | jsonb | internal only | The daily snapshot of a world's capture day (design §7): point-in-time figures (fleet, schedule, cash) as at p_at (default now) into airline_days for each active airline of our groups, with source (capture, fallback or backfill) and whether the day's capture was complete; then (p_flows) the flows of that UTC day and the two before. A later snapshot replaces the point-in-time figures, but a fallback or backfill never replaces one from a complete capture. Called by the capture when a day completes; pull request 7's 10:00 UTC fallback calls it too. |
| `private.world_mct_set(p_world_id bigint, p_mct jsonb)` | jsonb | internal only | site_admin()'s step for content mct: a world's minimum connection times from the whole map {airport code: minutes}, into world_airports.mct_min; times of airports the map no longer lists are cleared, and a row nothing else describes goes. Refuses anything but airport codes with whole minutes, 0 to 1440. Returns how many were set, cleared and removed. |

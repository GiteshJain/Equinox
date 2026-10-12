# The database, table by table

Generated from the database's own descriptions by `database/describe.py`. Don't edit by hand: change the
description in a migration (`comment on table ...`), and the database rehearsal regenerates and checks this
file. How the parts fit together: `docs/architecture.md`.

63 tables, 8 views and 35 functions, all in Supabase's `public` schema, plus 104 internal functions in `private`. Website photos and logos are files in the `site-photos` storage bucket, not tables.

## Contents

- [`adapter_check_days`](#adapter-check-days) (view): Per world and capture day, the side by side's runs (design §9): how many comparisons and mirrors, how many failed, and whether the day is clean (at least one comparison and nothing failed)
- [`aircraft`](#aircraft) (table): Each aircraft from order to delivery to service to retirement, one row each
- [`aircraft_cabin_keeps`](#aircraft-cabin-keeps) (table): "Keep this cabin" decisions: the aircraft keeps its cabin although its routes call for this one, until they call for a different cabin
- [`aircraft_types`](#aircraft-types) (table): Aircraft types and their figures in a world: seats, cruise speed, turns, maintenance, price
- [`airline_aircraft_types`](#airline-aircraft-types) (table): The aircraft types each airline may buy
- [`airline_bases`](#airline-bases) (table): Each airline's hubs and focus cities, with bank times and flight-number blocks
- [`airline_days`](#airline-days) (table): The daily history (decision #15, design §3.10, §7): one row per airline of our groups per capture day (design §2: the evening it was taken, 10:00 to 10:00 UTC), kept for good
- [`airlines`](#airlines) (table): Every airline we track in a world: our own, and from #13's capture work the rivals the world scan sees (their columns about our airlines stay null)
- [`airports`](#airports) (table): Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world's own corrections are in world_airports)
- [`backup_runs`](#backup-runs) (view): The nightly backup's runs (decision #6), in the shape the backup job and the planner have always used: when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied, with the copy's R2 key
- [`backup_runs_before_13`](#backup-runs-before-13) (table): Retired by #13 (pull request 7): the backup runs table as it stood when its rows moved into job_runs (job backup)
- [`cabin_configs`](#cabin-configs) (table): Cabin layouts (e.g
- [`capture_cash`](#capture-cash) (view): Cash and the next 7 days' payments per airline and capture date, from the capture, worked out as the planner does today: the latest balance of account 2800 that date, and the debits the events page lists for the 7 days after it was captured
- [`capture_keys`](#capture-keys) (table): Hashed keys that let the in-game capture send data
- [`cash_entries`](#cash-entries) (table): Cash and the next 7 days' fixed costs, in AS$, typed by hand or kept from before the capture: only figures the capture doesn't give
- [`change_log`](#change-log) (table): Every change to the planner's tables (decision #15): which row, added, changed or removed, the old and new values (for a change, only the columns that changed), when, and who
- [`countries`](#countries) (table): Country names by ISO code (-- for unknown)
- [`dismissals`](#dismissals) (table): Alerts dismissed on the planner's Home, by the old planner's key (e.g
- [`fare_plan`](#fare-plan) (table): Fare tests to make in the game, and whether each is still planned or was dropped
- [`flight_legs`](#flight-legs) (table): One row per flight in the schedule, in UTC (design §4): departure minute, UTC weekdays and block time
- [`flight_legs_local`](#flight-legs-local) (view): Each flight leg with its flight code (KF 1001) and its times as the game shows them: local departure and arrival and local weekdays, plus the arrival in UTC and its day offset
- [`flight_no_clashes`](#flight-no-clashes) (view): An airline's flight number used by two or more legs departing on the same weekday (local at the origin, as the planner's check counts it)
- [`game_balance`](#game-balance) (table): The balance-sheet page from the nightly capture: one row per airline, account and UTC date, each with the figures and capture time of that date's latest capture
- [`game_capture_raw`](#game-capture-raw) (table): Every page the capture sent, as rows of cells before parsing, with its world and airline
- [`game_events`](#game-events) (table): Payments the game lists ahead on the events page: leases, salaries and deliveries
- [`game_flight_pnl`](#game-flight-pnl) (view): Each statement block's income and costs by type and its profit, as before #13, from game_flights only: payments that aren't flights (salaries, leases and the like) are left out
- [`game_flights`](#game-flights) (table): One row per flown flight (decision #16, design §3.8): its loads from the loads page and its money from the bank statement, matched by route and time
- [`game_loads`](#game-loads) (view): Today's game_loads, from game_flights: every captured flight with passengers, seats, fares and loads by class and cargo, in the columns the planner (Check: daily load report, growth signals; Review: fare changes) and export_capture() read
- [`game_loads_before_13`](#game-loads-before-13) (table): Retired by #13 (pull request 3): the loads table as it stood when its rows moved into game_flights
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
- [`load_entries`](#load-entries) (table): Economy loads typed by hand, per flight and game date
- [`markets`](#markets) (table): Each airline's markets with their default aircraft, cabin and fares
- [`monthly_checks`](#monthly-checks) (table): When each monthly check was last done, per airline or for the group as a whole (airline_id null)
- [`plan_card_legs`](#plan-card-legs) (table): A plan card's flights, with the same time rules as flight_legs (UTC)
- [`plan_cards`](#plan-cards) (table): A plan for one aircraft's flying, on order or flying, kept after it is filed as the record of what was planned (whether it is filed is worked out, not stored)
- [`planner_data`](#planner-data) (table): The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries
- [`planner_loads`](#planner-loads) (table): The old planner's daily loads, one JSON document per month
- [`planner_meta`](#planner-meta) (table): Settings kept as data
- [`planner_scripts`](#planner-scripts) (table): Copies of Claude's scripts from before the repository existed
- [`planner_state`](#planner-state) (table): The old planner's whole state in one JSON row (id main)
- [`planner_users`](#planner-users) (table): Email addresses allowed into the planner (staff)
- [`report_access`](#report-access) (table): The password hash for the investor page and investor reports
- [`rotations`](#rotations) (table): An aircraft's out-and-back pair on a route: what the old planner calls a frequency
- [`route_days`](#route-days) (table): The daily history per route, direction and UTC day (design §3.10, §7): each airline's flights, passengers, seats, money and average economy fare, from game_flights (a flight's day is the UTC date it departs), kept for good after game_flights is archived
- [`routes`](#routes) (table): Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner's overrides (null = the research value; research refreshes never touch them)
- [`scan_airline_airports`](#scan-airline-airports) (table): Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and airport, its departures a week from there and how many destinations it flies to from there
- [`scan_airline_markets`](#scan-airline-markets) (table): Summary of each world scan, kept for good (design §3.9, §11 choice 2): per airline and market (the weekly report's market names, e.g
- [`service_profiles`](#service-profiles) (table): On-board service by distance (S1, S2, …)
- [`settings`](#settings) (table): Our own planning choices as data (decision #14): the manual's rule numbers, thresholds and display choices for a world, with per-airline overrides
- [`site_content`](#site-content) (table): Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser; since #13's pull request 8 site_admin() writes them to world_airports too, and site_public() reads them from there, so this copy is kept only for the adapter until the switch-over)
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

## adapter_check_days

*View.* Per world and capture day, the side by side's runs (design §9): how many comparisons and mirrors, how many failed, and whether the day is clean (at least one comparison and nothing failed). adapter_clean_days() counts the clean days in a row. Shows the caller only what it may read.

| Column | Type | Notes |
|---|---|---|
| `world_id` | bigint |  |
| `day` | date | The capture day (design §2: 10:00 to 10:00 UTC) |
| `comparisons` | bigint |  |
| `comparisons_failed` | bigint |  |
| `mirrors` | bigint |  |
| `mirrors_failed` | bigint |  |
| `clean` | boolean | At least one comparison, and no comparison or mirror failed |

## aircraft

*Table.* Each aircraft from order to delivery to service to retirement, one row each. Replaces the planner's tails and deliveries; status active is what the old planner calls a tail.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `registration` | text | e.g. N001AW; a field, not the key, so a re-registration touches one row |
| `aircraft_type_id` | bigint | Today's type |
| `cabin_config_id` | bigint | Today's cabin |
| `base_code` | text | Today's base |
| `status` | text | on_order, delivered (arrived, not yet filed into the planner), active (the old planner's tail) or retired |
| `ordered_on` | date |  |
| `delivery_at` | timestamp with time zone | Arrival in the game (the planner's deliveries[].utc) |
| `order_base_code` | text | Base as ordered |
| `order_config_id` | bigint | Cabin as ordered; can differ from today's after a refit |
| `order_note` | text |  |
| `checked_on` | date | The one-week check, Gitesh's to mark (manual §1) |
| `schedule_changed_on` | date | When its schedule last changed, which restarts the one-week check |
| `maintenance_note` | text | The planner's maint |
| `retired_on` | date |  |
| `extra` | jsonb | For the adapter only: tails_index and deliveries_index, the aircraft's place in the old planner's two lists; and under tail and delivery, any field of those items the table can't give back. Expected otherwise empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## aircraft_cabin_keeps

*Table.* "Keep this cabin" decisions: the aircraft keeps its cabin although its routes call for this one, until they call for a different cabin. Replaces the planner's cabinKeep.

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
| `photo_city` | text | Website: the city whose photo stands for the airline |
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

## backup_runs_before_13

*Table.* Retired by #13 (pull request 7): the backup runs table as it stood when its rows moved into job_runs (job backup). Nothing writes or reads it; the name backup_runs is now a view. Kept so a revert can put it back, until #18.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `ran_at` | timestamp with time zone |  |
| `kind` | text |  |
| `ok` | boolean |  |
| `tables` | integer |  |
| `rows` | bigint |  |
| `files` | integer |  |
| `bytes` | bigint |  |
| `commit_sha` | text | The equinox-backups commit holding that night's copy |
| `note` | text |  |
| `object_key` | text | R2 key of that run's copy (from 9 Oct; earlier runs have commit_sha) |

**Access:** planner staff read backup_runs: select for authenticated.

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

*Table.* Country names by ISO code (-- for unknown). The same in every world. Replaces planner_data.countries; kept in step with the research by planner_data_set().

| Column | Type | Notes |
|---|---|---|
| `code` | text |  |
| `name` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

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

*Table.* Fare tests to make in the game, and whether each is still planned or was dropped. Replaces the planner's farePlan.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `route_id` | bigint |  |
| `legacy_key` | text | The old planner's fare-plan id, kept for the adapter until #18 |
| `cabin_class` | text | economy, business or first |
| `change_pct` | numeric(5,1) | The fare change to make, percent |
| `fare_from` | numeric(14,2) | The fare before the change, AS$ |
| `proposed_on` | date |  |
| `status` | text | planned or dropped |
| `reason` | text |  |
| `extra` | jsonb | For the adapter only: fields the table doesn't know. Expected empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

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

*Table.* Every page the capture sent, as rows of cells before parsing, with its world and airline. Kept 14 days: the 10:20 UTC clean-up (private.job_cleanup, #13 pull request 7) deletes older pages. Written by capture_ingest(). Read by private.capture_page(), completeness (private.capture_day_complete) and the planner's Capture board.

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

## game_loads_before_13

*Table.* Retired by #13 (pull request 3): the loads table as it stood when its rows moved into game_flights. Nothing writes or reads it; the name game_loads is now a view. Kept so a revert can put it back, until #18.

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
| `eco` | numeric | Economy load, percent (bus and fst likewise for business and first) |
| `bus` | numeric |  |
| `fst` | numeric |  |
| `cargo` | numeric |  |
| `status` | text | finished or inflight |
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

**Access:** planner staff read game_loads: select for authenticated.

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
| `kind` | text | lease, salaries, purchase, deposit, cabin, refit or other |
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
| `job` | text | backup, snapshot, snapshot_fallback, cleanup, archive, adapter_mirror or adapter_check |
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

*Table.* A load day's flags typed in the planner (whether the day is complete). Replaces the day flags in planner_loads.

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

*Table.* Economy loads typed by hand, per flight and game date. Replaces the typed part of planner_loads.

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

*Table.* Each airline's markets with their default aircraft, cabin and fares. Replaces the planner's ref.markets.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `name` | text | e.g. Transatlantic – dense |
| `default_type_id` | bigint |  |
| `default_config_id` | bigint |  |
| `fare_y_pct` | numeric(5,1) | Economy fare, percent of the game's standard |
| `fare_j_pct` | numeric(5,1) | Business fare, percent of the game's standard |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

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
| `extra` | jsonb | For the adapter only: fields the table doesn't know. Expected empty |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## planner_data

*Table.* The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries. Written by planner_data_set(), which also writes countries, airports and routes. Read by the planner when it opens (until #18), the adapter and export_planner_data().

| Column | Type | Notes |
|---|---|---|
| `key` | text |  |
| `value` | jsonb |  |
| `updated_at` | timestamp with time zone |  |

**Access:** planner staff read data: select for authenticated.

## planner_loads

*Table.* The old planner's daily loads, one JSON document per month. Frozen since the switch-over (#13, pull request 9): every write is refused, the capture's loads step leaves it alone and save_loads() writes the tables, and it is kept unchanged as the fallback until #18. The planner reads planner_loads_get(). private.unfreeze_planner_state() undoes the switch-over.

| Column | Type | Notes |
|---|---|---|
| `month` | text | YYYY-MM |
| `json` | text |  |
| `saved_at` | bigint |  |
| `updated_at` | timestamp with time zone |  |

**Access:** planner users read loads: select for authenticated.

**Triggers:** planner_frozen, planner_loads_touch.

## planner_meta

*Table.* Settings kept as data. Holds growthRules, the thresholds for the growth signals as set on 5 Oct. Not read by the planner today: its rules are in its code.

| Column | Type | Notes |
|---|---|---|
| `key` | text |  |
| `value` | jsonb |  |
| `updated_at` | timestamp with time zone |  |

**Access:** planner staff read meta: select for authenticated.

## planner_scripts

*Table.* Copies of Claude's scripts from before the repository existed. The repository is now the source (decision #1). Written by save_script(). Read by export_repo_bootstrap().

| Column | Type | Notes |
|---|---|---|
| `name` | text |  |
| `content` | text |  |
| `updated_at` | timestamp with time zone |  |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## planner_state

*Table.* The old planner's whole state in one JSON row (id main). Frozen since the switch-over (#13, pull request 9): every write is refused ("frozen since <date>; write to the tables"), and it is kept unchanged as the fallback until #18. The planner reads planner_state_get() and saves through planner_state_put(); the tables are the truth. private.unfreeze_planner_state() undoes the switch-over.

| Column | Type | Notes |
|---|---|---|
| `id` | text |  |
| `json` | text | The planner's whole state as JSON text |
| `saved_at` | bigint | When it was last saved, in milliseconds since 1970 (UTC). Since the switch-over the planner uses planner_state_version() instead |
| `updated_at` | timestamp with time zone |  |

**Access:** planner users insert state: insert for authenticated; planner users read state: select for authenticated; planner users update state: update for authenticated.

**Triggers:** planner_frozen, planner_state_touch.

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
| `legacy_key` | text | The old planner's frequency id, e.g. z5qbaeg, kept for the adapter until #18 |
| `service_code` | text | On-board service, e.g. S3 |
| `fare_pct` | numeric(5,1) | Fare, percent of standard (100; Ryanair 85) |
| `launched_on` | date |  |
| `note` | text |  |
| `extra` | jsonb | For the adapter only: fields the table doesn't know. Expected empty |
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

*Table.* Our own planning choices as data (decision #14): the manual's rule numbers, thresholds and display choices for a world, with per-airline overrides. The old planner keeps its own copies in its code until #18.

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

*Table.* Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser; since #13's pull request 8 site_admin() writes them to world_airports too, and site_public() reads them from there, so this copy is kept only for the adapter until the switch-over). Written by site_admin() and the planner's Photos screen. Read by site_public() and site_investor().

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
| `legacy_key` | text | The old planner's to-do id, kept for the adapter until #18 |
| `title` | text |  |
| `due_on` | date |  |
| `done` | boolean |  |
| `done_at` | timestamp with time zone |  |
| `note` | text |  |
| `extra` | jsonb | For the adapter only: fields the table doesn't know. Expected empty |
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

*Table.* One row per AirlineSim world we play in (decision #14). Gander is the only one; is_default marks the world the old planner shows. Every planner table carries its world_id.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `name` | text |  |
| `game_host` | text | The world's address, e.g. gander.airlinesim.aero |
| `kind` | text | exclusive, long_term or short_term |
| `started_on` | date |  |
| `ended_on` | date |  |
| `is_default` | boolean | The world the old planner shows; at most one |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## Functions

*Runs as owner* means the function can do what its caller couldn't do directly, so it checks permission itself.

| Function | Returns | Who can call it | What it does |
|---|---|---|---|
| `adapter_clean_days(p_world_id bigint, p_as_of timestamp with time zone)` | integer | authenticated | How many clean days in a row the side by side had (design §11, choice 1), counted back from the capture day p_as_of falls in (default now; that day counts once it has a run, and a day still under way with none doesn't break the run). A day with no comparison, or with any failed mirror or comparison, ends the run. The side by side ended at the switch-over (#13, pull request 9), so from then on it counts 0 unless a rollback puts it back. Staff and postgres only. |
| `apply_loads_from_capture(p_airline text)` | jsonb | internal only · runs as owner | Retired by #13 (pull request 3): the loads step is private.apply_loads_from_capture(), which this now calls for the default world's airline of that name. No longer callable by signed-in accounts once 20261009230100_capture_data_removals.sql has run; kept until #18. |
| `as_num(p text)` | numeric | anon, authenticated | Turns game text such as 1,234.5 AS$ into a number (null when there is none). |
| `auto_confirm_planner_user()` | trigger | internal only · runs as owner | Trigger on sign-up: confirms the email straight away when it is on planner_users. |
| `capture_airlines(p_key text)` | jsonb | anon, authenticated · runs as owner | For the capture userscript, with the capture key: the key's world and its active airlines of our groups (game ID, name, code), in display order, so the userscript doesn't keep its own list. |
| `capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)` | jsonb | anon, authenticated · runs as owner | Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game's ID or, from older userscripts, by name, and refuses one outside the key's world; keeps the raw page (the 10:20 UTC clean-up deletes it after 14 days) and parses it (private.capture_store, private.capture_page): bank statement into game_flights and game_payments, loads into game_flights. Answers with the capture day and whether it is complete; the page that completes the world's capture for the day also takes the daily snapshot (airline_days, route_days) and answers with it. |
| `export_capture(p_secret text, p_days integer)` | jsonb | anon, authenticated · runs as owner | Exports recent capture data for Claude's scripts, exactly as before #13: profit per flight, loads, payments ahead, cash, the last 24 hours and capture runs, from the compatibility views. Needs the ingest secret. |
| `export_for_report(p_secret text, p_kind text, p_arg text)` | jsonb | anon, authenticated · runs as owner | Exports for the weekly report, gander monthly and the planning library: the world scans (snapshots), a scan's airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planner ({state, loads}: today's planner_state and planner_loads documents, built from the tables by planner_state_get() and planner_loads_get()); and the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19). Needs the ingest secret. |
| `export_planner_data(p_secret text)` | jsonb | anon, authenticated · runs as owner | Exports planner_data for scripts. Needs the ingest secret. |
| `export_repo_bootstrap(p_secret text)` | jsonb | anon, authenticated · runs as owner | Exported the stored scripts when the repository was created (decision #1). Needs the ingest secret. |
| `ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Receives the world scanner's results (start, airlines, airports, finish) into game_scans, game_scan_airlines, game_scan_schedules and game_scan_airports; finish builds the scan's airport summaries. Kind markets takes the weekly report's market summaries for a scan (scan_airline_markets). Every airline a scan sees gets an airlines row (change log actor script). Same kinds, payloads and answers as before #13. Needs the ingest secret. |
| `is_planner_user()` | boolean | authenticated · runs as owner | True when the signed-in email is on planner_users. Used by the access rules, the planner and the Photos functions. |
| `loads_day_captured(p_world_id bigint, p_day date)` | boolean | authenticated | A loads day's done, one rule (design §8): true when every active airline of our groups in the world was captured for that date (its loads page of that capture day is in, or a flight of that date has loads captured in that capture day or later). planner_loads_get() and the capture's loads step both use it, so part-way through an evening's capture a day isn't done until the last airline is in. Staff and postgres only. |
| `parse_capture(p_id bigint)` | jsonb | internal only · runs as owner | Retired by #13 (pull request 3): the parsing is private.capture_page(), which this now calls. No longer callable by signed-in accounts once 20261009230100_capture_data_removals.sql has run; kept until #18. |
| `planner_data_set(p_secret text, p_key text, p_value jsonb)` | jsonb | anon, authenticated · runs as owner | Replaces one planner_data entry (the old planner reads its route research there until #18). For the research (key DATA) it also writes countries, airports and routes, only the rows that change (private.research_apply(); change log actor script unless the caller named itself), and answers what changed under tables. Needs the ingest secret. |
| `planner_item_delete(p_section text, p_key text)` | jsonb | authenticated · runs as owner | Removes one item of the planner's document through the same code as a save (design §8). As planner_item_put(). Staff and postgres only; runs as owner and checks the caller itself. |
| `planner_item_put(p_section text, p_key text, p_value jsonb)` | jsonb | authenticated · runs as owner | Sets one item of the planner's document, in today's JSON shape, through the same code as a save (design §8): for other chats' data-only changes (a plan card, a to-do, a frequency ...). Section and key as private.planner_doc_with_item() describes; plan-card and frequency times are local, stored in UTC. The change log names whoever the caller set (equinox.actor), or planner for a signed-in user. Answers {saved_at, applied, skipped, reload}. Staff and postgres only; runs as owner and checks the caller itself. |
| `planner_loads_get(p_world_id bigint)` | TABLE(month text, "json" text, saved_at bigint) | authenticated | The planner's loads documents, built from game_flights, load_entries and load_days (design §8): one row per month, as planner_loads had them. Per flight, the latest write wins, captured or typed; a day is done when typed, or once every active airline was captured for that date (loads_day_captured). The planner reads it since the switch-over (#13, pull request 9). Staff only. |
| `planner_save(p_changes jsonb, p_client text)` | jsonb | authenticated · runs as owner | The new planner's one way to write (decision #18, design §6): one call per action, with every row it changes, as a list of {table, op (insert, update or delete), key (the primary key, e.g. {"id": 812}), base (the row's updated_at as loaded; needed for an update or delete), values (the columns to set)}. All or nothing: if any row to update or delete was changed or removed since it was loaded, nothing is written and the answer is {ok: false, clashes: [{table, key, current (the row now, or null if it's gone)}]}; otherwise {ok: true, rows: [{table, op, key, updated_at}]}, inserts included. Only the 32 planner tables the change log covers, and only their own columns; their checks still apply. Written as actor planner with p_client (the tab's ID) as the detail. Staff only; runs as owner and checks the caller itself. |
| `planner_state_get(p_world_id bigint)` | jsonb | authenticated | The planner's document built from the tables (design §8): {json: the document as text, saved_at: planner_state_version()}. Every list in the old planner's order; cash and next-7-day costs from the capture unless typed; anything the tables have no column for from the row's extra. The planner reads it since the switch-over (#13, pull request 9). Staff only. |
| `planner_state_put(p_json text, p_saved_at bigint, p_base bigint, p_client text)` | jsonb | authenticated · runs as owner | Saves the planner's document into the tables (design §8), writing only the rows that changed; the planner saves through it since the switch-over (#13, pull request 9). Takes a lock per world; skips any item someone else (another actor, or another tab than p_client) changed after p_base, or after p_saved_at when there is no base (§11, choice 4). A base covers its whole millisecond (it is a planner_state_version(), rounded down). Writes the rest as actor planner with the tab in actor_detail. Answers {saved_at (server time, planner_state_version()), applied, skipped, reload (true when anything was skipped), skipped_items}. Staff and postgres only; runs as owner and checks the caller itself. |
| `planner_state_version(p_world_id bigint)` | bigint | authenticated | The time of the latest logged change to a world's planner tables (or to airports and countries), in milliseconds rounded down, never earlier than the old planner_state row's last save: the planner's saved_at and the base it saves from (design §8). Staff only. Default: the default world. |
| `rules_input(p_world_id bigint)` | jsonb | authenticated · runs as owner | Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world's values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats); cabin_configs; every airport any route, leg or base uses (position, UTC offset with the world's correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name), each with its settings as they apply to it (its own overrides in place of the world's values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren't removed (distance and market with any override applied); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg. The new planner, the scripts (export_for_report('rules')) and Claude's command (node lib/rules/dist/cli.js) build the library's Rules object from it. Staff only; runs as owner and checks the caller itself. |
| `save_loads(p_month text, p_days jsonb)` | jsonb | authenticated · runs as owner | Saves the planner's loads typed by hand: merges only the days given (a whole day's flights with f, or single flights with set and del, plus done and savedAt) onto the days as they stand, so days captured since the page loaded aren't lost, and returns the merged month. Since the switch-over (#13, pull request 9) it writes load_entries and load_days only (actor planner, detail save_loads) and returns the month as planner_loads_get() gives it; while planner_loads is unfrozen (after a rollback) it writes planner_loads and the tables, as before. Planner staff only; runs as owner. |
| `save_script(p_secret text, p_name text, p_content text)` | jsonb | anon, authenticated · runs as owner | Stores a copy of a script in planner_scripts, from before the repository existed. Needs the ingest secret. |
| `site_admin(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Publishes website content: newsroom posts, reports and site content. Content mct (minimum connection times, {airport code: minutes}) also sets world_airports, which site_public() reads (private.world_mct_set(); change log actor script unless the caller named itself); site_content.mct is kept too, for the adapter until the switch-over. Needs the ingest secret. |
| `site_investor(p_password text)` | jsonb | anon, authenticated · runs as owner | The investor page's data, when the password matches report_access: cash and next-7-day costs as planner_state_get() gives them (the capture's figure unless typed by hand), money spent from spending_log, markets from site_content, and the investor reports list. Runs as owner. |
| `site_newsletter(p_id bigint)` | jsonb | anon, authenticated · runs as owner | A published gander monthly issue, with its PDF. |
| `site_public()` | jsonb | anon, authenticated · runs as owner | Everything the public website shows, in one call: hubs and focus cities an airline flies from, aircraft flying, the week's frequencies (local times), signed interlines, posts, the reports list, site_content (photos, logos) and the minimum connection times (content.mct), built from the tables (#13, pull request 8), plus our airlines (names, codes, colours, the website's text, display order) from airlines. Same answer as before #13, apart from airlines and updated_at (when the planner's data last changed). No bank or transfer times, cabin layouts or aircraft on order (6 Oct). Anyone may call it; runs as owner. |
| `site_remove_airline_logo(p_airline text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: goes back to the in-game logo for an airline. Staff only. |
| `site_remove_airport_photo(p_code text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: removes a destination photo. Staff only. |
| `site_report(p_id bigint, p_password text)` | jsonb | anon, authenticated · runs as owner | One investor report with its PDF, when the password matches report_access. |
| `site_set_airline_logo(p_airline text, p_url text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets an airline's logo after the upload, for one of our airlines in airlines (by the planner's name for it). Staff only. |
| `site_set_airport_photo(p_code text, p_url text, p_credit text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets a destination photo and its credit after the upload. Staff only. |
| `touch_updated_at()` | trigger | anon, authenticated | Trigger: sets updated_at on every update to planner_state and planner_loads. |

## Internal functions

In the `private` schema, which the data API doesn't expose (#13): trigger functions and helpers that only the database itself and postgres use.

| Function | Returns | Who can call it | What it does |
|---|---|---|---|
| `private.adapter_mirror_loads()` | trigger | internal only · runs as owner | The side by side (design §9) on planner_loads: copies each write of a month into load_entries and load_days when the transaction commits, and compares planner_loads_get()'s month with it; one job_runs row each. Not attached since the switch-over (#13, pull request 9): private.unfreeze_planner_state() attaches it again. |
| `private.adapter_mirror_state()` | trigger | internal only · runs as owner | The side by side (design §9) on planner_state: copies each save of the old row into the tables (mirror mode, actor planner, detail mirror) when the transaction commits, and compares planner_state_get() with it (private.planner_state_check); one job_runs row each, never stopping the save. Not attached since the switch-over (#13, pull request 9): private.unfreeze_planner_state() attaches it again. |
| `private.adapter_seen(p_key text)` | boolean | internal only | Whether this version of an old row was already copied and compared in this transaction, and marks it so: the side-by-side triggers run at commit once per write, and the first does the work. |
| `private.airport_offset_min(p_world_id bigint, p_code text)` | integer | internal only | An airport's UTC offset in a world, in minutes: coalesce(world_airports.utc_offset_override, airports.utc_offset). Null while it isn't known (the airports are loaded by #13's pull request 4). |
| `private.apply_loads_from_capture(p_airline_id bigint)` | jsonb | internal only | The capture's loads step. Since the switch-over (#13, pull request 9), while planner_loads is frozen, it does nothing: the loads are in game_flights, where planner_loads_get() reads them. Unfrozen (after a rollback) it copies the last 3 days of an airline's captured loads into planner_loads as before, a day done once every active airline was captured for that date (loads_day_captured, the getter's rule) and staying done. |
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
| `private.caller_is_staff()` | boolean | internal only | True for planner staff (their sign-in) and for postgres itself (Claude, jobs, migrations), the way the getters decide. Used by the write functions that run as owner. |
| `private.capex_key(p_airline text, p_day date, p_kind text, p_amount numeric, p_note text)` | text | internal only | What a money-spent entry says (airline, date, kind, amount in AS$, note) as one text, the same from the planner's document and from a spending_log row: the entries have no id, so identical ones are interchangeable (design §8). |
| `private.capture_day(p_world_id bigint, p_at timestamp with time zone)` | date | internal only | The capture day a moment belongs to (design §2): the UTC date of the moment minus capture_day_starts_utc (10:00 until set), so one evening's capture is one day, named after the evening. |
| `private.capture_day_complete(p_world_id bigint, p_day date)` | boolean | internal only | Completeness by world (design §7): true when every active airline of our groups in that world has all five pages (statement, events, income statement, balance sheet, loads) in that capture day. Not a count to 6, so a 7th airline must be captured too. |
| `private.capture_day_start(p_world_id bigint, p_day date)` | timestamp with time zone | internal only | When a world's capture day starts, in UTC: the day plus the setting capture_day_starts_utc (10:00 until it is set), design §2. |
| `private.capture_find_airline(p_world_id bigint, p_airline text)` | bigint | internal only | The airline a capture page is for, among the airlines of our groups in the key's world: by the game's ID (the userscript from version 1.3), or by name as the older userscript and the bookmark send it (the names matched since 7 Oct). Null when none or more than one fits, so the page is refused. |
| `private.capture_key_world(p_key text)` | bigint | internal only | The world a capture key belongs to (capture_keys.world_id), or null for a key that doesn't match. |
| `private.capture_page(p_raw_id bigint)` | jsonb | internal only | Parses one stored capture page into the capture tables, using the page's own capture time throughout: statement lines into game_statement, folded into game_flights and game_payments; events into game_events (with due_at where known); loads into game_flights; the income statement and balance sheet into game_pnl and game_balance (with capture_day), each row's figures and capture time from the same capture, the latest (#13 pull request 6). Then money and loads are matched. |
| `private.capture_refresh(p_world_id bigint)` | jsonb | internal only | For every airline of our groups in a world: fills flight times and events' due_at that have become known, then matches money to loads. Run once after the airports are loaded (#13, pull request 4); the capture does the same for one airline after each page. |
| `private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean)` | jsonb | internal only | Stores one page for an airline of the given world and parses it, at the given capture time, and says whether that capture day is now complete. When the page completes the world's capture for the day (private.snapshot_due), takes the daily snapshot (private.take_snapshot, one job_runs row, ok or failed; a failure never loses the page) and answers with it under snapshot. Refuses a page for an airline outside the world. capture_ingest() calls it with now(); the tests replay saved pages with their own times. |
| `private.check_leg_route()` | trigger | internal only | Trigger on flight_legs: refuses a leg whose airports don't match its rotation's route in its direction (leg 1 from the hub to the destination, leg 2 back). |
| `private.check_route_legs()` | trigger | internal only | Trigger on routes and rotations: refuses changing a route's airports, or a rotation's route, when its flight legs would no longer match. |
| `private.clock_min(p text)` | integer | internal only | A local clock time as the old planner reads it ("07:30" or "7:30", up to 23:59), as minutes after midnight; null for anything else. |
| `private.fill_due_at(p_airline_id bigint)` | integer | internal only | Fills an airline's game_events.due_at once its home airport's offset is known. |
| `private.fill_flight_links(p_world_id bigint)` | jsonb | internal only | The route and aircraft of a world's captured flights that don't have them yet: the route by the schedule's leg with that number and direction, else the airline's route that way or the other way; the aircraft by the registration the loads page or the statement names. |
| `private.fill_flight_times(p_airline_id bigint)` | integer | internal only | Fills an airline's loads rows' dep_at and arr_at where the airports' offsets have become known since they were captured. |
| `private.fold_statement(p_airline_id bigint, p_minutes timestamp with time zone[])` | integer | internal only | Folds an airline's statement lines in the given minutes into game_flights (one row per flight block, matched by minute and block) and game_payments (every other line), and ties each flight line to its flight (game_statement.flight_id). Blocks that changed since are taken apart and folded again; a flight already matched keeps its loads. Run after every statement page, and by the backfill for every minute. |
| `private.freeze_planner_state()` | text | internal only | Freezes planner_state and planner_loads (the planner_frozen trigger on each, with the moment as its argument); freezing again keeps the first moment. Run by the switch-over's migration; after a rollback, running it again (with the removal file of 20261010230000) switches over again. Returns the moment. |
| `private.growth_key(p_airline text, p_day date, p_move text, p_note text)` | text | internal only | What a growth move says (airline, date, move, note) as one text, the same from the planner's document and from a growth_log row (design §8). |
| `private.history_cash(p_world_id bigint, p_day date, p_at timestamp with time zone)` | TABLE(airline_id bigint, cash numeric, fixed_next7 numeric, cash_at timestamp with time zone) | internal only | The daily history's cash for a capture day, per active airline of our groups (design §7): the day's latest balance of account 2800 up to the moment, with the payments due in the 7 days after it (as capture_cash); with no balance that day, cash_entries by the planner's date. |
| `private.history_fleet(p_world_id bigint, p_at timestamp with time zone)` | TABLE(airline_id bigint, aircraft_by_type jsonb, aircraft_total integer, on_order integer) | internal only | The daily history's fleet at a moment, per active airline of our groups (design §7, §9 step 4): aircraft flying (by type, and the total) from arrival in the game (delivery_at; one with no delivery record from the start) until retired, unless still marked on order; on order from the order date until then. With the moment now it agrees with aircraft.status. |
| `private.history_flows(p_world_id bigint, p_from date, p_to date)` | jsonb | internal only | The daily history's flows for a span of UTC days (design §7): route_days replaced for those days, and each airline_days row of those days given its flights, passengers, seats, loads, money and payments, from game_flights and game_payments. Returns how many rows of each it wrote. |
| `private.history_schedule(p_world_id bigint, p_day date)` | TABLE(airline_id bigint, weekly_departures integer, weekly_seats integer, destinations integer) | internal only | The daily history's schedule as it stood on a day, per airline: departures and seats a week and destinations, from the flight legs of every rotation launched by that day (one with no launch date from the start), assuming nothing was dropped. |
| `private.is_payment_line(p_descr text, p_blk integer)` | boolean | internal only | True for a statement line that never belongs to a flight: a lease, salaries, a deposit, a purchase, a refit or a cabin, or a line the parser put in block 0. |
| `private.is_weekday_set(p_days smallint[])` | boolean | authenticated | True for a set of ISO weekdays as the schedule stores them: 1 (Monday) to 7 (Sunday), sorted, no repeats, at least one. Used by the checks on flight_legs.days_utc and plan_card_legs.days_utc. |
| `private.job_cleanup(p_at timestamp with time zone)` | jsonb | internal only | The 10:20 UTC job (pg_cron equinox-cleanup; design §7): per world, deletes raw pages (game_capture_raw) older than 14 days, and, while settings.statement_cleanup_enabled is true, statement lines older than 14 days, only once every one is in game_flights or game_payments (counted first; otherwise none goes and the run fails, saying how many aren't). One job_runs row per world (cleanup), failed with the error rather than raised. p_at: the run's moment, default now (for the checks). |
| `private.job_run_add(p_job text, p_world_id bigint, p_started_at timestamp with time zone, p_status text, p_note text, p_details jsonb)` | bigint | internal only | Adds one finished job_runs row: the job, its world, when it started (and finished: now), ok or failed, the note and details; for_day is the capture day it started in. |
| `private.job_snapshot_fallback(p_at timestamp with time zone)` | jsonb | internal only | The 10:00 UTC job (pg_cron equinox-snapshot-fallback; design §7): for each world with active airlines of ours, takes the snapshot of the capture day just ended if it has none (private.take_snapshot, source fallback; cash with no balance that capture day and none typed from the latest balance before it), and of any earlier day since the history began that has none. A day with a snapshot is left alone. One job_runs row per world (snapshot_fallback), failed with the error rather than raised. p_at: the run's moment, default now (for the checks). |
| `private.json_date(p jsonb)` | date | internal only | A date written YYYY-MM-DD in the old planner's JSON; null for anything else or a day that doesn't exist. Used by the loader. |
| `private.json_int(p jsonb)` | bigint | internal only | A whole number from the old planner's JSON (a flight number, seats, minutes); null when it isn't one. Used by the loader. |
| `private.json_num(p jsonb)` | numeric | internal only | A number from the old planner's JSON: a JSON number, or text that is plainly a number; null for anything else. Used by the loader. |
| `private.json_object_or_empty(p text)` | jsonb | internal only | Stored JSON text read safely as an object; {} when it isn't one. Used by the loader for planner_state and planner_loads. |
| `private.json_ts(p jsonb)` | timestamp with time zone | internal only | A moment written the ISO way in the old planner's JSON (2026-09-29T17:53:16.155Z); null for anything else. Used by the loader. |
| `private.load_planner(p_world_id bigint)` | jsonb | internal only | Fills a world's planner tables from the old planner's storage (only the default world has any): planner_state, planner_loads, planner_data, site_content.mct, planner_meta.growthRules and the planner's code constants (design §9 step 3). Runs as migration with the change log off. Run again, it brings the tables in line with today's planner_state, keeping the ids that exist and touching nothing that didn't change. Returns the rows each step wrote and the keys kept in extra. |
| `private.load_planner_extra(p_world_id bigint, s jsonb)` | jsonb | internal only | Loader step, last: builds the document with planner_state_get() and keeps in extra, as the old document has it, any key of a tail, delivery, frequency, plan card, to-do or fare plan that the columns don't give back (beyond the differences design §9 allows). Returns how often each key was kept. Expected: none. |
| `private.load_planner_fleet(p_world_id bigint, s jsonb)` | jsonb | internal only | Loader step: one aircraft row per registration from the old planner's tails and deliveries (today's type, cabin and base from the tail; as ordered from the delivery; each list's order in extra), and the "keep this cabin" decisions. |
| `private.load_planner_loads(p_world_id bigint)` | jsonb | internal only | Loader step: every load in planner_loads the capture doesn't give back becomes a load_entries row (null where a captured flight was cleared), and a day's flags a load_days row where the planner saved the day, the capture didn't write it, or its done differs from the getter's (loads_day_captured, since the switch-over). Used after a rollback, and by the tests. |
| `private.load_planner_money(p_world_id bigint, s jsonb, p_saved_at timestamp with time zone)` | jsonb | internal only | Loader step: every cash and next-7-day figure the old planner holds that the capture doesn't give back exactly (capture_cash, rounded as the planner rounds) becomes a cash_entries row, in AS$. |
| `private.load_planner_network(p_world_id bigint, s jsonb, d jsonb)` | jsonb | internal only | Loader step: routes (research, added, edits, route cabins) and each frequency as a rotation and two flight legs in UTC (design §4): weekdays and times from the local ones, the return's day by the old planner's rule, block times from the typed times. |
| `private.load_planner_places(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)` | jsonb | internal only | Loader step: countries and airports from the route research (planner_data), every other airport the planner names by its code, and what the world says about them (connection times from ref.hubs and site_content.mct, night bans from ref.curfews, ref.utcOverrides) into world_airports. |
| `private.load_planner_reference(p_world_id bigint, s jsonb, p_growth jsonb)` | jsonb | internal only | Loader step: aircraft types, cabin layouts, markets, service profiles, hubs and focus cities, the types each airline may buy (BUY_TYPES), and the first settings and world rules (design §3.7), from planner_state.ref, planner_meta.growthRules, the manual and the planner's code constants. |
| `private.load_planner_tidy(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)` | jsonb | internal only | Loader step, on a second run: removes the rows the old planner no longer has, or retires an aircraft the capture's flights or payments still point at, and turns a route back into a research route once nothing adds or edits it. |
| `private.load_planner_work(p_world_id bigint, s jsonb)` | jsonb | internal only | Loader step: plan cards and their legs (in UTC), to-dos and their steps, growth moves, money spent, the fare plan, interline, monthly checks and dismissed alerts. |
| `private.loads_mirror_days(p_world_id bigint, p_days jsonb, p_at timestamp with time zone)` | jsonb | internal only | Makes the tables give back the given loads days as planner_loads has them (design §8): each flight whose load the getter shows differently becomes a load_entries row stamped p_at (null clears it), and a day whose done or savedAt differs a load_days row. Days not given are left alone. Used by save_loads() and the side by side. |
| `private.loads_times(p_world_id bigint, p_game_date date, p_dep_local text, p_arr_local text, p_origin text, p_dest text, OUT dep_at timestamp with time zone, OUT arr_at timestamp with time zone)` | record | internal only | A loads row's scheduled departure and arrival as moments, from the local times and the airports' offsets (design §3.8, §4): arrival is departure plus the block worked out from the local times. Null while an offset isn't known. |
| `private.local_to_utc(p_date date, p_time text, p_offset_min integer)` | timestamp with time zone | internal only | A local date and clock time ("07:30") at a fixed offset in minutes, as a moment. Null if any part is missing. |
| `private.log_change()` | trigger | internal only · runs as owner | Trigger on every planner table (decision #15): writes one change_log row per row added, changed or removed, naming the writer from equinox.actor and equinox.actor_detail, or planner for a signed-in user and unset otherwise. An update logs only the columns that changed, and nothing when nothing changed. Skipped when equinox.change_log is off, which only postgres can do. Runs as owner, so the log can be written while it stays read-only. |
| `private.match_flights(p_airline_id bigint)` | integer | internal only | Matches an airline's money-only and loads-only game_flights rows (design §3.8): per route, in time order so two flights on one route never swap, a block pairs with a loads row whose scheduled departure is 30 minutes after to 3 hours before the statement time, of the same aircraft where the statement names one; the most pairs win, then the smallest total gap. Unpaired rows wait for their partner. Needs the airports' offsets. |
| `private.merge_flight(p_money_id bigint, p_loads_id bigint)` | boolean | internal only | Joins one money-only game_flights row and one loads-only row into one flight: the loads columns move into the money row, and the loads row goes. |
| `private.payment_kind(p_descr text)` | text | internal only | The kind of a statement line that isn't tied to a flight (game_payments.kind): lease, salaries ("Payment of employee salaries", the week-end closing), deposit, purchase, refit (a configuration), cabin, or other. |
| `private.payment_registration(p_descr text)` | text | internal only | The aircraft a payment names, e.g. B-0161 from "Leasing rate for B-0161". Null when it names none. |
| `private.planner_apply(p_world_id bigint, p_doc jsonb, p_mode text, p_base timestamp with time zone, p_client text, p_actor text, p_detail text)` | jsonb | internal only | Saves a planner document into a world's tables, writing only the rows of the items that differ (design §8): a lock per world; the document and the tables as items; in mode save, items someone else changed after p_base are skipped (§11, choice 4); mode mirror (the side by side) and item (planner_item_put) skip nothing; the rest written as p_actor with p_detail (left as set when p_actor is null). Returns {applied, skipped, skipped_items, rows, doc}. |
| `private.planner_apply_extra(p_world_id bigint)` | jsonb | internal only | Save step, last: builds the document again and keeps in extra, as saved, any key of a written tail, delivery, frequency, plan card, to-do or fare plan that the columns don't give back (the loader's last step, for the items just written). Returns the document as the tables now give it. |
| `private.planner_apply_fleet(p_world_id bigint)` | jsonb | internal only | Save step: one aircraft row per changed registration from its tail and its delivery, with each list's place in extra kept in step with the document's order. |
| `private.planner_apply_flights(p_world_id bigint)` | jsonb | internal only | Save step: changed frequencies as a rotation and two legs in UTC, exactly as the loader works them out (design §4), and changed plan cards with their legs in UTC. |
| `private.planner_apply_money(p_world_id bigint)` | jsonb | internal only | Save step: cash and next-7-day figures (design §8): a cash_entries row holds a figure only where it differs from the capture's (rounded as the planner rounds), in AS$, and goes once both agree again. |
| `private.planner_apply_places(p_world_id bigint)` | jsonb | internal only | Save step: the airports and countries the changed items name, by their code only, so nothing that names them is refused (as the loader does). |
| `private.planner_apply_reference(p_world_id bigint)` | jsonb | internal only | Save step: ref's types, cabin layouts, services, markets, constants (as settings, depCap as the house rule), time mode, hubs and focus cities, and what the world says about their airports (connection times, night bans, offsets), for the changed items only, with the loader's rules. Types, layouts and services are found by their place in the list as well as by code: an entry with a blank code (several may share one) keeps the row at its place, and one renamed in place keeps its row. A layout's cabin is stored as typed. |
| `private.planner_apply_routes(p_world_id bigint)` | jsonb | internal only | Save step: the routes the changed routesAdded, routeEdits and routeCabin items, frequencies and fare plans name. Added routes take their figures from routesAdded; a research route keeps its own, and one no longer added takes the research's again (planner_data). An edit's market "" clears the market (market_cleared); an edit that changes nothing is kept (edit_kept). |
| `private.planner_apply_tidy(p_world_id bigint)` | jsonb | internal only | Save step, after the others: aircraft in neither list (retired where the capture or money spent still point at them, else removed or taken out of the lists), routes nothing names any more and the research doesn't have, and ref entries no longer listed, unless something still uses them. |
| `private.planner_apply_work(p_world_id bigint, p_keep_order boolean)` | jsonb | internal only | Save step: changed to-dos and their steps, fare plans, interline, monthly checks, dismissed alerts, kept cabins, money spent and growth moves. Entries without an id are added and removed by what they say; when the stored order no longer matches the document's, the rest of the list is written again in order (unless p_keep_order is false). |
| `private.planner_doc_with_item(p_doc jsonb, p_section text, p_key text, p_value jsonb)` | jsonb | internal only | A planner document with one item set, or removed (p_value null), in today's JSON shape. Sections: plans, routeEdits, routeCabin, interline, dismissed, cabinKeep by key; cash and fixed7 by date ({airline: millions}); monthly by airline ({task: date}); tails, deliveries, freqs, todos and farePlan by id; routesAdded by Airline|HUB|DEST; ref.hubs by Airline|CODE, ref.types by name, ref.configs and ref.services by code (set in place, or added at the end); ref.markets, ref.curfews, ref.utcOverrides, ref.gameLinks and ref.consts by key; ref.timeMode alone; capex and growthLog by place in the list (0 first; no key adds at the end). |
| `private.planner_duplicates(p_doc jsonb)` | text | internal only | The codes a planner document's ref lists hold twice (a type's name, a layout's or service's code, a hub's airline|code), blank ones aside: "duplicate code X in ref.configs", or null. The tables keep the first of each, so the side by side's comparison names them first. |
| `private.planner_extra(p_item jsonb, p_known text[], p_old_extra jsonb)` | jsonb | internal only | What an old list item keeps in its row's extra: the keys its table has no column for, plus the earlier load's stand-ins that still hold (a value the columns can't give back exactly, or null for a key the item doesn't have). |
| `private.planner_frozen()` | trigger | internal only | Trigger on planner_state and planner_loads since the switch-over (#13, design §8): refuses every insert, update, delete or truncate, whoever sends it, with "frozen since <date>; write to the tables" and a hint naming the adapter and private.unfreeze_planner_state(). |
| `private.planner_frozen_since(p_table regclass)` | text | internal only | Since when planner_state or planner_loads is frozen (its planner_frozen trigger's argument, e.g. "2026-10-11 03:12 UTC"), or null while it isn't. The capture's loads step and save_loads() ask it. |
| `private.planner_items(p_doc jsonb)` | TABLE(section text, key text, grp text, pos integer, item jsonb) | internal only | A planner document as items, the unit a save changes and a clash is decided on (design §8's table): tails, deliveries, frequencies, to-dos and fare plans by id; plan cards, route edits, route cabins, interline, dismissed alerts and kept cabins by key; routes added by airline|hub|destination; monthly checks by airline|task; cash and next-7-day figures by date|airline; each ref list entry (hubs by airline|code, types by name, configs and services by code; one with a blank code, which may repeat, by code@place) and each key of ref's maps; money spent and growth moves by what they say and which of the identical ones they are. With each item's place in its list. Of two entries with the same id or code (not blank), the first. |
| `private.planner_json_diff(p_old jsonb, p_new jsonb, p_path text, p_key text, p_in_list boolean)` | TABLE(path text, kind text) | internal only | private.planner_json_differences() with a shortcut: two equal values (numbers by value, keys in any order) are passed over without walking into them, so on a whole document it is many times faster. The only kind it can leave out is "numbers by value", which is allowed anyway: the differences that count are the same. |
| `private.planner_json_differences(p_old jsonb, p_new jsonb, p_path text, p_key text, p_in_list boolean)` | TABLE(path text, kind text) | internal only | Compares an old planner document with one built from the tables (design §9): one row per difference, with its path and kind. The allowed kinds: a missing key equals null, numbers by value, flight numbers as text, a tail with no status equals "Active", savedAt and version (key order never shows: jsonb keeps none). Anything else is "differs". Used by the loader and the rehearsal's tests. |
| `private.planner_place(p_path text)` | text | internal only | Where a difference is, without the parts that change from item to item: list places as [], the keys of keyed sections as {}, a loads day as {day} and its flights as {flight}. For job_runs notes. |
| `private.planner_ref_blank(p_section text, p_code text)` | boolean | internal only | Whether a type's name, or a cabin layout's or service's code, is blank: the planner's placeholder for a new row (New type, NEW, S5) or empty. Blank codes may repeat; such an entry is told apart by its place in the list. |
| `private.planner_state_check(p_world_id bigint, p_old jsonb, p_saved_at bigint, p_new jsonb)` | TABLE(path text, kind text, why text) | internal only | The side by side's comparison of a planner_state document with the one built from the tables. Strict since the switch-over (#13, pull request 9): only design §9's differences are allowed, and the cash allowances that served the side by side ended. A cash or next-7-day difference says why (dates and airlines only). One row per difference: path, kind ('differs' when not allowed), why. Used only if a rollback puts the side by side back. |
| `private.planner_touched(p_world_id bigint, p_since timestamp with time zone, p_client text)` | TABLE(section text, key text) | internal only | The items someone else changed after a moment (design §8): every change_log row of the world since, except those this tab made (actor planner, detail p_client), traced back to the planner items it belongs to, under its old and new names. With no client, every later change counts. |
| `private.research_apply(p_world_id bigint, p_doc jsonb)` | jsonb | internal only | planner_data_set()'s step for the route research (planner_data DATA: routes, coords, utc, countries): writes countries, airports and a world's research routes, only the rows that change, by the loader's rules. Added routes and the planner's overrides are never touched; a research route no longer listed goes unless something points at it or it carries an edit. A new UTC offset for an airport that flights or plan-card legs use (with no world correction) is held back and named, since their UTC times were worked out with the old one (design §4). A part missing from the document leaves its rows alone. Returns how many rows each part changed. |
| `private.restore_row(p_table text, p_row_key jsonb, p_as_of timestamp with time zone)` | jsonb | internal only | Puts one row of a logged table back as it was at a moment, by replaying change_log backwards: re-adds a removed row with its own key, undoes changes, or removes a row added since. The restore is logged like any change. For Claude, as postgres: start with the equinox.actor line (design §6). |
| `private.rules_input_doc(p_world_id bigint)` | jsonb | internal only | The planning library's input for a world (decision #19, design §7), with no check of its own: what rules_input() gives staff and export_for_report('rules') gives the scripts. See rules_input(). p_world_id: the world, or null for the default world. |
| `private.scan_airline(p_world_id bigint, p_game_id integer, p_name text)` | bigint | internal only | The airlines row of an airline a world scan saw, by game ID, added when new (design §3.9: rivals can then be placed in groups); a rival's game_name follows the game, ours are left alone. Null without a game ID. |
| `private.scan_summarise(p_scan_id bigint)` | integer | internal only | Builds a world scan's airport summaries (scan_airline_airports) from its schedules: per airline and airport, departures a week and destinations. Run when a scan finishes; a scan whose schedules were archived keeps what it has. Returns the rows written. |
| `private.schedule_jobs()` | jsonb | internal only | Schedules the two database jobs with pg_cron, by name, so it can run again safely: equinox-snapshot-fallback at 10:00 UTC (private.job_snapshot_fallback) and equinox-cleanup at 10:20 UTC (private.job_cleanup). Run by migration 20261011150000_jobs, and again after a full restore (the backup copies no schedules). Answers with the jobs as the scheduler has them. |
| `private.set_updated_at()` | trigger | internal only | Trigger on every planner table: sets updated_at when a row is added or really changes, and leaves it as it was when an update changes nothing. |
| `private.shift_weekdays(p smallint[], p_days integer)` | smallint[] | internal only | ISO weekdays moved by whole days (−1: each a day earlier, Monday becomes Sunday), sorted. Turns local weekdays into UTC ones and back (design §4). |
| `private.snapshot_due(p_world_id bigint, p_day date, p_at timestamp with time zone)` | boolean | internal only | Whether a page at p_at completes a world's capture for the day: every active airline of our groups has all five pages since the day started, or since the last snapshot taken from a complete capture that day. So one snapshot per complete capture, taken by its last page. |
| `private.statement_blocks(p_airline_id bigint, p_minutes timestamp with time zone[])` | TABLE(ts timestamp with time zone, blk integer, is_flight boolean, route text, routes_n integer, pax integer, tail text, pax_income numeric, cargo_income numeric, fuel numeric, onboard numeric, handling numeric, landing numeric, atc numeric, maintenance numeric, income_total numeric, cost_total numeric, captured_at timestamp with time zone) | internal only | An airline's statement lines in the given minutes, grouped by minute and block (blk) as game_flight_pnl has always grouped them, leaving out payments: money by type, the route, passengers, the maintenance line's aircraft, and whether the block is a flight (any flight line or route) or only payments. |
| `private.statement_category(p_descr text)` | text | internal only | The type of a bank-statement line (pax_income, cargo_income, fuel, onboard, handling, landing, atc, maintenance or other), as game_flight_pnl has always counted them. |
| `private.take_snapshot(p_world_id bigint, p_day date, p_at timestamp with time zone, p_source text, p_flows boolean)` | jsonb | internal only | The daily snapshot of a world's capture day (design §7): point-in-time figures (fleet, schedule, cash) as at p_at (default now) into airline_days for each active airline of our groups, with source (capture, fallback or backfill) and whether the day's capture was complete; then (p_flows) the flows of that UTC day and the two before. A later snapshot replaces the point-in-time figures, but a fallback or backfill never replaces one from a complete capture. Called by the capture when a day completes; pull request 7's 10:00 UTC fallback calls it too. |
| `private.unfreeze_planner_state()` | jsonb | internal only | The switch-over's rollback in one step (design §9): writes planner_state and planner_loads from the getters, so nothing saved since the switch is lost; lifts the freeze; gives signed-in staff back planner_state's insert and update; and puts the side by side back (the adapter_mirror triggers), so the old planner's saves keep the tables and the website current. It doesn't revert the planner's code: revert the switch-over's pull request too. Postgres only. Returns what it did. |
| `private.weekday_set(p text)` | smallint[] | internal only | The weekdays in an old frequency's days ("135"), as the old planner reads them: the digits 1 to 7, each once, sorted. Null when there are none. |
| `private.world_mct_set(p_world_id bigint, p_mct jsonb)` | jsonb | internal only | site_admin()'s step for content mct: a world's minimum connection times from the whole map {airport code: minutes}, into world_airports.mct_min; times of airports the map no longer lists are cleared, and a row nothing else describes goes. Refuses anything but airport codes with whole minutes, 0 to 1440. Returns how many were set, cleared and removed. |

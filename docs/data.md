# The database, table by table

Generated from the database's own descriptions by `database/describe.py`. Don't edit by hand: change the
description in a migration (`comment on table ...`), and the database rehearsal regenerates and checks this
file. How the parts fit together: `docs/architecture.md`.

55 tables, 4 views and 24 functions, all in Supabase's `public` schema, plus 6 internal functions in `private`. Website photos and logos are files in the `site-photos` storage bucket, not tables.

## Contents

- [`aircraft`](#aircraft) (table): Each aircraft from order to delivery to service to retirement, one row each
- [`aircraft_cabin_keeps`](#aircraft-cabin-keeps) (table): "Keep this cabin" decisions: the aircraft keeps its cabin although its routes call for this one, until they call for a different cabin
- [`aircraft_types`](#aircraft-types) (table): Aircraft types and their figures in a world: seats, cruise speed, turns, maintenance, price
- [`airline_aircraft_types`](#airline-aircraft-types) (table): The aircraft types each airline may buy
- [`airline_bases`](#airline-bases) (table): Each airline's hubs and focus cities, with bank times and flight-number blocks
- [`airlines`](#airlines) (table): Every airline we track in a world: our own, and from #13's capture work the rivals the world scan sees (their columns about our airlines stay null)
- [`airports`](#airports) (table): Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world's own corrections are in world_airports)
- [`backup_runs`](#backup-runs) (table): One row per run of the nightly backup (decision #6): when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied
- [`cabin_configs`](#cabin-configs) (table): Cabin layouts (e.g
- [`capture_keys`](#capture-keys) (table): Hashed keys that let the in-game capture send data
- [`cash_entries`](#cash-entries) (table): Cash and the next 7 days' fixed costs, in AS$, typed by hand or kept from before the capture: only figures the capture doesn't give
- [`change_log`](#change-log) (table): Every change to the planner's tables (decision #15): which row, added, changed or removed, the old and new values (for a change, only the columns that changed), when, and who
- [`countries`](#countries) (table): Country names by ISO code (-- for unknown)
- [`dismissals`](#dismissals) (table): Alerts dismissed on the planner's Home, by the old planner's key (e.g
- [`fare_plan`](#fare-plan) (table): Fare tests to make in the game, and whether each is still planned or was dropped
- [`flight_legs`](#flight-legs) (table): One row per flight in the schedule, in UTC (design §4): departure minute, UTC weekdays and block time
- [`flight_legs_local`](#flight-legs-local) (view): Each flight leg with its flight code (KF 1001) and its times as the game shows them: local departure and arrival and local weekdays, plus the arrival in UTC and its day offset
- [`flight_no_clashes`](#flight-no-clashes) (view): An airline's flight number used by two or more legs departing on the same weekday (local at the origin, as the planner's check counts it)
- [`game_balance`](#game-balance) (table): The balance-sheet page from the nightly capture: one row per airline, account and day
- [`game_capture_raw`](#game-capture-raw) (table): Every page the capture sent, as rows of cells before parsing
- [`game_events`](#game-events) (table): Payments the game lists ahead on the events page: leases, the week-end closing (salaries) and deliveries
- [`game_flight_pnl`](#game-flight-pnl) (view): Each captured flight's income and costs by type (fuel, handling, on-board services, landing, air traffic control, maintenance) and its profit, built from the bank statement
- [`game_loads`](#game-loads) (table): Every captured flight, with passengers, seats and fares by class and cargo
- [`game_ops_recent`](#game-ops-recent) (view): Each airline's last 24 hours of flying from the bank statement: flights, income, costs and block hours
- [`game_pnl`](#game-pnl) (table): The game's income statement per airline and day, for the current, last and total periods
- [`game_snapshot_airlines`](#game-snapshot-airlines) (table): World scan: every airline in Gander with its full schedule at the time of a scan
- [`game_snapshot_airports`](#game-snapshot-airports) (table): World scan: every airport's details, the airlines stationed there and its news at the time of a scan
- [`game_snapshots`](#game-snapshots) (table): One row per world scan: when it ran, the week, its status and a note
- [`game_statement`](#game-statement) (table): Bank-statement lines from the capture: every income and cost, most of them tied to one flight
- [`groups`](#groups) (table): A player's airlines in a world: ours (equinox.) and rival players' groups
- [`growth_log`](#growth-log) (table): Moves logged under the order rotation: big, freq or feeder
- [`ingest_secret`](#ingest-secret) (table): The shared secret that Claude's scripts send to the export, ingest, script and site-admin functions
- [`interline_agreements`](#interline-agreements) (table): Interline status per airline and country: to sign, signed, declined, or no partner there
- [`load_days`](#load-days) (table): A load day's flags typed in the planner (whether the day is complete)
- [`load_entries`](#load-entries) (table): Economy loads typed by hand, per flight and game date
- [`markets`](#markets) (table): Each airline's markets with their default aircraft, cabin and fares
- [`monthly_checks`](#monthly-checks) (table): When each monthly check was last done, per airline or for the group as a whole (airline_id null)
- [`plan_card_legs`](#plan-card-legs) (table): A plan card's flights, with the same time rules as flight_legs (UTC)
- [`plan_cards`](#plan-cards) (table): A plan for one aircraft's flying, on order or flying, kept after it is filed as the record of what was planned (whether it is filed is worked out, not stored)
- [`planner_data`](#planner-data) (table): The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries
- [`planner_loads`](#planner-loads) (table): Daily loads as the planner keeps them, one JSON document per month
- [`planner_meta`](#planner-meta) (table): Settings kept as data
- [`planner_scripts`](#planner-scripts) (table): Copies of Claude's scripts from before the repository existed
- [`planner_state`](#planner-state) (table): The whole planner in one JSON row (id main): plan cards, to-dos, aircraft, frequencies, deliveries, the fare plan, interline and reference data
- [`planner_users`](#planner-users) (table): Email addresses allowed into the planner (staff)
- [`report_access`](#report-access) (table): The password hash for the investor page and investor reports
- [`rotations`](#rotations) (table): An aircraft's out-and-back pair on a route: what the old planner calls a frequency
- [`routes`](#routes) (table): Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner's overrides (null = the research value; research refreshes never touch them)
- [`service_profiles`](#service-profiles) (table): On-board service by distance (S1, S2, …)
- [`settings`](#settings) (table): Our own planning choices as data (decision #14): the manual's rule numbers, thresholds and display choices for a world, with per-airline overrides
- [`site_content`](#site-content) (table): Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser)
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
| `extra` | jsonb | For the adapter only: any field the old planner adds that the table doesn't know, so nothing is dropped. Expected empty |
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
| `name` | text |  |
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

## airlines

*Table.* Every airline we track in a world: our own, and from #13's capture work the rivals the world scan sees (their columns about our airlines stay null). Game ID, codes, home airport, colours and the website's text, which today are copied in the planner (CODE_AL, CAP_HOME, AIRLINE_ORDER, LIVERY), the website (AL, ORDER) and the capture. The game link is worked out from worlds.game_host and game_id.

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

*Table.* Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world's own corrections are in world_airports). Replaces planner_data.coords and planner_data.utc. Holds only our six home airports' codes until the planner's data moves (#13).

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

*Table.* One row per run of the nightly backup (decision #6): when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied. The copies live in Cloudflare R2 (decision #16): each night's is kept 30 days, and the month's first is kept for good, also as a file on a monthly GitHub release in equinox-backups. Written by the backup job in equinox-backups. Read by the planner's Capture board and the backup line on Home.

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

**Access:** backup job writes backup_runs: insert for postgres; planner staff read backup_runs: select for authenticated.

## cabin_configs

*Table.* Cabin layouts (e.g. 321-LEI) with their seats and cost. Replaces the planner's ref.configs.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `code` | text | e.g. 321-LEI |
| `aircraft_type_id` | bigint |  |
| `cabin` | text | Standard, Leisure, Leisure Plus or Comfort |
| `seats` | integer |  |
| `business_seats` | integer |  |
| `economy_seats` | integer |  |
| `cost` | numeric(14,2) | AS$ |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

## capture_keys

*Table.* Hashed keys that let the in-game capture send data. Only hashes are stored. Written by hand when a key is issued. Read by capture_ingest().

Never leaves the database: left out of the nightly backup on purpose.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `label` | text |  |
| `key_hash` | text |  |
| `created_at` | timestamp with time zone |  |

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

*Table.* Country names by ISO code (-- for unknown). The same in every world. Replaces planner_data.countries.

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

*Table.* The balance-sheet page from the nightly capture: one row per airline, account and day. Account 2800 is cash. Written by parse_capture(). Read by the planner (Review: the group today, Cash next 14 days) and export_capture().

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `captured_on` | date |  |
| `account` | text | Account number and name as the game shows them; 2800 is cash |
| `amount` | numeric |  |
| `captured_at` | timestamp with time zone |  |

**Access:** planner staff read game_balance: select for authenticated.

## game_capture_raw

*Table.* Every page the capture sent, as rows of cells before parsing. Kept 14 days, while the parsed tables keep everything. Written by capture_ingest(). Read by parse_capture() and the planner's Capture board (when each airline was last captured).

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `airline` | text |  |
| `kind` | text | statement, events, loads, pnl, balance or html |
| `page_url` | text |  |
| `captured_at` | timestamp with time zone |  |
| `rows` | jsonb | The page's table rows, each a list of cell texts |

**Access:** planner staff read game_capture_raw: select for authenticated.

## game_events

*Table.* Payments the game lists ahead on the events page: leases, the week-end closing (salaries) and deliveries. Written by parse_capture(). Read by the planner's cash forecast (Review: Cash, next 14 days), which also takes each type's lease from here.

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

**Access:** planner staff read game_events: select for authenticated.

## game_flight_pnl

*View.* Each captured flight's income and costs by type (fuel, handling, on-board services, landing, air traffic control, maintenance) and its profit, built from the bank statement. Read by the planner (Review: route profit, aircraft) and export_capture().

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

## game_loads

*Table.* Every captured flight, with passengers, seats and fares by class and cargo. Written by parse_capture() from the loads page. Read by the planner (Check: daily load report, growth signals; Review: fare changes), apply_loads_from_capture() and export_capture().

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

*View.* Each airline's last 24 hours of flying from the bank statement: flights, income, costs and block hours. Read by the planner (Review: the group today; the cash forecast's flight profit) and export_capture().

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `last_ts` | timestamp with time zone |  |
| `flights` | bigint |  |
| `income` | numeric |  |
| `costs` | numeric |  |
| `hours` | numeric |  |

## game_pnl

*Table.* The game's income statement per airline and day, for the current, last and total periods. Written by parse_capture(). Not read by any screen yet; kept for reports.

| Column | Type | Notes |
|---|---|---|
| `airline` | text |  |
| `captured_on` | date |  |
| `line` | text |  |
| `current_p` | numeric |  |
| `last_p` | numeric |  |
| `total_p` | numeric |  |
| `captured_at` | timestamp with time zone |  |

**Access:** planner staff read game_pnl: select for authenticated.

## game_snapshot_airlines

*Table.* World scan: every airline in Gander with its full schedule at the time of a scan. Written by ingest_snapshot(), from scripts/scanner/gscan.py. Read by export_for_report() for the weekly report and gander monthly.

| Column | Type | Notes |
|---|---|---|
| `snapshot_id` | bigint |  |
| `enterprise_id` | integer |  |
| `name` | text |  |
| `flights` | jsonb |  |
| `n_flights` | integer |  |
| `n_weekly` | integer |  |
| `n_airports` | integer |  |

**Access:** planner staff read snapshot airlines: select for authenticated.

## game_snapshot_airports

*Table.* World scan: every airport's details, the airlines stationed there and its news at the time of a scan. Written by ingest_snapshot(). Read by export_for_report().

| Column | Type | Notes |
|---|---|---|
| `snapshot_id` | bigint |  |
| `code` | text |  |
| `airport_id` | integer |  |
| `info` | jsonb |  |
| `stations` | jsonb |  |
| `news` | jsonb |  |

**Access:** planner staff read snapshot airports: select for authenticated.

## game_snapshots

*Table.* One row per world scan: when it ran, the week, its status and a note. Written by ingest_snapshot(). Read by export_for_report().

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `taken_at` | timestamp with time zone |  |
| `week` | text |  |
| `note` | text |  |
| `status` | text |  |

**Access:** planner staff read snapshots: select for authenticated.

## game_statement

*Table.* Bank-statement lines from the capture: every income and cost, most of them tied to one flight. The source of route profit. Written by parse_capture(). Read by the views game_flight_pnl and game_ops_recent.

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

*Table.* Interline status per airline and country: to sign, signed, declined, or no partner there. Replaces the planner's interline.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `country_code` | text |  |
| `status` | text | to_sign, signed, declined or nopartner |
| `partner` | text | The partner as the game names it, e.g. Emirates (41) |
| `partner_airline_id` | bigint | The partner, once it is in airlines |
| `decided_on` | date |  |
| `note` | text |  |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** log_change, set_updated_at.

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

*Table.* The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries. Written by planner_data_set(). Read by the planner when it opens, and by export_planner_data().

| Column | Type | Notes |
|---|---|---|
| `key` | text |  |
| `value` | jsonb |  |
| `updated_at` | timestamp with time zone |  |

**Access:** planner staff read data: select for authenticated.

## planner_loads

*Table.* Daily loads as the planner keeps them, one JSON document per month. Written only by save_loads() (the planner) and apply_loads_from_capture() (after each loads capture), both of which merge days rather than replace the month. Read by the planner and export_for_report().

| Column | Type | Notes |
|---|---|---|
| `month` | text | YYYY-MM |
| `json` | text |  |
| `saved_at` | bigint |  |
| `updated_at` | timestamp with time zone |  |

**Access:** planner users read loads: select for authenticated.

**Triggers:** planner_loads_touch.

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

*Table.* The whole planner in one JSON row (id main): plan cards, to-dos, aircraft, frequencies, deliveries, the fare plan, interline and reference data. Written by the planner on every change, and by Claude for data-only changes. Read by the planner, site_public(), site_investor() and export_for_report(). To be split into proper tables at decision #13.

| Column | Type | Notes |
|---|---|---|
| `id` | text |  |
| `json` | text | The planner's whole state as JSON text |
| `saved_at` | bigint | When it was last saved, in milliseconds since 1970 (UTC); the planner uses it to avoid overwriting newer copies |
| `updated_at` | timestamp with time zone |  |

**Access:** planner users insert state: insert for authenticated; planner users read state: select for authenticated; planner users update state: update for authenticated.

**Triggers:** planner_state_touch.

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

## routes

*Table.* Every route an airline could fly, has added or has removed: the route research and the routes added in the planner, with the planner's overrides (null = the research value; research refreshes never touch them). Replaces planner_data.routes, routesAdded, routeEdits and routeCabin.

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
| `market_override_id` | bigint | Typed in the planner; null = the research value |
| `stars_override` | smallint | Typed in the planner; null = the research value |
| `cabin_choice` | text | The cabin chosen for the route (the planner's routeCabin) |
| `created_at` | timestamp with time zone |  |
| `updated_at` | timestamp with time zone |  |

**Access:** staff add: insert for authenticated; staff change: update for authenticated; staff read: select for authenticated; staff remove: delete for authenticated.

**Triggers:** check_route_legs, log_change, set_updated_at.

## service_profiles

*Table.* On-board service by distance (S1, S2, …). airline_id null means every airline without its own. Replaces the planner's ref.services.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint |  |
| `world_id` | bigint |  |
| `airline_id` | bigint |  |
| `code` | text | S1, S2, …; unique in a world |
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

*Table.* Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser). Written by site_admin() and the planner's Photos screen. Read by site_public() and site_investor().

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

*Table.* Money spent, in AS$: aircraft orders, cabins and refits, losses. Replaces the planner's capex.

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

*Table.* What a world says about an airport, only where there is something to say: minimum connection time, night ban, a corrected UTC offset, closure. An airport's offset in a world is coalesce(utc_offset_override, airports.utc_offset). Replaces site_content.mct, ref.hubs[].mct, ref.curfews and ref.utcOverrides.

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
| `apply_loads_from_capture(p_airline text)` | jsonb | authenticated · runs as owner | Copies the last 3 days of captured loads for one airline into planner_loads and moves the month's saved_at on, so browsers pick them up. Called by capture_ingest() after each loads page. |
| `as_num(p text)` | numeric | anon, authenticated | Turns game text such as 1,234.5 AS$ into a number (null when there is none). |
| `auto_confirm_planner_user()` | trigger | internal only · runs as owner | Trigger on sign-up: confirms the email straight away when it is on planner_users. |
| `capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)` | jsonb | anon, authenticated · runs as owner | Entry point for the in-game capture. Checks the capture key, stores the page (raw pages kept 14 days), parses it with parse_capture(), and after a loads page updates planner_loads. |
| `export_capture(p_secret text, p_days integer)` | jsonb | anon, authenticated · runs as owner | Exports recent capture data for Claude's scripts. Needs the ingest secret. |
| `export_for_report(p_secret text, p_kind text, p_arg text)` | jsonb | anon, authenticated · runs as owner | Exports world-scan snapshots, airlines, airports and the planner for the weekly report and gander monthly. Needs the ingest secret. |
| `export_planner_data(p_secret text)` | jsonb | anon, authenticated · runs as owner | Exports planner_data for scripts. Needs the ingest secret. |
| `export_repo_bootstrap(p_secret text)` | jsonb | anon, authenticated · runs as owner | Exported the stored scripts when the repository was created (decision #1). Needs the ingest secret. |
| `ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Receives the world scanner's results (start, airlines, airports, finish) into the game_snapshot tables. Needs the ingest secret. |
| `is_planner_user()` | boolean | authenticated · runs as owner | True when the signed-in email is on planner_users. Used by the access rules, the planner and the Photos functions. |
| `parse_capture(p_id bigint)` | jsonb | authenticated · runs as owner | Parses one raw capture page into game_statement, game_events, game_loads, game_pnl or game_balance, depending on its kind. |
| `planner_data_set(p_secret text, p_key text, p_value jsonb)` | jsonb | anon, authenticated · runs as owner | Replaces one planner_data entry. Needs the ingest secret. |
| `save_loads(p_month text, p_days jsonb)` | jsonb | authenticated · runs as owner | The planner's only way to save loads: merges the days it changed into one month of planner_loads (a day's whole entry, or single flights set and cleared), leaves every other day as it is, and returns the merged month. Planner staff only. |
| `save_script(p_secret text, p_name text, p_content text)` | jsonb | anon, authenticated · runs as owner | Stores a copy of a script in planner_scripts, from before the repository existed. Needs the ingest secret. |
| `site_admin(p_secret text, p_kind text, p_payload jsonb)` | jsonb | anon, authenticated · runs as owner | Publishes website content: newsroom posts, reports and site content. Needs the ingest secret. |
| `site_investor(p_password text)` | jsonb | anon, authenticated · runs as owner | The investor page's data, when the password matches report_access. |
| `site_newsletter(p_id bigint)` | jsonb | anon, authenticated · runs as owner | A published gander monthly issue, with its PDF. |
| `site_public()` | jsonb | anon, authenticated · runs as owner | Everything the public website shows (hubs, schedules, posts, the reports list, photos and logos), built from planner_state, site_content, site_posts and site_reports. |
| `site_remove_airline_logo(p_airline text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: goes back to the in-game logo for an airline. Staff only. |
| `site_remove_airport_photo(p_code text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: removes a destination photo. Staff only. |
| `site_report(p_id bigint, p_password text)` | jsonb | anon, authenticated · runs as owner | One investor report with its PDF, when the password matches report_access. |
| `site_set_airline_logo(p_airline text, p_url text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets an airline's logo after the upload. Staff only. |
| `site_set_airport_photo(p_code text, p_url text, p_credit text, p_path text)` | jsonb | authenticated · runs as owner | The planner's Photos screen: sets a destination photo and its credit after the upload. Staff only. |
| `touch_updated_at()` | trigger | anon, authenticated | Trigger: sets updated_at on every update to planner_state and planner_loads. |

## Internal functions

In the `private` schema, which the data API doesn't expose (#13): trigger functions and helpers that only the database itself and postgres use.

| Function | Returns | Who can call it | What it does |
|---|---|---|---|
| `private.check_leg_route()` | trigger | internal only | Trigger on flight_legs: refuses a leg whose airports don't match its rotation's route in its direction (leg 1 from the hub to the destination, leg 2 back). |
| `private.check_route_legs()` | trigger | internal only | Trigger on routes and rotations: refuses changing a route's airports, or a rotation's route, when its flight legs would no longer match. |
| `private.is_weekday_set(p_days smallint[])` | boolean | authenticated | True for a set of ISO weekdays as the schedule stores them: 1 (Monday) to 7 (Sunday), sorted, no repeats, at least one. Used by the checks on flight_legs.days_utc and plan_card_legs.days_utc. |
| `private.log_change()` | trigger | internal only · runs as owner | Trigger on every planner table (decision #15): writes one change_log row per row added, changed or removed, naming the writer from equinox.actor and equinox.actor_detail, or planner for a signed-in user and unset otherwise. An update logs only the columns that changed, and nothing when nothing changed. Skipped when equinox.change_log is off, which only postgres can do. Runs as owner, so the log can be written while it stays read-only. |
| `private.restore_row(p_table text, p_row_key jsonb, p_as_of timestamp with time zone)` | jsonb | internal only | Puts one row of a logged table back as it was at a moment, by replaying change_log backwards: re-adds a removed row with its own key, undoes changes, or removes a row added since. The restore is logged like any change. For Claude, as postgres: start with the equinox.actor line (design §6). |
| `private.set_updated_at()` | trigger | internal only | Trigger on every planner table: sets updated_at when a row is added or really changes, and leaves it as it was when an update changes nothing. |

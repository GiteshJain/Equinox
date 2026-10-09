# The database, table by table

Generated from the database's own descriptions by `database/describe.py`. Don't edit by hand: change the
description in a migration (`comment on table ...`), and the database rehearsal regenerates and checks this
file. How the parts fit together: `docs/architecture.md`.

22 tables, 2 views and 23 functions, all in Supabase's `public` schema. Website photos and logos are files in the `site-photos` storage bucket, not tables.

## Contents

- [`backup_runs`](#backup-runs) (table): One row per run of the nightly backup (decision #6): when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied
- [`capture_keys`](#capture-keys) (table): Hashed keys that let the in-game capture send data
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
- [`ingest_secret`](#ingest-secret) (table): The shared secret that Claude's scripts send to the export, ingest, script and site-admin functions
- [`planner_data`](#planner-data) (table): The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries
- [`planner_loads`](#planner-loads) (table): Daily loads as the planner keeps them, one JSON document per month
- [`planner_meta`](#planner-meta) (table): Settings kept as data
- [`planner_scripts`](#planner-scripts) (table): Copies of Claude's scripts from before the repository existed
- [`planner_state`](#planner-state) (table): The whole planner in one JSON row (id main): plan cards, to-dos, aircraft, frequencies, deliveries, the fare plan, interline and reference data
- [`planner_users`](#planner-users) (table): Email addresses allowed into the planner (staff)
- [`report_access`](#report-access) (table): The password hash for the investor page and investor reports
- [`site_content`](#site-content) (table): Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser)
- [`site_posts`](#site-posts) (table): Newsroom posts on the website
- [`site_reports`](#site-reports) (table): Investor reports and gander monthly issues, each with its status (upcoming or published) and its PDF
- [Functions](#functions)

## backup_runs

*Table.* One row per run of the nightly backup (decision #6): when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied. Written by the backup job in equinox-backups. Read by the planner's Capture board and the backup line on Home.

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

**Access:** backup job writes backup_runs: insert for postgres; planner staff read backup_runs: select for authenticated.

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

## ingest_secret

*Table.* The shared secret that Claude's scripts send to the export, ingest, script and site-admin functions. To be replaced by proper roles (decision #11).

Never leaves the database: left out of the nightly backup on purpose.

| Column | Type | Notes |
|---|---|---|
| `secret` | text |  |

**Access:** no policies, so only the database's own functions and the server can read or write it.

## planner_data

*Table.* The route research the planner is built on, in one row (key DATA): routes, airport coordinates, UTC offsets and countries. Written by planner_data_set(). Read by the planner when it opens, and by export_planner_data().

| Column | Type | Notes |
|---|---|---|
| `key` | text |  |
| `value` | jsonb |  |
| `updated_at` | timestamp with time zone |  |

**Access:** planner staff read data: select for authenticated.

## planner_loads

*Table.* Daily loads as the planner keeps them, one JSON document per month. Written by the planner and by apply_loads_from_capture() after each loads capture. Read by the planner and export_for_report().

| Column | Type | Notes |
|---|---|---|
| `month` | text | YYYY-MM |
| `json` | text |  |
| `saved_at` | bigint |  |
| `updated_at` | timestamp with time zone |  |

**Access:** planner users insert loads: insert for authenticated; planner users read loads: select for authenticated; planner users update loads: update for authenticated.

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

## Functions

*Runs as owner* means the function can do what its caller couldn't do directly, so it checks permission itself.

| Function | Returns | Who can call it | What it does |
|---|---|---|---|
| `apply_loads_from_capture(p_airline text)` | jsonb | authenticated · runs as owner | Copies the last 3 days of captured loads for one airline into planner_loads. Called by capture_ingest() after each loads page. |
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

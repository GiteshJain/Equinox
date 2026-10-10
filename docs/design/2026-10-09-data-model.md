# The planner's data in proper tables: design (decision #13)

*9 Oct 2026. Approved by Gitesh when merged; nothing is built before that (#13). The four choices in §11 were
Claude's call, at his request. Shaped by #14 (worlds and airlines), #15 (history),
#16 (data growth), #17 (testing saves) and the jobs brief (`docs/briefs/2026-10-09-jobs.md`).*

## 1. Summary for Gitesh
**The answer:** every aircraft, flight, route, plan card, to-do and setting becomes its own row, tagged with its world
and airline. Each flight is a row with UTC times. Every change is recorded. The planner you use today keeps working,
unchanged on screen, through an adapter.

**The main tables:**
- `worlds`, `groups`, `airlines`: Gander; equinox. and rival players' groups; every airline with its game ID.
- `airports`, `world_airports`: one airport list; connection times, night bans and time zones per world.
- `aircraft`: each aircraft from order to delivery to service (replaces tails and deliveries).
- `routes`, `rotations`, `flight_legs`: every route, and each flight as a row with UTC times, weekdays and block time.
- `plan_cards`, `todos`, `growth_log`, `spending_log`, `fare_plan`, `interline_agreements`: the work lists.
- `settings`, `world_rules`: the manual's rule numbers and Gander's house rules, as data.
- `game_flights`: one row per flown flight with its money and loads, in place of about 9 statement lines.
- `airline_days`, `route_days`, scan summaries: the daily history, kept for good.
- `change_log`, `job_runs`: who changed what, and whether each nightly job ran.

**What changes for you:**
- On screen, nothing until the planner rebuild (#18), except new warnings on Home when a nightly job fails.
- Saves write only what changed, so a tab that's out of date can't wipe newer edits.
- Every change is kept 12 months. The daily history starts at once, filled back to 29 Sep.

**What you approve:** this design. The four choices in §11 were my call, at your request: switch after 3 clean
nights; keep scan totals per airport and market; the tables hold the rule numbers, with a check against the old
planner's copies; and a save keeps the parts that don't clash.

**Build:** about ten pull requests, one at a time (§10): test copy → tables → capture data → data load → adapter (run
beside the old row first) → history → jobs → website and scripts → switch-over → report PDFs.

## 2. Principles
**Keys (#14).**
- Every row carries `world_id`, and `airline_id` where it has one, child rows included (a to-do's steps, a plan
  card's legs).
- A child points at its parent with a two-column foreign key, `(parent_id, world_id)` → parent `(id, world_id)`, so a
  row can never point into another world. Legs point at rotations the same way with `airline_id`.
- Nothing assumes six airlines, or even several. "All of a world's airlines" is always a query on `airlines`, and
  group screens, cross-airline connections and interlines work with one.
- **One reading of #14 to note:** `countries` and `airports` carry no world. Their codes, places and time zones are
  the game's, the same in every world. Anything a world can change about an airport (connection time, night ban,
  closure, a time-zone correction) is in `world_airports`, which does carry the world.

**Stable IDs.**
- Every table of things we create has `id bigint generated always as identity` as its primary key. The exceptions
  use their natural key: `countries` and `airports` (a fixed code), and link, per-day and per-pair tables
  (`world_airports`, `cash_entries`, `load_entries`, `airline_days`, …), keyed by the columns that make a row unique.
- Names, registrations and flight numbers are fields, never keys. Renaming an airline or re-registering an aircraft
  touches one row.
- Natural codes only where the game never changes them: IATA airport codes (`*_code` → `airports.code`) and ISO country
  codes.
- The old planner's own keys (a frequency's `id`, a to-do's `id`) are kept in `legacy_key` for the adapter, until #18.

**One copy of everything.**
- Tails and deliveries become one `aircraft` row each.
- Connection times live once, in `world_airports.mct_min` (today in `ref.hubs` and `site_content.mct`).
- Airports live once (today in `planner_data.coords`, `planner_data.utc` and `ref.curfews`).
- Cash, next-7-day costs and loads are read from the capture tables. Only values typed by hand are stored
  (`cash_entries`, `load_entries`).
- Plan cards stay after filing, as the record of what was planned. Whether a card is filed is worked out, not stored.

**Times.**
- A moment is `timestamptz`, in UTC.
- A weekly schedule is stored in UTC: the departure minute of the day (`dep_utc_min`, 0–1439), the UTC weekdays it
  departs (`days_utc`), and the block time in minutes. Arrival is departure plus block.
- Weekdays are ISO numbers, 1 = Monday to 7 = Sunday, as the planner uses today.
- Local times are worked out for display with the airport's fixed offset. The game runs standard time all year
  (manual §9), so the conversion never changes with the season.
- Settings that are local by nature stay in local clock time: bank times and night bans (`time` columns), because
  that's how the game and Gitesh define them.

**What "a day" means.** One rule for flights, one for captures:
- **A flight's day is the UTC date it departs** (`dep_at`). Route and airline summaries add flights up by that date.
  Each flown flight also keeps the game's own date (`game_date`, the local date at departure), because the game's loads
  page and the old planner use it.
- **A capture belongs to the evening it was taken.** Gitesh captures in the Chicago evening, roughly 22:00 to 05:00
  UTC, which crosses midnight UTC. A capture's day is the UTC date of (capture time − 10 hours): anything captured
  from 10:00 UTC on 7 Oct to 09:59 UTC on 8 Oct is "7 Oct's capture". The 10 hours is a setting
  (`capture_day_starts_utc` = `10:00`).
- **Why:** one evening's capture always lands on one day, named after the evening it was pressed, whichever side of
  UTC midnight each airline went in. 10:00 UTC (05:00 in Chicago) is the agreed snapshot fallback time, so a day ends
  exactly when the fallback runs. UTC dates keep flight totals simple across six time zones. The boundary is fixed in
  UTC, so Chicago's clock change in November doesn't move it.
- **Today's code differs:** `game_balance.captured_on` is the UTC date, so the evening of 7 Oct is stored as 8 Oct.
  The new `capture_day` column fixes that; the old column stays for the old planner.

**One row per flight leg.** A flight in the schedule is a `flight_legs` row; a flight flown is a `game_flights` row.
The planner, website, scripts and checks all read the same rows instead of rebuilding flights seven ways.

**Settings and world rules are data** (#14): the manual's rule numbers, the planner's constants and Gander's house
rules become rows (§3.7). The old planner keeps its own copies in its code until #18 (§11, choice 3).

**Money** is `numeric(14,2)` in AS$: never millions, never floating point. The adapter converts to the planner's
millions (`amountM`) and back. Percentages are `numeric(5,1)`.

**Naming.**
- snake_case everywhere. Tables are plural nouns (`airlines`, `flight_legs`); columns are singular.
- Foreign keys end `_id`; airport columns end `_code`; moments end `_at`; dates end `_on`; minutes end `_min`;
  percentages end `_pct`.
- Capture tables keep the `game_` prefix, website tables `site_`. "Snapshot" now means only the daily history; the
  world-scan tables are renamed `game_scan*` so the two can't be confused.

**Described** (#10): every table, column, view and function gets a `comment` in its migration. The rehearsal fails
without one.

**Small and safe:**
- #16 keeps every table small, so nothing is partitioned. Revisit if a table passes about 10 million rows.
- Every foreign-key column has an index. Composite indexes put the equality columns first and the date last.
- Writes are upserts (`insert … on conflict`); transactions stay short.

## 3. The tables
**Types follow the names unless a column says otherwise:** `id` is the identity key; `world` means
`world_id bigint not null` → `worlds`; `airline` means `airline_id bigint` → `airlines` (two-column key); `*_id` is
`bigint`; `*_code` is `text`; `*_on` is `date`; `*_at` is `timestamptz`; `*_min` is `smallint`; `*_pct` is
`numeric(5,1)`; `money` is `numeric(14,2)` AS$; counts are `int`; flags are `boolean not null default false`;
everything else is `text`. Enumerated text columns have a `check` listing their values. Every table also has
`created_at` and `updated_at` (set by trigger) unless it is a log.

### 3.1 Worlds, groups and airlines

| Table | Purpose | Columns | Keys and notes | Replaces |
|---|---|---|---|---|
| `worlds` | One row per game world | `id`, `name` (Gander), `game_host` (gander.airlinesim.aero), `kind` (exclusive, long_term, short_term), `started_on`, `ended_on`, `is_default` (the world the old planner shows), `note` | unique `name`; unique `game_host`; only one `is_default` | "Gander" in the code |
| `groups` | A player's airlines in a world: ours and rivals | `id`, `world`, `name` (equinox.), `kind` (ours, rival), `player_name`, `owner_user_id uuid` → `auth.users` (Gitesh), `note` | unique (`world_id`, `name`) | — |
| `airlines` | Every airline we track in a world: ours, and rivals seen by the world scan | below | unique (`world_id`, `game_id`); unique (`world_id`, `planner_name`) | `CODE_AL`, `CAP_HOME`, `AIRLINE_ORDER`, `LIVERY`, `ref.gameLinks` (planner); `AL`, `ORDER` (website); `AIRLINES` (capture) |
| `airline_bases` | Hubs and focus cities | `id`, `world`, `airline`, `airport_code`, `role` (hub, focus), `is_main`, `parent_base_id` (a focus city's hub), `bank_times time[]` (local; 4 slots, null = empty), `flight_no_from int` (number block, e.g. 1000), `last_flight_no int`, `hold_note`, `position` | unique (`airline_id`, `airport_code`); one `is_main` per airline | `ref.hubs` (26), `MAIN_HUB` |
| `airline_aircraft_types` | The types each airline may buy | `world`, `airline`, `aircraft_type_id` | primary key (`airline_id`, `aircraft_type_id`) | `BUY_TYPES` |

`airlines` columns: `id`, `world`, `group_id` (null for a rival not yet placed in a group), `game_id int` (the game's
enterprise ID, e.g. 114), `game_name` (as the game shows it), `planner_name` (the old planner's key, "Pan American"),
`public_name` ("Pan Am"), `iata_code` ("AW"), `country_code`, `home_airport_code` (where the game's events page shows
its times), `is_lcc`, `low_demand` (the holding type, for the house rules), `active`, `founded_on`, `position`
(display order), `livery_color`, and the website's text: `slug`, `region_text`, `role_text`, `blurb`, `photo_city`.
Our columns are null for rivals. The game link is worked out from `worlds.game_host` and `game_id`.

### 3.2 Airports

| Table | Purpose | Columns | Keys and notes | Replaces |
|---|---|---|---|---|
| `countries` | Country names | `code` (ISO-2, plus `--` for unknown), `name` | primary key `code` | `planner_data.countries` (178) |
| `airports` | Every airport in the route research | `code` (IATA), `city`, `country_code`, `lat numeric(8,5)`, `lon numeric(8,5)`, `utc_offset numeric(4,2)` (hours: 5.50, 5.75, −5.00) | primary key `code` | `planner_data.coords`, `planner_data.utc` (1,337) |
| `world_airports` | What a world says about an airport, only where there is something to say | `world`, `airport_code`, `game_airport_id int`, `mct_min` (minimum connection time), `night_ban_from time`, `night_ban_to time` (local), `utc_offset_override numeric(4,2)`, `closed` (e.g. PNH), `note` | primary key (`world_id`, `airport_code`) | `site_content.mct` (127), `ref.hubs[].mct`, `ref.curfews` (122), `ref.utcOverrides` |

An airport's offset in a world is `coalesce(world_airports.utc_offset_override, airports.utc_offset)`.

### 3.3 Fleet and orders

| Table | Purpose | Columns | Keys and notes | Replaces |
|---|---|---|---|---|
| `aircraft_types` | Types and their figures in a world | `id`, `world`, `name` ("A321 NEO LIGHT"), `family_no int`, `seats_max int`, `cruise_kmh int`, `min_turn_min`, `gap_target_h numeric(4,1)`, `maint_per_hour numeric(5,2)`, `maint_per_cycle numeric(5,2)`, `ground_keep_min` (the turn the game keeps at each end; today `greens`), `price money` | unique (`world_id`, `name`) | `ref.types` (5) |
| `cabin_configs` | Cabin layouts and their cost | `id`, `world`, `code` ("321-LEI"), `aircraft_type_id`, `cabin` (Standard, Leisure, Leisure Plus, Comfort), `seats`, `business_seats`, `economy_seats`, `cost money`, `note` | unique (`world_id`, `code`) | `ref.configs` (10) |
| `aircraft` | Each aircraft, from order to retirement | below | unique (`world_id`, `registration`); index (`airline_id`, `status`) | `tails` (87), `deliveries` (59) |
| `aircraft_cabin_keeps` | "Keep this cabin" decisions | `world`, `aircraft_id`, `cabin`, `decided_on` | primary key (`aircraft_id`, `cabin`) | `cabinKeep` |

| `aircraft` column | Type | Notes |
|---|---|---|
| `id`, `world`, `airline` | | |
| `registration` | text | "N001AW"; a field, not the key |
| `aircraft_type_id`, `cabin_config_id` | bigint | today's type and cabin |
| `base_code` | text | today's base |
| `status` | text | `on_order`, `delivered` (arrived, not yet filed into the planner), `active`, `retired`. `active` is what the old planner calls a tail |
| `ordered_on` | date | from the delivery record |
| `delivery_at` | timestamptz | arrival in the game (today's `deliveries[].utc`) |
| `order_base_code`, `order_config_id`, `order_note` | | as ordered. 22 aircraft were refitted after delivery, so the ordered cabin differs from today's |
| `checked_on`, `schedule_changed_on` | date | the one-week check, Gitesh's to mark (manual §1) |
| `maintenance_note` | text | today's `maint` |
| `retired_on` | date | |
| `extra` | jsonb | adapter only: any field the old planner adds that the table doesn't know, so nothing is dropped. Expected empty. `rotations`, `plan_cards`, `todos` and `fare_plan` have it too |

### 3.4 Network

| Table | Purpose | Columns | Keys and notes | Replaces |
|---|---|---|---|---|
| `markets` | Each airline's markets and defaults | `id`, `world`, `airline`, `name` ("Transatlantic – dense"), `default_type_id`, `default_config_id`, `fare_y_pct`, `fare_j_pct` | unique (`airline_id`, `name`) | `ref.markets` (43) |
| `service_profiles` | On-board service by distance | `id`, `world`, `airline` (null = every airline without its own), `code` (S1…), `up_to_km int`, `note` | unique (`world_id`, `code`) | `ref.services` (4) |
| `routes` | Every route an airline could fly, has added or has removed: research, added and removed in one table | below | unique (`airline_id`, `hub_code`, `dest_code`) | `planner_data.routes` (4,438), `routesAdded` (84), `routeEdits` (45), `routeCabin` (3) |
| `rotations` | An aircraft's out-and-back pair on a route: today's "frequency" | `id`, `world`, `airline`, `route_id`, `legacy_key` (e.g. `z5qbaeg`), `service_code`, `fare_pct` (100; Ryanair 85), `launched_on`, `note`, `extra` | unique (`world_id`, `legacy_key`) | `freqs` (235) |
| `flight_legs` | **One row per flight in the schedule** | below, and §4 | unique (`rotation_id`, `leg_no`) | `freqs` (470 legs) |

`routes` columns: `id`, `world`, `airline`, `hub_code`, `dest_code`, `city` (a label, e.g. "Shanghai (Pudong)"),
`country_label` (as the research gave it; it mixes names and codes, "India" and "CN"), `distance_km int`, `market_id`,
`stars smallint`, `source` (research, added), `removed`, `removed_note`, the overrides typed in the planner
(`city_override`, `distance_override_km`, `market_override_id`, `stars_override`; null = the research value), and
`cabin_choice` (today's `routeCabin`). Research refreshes never touch the overrides. Index: (`airline_id`,
`hub_code`) for the Routes screen.

| `flight_legs` column | Type | Notes |
|---|---|---|
| `id`, `world`, `airline` | | |
| `rotation_id` | bigint | two-column key with `airline_id` |
| `leg_no` | smallint | 1 = out from the hub, 2 = back |
| `flight_no` | int | 1001; displayed with the airline's code, "KF 1001" |
| `origin_code`, `dest_code` | text | must match the route, in the leg's direction (checked by trigger) |
| `aircraft_id` | bigint | null only while being typed |
| `days_utc` | smallint[] | UTC weekdays it departs: sorted, no repeats, values 1–7, at least one |
| `dep_utc_min` | smallint | 0–1439; null only while being typed |
| `block_min` | smallint | from the game's times; null = arrival not typed (the planner estimates it) |

Indexes: `aircraft_id`; (`world_id`, `origin_code`); (`world_id`, `dest_code`); (`airline_id`, `flight_no`).

**Flight numbers are not unique per airline.** Kingfisher flies 1001/1002 on VT-AAA (Mon, Wed, Fri) and on VT-AAB
(Tue, Thu, Sat). Uniqueness is per number and weekday, which a plain constraint can't express. The view
`flight_no_clashes` lists real clashes, and the planner's "flight numbers used twice" check stays.

### 3.5 Plans

| Table | Purpose | Columns | Keys and notes | Replaces |
|---|---|---|---|---|
| `plan_cards` | A plan for one aircraft's flying | `id`, `world`, `airline`, `aircraft_id` (on order or flying), `base_code`, `title` ("HYD + CKG"), `note`, `extra` | unique (`aircraft_id`) | `plans` (41) |
| `plan_card_legs` | The card's flights | `id`, `world`, `plan_card_id`, `position`, `flight_no`, `origin_code`, `dest_code`, `days_utc` (default every day), `dep_utc_min`, `block_min`, `service_code` | unique (`plan_card_id`, `position`) | `plans[].legs` (214) |

Plan-card legs follow the flight-leg time rules. In the sample, all 214 legs' block times agree with their local
times, so storing departure and block loses nothing.

### 3.6 Work

| Table | Purpose | Columns | Keys and notes | Replaces |
|---|---|---|---|---|
| `todos` | The To-do board | `id`, `world`, `airline` (optional), `legacy_key`, `title`, `due_on`, `done`, `done_at`, `note`, `extra`; `created_at` is the item's own creation time | unique (`world_id`, `legacy_key`); index (`world_id`, `done`, `due_on`) | `todos` (31) |
| `todo_items` | A to-do's steps | `id`, `world`, `todo_id`, `position`, `body` | unique (`todo_id`, `position`) | `todos[].items` |
| `growth_log` | Moves logged under the order rotation | `id`, `world`, `airline`, `logged_on`, `move` (big, freq, feeder), `note` | | `growthLog` (25) |
| `spending_log` | Money spent: orders, cabins, refits | `id`, `world`, `airline`, `spent_on`, `amount money`, `kind` (order, cabin, loss), `aircraft_id` (optional), `note` | today's 7 entries without a kind are all orders | `capex` (101) |
| `fare_plan` | Fare tests to make in the game | `id`, `world`, `airline`, `route_id`, `legacy_key`, `cabin_class` (economy, business, first), `change_pct`, `fare_from money`, `proposed_on`, `status` (planned, dropped, …), `reason`, `extra` | unique (`world_id`, `legacy_key`) | `farePlan` (empty today) |
| `interline_agreements` | Interline status per airline and country | `id`, `world`, `airline`, `country_code`, `status` (to_sign, signed, declined, nopartner), `partner` ("Emirates (41)"), `partner_airline_id` (optional), `decided_on`, `note` | unique (`airline_id`, `country_code`) | `interline` (6) |
| `monthly_checks` | When each monthly check was last done | `id`, `world`, `airline` (null = the group as a whole), `task`, `last_done_on` | unique (`world_id`, `airline_id`, `task`) nulls not distinct | `monthly` |
| `dismissals` | Home's dismissed alerts | `world`, `alert_key` (the old planner's key, e.g. `maint\|B-0162`), `dismissed_on` | primary key (`world_id`, `alert_key`) | `dismissed` |
| `cash_entries` | Cash and next-7-day costs typed by hand, or kept from before the capture | `world`, `airline`, `day` (the planner's date key), `cash money`, `fixed_next7 money`, `entered_at` | primary key (`airline_id`, `day`) | the hand-typed part of `cash`, `fixed7` |
| `load_entries` | Loads typed by hand, per flight | `world`, `airline`, `game_date`, `flight_no`, `eco_pct` (null = cleared), `entered_at` | primary key (`airline_id`, `game_date`, `flight_no`) | the typed part of `planner_loads` |
| `load_days` | A day's flags typed in the planner | `world`, `game_date`, `done`, `saved_at_ms bigint`, `entered_at` | primary key (`world_id`, `game_date`) | day flags in `planner_loads` |

### 3.7 Settings and world rules

| Table | Purpose | Columns | Keys |
|---|---|---|---|
| `settings` | Our own planning choices: rule numbers, thresholds, display choices | `id`, `world`, `airline` (null = whole world; set = that airline's override), `key`, `value jsonb`, `unit`, `description`, `since`, `reason` | unique (`world_id`, `airline_id`, `key`) nulls not distinct |
| `world_rules` | The world's own rules: house rules, game settings, and whether #12's items are allowed | `id`, `world`, `key`, `value jsonb`, `kind` (house, game, permission), `unit`, `description`, `since`, `source` | unique (`world_id`, `key`) |

First rows for Gander. At the switch-over the manual's figures point here (checklist: one source for rule numbers):

| Manual | Key → value | Table |
|---|---|---|
| §3 cash forecast | `order_cushion` → 500000; `lease_estimate_pct` → 10 (only for a type never leased) | settings |
| §3 hubs first | `hub_first_departures` → 750; `contested_rival_weekly` → 250; `contested_rival_daily` → 2; Ryanair `hub_first_exempt` → true | settings, airline override |
| §4 connections | `connection_buffer_min` → 0; `connection_max_wait_h` → 8; `bank_arrival_window_min` → 60; `bank_departure_window_min` → 60; `bank_buffer_min` → 0 | settings |
| §4 scheduling | `second_daily_gap_h` → 3; `turn_margin_min` → 10 (10–15; 5 tolerated); `maintenance_min_pct` → 100; `maintenance_target_pct` → 105; `maint_min_ground_min` → 120; `block_allowance_min` → 25 (speeds in `aircraft_types.cruise_kmh`); `legal_gap_h` → 2 | settings |
| §5 fares | `fare_launch_pct` → 100; Ryanair → 85 (per-market prices in `markets`) | settings, airline override |
| Check → Growth | the growth-signal thresholds in the code and in `planner_meta.growthRules` | settings |
| Loads, days, display | `load_leeway_days` → 7; `load_window_days` → 14; `capture_day_starts_utc` → "10:00"; `planner_time_mode` → "local" | settings |
| §9 house rules | `holdings_max` → 8; `low_demand_holdings` → 2; `holdings_per_country` → {US: 1, CN: 1, EU: 2}; `lcc_holdings_max` → 1; `starting_capital` → 45000000; `departures_per_airport_week` → {value: 5000, then: 8000, after: "3 months"}; `same_route_gap_min` → 5; `fare_floor_pct` → 60; `freedom_routes_max` → 30; `alliance_max` → 30; `new_brand_route_days` → 14 | world_rules (house) |
| §9 mechanics | `demand_model` → "per airport"; `treaties` → as the world's settings page says (filled in during the build); `time_zones` → "standard time all year"; `subsidiaries_work` → false | world_rules (game) |
| #12 | `interline_own_airlines`, `capture_salary_step`, `world_scanner`, `schedule_check` → allowed | world_rules (permission) |

The planner's `ref.consts` map one to one: `buf`, `ovh`, `arrwin`, `depwin`, `maxWait`, `legalGap`, `turnMargin`,
`maintMinGround`, `leeway`, `lfWindow` to the settings above, and `depCap` to the house rule's 5,000. The capture and
the scanner read their permission row and refuse to run where it says no.

### 3.8 Capture data

| Table | Purpose | Kept | Replaces |
|---|---|---|---|
| `game_flights` | **One row per flown flight:** loads from the loads page and money from the bank statement | One full calendar month, then archived (#16) | `game_loads`, and the flight lines of `game_statement` |
| `game_statement` | Raw statement lines, for checking | 14 days, then deleted (the nightly copies keep them 30 days) | as today, plus `world_id`, `airline_id`, `flight_id` |
| `game_payments` | Statement lines not tied to a flight: leases, week-end closings (salaries), purchases, deposits, cabins, refits | For good (about 100 a week) | the non-flight lines of `game_statement` |
| `game_events` | Payments the game lists ahead | One month, then archived | as today, plus ids and `due_at` (from the home airport's local time) |
| `game_balance` | Balance sheet per airline and capture | For good | as today, plus ids and `capture_day` |
| `game_pnl` | Income statement per airline and capture | For good | as today, plus ids and `capture_day` |
| `game_capture_raw` | Raw pages | 14 days | as today, plus ids |
| `capture_keys` | Hashed capture keys | — | as today, plus `world_id`: a key belongs to one world |

`game_payments` columns: `id`, `world`, `airline`, `paid_at`, `kind` (lease, salaries, purchase, deposit, cabin, refit,
other), `registration` (from "Leasing rate for B-0161"), `aircraft_id`, `descr`, `amount money`, `side` (D, C), `occ`;
unique (`airline_id`, `paid_at`, `descr`, `amount`, `occ`). Capture tables have no foreign keys to `airports`: a page
must never be refused because it names an airport we don't know yet.

| `game_flights` column | Type | Notes |
|---|---|---|
| `id`, `world`, `airline` | | |
| `game_date` | date | the local date at departure, as the loads page shows it |
| `flight_no` | int | null until the loads page names the flight; the statement doesn't |
| `origin_code`, `dest_code` | text | |
| `dep_local`, `arr_local` | text | "07:30", as the game shows them |
| `dep_at`, `arr_at` | timestamptz | scheduled, from the local times and offsets; for a money-only row, the statement time |
| `posted_at` | timestamptz | the statement's time for the flight: its actual departure, UTC |
| `statement_blk`, `statement_routes` | smallint | today's `blk`, and how many routes the block named |
| `route_id`, `aircraft_id` | bigint | matched when known |
| `registration` | text | from the loads page |
| `maint_registration` | text | from the statement's maintenance line: today's `game_flight_pnl.tail` |
| `status` | text | finished, inflight |
| `eco_pax`, `eco_seats`, `eco_fare`; `bus_*`; `fst_*` | int, int, money | by class |
| `cargo_units`, `cargo_cap`, `cargo_rate` | int, int, money | |
| `eco_pct`, `bus_pct`, `fst_pct`, `cargo_pct` | smallint | generated: round(100 × pax ÷ seats). In the sample this equals the game's figure for every economy (513) and business (361) load; the build confirms the rounding on all captured rows, and stores the game's figure instead if they ever differ |
| `pax_income`, `cargo_income`, `fuel`, `onboard`, `handling`, `landing`, `atc`, `maintenance` | money | by type, as `game_flight_pnl` today |
| `income_total`, `cost_total` | money | every line of the block by side, so the old views add up exactly |
| `profit` | money | generated: `income_total − cost_total` |
| `statement_pax` | int | passengers named on the statement |
| `loads_captured_at`, `money_captured_at` | timestamptz | |

Keys: unique (`airline_id`, `dep_at`, `flight_no`) where `flight_no` is set; unique (`airline_id`, `posted_at`,
`statement_blk`) where `posted_at` is set. Indexes: (`world_id`, `dep_at`); (`airline_id`, `game_date`);
(`route_id`, `dep_at`). Other capture indexes: `game_payments` (`airline_id`, `paid_at`); `game_events`
(`airline_id`, `event_date`); `game_balance` (`airline_id`, `captured_at`).

**Matching money to loads.** The statement names no flight. Its time is the actual departure in UTC: KF 1002 on 7 Oct
was scheduled 07:30 at JFK (12:30 UTC) and posted at 12:37. A statement block joins the loads row of the same airline
and route whose `dep_at` is nearest its `posted_at`, within −30 minutes to +3 hours. A block with no partner yet
stays a money-only row, and the loads page fills it in when it comes (the statement covers 3 days, the loads page 24
hours). The rehearsal compares the old views with the new ones, row by row, on last night's copy.

### 3.9 World scans

| Table | Purpose | Kept | Replaces |
|---|---|---|---|
| `game_scans` | One row per world scan | For good | `game_snapshots`, plus `world_id` |
| `game_scan_airlines` | Each airline's totals in a scan: `scan_id`, `airline_id`, `n_flights`, `n_weekly`, `n_airports` | For good | the totals in `game_snapshot_airlines` |
| `game_scan_schedules` | Each airline's full schedule: `scan_id`, `airline_id`, `flights jsonb` | One month, then archived | the `flights` column of `game_snapshot_airlines` |
| `game_scan_airports` | Each airport's page: `info`, `stations`, `news` | One month, then archived | `game_snapshot_airports` |
| `scan_airline_airports` | Summary: `scan_id`, `airline_id`, `airport_code`, `weekly_departures`, `destinations` | For good | — (built when a scan finishes) |
| `scan_airline_markets` | Summary: `scan_id`, `airline_id`, `market` (the weekly report's market names), `weekly_departures`, `city_pairs` | For good | — (sent by the report script, which owns the market definitions) |

Every airline a scan sees becomes an `airlines` row by game ID, so rivals can be placed in groups. Summaries are keyed
(`scan_id`, `airline_id`, `airport_code` or `market`) with an index on (`airline_id`, `scan_id`).

### 3.10 History

| Table | Purpose | Key | Replaces |
|---|---|---|---|
| `change_log` | Every change to the planner's tables: old and new values, when and who (§6) | `id` | — |
| `airline_days` | One row per airline per capture day (§7) | (`airline_id`, `day`); index (`world_id`, `day`) | `cash`, `fixed7` as history |
| `route_days` | Per route, direction and UTC day: `world`, `airline`, `route_id` (when matched), `origin_code`, `dest_code`, `day`, `flights`, `passengers`, `seats`, `revenue`, `costs`, `profit`, `eco_fare_avg` | (`airline_id`, `origin_code`, `dest_code`, `day`); index (`world_id`, `day`) | — |

`airline_days` columns: `world`, `airline`, `day`, `complete`, `source` (capture, fallback, backfill), `taken_at`.
Point in time: `aircraft_by_type jsonb` ({"A321 NEO LIGHT": 50, …}), `aircraft_total`, `on_order`,
`weekly_departures`, `weekly_seats`, `destinations`, `cash`, `fixed_next7`, `cash_at` (the balance's capture time).
Flows for the UTC day: `flights_flown`, `passengers`, `seats_flown`, `load_pct`, `eco_load_pct`, `revenue`,
`flight_costs`, `flight_profit` (before leases), `leases_paid`, `salaries_paid`, `purchases_paid`.

### 3.11 Jobs

| Table | Purpose | Columns | Replaces |
|---|---|---|---|
| `job_runs` | One row per run of every job | `id`, `job` (backup, snapshot, snapshot_fallback, cleanup, archive, adapter_check), `world_id` (optional), `started_at`, `finished_at`, `status` (running, ok, failed, incomplete), `for_day`, `for_month`, `note`, `details jsonb` (backup: kind, tables, rows, files, bytes, object_key, commit_sha; archive: table, rows, checksum, file keys, layout) | `backup_runs`: its rows move here, and the old name stays as a view |

Index: (`job`, `started_at desc`).

### 3.12 Views
Every view is `security_invoker = true`: it shows the caller only what the caller may read.

| View | Shows |
|---|---|
| `flight_legs_local` | Each leg with `flight_code` ("KF 1001"), local departure and arrival, local weekdays, and the arrival's UTC time and day offset |
| `flight_no_clashes` | The same airline, number and departure weekday used twice |
| `capture_cash` | Per airline and capture date, cash and next-7-day payments worked out from the capture exactly as the planner does today (latest balance of account 2800; payments in the 7 days after it) |
| `game_loads`, `game_flight_pnl`, `game_ops_recent` | Today's shapes, from `game_flights`, so the old planner and `export_capture` read them unchanged |
| `backup_runs` | Today's shape, from `job_runs`, with an `instead of insert` trigger that turns the backup job's row into a `job_runs` row, so the job keeps working whatever the deploy order |

### 3.13 Today's tables after the switch-over

| Today | Becomes |
|---|---|
| `planner_state` | Frozen: refuses writes; kept as the fallback until #18 |
| `planner_loads`, `planner_data`, `planner_meta` | Frozen; kept until #18 |
| `game_loads` | Rows moved to `game_flights`; table renamed `game_loads_before_13`; the name becomes a view |
| `game_snapshots`, `game_snapshot_airlines`, `game_snapshot_airports` | Renamed and split (§3.9) |
| `backup_runs` | Rows moved to `job_runs`; table renamed `backup_runs_before_13`; the name becomes a view |
| `site_content` | Unchanged, except `mct` moves to `world_airports` (`site_public()` still returns it in the same place) |
| Everything else | Unchanged, apart from ids added to the capture tables. Renamed old tables are dropped at #18 |

## 4. Flights in detail
**A frequency becomes a rotation and two legs.** Today's frequency `z5qbaeg`: Kingfisher DEL–JFK on VT-AAA, days
"135", out 01:30 → 04:19, back 07:30 → 07:19, numbers 1001 and 1002. Delhi is UTC+5:30, New York UTC−5.

| | Leg 1: KF 1001 DEL → JFK | Leg 2: KF 1002 JFK → DEL |
|---|---|---|
| Local, as the game shows it | Mon, Wed, Fri 01:30 → 04:19 the same day | Mon, Wed, Fri 07:30 → 07:19 the next day |
| `days_utc` | {2,4,7}: Tue, Thu, Sun | {1,3,5} |
| `dep_utc_min` | 1200: 20:00 UTC, the evening before | 750: 12:30 UTC |
| `block_min` | 799 (13:19) | 799 |
| Arrival, worked out | 09:19 UTC the next day = 04:19 at JFK, Mon, Wed, Fri | 01:49 UTC the next day = 07:19 at DEL, Tue, Thu, Sat |

The rotation row holds the route, `legacy_key` `z5qbaeg`, service S3, fare 100% and launch date 22 Sep. The outbound's
UTC weekdays differ from its local ones, and the return lands the next day. Today both are guessed each time a flight
is drawn; here they're stored once.

**Weekdays across UTC midnight.** `dep_utc = dep_local − offset`. If that falls before 00:00, every weekday moves back
one (Mon → Sun); after 24:00, forward one. Display does the reverse. 59 of today's 235 frequencies have a leg whose
UTC day differs from its local day, mostly evening and night departures. All are daily except DEL–JFK, which is why
the mismatch hasn't shown yet.

**A return on the next day.** The old planner stores only the outbound's weekdays. Its rule: the return leaves on the
local day the outbound arrives, or the next day if its departure time is earlier than the outbound's arrival time.
Pan Am's JFK–LHR leaves JFK 06:45 and reaches LHR at 18:15; the return leaves LHR at 01:45, so the next day. Were it
flown Mon, Wed, Fri, the return would be stored as Tue, Thu, Sat. The adapter applies the rule once when it turns an
old-planner frequency into legs, and in reverse when it builds the old JSON. From #18 each leg's days are set directly,
and a return more than 24 hours later can be stored.

**Block time** is stored per leg in minutes, from the game's own times: arrival local − departure local − (offset at
destination − offset at origin), wrapped into 0–24 hours. The manual's formula (25 minutes + distance ÷ cruise speed)
is only for estimates, from `block_allowance_min` and `aircraft_types.cruise_kmh`, as today. A leg whose arrival isn't
typed yet has `block_min` null and the planner estimates it.

**Local times for display:** `(dep_utc_min + round(offset × 60)) mod 1440`, with the world's offset for the airport.
The game has no daylight saving, so this is exact all year. If an offset ever turns out wrong, a one-off fix re-times
the legs touching that airport so their local times stay as the game shows them (the game is right; our offset was
wrong).

**Flight numbers** are `int`. Of today's 470, 463 are stored as text and 7 as numbers; all are digits. The airline's
code is added for display ("KF 1001"); the capture splits the game's "VS 1022" the same way. The adapter hands the old
planner text, as most entries are today.

**Seats** for a leg come from its aircraft's cabin, or the type's maximum when there's no cabin.

## 5. Access rules
#11 stands: sign-ups are off, the only account is Gitesh's, and the staff rule is `public.is_planner_user()`.

| Who | How | What they can do |
|---|---|---|
| Gitesh in the planner (`authenticated`, staff) | The adapter functions and the compatibility views; from #18, the tables directly | Read every planner and capture table and view; write the planner's tables (through the adapter until #18) |
| The public website (`anon`) | `site_public()`, `site_newsletter()` | Nothing else: no grants on any table or view |
| Investors (`anon` + password) | `site_investor()`, `site_report()` | As today |
| The capture (`anon` + capture key) | `capture_ingest()`, `capture_airlines()` | Its own world's capture tables, through the functions |
| Claude's scripts (ingest secret) | `export_*`, `ingest_snapshot`, `site_admin`, `planner_data_set` | As today (#11 kept the secret) |
| Claude in chats | Direct SQL through the Supabase connector, as `postgres` | Everything; names itself in each write (§6) |
| Jobs | `pg_cron`, as `postgres` | Their own functions |
| The backup job | `SUPABASE_DB_URL`, as `postgres` | Reads everything; deletes only through `archive_delete()` |

**Rules:**
- **RLS on every table.** One policy per action for staff, written `using ((select public.is_planner_user()))`, so the
  check runs once per query, not once per row.
- **Explicit grants.** `anon` gets nothing on any table or view. `authenticated` gets `select` on what staff read,
  and `insert, update, delete` only on the planner's own tables. Default privileges for new tables are revoked from
  `anon` and `authenticated`, so a forgotten grant fails closed.
- **Views are `security_invoker`.** This also closes the two views #11 accepted as open to any signed-in account,
  since compatibility views replace them.
- **Functions:** `revoke execute … from public, anon` on everything, then grant each to the role that calls it.
  - `SECURITY DEFINER` only where the caller mustn't read tables directly, each with `set search_path = ''` and its own
    check: the website and investor functions, `capture_ingest`, the ingest-secret functions, and the change-log
    trigger (so a log row can be written while the log stays read-only).
  - The adapter functions are `SECURITY INVOKER`, so RLS checks them, and they also refuse anyone who isn't staff.
  - Internal steps (parsing, matching, snapshots, archive, adapter internals) live in a `private` schema that the data
    API doesn't expose. `parse_capture` and the loads step move there too, which closes the other gap #11 accepted.
- **The public feed keeps its 6 Oct limits:** no bank or transfer times, no cabin layouts, no aircraft on order.

**Tests** (`database/tests/`, run by the rehearsal and against the local Supabase from #17):
- **a signed-out visitor reads nothing:** for every table and view in `public`, `has_table_privilege('anon', …,
  'select')` is false, and a REST read with the anon key returns nothing;
- every table has RLS on, and every view is `security_invoker`;
- a signed-in account that isn't staff reads no rows;
- staff read and save through the adapter.

## 6. The change log (#15)
**One table, one trigger.** `change_log`: `id`, `changed_at` (`clock_timestamp()`), `world_id`, `table_name`,
`row_key jsonb` (the primary key, e.g. `{"id": 812}`), `op` (insert, update, delete), `old_values jsonb`,
`new_values jsonb`, `actor` (planner, claude, capture, script, job, migration, unset), `actor_detail` (a tab ID, a
script or chat name), `db_role`, `txid`. Indexes: (`world_id`, `changed_at`); (`table_name`, `changed_at`).
- Updates record only the columns that changed, ignoring `updated_at`; an update that changes nothing writes no row.
  Inserts record the new row, deletes the old one.
- One trigger function, `private.log_change()`, `after insert or update or delete for each row`, on every planner
  table: worlds, groups, airlines and their bases and buy list, countries, airports, world airports, aircraft types,
  cabin configs, aircraft, cabin keeps, markets, service profiles, routes, rotations, flight legs, plan cards and
  their legs, to-dos and their items, growth log, spending log, fare plan, interline, monthly checks, dismissals, cash
  and load entries, load days, settings and world rules.
- **Not logged:** the capture and scan tables, `airline_days`, `route_days`, `job_runs`, the website's tables and the
  log itself. They're dated already, or derived.

**Who made a change.** Roles can't tell the writers apart (Claude, the jobs and the backup all run as `postgres`), so
every writer names itself for its transaction:
- the adapter: `set_config('equinox.actor', 'planner', true)`, with the tab's ID in `equinox.actor_detail`;
- `capture_ingest`: `capture`; the ingest-secret functions: `script`; jobs: `job`; migrations and the data load:
  `migration`;
- Claude in a chat starts every write, in the same call as the change, with
  `select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', '<chat>', true);`.
  Manual §1 says so from the switch-over.
- **If nothing is set:** `planner` when a signed-in user made the change (`auth.uid()` is set), otherwise `unset`,
  with the role recorded. Nothing is refused; `unset` rows are listed at the weekly review so the gap gets fixed.

**The first load runs with logging off.** The trigger skips when `equinox.change_log` is `off`, and honours that only
when the session user is `postgres`, so neither the website nor the planner can switch it off. Only the data load sets
it.

**Undo.** `private.restore_row(table, row_key, as_of)` puts one row back as it was at a moment, by replaying the log
backwards. The restore is itself logged.

**Kept 12 months,** then archived month by month like the detail (§7). Expected size: 20–60 MB a year (#15).

## 7. Snapshots, clean-ups and the archive
**The daily snapshot** (`airline_days`, `route_days`):
- **When:** as soon as a world's capture for the day is complete, from inside `capture_ingest`, after the page that
  completes it. Complete means every active airline of our groups in that world has all five pages (statement,
  events, income statement, balance sheet, loads) inside the capture day. That's "all of that world's airlines", not
  6, which also removes the 7th-airline bug (consistency point 4).
- **Fallback:** a `pg_cron` job at 10:00 UTC takes the snapshot for the day just ended if none was taken, marked
  `complete = false` and `source = 'fallback'`. Cash then comes from the latest balance before it.
- **Fixed and refreshed:** point-in-time figures (fleet, schedule, cash) are fixed when taken; a later complete capture
  for the same day replaces them. Flow figures (flights, passengers, money) for the two days before are recomputed on
  each run, since a late capture can still fill them in.
- **Filling a gap later:** any day since the tables went live can be rebuilt from the change log (the schedule as it
  stood), `game_balance` and `game_flights`. So snapshots needn't start the same day the tables do.
- **Sources:** fleet and schedule from `aircraft` and `flight_legs`; cash from `game_balance` account 2800, or
  `cash_entries` with no capture; next-7-day costs from `game_events`, as the planner works them out today; flows from
  `game_flights` and `game_payments` for the UTC day.

**Clean-ups** (`pg_cron`, 10:20 UTC daily, one `job_runs` row each):
- `game_statement` lines older than 14 days, only once their flights are in `game_flights` (the job checks counts
  first);
- `game_capture_raw` older than 14 days (moved out of `capture_ingest`, which does it on every page today).
- **The statement clean-up ships switched off,** and is switched on only once the per-flight backfill (§9) is checked
  on live, so no statement line since 6 Oct is deleted before it's folded (checklist: backfill order).

**The monthly archive** runs in the nightly backup job, which already holds the database and R2 keys (jobs brief):

| Table | Archived once it's |
|---|---|
| `game_flights` (by `dep_at`), `game_events` (by `event_date`), `game_scan_schedules`, `game_scan_airports` (by scan time) | more than one full calendar month old: October on or after 1 December |
| `change_log` (by `changed_at`) | older than the last 12 full months |

On the first nightly run on or after the 1st, retried each night until done:
1. `private.archive_manifest(month, table)` returns the row count, a checksum (`md5` of the rows in primary-key
   order) and the table's layout: its columns, their types and the latest migration version. **Archives keep their
   layout version,** because #18 will change the tables (checklist).
2. The job exports the rows to `archive/<table>/<YYYY-MM>.csv.gz`, with the manifest beside it, in R2 and on the
   month's GitHub release (the second copy, outside Cloudflare).
3. It reads both copies back and checks the row count and SHA-256.
4. It calls `private.archive_delete(month, table, expected_count, checksum)`, which refuses:
   - a table not listed above;
   - a month inside the kept window;
   - a count or checksum that no longer matches (rows changed since the manifest);
   - `game_flights` for a month whose days aren't all in `route_days`.

   Otherwise it deletes those rows and records the run in `job_runs`.

**`job_runs` and the planner.** Every job writes a row when it starts and finishes it when it ends. The planner's
Home warns when:
- the last good backup is more than 30 hours old (as today);
- the latest snapshot is more than 30 hours old;
- the month's archive hasn't run by the 3rd;
- any job's last run failed.

That's a few lines in the old planner's Home, the only screen change before #18.

**Backups** need no change for the new tables: the nightly copy takes every table except the key tables, as today.
The backup job gains only the archive step, and its result row lands in `job_runs` through the `backup_runs` view.

## 8. The adapter
**What changes in the old planner.** Only its storage layer: the `dbAdapter` shim in `web/planner/index.html`, plus
`cloudSavedAt` and `cloudWrite`, about 20 lines. Every screen stays as it is.

| Function | Replaces | Does |
|---|---|---|
| `planner_state_get(world_id default null)` | reading `planner_state` | Builds today's JSON from the tables; returns `{json: text, saved_at}`. `saved_at` is the time of the latest logged change in milliseconds, never earlier than the old row's last save |
| `planner_state_version(world_id default null)` | reading `saved_at` before each save | That time only, without building the JSON, so the check before each save stays cheap |
| `planner_state_put(json text, saved_at bigint, base bigint, client text)` | the upsert of the whole row | Compares the JSON with the tables and writes only the rows that changed (below). Returns `{saved_at, applied, skipped, reload}` |
| `planner_loads_get(world_id default null)` | reading `planner_loads` | Builds each month's loads document from `game_flights`, `load_entries` and `load_days` |
| `save_loads(month, days)` | same name and arguments | Writes typed loads to `load_entries` and `load_days`; returns the merged month, as today |
| `planner_item_put(section, key, value jsonb)`, `planner_item_delete(section, key)` | Claude editing `planner_state` by hand | One item in today's JSON shape (a plan card, a to-do, a frequency), through the same code as a save. For other chats' data-only changes |

The shim's `get` and `set` call the first and third; `collection("loads")` calls `planner_loads_get`;
`cloudSavedAt` calls `planner_state_version`. `cloudWrite` keeps the `saved_at` the server returns (server time, not
the browser's), and on `reload` takes the existing path: reload, with the existing message. The three read functions
join `READ_ONLY_RPCS`, so previews can read and still can't save. The tab's ID is made once per page load.

**Saving only what changed** (#15's condition). Each section maps to a table and a key:

| Section | Table | Matched by |
|---|---|---|
| `tails`, `deliveries` | `aircraft` | registration |
| `freqs` | `rotations`, `flight_legs` | `legacy_key` |
| `plans` | `plan_cards`, `plan_card_legs` | registration; legs replaced as a set when any differs |
| `todos` | `todos`, `todo_items` | `legacy_key` |
| `routesAdded`, `routeEdits`, `routeCabin` | `routes` | airline, hub, destination |
| `capex`, `growthLog` | `spending_log`, `growth_log` | the whole entry (they have no ID); identical entries are interchangeable |
| `farePlan` | `fare_plan` | `legacy_key` |
| `interline`, `monthly`, `dismissed`, `cabinKeep` | their tables | the parts of the old key |
| `ref.*` | bases, types, configs, markets, services, world airports, settings | code or name |
| `cash`, `fixed7` | `cash_entries` | airline and date; stored only when it differs from the capture's figure (below) |

**When a save meets a newer change.** Today a stale tab either reloads and loses the click, or overwrites. The
adapter:
1. takes a lock for the world (`pg_advisory_xact_lock`), so saves queue instead of racing;
2. works out every row the save would change;
3. skips any row that someone else changed after the tab's `base`: the log shows a later change by another actor or
   another tab. With no base (the planner pushing a copy from the browser's own storage), the save's own time is used;
4. writes the rest, and answers `reload: true` if it skipped anything, so the tab picks up the newer data.

So a click touching other rows is kept, and a newer change is never overwritten (§11, choice 4).

**Cash and next-7-day costs.** The old planner copies cash into its JSON from the capture (`applyCaptureCash`) and
lets Gitesh type it (Manual entry). The getter returns the capture's figure from `capture_cash`, unless a
`cash_entries` row exists for that airline and date, which wins. A save stores a value only when it differs from the
capture's figure, and removes the entry once they agree again. That matches the planner: the capture overwrites a
typed figure at the next refresh.

**Loads.** `planner_loads_get` builds the month documents the planner reads today:
- `f`: each flight's economy load, keyed "Airline|number", from `game_flights` (by `game_date`) and `load_entries`;
- `done`: true when all of the world's airlines were captured for that date, or as typed;
- `source`, `captured` and `savedAt`, as today.

For each flight and each day's flags, the latest write wins, captured or typed: how today's two merges behave
together. The loads bug goes at its root, since there's no month document left to overwrite. Detail older than a
month leaves `game_flights` with the archive; the old planner only looks back 14 days.

**The website and scripts keep their outputs exactly:**
- `site_public()` builds hubs, tails, compact frequencies, signed interlines and `content.mct` from the tables. It adds
  one key, `airlines` (names, codes, colours, descriptions), which the website reads instead of its own copy (#14).
- `site_investor()` reads cash and costs as the getter does, and spending from `spending_log`.
- `export_for_report('planner')` returns `{state: planner_state_get(), loads: planner_loads_get()}`. Its scan kinds
  read the renamed scan tables, with the same output.
- `planner_data_set` writes `routes`, `airports` and `countries` (changed rows only); `site_admin('content', 'mct')`
  writes `world_airports`.
- The Photos functions check the airline against `airlines` instead of a list in their code.

**At the switch-over** (checklist: cut-over):
- `planner_state` refuses writes: a trigger raises "frozen since <date>; write to the tables", and `insert, update`
  are revoked. `planner_loads` likewise.
- **Other chats' data-only changes** (plan cards, to-dos, logs) go to the new tables: through `planner_item_put` in
  today's JSON shape, which also converts plan-card local times to UTC, or plain SQL, after the `equinox.actor` line
  (§6). Manual §1 is updated in the same pull request.
- **Rollback:** `private.unfreeze_planner_state()` writes `planner_state` from `planner_state_get()`, so nothing since
  the switch is lost, and lifts the freeze; then revert the switch-over pull request. The old row stays as the
  fallback until #18 is done.

## 9. Moving the data
**Order.** Each step is a migration, tried by the rehearsal on last night's copy before it reaches live. Loads run
with `equinox.change_log = off` and `equinox.actor = migration`.
1. **Reference rows** (PR 2): Gander; the equinox. group, owned by Gitesh; our six airlines with their game IDs,
   codes, home airports, colours and website text, from `capture_all.user.js`, the planner's constants and `site.js`.
2. **Capture data** (PR 3): `game_flights` from every statement line since 6 Oct, plus the loads rows; non-flight
   lines into `game_payments`; ids on the other capture tables (the scan tables are renamed and split with the history, PR 6). **This happens before
   the 14-day statement clean-up is ever switched on.**
3. **The planner's data** (PR 4), from `planner_state`, `planner_loads`, `planner_data`, `site_content.mct`,
   `planner_meta.growthRules` and the code constants:
   - countries, airports and world airports;
   - types, configs, markets, services, bases, buy lists, settings and world rules;
   - aircraft, with tails and deliveries merged;
   - routes: research, added, edits and route cabins;
   - rotations and legs, with the return-day rule applied once;
   - plan cards, to-dos, the logs, interline, monthly checks, dismissals;
   - cash: every stored value the capture doesn't reproduce exactly becomes a `cash_entries` row (all of 29 Sep to
     6 Oct, and any captured date that differs), so nothing on screen moves;
   - loads: typed values and day flags the capture doesn't reproduce go to `load_entries` and `load_days`.
4. **History** (PR 6):
   - `route_days` from `game_flights` since 6 Oct;
   - `airline_days`: cash from 29 Sep (the stored figures, then `game_balance` from 7 Oct); flights from 6 Oct; the
     fleet from delivery dates (aircraft without a delivery record counted from the 22 Sep start); weekly departures
     from each rotation's launch date, assuming nothing was dropped, marked `source = 'backfill'`;
   - the 6 Oct scan's summaries.

**Proving old and new are the same:**
- **On the frozen sample** (`tests/fixtures/sample_2026-10-08.json.gz`), loaded into an empty copy:
  - `planner_state_get()` equals the sample's `planner_state`;
  - `planner_loads_get()` equals the sample's loads;
  - `site_public()` equals the sample's, apart from `updated_at`;
  - the compatibility views equal the sample's capture reads.

  Allowed differences, and only these: key order; a missing key equals `null`; numbers compared by value (2.15 =
  2.150000); flight numbers compared as text; a tail with no `status` equals "Active" (one aircraft, VT-AAE); `savedAt`
  and `version`. The sample has money per flight but not the raw statement lines, so for this test `game_flights` is
  loaded from the sample's `game_flight_pnl` rows.
- **Round trip:** `planner_state_put(planner_state_get())` changes no rows and writes no log.
- **On last night's copy** (the rehearsal): the same comparisons against the real `planner_state`, and the old views
  (worked out before the migration) against the new ones, row by row, every statement block since 6 Oct included.
- **Real saves** (the local Supabase from #17): the planner checks sign in, tick a to-do, edit a plan card, add a
  frequency and type loads; the test then reads the tables and the log to confirm exactly those rows changed, with
  actor `planner`.
- **Side by side on live** (PR 5 to PR 9): a trigger on `planner_state` copies every save of the old row into the
  tables through the adapter, in mirror mode (no skipping, since the old row is still the truth). A failure is
  recorded in `job_runs` and never blocks the save. The capture keeps writing `planner_loads` as today until the
  switch-over. After each save of the old rows, `planner_state_get()` and `planner_loads_get()` are compared with them (a `job_runs` row each; changed 10 Oct from a nightly job, so no scheduler is needed before PR 7). The
  switch-over was to wait for 3 clean nights in a row (§11, choice 1); since 10 Oct it goes as soon as PR 8 and PR 9 are built, with no failure outstanding.

**Rollback:**
- before the switch-over: nothing reads the new tables, so revert, or drop the side-by-side trigger;
- after it: `private.unfreeze_planner_state()`, then revert the switch-over (§8);
- the capture changes (PR 3): the old tables are renamed, not dropped, until #18, so a revert puts them back.

## 10. Build order
One pull request each, each with its own spec for a fresh helper (#26), each merged and applied to live before the
next starts. Any step that removes something (a grant, a policy, a function) has that part run by Gitesh in
Supabase's SQL editor, as manual §1 requires; the pull request says which file.

| # | Pull request | Proves |
|---|---|---|
| 1 | **Full local Supabase in the checks** (#17): the rehearsal starts the database, data API and sign-in with last night's copy; the planner checks sign in as a test staff user and save for real | Saves can be tested before live |
| 2 | **The tables**, empty: everything in §3 with RLS, grants, descriptions, the change-log trigger and the `private` schema; reference rows for Gander and our airlines | A signed-out visitor reads nothing; the log names its writer; every description is there |
| 3 | **Capture data:** `game_flights`, `game_payments`, ids on the capture tables; `capture_ingest` matches airlines by game ID (and still accepts the old names until the new userscript is in) and checks completeness by world; `capture_airlines()` and a userscript that reads its airlines from it (Gitesh reinstalls it with his key: a to-do); compatibility views; backfill since 6 Oct | Old and new views agree on last night's copy; the capture works on saved pages |
| 4 | **Data load and the adapter's read side:** the loader, `planner_state_get`, `planner_state_version`, `planner_loads_get` | The getter equals today's JSON on the sample and on last night's copy |
| 5 | **The adapter's write side:** `planner_state_put`, `save_loads` rewritten, `planner_item_put`/`_delete`, the side-by-side trigger, the comparison after each save, and `job_runs` | A round trip writes nothing; real saves change only the intended rows; live stays equal night after night |
| 6 | **History:** `airline_days`, `route_days`, the scan tables renamed and split (moved here from 3 on 9 Oct, so the scan's functions change once), scan summaries, the snapshot on a complete capture, backfill | Backfilled days match the known cash and flights |
| 7 | **Jobs:** `pg_cron` on; `job_runs` and the `backup_runs` view; the 10:00 fallback; clean-ups (statement clean-up off until PR 3's backfill is checked on live); archive manifest and guarded delete; the archive step in `equinox-backups`; Home warnings | Jobs run on the copy; `archive_delete` refuses a wrong month, count or checksum |
| 8 | **Website and scripts:** `site_public`, `site_investor`, `export_*`, `planner_data_set`, `site_admin` and the Photos functions on the tables; the website reads airline text from the data | Website checks pass; outputs equal today's |
| 9 | **Switch-over:** the planner's storage shim moves to the adapter; `planner_state` and `planner_loads` frozen; side-by-side removed; manual §1, §3, §4, §7 and §9, the map and the table guide updated; a new test sample | Planner checks pass with real saves; the rollback is rehearsed on the copy |
| 10 | **Report PDFs to a private storage bucket** (#16), independent of the rest | The investor library and gander monthly still download |

## 11. Choices made
Gitesh asked on 9 Oct whether any of these needed him. None does: each follows from what #13 to #17 already
decided, and each can be changed later. So they were Claude's call. The chosen option is marked.

1. **How long old and new run side by side before the switch.**
   - A. Switch as soon as the checks pass.
   - **B. After 3 nights in a row with no difference on live. Chosen 9 Oct.** Real use catches what tests miss, for a
     few days' wait.
   - **Changed 10 Oct by Gitesh: no waiting for clean days.** The switch-over (PR 9) goes as soon as it's built,
     after PR 8 (the website and scripts must read the tables before the old row freezes). The comparison keeps
     running until then, and a failure found before the switch is fixed first.
   - C. After a week.
2. **How much of each world scan to keep for good.**
   - **A. Each airline's totals, per airport and per market. Chosen.** Roughly 5 to 15 MB a year with weekly
     scans, enough for market share by airport and by market. The full schedules stay in the monthly archives for
     anything else.
   - B. Also each airline's weekly departures per city pair, for route-level trends kept for good: roughly 20 to
     50 MB a year more.

   Both sizes are estimates from the scan's 800 KB of schedules; the build measures them on the 6 Oct scan. A fits
   #16 (summaries kept, detail archived), and B can still be built later from the archived schedules.
3. **The rule numbers the old planner keeps in its code** (the 0.5M cushion, 750 departures, growth thresholds,
   airline codes and colours, the types each airline may buy).
   - **A. The tables are the source; the old planner keeps its copies until #18, and a check fails if the two ever
     differ. Chosen.** No rewrite of a planner #18 replaces.
   - B. Change the old planner to read them from the tables now: more edits that #18 throws away.
4. **When a save meets a newer change.**
   - **A. Keep the rows that don't clash, skip the ones that do, and reload. Chosen.** Your click survives
     unless it hit the very row that changed.
   - B. Refuse the whole save and reload, as today: simpler, but the click is lost.

**Found in the code, handled as described** (no decision needed; raised so nothing is changed silently):
- Flight numbers repeat on alternate days (Kingfisher 1001/1002 on two aircraft), so there's no unique constraint on
  them (§3.4).
- The return's weekdays are still worked out by the old planner's rule while it's in use (§4).
- **The connection buffer differed between tools:** the manual said connection time + 10 minutes, the planner's bank
  check used a buffer of 0 (`ref.consts.buf`) and its connection count the connection time alone, while the
  optimiser added 10. Settled 9 Oct by Gitesh: no margin, the minimum connection time is enough (manual §4). The
  setting is 0; the optimiser changes to match in its own pull request.
- The planner copies captured cash into its own JSON, and its "today" mixes the browser's date with UTC (Manual entry
  uses UTC). The adapter keeps the planner's date keys; the new tables use capture days (§2).
- `game_balance.captured_on` is the UTC date, a day after Gitesh's evening (§2).
- The route research mixes country names and codes; kept as given for the old planner, and #18 uses the airport's
  country instead.
- 22 aircraft were refitted after delivery, so the ordered cabin and today's differ; both are kept.
- The statement names no flight, so money joins loads by route and time (§3.8); the rehearsal checks every block.
- `game_flight_pnl.tail` comes only from maintenance lines (104 of 516 flights). The compatibility view keeps that;
  #18 can use the loads page's registration, which every flight has.
- Renaming an aircraft in the old planner looks like one aircraft removed and another added, which breaks its history
  link. Until #18, ask Claude to rename: one update keeps the history.
- The website still has code for aircraft on order, which `site_public()` deliberately stopped sending on 6 Oct.
  Harmless; left as it is.
- `countries` and `airports` carry no world (§2): the one place this design reads #14's "every row" narrowly.

## 12. What this design does not do
- **#18:** no new planner and no screen changes, apart from Home's job warnings. No world switcher yet.
- **#19:** block times, connections and maintenance are still worked out separately in the planner, the website and
  the optimiser. The tables make one shared library possible later.
- **#20:** the website still gets everything in one call, `site_public()`, the same size as today.
- **#21:** no capture safeguards beyond completeness by world; parser tests on saved pages and short-capture alerts
  come later.
- **#22:** the weekly world scan and report drafts stay manual.
- **#23:** only the job warnings on Home; no single monitoring page.
- **#24:** only the views needed here; no ready-made report views.
- **#25:** no unattended Claude jobs.
- Accounts for other players: dropped at #14.

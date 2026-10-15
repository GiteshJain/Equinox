# Scripts

The Python scripts Claude runs for the airline briefing, the weekly report, gander monthly and the world scan, and the
planning library's command, which is the schedule optimiser (decision #10; #19; #24). They are Claude's working tools, not part of the website or
planner, and they run in Claude's workspace.

**Before running any of them**, know these limits as they stand on 8 Oct 2026:
- **Fixed paths.** They read and write files in `/home/claude/` and the current folder.
- **Two key files.** `~/.sb_anon` holds the public Supabase key, which is also in the planner's code.
  `~/.ingest_secret` holds the ingest secret, taken from the `ingest_secret` table. Neither file is ever committed.
  Recreate them in a new workspace before running a script. Decision #11 keeps the ingest secret as it is.
- **Hand-made inputs.** Some inputs aren't made by any script yet. Where each one comes from is listed below.
- **To be cleaned up:** these points are for #22 (scheduled jobs). Until then, run the scripts the way this page says.

All database access goes through functions described in `docs/data.md`. Which call answers which question, with a
tested example of each: the map, `docs/architecture.md`.

## The airline briefing (Scheduling chat, any chat)
One airline's whole background in one step (decision #24): where the scheduling routine starts (manual §4). From a
clone of the repository, with the planning library built (`npm ci && npm run build`) and the two key files in place:

```bash
python3 scripts/briefing/brief.py KF                     # IATA code, planner name (Kingfisher), game name or id
python3 scripts/briefing/brief.py "Malaysia Airlines" --as-of 2026-10-15T08:00:00Z --out ~/briefings
```

It prints a short briefing, about one screen, and writes the full JSON beside it, `briefing_<code>.json` (in `--out`,
else the current folder). It only gathers: each figure comes from its one home (#19), through `export_for_report()`.

| Section | What it holds | Where it comes from |
|---|---|---|
| `card` | Profit a day, per aircraft, fleet, on order, flights a day, load over 7 days, the next order and what can be ordered now; cash, the lowest point in 14 days and the payment that makes it | `airline_cards()`, `cash_forecast()` (kind `figures`) |
| `fleet` | Each aircraft flying or in service: base, type, cabin, legs a week, block hours a day, maintenance, issues (short or tight turns, position breaks, overlaps, estimated blocks, low maintenance), profit a day after its lease | The library's `aircraft` (kind `rules`); `aircraft_profit()` over 7 days |
| `routes` | Each route: load over 7 days, profit a week, its mark and why, the growth lists it's on and its load pattern | `route_loads()` (kind `briefing`), `route_profit()` over 7 days and `growth_signals()` (kind `figures`) |
| `hubs` | Hubs first and each base's busiest rival, contested or not | `hub_progress()` |
| `deliveries` | Aircraft on order, or arrived and not yet filed, each with its plan cards, their legs and each card's check at both ends, service codes included | Kind `briefing`; the library's `check-card` |
| `todos` | Open to-dos, the airline's and the group's, with their steps | Kind `briefing` |
| `fare_plan` | Fare changes planned, and whether the captures show each | `fare_plan_status()` (kind `briefing`) |
| `rivals` | From the latest finished world scan by the moment (its id, date and age): the routes it flies now and in the scan, with each rival's departures a week on the pair, and the busiest rivals at each of its airports | Kinds `snapshots` and `airlines`; passenger flights only, by the weekly report's rule (`report/analyze.py`'s market block) |
| `capture` | Its latest capture, today's pages and #21's verdict | `capture_status()` |

**Moments:** the captured figures, the fare plan and the loads are as of `--as-of` (now by default); the planning
input, the deliveries, plan cards and to-dos are the tables as they are now. `sources` in the JSON says so.

**Needs:** `~/.sb_anon`, `~/.ingest_secret` and the library's command (or `$EQUINOX_RULES_CLI`). `$EQUINOX_API_URL` points
it at another copy of the database (the rehearsal's); `--inputs <file>` reads saved inputs instead (the checks' sample).
The checks run it on a dated sample on every pull request
(`tests/briefing_test.py`), and the rehearsal runs it for every airline on last night's copy
(`tests/briefing_copy_test.py`).

## The weekly report (Saturday review chat)
Run these in order, from one working folder, straight from a clone of the repository (no need to copy them):
`python3 <clone>/scripts/report/<script>`. The planning library's command must be built first (`npm ci && npm run
build` in the clone, below). **The report's money is the database's:** cash, profit a day, flight profit a day, the
lowest point in the next 14 days and when, the next order, route profit, the growth signals and hubs first come from the
captured figures (decision #19), each airline on its own. There is no surplus figure and no group total (manual §1, §3).
Our airlines, their game IDs, names and bases come from the database too (`rules.json`); nothing about them is typed into
the scripts, and nothing assumes six airlines (#14).

| Step | Script | What it does | Needs | Makes |
|---|---|---|---|---|
| 1 | `report/pull.py` | Downloads what the report reads, through `export_for_report()`: the captured figures, now (kind `figures`), the planning library's input (kind `rules`) and the latest finished world scan (every airline with its schedule, and the scanned airports); and the website's airlines from `site_public()`, for the charts' colours | `~/.sb_anon`, `~/.ingest_secret` | `figures.json`, `rules.json`, `airlines.json`, `airports.json`, `scan.json` (which scan), `site_airlines.json` |
| 2 | `report/analyze.py` | Works out the briefing's numbers into `results.json`: each airline's money from `figures.json`; its aircraft, routes, flights, seats and block hours a day from its stored legs through the planning library (`node lib/rules/dist/cli.js aircraft rules.json`: the Tails screen's figures); competitors by market, our bases at their airports, head-to-head routes and the world ranking from the scan. Then sends the scan's market summaries (each airline's passenger departures a week and city pairs per market, kept for good in `scan_airline_markets`) through `ingest_snapshot()`, kind `markets`, for the scan in `scan.json`, using `report/scan_markets.py` beside it; if that fails it says so and the report carries on (run step 2b later). `--no-send` leaves the sending out | Step 1's files, `airports_oa.csv` (OurAirports' public airport list), the library's command (in the script's own clone, or `$EQUINOX_RULES_CLI`) | `results.json`; the scan's market summaries in the database |
| 2b | `report/scan_markets.py` | Only when needed: sends the market summaries for any scans (`python3 scan_markets.py [scan id ...]`; no ids: every finished scan whose schedules are still kept, one month). For scans stored before 11 Oct, and after a change to the market definitions | `airports_oa.csv`, `~/.sb_anon`, `~/.ingest_secret`; `analyze.py` beside it (the market definitions) | The scans' market summaries in the database |
| 3 | `report/charts.py` | Draws the charts, every name and colour from `results.json` | `results.json`, the Liberation Sans fonts | `c_profit.png`, `c_cash.png`, `c_fleet.png`, `c_markets.png`, `c_hubs.png` |
| 4 | `report/build.py` | Lays out the PDF briefing: every figure from `results.json`, the week's written text from `notes.json` | `results.json`, the charts, `notes.json` (`--notes` for another file), the Liberation Sans fonts | `~/report/Equinox_Weekly_Briefing_<year>-W<week>.pdf` (`--out` for another folder). The week is the ISO week of the figures' date, so nothing in the script changes from week to week |

**`notes.json`, the week's words.** The Saturday review writes it each week; `report/notes.example.json` shows every part,
with example text. It holds what only the review can say: the week in one line, what matters, the decisions, a headline
and notes for each section, each airline's rivals read (by its code or name), rivals' moves, risks, opportunities and the
plan (what we did, the growth rotation, what's coming up, the watch list). `build.py` lays out what's there and leaves out
any part that is missing. Never type a figure the database gives into the notes: the tables beside them print it.

The finished PDF is published to the investor library with `site_admin()` (kind `report`). The checks run steps 2 to 4
on a small dated sample on every pull request and keep the PDF (`tests/report_test.py`, `tests/README.md`).

## gander monthly (Monthly chat)

| Step | Script | What it does | Needs | Makes |
|---|---|---|---|---|
| 1 | `newsletter/nl_analyze.py` | The market numbers for the issue: biggest airlines, airports and routes, market leaders, fleets | `airlines3.json` and `airports3.json` (a world scan, pulled as in the weekly report's step 1 and renamed), `game_stats.json` (the game's own statistics pages, saved by hand), `airports_oa.csv` | `nl.json` |
| 2 | `newsletter/nl_build.py` | Lays out the issue with its map | `nl.json`, `land110.geojson` (Natural Earth's public 1:110m land outline) | `nl_map.png`, `~/report/Gander_Monthly_Issue1_Oct2026.pdf`. The issue name is written into the script. |

## The world scan

| Script | What it does | How to run | Makes |
|---|---|---|---|
| `scanner/gscan.py` | Reads every airline in Gander and its schedule, then the airport pages for our hubs and the big rival hubs. Saves them as a scan through `ingest_snapshot()`, which feeds the weekly report and gander monthly. Every airline a scan sees becomes an `airlines` row by game ID, so rivals can be placed in groups. | First start a scan: call `ingest_snapshot()` with kind `start` to get its number (`snapshot_id`). Then run `python3 gscan.py airlines <scan> [from] [to]` (in slices if needed) and `python3 gscan.py airports <scan>`, which marks the scan finished and builds its airport summaries. | Rows in `game_scans`, `game_scan_airlines` (totals, kept for good), `game_scan_schedules` and `game_scan_airports` (kept a month, then archived) and `scan_airline_airports` (each airline's departures and destinations per airport, kept for good); working files `~/ents.json`, `~/apid.json` |
| `gfetch.py` | Fetches one page from the game, keeping the session cookie. Used by the scanner, and handy on its own. | `python3 gfetch.py <url> <file>` | The page, saved to the file |

The scanner waits between pages (0.25 to 0.5 seconds) so it doesn't load the game's servers. A full scan takes a
while; run it in slices with `[from] [to]` if needed.

## The schedule optimiser (Scheduling chat)
The planning library's `optimise` command (decision #19; `scripts/planning/plan.py`, which did this before, was retired
by build pull request 4). It builds the best day's schedule for one aircraft from a base: it tries every order of the
given destinations and every start time in the window, keeps the plans that respect night bans, the second-daily gap,
turns and the maintenance the day needs, and picks the one with the most connections at the base (and any extra hubs),
then the most maintenance time. Connections count from the airport's minimum connection time to
`connection_max_wait_h` (manual §4); block times are 25 minutes + distance ÷ the type's speed, or the leg's stored time.

Its input is `rules.json`, from `export_for_report()` with kind `rules` (next section, step 2): every leg already flying,
so new connections are counted against the real network. A worked example, Malaysia's next aircraft at KUL:

```bash
node lib/rules/dist/cli.js optimise rules.json KUL KCH,PQC,PEN --type "A321 NEO LIGHT" --start 05:00-11:00 --step 5
```

It answers in JSON: `best` (the order, the local start, connections, the maintenance ratio, and each leg with its local
and UTC times and block), `plans` (the next best), and how many plans it tried and found feasible. On the 10 Oct test
sample this gives KCH, PQC, then PEN from 06:45, 70 connections at KUL and maintenance 289%, exactly what plan.py gave
(`tests/optimiser_saved_answer_test.py`). Add `--hubs DEL,PVG` to count connections at other hubs too, and `--airline
<id>` when the base serves more than one of our airlines. Check the plan card it suggests with `check-card` before it
goes into the planner.

## The planning library's command (any chat)
The planning rules (block times, turns, connections, banks, maintenance, the schedule checks, the optimiser) live in
one library, `lib/rules/` (decision #19); `lib/rules/README.md` says what each part does. Claude runs it as a command
from a clone of the repository, with Node 22:

1. Build it once: `npm ci && npm run build` (it writes `lib/rules/dist/`).
2. Get its input, everything it needs in one document, through `export_for_report()` with kind `rules` and the ingest
   secret (the third argument is the world's id; leave it empty for the default world):

   ```bash
   curl -s "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/export_for_report" \
     -H "apikey: $(cat ~/.sb_anon)" -H "Authorization: Bearer $(cat ~/.sb_anon)" -H "Content-Type: application/json" \
     -d "{\"p_secret\": \"$(cat ~/.ingest_secret)\", \"p_kind\": \"rules\", \"p_arg\": \"\"}" > rules.json
   ```

   Staff signed in get the same document from `rules_input()`; in a chat with the Supabase connection,
   `select public.rules_input();` as postgres gives it too.
3. Ask it, with `node lib/rules/dist/cli.js <command> rules.json`:
   - `block DEL BOM "A321 NEO LIGHT"`: the block time for a leg not yet timed;
   - `connections KUL`: every connection there, with its days and gaps, the city pairs linked and each one's bank;
   - `aircraft` (every aircraft's legs a week, block hours a day, maintenance and routes) or `aircraft 9M-AAB` (its week);
   - `check-card card.json`: a plan card's legs checked against every rule, at both ends, each leg's service code
     (`service_code`) against the one its route's distance calls for included;
   - `optimise KUL KCH,PQC,PEN --type "A321 NEO LIGHT" [--start 05:00-11:00] [--step 5] [--hubs DEL]`: the best day's
     schedule for one aircraft, by connections, then maintenance.

   Each answers in JSON. The weekly report runs `aircraft` (above), and the website's trip search uses the library's
   connection test from `web/assets/rules.js`, which the same build writes.

## The captured figures (any chat)
The figures worked out from what the capture recorded live in the database (decision #19, design §8): the cash
forecast and when an airline can order (manual §3), Review's cards and profit by day, route and aircraft profit, fare
changes, the growth signals and load patterns, hub progress and the capture board. Each is a function with an "as of"
moment (now by default); `docs/data.md` says what each answers. Scripts get all of them, for every airline, in one
document through `export_for_report()` with kind `figures` and the ingest secret; the third argument is a JSON object,
both keys optional: `as_of` (a moment, now when left out) and `world` (the world's id, the default world when left
out):

```bash
curl -s "https://ulecwsyedvwcxgdzmhoq.supabase.co/rest/v1/rpc/export_for_report" \
  -H "apikey: $(cat ~/.sb_anon)" -H "Authorization: Bearer $(cat ~/.sb_anon)" -H "Content-Type: application/json" \
  -d "{\"p_secret\": \"$(cat ~/.ingest_secret)\", \"p_kind\": \"figures\", \"p_arg\": \"{}\"}" > figures.json
```

It holds `airline_cards`, `growth_signals`, `hub_progress`, `capture_status`, and for each airline `cash_forecast`,
`airline_profit`, `route_profit` and `aircraft_profit` (each over 1, 3 and 7 days) and `fare_changes`. Money is in
millions of AS$, unrounded; moments are UTC. In a chat with the Supabase connection, Claude calls the functions
themselves as postgres, e.g. `select public.cash_forecast(<airline id>, '[{"type": "A321 NEO LIGHT", "count": 2}]');`
to test orders. The weekly report reads its money from them (above).

## Where the inputs come from
- **The planner's old document** is gone with the old planner (the clean-up, build pull request 14): `export_for_report()`
  refuses kind `planner`, and the `planner_state`, `planner_loads`, `planner_meta` and `planner_data` tables are dropped.
  No script read them any more (the weekly report and the optimiser moved off them in build pull request 4).
- **`rules.json`** (the planning library's command and the weekly report): `export_for_report()` with kind `rules`, which
  gives exactly what `rules_input()` gives staff: the settings, world rules, aircraft types, airports, airlines, bases,
  aircraft, routes, rotations and every flight leg, from the tables (#19).
- **`figures.json`** (the captured figures, the weekly report's money): `export_for_report()` with kind `figures` (above),
  the same figures the database functions give staff (#19).
- **`site_airlines.json`** (the weekly report's chart colours): `site_public()`'s airlines, from the airlines table.
- **`notes.json`** (the weekly report's words): written by the Saturday review each week, as `report/notes.example.json`
  shows.
- **The route research** (what `data.json` held: routes, coordinates, UTC offsets and countries) lives in the
  `countries`, `airports` and `routes` tables, which `rules.json` gives; `export_planner_data()` went with the clean-up
  (build pull request 14), and no script read it. To change it, `planner_data_set()` (key `DATA`, the research document)
  writes those tables, only the rows that change, and answers what changed; any other key is refused. A new UTC offset for an airport our flights use is held back and named: tell the
  Building chat, since those flights need re-timing (design §4).
- **Connection times:** each airport's `mct_min` in `world_airports`, which `rules.json` and `site_public()`'s
  `content.mct` both give. To change them,
  `site_admin()` with kind `content`, key `mct` and the whole map `{airport code: minutes}` (whole minutes; an airport
  left out loses its time).
- **`airports_oa.csv`:** OurAirports' public airport data (ourairports.com/data), for names, countries and
  coordinates.
- **`land110.geojson`:** Natural Earth's public 1:110m land outline, for the newsletter map.
- **`game_stats.json`:** the game's statistics pages, saved by hand. No script makes it yet.

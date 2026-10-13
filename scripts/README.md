# Scripts

The Python scripts Claude runs for the weekly report, gander monthly, the world scan and the schedule optimiser
(decision #10). They are Claude's working tools, not part of the website or planner, and they run in Claude's workspace.

**Before running any of them**, know these limits as they stand on 8 Oct 2026:
- **Fixed paths.** They read and write files in `/home/claude/` and the current folder.
- **Two key files.** `~/.sb_anon` holds the public Supabase key, which is also in the planner's code.
  `~/.ingest_secret` holds the ingest secret, taken from the `ingest_secret` table. Neither file is ever committed.
  Recreate them in a new workspace before running a script. Decision #11 keeps the ingest secret as it is.
- **Hand-made inputs.** Some inputs aren't made by any script yet. Where each one comes from is listed below.
- **To be cleaned up:** these points are for #22 (scheduled jobs). Until then, run the scripts the way this page says.

All database access goes through functions described in `docs/data.md`.

## The weekly report (Saturday review chat)
Run these in order, from one working folder.

| Step | Script | What it does | Needs | Makes |
|---|---|---|---|---|
| 1 | `report/pull.py` | Downloads the latest finished world scan (every airline and the scanned airports) and the planner, through `export_for_report()` | `~/.sb_anon`, `~/.ingest_secret` | `airlines.json`, `airports.json`, `planner.json`, `scan.json` (which scan) |
| 2 | `report/analyze.py` | Works out competitors by market, hub progress, fleet, profit and the rest of the briefing's numbers. Then sends the scan's market summaries (each airline's passenger departures a week and city pairs per market, kept for good in `scan_airline_markets`) through `ingest_snapshot()`, kind `markets`, for the scan in `scan.json`; it uses `report/scan_markets.py`, so copy both. If the sending fails it says so and the report carries on: run step 2b later | Step 1's files, `airports_oa.csv` (OurAirports' public airport list), `~/data.json` (the planner's route research, from `export_planner_data()`) | `results.json`; the scan's market summaries in the database |
| 2b | `report/scan_markets.py` | Only when needed: sends the market summaries for any scans (`python3 scan_markets.py [scan id ...]`; no ids: every finished scan whose schedules are still kept, one month). For scans stored before 11 Oct, and after a change to the market definitions | `airports_oa.csv`, `~/.sb_anon`, `~/.ingest_secret`; `analyze.py` beside it (the market definitions) | The scans' market summaries in the database |
| 3 | `report/charts.py` | Draws the charts | `results.json`, the Liberation Sans fonts | `c_fleet.png`, `c_hubs.png`, `c_markets.png`, `c_profit.png` |
| 4 | `report/build.py` | Lays out the PDF briefing | `results.json`, the charts | `~/report/Equinox_Weekly_Briefing_W41.pdf`. The week number is written into the script, so change it each week. |

The finished PDF is published to the investor library with `site_admin()` (kind `report`).

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

| Script | What it does | Needs | Makes |
|---|---|---|---|
| `planning/plan.py` | Builds a day's schedule for an aircraft. It tries every order of the given destinations and every start time, and keeps the plan that makes the most connections at the hub. Connections count from the airport's minimum connection time, with no extra margin, up to 8 hours (manual §4). It respects night bans, the maintenance time the day needs, and keeps a second daily at least 3 hours from the first. Block times are fitted to 468 of our flights on 7 Oct: exact to the minute for about 93%, never more than 2 minutes out. | `~/real_state.json` (the planner's state), `~/data.json` (route research), `~/.sb_anon` (it reads minimum connection times from `site_public()`) | Printed plans: connections, hours a day, maintenance share and each leg's times |

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
   - `check-card card.json`: a plan card's legs checked against every rule, at both ends;
   - `optimise KUL KCH,PQC,PEN --type "A321 NEO LIGHT" [--start 05:00-11:00] [--step 5] [--hubs DEL]`: the best day's
     schedule for one aircraft, by connections, then maintenance.

   Each answers in JSON. Until pull request 4 moves the scripts onto it, `planning/plan.py` stays as it is; the library's
   optimiser gives the same plan on the same input (`tests/rules_planpy_test.py`).

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
to test orders. The weekly report moves onto these figures in pull request 4; until then its scripts are unchanged.

## Where the inputs come from
- **`planner.json`, `real_state.json`:** the planner's state, from `export_for_report('planner')`, which builds it from
  the planner tables (#13, pull request 8). Don't read the `planner_state` row directly: it has been frozen since the
  switch-over (pull request 9) and no longer changes.
- **`rules.json`** (the planning library's command): `export_for_report()` with kind `rules`, which gives exactly what
  `rules_input()` gives staff: the settings, world rules, aircraft types, airports, airlines, bases, aircraft, routes,
  rotations and every flight leg, from the tables (#19).
- **`figures.json`** (the captured figures): `export_for_report()` with kind `figures` (above), the same figures the
  database functions give staff (#19).
- **`data.json`:** the planner's route research, from `export_planner_data()`. To change it, `planner_data_set()` (key
  `DATA`) writes it to `planner_data` and to the `countries`, `airports` and `routes` tables, only the rows that
  change, and answers what changed. A new UTC offset for an airport our flights use is held back and named: tell the
  Building chat, since those flights need re-timing (design §4).
- **Connection times** (`plan.py`): `site_public()`'s `content.mct`, which comes from `world_airports`. To change them,
  `site_admin()` with kind `content`, key `mct` and the whole map `{airport code: minutes}` (whole minutes; an airport
  left out loses its time).
- **`airports_oa.csv`:** OurAirports' public airport data (ourairports.com/data), for names, countries and
  coordinates.
- **`land110.geojson`:** Natural Earth's public 1:110m land outline, for the newsletter map.
- **`game_stats.json`:** the game's statistics pages, saved by hand. No script makes it yet.

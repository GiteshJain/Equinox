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
| 1 | `report/pull.py` | Downloads the latest finished world scan (every airline and the scanned airports) and the planner, through `export_for_report()` | `~/.sb_anon`, `~/.ingest_secret` | `airlines.json`, `airports.json`, `planner.json` |
| 2 | `report/analyze.py` | Works out competitors by market, hub progress, fleet, profit and the rest of the briefing's numbers | Step 1's files, `airports_oa.csv` (OurAirports' public airport list), `~/data.json` (the planner's route research, from `export_planner_data()`) | `results.json` |
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
| `scanner/gscan.py` | Reads every airline in Gander and its schedule, then the airport pages for our hubs and the big rival hubs. Saves them as a snapshot through `ingest_snapshot()`, which feeds the weekly report and gander monthly. | First start a snapshot: call `ingest_snapshot()` with kind `start` to get its number. Then run `python3 gscan.py airlines <snapshot> [from] [to]` (in slices if needed) and `python3 gscan.py airports <snapshot>`, which marks the snapshot finished. | Rows in `game_snapshots`, `game_snapshot_airlines`, `game_snapshot_airports`; working files `~/ents.json`, `~/apid.json` |
| `gfetch.py` | Fetches one page from the game, keeping the session cookie. Used by the scanner, and handy on its own. | `python3 gfetch.py <url> <file>` | The page, saved to the file |

The scanner waits between pages (0.25 to 0.5 seconds) so it doesn't load the game's servers. A full scan takes a
while; run it in slices with `[from] [to]` if needed.

## The schedule optimiser (Scheduling chat)

| Script | What it does | Needs | Makes |
|---|---|---|---|
| `planning/plan.py` | Builds a day's schedule for an aircraft. It tries every order of the given destinations and every start time, and keeps the plan that makes the most connections at the hub. Connections count from the airport's minimum connection time plus 10 minutes, up to 8 hours. It respects night bans, the maintenance time the day needs, and keeps a second daily at least 3 hours from the first. Block times are fitted to 468 of our flights on 7 Oct: exact to the minute for about 93%, never more than 2 minutes out. | `~/real_state.json` (the planner's state), `~/data.json` (route research), `~/.sb_anon` (it reads minimum connection times from `site_public()`) | Printed plans: connections, hours a day, maintenance share and each leg's times |

## Where the inputs come from
- **`planner.json`, `real_state.json`:** the planner's state, from `export_for_report('planner')` or from Supabase
  (`planner_state`).
- **`data.json`:** the planner's route research, from `export_planner_data()`.
- **`airports_oa.csv`:** OurAirports' public airport data (ourairports.com/data), for names, countries and
  coordinates.
- **`land110.geojson`:** Natural Earth's public 1:110m land outline, for the newsletter map.
- **`game_stats.json`:** the game's statistics pages, saved by hand. No script makes it yet.

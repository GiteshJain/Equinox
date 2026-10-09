# How equinox. fits together

The map of the whole system: what each part is, where it lives, what runs when, where keys are kept, and what to do when
something breaks. Decision #10. The rules are in `docs/operating-manual.md`, the reasons in `docs/decisions.md`,
the tables in `docs/data.md`.

```mermaid
flowchart LR
  subgraph Game["AirlineSim, Gander world"]
    G[Six airlines' pages]
  end
  subgraph Gitesh["Gitesh's browser"]
    C["Capture all airlines<br/>(userscript, each evening)"]
  end
  subgraph Supabase["Supabase: database, sign-in, files"]
    I["capture_ingest()"] --> R[(game_capture_raw)] --> P["parse_capture()"] --> T[("game_* tables<br/>statement, loads, events,<br/>balance, income statement")]
    PS[(planner_state<br/>planner_loads<br/>planner_data)]
    S[(site_content<br/>site_posts<br/>site_reports)]
    F["site_public() and<br/>other functions"]
    B[[site-photos bucket]]
  end
  subgraph Cloudflare["Cloudflare Pages: equinox-alliance.com"]
    W[Website]
    PL["Planner /planner/<br/>(staff sign-in)"]
    GS["/api/game-schedule"]
  end
  subgraph GitHub
    E["Equinox repository<br/>code, docs, checks"]
    BK["equinox-backups (private)<br/>the backup job;<br/>monthly release copies"]
  end
  subgraph R2["Cloudflare R2: equinox-backups bucket"]
    RB[("nightly copies, 30 days<br/>monthly copies, for good")]
  end
  G --> C --> I
  T --> PL
  PS <--> PL
  PS --> F
  S --> F --> W
  B --> W
  GS --> G
  PL --> GS
  E -- "merge publishes" --> Cloudflare
  Supabase -- "nightly copy" --> BK
  BK -- "upload (writer key)" --> RB
  RB -- "last night's copy (reader key)" --> E
```

## The parts

| Part | What it is | Where |
|---|---|---|
| **Website** | The public airline site: home, flights, destinations, live network, our airlines, newsroom, investors, gander monthly. A single page that reads everything from `site_public()`. | `web/index.html`, `web/assets/`; served by Cloudflare Pages at equinox-alliance.com |
| **Planner** | The staff tool: routes, aircraft, hubs, the nightly capture's numbers, the cash forecast, to-dos. One HTML file. It keeps its own state in one database row (`planner_state`), saved 0.3 seconds after every change. Previews are look-only (#8). | `web/planner/index.html`, at equinox-alliance.com/planner/ |
| **Schedule check** | Reads an airline's public schedule from the game and returns it as JSON; the planner's Check screen compares it with the plan. | `functions/api/game-schedule.js`, a Cloudflare Pages Function at `/api/game-schedule` |
| **Database** | Supabase project `ulecwsyedvwcxgdzmhoq` (free plan): 22 tables, 2 views, 23 functions, staff sign-in, and the `site-photos` file bucket. | supabase.com; tables in `docs/data.md`; every change in `database/migrations/` |
| **Capture** | A userscript in Gitesh's browser. One button captures each airline's events, bank statement (last 3 days), income statement, balance sheet and loads, sends them to `capture_ingest()`, then sets every salary to 10% above the country average. | `capture/capture_all.user.js` (the key is a placeholder in the repository) |
| **Scripts** | Python scripts Claude runs for the weekly report, gander monthly, the world scan and the schedule optimiser. | `scripts/`, how to run them in `scripts/README.md` |
| **Repository** | All code, database changes, tests and documents. Every change is a pull request that Gitesh approves with "merge" (#2). | GitHub `GiteshJain/Equinox` |
| **Backups** | A nightly copy of the database and files, restored each night to prove it works (#6), then uploaded to Cloudflare R2 (#16). Each night's copy is kept 30 days. The month's first is kept for good, in R2 and as a file on a GitHub release. Copies no longer go into git (since 9 Oct). | The job: GitHub `GiteshJain/equinox-backups` (private). The copies: R2 bucket `equinox-backups` (`nightly/`, `monthly/`, `latest.json`), and releases `backup-<YYYY-MM>` in `equinox-backups` |
| **Checks** | On every pull request: no keys, the schedule check, every planner screen and its key numbers, every website page (#9). The database rehearsal runs when the database or the planner changes (#8): it restores last night's copy from R2 into a full local Supabase on GitHub's runner (database, data API and sign-in), tries the database changes, then lets the pull request's own planner sign in as a test staff user and save into the copy for real, and reads the tables back (#17). | `.github/workflows/`, `tests/`, `database/rehearse.sh`, `database/backup/` |
| **Claude** | The Equinox project in Claude: four chats (Scheduling, Saturday review, Monthly, Building), the manual and decisions in the project files, and a Supabase connection. Big builds go to a helper with a fresh memory, which starts from `CLAUDE.md` (#26). | claude.ai |

## How data moves
1. **Each evening** Gitesh presses *Capture all airlines* in the game. For each airline, `capture_ingest()` checks the
   capture key, keeps the raw page for 14 days (`game_capture_raw`) and `parse_capture()` turns it into rows:
   - the bank statement goes to `game_statement`, which the views `game_flight_pnl` (profit per flight) and
     `game_ops_recent` (the last 24 hours) are built on;
   - payments ahead go to `game_events`;
   - the balance sheet goes to `game_balance` (account 2800 is cash);
   - the income statement goes to `game_pnl`;
   - loads go to `game_loads`, and are copied into the planner's month documents (`planner_loads`). The
     planner's own load saves go through `save_loads()`, which merges only the days it changed.
2. **The planner** reads those tables when a staff member signs in. Route profit, the 14-day cash forecast, growth
   signals and the daily load report are all calculated in the browser. Plans and to-dos are saved back to
   `planner_state`.
3. **The website** calls `site_public()`, which builds everything public from `planner_state` (hubs, schedules),
   `site_content` (photos, logos, markets), `site_posts` and `site_reports`. Investor pages and reports need the
   password (`site_investor()`, `site_report()`).
4. **Claude's scripts** read through the `export_*` functions and write through `ingest_snapshot()`, `site_admin()` and
   `planner_data_set()`, using the ingest secret (kept as it is by #11).
5. **Every night** the backup copies the database (except the key tables and sign-in data) and the photo files,
   restores the copy, uploads it to Cloudflare R2 and records the result in `backup_runs`, which the planner shows.
   `latest.json` in R2 names the newest copy; the database rehearsal reads it to find last night's copy.

## What runs when

| When | What | Where to see it |
|---|---|---|
| Each evening, Chicago time | Gitesh's capture, all six airlines in one press | Planner → Check → Capture |
| 07:17 UTC daily (about 02:17 in Chicago; GitHub can start it hours late, as on 9 Oct at 14:20 UTC) | Nightly backup, restore check and upload to R2 (the month's first copy is also kept in `monthly/` and on a GitHub release) | Planner Home (backup line); `backup_runs` |
| Every pull request | Checks; database rehearsal, with real saves, if the database or the planner changes; a Cloudflare preview | Comments and checks on the pull request |
| Every merge to `main` | Cloudflare publishes the site and planner; the checks run again on `main` | equinox-alliance.com |
| Saturdays | Weekly report and review (Saturday review chat) | The investor library on the website |
| First Saturday of the month | Monthly report, gander monthly, monthly strategy (Monthly chat) | The investor library; gander monthly page |

## Where keys are kept (names only, never the keys)

| Key | Lives in | Used by |
|---|---|---|
| Supabase public (anon) key | In the website and planner code. It's public by design, and access is controlled by the database's rules. | Everything that talks to the database |
| Capture key | Gitesh's copy of the userscript; only its hash is in `capture_keys` | The capture |
| Ingest secret | `ingest_secret` table; Claude's scripts read it from a file in Claude's workspace (`~/.ingest_secret`) | Claude's scripts (#11 kept it as it is) |
| Investor password | Its hash is in `report_access` | Investor page and reports |
| `SUPABASE_DB_URL` | GitHub secret on `equinox-backups` | The nightly backup |
| R2 writer key: `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` (Object Read & Write, the `equinox-backups` bucket only) | GitHub secrets on `equinox-backups` | The nightly backup uploads its copy to R2 |
| R2 reader key: `R2_ENDPOINT`, `R2_READ_ACCESS_KEY_ID`, `R2_READ_SECRET_ACCESS_KEY` (Object Read only, the `equinox-backups` bucket only) | GitHub secrets on `Equinox` | The database rehearsal reads last night's copy; also used to get a copy for a test sample (`tests/README.md`) |
| Your password | Supabase sign-in (not in any table or backup). Sign-ups are off (#11), so yours is the only account | The planner |
| The rehearsal's local keys and test users | Made on GitHub's runner for the local copy each run, never printed, thrown away when the run ends | The real-saves test (#17) |

## When something breaks

| What | What to do |
|---|---|
| A change broke the site or planner | Revert its pull request on GitHub. Cloudflare republishes the previous version within a couple of minutes. |
| The site is down | Check Cloudflare's dashboard (Workers & Pages → equinox-alliance). The last good deployment can be rolled back there. |
| A capture failed for an airline | Press the capture again. If the game won't cooperate, enter cash and loads in Planner → Review → Manual entry. |
| The planner's data was overwritten or damaged | Restore `planner_state` from last night's copy (the README in `equinox-backups` has the steps). The planner warns if there's no good copy in the last 30 hours. |
| The whole database is lost | Restore everything from a copy into a new Supabase project (the README in `equinox-backups` has the steps), then re-issue the keys, which are never backed up. The copies are in R2; if R2 can't be reached, use the month's GitHub release in `equinox-backups`. |
| A key leaked | Issue a new one and replace it where it lives (table above). For the capture key, also update Gitesh's userscript. |
| A check is red | Don't merge. The pull request's comment says which check and why. |
| The rehearsal can't get last night's copy | Its comment on the pull request says why: the R2 reader key isn't set up, there's no `latest.json`, or the copy doesn't match its SHA-256. Check the backup line on planner Home, fix the cause, then re-run the check. |
| Claude's workspace was reset | Nothing is lost: everything is in GitHub. A new session clones the repository. |

# Unattended capture

One part of the map, `docs/architecture.md`, in full. The map has the short version; a build that changes this part adds its dated note here, not in the map.

## What it is

The same capture, run twice a day without Gitesh's laptop (since 10 Nov, to-do 203; spec `docs/specs/2026-11-10-unattended-capture.md`, briefs `docs/briefs/2026-11-10-unattended-capture.md` and `docs/briefs/2026-11-10-unattended-capture-scope.md`).

**Built in two pull requests: the database's part and the planner's are in; the GitHub job comes with the second**, and until it's built, and until Gitesh has put the token in the vault, each start writes a failed row and nothing posts (manual *Decided, not yet built*: Gitesh's own press stays the only capture until then).

**The key:** its own capture key, marked `capture_keys.unattended`, issued by Gitesh with `private.capture_key_issue()` in Supabase's SQL editor (only its hash is kept). For that key `capture_airlines()` follows three world settings: `unattended_salaries` (false: it answers `salary_above_average_pct` null, so salaries stay with Gitesh's press), `unattended_scan` and `unattended_market` (true: the world scan and the market pages when they're due, exactly as for his press; false: not due); and it says `unattended: true`. The fares calls (`capture_fare_actions()`, `capture_fare_actions_by_airline()`) and the aircraft evaluation's (`capture_eval_runs()`, `capture_eval_result()`) refuse it as a wrong key, and `capture_scan()` and `capture_market()` while their setting is false.

**The start:** `private.capture_dispatch()` (`pg_cron` `equinox-capture-dispatch`, 09:30 and 21:30 UTC) asks GitHub to run `capture.yml` in `equinox-backups` (`POST /repos/GiteshJain/equinox-backups/actions/workflows/capture.yml/dispatches`, `{"ref": "main"}`, through `pg_net`) with the vault's `github_dispatch_token`. It posts only from the live project: with no token in the vault it writes a failed row, and unless the vault's `project_url` is this project's address (`https://ulecwsyedvwcxgdzmhoq.supabase.co`, written in the function) it writes a failed row "not the live project"; a restored copy has an empty vault (the backup dumps only `public` and `storage` data), so the rehearsal's copy never posts. When a capture page arrived in the last 20 minutes, or a world scan is open within the hour, it writes an ok row "skipped: a capture is running". GitHub's answer is noted on the start's row ten minutes later (`private.capture_dispatch_answer()`, `equinox-capture-dispatch-answer`, 09:40 and 21:40 UTC; `pg_net` keeps an answer only 6 hours): 204 stays ok, anything else makes the row failed with the status and the first 200 characters.

**Its record:** `job_runs`, `capture_dispatch` (each start) and `capture_unattended` (each run, written by the job).

**On the planner:** Today warns "Unattended capture: last good run 15 hours ago" when the last good run is over `settings.capture_unattended_warn_h` (14) hours old, in the Capture group (nothing before the first good run), and lists a failed run with the nightly jobs (a failed start only once it has run well); the Systems board has its line (`system_status()`'s `unattended`): its last run, ok or failed with the note, and its last good run, green under 14 hours, amber to 26, red beyond or when the last run failed.

**The job** (second pull request): signs in to the game in a hidden browser, loads the capture script with the unattended key, presses Capture all airlines, checks every airline came in all good and writes its row, failing (and so emailing Gitesh) when not.

## Where

Database: migration `20261110040000_unattended_capture.sql`; planner: Today (`app/planner/src/screens/today/attention.ts`) and Systems (`app/planner/src/screens/systems/systems.ts`); the job: GitHub `GiteshJain/equinox-backups` (second pull request)

# Spec: the unattended capture

Part 2 of to-do 203 (decided by Gitesh, 10 Nov, in the Audit chat: brief `docs/briefs/2026-11-10-unattended-capture.md`,
option C; manual *Decided, not yet built*). Part 1, the whole statement in parts, is live (#144). Read `CLAUDE.md`, the
map, manual §1 and §7, the brief and the capture's own header in `capture/capture_all.user.js` first.

## What it does, in one paragraph
Every 6 hours the database's scheduler asks GitHub to start a job in `equinox-backups`. The job signs in to the game in
a hidden browser, loads the capture script with its own key, presses **Capture all airlines** and waits for it to
finish. For that key the database answers "no salaries, no world scan, no market pages", so a run reads only our six
airlines' pages and fleets: about 140 pages, about 3 minutes. The job then asks the database whether every airline came
in "all good", writes one `job_runs` row, and fails if not, so GitHub emails Gitesh. Gitesh's own evening press is
unchanged and stays the only one that scans the world, reads the market pages and sets salaries.

## 1. The database (one migration)
- **`capture_keys.unattended`** (boolean, not null, default false; described). The current key stays false.
- **`private.capture_key_issue(p_world bigint, p_label text, p_unattended boolean)`**: makes a new random key (32 bytes,
  hex), stores only its hash the way `private.capture_key_world()` checks it, and answers the key once. No grants: only
  the owner can call it, so **Gitesh runs it in Supabase's SQL editor** and the key never passes through a chat.
- **`private.capture_key_unattended(p_key)`**: whether a key is an unattended one (false for an unknown key).
- **`capture_airlines()`** with an unattended key answers `salary_above_average_pct` null (the script already leaves
  salaries alone then), the scan not due and the market pages not due, whatever the settings say. A normal key answers
  as now.
- **Refused for an unattended key**, as a wrong key is now: `capture_scan()`, `capture_market()`,
  `capture_fare_actions()`, `capture_fare_actions_by_airline()`, `capture_eval_runs()`, `capture_eval_result()`. Fares
  and the world are never changed or scanned on a schedule (manual §5, §7).
- **The dispatch:** `pg_net` switched on. `private.capture_dispatch()` posts to GitHub's
  `POST /repos/GiteshJain/equinox-backups/actions/workflows/capture.yml/dispatches` (`{"ref": "main"}`) with the token
  read from the vault (`vault.decrypted_secrets`, name `github_dispatch_token`). With no token in the vault it writes a
  failed `job_runs` row ("no GitHub token in the vault") and posts nothing. It writes one `job_runs` row (job
  `capture_dispatch`, ok when the post was queued, with pg_net's request id). The answer from GitHub is read by the next
  dispatch from `net._http_response` and noted on its row (a 204 is ok; anything else makes that row failed, with the
  status and the first 200 characters of the answer).
- **Skip when Gitesh is capturing:** the dispatch posts nothing, and writes an ok row "skipped: a capture is running",
  when any capture page arrived in the last 20 minutes.
- **The schedule:** `pg_cron` job `equinox-capture-dispatch` at **03:30, 09:30, 15:30 and 21:30 UTC** (09:00, 15:00,
  21:00 and 03:00 in India). The 09:30 run completes the capture day before the 10:00 UTC snapshot fallback. Added to
  `private.schedule_jobs()`, so a restored copy schedules it too. **The rehearsal's copy never posts:** the dispatch
  posts nothing outside the live project (no token in a copy's vault, and it checks the project's address too).
- Every new table column and function described; `database/current/` updated.

## 2. The job (in `equinox-backups`, the private repository)
- `.github/workflows/capture.yml`: `workflow_dispatch`, plus GitHub's own timer once a day at 12:45 UTC as a backstop in
  case the database's scheduler stops (GitHub's timer can start hours late, which doesn't matter for a backstop, and an
  extra capture does no harm). `concurrency: capture` so two runs never overlap. Timeout 20 minutes.
- **Secrets** (Gitesh adds them; never printed): `GAME_USERNAME`, `GAME_PASSWORD`, `CAPTURE_KEY_UNATTENDED`; the
  database's address is already there (`SUPABASE_DB_URL`).
- **The script** (`capture/run.mjs`, Playwright on the runner's Chromium, Node 22):
  1. Takes `capture/capture_all.user.js` from the `Equinox` repository at `main` (public; a plain download of the raw
     file), puts the key in place of `__CAPTURE_KEY__`, and checks its `@version` is 1.16 or later.
  2. Signs in to the game the way the sign-in page's form posts (built and tested against the page Gitesh saves, below;
     never a made-up page). Stops with "sign-in failed" (and the page's title, nothing else) if the dashboard doesn't
     open.
  3. Injects the script on every page of `gander.airlinesim.aero` as the Userscripts app does (after the page loads),
     opens the dashboard and clicks `#eq-cap-btn`.
  4. Waits for the panel's "Done:" line, or a line that the capture stopped, up to 15 minutes.
  5. Asks the database (`capture_status()`, as the database URL's role) for each active airline's latest capture: ok
     only when every one has all its pages since the run started and its verdict is "all good".
  6. Writes one `job_runs` row: job `capture_unattended`, ok or failed, the note "6 airlines all good in 3 min 12 s" or
     which airline came in short or broken and why (the verdict's words); exits non-zero when failed.
  7. Prints only those words: no page content, no cookies, no game figures.
- **Signs out at the end**, in case the game keeps one session per account.

## 3. The planner
- **Today's needs attention:** "Unattended capture: last good run 9 hours ago" when the latest ok `capture_unattended`
  row is more than **8 hours** old (`settings.capture_unattended_warn_h`, 8; described), and the existing failed-job
  item when its last run failed. Not shown before the first ok run (so nothing nags while it's being set up).
- **The Systems board:** a line for the unattended capture: its last run, ok or failed with the note, green under
  8 hours, amber to 14, red beyond, from `system_status()` (its new `unattended` part).
- No other screen changes.

## 4. Documents
- Manual §7: "Every evening" becomes: Gitesh's evening press (the world scan, the market pages, the salaries) plus the
  unattended capture every 6 hours (our airlines' pages and fleets only); the *Decided, not yet built* entry goes. Rule
  history with why.
- The map: the parts table (a new **Unattended capture** row), What runs when (four rows), Where keys are kept (the
  unattended key, the two game secrets, the GitHub token in the vault), When something breaks (a failed or missing
  unattended run: GitHub's email, Today, the Systems board; how to rotate the key or the token).
- `equinox-backups`' README: the job, its secrets, and how to run it by hand (Actions → capture → Run workflow).
- `decisions.md` #21 and #22: built, with the date.

## 5. What the checks should show
- *Database rehearsal:* a new `database/tests/unattended_capture_test.sql`: `capture_key_issue()` makes a key that
  `capture_key_world()` accepts and that isn't callable by anon or authenticated; with an unattended key
  `capture_airlines()` answers no salaries, scan or market and every refused function refuses it, while the normal key
  is unchanged; the dispatch on the copy posts nothing and writes its row; `schedule_jobs()` lists the new job at the
  four times. The planner's screen test: Today and Systems with an old ok row, a failed row and no row.
- *equinox-backups:* the run script's sign-in and result logic tested against the saved sign-in page and a stand-in for
  the game, as the aircraft evaluation script's tests do; no real sign-in in the checks.

## 6. Built in two pull requests
1. `Equinox`: the migration, the planner and the documents. Merged and applied first (nothing posts until the token is
   in the vault).
2. `equinox-backups`: the job and its script.

## 7. Gitesh's steps, one at a time, when asked
1. **Before the build:** save the game's sign-in page (Safari → File → Save As → Page Source) and attach it here.
2. After the merges: run `select private.capture_key_issue(1, 'unattended (GitHub)', true);` in the SQL editor and add
   the answer as the `CAPTURE_KEY_UNATTENDED` secret in `equinox-backups`, then `GAME_USERNAME` and `GAME_PASSWORD`.
3. Make a fine-grained GitHub token with only *Actions: read and write* on `equinox-backups`, and add it to the vault in
   Supabase (Project settings → Vault, name `github_dispatch_token`).
4. Run the job once by hand while watching, then check three things: the run is green; the game hasn't signed you out
   in Safari; Safari still has the airline you left open.

Then the four runs a day start on their own.

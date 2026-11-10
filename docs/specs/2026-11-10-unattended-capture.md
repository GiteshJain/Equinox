# Spec: the unattended capture

Part 2 of to-do 203 (decided by Gitesh, 10 Nov, in the Audit chat: brief `docs/briefs/2026-11-10-unattended-capture.md`,
option C; amended the same evening in the Building chat, brief `docs/briefs/2026-11-10-unattended-capture-scope.md`,
option B: twice a day, with the world scan and the market pages; manual *Decided, not yet built*). Part 1, the whole statement in parts, is live (#144). Read `CLAUDE.md`, the
map, manual §1 and §7, the brief and the capture's own header in `capture/capture_all.user.js` first.

## What it does, in one paragraph
Twice a day the database's scheduler asks GitHub to start a job in `equinox-backups`. The job signs in to the game in a
hidden browser, loads the capture script with its own key, presses **Capture all airlines** and waits for it to finish.
For that key the database answers "no salaries" (a setting), so a run reads our six airlines' pages and fleets (about
140 pages, about 3 minutes), then the world scan when one is due (once a capture day, about 8 minutes more) and the
market pages when they're due (once a week, 10 to 15 minutes more), exactly as Gitesh's press does. The job then asks
the database whether every airline came in "all good", writes one `job_runs` row, and fails if not, so GitHub emails
Gitesh. Gitesh's own press is unchanged; whichever capture comes first after the scan or the market pages fall due does
them, and his press is the only one that sets salaries.

## 1. The database (one migration)
- **`capture_keys.unattended`** (boolean, not null, default false; described). The current key stays false.
- **`private.capture_key_issue(p_world bigint, p_label text, p_unattended boolean)`**: makes a new random key (32 bytes,
  hex), stores only its hash the way `private.capture_key_world()` checks it, and answers the key once. No grants: only
  the owner can call it, so **Gitesh runs it in Supabase's SQL editor** and the key never passes through a chat.
- **`private.capture_key_unattended(p_key)`**: whether a key is an unattended one (false for an unknown key).
- **What an unattended key may do is three settings** (world rows, described): `unattended_salaries` (false),
  `unattended_scan` (true) and `unattended_market` (true). With an unattended key `capture_airlines()` answers
  `salary_above_average_pct` null when `unattended_salaries` is false (the script already leaves salaries alone then),
  the scan not due when `unattended_scan` is false and the market pages not due when `unattended_market` is false;
  otherwise as for a normal key. A normal key answers as now. Moving salaries to the job later is a data change.
- **Refused for an unattended key**, as a wrong key is now: `capture_fare_actions()`,
  `capture_fare_actions_by_airline()`, `capture_eval_runs()`, `capture_eval_result()` (fares are never changed on a
  schedule, manual §5), and `capture_scan()` or `capture_market()` while its setting is false.
- **The dispatch:** `pg_net` switched on. `private.capture_dispatch()` posts to GitHub's
  `POST /repos/GiteshJain/equinox-backups/actions/workflows/capture.yml/dispatches` (`{"ref": "main"}`) with the token
  read from the vault (`vault.decrypted_secrets`, name `github_dispatch_token`). With no token in the vault it writes a
  failed `job_runs` row ("no GitHub token in the vault") and posts nothing. It writes one `job_runs` row (job
  `capture_dispatch`, ok when the post was queued, with pg_net's request id). The answer from GitHub is read by the next
  dispatch from `net._http_response` and noted on its row (a 204 is ok; anything else makes that row failed, with the
  status and the first 200 characters of the answer).
- **Skip when Gitesh is capturing:** the dispatch posts nothing, and writes an ok row "skipped: a capture is running",
  when any capture page arrived in the last 20 minutes.
- **The schedule:** `pg_cron` job `equinox-capture-dispatch` at **09:30 and 21:30 UTC** (15:00 and 03:00 in India).
  The 09:30 run completes the capture day before the 10:00 UTC snapshot fallback. The game keeps 24 hours, so one
  failed run still leaves 12 hours to capture again. Added to
  `private.schedule_jobs()`, so a restored copy schedules it too. **The rehearsal's copy never posts:** the dispatch
  posts nothing outside the live project (no token in a copy's vault, and it checks the project's address too).
- Every new table column and function described; `database/current/` updated.

## 2. The job (in `equinox-backups`, the private repository)
- `.github/workflows/capture.yml`: `workflow_dispatch`, plus GitHub's own timer once a day at 12:45 UTC as a backstop in
  case the database's scheduler stops (GitHub's timer can start hours late, which doesn't matter for a backstop, and an
  extra capture does no harm). `concurrency: capture` so two runs never overlap. Timeout 45 minutes (a market evening
  with the scan is about 25).
- **Secrets** (Gitesh adds them; never printed): `GAME_USERNAME`, `GAME_PASSWORD`, `CAPTURE_KEY_UNATTENDED`; the
  database's address is already there (`SUPABASE_DB_URL`).
- **The script** (`capture/run.mjs`, Playwright on the runner's Chromium, Node 22):
  1. Takes `capture/capture_all.user.js` from the `Equinox` repository at `main` (public; a plain download of the raw
     file), puts the key in place of `__CAPTURE_KEY__`, and checks its `@version` is 1.16 or later.
  2. Signs in through the real sign-in page, as a person does: opens `https://airlinesim.aero/auth/login`, fills the
     form and clicks **Log in**; the site then shows **Game worlds**, a grid of cards (Gitesh's screenshot, 10 Nov):
     each card has a label, the world's name as its heading, and one button with a note under it. Gander's card is
     EXCLUSIVE, "Activated", button **Play**, note "no credits are charged"; others say "Play for 4 credits/day" or
     "Play for free", which can spend credits or join a world. The job clicks only the button whose text is exactly
     "Play" in the card whose heading is exactly "Gander", and refuses (stopping with "sign-in: Gander's Play button
     not found as expected") when that button mentions credits or the card's note doesn't say "no credits are
     charged". It never clicks anything else on that page. Then it waits for `https://gander.airlinesim.aero` and
     opens `/app/enterprise/dashboard`. The page is behind sign-in, so the tests use a stand-in with decoy cards, and
     the first watched run proves it. Stops with
     "sign-in failed" (and the page's title, nothing else) if the dashboard doesn't open. What the page is (read in the
     built-in browser on 10 Nov, signed out; Safari's Page Source holds only the site's shell, as the form is drawn by
     JavaScript): one form, `method="POST"` with no action, fields `login` (text, "Email Address"), `password`,
     `persistent` (checkbox, "keep me logged in": left unticked) and a submit button "Log in". The page's script posts
     `{login, password, persistent, method: "password", brand, metadata}` as JSON to
     `https://sar.simulogics.games/api/sessions` and keeps the session in the cookie `as-sid`; signing out is
     `DELETE /api/sessions/<its id>`, the one session only. Fill and click; don't call the API directly, so a change in
     its body doesn't break the job. The same API has a `confirm_code` method (an emailed code): Gitesh checked on
     10 Nov that his sign-in asks for none, and a page asking for one stops the run with "sign-in asks for a code".
     The tests use this form as `tests/fixtures/game_login_form_2026-11-10.html` (the form's own markup, as read).
  3. Injects the script on every page of `gander.airlinesim.aero` as the Userscripts app does (after the page loads),
     opens the dashboard and clicks `#eq-cap-btn`.
  4. Waits for the capture's last line, up to 40 minutes: "Done:" on an evening with nothing more, else the scan's and
     the market pages' own last lines (read from the script, not guessed), or any line that says it stopped. The
     script's page loads (each airline switch is one) carry on from `sessionStorage`, as in Safari.
  5. Asks the database (`capture_status()`, as the database URL's role) for each active airline's latest capture: ok
     only when every one has all its pages since the run started and its verdict is "all good". When the run read a
     scan or market pages, it also checks that the scan or market run it started finished (`system_status()`); one
     that didn't makes the run failed, with the capture's own reason.
  6. Writes one `job_runs` row: job `capture_unattended`, ok or failed, the note "6 airlines all good · world scan done ·
     12 min 40 s" or which airline, scan or market run came in short, broken or unfinished and why (the database's
     words); exits non-zero when failed.
  7. Prints only those words: no page content, no cookies, no game figures.
- **Signs out at the end** (the site's own log out, which deletes this session only), so no session is left on GitHub's
  machine. Each sign-in is a session of its own with its own id, so the job's shouldn't sign Gitesh out; the first
  watched run checks it.

## 3. The planner
- **Today's needs attention:** "Unattended capture: last good run 15 hours ago" when the latest ok `capture_unattended`
  row is more than **14 hours** old (`settings.capture_unattended_warn_h`, 14; described), and the existing failed-job
  item when its last run failed. Not shown before the first ok run (so nothing nags while it's being set up).
- **The Systems board:** a line for the unattended capture: its last run, ok or failed with the note, green under
  14 hours, amber to 26, red beyond, from `system_status()` (its new `unattended` part).
- No other screen changes.

## 4. Documents
- Manual §7: "Every evening" becomes: the unattended capture twice a day (our airlines' pages and fleets, and the world
  scan and market pages when due), plus Gitesh's own press, which also sets salaries; the *Decided, not yet built*
  entry goes. Rule history with why.
- The map: the parts table (a new **Unattended capture** row), What runs when (its two runs), Where keys are kept (the
  unattended key, the two game secrets, the GitHub token in the vault), When something breaks (a failed or missing
  unattended run: GitHub's email, Today, the Systems board; how to rotate the key or the token).
- `equinox-backups`' README: the job, its secrets, and how to run it by hand (Actions → capture → Run workflow).
- `decisions.md` #21 and #22: built, with the date.

## 5. What the checks should show
- *Database rehearsal:* a new `database/tests/unattended_capture_test.sql`: `capture_key_issue()` makes a key that
  `capture_key_world()` accepts and that isn't callable by anon or authenticated; with an unattended key
  `capture_airlines()` follows each of the three settings (no salaries; scan and market as for a normal key, and not
  due when switched off) and every refused function refuses it, while the normal key is unchanged; the dispatch on the
  copy posts nothing and writes its row; `schedule_jobs()` lists the new job at the two times. The planner's screen test: Today and Systems with an old ok row, a failed row and no row.
- *equinox-backups:* the run script's sign-in and result logic tested against the saved sign-in page and a stand-in for
  the game, as the aircraft evaluation script's tests do; no real sign-in in the checks.

## 6. Built in two pull requests
1. `Equinox`: the migration, the planner and the documents. Merged and applied first (nothing posts until the token is
   in the vault).
2. `equinox-backups`: the job and its script.

## 7. Gitesh's steps, one at a time, when asked
1. Done 10 Nov: the sign-in page was read in the built-in browser (above).
2. After the merges: run `select private.capture_key_issue(1, 'unattended (GitHub)', true);` in the SQL editor and add
   the answer as the `CAPTURE_KEY_UNATTENDED` secret in `equinox-backups`, then `GAME_USERNAME` and `GAME_PASSWORD`.
3. Make a fine-grained GitHub token with only *Actions: read and write* on `equinox-backups`, and add it to the vault in
   Supabase (Project settings → Vault, name `github_dispatch_token`).
4. Run the job once by hand while watching, then check three things: the run is green; the game hasn't signed you out
   in Safari; Safari still has the airline you left open.

Then the two runs a day start on their own.

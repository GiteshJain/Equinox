# Automatic checks

Decision #9. GitHub runs these on every pull request and every change to `main` (`.github/workflows/checks.yml`). The
result, with anything that failed, is posted as a comment on the pull request. While any check is red, nothing is merged.

| Check | File | What it proves |
|---|---|---|
| No keys or passwords | `check_secrets.py` | Nothing in the repository, test samples included, looks like a real key, a database password or a filled-in capture key. The public "anon" key and placeholders are allowed. |
| Schedule check | `schedule_test.mjs` | The real `/api/game-schedule` function reads a saved game page right: the session cookie, the airline, all 48 flights and their fields, plus clear errors for bad links and game errors. |
| Planner | `planner_test.py` | Every screen, each airline's Review page and the main pop-ups open with no errors. Previews save nothing while the live address saves. Loads by hand save only the days they change. The numbers that matter match the saved answers, and the leases match the manual. |
| Website | `site_test.py` | Every public page opens with its content and no errors, and `/planner` reaches the planner. |
| Database rehearsal | `../database/rehearse.sh` | Separate workflow (#8), when the database or the planner changes: last night's backup (downloaded from Cloudflare R2 and checked) restored into a full local Supabase (database, data API and sign-in); the database changes applied to it; every test in `database/tests/` run on that copy and rolled back; then the real saves. |
| Real saves | `real_saves_test.py` | Run by the rehearsal as its last step, not by `run_all.sh`: it needs Docker and the backup (#17). The pull request's own planner, at its live address and with its real Supabase library, signs in as a test staff user through its own form (opening it saves nothing, except its own copy of a capture taken after it last saved: cash and fixed7 figures equal to the capture's, allowed as in `planner_load_state_test.sql`) and saves into the copy: ticks a to-do, changes a plan card's title, types a load. After each save the tables are read back: only the intended field changed, and no table's row count. An account that isn't staff reads no rows and can't write. Signed out and as that account, through the data API, each of #13's new planner tables and views, and the capture's new tables and views, reads no rows and refuses a new row; the adapter's getters refuse both, and give staff what psql gets. No request leaves the runner. |

Run them all: `bash tests/run_all.sh` (needs Python with Playwright 1.56 and its Chromium, and Node 22).

## Database tests
Each file in `database/tests/` runs on the rehearsal's copy, after the new migrations, in a transaction that is rolled
back. A failed check stops with an error that says which. A passing test's notices (counts, never rows) are printed
under its `ok`.

**Before and after.** The files in `database/tests/before/` run before the new migrations and save chosen outputs into
the schema `rehearsal_before` (the data API, the row counts and the table guide don't look at it), so a test can
compare them afterwards. `capture_outputs.sql` saves the three capture views, `export_capture()` (every captured row),
`export_for_report('planner')`, `site_public()` and `planner_loads`; `planner_load_before.sql` how many of the capture's
flights had both their money and their loads.

| Test | What it proves |
|---|---|
| `capture_data_access_test.sql` | Signed out (anon) holds nothing on any table or view in `public`; `game_flights` and `game_payments` have RLS and one staff read rule, and authenticated may only read them; the capture views are `security_invoker` and read-only; the capture's internal functions are closed, `parse_capture()` and `apply_loads_from_capture()` retired; every capture row carries its world and airline; every foreign key on the capture tables has an index; an account that isn't staff reads no rows |
| `capture_data_compat_test.sql` | Once the capture data lives in `game_flights` and `game_payments`: `game_loads`, `game_flight_pnl` and `game_ops_recent` return the same rows as before, row by row; `export_capture()`, `export_for_report('planner')` and `site_public()` the same JSON; `planner_loads` unchanged; every statement line is in exactly one place (a flight or a payment) |
| `capture_data_ingest_test.sql` | `capture_airlines()` and `capture_ingest()` with the capture key, signed out: by game ID and by today's names; a wrong key, a wrong kind and an airline of another world are refused; the capture day runs 10:00 to 10:00 UTC; a day is complete only when every active airline of the world has all five pages (a 7th airline included), and `planner_loads` follows |
| `capture_data_matching_test.sql` | Money joins loads by route and time (design §3.8), on hand-made pages: a flight posted late, a block whose loads come the next evening, two flights close together on one route, one flight number flown on alternate days by two aircraft. On the copy, with the airports' offsets loaded from the planner's research: matching changes none of the views, every pair keeps the rules, and no pair that could only go one way is left |
| `capture_data_replay_test.sql` | Every raw page the copy keeps, replayed through the new capture path (by name, then by game ID) into emptied capture tables, gives exactly the rows the backfill gave |
| `planner_load_state_test.sql` | #13's data load: `planner_state_get()` equals `planner_state`, with only the differences design §9 allows, plus "cash/fixed7 captured after the planner last saved" (the Building chat's call, 10 Oct): the getter shows a capture at once, the planner copies it in only when it next opens. That one is allowed only where the getter's figure equals the capture's and that airline's balance for the date (or, for fixed7, an event it counts) was captured after `planner_state` was last saved. Each allowed difference used is printed with how often; a cash or next-7-day figure that fails is named, with the side that has it and why |
| `planner_load_test.sql` | #13's data load and the adapter's read side: `planner_loads_get()` equals every month of `planner_loads`, with only the differences design §9 allows; what went to `extra`; the loader run a second time changes no rows; how long each getter takes; signed out nobody may call them, an account that isn't staff is refused, staff get what postgres gets |
| `planner_load_flights_test.sql` | Every frequency is a rotation with two legs whose UTC weekdays, departure minutes and block times give back its local days, times and flight numbers; every return is the first departure within 24 hours of its outbound's landing (the old planner's next-day rule); design §4's DEL-JFK example by name; the share of the capture's flights with both money and loads after the matching, before and after, and why the rest are one-sided |
| `planner_load_sample_test.sql` | The same load on the frozen sample, in an emptied copy: the getters equal the sample's `planner_state` and loads, and DEL-JFK `z5qbaeg` is stored exactly as design §4 shows it |
| `loads_merge_test.sql` | Loads saves merge the days they change instead of replacing the month; the capture moves the month's saved time on |
| `planner_tables_access_test.sql` | #13's planner tables: RLS and one staff rule per action on each; anon gets nothing; authenticated reads them all and writes all but `change_log`; an account that isn't staff reads no rows and can't write; staff can; new objects in `public` aren't given away by default |
| `planner_tables_change_log_test.sql` | Every add, change and removal is logged with who made it (and nothing when nothing changed); logging can be switched off only by postgres; `private.restore_row()` puts a row back |
| `planner_tables_rules_test.sql` | The reference rows; design §4's worked example reads back in local time; the checks on weekdays, times and a leg's direction; flight-number clashes; rows can't point into another world; every foreign key has an index |

## Real saves (#17)
The rehearsal starts Supabase's database, data API and sign-in, and nothing else, then restores the backup. The test
makes two throwaway users through the local sign-in (one in `planner_users`, one not). The planner's requests for the
live Supabase address are answered by the local copy, with the local key in place of the live one; its Supabase
library is the version it names, from npm. Every other outside request is stopped, and the test fails if anything
reached the network except the local server.
- **Plan card title:** the planner has no field for it, so the test uses Reference → Data: export, change the title,
  import. That saves the whole document, which also proves an export and import change nothing else.
- **Typed load:** typing a day under Loads by hand replaces that day's whole entry with what's in the boxes (only
  flights under 95%). So the test types on the latest recent day with no loads yet, where nothing else can change.
- **The items** (the first open to-do, the first plan card, the day and flight) are picked from the restored data each
  run. `savedAt` and `version` may change with any save; a missing field counts the same as an empty (null) one.
- The log is posted on the pull request, so it shows ids and the names of changed fields only, never rows or keys.

To try it on your machine (Docker, the Supabase CLI, psql 17, Python with Playwright, Node): get a backup as below,
then `bash database/rehearse.sh .backup`.

## The sample
`fixtures/sample_<date>.json.gz` is what the planner and website read at one moment (`frozen_at`), taken from a nightly
backup by `fixtures/make_sample.sh`. The tests freeze the clock at that moment, so the answers don't drift.
`fixtures/game_schedule_113.html.gz` is Kingfisher's public schedule page from the game, saved signed out.

These are the one exception to "no game data in the code repository" (decision #9). They are small and dated, and
never hold the database, keys or sign-in data.

**Getting a backup to make a sample from.** The nightly copies are in the Cloudflare R2 bucket `equinox-backups`
(decision #16). You need the AWS CLI, jq and the R2 reader key (read-only). From the repository root:

```bash
export R2_ENDPOINT="https://<account id>.r2.cloudflarestorage.com"
export AWS_ACCESS_KEY_ID="<reader key id>" AWS_SECRET_ACCESS_KEY="<reader secret>"
bash database/backup/download.sh .backup   # latest.json, then the copy it names: checks the SHA-256 and unpacks it
bash tests/fixtures/make_sample.sh .backup 2026-10-08T21:00:00Z
rm -rf .backup                             # git ignores .backup/, but don't keep live data around
```

For an older night, download `nightly/equinox-backup-<date>T<time>Z.tar.gz` (kept 30 days) or
`monthly/<YYYY-MM>.tar.gz` (kept for good) together with its `.sha256`, into one folder and with the same names. Check
it with `sha256sum -c <file>.sha256`, then unpack it with `tar -xzf <file> -C <new folder>`.

## When an answer changes
- **Unintended:** the check caught a bug, so fix it.
- **Intended** (a calculation was meant to change): run `python3 tests/planner_test.py --update`, or
  `node tests/schedule_test.mjs --update` for the schedule check. Commit the new `*.expected.json` with the change, and
  say in the pull request which answers moved and why.
- **A new bug fixed:** add a test that would have caught it.
- **The data model changes** (#13): make a new sample with `make_sample.sh` and update the answers in the same pull
  request.

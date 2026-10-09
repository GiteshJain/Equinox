# Automatic checks

Decision #9. GitHub runs these on every pull request and every change to `main` (`.github/workflows/checks.yml`). The
result is posted on the pull request as **Checks: results**. While any check is red, nothing is merged.

| Check | File | What it proves |
|---|---|---|
| No keys or passwords | `check_secrets.py` | Nothing in the repository, test samples included, looks like a real key, a database password or a filled-in capture key. The public "anon" key and placeholders are allowed. |
| Schedule check | `schedule_test.mjs` | The real `/api/game-schedule` function reads a saved game page right: the session cookie, the airline, all 48 flights and their fields, plus clear errors for bad links and game errors. |
| Planner | `planner_test.py` | Every screen, each airline's Review page and the main pop-ups open with no errors. Previews save nothing while the live address saves. The numbers that matter match the saved answers, and the leases match the manual. |
| Website | `site_test.py` | Every public page opens with its content and no errors, and `/planner` reaches the planner. |
| Database rehearsal | `../database/rehearse.sh` | Separate workflow (#8): database changes applied to a copy of last night's backup. |

Run them all: `bash tests/run_all.sh` (needs Python with Playwright 1.56 and its Chromium, and Node 22).

## The sample
`fixtures/sample_<date>.json.gz` is what the planner and website read at one moment (`frozen_at`), taken from a nightly
backup by `fixtures/make_sample.sh`. The tests freeze the clock at that moment, so the answers don't drift.
`fixtures/game_schedule_113.html.gz` is Kingfisher's public schedule page from the game, saved signed out.

These are the one exception to "no game data in the code repository" (decision #9). They are small and dated, and
never hold the database, keys or sign-in data.

## When an answer changes
- **Unintended:** the check caught a bug, so fix it.
- **Intended** (a calculation was meant to change): run `python3 tests/planner_test.py --update`, or
  `node tests/schedule_test.mjs --update` for the schedule check. Commit the new `*.expected.json` with the change, and
  say in the pull request which answers moved and why.
- **A new bug fixed:** add a test that would have caught it.
- **The data model changes** (#13): make a new sample with `make_sample.sh` and update the answers in the same pull
  request.

# Remove the one-week aircraft checks from the planner (22 Oct 2026)

Gitesh, 22 Oct: remove the Aircraft checks board. Manual §1 has had no one-week aircraft checks since 15 Oct ("A new
schedule is checked once, when it's filed, and the capture's page checks show each night whether it flies"). Live has
`settings.aircraft_check_after_days` at 0, so the board and its items are already hidden there; they only show on the
rehearsal's copy, which switches them on for its tests. This removes the dormant feature from the planner's code.

## Remove
- Systems: the Aircraft checks board and its saves (mark checked), its row in the detail list, its FIGURE and NOTES
  entries, and `shownBoards`' rule for it.
- Today: the "One-week checks due" needs-attention group, its tile and card, and any one-week items in Coming up.
- Tails, Routes and Home: anything that shows, counts or saves a one-week check (a "check due" mark, "mark checked"
  buttons, the check's date in the aircraft pop-up), and the reads that fetch only for it.
- The planning library or the screens' models: the one-week check logic (e.g. `checks.oneWeek`) and its unit tests.
- The rehearsal's tests: stop switching the checks on, and drop the steps and saved answers that test them
  (`tests/planner_next_test.py`, `tests/planner_saves_test.py`, `tests/fixtures/planner_saves.expected.json`).

## Keep
- The database as it is: the `aircraft_check_after_days` setting row and `aircraft.checked_on` stay (removing them would
  be a removal migration Gitesh has to run by hand; not worth it for a value nothing reads). Note them in the pull
  request as left in place. Generated types (`app/planner/src/db/types.ts`) don't change.
- Everything else on every screen. No other figure, save or query changes.

## Checks
- `bash tests/run_all.sh` green; the database rehearsal green, every screen at 1280 and 380 px with no errors and no
  sideways scroll. The screens' figures tests may move only where they counted one-week items: say which in the pull
  request.
- Update `docs/planner-guide.md` and `docs/architecture.md` where they mention the checks.

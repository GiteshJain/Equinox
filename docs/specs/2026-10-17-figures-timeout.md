# The report's figures get time to finish (17 Oct 2026)

Building chat, option A, chosen by Gitesh 17 Oct ("A plus look at it").

## What happened
- `export_for_report('figures')` failed twice on 17 Oct (16:04 and 16:14 UTC) with a server error before a third try
  got through. The logs show both cut off after 3.09 seconds with "canceling statement due to statement timeout"
  (57014), called signed out (`anon`) by the weekly report's script.
- Signed-out calls have 3 seconds (`anon`), signed-in staff 8 (`authenticated`). The figures took 3.2 seconds on a quiet
  database the same day: about 700 KB, every captured figure for every airline, route profit worked out three times per
  airline (1, 3 and 7 days).

## The change
- `alter function public.export_for_report(text, text, text) set statement_timeout = '30s'`. The data API (PostgREST
  12 and later; live runs 14.5) applies a function's own `statement_timeout` to the call's transaction, so this one
  function gets 30 seconds and every other call keeps its role's limit. Calling it still needs the ingest secret.
- Migration `20261017170000_figures_timeout.sql`; `database/current/functions.sql` gains the `SET` line.
- Test `database/tests/figures_timeout_test.sql`: the 30 seconds and the search path on the function, no other function
  with a limit, the figures within 30 seconds on the copy.
- After the merge: applied to live, then the figures called through the data API as the script calls them.

## The 07:05 look (no change)
- At 07:05 UTC on 17 Oct `system_status()` (11.7 s) and `growth_signals()` hit the staff limit of 8 seconds, and
  `capture_status()` (4.6 s), `hub_progress()` (6.1 s) and `route_loads()` (5.4 s) were slow. All were Check opening
  25 seconds after an evening capture finished (snapshot 07:04:43), five heavy calls at once while the database was
  still busy with the capture. Two minutes later the same calls took 0.7 to 1.4 seconds. No other timeouts in the
  24 hours before.
- It's a burst after a capture, not a slow function, so nothing changes; the map's *When something breaks* says to open
  Check again a minute later. If it starts happening away from a capture, that's the time to speed the figures up
  (option B).

# Build spec: rivals' connecting options (23 Oct 2026)

**Why:** Gitesh chose option A of `docs/briefs/2026-10-23-rival-connections.md` on 23 Oct, with a 1.5 detour limit.
Read it, and the manual's *Decided, not yet built* entry "To build: rivals' connecting options" (the rule).
`competition()` counts a rival on our pair only if it flies it direct (spec
`docs/specs/2026-10-21-competition-analysis.md`), so connections through a rival's hub are invisible.

**Build after the rival fleets pull request has merged** (both change `competition()`): start from main with it in.

**Outcome when done:** each evening, when the world scan finishes, the database works out every rival's one-stop
connections on our pairs from that scan's schedules. Competition, a route's page and the weekly report show
"connecting" departures a week beside direct ones, never added to them. Nothing else reads them.

## 1. The calculation: `private.scan_connections(scan_id)`
Run at the scan's finish (`private.scan_ingest()` kind finish, the capture's and `gscan.py`'s alike), after the airport
summaries; also callable by hand for a past scan.
- **From the scan's schedules** (`game_scan_schedules.flights`: code, number, from, to, days 1–7, local departure,
  local arrival, type, airline name), passenger flights only (`private.scan_passenger()`), our airlines left out.
- **A connection:** a rival's flight A→H joined to the same airline's flight H→B, B ≠ A, on the same day, or the next
  day where the first leg's local arrival is earlier than its local departure (crossed midnight). The days string
  decides which weekdays each pairing runs. The gap (local times at H, no time zones needed) is at least
  `world_airports.mct_min` for H (90 minutes where unknown, as the website's trip search) and at most
  `settings.connection_max_wait_h` hours (8).
- **Detour:** the great-circle distance A→H→B at most `settings.rival_connection_detour_max` (new, 1.5, described)
  times A→B, from `airports.lat`/`lon`; a leg with an airport lacking coordinates is left out (and counted in the note).
- **Counted once per first flight:** for each rival, pair, direction and connecting airport, the weekly departures from
  A that connect onward (a flight with several onward options counts once a day, its earliest connection's gap kept
  as `best_gap_min`).
- **Kept only for our pairs:** pairs any of our airlines flies (a route with rotations) or has on its route list
  (`routes` not removed), either way round.

## 2. Storage (a new migration; descriptions; no `anon`/`authenticated` access)
- `scan_rival_connections`: scan_id, world_id, airline_id (the rival), origin, dest, via, weekly_departures,
  best_gap_min. Detail: archived with the scan schedules by the monthly archive after a full calendar month (add it to
  `private.archive_due()` and the archive's guarded delete, with a test, as the other detail tables).
- `scan_rival_connections_week`: kept for good. Per scan and rival, pair (least, greatest), direction totals, written
  by the same function.
- The scan's finish note adds "connections: N rivals on M of our pairs".

## 3. The figures
- `competition()`: each market and each pair's rivals gain `connecting_weekly` with the connecting airports (top 3 by
  departures), beside the direct figures; each rival profile and each of the three biggest competitors gains its
  connecting departures on this airline's pairs. The three biggest competitors are still chosen by direct departures;
  market share, threats, openings, contested and hubs first don't change (test that their answers are identical with
  and without connection rows).
- `route_story()`: Rivals on the pair gains each rival's connecting departures and airports at each scan.

## 4. Where it shows
- **Competition:** a "connecting" figure beside direct on each market card, rival profile and the openings' rivals
  column (as "3 direct · 14 connecting"); labelled so it never reads as one total.
- **Performance → route page, Rivals on the pair:** a connecting column.
- **The weekly report:** each of the three competitors with its connecting departures on our pairs, beside direct.
- Not Today.

## 5. Tests
- `database/tests/` on the rehearsal's copy: a hand-made scan with a connection inside the window, one under the
  minimum connection time, one over 8 hours, one over midnight (next day), one at 1.6 × detour (left out), a
  freighter (left out), our own airline (left out), two onward options from one flight counted once; the archive
  includes the detail table; `competition()`'s openings, threats, contested and share unchanged by connection rows.
- Timing: the function on the copy's latest scan, reported in the pull request (expect 1–3 seconds).
- The screens check (1280 and 380 px), the report test, the map's examples.

## 6. Documents (same pull request)
The map (paragraphs for the project copy in the description), the planner guide, `scripts/README.md`,
`database/current/functions.sql`, `docs/data.md` via the rehearsal. **Not the manual.**

## 7. What the checks should show
All green; `figures-moved`: `competition()` and `route_story()` gain fields only, every existing figure unchanged.

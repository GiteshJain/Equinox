# Build spec: the world scan in Capture all airlines (21 Oct 2026)

**Why:** Gitesh, 21 Oct (brief `docs/briefs/2026-10-21-competition-analysis.md`, outcome). Competition analysis and
the evening order proposal need fresh rivals. Instead of Claude running `scripts/scanner/gscan.py` on Saturdays,
**Capture all airlines** scans the world itself when a scan is due. How often is a setting, `scan_every_days`, which
starts at 1, every evening. Gander's owner allows the scanner (`world_rules.world_scanner`, manual §9).

**Outcome when done:**
- Pressing **Capture all airlines** captures our six airlines as now. Then, if the latest finished scan is at least
  `scan_every_days` old (by date, UTC), it scans the world, sends it in and finishes it.
- The panel says "World scan: 120 of 163 airlines…" and then "World scan done".
- The Systems board's scan line goes green that night.
- `gscan.py` stays in the repository as a fallback, run by hand.

## 1. The database
- **New migration:** `public.capture_scan(p_key text, p_kind text, p_payload jsonb)`, run as owner, granted to anon and
  authenticated like `capture_ingest()`.
  - With a valid capture key, it does what `ingest_snapshot()` does for the kinds `start`, `airline`, `airport` and
    `finish`, in the key's world, not the default world. Share the logic: move `ingest_snapshot()`'s body into a
    private function both call, `ingest_snapshot()` keeping its secret check and its answers unchanged.
  - A bad key is refused as the capture refuses one.
  - `start` refuses a second unfinished scan of the same world started within the last hour, and answers with that
    scan's id instead, so a capture run twice doesn't start two.
- **`capture_airlines(p_key)`** also answers with:
  - `scan_due` (true when the world's latest finished scan is at least `scan_every_days` days old by UTC date, or there
    is none);
  - `scan_open` (an unfinished scan's id from the last hour, if any);
  - the **airport list** to read: our bases, the big rival hubs (the list in `gscan.py`) and the top airports
    (`gscan.py`'s `top_airports.json` idea, taken now from the latest scan's busiest 20 airports by departures),
    without repeats.
- **New setting `scan_every_days`**, 1, in every world, described ("Gitesh, 21 Oct: every evening to start").
- **Database test** (`database/tests/capture_scan_test.sql`):
  - a bad key refused;
  - start, an airline and an airport sent, finished, with the rows in `game_scan_airlines`, `game_scan_schedules` and
    `game_scan_airports` and the airlines placed, exactly as `ingest_snapshot()` makes them;
  - a second start within the hour gets the same id;
  - `scan_due` true and false around the setting.

## 2. The capture script (`capture/capture_all.user.js`, version 1.5)
After the last airline's loads page, if `scan_due`:
1. **`start`**, or carry on with `scan_open`.
2. **The airline list:** the 26 letter pages, `/app/info/enterprises?letter=A` to `Z`, read for `./enterprises/<id>`
   and the name, as `gscan.py` does.
3. **Each airline:** `/app/info/enterprises/<id>?tab=3`, the schedule table read into the same flight rows as
   `gscan.py`: code, number, from, to, days, the two times, aircraft and operator. Send `airline` with its counts. Keep
   the airport ids seen (`../airports/<id>` and the code).
4. **Each airport** on the list: `/app/info/airports/<id>`. Read the same info, stations and news as `gscan.py`, and
   send `airport`.
5. **`finish`.**

- **Pace:** the scanner's own, 0.4 s between letter pages, 0.5 s between airlines, 0.25 s between airports.
- **The panel** shows progress and a Stop button.
- **State in `sessionStorage`,** so a page reload carries on where it was.
- **A failed page is logged and skipped,** as `gscan.py` does. If more than 10% of the airlines fail, the scan isn't
  finished, and the panel says so, so the Systems board stays amber.
- **The capture's own pages and verdicts don't change.** If the capture of our airlines failed, there's no scan that
  evening.
- **The parsing is plain functions,** split from the page code as `fares_apply.user.js` does, so a Node test can run
  them.

## 3. Tests
- `tests/capture_scan_test.mjs` on saved samples in `tests/fixtures/` (dated, cut down, no account data):
  - one letter page;
  - one airline's schedule page;
  - one airport page.

  It checks that the same rows come out as from `gscan.py`'s rules on the same samples: run both and compare in the
  test. Python is available in `run_all.sh`.
- Samples: if none are in the repository, build small ones by hand from `gscan.py`'s patterns and say so; Gitesh can
  save real ones from the game (Share → Web Archive) for a follow-up.
- `tests/run_all.sh`, `tests/README.md`, `tests/check_secrets.py` passing.

## Docs
- Manual:
  - §7: the Saturday step "first, the world scan" becomes "the world scan runs with the evening capture
    (`scan_every_days`); if the Systems board shows it old, run `gscan.py` by hand";
  - the Systems board line: keep amber over 8 days, red over 15;
  - take the item out of "Decided, not yet built".
- `docs/playbook.md`:
  - the Saturday steps;
  - the capture step: it takes a few minutes longer on scan evenings; keep the page open.
- `docs/architecture.md`: Capture row, the scan, `capture_scan()`, the key table.
- `scripts/README.md`: `gscan.py` as the fallback.

## Not in this build
- Competition analysis itself (next spec).
- Changing what a scan reads.

# Spec: the market pages, part 1 (capture 1.9 and the database) — 30 Oct 2026

*Building chat. Decided 30 Oct (Gitesh), brief `docs/briefs/2026-10-29-market-pages.md`, option C, once a week when due.
Manual: *Decided, not yet built*, "The market pages, once a week". Part 2 (the route page, Competition, the weekly
report) is a separate spec after this merges.*

## What
Once a week, after the evening's capture (and its world scan, when one runs), the capture userscript reads the game's
Market Analysis page for both directions of every pair our airlines fly, parses it in the browser and sends only the
figures to the database. Nothing is shown in the planner yet.

## Why
The fare ladder moves on our own loads with no view of rivals' fares, and Competition's share is estimated from the
scan's departures. The page gives rivals' fares by flight and class, the game's passenger share, and the pair's weekly
seats and price. Raw pages (about 290 KB) are not kept.

## The page
`https://<game host>/app/com/markets/<FROM><TO>` (IATA codes, e.g. `DUBAMS`; the game redirects to its own `?n`
version). It belongs to the airline that is **open**: its airport lists are that airline's stations and its pricing is
that airline's. A saved copy (Ryanair open, DUB→AMS, 30 Oct 04:51 UTC) is at
`/tmp/claude-0/-home-claude/774e0f0a-6a27-5acc-8550-e6bf855ae442/scratchpad/market_DUBAMS_2026-10-30.html`.
Add it as `tests/fixtures/market_DUBAMS_2026-10-30.html`, with the page header's account menu (player name, holdings
list, cash) cut out and the rest left as saved.

What to read from it:
1. **The filters** (in the markup, `pair:pair-panel:listing:filters:*`): every `serviceClasses` and every `flightStati`
   checkbox checked, `ignoreCarriers` unchecked, `display` (Group by flight) checked. The game keeps them between
   visits. **If any differs, the userscript sets it** through that filter's own listing control only (the page's
   Wicket calls `...-listing-filters-serviceClasses`, `-flightStati`, `-ignoreCarriers`, `-display`, as its load
   script names them; the evaluation userscript shows how to post to a Wicket page), then fetches the page again and
   checks. Only if a filter still differs does the run stop, naming it ("Market pages: couldn't set 'cancelled' under
   Flight status on DUB→AMS"). The panel notes each filter it set (Gitesh, 30 Oct).
2. **Current Availability** (`#inventory-grouped-table`): one `tbody` per flight: the flight (`KL 8`), the aircraft
   type, the date and times (each cell's title gives UTC), then a row per class (`Y`, `C`, `F`, `Cargo`) with seats left
   (shown at most 9 for passengers) and price (`120 AS$`), and the status (finished, booked, inflight, cancelled).
3. **Market Shares**: the current week (`44/2026`) and the previous one's label; Passengers and Cargo tables, each row
   an enterprise (link `../../info/enterprises/<game id>`), its share and its change in points.
4. **Historic Capacities and Prices**: the two `setData([...])` calls in the page's load script: `capacities` and
   `prices` by `period` (`202644` is week 44 of 2026). Keep the weeks with figures (non-zero).

## Capture 1.9 (`capture/capture_all.user.js`)
- `capture_airlines()` also says whether market pages are due and lists them: due when the world's latest **finished**
  market run is at least `settings.market_every_days` capture days old (as `scan_every_days` works; 0 switches it
  off), or there is none; an unfinished run started within the hour is carried on. The list: for each of our active
  airlines (its `game_id` and code), both directions of each pair it flies (routes with rotations, not removed), in a
  fixed order, with the pages already read in an open run left out.
- It runs after the world scan (or after the last airline when no scan is due), only when no capture page failed that
  evening, and with Stop and the `sessionStorage` carry-on the scan has. Panel: "Market pages: 120 of 686 (Pan Am)…",
  then "Market pages done: 686, N failed".
- **Switch airline** before each airline's pairs, as the fares userscript does
  (`/app/enterprise/dashboard?select=<game id>`), and check the first page shows that airline open (as the fares
  userscript checks; stop if not).
- Each page by `fetch` with the session's cookies. **The only posts allowed are the four listing filters above;** the
  Pricing and settings forms on the same page change our fares and are never submitted. Pace 500 ms between pages. A page that doesn't parse is sent as
  failed with its error and skipped; a filter mismatch or the session lost stops the run.
- Sends to a new `capture_market(p_key, p_kind, p_payload)` with the capture key: `start`, `page` (the parsed
  figures, never the HTML), `finish`. A run with more than 10% of pages failed isn't finished, as the scan's 10%.

## Database (one migration; descriptions and grants on everything)
- **Setting** `market_every_days`, 7, world default, described.
- **`market_runs`**: id, world, started and finished (status open, done, stopped), pages read and failed, note,
  capture version. As `game_scans`.
- **`market_reads`**: a run's page: run, our airline, origin, destination (codes), read at, ok or failed with its error,
  the market share's week label.
- **`market_fares`**: per read, airline and class (Y, C, F, Cargo): flights seen, lowest, average and highest price,
  flights finished and finished with 0 seats left (sold out). The airline: `airlines` matched by the flight's prefix
  where the latest world scan's schedules give one airline that prefix, else by an enterprise on the page's share list
  with that name; unmatched keeps the prefix text (`airline_code`) with `airline_id` null. Nothing per flight is stored.
- **`market_shares`**: per read: kind (passengers, cargo), airline (by the enterprise's game id; an unknown one gets an
  `airlines` row, actor capture, as the scan does), week (2026-44), share and change in points.
- **`market_weeks`**: per world, origin, destination and calendar week: seats offered and price per unit, the latest
  read winning. Kept for good.
- **`capture_market()`** (capture key, its world; 30 s limit as `export_for_report()`), **`capture_airlines()`**'s new
  market part, and the work in `private.*` as the scan's is.
- **Grants:** `market_runs`, `market_reads`, `market_fares`, `market_shares`: RLS on, staff read. `market_weeks`: the
  same. Nothing for `anon`.
- **Keeping:** `market_reads`, `market_fares` and `market_shares` go to the monthly archive with the scan schedules
  (detail more than one full calendar month old, `private.archive_due()` and friends); `market_weeks` and `market_runs`
  stay. Check the archive's tests still pass with the new tables.
- `system_status()` gains a market line (latest finished run, its age, pages and failed), so the Systems board can show
  it in part 2. Leave the board's screen alone.

## Tests
- `tests/capture_market_test.mjs`: the parser on the saved page gives the filters as expected, every flight's classes
  and prices (KL 8: Y 120, C 245, Cargo 91; EI 506: F 457), the shares (KLM 68.46, −10.32; Aer Lingus 24.61; Ryanair
  6.94) and the historic weeks (week 43: 9,616 seats, 122 AS$); a page with one filter changed is refused and named;
  a page with filters off is set right through the four filter calls and then read; a filter that won't take stops
  the run, named; a whole run against a stand-in for the game posts only to the four filter calls (never the Pricing
  or settings forms) and switches airline once per airline.
- `database/tests/market_pages_test.sql`: `capture_market()` start, pages and finish on the saved page's figures
  give the expected rows; due and not due by `market_every_days`; an open run carried on; an unknown enterprise added;
  wrong key refused; staff can read, `anon` can't.
- The rehearsal runs as usual; the planner's types regenerate with the new tables.

## Docs, in the same pull request
The map (`docs/architecture.md`: the capture row, How data moves, What runs when, the call guide with one tested
example over `market_fares` that aggregates into one row), `docs/data.md` through the rehearsal, `scripts/README.md`
if anything there changes, `database/current/`, and `capture/` notes. Don't change the manual: the Building chat moves
the rule out of *Decided, not yet built* when part 2 merges.

## Not in this pull request
The planner's screens, Competition, the weekly report, the fare ladder, the openings. Nothing reads the new tables yet
except the tests and `system_status()`.

# Build spec: rivals' fleets in the world scan (23 Oct 2026)

**Why:** Gitesh chose option A of `docs/briefs/2026-10-23-rival-fleets.md` on 23 Oct. Read it, and the manual's
*Decided, not yet built* entry "To build: rivals' fleets in the world scan" (the rule). The scan reads schedules and
airports only, so a rival's fleet and order book never show: Icelandair (enterprise 101) has 99 aircraft and 44 on order.

**Outcome when done:** each evening's world scan also reads every enterprise's overview page and keeps its fleet by type
with the scan. Competition and the weekly report show each rival's fleet, aircraft on order and the change since the
week-before scan, and flag big order books and airlines with orders but no flights yet.

## 1. The page
`https://gander.airlinesim.aero/app/info/enterprises/{game id}`; saved sample
`tests/fixtures/enterprise_overview_101_2026-10-23.html` (Icelandair, trimmed, the game's markup kept). The Fleet table
is `table.fleet`: per type (the link's text, its `aircraftsType?id=`), owned, leased, overall, leased out, on offer, on
order, Ø age ("0.1 yrs"); `tfoot` holds the totals. Read too, from the same page: General Information (code, alliance,
headquarters IATA, parent company's enterprise id, founded) and General statistics (transported passengers, stations,
fleet size, staff). The page reads signed out; outside a browser it first redirects (Wicket's `?0`) and needs the
session cookie, as the schedule pages do.

## 2. Reading it: the capture userscript (version 1.8) and `gscan.py`
- In the world scan, after each airline's schedule, read its overview page, at the scan's pace (0.4 to 0.5 s between
  pages), every enterprise the letter pages list (flying or not). Send it to `capture_scan()` with a new kind `fleet`
  (the scan id, the airline's game id, the parsed rows and the general figures; a page that doesn't read is sent with
  its error).
- A failed overview page is logged and skipped. It never stops the scan, and never counts towards the 10% of failed
  airline pages that leave a scan unfinished.
- The panel's progress names them ("World scan: 120 of 171 airlines…" stays one count; the airline step now reads two
  pages). The finish note adds "N fleet pages, M failed".
- `scripts/scanner/gscan.py` reads the same pages the same way and sends them through `ingest_snapshot()` (the shared
  `private.scan_ingest()`), so the fallback gives the same rows. `tests/capture_scan_test.mjs` checks both parse the
  saved page to the same rows.
- `scan_every_days` is unchanged: the fleet pages come with every scan.

## 3. Storing it
A new migration (descriptions on everything; no access for `anon` or `authenticated` on the tables, read through
functions, manual §1):
- `scan_airline_fleet`: scan_id, world_id, airline_id, type_name, game_type_id, owned, leased, overall, leased_out,
  on_offer, on_order, avg_age_years. One row per scan, airline and type; kept for good (with the scan summaries, so the
  monthly archive leaves it alone).
- `scan_airline_profile`: scan_id, world_id, airline_id, fleet_size, on_order (the totals), stations, staff,
  passengers, alliance, parent game id, founded, read_ok, note. One row per scan and airline read; kept for good.
- Settings: `rival_orders_flag_pct` 25 and `rival_orders_flag_min` 5, described.
- `private.scan_ingest()` handles kind `fleet`; `capture_scan()` accepts it.

## 4. The figures: `competition()`
- Each of the three biggest competitors (`competitors`) and each rival profile gains `fleet`: overall, on order, average
  age, the types (top 5 by overall, with on order), and the change against the week-before scan (overall and on order;
  null when either scan has no read for that airline).
- A new `order_flags` list, world-wide (the same in every airline's answer), each with the airline, fleet, on order,
  share and kind:
  - **orders:** on order at least `rival_orders_flag_pct`% of overall and at least `rival_orders_flag_min`;
  - **starting:** on order above 0 and no flights in the scan.
  Our own airlines are never flagged. Freighter-only airlines are left out (the passenger rule, `private.scan_passenger()`).
  Each flag says whether the airline flies on any of this airline's pairs or at its bases.
- No flag feeds the openings, the contested test or the fare pause.

## 5. Where it shows
- **Competition** (`app/planner/src/screens/competition/`): on an airline's page, each rival profile shows its fleet
  ("99 aircraft, 44 on order, +6 on order this week") and its top types; on the group page, a new board **Order books**
  lists `order_flags` (biggest share first), each marking whether it meets this group's airlines.
- **The weekly report** (`scripts/report/`): each of our airlines' three competitors gains fleet, on order and the week's
  change; flagged rivals appear in the risks.
- **Systems:** the scan line says how many fleet pages the latest scan read.
- Not Today's Needs attention.

## 6. Tests
- `tests/capture_scan_test.mjs`: the userscript's and `gscan.py`'s parse of the saved page give the same rows (8 types,
  totals 99 and 44, the profile figures).
- `database/tests/` (rehearsal): `capture_scan()` kind `fleet` stores the rows; a failed page doesn't stop the finish;
  `competition()` gives fleets, the week's change, an orders flag (Icelandair-like), a starting flag, no flag at 20% or
  with 4 on order, no flag for our airlines or a freighter-only airline.
- The weekly report test on its sample; the screens check (every screen at 1280 and 380 px) with the new board.
- The map's examples still run on the copy (`tests/briefing_copy_test.py`).

## 7. Documents (same pull request)
The map (`docs/architecture.md`; put the changed paragraphs in the pull request description for the project copy), the
planner guide, `scripts/README.md`, `database/current/functions.sql`, `docs/data.md` via the rehearsal, the README if it
names the scan's pages. **Not the manual:** the Building chat updates §7 after the merge.

## 8. What the checks should show
All green. `figures-moved`: `competition()` only (its new fields), and the report's three-competitors section.

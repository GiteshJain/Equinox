# The fleet in the evening capture (22 Oct 2026)

Brief `docs/briefs/2026-10-22-fleet-capture.md`, option B now, C later (Gitesh, 22 Oct). This build is B: the capture
reads every fleet page of every airline each evening; the database keeps each aircraft's figures night by night; Today
flags what needs a look. C (fitting the planner's maintenance figure to the game, refitted weekly) is a later build once
about two weeks of nights are in; this build only has to keep what C will need.

## 1. The capture (`capture/capture_all.user.js`, version 1.6)
- After each airline's existing pages, read its fleets: the fleet list (`/app/fleets`) gives each fleet's link
  (`/app/fleets/<id>`, Gitesh keeps one per hub); read each fleet page and send it as a new page kind, `fleet`, with the
  capture key, like the other pages (`capture_ingest()`). An airline with no fleets sends none.
- Keep the capture's pace and its panel ("Pan Am: fleet 2 of 3"). A fleet page that doesn't read is a broken page (#21).
- A dated sample of a real fleet page is in this build's hands (Pan Am's JFK fleet, 22 Oct, 19 aircraft): put it in
  `tests/fixtures/` as `fleet_JFK_2026-10-22.html` after removing anything that identifies the session (session ids in
  links, tokens, the user's name or e-mail); keep the aircraft rows exactly. The capture's parser is tested on it in
  Node, like the fares userscript's test.

## 2. The database (one migration)
- **`game_fleet`**: one row per aircraft per capture day (design §2's day: 10:00 to 10:00 UTC), the latest capture of
  that day winning: world, airline, `aircraft_id` (matched by registration within the airline; null when the planner
  doesn't know it), registration, the game's type name, nickname, location (from and to, or the airport it's at), the
  flight it's on, age in years, condition %, maintenance %, seats Y, C, F, pilots (yes or no), owned (yes or no),
  contract status, the fleet's game id, captured_at. Kept for good (it's small: about 140 rows a night): it is what C
  learns from. Staff read it; only the capture writes it. A description on the table and every column; grants as manual
  §1 ("a new table grants its own access").
- **Page check (#21)**: a fleet page is short with no aircraft rows, broken if it doesn't read. Add `fleet` to
  `capture_status()` and the Systems board's capture verdicts.
- **`fleet_checks(p_world_id, p_as_of)`**, staff only, 30 s limit like the other figures: from the latest night's
  `game_fleet` for our airlines, a list of problems, each with the aircraft (registration and base), the kind and the
  words:
  - **maintenance**: maintenance under `settings.maintenance_min_pct` (100), with the condition beside it ("N003AW (JFK):
    maintenance 0.0%, condition 83%");
  - **crew**: pilots "no";
  - **cabin**: seats Y/C/F that don't match the aircraft's cabin in the planner (`aircraft.cabin_config_id` →
    `cabin_configs`' seats); an aircraft with no cabin in the planner is listed as "no cabin in the planner";
  - **not in the planner**: a registration in the game that no `aircraft` row of that airline has;
  - **not in the game**: an active aircraft of ours (status active) missing from that night's fleet pages, only when
    every fleet page of its airline came in ok that night.
  It also gives each kind's count and the night it read.
- Tests in `database/tests/`: the page kind and its check, the matching, each problem kind, and the "only when every
  page came in ok" rule.

## 3. The planner
- **Today**: a needs-attention group "Fleet" with one item per problem from `fleet_checks()`, worst first (maintenance,
  crew, then the rest), in Today's existing tile and card pattern (step 2 of the new look). A maintenance problem is the
  most urgent kind of card after "order now".
- **Systems**: the evening capture table shows the fleet pages in each airline's verdict; Systems' detail rows gain
  "Fleet", the latest night's fleet as a table per airline (registration and base, type, location, condition,
  maintenance, seats, pilots), with problems marked.
- **Tails**: each aircraft's pop-up shows the game's maintenance and condition from the latest night beside the
  planner's own maintenance figure, so the two can be compared.

## Docs
`docs/architecture.md` (the capture's pages, the new table and figure), `docs/data.md` (regenerated),
`docs/planner-guide.md` (Today, Systems, Tails), `docs/playbook.md` (the evening capture: one more page kind, about a
minute more), `scripts/README.md` if touched, the manual §7 (the capture's pages and their checks: one sentence).

## Checks
`bash tests/run_all.sh` green; the database rehearsal green (every screen at 1280 and 380 px, every save). No
existing figure or saved answer moves. Gitesh installs the new capture version himself after the merge (the pull
request says how, as for 1.5: the Userscripts app on the Mac, his key in place of `__CAPTURE_KEY__`).

## Not in this build
C (fitting the maintenance figure); any change to the planner's maintenance formula; an idle-aircraft check.

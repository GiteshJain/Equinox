# Stations: a third role in the airline's bases, for point-to-point routes (22 Oct 2026)

Brief `docs/briefs/2026-10-22-point-to-point-routes.md`, option A (Gitesh, 22 Oct). Manual: "Decided, not yet built"
(the station role) and §3 hubs first ("Stations open nothing until the main hub reaches the 750, contested or not").

## What and why
Kingfisher's route list is to hold about 214 Inter Connect pairs that touch none of its six bases (Lucknow–Patna,
Ahmedabad–Pune). A route is filed under one of its ends (`routes.hub_code`, leg 1 leaves it). For these pairs that end
becomes a **station**: an `airline_bases` row with `role = 'station'`, no bank times and no flight-number block of its
own. Stations make the pairs listable, rankable in `competition()`, numberable and plannable, without being mistaken
for hubs or focus cities anywhere.

## Database (one migration)
1. `airline_bases.role` check: allow `'station'`. A station has `bank_times` null or all null, `is_main` false,
   `parent_base_id` null, `flight_no_from` null. Enforce with a check constraint.
2. Settings (with descriptions): `station_flight_no_from` 100 and `station_flight_no_to` 999, world-wide with an
   airline override possible like other settings. Rule numbers live only there (manual §1).
3. Everywhere the database reads `airline_bases` as "our hubs and focus cities", exclude stations (`role <> 'station'`):
   - `private.fig_competition`: trunks (both ends must be hubs or focus cities), contested bases, the base list used to
     sort and to judge hubs first. A station pair is listed and ranked like any opening, and hubs first marks it not
     allowed until the airline's main hub reaches `hub_first_departures`, with the reason "hubs first: stations wait
     for <MAIN>'s 750", whatever the contest (manual §3). Ryanair stays exempt. In November (`trunk_month_*`) a pair
     with a station end is never a trunk.
   - `fig_hub_progress`, `site_public()`'s hubs, the briefing and report exports where they list bases: no stations.
     Where a list of airports flown from is wanted (e.g. a route list grouped by where it starts), stations may appear
     as stations, never as hubs.
   - Search `database/current/functions.sql` and `views.sql` for every `airline_bases` read and decide each; say in the
     pull request which you changed and which needed nothing.
4. New tests in `database/tests/`: a station is accepted only with no banks and no block; competition() lists a station
   pair with the hubs-first reason before the 750 and allows it after (move the setting in the test); a station pair is
   never a trunk; hub_progress and site_public() leave stations out.

## Planning library (`lib/rules/`)
- Flight numbers (`schedule.ts` `nextFlightNumbers`): for a station, the next free pair in the airline's station pool
  (`station_flight_no_from` to `_to`), counting every number the airline already uses on any station route, so no two
  stations clash. A pool that's full says so.
- Banks (`banks.ts` `wave`, `baseAt`): a station is "no banks" (never "off wave"), and `baseAt` must not fall back to
  another airline's base at the same airport when this airline has a station there.
- Growth (`growth.ts`): stations never feed "big" growth candidates or count as banked hubs.
- Optimiser: finds the airline from a station like from a base.
- Cases in `lib/rules/cases/` for each of these.

## Planner
- Routes: the base picker lists stations after hubs and focus cities, marked "station" ("From LKO (station)"); the
  add-route form offers stations; a station route's detail says "station · no banks" instead of "no bank at this
  hub"; trunk tags never on a station pair.
- Reference → hubs: the role picker has Hub, Focus and Station; saving keeps Station (today anything not Focus saves as
  Hub). A station row shows no bank times or block fields.
- Home: the map draws a station as an ordinary airport dot, not a hub ring, and airline cards don't count stations as
  hubs.
- Plan cards and filing: work for a station route as for a base route (they already do; add a test).

## Website (`web/`)
- `site_public()` already leaves stations out of hubs (above); the trip search connects only through hubs, so a station
  leg shows as a direct flight only. Check the departure boards and labels never call a station a hub.

## Scripts
- `scripts/briefing/brief.py`, `scripts/report/*`: bases lists and charts leave stations out; a station route counts
  under its airline like any other route.

## Docs
`docs/architecture.md`, `docs/data.md` (regenerated), `docs/planner-guide.md` (Routes, Reference), `docs/playbook.md`
if a step changes, `scripts/README.md`, the README if needed. Manual: move the "Decided, not yet built" entry for
stations into §2 or §3 as built (one sentence), in the same pull request.

## Checks
`bash tests/run_all.sh` green; the database rehearsal green (every screen at 1280 and 380 px, every save). The screens'
figures and saved answers must not move: no station exists yet on the copy. No live data is loaded by this build; the
review chat loads Kingfisher's stations and pairs after the merge.

## Not in this build
Loading any station or pair; any change to hubs first beyond the stations line; any other airline.

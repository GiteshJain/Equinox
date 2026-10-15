# The new planner and its calculations: design (decisions #18 and #19)

*12 Oct 2026. Approved by Gitesh when merged; nothing is built before that. The choices in §14 are Claude's call
unless he changes them. Based on #18 (React with TypeScript, screen by screen at `/planner/next/`), #19 (planning rules
in a TypeScript library, captured figures in the database) and #20 (the website keeps its one call). While this is
built the game is paused and the old planner frozen (manual §1).*

## 1. Summary for Gitesh
**The answer:** a new planner, built in React with TypeScript, grows at `equinox-alliance.com/planner/next/` beside
the old one. It reads the tables directly and saves one change at a time. The calculations move out of the screens:
- **planning rules** (block times, turns, connections, maintenance) into one library the planner, the website, the
  optimiser and Claude all use;
- **figures from the capture** (cash forecast, route profit, growth signals, hub progress) into the database.

Each new screen must show the same figures as the old one on the same data before it's merged.

**What changes for you:**
- Nothing until you open `/planner/next/`. The old planner stays at `/planner/` until you say switch.
- Every screen works on your phone.
- Each screen loads only what it shows, and each change saves on its own.
- Two things go: importing or clearing the whole planner (Reference → Data), and the copy kept on this device when a
  save fails (§14).

**What you approve:** this design, including the choices in §14.

**One step for you, at the first pull request's merge:** a build command in Cloudflare's settings (§3).

**Build:** 14 pull requests, one at a time (§13):
- 1: the shell;
- 2 to 4: the calculations;
- 5 to 12: the screens;
- 13: the switch;
- 14: the clean-up.

## 2. Principles
- **Same features, then more.** The new planner does what the old one does, on a phone too, and nothing new until
  after the switch. Ideas that come up meanwhile go on a list in the decision log.
- **One home for each calculation (#19).** A figure is worked out in exactly one place: the planning library or the
  database. Screens only display.
- **Same numbers, proven.** Each screen's figures are compared with the old planner's on last night's copy, at the
  same moment, before its merge (§10).
- **One source for rule numbers.** The library and the database read `settings`, `world_rules`, `aircraft_types` and
  `world_airports`; nothing is typed into code.
- **Small loads, small saves.** A screen asks for its own rows; a change sends its own rows.
- **Nothing assumes six airlines or one world (#14).** Airlines come from `airlines`; a world switcher appears only
  when there's a second world.

## 3. Where the code lives, and how it's built
**In the repository:**

| Folder | What |
|---|---|
| `app/planner/` | The new planner: `src/screens/` (one folder per screen), `src/data/` (reading and saving), `src/ui/` (shared parts: tables, cards, the map), `src/db/types.ts` (generated, §5) |
| `lib/rules/` | The planning library (§7): `src/`, its tests, `cases/`, and `cli.ts` |
| `package.json` (root) | One set of dependencies with a lock file. Scripts: `build`, `typecheck`, `test`, `lint` |
| `.nvmrc` | Node 22, for Cloudflare's build and the checks |

**Main parts:** React 19, TypeScript, Vite 8, React Router, TanStack Query (loading and caching data), Vitest (unit
tests) and ESLint with React's hook rules. Versions are pinned in the lock file. A chart or map library is added only
when a screen's spec needs one.

**Built output (not committed):**
- `web/app/`: the new planner's page and files;
- `web/assets/rules.js`: the library, for the website's trip search.

**Cloudflare:** the build command becomes `npm ci && npm run build`; the output folder stays `web`. Gitesh sets it
once in Cloudflare's dashboard (Workers & Pages → equinox-alliance → Settings → Build) when the first pull request
merges. Every deploy then runs the build, previews included. If a build fails, Cloudflare keeps the last good
version live; the checks run the same build on every pull request, so a broken one can't merge.

**Addresses.** On Cloudflare, `_redirects` rules win over files, and `/planner/*` already sends everything to the old
planner. So the new planner's files live under `/app/`, and only its page is mapped:

```
/planner/next     /planner/next/    301
/planner/next/*   /app/             200
/planner          /planner/         301
/planner/*        /planner/         200
```

The two new lines go above the old ones. The target is the folder, `/app/`, not `/app/index.html`: Cloudflare drops a
200 rule that points at a path ending in `/index.html` as a loop, and the old planner's line would then take over
(found by the shell's build, pull request #27, 12 Oct). The new planner's own addresses are `/planner/next/routes`,
`/planner/next/review/VS` and so on. `_headers` gives `/app/assets/*` a year's caching, since their names change with
every build, and keeps `/app/index.html` uncached.

**Since the switch (§11, build pull request 13, 14 Oct)** the rules are:

```
/planner/next     /planner/           301
/planner/next/*   /planner/:splat     301
/planner/old      /planner/old/       301
/planner/old/*    /planner/           200
/planner          /planner/           301
/planner/*        /app/               200
```

The new planner's base is `/planner/` (`BASENAME` in `app/planner/src/data/config.ts`), so its addresses are
`/planner/routes`, `/planner/review/VS` and so on. An address from the build moves (301) to the same address under
`/planner/`. The old planner's file stays where it is and is served at `/planner/old/`: a 200 rule serves the file at its
target without the rules being applied again, so `/planner/` there is the old planner's own `index.html`. Going back
is the last line: `/planner/*   /planner/   200` again. The checks follow the file itself (`tests/harness.py` reads
`_redirects`), so a wrong rule turns them red.

## 4. Sign-in, previews and access
- **Sign-in:** the same Supabase sign-in and staff check (`is_planner_user()`). Sign-ups stay off (#11).
- **Look-only previews (#8):** saving works only on `equinox-alliance.com` and `www`. Anywhere else the planner says
  "preview · not saved" and sends no writes.
- **Reading:** straight from the tables and views, under their existing staff rules.
- **Writing:** only through `planner_save()` (§6) and the existing photo functions.

## 5. Reading data
- **Types from the database.** `app/planner/src/db/types.ts` is generated by `supabase gen types typescript` and
  committed. The rehearsal regenerates it on last night's copy after the pull request's migrations and fails if it
  differs. A migration that renames or drops a column must update the types in the same pull request, and the
  planner must still build.
- **Per screen.** Each screen asks for what it shows (§9), through TanStack Query, which keeps a screen's data while
  you move around and reloads it when it's stale or after a save.
  - The route research loads one airline at a time.
  - Captured figures come from the database functions in §8, not raw rows.
- **Rules at start.** One call, `rules_input(world)` (§7), gives the library everything it needs: the settings, world
  rules, aircraft types, airports (connection times, time zones, night bans) and every planned leg.
  *Found 12 Oct, after pull request #28:* on live it's about 1 MB, because it carries all 4,522 researched routes and
  their 1,219 airports. Pull request 5 (Home) gives the planner a lighter start (flown routes and their airports
  only), with the rest loaded one airline at a time by the Routes screen.
- **Time.** Stored times are UTC. The screens show local or UTC times, as the old planner's toggle does
  (`settings.planner_time_mode`).

## 6. Saving
**One database function, `planner_save(p_changes jsonb, p_client text)`.** Each action you take (tick a to-do, move a
departure, edit a plan card) sends one call with every row it changes.
- **Inside:**
  - the actor is `planner`, and the tab's ID goes in the change log (#15);
  - each change names its table, its key, the operation and its values;
  - an update or delete also sends the row's `updated_at` as it was loaded.
- **All or nothing per action.** If any row was changed elsewhere since it was loaded, nothing in that call is
  written. The answer returns those rows as they are now, and the planner shows them, says what clashed and lets you
  redo it. Other actions are separate calls, so they still land. This follows #13's rule (design §11, choice 4) at
  the level of a single action.
- **Answer:** the new or changed rows with their keys and `updated_at`.
- **Access:** staff only, runs as owner with an empty search path, writes only the planner tables on its list, and
  relies on the tables' own checks. Same pattern as `planner_state_put()`. Every one of the 32 planner tables already
  has `updated_at`, set on each change.
- **Saves happen as you go**, as now, with the state shown in the header: saving, saved, or "not saved" with a retry.
  Nothing is kept on the device (§14).
- **Photos** keep their existing functions (`site_set_airline_logo()` and the rest).

## 7. The planning library (#19)
**`lib/rules/`, TypeScript, no screen code.** It works on plain data and returns plain data.

| Part | What it works out | Replaces |
|---|---|---|
| `time` | Local and UTC times from each airport's offset (standard time all year, manual §9) | The old planner's `utcOf`, the optimiser's `off` |
| `block` | Block minutes = `block_allowance_min` + distance ÷ the type's `cruise_kmh` (manual §4) | `blockMin`; the optimiser's `block`; the report's 846 km/h formula |
| `turns` | Whether a turn fits: the type's `min_turn_min` + `turn_margin_min` | Turn checks in the old planner and the optimiser |
| `connections` | Valid connections at an airport between `mct_min` and `connection_max_wait_h`, and the check at both ends of a leg | The Hubs screen's connections; the optimiser's `conns`; the website's `findTrips` window |
| `banks` | Bank windows from `airline_bases.bank_times` and the bank settings | `bankWindows` |
| `maintenance` | Usable ground time against the need (cycles × `maint_per_cycle` + hours × `maint_per_hour`), as a share | `maintFor`; the optimiser's A321-only figures |
| `schedule` | The second-daily gap, the same-route gap, night bans, flight numbers used twice, departures per airport | The old planner's attention checks |
| `positions` | Where each aircraft is at a given moment, for the live map | The old planner's and website's map code |
| `optimiser` | The best day's schedule for an aircraft, by connections, then maintenance | `scripts/planning/plan.py`, retired |

- **Inputs:** one `Rules` object built from `rules_input(world)`, a database function that returns the rows above in
  one call. Staff can call it, and scripts through `export_for_report()` with kind `rules`.
- **For Claude and the scripts:** `node lib/rules/dist/cli.js <command> <input.json>` (block, connections,
  maintenance, check a plan card, optimise), answering in JSON.
- **For the website:** the build writes `web/assets/rules.js`, which the trip search loads. It switches to the
  8-hour rule (#19), with the window read from `site_public()`.
- **Tests:**
  - `lib/rules/cases/` holds inputs and answers, run on every pull request;
  - the old planner's saved answers (`tests/fixtures/planner_numbers.expected.json`) must come out the same where
    they cover a rule;
  - cases for figures that exist in both homes (block hours a day per aircraft, weekly departures per airport) are
    also run by a database test.

## 8. Captured figures in the database (#19)
**Functions in `public`**, each with an `as of` moment (now by default) so tests can freeze time. Staff can call them;
Claude calls them through its Supabase connection; scripts through `export_for_report()`.

| Function | What it gives | Replaces |
|---|---|---|
| `cash_forecast(airline, orders, as_of)` | Captured cash, flight profit a day, every scheduled payment for 14 days, the lowest point, and whether 0.5M stays in hand (`order_cushion`). Each order to test is counted with its own lease from 7 days after arrival (`lease_estimate_pct` for a type never leased), manual §3 | The old planner's `cashForecast`; the report's surplus |
| `airline_cards(world, as_of)` | Review's card for each airline: profit a day, per aircraft, return on fleet, payback, funds an aircraft every, fleet, flights, load, next order | Review's cards |
| `airline_profit(airline, as_of)` | Profit for each day between captures (change in cash plus that day's order payments) | Review's profit chart |
| `route_profit(airline, days, as_of)` | Each route over 1, 3 or 7 days, marked add a flight, raise fares or hold | `routeProfit` |
| `aircraft_profit(airline, days, as_of)` | Each aircraft's flight profit a day, less its lease | Review → Aircraft |
| `growth_signals(world, as_of)` | Ready for another flight, raise fares, fix or reduce, losing after their lease, from the `growth_*` and `pattern_*` settings | The Check screen's growth lists |
| `hub_progress(world, as_of)` | Each main hub's weekly departures against `hub_first_departures`, and each base's contested status from the latest world scan (`contested_rival_*`) | Growth → main hubs; hubs first (manual §3) |
| `capture_status(world)` | What the capture collected for each airline and when | Check → Capture (it read raw pages) |
| `fare_changes(airline, as_of)` | Fare changes seen in the captures, with the load before and after | Review → Fare changes |

- These are the figures #24's data views will build on; #24 itself stays a step 5 decision.
- **Tests:** in the rehearsal, each function's answer on last night's copy is compared with the old planner's on the
  same copy at the same moment. In `database/tests/`, hand-made cases cover the edges: no capture, an order never
  leased, a payment day.

## 9. The screens
Each screen is rebuilt whole, in the old planner's order of use, with the same names on screen.

| Screen | Reads | Library | Database |
|---|---|---|---|
| Home | Aircraft, legs, airports, to-dos, `job_runs`, `backup_runs` | Live map positions; attention checks (maintenance, turns, night bans, flight numbers, airport caps) | Average load; when an airline can order |
| Routes | One airline's routes, market defaults, rotations and legs | Block times; connections at both ends while editing | Loads per route |
| Tails | Aircraft and their legs | Legs a week, block hours a day, maintenance | — |
| Hubs | Legs at the hub (all our airlines), banks, connection times | Bank windows; connections; city pairs linked | — |
| Check | Aircraft checks, cabins, one day's flights; the schedule check | Game check comparison | Capture status, growth signals, hub progress |
| Review | Fare plan, manual entries | — | Cards, profit, cash forecast, route and aircraft profit, fare changes |
| Interline | Interline agreements, countries | — | — |
| Photos | Logos and photos | — | — |
| Reference | Bases and banks, aircraft types, cabins, markets, service profiles, removed routes, night bans, time zones, game schedules | — | — |

- **The look stays:** today's colours, fonts and globe, from shared styles. The world outline and logos come from
  the website's files (`web/assets/world.js`, `logos.js`), no longer embedded in the planner.
- **Phones:** every screen works at 380 px wide, and the page never scrolls sideways. Wide parts (the Hubs grid) scroll
  inside their own box.
- **Unbuilt screens** show a link to the same screen in the old planner, until they're rebuilt.

## 10. Checks
**On every pull request (*Checks*, a few minutes):** keys and passwords as now; then `npm ci`, the type check, lint,
the library's tests and the build. The old planner's checks kept running until the clean-up, which replaced them with
the screens' figures on a dated sample (below).

**In the rehearsal (now also when `app/` or `lib/` changes),** on last night's copy in a full local Supabase:
- the types are regenerated and must match;
- **side by side:** the old and new planners open at the same frozen moment, signed in as the test staff user. Every
  rebuilt screen's figures (marked `data-figure` with the same names as the saved answers) must equal the old
  planner's, and §8's functions must equal the old planner's figures;
- **real saves through `planner_save()`:** tick a to-do, move a leg, edit a plan card. Only the intended rows change,
  logged as planner with the tab; two tabs clash and the second is told; a preview address saves nothing;
- **phones:** each rebuilt screen at 380 px wide, with no sideways scroll and no errors.

The rehearsal's limit stays 30 minutes; if it nears it, the side by side moves into its own job.

*Since the clean-up (build pull request 14; spec `docs/specs/2026-10-14-clean-up.md`), with the old planner gone, what
the side by sides proved is kept without it: every screen opens on the copy at a frozen moment at 1280 and 380 px with
no errors and no sideways scroll (`tests/planner_next_test.py`); every kind of save each screen has writes exactly the
rows recorded for it in the run where every side by side last passed (`tests/planner_saves_test.py`,
`tests/fixtures/planner_saves.expected.json`); and the figures stay guarded by the library's cases, the database's
figure tests and saved answers, with the screens' own figures on a fixed, dated sample (`tests/planner_figures.mjs`).
When there are database changes, the rehearsal also backs the copy up and restores it as the nightly job does.
`tests/README.md` says what each proves.*

## 11. Rollout and the switch
1. Screens land one by one at `/planner/next/`. You can open any rebuilt screen there; the old planner stays at
   `/planner/`.
2. When every screen has passed, you use `/planner/next/` for a few days, with captures as usual.
3. **The switch,** when you say so: `/planner/*` points at the new planner, the old one moves to `/planner/old/`, and
   the planner guide is rewritten. Going back is one `_redirects` change. *Done in build pull request 13 (14 Oct; spec
   `docs/specs/2026-10-14-switch.md`) after Gitesh's trial ("all looks good"): the rules are in §3, game changes are made
   in the new planner, and the old one at `/planner/old/` was the way back only (manual §1) until the clean-up removed it
   the same day (§12): `/planner/old/` now goes (301) to `/planner/`, and there is no way back but a revert.*

## 12. The clean-up
When you're happy, a last pull request removes:
- the old planner and its checks (`web/planner/index.html`, `tests/planner_test.py`, the old real-saves test);
- the adapter (`planner_state_get()`, `planner_state_put()`, `planner_loads_get()`, `save_loads()`,
  `planner_state_version()`, `planner_item_put()`, `planner_item_delete()`) and the freeze and side-by-side functions;
- `planner_state`, `planner_loads`, `planner_meta`, `planner_data` and the renamed old tables (#13 design §3.13);
- the rule-number cross-check (`tests/rule_numbers_test.py`);
- `export_for_report('planner')`'s old-format documents, once pull request 4 has moved the scripts off them.

**Data-only changes from other chats then go through `planner_save()`** or plain SQL after the actor line (manual §1,
updated then). The removals are a file you run in Supabase's SQL editor (manual §1). Archives keep their table layout
version (#16).

*Done in build pull request 14 (14 Oct; spec `docs/specs/2026-10-14-clean-up.md`). Two database files: Claude's
(`20261014200000_clean_up.sql`: the two §16 fixes below, `loads_by_day()` for Review's Loads by hand, the website, the
investor page, the exports, the capture and `planner_data_set()` off the adapter, and the old planner's leftovers in the
data cleared: the old lists' places and delivery items in `aircraft.extra`, `plan_cards.extra.legs` and the other old
fields) and Gitesh's (`20261014200100_clean_up_removals.sql`: the tables, the view and 59 functions, behind a check that
stops it if anything that stays still names them). The planner reads neither list's places any more: Tails is the
aircraft in service, the deliveries board those with a delivery that aren't retired. The archived tables keep their
layout (the clean-up's database test compares last month's manifests).*

## 13. Build order
Each pull request gets a spec from the Building chat and goes to a fresh helper (#26).

| # | Pull request | Decision |
|---|---|---|
| 1 | **The shell:** build setup, `/planner/next/`, sign-in, previews, navigation with links for unbuilt screens, types, `planner_save()`, the new checks | #18 |
| 2 | **The planning library**, `rules_input()` and the command | #19 |
| 3 | **The captured figures** in the database (§8) | #19 |
| 4 | **Callers onto them:** the optimiser on the library; the weekly report on the database figures and tables (no surplus, no group totals, airlines from `airlines`); the website's trip search on `rules.js` | #19 |
| 5 | Home | #18 |
| 6 | Routes | #18 |
| 7 | Tails | #18 |
| 8 | Hubs | #18 |
| 9 | Check | #18 |
| 10 | Review: cards, the airline page, profit and the cash forecast | #18 |
| 11 | Review: route profit, aircraft, fare changes, fare plan, manual entry | #18 |

*Rows 10 and 11 were built as one pull request (Gitesh, 14 Oct; spec `docs/specs/2026-10-14-review.md`), with the plan
card's service check in the library. Row 12 keeps its number.*
| 12 | Interline, Photos, Reference | #18 |
| 13 | The switch | #18 |
| 14 | The clean-up | #18 |

## 14. Choices made
Claude's call, as with #13's; any of them can be changed before the merge.
1. **Same features, plus phones; nothing new until after the switch.** Keeps the comparison exact and the build
   short.
2. **Import and clear go from Reference → Data; export stays** (JSON of the tables, CSV of the legs). The nightly
   backup and per-row undo (`private.restore_row()`) are the safety net, and a whole-document import doesn't fit
   tables.
3. **No copy on the device.** A save that can't reach the database stays on screen as "not saved" with a retry;
   nothing is pushed later on its own. Stale saves from a browser overwrote captured loads (fixed 9 Oct), the device
   copy needed its own fix (10 Oct), and pushing old changes later is how newer ones get overwritten.
4. **All or nothing per action** (§6), so a frequency's two legs, or a card and its legs, never half-save.
5. **Screen order** as §13. The game is paused, so the order is about building blocks, not urgency: Home first
   because it uses the most shared parts.
6. **The new planner's files live under `/app/`** (§3), because Cloudflare's redirects would otherwise send them to
   the old planner.

## 15. What this design does not do
- **No new features** (§14, choice 1), and no world switcher until there's a second world.
- **No change to the website** beyond the trip search's rules (#20 keeps its one call).
- **No change to the capture, the jobs or the backups.** Step 5 (#21 to #25) is decided after this.
- **No change to the tables' shape** beyond what §6 to §8 need. The tables move only if a screen's spec needs it,
  with a migration and the types updated together.

## 16. Follow-ups found during the build
Kept as the old planner has them so the side-by-side figures match; each is for after the switch (§11), unless it
starts to matter sooner.

**Left after the clean-up (build pull request 14, 14 Oct), closed by the last leftovers (pull request #44, 15 Oct; spec
`docs/specs/2026-10-15-last-leftovers.md`):** the cabin an order comes with, made data (done); Ryanair's main base (kept
as it is, with the reason); Photos' city-photo and name lists, made data with the website (done). The same pull request
brought `database/current/functions.sql` back in step with the database and made its check compare each function's
definition, not only its name. Every item below is done, kept as decided ("flights today", the block-hours flag,
filing's block time, Ryanair's main base), or went with the old planner. Nothing is left open.
- **Event and load times ignore an airport's UTC correction** (`world_airports.utc_offset_override`) in the captured
  figures, as the old planner does; its schedules use it. No airport has a correction on 12 Oct, so nothing is
  affected. Found by pull request #29. *Done in build pull request 14: `private.fig_events()` and
  `private.fig_route_profit()` take the airport's offset in the world (`private.airport_offset_min()`); no figure moved
  (no airport has a correction), and with one put on a home airport in the test, its payments move by exactly that.*
- **The cabin an order comes with** is worked out from the cabin names, where the old planner kept a list in its code.
  They agree on every type today; make it data. Found by pull request #29. *Done in pull request #44 (15 Oct): each type's
  order cabin is `aircraft_types.order_config_id`, and an airline's own where it differs is a row of `airline_order_cabins`
  (Ryanair's Standard layouts, as a low-cost airline), both filled from exactly what `private.fig_order_cabin()` gave for
  every airline and type, which now reads them. No answer moved: the migration checks every pair before it commits, and
  `database/tests/order_cabins_test.sql` checks them again against the answers saved before the changes. Reference shows
  them with the aircraft types and changes them, each one `planner_save()` action.*
- **Ryanair has no main base marked** in `airline_bases`; its home falls back to `airlines.home_airport_code` (CDG),
  as the old planner does. It's exempt from hubs first, so nothing is affected. Found by pull request #29. *Kept as it is
  (pull request #44, 15 Oct): its home already falls back to CDG (`private.fig_home()`), and its hubs-first exemption is
  held by the setting `hub_first_exempt` (Ryanair's own value), not by the missing main base, so marking one would change
  nothing.*
- **The header's search box and Website button** are in the old planner's header but not yet the new one's. Add them
  before the switch, once Routes and Tails exist to search. Found by pull request #31. *Done in pull request #37 (build
  pull request 12): the search finds what the old one found, and a result opens its new screen.*
- **Which city photo each airline card shows** is a list in the Home screen's code; `airlines.photo_city` should hold
  it. With Photos (pull request 12). Found by pull request #31. *Done in pull request #37: the column existed, so the
  migration fills it where empty, and Home's cards read it.*
- **"Flights today"** counts each leg on its own UTC day in the new planner; the old one used the hub's local weekday and
  gave each return its outbound's days. On 11 Oct that was 467 against 466. The new count follows the stored legs and is
  kept. Found by pull request #31.
- **Plan cards keep a hidden copy of their legs** in `plan_cards.extra.legs` (the old planner's). The new filing deletes
  it; any later screen that edits a card's legs must delete it too. Drop it at the clean-up (pull request 14). Found by
  pull request #33. *Done in build pull request 14: cleared with the old planner's other fields.*
- **Tails' "under 10 h a day" flag** stays, though manual §4 retired the target on 7 Oct: it's now the setting
  `aircraft_block_target_h` (10), and 0 turns it off. Gitesh kept it at the merge, 13 Oct. Found by pull request #33.
- **Filing with the game's times** takes the game's block time too (flight 1069: 85 min, where the old planner kept the
  card's 80). The new figure is kept. Found by pull request #33.
- **Before the switch, from Tails:** the aircraft pop-up opens from Home only (add it to Routes), and a delivery can't
  be removed yet. Found by pull request #33. *Done in pull request #37: a frequency's aircraft on Routes opens its
  pop-up, and the deliveries board's **remove** writes what the old `deldel` writes.*
- **Regions on Hubs' connections table:** the old planner kept a country-to-region list in its code, so the new table
  counts by country ("US 5 · IN 2") where the old said "North America 7". Add a `region` column to `countries` with
  Interline and Reference (pull request 12). Found by pull request #34. *Done in pull request #37: `countries.region`
  from the old list (Europe where it named none, as its fallback; Other for the empty country), carried in
  `rules_input()`; Hubs and Check name regions again.*
- **Hubs gives some arrivals a bank they can't make:** 329 arrivals a week (mostly Ryanair at CDG and AMS; CDG 2012
  shows bank 1 though it lands 16:11 before it). Kept as the old planner has it; fix after the switch. Found by pull
  request #34. *Done in build pull request 14: an arrival is named with a bank only when it connects onto that bank's
  departures within the connection rules (`hubs.arrivalBank`), else "outside the banks"; on the 12 Oct sample exactly
  329 arrivals a week moved (`tests/planner_figures.mjs` prints the count).*
- **Check's suggested aircraft size** on route options (for example "E195", 24 options) came from a rule in the old
  planner's code (`suggestSize`), so the new Check leaves it out. Store the rule as data with pull request 12. Check's
  hub-readiness rows also need the regions above. Found by pull request #35. *Done in pull request #37: the setting
  `suggested_size` (the world's lists and Ryanair's own), read through `rules_input()`, shown again on Check.*
- **The old planner's loads table (`planner_loads`) isn't frozen,** though `docs/data.md` says it is: saving loads by
  hand in the old planner also writes its month copy, and the database copies that month back into the loads tables.
  Correct the docs, and stop the copy at the clean-up (pull request 14). Found by pull request #36. *Done in build pull
  request 14: `planner_loads` and the copy into it are gone; loads by hand are `planner_save()` rows.*
- **One rehearsal run hung in the Hubs side by side** and was cancelled at 30 minutes; the cause wasn't found. Hubs now
  runs last with a 5-minute stop, so a hang loses only its own result. Found by pull request #36. *Gone with the side
  by sides in build pull request 14.*
- **The interline rules** (the 17 countries, the Europe zone, the hub rivals, the countries each airline covers, the
  partners in Gander) were in the old planner's code; they are the setting `interline_rules` now, which Interline reads.
  Home's interline line in needs attention isn't rebuilt yet; it can read the same setting. Found by pull request #37.
  *Done in build pull request 13 (the switch): Home's line counts Interline's own rows (`screens/interline/useRows.ts`,
  shared by both) without an agreement, as the old Home did, and the Home side by side compares it.*
- **Photos' city-photo and name lists** (which city's photo an airport takes, and the name the website gives it) are
  kept in the Photos screen's code, as the website keeps them in its own; make them data with the website. Found by pull
  request #37. *Done in pull request #44 (15 Oct): one `site_content` row, `airport_cities` ({name, photo}, word for word
  the lists both kept), which `site_public()` gives as `content.airport_cities`; the website and Photos read it there and
  keep no list of their own. Nothing visible moved: with the data, the website and Photos give each of the 1,337 airports
  in `web/assets/airports.json` the name and photo they gave before (`tests/site_test.py` and Photos' unit test, against
  `tests/fixtures/airport_cities.expected.json`, recorded at 7fc2a99).*
- **The old Reference's "restore all"** sits in its section's title, which the old page strips, so the button never
  shows there; the new one works. Its **Game schedules** links are worked out from each airline's game ID and can't be
  typed (the old box's edits were lost on save since the switch-over), and Data's import and clear are gone (§14).
  Found by pull request #37.
- **Today's backup (14 Oct)** has every delivery in service and two Malaysia aircraft that tie in Review: the Home,
  Tails and Review side by sides were made to cope (a part neither Home draws, filing not tried when nothing waits, a
  tie's order). Filing is tried again on a copy with an arrived aircraft. The cards the old planner filed with the
  game's times keep the game's arrival in their copy of the legs (`plan_cards.extra.legs`) beside the old block, so
  the old card shows an arrival a minute or two before the new card's (departure plus the leg row's block); drop the
  copy at the clean-up (pull request 14), as above. Found by pull request #37. *Gone with the side by sides and the
  copy in build pull request 14.*

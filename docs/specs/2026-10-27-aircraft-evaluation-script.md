# Spec: the aircraft evaluation script — 27 Oct 2026

*From the Scheduling chat, for the Building chat. Gitesh's decisions of 27 Oct. Gitesh brings the tool's saved pages
(the form and one result) to the Building chat directly.*

## What and why
**What:** a userscript that runs the game's **aircraft evaluation tool** over a list of routes, one route after
another, and collects what the tool shows for every aircraft on each route (at least the seats that fit and the
margin %).

**Why:** the default line (manual §3) picks variants by the game's published ranges, which are at full load with each
type's maximum seats. Our cabins carry 19–41% fewer seats, and the game flies them further: 9M-AAY (KUL), an A320neo
LIGHT with 147 seats, flies KUL–Beijing (4,414 km), 20% past its published 3,690 km, with every seat sold and no cargo
cut. Across about 4,000 captured flights the game never cut seats or cargo for distance. Real ranges would move many
routes to a cheaper variant (SHARP instead of Heavy, A321neo LIGHT instead of LR or XLR: 3–9M of list price each).
The same runs also say which aircraft earns the best margin at each distance. The Scheduling chat turns the results
into a proposed new reach column for §3, a rule change for Gitesh to decide.

## How the tool works (Gitesh, 27 Oct)
- Select a route, select the aircraft (all of them can be selected at once), select the economy seat type, run.
- One run shows the analysis for every selected aircraft together.
- For the next run only the route changes; the aircraft and seat type stay as they were.

## The runs (about 520)
Built by the Scheduling chat once the input format is fixed, sorted by pass and then by distance:

| Pass | What | Runs | Seat type |
|---|---|---|---|
| 1. Distance ladder | A real pair from our route lists every 250 km from 1,000 to 16,000 km, and every 100 km within ±1,500 km of each type's published range | about 120 | by distance (below) |
| 2. Second region | Another pair at each ladder distance, in a different region, so market effects can be told apart from the aircraft | about 120 | by distance |
| 3. Real decisions | Every November trunk and each airline's top 20 openings (`competition()`) | about 200 | by distance |
| 4. Ryanair | Routes up to about 5,000 km again, Standard seats | about 80 | Standard |

**Seat type by distance** (manual §5): Leisure under 3,500 km, Leisure Plus from 3,500 to under 6,500 km, Comfort from
6,500 km. Within passes 1–3 the rows run shortest first, so the seat type changes only twice; pass 4 sets Standard once.
Each row in the list carries its seat type, and the script sets it whenever it differs from the last row's.

**Aircraft:** all 13 selected every run: E195-E2, E190-E2, A320neo SHARP, A320neo LIGHT, A320neo, A320neo Heavy,
A321neo LIGHT, A321neo, A321LR, A321XLR, A350-900, A350-1000, A350-900ULR.

## What the script does
- **Started by Gitesh and watched,** like the fares userscript (manual §5): a button in the tool's page, which shows
  how many runs are left and asks once before starting. Never on a schedule.
- **Read only:** it fills the tool's form and reads the result. It never changes anything in the game.
- **Paced:** a few seconds between runs (the fares script uses 2 seconds), so it doesn't load the game's servers.
- **Stop and resume:** a Stop button throughout; run again, it carries on from the first route without a result. A
  page reload carries on too.
- **Stops at the first problem** and says which route and why (a route the tool won't take, a page that doesn't read).
- **Keeps everything the result shows** for each aircraft, not just seats and margin (the raw row as well as the
  parsed fields), so nothing needs re-running if another figure turns out to matter.

## Where the run list comes from and the results go
The Building chat's choice. Suggested, following the fares script's pattern (`capture_fare_actions()` with the capture
key): the run list in a table, read by the script through a function with the capture key, and results written back
through another, so the Scheduling chat reads them straight from the database. A new table grants its own access
(manual §1). A CSV in and out is the simpler fallback if that's much more work.

## Checks
- Gitesh's saved pages (the form and one result) become test fixtures, and the script's reading of them is checked on
  every pull request like the other userscripts (manual §1, automatic checks).
- The usual: documents updated in the same pull request (map, planner guide if it touches the planner,
  `scripts/README.md` or the userscript's notes, `database/current/` for a new function).

## Rules this touches
- **Manual §9 (Gander is an exclusive world)** lists the scripts allowed there. This one would be added; it's read-only,
  like the world scanner. That's a rule change for Gitesh to agree when the pull request is ready.

## Out of scope
The analysis: the Scheduling chat reads the results and proposes the new reach column and any variant changes.
The 151-run workbook of 27 Oct (`aircraft-range-tests.xlsx`, one row per route and aircraft) is replaced by this list.

---

## The Building chat's design (27 Oct, from Gitesh's saved pages)
*Added by the Building chat once the tool's pages were in. The helper builds this; where this section and the text
above differ, this section wins.*

### What the pages show
The saved pages are `tests/fixtures/aircraft_eval_form_2026-10-27.html` (JFK to SGN selected, no aircraft added) and
`tests/fixtures/aircraft_eval_result_2026-10-27.html` (JFK to SGN, three types added, Comfort applied). Both are
scrubbed to the tool's own part of the page; the game's header, footer, scripts and our userscripts are left out (the
saved originals held the capture key, so they never go into the repository).
- The tool is `/app/aircraft/evaluation`, a stateful page (Wicket): its address carries a page version (`?134`,
  `?138`) and each form's `action` is tied to it (`./evaluation?138-6.-aircraft.eval.route.form`). Three plain POST
  forms, no AJAX:
  - **the route form** (`…-aircraft.eval.route.form`): `from:phrase` and `to:phrase`, typed codes the game resolves.
    After it, both boxes hold the airports' names and the `h2` reads "Evaluation for route from New York John F.
    Kennedy to Ho Chi Minh City Tan Son Nhat". **Nothing else can be set until a route is selected** (Gitesh): on the
    first page there is only this form.
  - **the add form** (`…-evaluation-add`): `types`, a multiple select. **Its option values are positions in the list,
    not type ids, and shift as types are added** (the A350-900 is 73 on the form page; types already in the table are
    left out of the list). So types are always matched by their text, and values read from the latest page.
  - **the settings form** (`…-evaluation-settings`): `age` (0 to 24), `serviceClass` (Economy 2, Business 1,
    First 0), `seat` (Standard 101, Leisure 102, Leisure Plus 103, Comfort 104, and others), `priceFactor` (50 to
    200). Read the values from the page by the option's text; never hard-code them. A change shows only after
    **Apply settings** (Gitesh's screenshots: the table kept the Standard figures until it was pressed).
- **The table** (`table.aircraftEvaluation`): one row per type added, kept from route to route. The first cell links
  the type (`../../action/enterprise/aircraftsType?id=3921`: the game's type id) and holds a remove link. Then either
  one cell `colspan="17"` reading "This type cannot operate on the selected relation." or 17 cells: flights per week
  (`6.00`), available seats (`377`), fuel, aircraft handling, ATC, landing fees, maintenance, capital cost, crew, fixed
  costs total (numbers with thousands commas), per seat (`539 AS$`), and six profit cells at 50%, 60%, 70%, 80%, 90%
  and 100% load, each an amount and a margin (`-30,422 (-17%)`). With no types added it holds one row, "Please select
  the aircraft types you wish to compare."

### The types
The 17 Gitesh selected (the spec's 13 plus the A321neo Heavy and Medium and the A321XLR Heavy and Light), by the
tool's own names: Airbus A320NEO, A320NEO Heavy, A320NEO Light, A320NEO SHARP, A321LR, A321NEO, A321NEO Heavy,
A321NEO Light, A321NEO Medium, A321XLR, A321XLR Heavy, A321XLR Light, A350-1000, A350-900, A350-900ULR, Embraer 190
E2, Embraer 195 E2. They're a `settings` row (`aircraft_eval_types`, a JSON list of those names, world-level), so the
Scheduling chat can change them without a code change; the run list's function hands them to the script.

### The database (one migration)
- **`aircraft_eval_runs`**, the run list the Scheduling chat fills: `world_id`, `pass` (1 to 4), `seq` (the order,
  unique in the world), `from_code`, `to_code` (IATA), `distance_km` (optional, for the Scheduling chat), `seat` (the
  tool's text: Standard, Leisure, Leisure Plus or Comfort; checked), `note`; and the result's header, written by the
  script: `from_name`, `to_name` (as the tool resolved them), `settings` (jsonb: the age, class, seat and price factor
  the page showed), `done_at`. Unique on (world, from, to, seat).
- **`aircraft_eval_results`**, one row per run and type: `run_id`, `type_name`, `game_type_id`, `can_operate`,
  `message` (the cannot-operate text), the 11 figures as numbers (`flights_week`, `seats`, `fuel`, `handling`, `atc`,
  `landing`, `maintenance`, `capital`, `crew`, `fixed_total`, `per_seat`), `profit_50` to `profit_100` and
  `margin_50` to `margin_100`, and `cells` (jsonb: every cell's text as the page showed it). Primary key (run, type).
- **`capture_eval_runs(p_key)`**: with the capture key (`private.capture_key_world()`, as `capture_fare_actions()`),
  `{ok, world, types, total, done, runs}`: the runs without a result, in `pass`, `seq` order, each `{id, pass, seq,
  from, to, seat}`. A bad key answers `{ok:false, error:"bad key"}`.
- **`capture_eval_result(p_key, p_run, p_doc)`**: saves one run's result. Refuses (ok false, saying why) a run not in
  the key's world, a doc without one row for each of the `aircraft_eval_types`, or a figure that isn't a number. Saves
  rows for extra types in the table too. Replaces any earlier result for that run (a run saved twice is no harm), sets
  `done_at`, answers `{ok, done, total}`.
- Both `security definer`, `search_path ''`, execute for `anon` and `authenticated` (as `capture_fare_actions()`).
  Descriptions on both tables, every column worth one, and both functions. Grants per manual §1 ("a new table grants
  its own access") and whatever the rehearsal's access checks require; staff read is enough, and nothing for the
  website. A database test covers the key, the order, a save, a re-save, a missing type refused and `done_at`.
- **The Scheduling chat writes the run list** with plain SQL (manual §1's actor line) and reads the results as
  postgres. Not part of this build.

### The userscript: `capture/aircraft_eval.user.js`
- `@match https://gander.airlinesim.aero/app/aircraft/evaluation*`, the key `__CAPTURE_KEY__`, the same anon key and
  RPC address as the fares userscript. Built like `fares_apply.user.js`: the page logic as plain functions over the
  page's HTML, handed over as `eqEval` when there's no page, so a Node test runs the same file.
- **One button on the tool's page, "Aircraft evaluation".** It reads the run list and asks once in its panel ("212
  runs left of 520, about 15 minutes. Leave this tab open and watch; Stop is here throughout. It only reads the tool:
  nothing in the game changes."), Go ahead or Cancel. No browser dialogs.
- **Each run, all by `fetch` with the session's cookies, no page loads** (the tab stays where it is; always use the
  form actions of the latest page fetched, never an older one):
  1. POST the route form with the two codes. The answer must have the `h2` and both boxes holding names (not the
     typed codes); else stop: "the tool didn't take LGW to CAI".
  2. If any of the 17 types isn't in the table, POST the add form with those types' values, read by text from that
     page's add list; read again, and stop naming any still missing. Extra types in the table are left there.
  3. If the page's settings aren't age 0, Economy, price factor 100% and the run's seat, POST the settings form with
     those (values by text). Read again; stop if they didn't take. The first run sets them; after that only the two
     seat changes and pass 4's Standard do.
  4. Read the table: a row for each of the 17, each either "cannot operate" or 17 cells that read as numbers. Else
     stop: "the result didn't read" with the type.
  5. Send it to `capture_eval_result()`; stop on anything but ok.
  6. 2 seconds, then the next run (`PAUSE_MS`, as the fares script). Half a second between the POSTs inside a run.
- **The panel**: progress ("Run 37 of 212: LGW to CAI, Leisure Plus · 14 can fly"), Stop throughout, and at the end
  how many runs were saved and, if it stopped, which run and why. **Stop and resume**: run again, it reads only the
  runs without a result. **A reload carries on**: a run in progress is noted in `sessionStorage` and picked up after a
  reload unless it's been idle over 3 minutes, as the fares script does.
- **Read only**: the script sends only the tool's three forms. It never opens another page of the game.

### Checks and documents
- `tests/aircraft_eval_userscript_test.mjs`, in `tests/run_all.sh` and `tests/README.md`, on the two samples: the
  three forms and their actions read from each page; the form page's empty table read as no rows; the result page's
  three rows (the A350-900's 17 figures exactly: 6, 377, 64,305 … 539 and the six profits and margins, −30,422 and
  −17% to 143,458 and 41%; the A321NEO Light and Embraer 195 E2 as cannot operate with the game's type ids 3155, 3921,
  20260); the route `h2` names; the settings as selected (Comfort, 104); the add list matched by text and the missing
  types worked out (on the form page all 17 are in the list; on the result page the three added are not); the three
  POST bodies built from the page's own field names and values (the add form with several `types`); a missing type
  and a page without the table refused; `capture_eval_runs()`'s answer read and its errors; the panel's words.
- Documents in the same pull request: the map (the parts table, how data moves, which call answers which question,
  the keys table, when something breaks), the README's `capture/` line, `database/current/`. The table guide is
  regenerated by the rehearsal.
- **Not in the pull request:** the manual's §9 sentence listing the scripts allowed in Gander. That's a rule change
  the Building chat puts to Gitesh when the pull request is ready, and commits directly once he agrees.

### A note for the analysis (27 Oct, after the first 14 runs)
"Cannot operate" isn't always range. Each type has route restrictions by airport size (0–10) on its type page, and
among our families only the E190-E2 has one: it can't fly between two size-10 airports (Gitesh, from the game). The
first runs showed it refused on PVG–NRT, PVG–KMG, DEL–DXB and KUL–CAN (1,796–2,613 km) while flying longer routes,
and B-0360 (PVG) flies PVG–Penang (3,648 km) in the game. So an E190-E2 "cannot operate" between two very big
airports says nothing about its reach. Under the default line it never meets this: a size-10 destination is 5 stars,
which takes the A320neo, A321neo or XLR (manual §3).

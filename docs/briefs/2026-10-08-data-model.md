# The planner's data in proper tables — 8 Oct 2026 (decision #13)

**Decision:** whether the planner's own data moves out of one big JSON row into proper database tables with a cleaner
model (stable IDs, UTC times, one row per flight leg), and how.
**Recommendation:** C. Proper tables with the clean model now, while the current planner keeps working unchanged
through two database functions (an adapter). That fixes the fundamentals at the cheapest moment it will ever be: 87
aircraft, 17 days of data, one user. It also avoids rewriting the old planner, which #18 replaces anyway. The build
starts once the rest of Step 3 (#14 to #17) is decided, since those shape the tables.

*Columns adapted for a non-game decision. All four options cost $0 in money: the database is 21 MB of the free plan's
500 MB.*

| Option | What you get | Effort | Risk | Easy to undo? |
|---|---|---|---|---|
| A. Keep the one row, add a safety net | A copy of the row on every save, so a bad save can be undone | 1 small pull request | The model stays as it is: flights rebuilt seven ways, names as keys, the return-day guess. History is whole 194 KB copies. #15, #18 and #24 all build on it | Yes |
| B. Split the row by area | One document each for aircraft, flights, plans, to-dos and so on: smaller saves, fewer clashes | About 2 pull requests | Same messy model inside each piece. A half step that gets redone later | Yes |
| **C. Proper tables now, old planner via an adapter** | **One copy of everything; stable IDs; UTC times; one row per flight leg; settings as data. Website, scripts and checks all read the same flights. History (#15) and ready-made views (#24) become simple. #18 starts on clean tables** | **About 5 pull requests: a design for approval, then tables and data, adapter, website and scripts, clean-up** | **The adapter must hand the old planner exactly what it reads today. Tests compare old and new on saved data, and the rehearsal tries it on a backup first** | **Yes. The old row stays, frozen, as a fallback until #18 is done** |
| D. Tables during the planner rebuild (#18) | No adapter: each screen gets its tables when it's rebuilt | Spread over #18 | Two sources of truth for months, kept in step by hand. History, views and scripts wait for the last screen | Hard midway |

## Background
**How the data is kept today** (live database and the repository, 8–9 Oct):
- **One row holds the planner's own data:** `planner_state`, 194 KB of JSON in 20 sections. It holds:
  - 87 aircraft and 235 rotations;
  - 41 plan cards and 59 deliveries;
  - 37 to-dos, 101 spending entries;
  - settings: 26 hubs, 43 markets.

  It started on 22 Sep. Nothing is ever pruned.
- **Loads** are a second copy: one JSON document per month in `planner_loads`, built from the capture's `game_loads`
  rows (935 rows since 6 Oct).
- **Route research** (4,438 routes and 1,337 airports, 469 KB) is a third JSON blob in `planner_data`.
- **Every edit re-uploads the whole 194 KB row** (planner code, `save()` and `cloudWrite()`).

**What goes wrong with one row:**
- **Overwrites.** The overwrite safeguard reloads instead of saving over newer data, but the click that hit it is
  lost. The check and the save are two separate steps, and the database accepts whatever arrives.
- **A live bug of the same kind, in loads:**
  - the capture adds new days to a month's loads document without updating its saved time;
  - a browser that has saved that month itself (manual entry) then keeps its own older copy;
  - its next save can overwrite captured days.

  This is separate from this decision and can be fixed on its own.
- **No history.** A bad save replaces the only copy, apart from last night's backup.
- **Unknown fields get dropped** when the planner saves. That once wiped the growth rules.
- **One question needs the whole document.** The website converts the whole row on every visit (`site_public()`).
  Reports unpack the whole document first (`export_for_report`). The database can't join flights to route profit.

**What's messy inside it:**
- **No flight is stored as a flight.** A rotation is one entry: outbound and return on one aircraft, with weekdays for
  the outbound only. Flights are rebuilt from it in seven places:
  - five in the planner;
  - one in the website (`web/assets/site.js`);
  - one in the optimiser (`scripts/planning/plan.py`).

  They don't agree:
  - the website gives the return flight the outbound's weekdays even when it leaves the next day;
  - the optimiser ignores weekdays altogether.

  That's harmless today because 233 of 235 rotations fly daily, but it breaks as soon as that changes.
- **Times are local "HH:MM" text.** The return's day is guessed, a return more than 24 hours later can't be stored,
  block time isn't stored, and the planner's "today" is the browser's date while the capture uses UTC.
- **Names are the keys:**
  - an airline's display name ("Pan American");
  - a route as "Airline|HUB|DEST";
  - an aircraft as its registration.

  Renaming an aircraft only partly carries through. Flight numbers are a mix of text (228) and numbers (7).
- **The same data in several places:**
  - delivered aircraft stay in deliveries after they become tails (44 of 59);
  - plan cards repeat the schedule once flown;
  - connection times are stored twice;
  - airports exist three times;
  - cash and next-7-day costs are worked out from the capture and then stored again.

**What the move touches:** the word `state` appears on 218 lines in 87 functions of the planner, plus two database
functions that read single sections, one export, the website and two scripts. That's why C keeps the old planner on an
adapter instead of rewriting it, and why #18 then replaces it screen by screen.

**What Gitesh said when the foundation plan began:** this "can scale into a huge thing in the next 10 years", and he
doesn't want to redo the fundamentals in two years; they should be clean. Before that, a table split had been set aside
as more than a game needed. The foundation plan replaced that view.

## What the clean model would hold (C)
Details go in a design document for approval before any table is built. In outline:
- **Who and where:** airlines (by code, not display name), airports (one list instead of three).
- **Fleet:** aircraft with a stable ID (registration becomes a field), and orders that move from ordered to delivered to
  in service, instead of separate delivery and tail lists.
- **Network:**
  - routes: research, added and removed in one table, with a status;
  - flight legs: one row per flight, with number, aircraft, from, to, weekdays, departure and arrival in UTC, and block
    time. Local times are worked out for display.
- **Plans:** plan cards and their legs as rows, linked to the aircraft.
- **Work:** to-dos and their items, the growth log, the spending log, the fare plan, interline status, cabin decisions.
- **Settings as data:** hubs and banks, connection times (one copy), markets and fares, cabins, curfews, and the
  growth-rule thresholds that sit in the code today.
- **No longer stored:**
  - the cash and next-7-day copies, which become views over the capture tables;
  - the monthly loads documents: loads stay as `game_loads` rows, with manual entries as rows too, which removes the
    loads bug at its root.
- **The adapter:** one function builds today's JSON from the tables for the old planner, and one splits its saves
  back into the tables. Old and new are tested against each other on the saved sample.

**Decided separately:**
- #14: world, group and airline keys, so other players' airlines could fit;
- #15: keeping every change;
- #16: how long detail is kept;
- #17: the database plan;
- #18: the new planner's framework.

## Scenarios and the risk of waiting
- **C goes well:** after about five pull requests, everything reads from the same tables. The weekly report and the
  scripts stop unpacking JSON, the website stops converting the whole row, and #15, #18 and #24 build on it directly.
- **C goes badly** (the adapter doesn't round-trip cleanly): the tests catch it before merge. The old row stays in
  place, and switching back is one revert.
- **A or B now:** cheap today, but the move to tables still has to happen before #18 can build on anything clean. The
  work is then done twice, on more data.
- **Waiting:** every week adds aircraft, rotations and logs to migrate (about 7 spending entries a day, about 6 KB of
  loads per captured day). Migration code is the same size either way, but checking the moved data takes longer. The
  rebuild (#18) can't start on a clean base until this is done.

## What would change the recommendation
- **If the planner rebuild (#18) were dropped:** C still makes sense, but the old planner would need rewriting onto the
  tables in the end, rather than an adapter that #18 retires.
- **If the adapter proves hard on a few sections** (for example the growth screens): move those few with D during #18
  and do the rest with C.
- **If you'd rather keep it light** after all: A, plus the loads fix, is a safe minimum. It just leaves the
  fundamentals as they are.

## Sources
- Live database, 8–9 Oct: `planner_state`, `planner_loads`, `planner_data` and `game_loads` contents and sizes;
  database size.
- Repository: `web/planner/index.html` (`save()`, `cloudWrite()`, `loadLoads()`, `computeFreq`), `web/assets/site.js`
  (`derive()`), `scripts/planning/plan.py`, `database/current/functions.sql` (`apply_loads_from_capture`,
  `site_public`, `export_for_report`).
- Supabase pricing (free plan: 500 MB database): https://supabase.com/pricing
- The chat where the foundation plan began ("MAIN OLD").

## Outcome
Open: waiting for Gitesh's decision.

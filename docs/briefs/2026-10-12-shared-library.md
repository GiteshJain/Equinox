# One home for each calculation — 12 Oct 2026 (decision #19)

**Decision:** where the calculations live (block times, turns, connections, maintenance, the cash forecast, route
profit, growth signals, hub progress), so the planner, the website, the scripts and Claude in every chat get the same
answer.

**Recommendation:** D. Each calculation gets exactly one home, picked by a simple test:
- **Calculations used while editing a plan** go in one TypeScript library: block times, turns, connections at both
  ends, bank windows, maintenance, the second-daily gap and night bans. The new planner uses it instantly as you
  edit. The website's trip search, the optimiser and Claude use the same code.
- **Figures worked out from what the capture recorded** go in the database: the cash forecast (with orders to test as
  an input), route profit, growth signals and hub progress. The planner, the report scripts and Claude in any chat read
  the same rows.

The numbers stay in `settings` and `world_rules` for both. It's about three pull requests, built as step 2 of #18's
rollout. $0 a month.

*Columns adapted for a non-game decision.*

| Option | Where each calculation lives | Effort | Risk | Easy to undo? |
|---|---|---|---|---|
| A. No library | Each copy stays where it is, each reading `settings`, with a test per copy | Least: a test per copy | Every rule change means finding every copy. The weekly report still uses the surplus rule five days after it was retired (below) | Yes |
| B. One TypeScript library for everything | The planner and website import it. Claude and the scripts run it as a command. The cash forecast too, after downloading the captured data it needs | About 3 pull requests | The money figures need the raw captured data fetched first, by the planner, Claude and every script; the command needs database access of its own | Yes |
| C. Everything in the database | One SQL function per calculation; every caller runs a query | About 3 pull requests | Each edit in the planner waits on a database call, and nothing can be checked offline. Connection searches and maintenance windows are awkward in SQL | Yes |
| **D. Split by use: planning rules in TypeScript, captured figures in the database** | **Editing rules in one library; captured figures as database functions. One home each, never two** | **About 3 pull requests** | **Two places to look, though the test above says which. A shared set of test cases checks both** | **Yes** |

## Background

### Where the calculations live today
From the repository (12 Oct) and the live database (12 Oct).

| Calculation | Copies | Agree? |
|---|---|---|
| Block time | Planner; optimiser (`plan.py`); weekly report (`analyze.py`) | No. The report uses distance ÷ 846 km/h + 27 minutes for every type. The rule is 25 minutes + distance ÷ the type's speed (840 for the A321neo) |
| Connections | Planner; optimiser; website trip search (`site.js`) | No. The website allows up to 10 hours between flights; the rule (`connection_max_wait_h`) is 8 |
| Maintenance | Planner; optimiser | Only for the A321neo. The optimiser uses the A321neo's figures for every type |
| Rule numbers in the optimiser | Speeds, the 25-minute allowance, maintenance, the 3-hour gap and the 8-hour wait typed into the code | Equal to `settings` today, but a change there wouldn't reach it. It drifted once already: the 10-minute buffer, fixed 9 Oct |
| Cash forecast | Planner only, inside its screen code | Claude has to re-create it from the planner's code to recommend an order in a chat |
| Cash available | Weekly report (`analyze.py`, `build.py`) | No. It still uses the surplus rule (cash − 7 days' fixed costs − spending) and group totals. Both were retired on 7 Oct; the manual says never to use the surplus figure |
| Our airlines | The report scripts list the six by name | #14 says nothing may assume six |

The database already holds the numbers (`settings`, `world_rules`, `aircraft_types`) and every planned leg with its
times. Its functions store and report, but don't calculate any of these rules. The daily history (`route_days`, #15)
already holds route profit per day.

The weekly report is paused with the game (manual §1), so the surplus figure does no harm today. It must be fixed
before the report runs again.

### Why split by use
- **Editing needs instant answers.** When you move a departure time in the new planner, the connections at both ends,
  the turns and the maintenance share should update as you type. That's code running on the page (TypeScript), not a
  database call each time.
- **Captured figures need the captured data.** The cash forecast reads the latest balance, the last day's flight
  profit, the scheduled lease payments and the week-end closings, all in the database. Worked out there, the answer is
  a few rows. Worked out anywhere else, every caller first downloads the raw rows (today the planner pulls 9 days of
  loads and 8 days of flight money on every opening, about 1 MB, partly for this).
- **Claude can reach both.** The database through the Supabase connection it already uses; the library by running it
  from the repository in its workspace. The number that decides an order is then the same in the planner, the
  Scheduling chat and the weekly report.
- **Reports need no formula at all for flown or planned flights:** each leg's times are stored (#13), so block hours
  are the sum of the legs. The block-time formula is only needed for a leg not yet planned.

### What D would build
Step 2 of #18's rollout, in about three pull requests:
1. **The planning library** (`lib/rules/`, TypeScript): the rules moved out of the old planner's code. It reads its
   numbers from `settings`, `world_rules` and `aircraft_types`, with tests against today's saved answers. It comes with
   a small command for Claude and the scripts.
2. **The captured figures in the database:** the cash forecast (orders to test as an input, each with its own lease
   from 7 days after arrival, manual §3), route profit, growth signals and hub progress towards 750. Each is checked
   against the old planner's saved answers on the test sample.
3. **Everyone onto them:**
   - the optimiser rewritten on the library (it's 69 lines);
   - the weekly report reading the database's forecast instead of the surplus, with no group totals and our airlines
     from `airlines`;
   - the website's trip search using the library's connection rule.

**One set of test cases** (inputs and answers in a JSON file) checks the library and the database the same way, so
a change in one place can't quietly differ from the other.

**A smaller point inside D:** the website's trip search would use the 8-hour rule. If you'd rather readers see longer
connections, that becomes a setting of its own.

## Scenarios and the risk of waiting
- **A rule changes later** (the cushion, a turn margin, the connection window): one row in `settings`, or one function
  in its one home. The planner, the scripts and Claude all follow, and the shared test cases show the change.
- **A calculation moves and gets a number wrong:** the saved answers from the old planner catch it on the pull request.
- **Waiting:** #18's step 2 is this decision, so the new planner's screens wait on it. With the game paused, waiting
  costs build time, not cash. The report's surplus figure stays wrong until this is built.

## What would change the recommendation
- **If you want the new planner to work fully offline:** move the cash forecast into the library too, accepting that it
  downloads the captured data first (B for that part).
- **If you'd rather everything sat in one place, whatever the speed:** C, with each edit in the planner waiting on the
  database.
- **If the scripts were being retired:** the library alone (B) would do. They aren't: the weekly report, gander monthly
  and the scan stay.

## Sources
- Repository `GiteshJain/Equinox`, `main` (12 Oct): `web/planner/index.html` (`makeModel`, `blockMin`, `cashForecast`),
  `scripts/planning/plan.py`, `scripts/report/analyze.py` (block hours at line 123, surplus at line 140),
  `scripts/report/build.py` (surplus tiles and table), `web/assets/site.js` (`findTrips`, the 10-hour window at line
  298), `scripts/README.md`, `docs/data.md` (`route_days`).
- Live database, 12 Oct: `settings` (`connection_max_wait_h` 8, `block_allowance_min` 25, `second_daily_gap_h` 3,
  `order_cushion` 500,000); `aircraft_types` (A321neo 840 km/h, maintenance 27.6 minutes a cycle and 1.7 an hour;
  other types differ).
- Operating manual §1 (one source for rule numbers), §3 (the cash forecast; the surplus rule retired 7 Oct), §4
  (block time, connections); decision #14 (nothing assumes six airlines).

## Outcome
12 Oct 2026: Gitesh chose **D**, with the website's trip search on the 8-hour rule. Recorded in `docs/decisions.md`
and the manual's *Decided, not yet built*.

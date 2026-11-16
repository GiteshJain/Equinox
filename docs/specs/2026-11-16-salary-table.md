# Spec: the salary table (the capture stores salaries and the country averages; the planner flags any position off target)

To-do 245 (decided by Gitesh, 15 Nov, in the Main chat; brief `docs/briefs/2026-11-15-salaries-unattended.md`,
its Outcome). Lowering by hand is to-do 246. Read `CLAUDE.md`, the map's rows for the capture, the unattended capture,
the captured figures and the planner (and their files in `docs/map/`), manual §1 (new tables, stored figures, rule
numbers) and §7 (the capture; salaries), and the salary step in `capture/capture_all.user.js` first.

**Status: decided and built.** Gitesh decided every choice on 16 Nov, 08:59 to 09:04 India time (in the Main chat; the
outcomes are at the bottom, each under its choice). Built in one pull request on branch `build-245-salary-table`:
capture 1.18, migration `20261116100000_salary_table.sql`, the Salaries board on Systems and one item on Today. Manual
§7's salary rule is replaced in the same pull request.

**Built differently from the draft, and why:** the four tables give staff no access (the draft had staff read, and
staff write on `salary_positions`): the planner reads only the stored `salary_table` answer, so nothing needs more
(manual §1, "exactly what the planner needs"), and no screen edits the mapping yet. Reads older than 90 days are deleted
by the capture's own salaries call, not by the clean-ups job, so the job and its test are unchanged. The salary table
is not added to `export_for_report()`: no report section reads it yet.

## What it does, in one paragraph
The capture keeps setting salaries exactly as manual §7 says (a position below its country average goes to the
average plus `settings.salary_above_average_pct`, 5%; never lowered). After that step, for each airline, it also
sends the database what it saw: every position on the game's Employee overview page (staff, salary, next week's
salary, the page's own country average) and the airline's country page (each position's average). The database keeps
them. After each capture the stored figures work out a salary table for each airline: our salary, the country page's
average, the target (that average plus 5%) and the difference. A position more than `settings.salary_flag_pct` (1%)
under or over its target is flagged. The capture never lowers a salary; Gitesh lowers by hand (to-do 246).

## 1. What was found (16 Nov)
- **The country page opens without signing in.** `https://gander.airlinesim.aero/action/info/country?id=<n>` answered
  200 for ids 1 to 195 (196 to 260 had no country), read from here 16 Nov 02:55 to 03:05 UTC. Its heading is
  "Country information for India (IN)", so each id carries its ISO code. Its average salaries are a table of two-cell
  rows, "Narrow-body pilots | 1,794 AS$". Saved as `tests/fixtures/country_IN_2026-11-16.html` (India, as served).
- **The ids we need** (from those headings): USA (US) **182**, India (IN) **61**, United Kingdom (GB) **54**, China (CN)
  **30**, Malaysia (MY) **97**, Ireland (IE) **65**. For Ryanair's possible countries: France 47, Germany 35, Italy 68,
  Netherlands 118, Spain 154. **Not found:** which country the game registers Ryanair in (manual §2 lists only focus
  cities in France, the Netherlands, Spain, Italy and Germany). `airlines.country_code` holds each airline's country,
  but its values were not read from here (the live database is out of reach for this worker).
- **The positions each page lists (16 Nov):**

| Country page (id) | Positions | Pilot rows |
|---|---|---|
| India (61) | 16 | Regional Jet 1,220, Narrow-body 1,794, Wide-body 1,610 |
| USA (182) | 17 | Prop 980, Regional Jet 1,190, Narrow-body 1,443, Wide-body 1,822 |
| United Kingdom (54) | 16 | Regional Jet 1,213, Narrow-body 1,422, Wide-body 1,610 |
| China (30) | 17 | Prop 980, Regional Jet 1,472, Narrow-body 1,492, Wide-body 1,644 |
| Malaysia (97) | 15 | Regional Jet 1,250, Narrow-body 1,508; **no Wide-body row** |
| Ireland (65) | 16 | Regional Jet 1,306, Narrow-body 1,859, Wide-body 2,305 |

  The thirteen other positions are the same on every page: Pursers, Flight attendants, Station Managers, Check-in
  agents, Ramp agents, Cargo controllers, Fleet management, Flight planning, Customer service, Administration, Network
  Planning, Ground handling, Logistics. (The game writes "Wide-body Pilots" with a capital P.)
- **The Employee overview page already shows a country average** in its own column (manual §7; `readSalaryPage()`
  reads it as `avg`, and the capture sets salaries from it). On Kingfisher's saved page (9 Nov) it matches the India
  country page of 16 Nov where the figure hasn't moved (wide-body pilots 1,610, station managers 1,400, ground handling
  720) and differs where it has (narrow-body pilots 1,699 on 9 Nov, 1,794 on 16 Nov). So the two are very likely the
  same figure; **not confirmed** on two reads at the same moment. This build stores both, so the first evening shows it.
- **The names differ only for pilots.** The Employee overview names pilots by aircraft family ("EMB-170 / -175 / -190 /
  -195", "A318 / A319 / A320 / A321", "A330 / A340 / A350"); the country page by class ("Regional Jet pilots",
  "Narrow-body pilots", "Wide-body Pilots"). Every other position has the same name on both. Only Kingfisher's three
  family rows are known (its saved page); the other airlines' family rows are not in the repository.
- **The unattended run never reaches the salary step:** `capture_airlines()` answers `salary_above_average_pct` null
  for its key (`unattended_salaries` false), and with null the script logs "left alone" and moves on without reading the
  page (`salaries()` in the script). Reading on that run needs a new answer (choice 3).

## 2. The capture (version 1.18)
- **Still sets salaries as today.** `runSalaries()` is unchanged in what it sets and when.
- **Then reads and sends** (each airline, after its salary step, Gitesh's press; on the unattended run only if choice 3
  says so):
  1. The Employee overview page as it stands after the step (the page `runSalaries()` already reads again after a
     change; read once more when nothing was changed is not needed: the first read is used). For each position:
     its name as the page shows it, its group (Flight crew, Cabin crew, Ground crew: the heading rows above it),
     employed, active and required, salary per employee, next week's salary (the box), the page's country average, and
     whether the capture raised it this run (and to what). `readSalaryPage()` grows these fields; its present fields
     stay.
  2. The airline's country page, `/action/info/country?id=<id>` with the id `capture_airlines()` gives for the airline
     (§3), by `fetch` (no sign-in needed, but the game session is sent as for any page), half a second after the
     Employee overview. Read: the heading's name and ISO code, and each two-cell row ending in "AS$". A country two of
     our airlines share is read once a run.
- **What it sends:** one `capture_ingest()` call per airline, page kind **`salaries`**, page address the Employee
  overview's, rows one JSON object: `{ overview: { rows: [...], error? }, country: { id, name, code, averages: [{ position,
  avg }], error? }, raised: [...], stuck: [...] }`. A page that doesn't read is sent with its error (as the fleet pages
  are), never skipped silently.
- **Never in the way:** as today, nothing in the salary step stops the capture, counts as a failed page, or holds back
  the world scan or the market pages. A refused `salaries` call is a panel line.
- **The panel:** today's line plus the comparison's count, e.g. "Kingfisher · salaries: all at or above the average;
  stored, 2 off target". (The count comes from the reply, §4.)
- **The version:** `@version` and `VERSION` 1.18; `@name` unchanged; the shared key-and-version block identical in the
  three scripts (`tests/userscript_key_test.mjs`). The description line and the head comments say what 1.18 adds.

## 3. Each airline's country id
- **Kept on `airlines`:** a new column `game_country_id integer` ("The game's country id for the airline's country,
  the id in `/action/info/country?id=`; the salary table's country page, spec 2026-11-16-salary-table"). A per-world
  column, since the game's ids were checked in Gander only.
- **Filled by the migration** by a stable key: the world whose `game_host` is `gander.airlinesim.aero` and each
  airline's `game_id`: Pan Am 114 → USA 182, Kingfisher 113 → India 61, Ryanair 112 → Ireland 65 (Gitesh, 16 Nov),
  Virgin Atlantic 203 → United Kingdom 54, China Eastern 208 → China 30, Malaysia Airlines 210 → Malaysia 97.
  `airlines.country_code` is null for all six (the live database, read by the Main chat 16 Nov), so it couldn't be the
  key; whether to fill it is outside this build.
- `capture_airlines()` gives it with each airline (`country_id`); null means "no country page" and the table says so.
- Not chosen: reading the id from a game page each run. The airline's own pages need signing in to check from here,
  and the id never changes.

## 4. The database
**Tables** (each with a description, and grants exactly as below; `public` gives nothing by default, manual §1):
- **`salary_reads`**: one row per airline per capture: `world_id`, `airline_id`, `raw_id` (the `game_capture_raw`
  page), `read_at`, `unattended` (which key), `country_id`, `country_code`, `overview_ok`, `country_ok`, `note`. Staff
  read (select for authenticated). Written only by the capture's functions.
- **`airline_salaries`**: one row per position per read: `read_id`, `position` (the game's name), `crew_group`,
  `employed`, `required`, `salary`, `salary_next`, `overview_avg`, `raised_to` (null when not raised). Staff read.
- **`country_salaries`**: one row per position per country page read: `read_id`, `country_id`, `position`, `avg`.
  Staff read.
- **`salary_positions`**: how an Employee overview name maps to a country page name, per world: `world_id`,
  `overview_name`, `country_name`, `note`. Seeded with the three known pilot rows (§1); every other position maps to
  itself without a row. Staff read and write (the planner's Reference screen can edit it later; no screen in this
  build). A pilot family with no row is **unmapped**: the table shows it with no country average and says so; it is
  never guessed from its numbers.
- **Kept:** reads are small (six airlines, about 17 positions, a few runs a day: about 300 rows a day). The existing
  clean-ups job deletes reads older than 90 days (no new job; `jobs_test.sql` unchanged unless the clean-up's notes
  are listed there). The raw page is kept 14 days, as every capture page.

**`capture_ingest()`:** accepts the kind `salaries`. `private.capture_page()` turns it into the three tables.
`private.capture_check()` judges it: **ok** when both pages read and every position with staff found its country
average; **short** when the country page failed, or a position with staff is unmapped or missing from the country page
(Malaysia's wide-body pilots today, if it has any); **broken** when the Employee overview didn't read. The verdict is
kept on the raw page and shown on Systems, but **a `salaries` page never enters the airline's verdict**
(`capture_airline_verdict()` lists its kinds and must not take this one), the day's completeness or the snapshot: the
unattended job fails on anything but "all good", and a salary read must never fail it.

**The setting:** `settings.salary_flag_pct` = 1 (per cent), world level, described ("The salary table flags a position
whose next week's salary is more than this many per cent under or over its target, the country page's average plus
salary_above_average_pct; spec 2026-11-16-salary-table"). `rules_input_test.sql`'s exact list gains it. If choice 3 is
B, also the reading answer below.

**The figure:** `salary_table(world, as_of)` (staff, with its builder `private.fig_salary_table()`, described, 30 s
limit as the others, listed in `figures_timeout_test.sql`): for each of our active airlines, its latest read at or
before the moment, and per position: the name, group, employed, salary, next week's salary, the overview's average, the
country page's average, the target (`round(country avg × (1 + salary_above_average_pct/100))`, the capture's own
rounding), the difference in AS$ and per cent of the target, and `flag`: `under`, `over`, or null within the band, or
`no_average` (unmapped or not on the country page). Positions with no staff are listed but never flagged (decided,
choice 4). Also per airline: the read's time, its verdict, the count flagged, and `averages_differ`: positions where
the overview's and the country page's averages differ by more than 0.5% (the two sources, §1). **Stored** after each
capture in `planner_figures` (kind `salary_table`, world key), never read live by the planner (manual §1); added to
`private.figures_refresh()`'s list and `stored_figures_test.sql`, and to `export_for_report('figures')` so the weekly
report can use it.

## 5. The planner (choice 1: A, a Salaries board on Systems and one Today item)
The screen part depends on choice 1. Common to every option: the table's words and marks in a `model.ts` with unit
tests; numbers as the planner writes AS$ elsewhere; under rows red, over rows amber (over costs money, under risks
staff); the read's time at the top ("Salaries read 16 Nov, 21:34 UTC"); a position with no average says why. A table,
as Gitesh asked (not a chart).

## 6. Manual and documents (in the build's pull request)
- **Manual §7, salaries:** the sentence "Nothing about salaries is stored." is replaced by what is stored and where it
  shows, e.g. "Each capture that reads salaries stores every position's salary and the country page's averages; the
  planner's salary table flags a position more than `settings.salary_flag_pct` (1%) under or over its target (the
  country page's average plus 5%). The capture still never lowers a salary; Gitesh lowers by hand." The old wording and
  why go in `docs/rule-history.md`, and the project copies are updated by the Main chat.
- **Manual §7, the capture paragraph:** only if choice 3 is B ("for its key it never sets salaries" gains "but reads
  and stores them").
- **Manual §1:** nothing changes.
- The map: the capture row and the captured figures row only if their short description changes; dated notes in
  `docs/map/capture.md` (1.18), `docs/map/captured-figures.md` (`salary_table()`), `docs/map/planner.md` (the screen),
  and `docs/map/unattended-capture.md` if choice 3 is B. `docs/data.md` regenerates from the descriptions.
  `docs/planner-guide.md` for the new table.

## 7. What the checks should show
- `tests/capture_salary_test.mjs`: the saved Kingfisher page still reads as today, plus the new fields (group,
  employed, salary per employee); `readCountryPage()` on `tests/fixtures/country_IN_2026-11-16.html` gives 16 positions,
  "Narrow-body pilots" 1,794, name "India", code "IN"; a page that isn't a country page gives an error; the payload a
  run sends has both parts, and a failed country page still sends the overview with the country's error; a `salaries`
  call refused never stops the capture.
- `tests/userscript_key_test.mjs`: unchanged and green (1.18, the shared block identical).
- `tests/check_secrets.py`: green (the fixture holds no key).
- Database (`database/tests/salary_table_test.sql`, new): a `salaries` page is stored, judged ok / short / broken as
  §4 says and never changes `capture_airline_verdict()`'s answer or the day's completeness; the mapping finds the three
  pilot rows and leaves an unknown family unmapped; the target and flag at the band's edges (exactly 1% not flagged,
  just over flagged, both ways); no-staff rows unflagged (or as choice 4 decides); every new table, column, view and
  function described; staff can select the new tables, `anon` can't; `salary_table` is in the stored set.
  `rules_input_test.sql` and `stored_figures_test.sql` and `figures_timeout_test.sql` updated to their new exact lists.
- The rehearsal's planner step: the new board opens from the stored set with no live figure call
  (`tests/planner_next_test.py`'s list gains `salary_table`).

## 8. What stays out
- **No lowering by the capture** (decided 15 Nov, "A1"). Over-target rows are for Gitesh to lower by hand (to-do 246).
- **No setting of salaries on the unattended run**: `unattended_salaries` stays false. Whether the unattended run may
  set salaries, and whether the capture may lower, come back after the table has run about a week (the brief's Outcome).
- No change to how a salary is set, to the 5%, or to the Employee overview's average being the one the capture sets
  from.
- No new job; no live database change by this build (the Building chat applies the migration after "merge").

## 9. Files
- `capture/capture_all.user.js` (1.18).
- `database/migrations/<date>_salary_table.sql`: the column, four tables with grants, the setting, `capture_ingest()`
  / `capture_page()` / `capture_check()` for the kind, `capture_airlines()` (country id; choice 3), `salary_table()`
  and its builder, the stored figures' list, the clean-up. `database/current/` updated.
- `database/tests/salary_table_test.sql` (new) and the three listed tests.
- The planner: per choice 1. `tests/capture_salary_test.mjs`. `tests/fixtures/country_IN_2026-11-16.html` (in this
  spec's commit).
- Documents: §6.

## 10. Read from the live database before building (by the Main chat, 16 Nov)
- `airlines.country_code` is null for our six airlines; the ids are set by game id (§3).
- The aircraft in service: every airline flies the A320 family and the E-jet E2 family, and Pan Am also the A350, so
  Kingfisher's three pilot rows cover all six. A pilot row with no mapping still shows as unmapped, never guessed.

---

## Choices for Gitesh, and his decisions (16 Nov, 08:59 to 09:04 India time)

### Choice 1: where the table shows (decided)
| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. A **Salaries** board on Systems (one table per airline, folded; flagged rows marked) and **one item** in Today's Needs attention ("Salaries: 5 positions off target in 3 airlines") linking to it, the way Cabin charges works | Today shows only that something needs a look; the whole table is one click away | Small: one board, one attention item | Systems is the plumbing screen; the table sits beside the capture boards rather than the money | Yes |
| B. A **Salaries** group in Today's Needs attention, **one item per flagged position** (for example, made up: "Kingfisher · A320 pilots 1,800 AS$, target 1,884, 4.5% under"), plus the full table on each airline's **Performance** page | Each position to fix is its own line on Today, with dismiss; the full table sits with the airline's money | Larger: two places, item keys, dismissals | Many items on a busy evening (six airlines × up to 17 positions), which crowds Today until the first lowering round is done | Yes |
| C. The full table on each airline's **Performance** page only, with a flagged count on its scorecard; nothing on Today | One place, next to the airline's profit | Small | Nothing pushes it at him; a flagged position waits until he opens the airline | Yes |

**Recommendation (only):** A. It follows the existing pattern for game-side figures to check (Cabin charges: a
Systems board and one Today item), and keeps Today short while to-do 246's first round of lowering clears many rows at
once.

**Outcome (Gitesh, 16 Nov): A.** A Salaries board on Systems with all six airlines, and one Today item when anything is
flagged, linking to it, as Cabin charges works.

### Choice 2: Ryanair's country (decided)
`airlines.country_code` is null for all six airlines, so Gitesh said which country.

**Outcome (Gitesh, 16 Nov): Ireland**, the game's country id 65.

### Choice 3: whether the unattended run reads and stores salaries (decided)
Today the unattended key never reaches the salary step (§1). The 15 Nov brief settled that it doesn't **set** them; it
did not settle reading.

| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. Only Gitesh's press reads and stores (as now) | The table updates when he presses | None | The table goes stale when he doesn't press (12 to 15 Nov he didn't); its time at the top says so | Yes |
| B. The unattended run also reads and stores, never sets: a new world setting `unattended_salary_read` (true), and `capture_airlines()` answering a separate `salary_read` flag so the script reads without setting | The table is fresh twice a day, whether or not he presses; gives the week of data the brief wants before deciding unattended setting and lowering | One setting, a flag, and a branch in the script (read without the setting step) | Two more game page reads per airline per run; a read that fails is short, never fails the run (§4). Reading changes nothing in the game | Yes, the setting off |

**Recommendation (only):** B. Reading changes nothing in the game, and the brief's next decision (about a week of the
table) needs fresh rows, which only twice-a-day reads give when he is away.

**Outcome (Gitesh, 16 Nov): B.** The unattended run also reads and stores salaries and the averages, behind
`settings.unattended_salary_read` (true); it never sets a salary (`unattended_salaries` stays false), and a salary page
that fails to read never fails the run or changes an airline's verdict.

### Choice 4: which salary is compared, and positions with no staff (decided)
| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. **Next week's salary** (the box the capture and Gitesh set); positions with no staff listed, never flagged | Compares what will be paid, and shows a change the moment it is made (the capture's own raise, or his lowering) | None | This week's figure, which is still being paid, isn't the one flagged (it is shown beside it) | Yes |
| B. **This week's salary per employee**; no-staff positions as in A | Compares what is paid now | None | A raise or a lowering shows a week late, so the table flags what he has already fixed | Yes |
| C. As A, but no-staff positions flagged too | Every position ready before staff arrive | None | Rows that cost nothing are flagged (Kingfisher's wide-body pilots: 0 staff, 1,934 AS$ against a 1,691 target on its page's 9 Nov average) | Yes |

**Recommendation (only):** A. It matches what the capture sets and what he changes by hand, and leaves out rows that
cost nothing.

**Outcome (Gitesh, 16 Nov): A.** Next week's salary against the target, this week's shown beside it; a position with no
staff is listed but never flagged.

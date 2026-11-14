# Salaries in the unattended capture

*Main chat, 15 Nov 2026. To-do 213 (option C of `2026-11-10-unattended-capture-scope.md`, left open then) and to-do
218, step 3.*

## Decision
Only Gitesh's own press of "Capture all airlines" checks salaries (`settings.unattended_salaries`, false; manual §7).
Should the unattended runs check them too?

**Recommended: C, a limit first, then switch it on.** Gitesh chose **C**, with the game's country page as the check.

## Options

| | A. Leave as is | B. Switch it on now | C. Add a limit, then switch on |
|---|---|---|---|
| Salaries checked | Only when he presses | Every unattended run | Every unattended run |
| When he is away (12 to 15 Nov) | Positions can sit below the country average for days | Covered | Covered |
| Risk | Staff paid under average until his next press | The script sets no limit of its own: a page read wrong would set a wrong salary with nobody watching, paid every week | The same misread is stopped by the limit |
| Cost | None | A setting | A small build, then the setting |
| Undo | Nothing to undo | The setting off; a salary already raised is never lowered by the script | Same |

No growth or route choice moves, so the usual money columns are left out. The cash at risk is a wrong salary, paid at
each week-end closing until someone corrects it in the game.

## Background
- Manual §7, salaries: a position below its country average is set to the average plus
  `settings.salary_above_average_pct` (5%); a salary is never lowered; nothing about salaries is stored.
- The 10 Nov audit: the scripts set no limit of their own on a salary or fare change (to-do 218, step 3).
- The unattended capture has run three times a day since 11 Nov and never sets salaries. Gitesh was away from 12 to
  15 Nov, so no salary was checked in that time.
- Not checkable from the database: whether the salary step has worked on his presses since 5 Nov (nothing is stored).
- **The check Gitesh named (15 Nov):** the game's country page lists the country's average salary for each staff
  position, and it opens without signing in (`https://gander.airlinesim.aero/action/info/country?id=61` is India: 16
  positions, narrow-body pilots 1,788 AS$ when read on 15 Nov). It is a second source for the average the Employee
  overview page shows.

## If we wait
Nothing breaks. Salaries are checked only when he presses.

## What would change the recommendation
If the salary step has been watched working on many presses, B is a reasonable shortcut.

## Outcome
**Not C as first recorded.** The Main chat took Gitesh's "I think it can read the average salaries of a country from the
countries page" (15 Nov) as a check before a salary is set, and recorded C that way (to-do 244). He corrected it the
same sitting: "Capture sets the salaries like it normally does but stores what the salary [is] for each employee for
each airline. The capture also reads the average salaries from country page. Then we have a table or something which
compares both and if numbers differ by [more] than 1% on either direction it [shows] in the [planner]".

**Decided (Gitesh, 15 Nov, Main chat):**
- **A salary table in the planner.** The capture stores each airline's salary for each position and the country page's
  average for each position. The planner compares our salary with the target (the country page's average plus
  `settings.salary_above_average_pct`, 5%) and flags a position more than 1% under or over it. The build is to-do 245.
- **The capture does not lower salaries yet** ("A1"). He lowers the ones above target by hand (to-do 246). Why not
  automatic: our own staff are part of each country's average, so always moving to the average plus 5% feeds itself
  where we are a big employer (at half a country's staff in a position it settles about 10.5% above the others), and
  the nightly "everyone to 10% above" was stopped on 10 Oct on that suspicion (rule history).
- **Still open,** to bring back once the table has run about a week: whether the unattended runs set salaries too
  (this brief's first question), and whether the capture may lower.

Nothing is in force until to-do 245 is built: manual §7's salary rule, "Nothing about salaries is stored" included,
stands until its pull request.

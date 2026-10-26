# The fare ladder, one airline at a time

Decided 26 Oct 2026, option E of `docs/briefs/2026-10-26-fare-ladder-timeouts.md`. Planner only: no database change, no
rule change (manual §5 still says "Put on the fare plan in Performance"; the airline page is part of Performance).

## Why
Performance's group page asks for all six airlines' `fare_ladder()` at once, beside growth signals and the other
figures. On the free plan's small processor they slow each other down from 1–2 s each to 10–26 s, and on 26 Oct eight
calls hit the 30-second limit with no capture running ("Couldn't read the fare ladder: canceling statement due to
statement timeout"). One ladder alone takes 1–2 s.

## What changes

### 1. The group page (`/planner/performance`)
- The fare ladder board (`FareLadderBoard` with every airline) goes, and so does its read, `useFareLadders`. Remove
  `useFareLadders` from `reads.ts` if nothing else uses it.
- In its place, a short section with the same heading, **The fare ladder**, and one link per airline in our airlines'
  order: the airline's mark and name, opening `/planner/performance/<code>#fare-ladder`. No figures, no counts: the
  links read nothing. A one-line lead under the heading: "One airline at a time: open an airline for this Saturday's
  fare moves."
- Opening the group page must call `fare_ladder` **zero** times.

### 2. The airline page (`/planner/performance/<code>`)
- The fare ladder board for that airline only: `FareLadderBoard` with `airlines` = the one airline and `ladders` = its
  one answer, from the existing `useFareLadder(selId)`. That read already serves the route profit table's fare index
  under the same query key (`tableKey("fare_plan", "ladder", id)`), so the page still makes **one** `fare_ladder` call.
- Place it straight under the airline's scorecard and above the other boards, open on arrival, as a section with
  `id="fare-ladder"` (so the group page's links land on it) and the same `data-board="Fare ladder"` and
  `data-figure="performance: fare ladder board"` the group page's section had, with its lead (`LADDER_NOTE`).
- **Put on the fare plan** works exactly as it did (`ladderPlanChanges`, one `planner_save()` call, the same message).
  It already refreshes the ladder through the fare plan's key; check the fare plan board below updates too.
- While the ladder loads, the board says so; if the call fails, the same error line as today, for that airline only.

### 3. Nothing else changes
Tails' plan cards, the route page, the briefing and the fares userscript (`capture_fare_actions()`) keep their reads.

## Tests
- `tests/planner_next_test.py`: the fare ladder checks (one section per airline, moves line "N up, N hold, N down", Put
  on the fare plan, the game-action count, the set-back heading, the lists cut to 10 and opened) move from the group
  page to each airline's page: open each of the six airline pages and check its one section. On the group page check
  the six links (each to `/planner/performance/<code>#fare-ladder`) and that **no request to `rpc/fare_ladder`** was made
  while it opened (watch the page's requests). The screens at 1280 and 380 px stay free of errors and sideways scroll.
- `tests/planner_saves_test.py` and `tests/fixtures/planner_saves.expected.json`: Put on the fare plan is now saved from
  an airline's page; the rows written must be the same as before. Update only what moved (the screen or address), and
  say so in the pull request.
- Any other check that looked for the board on the group page (`tests/planner_figures.mjs`, unit tests beside
  `model.ts`) follows it.

## Documents (same pull request)
- `docs/architecture.md` (and say in the pull request that `claude/architecture.md` needs the copy): Performance's
  paragraph — the group page's fare ladder becomes the links, the airline page gets the board; `useFareLadders` gone.
- `docs/planner-guide.md`: the fare ladder section and the group/airline page descriptions.
- `docs/playbook.md` (and its copy, `claude/playbook.md`, named in the pull request): the Saturday step "Performance →
  The fare ladder" becomes "Performance → each airline's page → The fare ladder", airline by airline.

## Lessons from earlier helpers (read them)
- A test comparing whole JSON breaks when fields are added; compare what you mean.
- The saves test's recorded answers list the columns each insert sends.
- A pull request with merge conflicts runs no checks at all: update its branch first.
- `types.ts` must match what the database copy generates; this build changes no database, so leave it alone.

## Done when
`bash tests/run_all.sh` passes locally, the pull request says what changed, why and how it was tested, and the checks on
GitHub (Checks and Database rehearsal) are green.

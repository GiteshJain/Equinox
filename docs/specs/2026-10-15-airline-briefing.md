# Build spec: the airline briefing and the question guide (#24) — 15 Oct 2026

**Why:** decision #24, option B, decided 14 Oct (`docs/decisions.md`; brief `docs/briefs/2026-10-14-data-views.md`). The
manual's scheduling routine (§4) starts with each airline's background: loads, money, network and competition. A chat
stitches that from about six calls plus table queries each time aircraft arrive, slowly and with wrong guesses at column
names. One command should give the whole picture for one airline, and one page should say which call answers which
question.

## Part 1: the briefing command
`python3 scripts/briefing/brief.py <airline>` (IATA code, planner name or game name; `--as-of` optional; `--out <dir>`
for the files). It prints a short briefing, about one screen, and writes the full JSON beside it (`briefing_<code>.json`).

**What it holds, for one airline, as of now:**
- **its card and cash:** profit a day, per aircraft, fleet, flights a day, 7-day load, the next order and whether it can
  order now, and the cash forecast's lowest point and when (`airline_cards()`, `cash_forecast()`);
- **its fleet:** each aircraft's base, type and cabin, legs a week, block hours a day, maintenance and issues (the
  planning library), and profit a day (`aircraft_profit()`);
- **its routes:** each route's 7-day load, profit a week and the growth mark with its reason (`route_loads()`,
  `route_profit()`, `growth_signals()`);
- **its hubs:** hubs-first progress and contested bases (`hub_progress()`);
- **deliveries and plan cards:** aircraft on order or arrived and not yet flying, with their plan cards and the plan-card
  check (the library's `check-card`, service codes included);
- **open to-dos** for the airline and the group;
- **the fare plan:** changes planned and whether the captures show them (`fare_plan_status()`);
- **the rivals in its markets:** from the latest world scan, with the scan's date (the airports and routes it flies,
  and who else flies them, from what `scripts/report/` already reads);
- **the capture's state:** its latest capture and #21's verdict.

**Where it reads:** each figure from its one home (#19): the captured figures and scans through `export_for_report()`
(kinds `figures`, `rules`, `snapshots`, `airlines`, `airports`), the planning figures from the library's command on
`rules`. For what no export kind gives yet (deliveries, plan cards and their legs, to-dos, the fare plan for one
airline), add one export kind (`briefing`, one airline, read only), added in a migration that only adds. Nothing works out
a figure that already has a home; the command only gathers.

**Keys:** as the other scripts (`scripts/README.md`): `~/.sb_anon` and `~/.ingest_secret`, never committed.

## Part 2: the question guide
A section in `docs/architecture.md`, "Which call answers which question": a table of the recurring questions (an
airline's background, can it order, route profit, hub progress, an aircraft's week, a plan card's check, loads by day,
the capture's state, the systems' state, the rivals, the scan's age …), each with the one call that answers it (database
function, export kind, library command or the briefing) and a short tested example. A test checks that every call the
guide names exists and answers on the copy.

## Checks
- **In Checks (no database):** the briefing's printing and JSON shape from saved inputs (a small dated sample in
  `tests/fixtures/`, like the report's), including an airline with no deliveries and one with no scan.
- **In the rehearsal:** the command runs for every airline on last night's copy with the local keys, and each section is
  filled; the guide's calls all answer.
- The new export kind gets a database test (one airline only; the secret required; read only).
- **A deliberate failure,** seen to fail then removed: the briefing takes another airline's routes (a test must go red).

## Docs, in the same pull request
`scripts/README.md` (the briefing), the map (the guide), the manual §4 (the scheduling background starts from the
briefing) and *Decided, not yet built* (#24 built), `tests/README.md`, `docs/data.md` (regenerated).

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` for the migration.
- **Work lean:** check on GitHub runs every few minutes rather than continuously, and don't read beyond what the build
  needs.
- **Never connect to the live database or use the Supabase connector tools.** Never commit a key.
- Work on branch `briefing`, open the pull request with the REST API, and don't merge.

## Done when
Every check is green and the deliberate failure was seen to fail, then removed. The pull request says what changed, the
run time, a sample briefing (one airline, from the copy), any finding, the steps after "merge" (the migration applied from
the chat), and how to roll back.

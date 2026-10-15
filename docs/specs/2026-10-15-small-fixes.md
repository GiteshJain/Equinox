# Build spec: three small fixes found by the briefing build — 15 Oct 2026

**Why:** the airline briefing's build (pull request #42) found three problems outside its spec. Fix them before
Saturday's review, which reads the figures and runs the market summaries.

## 1. Pilot-training payments counted as flight costs
The 14 Oct orders brought 34 "Pilot training" lines on the bank statements, each beside a cabin payment. They're not
recognised, so `game_flight_pnl` and `game_ops_recent` count them as unnamed flight costs, which understates flight
profit (as the salary label did on 10 Oct).
- Recognise them where the statement lines are sorted into flights and payments, as a one-off payment tied to the
  aircraft order (like the cabin payments), not a flight cost. Find how the salary label was fixed on 10 Oct and follow
  it.
- Re-sort the lines already stored (a data step in the migration, logged as migration).
- Say in the pull request which figures move (flight profit a day, route profit, aircraft profit) and by how much on
  last night's copy. Profit a day from cash doesn't move.
- A database test: a statement with a pilot-training line keeps it out of the flight's costs.

## 2. The market definitions in two scripts
`scripts/report/scan_markets.py` and `scripts/newsletter/nl_analyze.py` can't load the market definitions since 13 Oct
(the comment above the block in `scripts/report/analyze.py` says why). Make both load them as `analyze.py` does, and
add a test that runs each on the saved samples in `tests/fixtures/`.

## 3. The database's reference file
`database/current/functions.sql` is missing `cash_log()`, `fare_plan_status()`, `private.fig_cash_log()` and
`private.fig_fare_plan()`. Add them as live has them, and add a rehearsal step that fails when the file and the copy
(after the migrations) don't list the same functions, so this can't drift again.

## Checks and proof
- `bash tests/run_all.sh` passes; the rehearsal passes.
- **A deliberate failure,** seen to fail then removed: pilot training counted as a flight cost again (the new test must
  go red).

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` for the migration.
- Migration: adds or replaces with the same arguments, plus the data step; says it can be applied from the chat.
- **Work lean.** **Never connect to the live database or use the Supabase connector tools.** Never commit a key.
- Work on branch `small-fixes`, open the pull request with the REST API, and don't merge.

## Done when
Every check is green and the deliberate failure was seen to fail, then removed. The pull request says what changed,
which figures moved and by how much, the steps after "merge", and how to roll back.

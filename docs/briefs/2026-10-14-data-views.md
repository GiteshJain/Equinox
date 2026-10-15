# Ready-made data views — 14 Oct 2026 (decision #24)

**Decision:** whether to add ready-made answers for the questions the chats ask again and again, such as an airline
briefing, route profit and hub progress.

**Recommendation:** B. One airline briefing command, and a one-page guide to which call answers which question.
- **Most of #24 was built by #19.** Route profit, hub progress, growth signals, the cash forecast, the airline cards,
  route loads, fare changes and aircraft profit are each one call in the database, and `export_for_report('figures')`
  gives them all at once.
- **What's missing is the briefing before scheduling.** The manual's scheduling routine (§4) starts with the airline's
  background: loads, money, network and competition. Today a chat stitches that from about six calls plus table
  queries, by hand, each time aircraft arrive. It's slow, it costs Claude usage, and it goes wrong: this week alone I
  guessed column names wrong five times. The full data guide (`docs/data.md`, 134 KB) is too big to read each time.
- **B is one command per airline** (`python3 scripts/briefing/brief.py KF`). It gathers the captured figures from the
  database, the planning figures from the planning library, the competition from the latest world scan, and the
  airline's deliveries, plan cards and open to-dos, and prints a short briefing. Each figure still comes from its one
  home (#19); the command only gathers them.

One pull request, about 2 to 3 hours. $0 a month.

*Columns adapted for a non-game decision.*

| Option | What changes | Effort | Gain | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Keep as is | Nothing. Chats use the #19 calls and query tables for the rest | None | None | Each briefing stitched by hand: slower, more usage, wrong guesses | — |
| **B. An airline briefing, plus a guide** | **One command per airline gathers its figures, planning figures, competition, deliveries, plan cards and to-dos into a short briefing; a one-page guide in the map says which call answers which question** | **1 pull request, about 2 to 3 hours** | **Every scheduling session starts from the same complete picture, in one step** | **One more script to keep working when tables change (the checks run it)** | **Yes** |
| C. B, plus more views | B, plus database views for other questions (each route's week, the fleet, rivals by market) | 1 to 2 pull requests | A few more one-call answers | More to keep in step with the tables; most of these questions are already one #19 call | Yes |
| D. The guide only | Just the one-page guide of which call answers which question, with tested examples | Done in the chat, about 30 minutes | Fewer wrong guesses | The briefing is still stitched by hand | Yes |

## Background

### What the chats can ask for today
The live database and repository `main`, 14 Oct.
- **The captured figures (#19, design §8):** `airline_cards()`, `cash_forecast()`, `airline_profit()`,
  `route_profit()`, `aircraft_profit()`, `growth_signals()`, `hub_progress()`, `route_loads()`, `fare_changes()`,
  `capture_status()`, and `loads_by_day()` since the clean-up. The scripts get all of them through
  `export_for_report('figures')`.
- **The planning library (#19, design §7):** `rules_input()` (or `export_for_report('rules')`) and the library's command
  (`node lib/rules/dist/cli.js`) for block times, turns, connections, maintenance, plan-card checks and the optimiser.
- **The world scans:** `export_for_report()` with kinds `snapshots`, `airlines` and `airports`.
- **Everything else** (deliveries, plan cards, to-dos, the fare plan) by querying the tables, with `docs/data.md` as the
  guide.

### Where it goes wrong
- The scheduling background (manual §4) needs pieces from all four, for one airline, each time aircraft arrive.
- Column-name guesses that failed in this chat on 13 and 14 Oct: the planner's old data table, the change log's time,
  the jobs' status, the to-do steps, the capture's raw pages. Each one cost a retry.

### What the briefing would hold (B)
For one airline, as of now: its card and the cash forecast (can it order, the lowest point); its fleet (each aircraft's
base, legs a week, block hours a day, profit a day, issues); its routes (7-day load, profit, the growth mark); its hubs'
progress; deliveries waiting and their plan cards (with the service check); open to-dos; the fare plan; and the rivals
in its markets from the latest scan, with that scan's date. It prints a short summary for the chat, and writes the full
JSON beside it.

### Risks
- **A table changes and the command breaks.** It runs in the checks on every pull request, so a break shows before the
  merge.
- **An old scan.** The briefing prints the scan's date; #22 makes the Saturday scan a standing step.

## Outcome
14 Oct 2026: Gitesh chose **B**: one airline briefing command and a one-page guide to which call answers which
question. Recorded in `docs/decisions.md` and the manual's *Decided, not yet built*.

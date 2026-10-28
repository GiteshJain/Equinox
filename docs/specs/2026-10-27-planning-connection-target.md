# Spec: plan for short connections — 27 Oct 2026

*From the Scheduling chat, for the Building chat. Gitesh's decision of 27 Oct (option B of
`docs/briefs/2026-10-27-connection-waits.md`, planning only). One pull request carries the setting, the library, the
tests and the documents, so the rule and the tools change together at the merge.*

## What and why
**What:** a planning target for connections, **4 hours** (`settings.plan_connection_target_h`), that the optimiser
scores by. A connection still counts up to `connection_max_wait_h` (8 hours) everywhere else.

**Why:** only about a third of our flights sit in their hub's banks, and 58% of our 5,447 connections wait more than
4 hours (average 4.5 h). Passengers choose on price, time, cabin and service (Gitesh, from the game), so long waits lose
bookings. The cause: the optimiser scores every connection up to 8 hours alike, so nearly any departure time collects
connections and nothing pulls flights into the banks. A flight in its bank connects in the minimum connection time to
about two hours more (1.3 to 3.5 h), so 4 hours means "in a bank, or close".

## Changes
1. **Setting.** A new `settings` row `plan_connection_target_h` = 4 (hours), with its description, world-wide, no
   airline overrides. Read like the other rule numbers (manual §1, one source).
2. **The optimiser** (`lib/rules/src/optimiser.ts`): the score's first key becomes the connections whose gap is from
   the minimum connection time to `plan_connection_target_h`; then, as now, all connections to `connection_max_wait_h`;
   then maintenance. (So between two plans with as many short connections, the one with more connections overall still
   wins.) Its answer gives both counts.
3. **The card check** (`check-card`): reports, beside today's connections at both ends, how many fall within the target
   (count and share), for the card and for each leg. No new problem mark: a card isn't wrong for having long
   connections.
4. **Nothing else reads the new setting.** `connection_max_wait_h` stays 8, and every current reader keeps it: Routes'
   connections at both ends, Performance's hub readiness, the banks' early/in/late, rivals' one-stop connections
   (`private.scan_connections()`), the website's trip search, the connection audit's counts and the weekly report.

## Tests
- A case where two plans tie on connections within 8 hours but one has more within 4 hours: that one wins.
- A case where a plan with fewer connections overall but more within 4 hours wins.
- The optimiser's saved answer (`tests/optimiser_saved_answer_test.py`, the 10 Oct KUL sample) will move: update it and
  say in the pull request what moved and why (manual §1).
- The rehearsal's types and screens as usual; nothing on screen should change except the card check's new figures.

## Documents (same pull request)
- **Manual §4**, under "Maximise connections at both ends": plans and retimes aim for connections within
  `plan_connection_target_h` (4 hours) of the arrival; a connection still counts up to 8 hours. *(since the merge,
  brief `docs/briefs/2026-10-27-connection-waits.md`)*
- **Manual §7**, the connection audit: retimes of **30 minutes** or less (today 10).
- **`docs/rule-history.md`:** the old §4 sentence (connections scored alike to 8 hours) and the old §7 limit (10 minutes),
  with the reason above; project copies of the manual and rule history updated after the merge.
- `lib/rules/README.md`, `scripts/README.md` (the optimiser's answer), the planner guide's card check lines, the map if
  it names the optimiser's score.

## After the merge (Scheduling chat)
The retime pass at the five big hubs, Gatwick first: moves of up to 60 minutes that gain the most connections within
4 hours, net of any they break, each checked at both ends; Gitesh makes them in the game and on Routes.

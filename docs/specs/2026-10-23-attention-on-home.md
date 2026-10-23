# Spec: Needs attention's cards on Home, aircraft on order off Home — 23 Oct 2026

Decided by Gitesh, 23 Oct: "want the cards on home only, not on today. they can then link to their sections on today";
and Home no longer shows aircraft on order (Today's Orders and delivery lines already do). No brief (a layout choice).

## What and why
On 20 Oct Needs attention moved whole from Home to Today. Today now opens with its Needs attention summary cards (one
card per group, e.g. "NEEDS ATTENTION · LGW-CAI: fix or reduce — economy averaging 68% · and 2 more in Routes to fix ·
See all 3"), and below them each group's full list (Routes to fix, Rival moves, Fleet, …) with dismiss and show again.
Home shows the operations hero, the network map, aircraft on order and the airline cards.

## The change
- **Home:** add the Needs attention summary cards, exactly as Today shows them now (same groups, same words, same
  order, same rules for dismissed items), placed right after the hero, before the network map. Each card's button
  ("See all 3") opens Today at that group's section (`/planner/today#<group>`), scrolled to it, with the list open.
  When nothing needs attention, Home says so in one line, as Today does now.
- **Today:** remove the summary cards. Keep every group's full list as its own section, each with a stable anchor id
  that Home's buttons link to, still with dismiss and show again. Today's page heading count ("N things waiting")
  counts what's left on Today; make it match the sections shown (this also settles the title/count mismatch noted in
  the 22 Oct handover).
- **Home:** remove the aircraft on order board (`OnOrderBoard`, `onOrder.ts`) and its read if nothing else uses them.
- Needs attention's figures and grouping stay in their one place (`today/attention.ts`, `ui/attention.ts`); Home only
  shows them. One set of reads, shared: don't copy the logic into Home.

## Tests and documents
- Unit tests: Home builds the same cards as Today did on the same sample; each card links to its section's anchor;
  Today no longer renders the cards but keeps every section; Home has no aircraft-on-order board.
- The screens' saved answers that move: say which and why.
- `docs/planner-guide.md` (Home and Today), `docs/architecture.md` where it describes the two screens, the Today and
  Home header comments.

## What the checks should show
All green: Checks and the Database rehearsal (every screen at 1280 and 380 px, no errors; the screen tour opens Home
and Today).

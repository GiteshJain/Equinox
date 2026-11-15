# Spec: a cleaner plan card

To-do 242 (Gitesh, 15 Nov, Main chat). One small pull request: the plan card's component, its model and tests, the
documents. No database change. Nothing the card stores, and nothing filing does, changes.

## What and why
The plan card (Tails → Deliveries → **card**, and Today's Aircraft to file, which opens the same card) shows only what
Gitesh uses while he sets a new aircraft up in the game. Everything else folds under one **More** line, closed by
default. In his words: "I think we can make the plan cards cleaner. I only care about the schedule, cabin and tail
details + hub." Then: "Need service code." On the fare level: "I'll remember that Ryan needs to launch at 85", so no
fare level on the card itself.

## What stays on the card itself
- **Its head:** the tail number and the hub (base), "N501AW · JFK"; the type as a pill; the cabin, just its name, or
  **no cabin chosen** in red when neither the card nor the order names one.
- **The schedule:** each flight's number, route, departure, arrival and service code. **Days** too: as today, a Day
  column when a leg doesn't fly every day (a line's card); a daily card has none.
- **The controls he files with,** where they are: the **Cabin** box (until filed) and **File into planner** (or **in
  the planner** once filed).
- **What is wrong, in red, on the card itself:** a wrong service code ("S1, wants S3"), and no cabin chosen. An airport
  where the airline has no station yet stays highlighted in the route column: it costs no clutter, and it is how he
  sees a route is new there.

## What folds under "More"
Closed by default. Nothing is deleted or stops being saved. In this order:
- the plan's title ("DDD + EEE", its new stations highlighted) and the flight count (both were in the head);
- the line, its place and its slot, for a card on a 7-day line;
- the note;
- the cabin's suggestion with its reason and **Use the suggestion** (before filing, as today);
- block time and the **Fare level** column, in one small table by flight and route (all of it, Ryanair's new routes
  too).

The planner has no checks, connections or maintenance on the card today (the card check at both ends is Claude's
`check-card`, not a planner screen), so none fold.

## How a problem shows while "More" is closed
The **More** line names what is under it ("More · plan · flight count · note · cabin suggestion · block times · fare
levels") and, when something under it needs a look, a count as a pill: **1 to check**. The one check under it is a
cabin that differs from the suggestion (amber on the card until now), so the count is amber, its level as before; the
reason is on the pill's hover and, opened, at the top of "More". A **More** line with no count means nothing under it
needs fixing. The red marks above never fold.

## Files
- `app/planner/src/screens/tails/model.ts`: `CARD_FACE`, `CARD_SCHEDULE` and `cardMore()` (what is under "More", its
  words, its problems and the count).
- `app/planner/src/screens/tails/Deliveries.tsx`: `PlanCard` laid out as above; the "More" line is the planner's
  existing folding line (`details.gsub`).
- `app/planner/src/ui/styles.css`: spacing for the "More" line inside the card's window; no colour (the pills are the
  named ones).
- `app/planner/src/screens/tails/plancard.test.tsx` (new): unit tests, the card rendered to markup.
- `tests/planner_next_test.py`: the rehearsal's plan-card check also checks the closed "More" line and its count.
- Documents: `docs/planner-guide.md` (the card), `docs/playbook.md` §6 step 5 (the suggestion and the fare level are
  under "More"), `docs/map/planner.md` (a dated note), `tests/README.md`.

## What the checks should show
- Unit tests: the card's head, schedule, Cabin box and File into planner on the card itself; no Block, Fare level,
  suggestion, note or title before "More"; one `details` line, closed; a differing cabin counted on it ("1 to check")
  and a clean card's line with no count; the red marks and the new-station highlight on the card itself; a filed card
  without Cabin box or suggestion.
- The rehearsal: the opened card still shows the library's suggestion and each direction's fare level (they are in the
  page under "More"), the "More" line is closed, and its count matches whether the cabin differs. The cabin save
  (the Cabin box) and filing (File into planner) are clicked where they were.
- No saved answer moves.

## Outside the spec
- The manual's §5 sentence "Every plan card shows the fare level of each route it flies …" is still true as worded:
  the card still carries each route's level, under "More". It is unchanged.
- Today's Aircraft to file and every other screen are unchanged.

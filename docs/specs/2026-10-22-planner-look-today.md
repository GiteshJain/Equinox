# The planner's new look, step 2: Today (22 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 22 Oct); step 1, the foundation, is live
(#71). This step rebuilds Today's layout to the approved mockup (the "equinox. planner redesign" canvas, artboards
Today and Today on a phone). Everything Today shows today stays reachable; nothing about figures, saves or queries
changes.

## What Today looks like after this
1. **The answer is the title.** The page head's title becomes the answer the screen already works out
   (`waiting.title`, e.g. "2 things waiting", in display type). The small context line stays ("Every day"). The
   capture line ("All six airlines captured, all good, 04:25 UTC" with its dot and the Systems link) moves up beside
   the title as one rounded pill on the right (below the title on phones). The all-clear state reads the same way.
2. **The things waiting, as big cards.** Each item the answer counts gets its own card in a two-column grid (one column
   on phones): a small coloured kind line ("Order now" for an airline that can order, "Due <day>" for a to-do with a
   date, "To file" for an aircraft waiting to be filed, "Needs attention" for anything else), a one-sentence heading
   in Unbounded (the item's own words), a short line of detail where the screen has one, and its existing action as a
   button. The single most urgent card (an airline that can order now) is night with the amber button
   (`.primary.now`); the others are white with the night button. If nothing is waiting, the all-clear shows instead,
   as now.
3. **Delivery lines, as one table.** Orders becomes a table: one row per airline (its colour dot and name), one column
   per delivery line in the airline's order (A320 family, E-jet, A350; "—" where the airline has no such line). Each
   cell keeps what the card says today in short form: "Safe from Thu", "Safe now" (as an amber pill), "1 on order",
   "runs dry 19:29 · in 14 h". The row of an airline that can order now is tinted. Each row ends with a link "Cash,
   next 14 days" and a fold with "all safe types", as now. On phones the table becomes one compact row per airline
   (its soonest safe line on the right) that opens to show its lines. The board's long explanation moves into a
   one-line note under the heading.
4. **Counts, then detail.** Aircraft to file and every group of Needs attention (routes to fix, rival moves, and the
   rest) show first as count tiles in a three-column grid (two on phones): the number in Unbounded, the group's name,
   one muted line. Tapping a tile opens that group's list right below the tiles (the same list and dismiss buttons as
   now). Dismissed items keep "show again".
5. **Game check and the To-do board** stay as they are, restyled by step 1, below the tiles.

## Checks
- `bash tests/run_all.sh` green; the database rehearsal green: Today opens at 1280 and 380 px with no errors and no
  sideways scroll, and every save on Today (dismiss, show again, the To-do board, filing, the game check) still works.
  The screens' figures tests must not move. Update the planner's screen tests only where the layout change requires it,
  and say which in the pull request.
- Update `docs/planner-guide.md` (Today).
- Look at the rehearsal's Today screenshots at 1280 and 380 before reporting.

## Not in this build
Routes and Systems (steps 3 and 4); any change to data, figures, saves or queries.

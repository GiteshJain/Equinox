# The planner's new look, step 4: Systems (22 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 22 Oct). Steps 1 to 3 (#71 foundation,
#72 Today, #73 Routes) are live. This last step makes Systems short and answer-first, in the same style as the new
Today (`docs/specs/2026-10-22-planner-look-today.md`). Everything Systems shows and does stays reachable: the Systems
board's lines, the capture detail, Cabin charges (and its "Use the game's amount" save), Manual entry and its saves,
Aircraft checks and its saves, and the `#cabin-charges` address that opens Cabin charges. No figure, save or query
changes.

## What Systems looks like after this
1. **The answer is the title.** The page head's title becomes the board's summary (`boardSummary`): "All systems good"
   when every line is green, else how many need a look ("2 need a look"). The context line stays ("The plumbing"),
   and "checked at …" sits beside the title as a small muted pill.
2. **The Systems board as tiles.** Each line becomes a tile in a three-column grid (two under 1100 px, one on phones):
   its mark as a coloured dot and word (good, check, problem, using the status colours with text at 4.5:1 or better),
   the line's name in bold, its words in one or two lines, and its time. Red tiles first, then amber, then green, the
   order within each as now. Keep each line's `data-sys` and `data-mark`.
3. **The evening capture per airline, as one table.** Where the board shows each airline's capture verdict, show one
   row per airline (colour dot, name, when, verdict, and what came in short or broken), so six airlines read at a
   glance.
4. **The detail boards as rows that open.** Capture, Cabin charges, Manual entry and Aircraft checks become a short
   list of large rows: the board's name, a muted one-line note (the current NOTES text, shortened if needed) and a count
   or state where the board has one ("27 fits, no problems"). Tapping a row opens that board right below it, with its
   content as now; all start closed except Cabin charges when the address is `#cabin-charges`, as now.

## Checks
- `bash tests/run_all.sh` green; the database rehearsal green: Systems opens at 1280 and 380 px with no errors and no
  sideways scroll, and every save on Systems still works. The screens' figures tests must not move. Keep every
  `data-figure`, id and data attribute the tests use; change a test only where the layout requires it (e.g. opening a
  row first), and say which in the pull request.
- Update `docs/planner-guide.md` (Systems).
- Look at the rehearsal's Systems screenshots at 1280 and 380 before reporting.

## Not in this build
Any other screen; any change to data, figures, saves or queries. Whether Aircraft checks should stay at all (the
one-week checks were retired on 15 Oct, manual §1) is a separate question for Gitesh: leave the board as it is and
mention it in the pull request.

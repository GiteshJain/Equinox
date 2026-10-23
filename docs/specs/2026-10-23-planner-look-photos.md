# The planner's new look, step 11: Photos (23 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 23 Oct). Photos holds the airline logos and
destination photos for the public website.

## What Photos looks like after this
1. **The answer is the title:** "N destinations missing a photo" or "Every destination has a photo".
2. **Logos** as a row of six tiles (logo, airline, in-game or uploaded, Upload / Replace / Use the in-game logo).
3. **Destinations** as a grid of photo tiles (photo, city and code, flights a week, credit, the buttons), busiest first,
   with "Missing a photo only" as a pill toggle (on at first, as now); a photo just uploaded stays in view.

## Rules for every step
- Same style as steps 2 to 5 (Today, Routes, Systems, Performance): read their specs (`docs/specs/2026-10-22-planner-look-*.md`)
  and the live code for those screens, and reuse their classes and parts (the page head with the answer as the title,
  tiles, tables, rows that open, pills, the status colours with text at 4.5:1 or better). No new colours or fonts; the
  foundation (#71) holds the tokens.
- **Nothing about data, figures, saves or queries changes.** Everything the screen shows and does now stays reachable,
  every address keeps working, and every `data-*` attribute and id the tests use stays. The screens' figures tests must
  not move; change a screen test only where the layout requires it (e.g. opening a row first) and say which.
- Phone first: works at 380 px with no sideways scroll; wide tables scroll inside their own box or become rows.
- `bash tests/run_all.sh` green; the database rehearsal green (the screen at 1280 and 380 px, no errors, every save on
  it still works). Look at the rehearsal's screenshots of the screen at both widths before reporting.
- Update `docs/planner-guide.md` for the screen and the screen file's header comment.
- Only this screen: no other screen, no shared part's behaviour changed for another screen.

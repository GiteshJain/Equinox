# The planner's new look, step 8: Home (23 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 23 Oct). Builds on the 23 Oct change that
put Needs attention's cards on Home and took aircraft on order off it (`docs/specs/2026-10-23-attention-on-home.md`):
that layout and its links stay exactly as built.

## What Home looks like after this
1. **The hero stays** (globe, aircraft in the air, its tiles), tidied to the foundation's tokens.
2. **Needs attention's cards** as built on 23 Oct, styled as Today's cards were (kind line, Unbounded heading, button).
3. **The network map** in a card with a one-line heading and its legend as pills.
4. **The airline cards** in the Performance scorecard style (step 5): colour dot and name, then label/value rows that
   start at the top of the card and never squeeze the label to one word a line (the fix made on Performance), with the
   pills (lowest maintenance and the rest) as they are.

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

# The planner's new look, step 9: Interline (23 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 23 Oct). Interline is which foreign
countries each airline flies into and whether it has an interline agreement there.

## What Interline looks like after this
1. **The answer is the title:** how many agreements are open to do ("5 agreements to set up") or "All agreements in
   place", with the airline and status filters as pills beside it (kept in the address).
2. **Counts first:** tiles by status (to do, requested, agreed, not needed and the rest the screen uses), each applying
   the status filter.
3. **The agreements as one table,** editable as now (each change saved as you make it), grouped by airline with its
   colour dot; on phones each row is a compact card (country, airline, status pill) that opens to its fields.
4. **The interline countries and the guidance** (what to do when another airline asks, the countries each airline
   covers) as rows that open, closed by default.

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

# The planner's new look, step 7: Tails (23 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 23 Oct: the remaining screens). Tails is
every aircraft, what it flies and how hard it works, plus the deliveries board and its plan cards.

## What Tails looks like after this
1. **The answer is the title.** "N aircraft need a look" (from the screen's own Needs a look filter count) or
   "All N aircraft flying well", with the airline's fleet size and block hours a day as a muted pill.
2. **Counts first:** tiles for Flying, No flights, Needs a look and Deliveries (on order, arrived, to file), each
   applying its filter when tapped (the existing filters, kept in the address).
3. **The list as one table:** registration and base, type, cabin, legs a week, block hours a day, maintenance pill,
   routes (truncated, full on hover/tap). On phones, compact rows (registration, base, block h/day, maintenance) that
   open to the rest.
4. **Deliveries board and plan cards:** the deliveries as rows that open their plan card; the plan card window keeps
   every field, check, Cabin box, Use the suggestion, fares column, the station highlight and File into planner,
   restyled (card head, legs table, checks as pills).
5. **An aircraft's page:** its header as the title with type, cabin and the week's figures as pills, its fields grouped,
   its week strip and issues as before, restyled.

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

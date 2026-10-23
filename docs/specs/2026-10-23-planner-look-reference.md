# The planner's new look, step 10: Reference (23 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 23 Oct). Reference holds every section of
settings and lookups (hubs, focus cities, stations and banks; constants; aircraft; configs; markets; service profiles;
removed routes; night bans; game schedules; time zones; storage; data), each editable as now.

## What Reference looks like after this
1. **The title** is the page's name with a muted line saying what it holds; no count.
2. **Sections as large rows that open** (one at a time as now, the open one in the address `/planner/reference/<section>`):
   the section's name, a muted one-line note of what's in it and a count where it has one ("14 bases", "12 aircraft
   types"). Grouped under three small headings: Network (bases and banks, night bans, time zones, removed routes),
   Fleet and fares (aircraft, configs, markets, service profiles), Settings and data (constants, game schedules,
   storage, data).
3. **Inside each section,** its tables restyled (header row, row lines, numbers right-aligned, edits inline as now),
   scrolling inside their own box on phones. Every edit, its confirm step (time zones list what moves and ask) and the
   exports stay.

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

# The planner's new look, step 6: Competition (23 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps. Gitesh, 23 Oct: redesign the remaining screens
in the same look, one step each. Competition answers "who are we up against, and where do we open next?".

## What Competition looks like after this
1. **The answer is the title.** On the group page, the title is the group's headline from `competition()` (e.g. our
   departures' share of the world's, "8.4% of the world's departures"), with the scans' dates as a small muted pill
   ("latest scan 22 Oct, compared with 15 Oct"). On an airline's page, the title is that airline's share across its
   markets with its arrow.
2. **The group page:** one tile per airline (colour dot, name, share with its arrow, threats count, its top opening in
   one line), in a three-column grid (two under 1100 px, one on phones), each opening the airline's page. Every
   airline's threats below as one table (airline, rival, pair, numbers, day, the Performance link), newest first.
3. **An airline's page:** sections as rows that open (Market share, Threats, Openings, Rival profiles), Openings open by
   default. Market share as tiles with the share bar; Threats as a table; Openings as the ranked table, cut to 10 with
   "show all" as now, the hubs-first column as a pill (allowed, or the reason); Rival profiles as cards.

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

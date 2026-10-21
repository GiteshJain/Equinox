# Build spec: the weekly report sets each airline against its three biggest competitors (21 Oct 2026)

**Why:** decided 18 Oct (manual §7, the weekly report; "Decided, not yet built"): "each of our airlines against its
three biggest competitors: the three outside airlines with the most weekly departures on its own city pairs in the
latest scan, each with its size and growth since the previous scan beside our airline's" (Gitesh: to see whether each
airline is gaining on its rivals). Gitesh asked for it to be built on 21 Oct. Competition analysis (`competition()`,
#62) now has the scans and the rivals, so the report reads it rather than working it out again.

**Outcome when done:** every weekly report has, for each of our airlines, a short table and one line of words: the
airline and its three biggest competitors, each with departures a week on the airline's city pairs, total departures a
week, airports, and growth over the week.

## 1. The figure (new migration, `CREATE OR REPLACE` only)
- **`private.fig_competition()` adds `competitors`:** from the latest finished scan, the three rivals (outside airlines:
  not ours, passenger flights only, as the rest of `competition()`) with the most departures a week on the airline's
  own city pairs (the pairs it flies, both ways), ties by name. Each with:
  - `on_pairs` (their departures a week on those pairs) and `pairs` (how many of the airline's pairs they fly);
  - `weekly` and `airports` (their whole passenger network in the latest scan), `weekly_before` and the change
    against the week-before scan (`competition()`'s `week_before`), as a number and a percent.
- **And `self`:** the airline itself on the same terms, from the same scans (its passenger flights in the scan's
  schedules, both totals), so the two sit side by side.
- **"Since the previous scan":** when this was decided (18 Oct) scans were weekly. Now they run every evening, so use the
  **week-before** scan (as the rest of `competition()` does), and say so in the manual's wording.
- **Export:** `export_for_report('figures')` adds each airline's `competitors` and `self` (with the scans' dates), so
  `scripts/report/pull.py` gets them in `figures.json` with no new call. Keep the export's time on the copy in the PR.
- **Test:** the competition test gets the three, the tie, a rival with no week-before row, and `self`.

## 2. The report (`scripts/report/`)
- **`analyze.py`** reads them from `figures.json`; **`build.py`** adds, in each airline's part, "Against its three
  biggest competitors": the table (our airline first, then the three) and one line of words, e.g. "Pan Am grew 18% this
  week; American, its biggest rival on its pairs, grew 42%." Fit it to the report's existing look; no new chart unless
  it's one line of code with `charts.py`'s helpers.
- If a scan or `competitors` is missing, the section says "no world scan to compare yet" instead of failing.
- **`report_test.py`** keeps passing on the newest sample. If the sample has no `competitors`, add them to the test's
  copy in the test (a small synthetic block), not to the dated fixture, and check the section's text in the PDF.

## Checks
- `bash tests/run_all.sh` green; the rehearsal green with the migration and the test on the copy.
- The pull request gives, from the copy, each airline's three competitors with the numbers.

## Docs
- Manual §7: the line says it's built and reads `competition()`, with "the week-before scan" for growth; take the
  rule out of "Decided, not yet built". `scripts/README.md`, `tests/README.md`, `docs/architecture.md` (the report's
  row).

## Not in this build
- Any other change to the report.

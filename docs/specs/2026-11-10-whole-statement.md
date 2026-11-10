# Spec: the capture reads the whole bank statement, sent in parts

Part 1 of to-do 203 (decided by Gitesh, 10 Nov, in the Audit chat; brief `docs/briefs/2026-11-10-unattended-capture.md`,
*The 1,500*). One pull request: capture 1.16 and one migration. Part 2, the unattended capture, has its own spec and
starts from `main` after this merges. Read `CLAUDE.md`, the map (`docs/architecture.md`), manual §7 (the evening
capture and its page checks, #21) and the brief first.

## Why
- The game shows the bank statement's whole last 24 hours (Ryanair's ran to page 24 on 10 Nov). The capture stops at
  15 pages (`pages < 15` in `capture/capture_all.user.js`), 1,500 lines. On 9 Nov Ryanair, Virgin and China Eastern all
  stopped at exactly 1,500, so their oldest hours never reached the database. From 27 Oct to 8 Nov, 362 flights have
  loads but no money (Ryanair 267, Virgin 45, China Eastern 39).
- One `capture_ingest()` call for 2,400 lines would come near its 30 s limit, and the statement grows with every
  aircraft. So the statement goes in parts.

## 1. The capture script (1.16)
- **Read every page:** follow the ">" link to the last page. Keep the date stop, but at **26 hours** before the capture
  (was 3 days, which the game's 24 hours never reached). A safety stop at **60 pages**; hitting it is a panel line
  ("statement: stopped at 60 pages, 6,000 lines") and the statement is still sent.
- **Split into parts** of at most **500 lines** (a constant, `STATEMENT_PART_LINES`), **never splitting a minute**:
  a part ends only where the next line has a different `dd.mm. hh:mm` from the line before. The database numbers
  identical lines within one minute (`occ`) and groups a minute's lines into flights (`blk`) one page at a time, so a
  minute cut across two parts would number them twice and lose or misgroup lines. A single minute over 500 lines stays
  whole in one part. Lines keep the game's order (newest first).
- **Send each part** as page kind `statement`, page `/app/finance/accounting/2#run=<the run's ISO time>&part=<k>/<n>`,
  in order 1 to n. The run's time is taken once, when the statement starts. A part the database refuses counts as a
  failed page, as now (no world scan that evening).
- **The panel:** one line per airline as now, "Ryanair · statement 2,412 lines, 24 pages, 5 parts" (or the error of the
  first part that failed).
- **Pure functions in the lib** (`root.eqScan`), so they're tested without the game: `statementParts(rows, max)` and
  `statementPage(run, k, n)`. Tests in a new `tests/capture_statement_test.mjs`: a minute is never split; every line is
  kept, in order; a minute bigger than the limit stays whole; one part when under the limit; the page names.
- No other page changes. `VERSION` and `@version` to 1.16.

## 2. The database (one migration)
- **`private.statement_run(p_page text)`** (described): the run and part from a statement page's address, as
  `jsonb {run, part, parts}`, or null for a page without them (every page before 1.16).
- **One run, judged once:** `private.capture_check()` for a statement page that is a part:
  - parts 1 to n−1 are judged **ok** with the note "statement part k of n", facts `{part, parts, read}`;
  - the last part is judged on **the run's lines together**: every raw statement page of the airline with the same run,
    summed, against the median as now. Its note is the whole run's: "statement 2,412 lines in 5 parts (usually about
    1,400)". If a part of the run is missing when the last arrives, **broken**: "statement: part 3 of 5 missing".
  - Since an airline's verdict reads each kind's latest page (`capture_airline_verdict()`), and the last part is the
    latest, the panel, Today and the Systems board show the whole run's verdict with no change to them.
- **The median by run:** the expectation's recent nights (`private.capture_expect()`, kind statement) count each
  night's latest **run** (all its parts summed), and a page without a run alone, as now.
- **Reaches back to the last capture** (to-do 203): on the last part, the run's oldest line against the airline's
  previous statement capture. When the oldest line is more than 15 minutes after that capture, the note adds "the
  N hours before 08:00 9 Nov weren't captured" and the facts `gap_from`, `gap_to`. The verdict is unchanged by a gap:
  capturing again can't bring those hours back, and Today already says when an evening is missed. With no earlier
  capture, nothing is said.
- **Nothing else changes:** each part is parsed and matched by `private.capture_page()` as a page is now (lines are
  idempotent on `game_statement`'s key), the day's completeness and the snapshot are unchanged (the statement comes
  before the loads page, the airline's last), and `capture_statement_lines()` still counts one page.
- `database/current/` updated for the changed functions.

## 3. Documents
- The map: the statement covers **the last 24 hours** (it says 3 days in two places), read to its last page and sent in
  parts of 500 lines cut between minutes; the Capture row gets 1.16; the How data moves step's "the statement covers
  3 days" corrected.
- Manual §7 (the page checks): add that a statement is judged on the run's parts together, and that a gap before the
  first line is said in the note. Rule history: the why (this spec). The playbook if it mentions the 1,500 or 3 days.
- `tests/README.md` for the new test.

## 4. What the checks should show
- *Checks:* the new statement test, and the existing capture tests unchanged.
- *Database rehearsal:* a new case in `database/tests/capture_checks_test.sql`: one airline's saved statement
  (`tests/fixtures/capture_pages_*.json.gz`) sent as three parts gives exactly the rows the single page gives, parts 1
  and 2 ok, part 3 judged on the total; a run with part 2 missing is broken; a run starting 3 hours after the previous
  capture says the gap. Every kept page replayed is still judged ok (`capture_data_replay_test.sql`): pages before
  1.16 have no run and are judged as before.

## 5. After the merge
- Claude applies the migration to live and records it (manual §1).
- Gitesh installs capture 1.16 on the Mac and the iPhone (it replaces the uninstalled 1.15) and presses as usual. The
  first press should show "N parts" for Ryanair, Virgin and China Eastern and about 2,000+ lines each; Claude checks
  `game_statement` reaches 24 hours back and that the 1.15 salary line reads right (the handover's open check).

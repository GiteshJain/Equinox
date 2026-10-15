# Build spec: capture page checks (#21) and the Systems board (#23) — 14 Oct 2026

**Why:** decisions #21 and #23, both decided 14 Oct (`docs/decisions.md`; briefs
`docs/briefs/2026-10-14-capture-safeguards.md` and `docs/briefs/2026-10-14-monitoring.md`). Built together because both
show on Check and Home. On 11 and 12 Oct no capture came in and nothing said so for two days; about 780 flights' loads
were lost for good. Nothing judges whether a capture's pages are complete, and nothing shows "all good", deploys or
usage.

## Part 1: each capture page checked as it arrives (#21, option B)
- **The check, in the database,** when a page is stored (`private.capture_store()` / `capture_page()`), one verdict per
  page: **ok**, **short** or **broken**, with what was expected and what came:
  - **loads:** flights read against the airline's flights scheduled in the page's window (its legs); short below
    `settings.capture_loads_min_share` (0.9);
  - **statement:** lines read against the airline's recent captured nights (short below
    `capture_statement_min_share` of their median, 0.5), and none at all is short;
  - **balance:** the cash account (2800…) present, else broken;
  - **events, income statement:** rows present, else short;
  - **a page that fails to parse:** broken (the raw page stays for inspection, as now).
  The limits are settings, with descriptions. Keep each verdict where Home and the board can read it (a small table or
  columns on the raw pages; your choice, described).
- **The capture's reply** carries the verdict, and the capture panel shows one line per airline: "all good", or what came
  in short or broken ("loads 12 of 78 flights"). **Prefer a way that needs nothing from Gitesh** (the panel already
  prints what the reply gives). If the userscript must change, keep it to a few lines and say exactly how he updates his
  copy (his key stays in it; never commit a key).
- **`capture_status()`** gains each airline's latest verdicts. **Home's "needs attention"** lists a short or broken page
  the same night, in the capture group, linking to Check.
- **Tested on saved pages:** a small dated sample of each page kind (one airline, one evening, in `tests/fixtures/`),
  with the rows it must give, run wherever the database is tested; plus cases that must be judged short or broken (half
  the loads rows, no statement lines, a balance sheet without the cash account, a page that doesn't parse). The
  rehearsal's replay of every kept page must judge each real evening ok.

## Part 2: the Systems board on Check (#23, option B)
At the top of Check, one line each with a green, amber or red mark, and when:
- **the evening capture** (each airline: when, and #21's verdict);
- **the daily snapshot** (taken by the capture, or by the fallback and so incomplete);
- **the nightly backup** (last good copy, its restore check, its size);
- **the monthly archive** (this month's state; due by the 3rd);
- **the clean-ups** (last run);
- **the world scan** (its age: amber over 8 days, red over 15);
- **the planner's own build** (the time and change it was built from, written in at build time; shown so a failed
  deploy is visible after a merge);
- **usage the database can measure,** each against its trigger (manual §1): database size (350 MB), the report PDFs in
  `site_reports` (50 MB), the size of `site_public()` (500 KB). Amber from 70%, red at the trigger.
- Marks use the same limits as Home (manual §7: capture 26 and 48 hours, backup and snapshot 30 hours, archive by the
  3rd, any job's last run failed). Home keeps flagging problems; the board is where "all good" shows.
- The database figures come from one staff function (for example `system_status()`), read only. A line with nothing
  recorded shows its last run getting old.

## Database
One migration that adds or replaces only (new settings, the verdicts' home, the staff function, replaced functions with
the same arguments), with descriptions, applied from the chat after "merge". Tests in `database/tests/`.

## Checks
- **Unit tests:** the board's marks at each limit; the panel's verdict wording.
- **Database tests:** each verdict on the saved samples and the broken cases; `system_status()`'s figures on the copy.
- **In the rehearsal:** the replay judges every kept evening ok; Check's board renders on the copy with every line
  marked; Home lists a short page made on purpose (then put back); 380 px with no sideways scroll; the recorded save
  answers and screen checks from the clean-up still pass.
- **A deliberate failure,** seen to fail then removed: a loads page with half its rows judged ok (a database test and
  the rehearsal must go red).

## Docs, in the same pull request
The manual §7 (each page checked; the Systems board; the monthly usage look keeps only Supabase's egress and the
website's calls a day) and *Decided, not yet built* (#21 and #23 built), the map (what runs when, where to see it),
`docs/planner-guide.md` (Check's board), `capture/` notes if the userscript changes, `tests/README.md`, `docs/data.md`
(regenerated).

## Rules for the helper
- Follow `CLAUDE.md`. Read `.claude/skills/supabase-postgres-best-practices/SKILL.md` for the migration.
- **Work lean:** check on GitHub runs every few minutes rather than continuously, and don't read beyond what the build
  needs.
- **Never connect to the live database or use the Supabase connector tools.** Never commit a key.
- Work on branch `capture-checks`, open the pull request with the REST API, and don't merge.

## Done when
Every check is green and the deliberate failure was seen to fail, then removed. The pull request says what changed, the
run time, what the verdicts said on the kept evenings, any finding, the steps after "merge" (whether Gitesh has to do
anything, and the migration applied from the chat), and how to roll back.

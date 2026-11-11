# Faster checks on a pull request — 11 Nov 2026

**Decision:** whether, and how, to make the *Database rehearsal* run only what a change can break, so a pull request
waits minutes instead of 20 to 31.
**Recommendation:** E, in two pull requests: first run only the parts a change can affect, with the full rehearsal
every night on `main` (D, one pull request, before the glass build); then run the slow parts side by side. The glass
look's pull requests would wait 8 to 11 minutes after the first step and 5 to 8 after the second, instead of 20 to 31.
Nothing a look change could break goes untested.

Minutes a pull request waits for the rehearsal. *Checks* (about 2.5 minutes) runs alongside in every option. The range
is a slow runner to a fast one: GitHub gave us both on 11 Nov, with the same steps and the same image (see Background).

| Option | Planner look only (glass look) | Database change | Documents only | Protection kept or lost | Effort | Risk | Easy to undo? |
|---|---|---|---|---|---|---|---|
| A Leave as is | 20–31 | 20–31 | 0, or 20–31 if it touches the map or `docs/data.md` | All kept | None | Builds stay slow; each red run costs another 20–31 | n/a |
| B Run only the parts a change can affect (one job) | 8–11 | 20–31 | 0, or about 3 for the map | All kept for the change itself. Lost: other changes already merged to `main` are no longer re-tested on each later pull request (they were tested on their own) | 1 pull request (workflow and `rehearse.sh`) | A path put in the wrong group skips a part it needed. Unknown paths run everything | Yes: put the workflow back |
| C B, plus the slow parts side by side as separate jobs | 5–8 | 7–11 | 0, or about 3 for the map | As B | 2 pull requests (B, then the split) | More moving parts: five copies restored at once, one comment made from five results | Yes |
| D B, plus the full rehearsal every night on `main`; the briefing and map guide run on a pull request only when the briefing or library changes | 8–11 | 18–28 | 0 | As B, and gained: everything is re-tested every night on new data and on `main` as merged. Moved to the night: the briefing and the map's guide for a change that doesn't touch them (caught within a day) | 1 pull request | A failed night must show somewhere Claude looks (a Systems line or an issue) | Yes |
| **E C and D together** | **5–8** | **6–10** | **0** | As D | 2 pull requests | As C and D | Yes |

Effort counts build pull requests. None needs money: the repository is public, so GitHub's standard runners are free,
side by side too.

## Where the 20 to 31 minutes go
Measured from the timestamps in each run's log (`gh api .../actions/jobs/<id>/logs`), from one `==` heading in
`database/rehearse.sh`'s output to the next. Every part ran in all four runs.

| Part | #151 planner (run 43019391073) | #150 database (43002791037) | #149 documents (42988875238) | #148 documents and a check (42984487997) |
|---|---|---|---|---|
| Set-up: backup from R2, CLI, psql, browser | 0.6 | 0.6 | 0.7 | 0.8 |
| Start the local Supabase and restore the backup | 1.6 | 1.3 | 1.3 | 1.5 |
| Save outputs before the changes (13 files) | 1.2 | 1.7 | 1.8 | 1.6 |
| Apply migrations (2, 2, 1, 1) | 0.0 | 0.0 | 0.0 | 0.0 |
| Database test: `capture_data_replay_test.sql` (replays every kept capture page, judges each evening) | 4.0 | 7.7 | 8.2 | 7.6 |
| Database test: `briefing_test.sql` | 1.6 | 2.9 | 3.0 | 2.8 |
| The other 66 or 67 database tests | 2.3 | 4.1 | 3.1 | 2.9 |
| Figures moved | 0.1 | 0.2 | 0.2 | 0.1 |
| Descriptions, reference file, types generated | 0.0 | 0.0 | 0.0 | 0.0 |
| Planner build (`npm ci`, build) | 0.1 | 0.1 | 0.1 | 0.1 |
| Planner on the copy: sign-in, refusal, each screen opened, saves through `__eqPlanner`, preview | 1.3 | 2.4 | 2.4 | 2.5 |
| Planner: every screen at 1280 and 380 px | 1.4 | 1.8 | 1.8 | 1.8 |
| Planner: Systems board, short page, unattended capture, addresses | 0.5 | 1.4 | 1.4 | 1.5 |
| Airline briefing for every airline, then the map's guide (0.4 to 0.7 of it) | 1.6 | 2.8 | 2.8 | 2.6 |
| Every kind of save | 2.7 | 2.8 | 2.9 | 2.8 |
| Backup and restore after the changes | 0.6 | 0.7 | 0.7 | 0.6 |
| Keep artifacts, post the comment | 0.2 | 0.2 | 0.2 | 0.2 |
| **Whole run** | **19.7** | **30.7** | **30.3** | **29.4** |

What the table shows:
- **The database tests are half the run** (8 to 15 minutes), and one of them, the capture replay, is a quarter of it.
  Restoring the copy is only 1.3 to 1.6 minutes, so a prepared copy kept between runs would save little.
- **Every run did the database work, documents too.** "Applying new changes" means every migration newer than last
  night's backup, so on a day something reached `main` after the backup, every later pull request applies it, tests it
  and backs it up and restores it again. #148 and #149 each re-tested `20261111010000_statement_no_rewrite.sql`, which
  #147 had already tested and put live. So "backs up and restores when there are database changes" in practice means
  "on any day a migration was merged".
- **#148 and #149 ran the rehearsal only because they changed `docs/architecture.md`**, which is on the rehearsal's list
  because the map's guide is run on the copy (40 seconds of it). `docs/data.md` is on the list for the descriptions check.
- **The fast run was the machine, not the work.** #151 did the same parts as the others; its database parts took half
  as long, while the saves, which wait on the browser, took the same. Of the last 29 runs that passed, the shortest was
  18.5 minutes, the middle 29.5, the longest 36.
- **Red runs double the wait.** Of the last 60 rehearsals (30 Oct to 11 Nov), 27 failed and 4 were cancelled. A failure
  is found only near the end: the descriptions check (`docs/data.md` not regenerated, 6 failures) and the types check
  (2) run after the database tests, about 18 minutes in, though they need only the restored copy.

## What each part protects, and which pull requests need it
| Part | Can be broken by | Needed for |
|---|---|---|
| Restore the copy, apply migrations | Database change | Every pull request that runs any part below |
| Outputs before, the database tests, figures moved | Database change (they are SQL only: none reads the planner, the library or any script) | Changes to `database/` |
| Capture replay (a database test) | A database change to the capture's storing and reading (`private.capture_store()` and the tables it fills). A change to the capture userscript doesn't reach it: the userscript is tested by *Checks* on saved pages and doesn't start the rehearsal | Changes to `database/` |
| Descriptions and reference file | Database change, `docs/data.md`, `database/current/` | Those |
| Types generated | Database change, or editing `types.ts` by hand | Database and planner changes |
| Planner on the copy, every screen at two widths, addresses | Planner code, planner look (a screen that errors or scrolls sideways at 380 px), the library, the database it reads | Database, planner (look included), library, `web/_redirects` |
| Every kind of save | Planner code or look (a hidden or moved control), the database it writes to | Database, planner (look included), library |
| Airline briefing on the copy | The briefing's script, the library, the database it reads | `scripts/briefing/`, `scripts/report/analyze.py`, `lib/`, database |
| The map's guide on the copy | The map's text, the database's calls | `docs/architecture.md`, database |
| Backup and restore after the changes | Database change | Changes to `database/` |

So a look-only planner change needs the restored copy, the types, the planner on the copy and the saves, and nothing
else. Those are the parts that judge a look change: every screen at 380 px with no errors and no sideways scroll, and
every save made through the screen's own controls. The real catch on 30 Oct shows why they stay: the charts pull request
for Competition failed on "route page opens" (run 41107888415).

## How each option works
- **B** Each part runs when the pull request changes a path the table above lists for it, compared with the base
  branch. Any path not on a known list runs everything, so a mistake costs time, not protection. Migrations already on
  `main` are still applied (milliseconds), so the planner meets the database as live has it, but their tests aren't
  re-run on later pull requests. The descriptions, reference and types checks move to right after the migrations, so
  their red shows about 4 minutes in rather than 18.
- **C** The same parts, in up to five jobs at once, each with its own restored copy: the capture replay; the other
  database tests with the backup and restore; the briefing test, briefing and guide; the planner's screens; the saves.
  A last job posts one comment. The longest job, the replay, sets the time for a database change.
- **D** B, plus the whole rehearsal once a night on `main`, after the nightly backup (19:33 UTC). It catches what a
  pull request no longer re-tests: a test that new data breaks, and two merged changes that clash.
- **E** C and D together.

Dropped:
- **A prepared copy kept between runs** instead of restoring each time: restoring is 1.3 to 1.6 minutes (5 to 8%), and a
  kept copy can go stale. Not worth it.
- **Moving the planner's screens or saves to the night**: the planner goes live when merged, so a broken screen would
  stay live for up to a day.
- **Moving the database tests to the night**: Claude applies a database change to live right after "merge", so it must
  be tested before.
- **A faster machine**: larger GitHub runners cost money. The 20 to 30 minute spread is GitHub's choice of machine.
- **Running the capture replay only when a change touches the capture**: it's the slowest part, but a migration that
  doesn't name a capture function can still break it through a table it writes, and that's hard to tell from paths.
  In C and E it runs alongside everything else.

## Which sentences of the manual change (rule changes, Gitesh's to agree)
In `docs/operating-manual.md` §1, **Automatic checks**:
- B, C, D, E change "When the database, the planner or the library changes, the *Database rehearsal* also generates the
  planner's types … ; reads a saved evening of each capture page kind and replays every kept capture page, each evening
  judged ok (#21); and when there are database changes, it backs the copy up and restores it as the nightly job does."
  It would say that the planner's parts (types, sign-in, every screen at both widths, every kind of save) run when the
  database, the planner or the library changes, and that the capture replay, the database tests and the backup and
  restore run when the pull request changes the database.
- D and E add one sentence: the full rehearsal runs every night on `main` after the backup, and a failed night shows
  on the Systems board (or wherever Gitesh chooses).
- C alone changes no sentence: running side by side changes how the parts run, not what they check.

**Preview before live** ("Every pull request that changes the database is rehearsed … which posts the result on the
pull request") stays true in every option.

`tests/README.md` (the *Database rehearsal* row and "The planner on the copy") and `docs/map/checks.md` would change in
the same pull request.

## Scenarios and the risk of waiting
- Leaving it as is: the glass look's six pull requests wait about 2 to 3 hours on the rehearsal in all, more with any
  red run.
- With D or E's first step in place before the glass build: about 1 hour in all. After the second step, about 40 minutes.
- If a path is put in the wrong group, a part is skipped on that pull request. The nightly run catches it within a day,
  and unknown paths run everything.
- Waiting costs only time. Nothing is less safe today.

## What would change the recommendation
- Database changes becoming rare: then B or D alone (one pull request) gives most of the gain, and C's split isn't worth
  its moving parts.
- If no planner screen or line is the right place to show a failed night, D and E lose their safety net. Then B
  alone, or C.
- If the capture replay is split by airline across jobs (a test change), a database change could drop to about 5
  minutes.

## Outcome
<Gitesh's decision and the date; rule changes made in the manual>

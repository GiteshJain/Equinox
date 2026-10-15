# Capture safeguards — 14 Oct 2026 (decision #21)

**Decision:** how the evening capture protects itself: its page readers tested on saved pages, and you told when an
evening's capture is missing or short.

**Recommendation:** C. Check every page as it arrives, and alert your phone when the evening's capture is missing or
short.
- Two evenings were missed this week (11 and 12 Oct) and nothing told you for two days. Those days' loads are gone for
  good: about 780 flights (11 Oct has loads for 139 of about 465 flights, 12 Oct for 9).
- Today the capture panel lists row counts without judging them, and Home warns only after 26 hours, once you open it.
  By then the game's loads page (the last 24 hours) has moved on.
- C judges each page as it arrives, says so in the panel and on Home, and alerts you through GitHub, which you already
  use: an evening reminder if the capture hasn't arrived, and a morning note if the fallback had to step in or a page
  was short.

One pull request, about 2 to 3 hours. $0 a month.

*Columns adapted for a non-game decision.*

| Option | What changes | Effort | Gain | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Keep as is | Nothing. The panel's counts, Home's 26-hour warning and the rehearsal's replay stay | None | None | Missed evenings keep costing loads for good (about 780 flights this week); a change to a game page could cut rows unnoticed | — |
| B. Check each page | Each page is checked against what to expect as it arrives (loads against the flights scheduled, the statement against recent nights, the cash account present). The panel gives a verdict per airline ("all good", or "short: loads 12 of 78"), and Home lists it the same night. A small dated sample of each page kind is tested on every pull request | 1 pull request, about 2 hours | Short or broken pages caught the same evening | A missed evening still shows only on Home, after 26 hours | Yes |
| **C. B, plus an alert** | **B, plus a free GitHub check that opens an alert (GitHub's app or email tells you) at a set evening time if the capture isn't complete, and after the 10:00 UTC fallback if it had to take the snapshot or a page was short. The alert closes itself when the capture arrives** | **1 pull request, about 2 to 3 hours** | **Missed evenings caught while the loads can still be saved** | **An alert on a night you skip on purpose (it closes itself once you capture; a setting turns it off)** | **Yes: one setting** |
| D. B, plus a Claude task | B, plus a daily Claude scheduled task that checks and pushes a message to your phone, with what to do | 1 pull request, plus a scheduled task | As C, with a written explanation | Uses Claude every day; it belongs with #25 (unattended jobs and their spending cap) | Yes |

## Background

### What protects the capture today
Repository `main` and the live database, 14 Oct.
- **The capture panel** lists each page's rows ("loads 78 flights", "statement 312 lines, 5 pages") or its error. It
  doesn't say whether the numbers are right.
- **Home** warns when an airline hasn't been captured for 26 hours, and turns red at 48 (manual §7), but only when you
  open it.
- **The 10:00 UTC fallback** takes the day's snapshot when no complete capture did, and marks it incomplete. No one is
  told.
- **The rehearsal** replays every kept page (14 days) through the readers and checks the rows come out the same. That
  guards changes to our code. It can't catch a change in the game's pages: the replay would be wrong the same way the
  capture was.

### What a normal evening looks like
`game_capture_raw`, 7 to 14 Oct: every captured evening has 6 airlines with 5 pages each, about 474 loads rows and about
4,300 statement lines. That steadiness makes "short" easy to judge: loads rows under 90% of the flights scheduled
that day, a statement with no lines, a balance sheet without the cash account. The limits would be settings.

### What the missed evenings cost
No capture on 11 and 12 Oct. The fallback took both snapshots, marked incomplete. Flights with loads, by game date:

| 10 Oct | 11 Oct | 12 Oct | 13 Oct | 14 Oct |
|---|---|---|---|---|
| 467 | 139 | 9 | 364 | 458 |

Money suffers less, since the statement covers the last 3 days. The loads, route loads and load patterns for those
days stay thin.

### How the alert would reach you (C)
A GitHub Action on a schedule (free) asks the database, through a function that needs a secret, whether the evening's
capture is complete and whether any page was short. If not, it opens an issue in the repository ("Capture missing for
14 Oct"). GitHub's app or email tells you, and the issue closes itself when the capture arrives. There's no new
service, and the secret lives in GitHub's settings like the backup's. The evening time is a setting. Check that
GitHub's notifications reach your phone; the pull request will say how.

### Risks
- **A false alarm on a night you skip on purpose.** It says so plainly, closes once you capture, and a setting turns it
  off.
- **Limits set too tight or too loose.** They're settings; the first week's verdicts get a look at the Saturday review.
- **GitHub's schedule can run a few minutes late.** That's fine for an evening reminder and a morning note.

## Outcome
14 Oct 2026: Gitesh chose **B**: each page checked as it arrives, with a verdict in the capture panel and on Home, and a
dated sample of each page kind tested on every pull request; no alert outside the planner. Recorded in
`docs/decisions.md` and the manual's *Decided, not yet built*.

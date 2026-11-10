# Brief: what the unattended capture does, and how often

Building chat, 10 Nov 2026, on Gitesh's question to the spec `docs/specs/2026-11-10-unattended-capture.md`: "Why can't
this one do the scan and market pages at least? I think twice a day is ok." An amendment to the brief
`docs/briefs/2026-11-10-unattended-capture.md` (option C), whose runtime and pages it changes.

## Decision and recommendation
**Recommended: B.** The unattended capture runs **twice a day** (09:30 and 21:30 UTC) and also does the **world scan and
the market pages when they're due**. Salaries stay with Gitesh's own press for now. Each of the three is a setting, so
moving salaries over later is a data change, not a build.

## Why the spec left them out
Not a limit of the job: the first brief kept the unattended run small (about 3 minutes, our own pages only, nothing
unwatched beyond what the press already reads), so that Gitesh's press kept the slow, rarer parts. Nothing in the game
or GitHub stops the job doing them.

## Options
| | A. As specced | B. Twice a day, with scan and market | C. B plus salaries |
|---|---|---|---|
| Runs a day | 4 (every 6 h) | 2 (09:30, 21:30 UTC) | 2 |
| What a run reads | our pages and fleets, ~140 | the same, plus the scan once a day (~500 pages, ~8 min) and the market pages once a week (~690, 10 to 15 min) | as B |
| Gitesh's evening press | needed every day (scan, market, salaries) | only for salaries; the scan and market are done by whichever capture comes first | optional |
| Loads lost when | 4 failed runs in a row | 2 failed runs in a row (each failure emails) | as B |
| GitHub minutes a month (of 2,000; backup ~120) | ~480 | ~550 (one market run is the longest, ~20 min) | as B |
| Game effect unwatched | none | none (the market pages set listing filters, as now; no prices) | salary raises, raise only, to 5% above the country average |
| Risk | lowest traffic unwatched | ~1,200 pages a day unwatched instead of ~280: the same pages the press reads now, at the same pace | as B, plus money changing with no one looking; the salary step (1.15's fix, live in 1.16) hasn't been seen working yet |
| Easy to undo | yes | yes: settings | yes: settings |

Growth, profit and cash are the same in all three: the data comes in either way. The difference is how much Gitesh has
to do and how much can go wrong unwatched.

## Background
- The game keeps loads and the bank statement for 24 hours. Twice a day leaves 12 hours of slack after one failed run.
- The scan is due once a capture day (`scan_every_days`, 1) and the market pages once a week (`market_every_days`, 7):
  whichever capture comes first after they fall due does them, Gitesh's or the job's.
- Gander's owner allows Gitesh's scripts (#12, manual §9). The first brief noted that penalties fall on the whole
  account; B reads no page the press doesn't read now.

## What would change the recommendation
- Runs that fail often: back to four a day (a setting and a schedule change).
- The salary step proven on a few presses (the panel's line right): then C costs nothing more.

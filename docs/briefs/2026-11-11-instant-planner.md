# Making the planner instant in use — 11 Nov 2026

Building chat, to-do 223 (decided in outline by Gitesh in the Audit chat, 11 Nov). His goal, in his words: "I just want
it to be superfast when actually using it, even if it's slightly slow to open first time in a session." And earlier:
"planner should just show a landing page after a capture while it's still reading / calculating. So that once it's
online everything is super fast."

**Decision:** how the planner gets its figures, and when it shows a landing page.
**Recommendation: A.** The database works every figure out once after each capture and stores it. Opening the planner
shows a landing page while it loads everything, and then no screen waits until the next capture. During a capture the
planner keeps the last answers, with a line saying a capture is running. The landing page shows again only for the
minute or so that the new answers take to work out and load.

| | A. Stored, landing page while the new answers load | B. Stored, landing page for the whole capture | C. Not stored: everything loaded live at opening | D. Quick fixes only |
|---|---|---|---|---|
| First opening | about 5–10 s, estimated (a 1.5–2 MB download, nothing worked out) | the same | 30 s or more (all the work, every time); under load slower, with failures | as today: 5–40 s a screen |
| Moving between screens | instant | instant | instant, until the next capture | as today, a bit better |
| A route's page | instant once the background has worked it out (about 20 min after a capture); before then about 3 s | the same | about 3 s each | about 3 s each |
| Right after a capture | about a minute on the landing page, then instant | landing page for the whole capture: about 3 min at the 15:00 IST run, about 8 min at the 03:00 run (world scan), up to about 20 min once a week (market pages), and on every press of his own | the next screen change loads everything again (30 s or more) | no change |
| A save that changes figures (fare plan, plan cards, orders) | that board reads its figures again at once, as today (1–3 s); the stored answers follow within a minute | the same | the same | the same |
| Database work | about 30 s after each capture, plus the route pages in the background | the same | about 30 s on every opening | as today |
| Build | two pull requests (database, then planner) | the same | one (planner only) | one small |
| Risk | stored answers falling out of step with the live ones: a check compares them on every pull request | as A, plus locked out of the planner when a capture runs long or stalls (a time limit lets him in) | the same request burst that failed 16 calls on 11 Nov | doesn't meet the goal |
| Easy to undo? | yes: the planner can be pointed back at the live functions | yes | yes | yes |

Growth, profit and cash don't change under any option: this is about how fast the tool answers, not what it says.

## Background
**Why it's slow today** (the request log and timings in to-do 223, 11 Nov). Every figure is worked out from the raw
tables each time a screen asks, and nothing is stored. A screen sends 30 to 50 requests at once, and the free plan's
database answers a few at a time. 05:58–05:59 UTC: 104 requests, the slowest 42 s, 16 failed (500). Medians over the
day: competition 10.2 s, system_status 11.4 s, cash_log 12 s, growth_signals 5 s.

**Found today, reading the planner's code:** several figures are asked for more than once under different names, so
the browser can't share the answer. growth_signals (369,000 characters) is fetched three times (Home, Performance's
growth signals, Routes' load patterns), and route_loads and airline_cards twice each. Systems asks capture_status 14
times for its 14-night history. Every call also carries "now" to the millisecond, so no two answers are ever the same
request. D fixes only these.

**What a full refresh costs** (measured 11 Nov, about 09:10 UTC, every figure the planner reads, all six airlines, one
after another): **30.1 s and 5.4 MB of text.** The fare ladder took 5.2 s (1.4 MB), competition 8.3 s (0.5 MB), the
fare results 0.9 s (0.9 MB), the cash forecast, profit, fare plan and fare changes 7.8 s (0.9 MB), route and aircraft
profit for 1, 3 and 7 days 4.5 s (1.0 MB), and the world-wide figures 3.3 s (0.8 MB). The planning library's input,
rules_input, is another 2.7 MB. Route pages are about 3 s and 51,000 characters each; 419 routes are flown.

**What a first opening downloads:** Supabase compresses its answers (site_public: 193 KB sent as 38 KB, 11 Nov), so
about 8 MB of figures and input is about 1.5–2 MB over the wire. That is the estimate behind "5–10 s"; the build
measures it before and after. At about 10 openings a day that is well under §1's 4 GB egress trigger.

**Room in the database:** only the latest set is kept, each refresh replacing the last: about 5 MB of figures and
about 21 MB of route pages before the database compresses them, against 192 of 350 MB (11 Nov). Replacing 26 MB twice a
day leaves dead rows behind, as the statement table did before 10 Nov, so the spec has the refresh clear them.

**When the refresh runs:** a scheduler job checks every minute whether anything the figures read has changed since
the last stored set: a complete capture (the snapshot), a finished world scan, a finished market run, or a save in the
planner. When something has, it works the figures out again, one at a time, in its own time limit, outside the
capture's 30-second calls. A capture's own pages never wait for it.

**Figures that read the clock.** A few figures move with the time of day as well as with captures: the cash
forecast's 14 days, "can order from 14:00", and the 7-day windows. Stored answers are as of the moment they were
worked out, and the planner says so ("as of the 15:00 capture"). Where a figure names a time, the planner compares it
with the clock itself. The capture's and the systems' own status lines stay live; they're light alone.

**If the refresh fails or runs long:** the planner never stays on the landing page. After a time limit (about
5 minutes) it opens with the last stored answers and a line saying they're from the previous capture, and the Systems
board gets a line for the stored figures.

**Nothing is kept on the device:** under A, B and C the answers stay in the browser's memory until the next capture or
until the tab closes, as today (design §14, choice 3). Keeping them on the device would make even the first opening
instant, but it reverses that choice, so it isn't offered here.

## Scenarios and the risk of waiting
- **A goes well:** one short wait when the planner opens, then every screen opens at once. After the 15:00 and 03:00
  IST runs, about a minute on the landing page.
- **A goes badly:** a stored answer drifts from the live one (a figure changed in the database but not in the
  refresh). The check on every pull request compares each stored answer with the live function on the rehearsal's
  copy, so a drift fails before it merges.
- **B:** the same speed, but the planner is shut while a capture reads. The answers from the previous capture are
  still correct while it reads, so the lock-out buys nothing except never showing figures a few minutes old.
- **C:** the smallest build, but each opening repeats 30 s or more of work on the small database, the work that made
  16 calls fail this morning.
- **Waiting:** the planner stays as it is: 5–40 s a screen at busy moments, with occasional failed boards.

## What would change the recommendation
- If Gitesh wants the planner shut during every capture, as he first described: B. It's the same build with a
  different trigger for the landing page.
- If the first opening measures well over 10 s: load the route pages and the less-used boards (Systems' history,
  Flights by day) after the landing page, in the background.
- If the refresh grows past a few minutes as the network grows (the fare ladder grows with the routes): work out each
  airline's figures as soon as it is captured, instead of all at the end.

## Outcome
**B**, Gitesh, 11 Nov (Building chat): the landing page for the whole capture, until the new answers are stored
and loaded. Recorded in the manual's *Decided, not yet built*. The spec follows.

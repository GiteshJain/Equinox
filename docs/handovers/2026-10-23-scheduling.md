# Scheduling chat handover — 23 Oct 2026, 23:55 UTC (18:55 Chicago)

Start as usual: read the operating manual, `docs/decisions.md` and the playbook, then check the planner's live state.
Figures below are as of 23:55 UTC on 23 Oct; the last capture was 15:00 UTC (all six "all good").

## New since the last handover (22–23 Oct)
- **The used aircraft market is in the evening proposal** (manual §3, "The used market too"; how auctions work, §9).
  Each evening ask Gitesh for a screenshot of the game's Aircraft Market and look at every offer on the default line.
  Bid only where it flies the chosen routes for less than new, at most the new aircraft's own price. An auction ends
  an hour after the last bid; the money bid is held until it ends (it comes back if outbid). Unsold aircraft get
  cheaper the longer they stay listed. The ferry from wherever it's parked costs nothing.
- **Replacement by age** (manual §3): new aircraft at 3 years, used at 10. A used aircraft must have at least a year
  left, so 9 years old at most. Four used aircraft so far: N023AW (JFK), 9M-AAY (KUL), G-AAFB (LGW), VT-ABE (DEL);
  each `order_note` says "Used" with its price. The fleet check counts aircraft due for replacement (`replace`, 0 now).
- **Planner registrations:** the game names a used aircraft with the airline's next registration on arrival, so log
  the order with the expected registration and correct it when Gitesh reports it (Ryanair's new SHARP came as EI-ACF,
  skipping ACD and ACE).
- **Briefs** for each order are in `docs/briefs/2026-10-22-*` and `2026-10-23-*`; each has its outcome.
- **The cash forecast's lowest point can already be in the past** between captures: read the lowest point from now on
  (`points` after now), or ask Gitesh for the cash the game shows. Virgin's VT-ABG bid nearly got turned down on a
  past low.
- **Fitting a cabin a few hours under the 0.5M cushion** was accepted once (G-AAFB, Virgin at 0.46M, nothing due for
  13 hours). It's not a rule; ask each time.

## Waiting on Gitesh
- **File VT-ABE (DEL)** on card 140 (KF1077–1082: Sharjah 20:20, Jaipur 04:58, Almaty 08:56, Delhi time; cabin
  `E195-LEI`). Arrived 16:33 UTC on 23 Oct, so due by about 16:30 UTC on 24 Oct. Still "on order" with no legs.
- **File EI-ACF (CDG)** on card 139 (FR3065–3072: Berlin 19:50, Milan Malpensa 01:14, Brussels 06:02, Zurich 10:00,
  Paris time; cabin `320S-STD`). Arrives 24 Oct 12:33 UTC.
- When he says each is filed, check it against the game (the next capture's fleet pages) and the card.

## Next evening's orders (24 Oct, after the capture)
Re-run `cash_forecast()` for all six; at 15:00 UTC on 23 Oct every airline was "from the next capture" except
Kingfisher and Ryanair, who ordered today. One airline at a time, used offers first, each mix checked with
`optimise` and `check-card` (rules_input(1,'all')) before recommending.
- **Kingfisher's A350s** (to-do 165, brief 2026-10-23-kingfisher-a350s.md): leases ended; VT-AAA (DEL) returns
  28 Oct 05:11 UTC, VT-AAB (DEL) 29 Oct 11:11 UTC, both flying Delhi–JFK until then. On each date: retire the aircraft
  in the planner, remove its KF1001/1002 legs, log the deposit (about 7.19M each), close #165 after both. Until then
  the forecast still counts their last lease payments and not the deposits. From 28 Oct Kingfisher's orders spend
  the deposits on Delhi narrowbodies (its top openings are 5-star and need an A320neo or larger).
- Until 31 Oct only new routes (Pan Am and China Eastern exempt); from 1 Nov the trunk month (manual §4).

## Open to-dos (Scheduling's)
- 32 connection-audit retimes, #114–145, due 24 Oct.
- #147: S3 for B-0162 (PVG) KWE–PVG 1034 and G-AADL (LGW) AGP–LGW 1038, then correct their cards.
- The airport checks (#150–157), #146, #148 and #161 belong to the Saturday chat; #167 to the Building chat.

## For the Building chat (passed on 22 Oct, not yet briefed there)
- An aircraft age check with an alert on the planner when an aircraft is due for replacement (manual §3). The
  planner doesn't record which aircraft came from the used market (only `order_note`).
- Check after a capture how the game words an auction's deposit, in case the capture files it as the wrong kind of
  payment.

## Tools that worked
- Optimiser and card check: clone the repository, `npm ci` and build `lib/rules`; `rules_input(1,'all')` is about
  2.6 MB, so save it to a file from the tool result and run `node lib/rules/dist/cli.js optimise rules.json <base>
  <dests> --type "<type>" --airline <id> --start 00:00-23:55 --step 5`. A card for an aircraft not yet in the planner
  takes `type` and `airline` and no `aircraft`.
- Plan cards: one SQL insert of the aircraft (status `on_order`), the card and its legs, after
  `set_config('equinox.actor','claude',true)`. Short plain notes go through; avoid long notes with special characters.

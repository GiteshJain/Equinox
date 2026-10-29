# Long haul only once an airline earns its deposit a day? — 28 Oct 2026

*Scheduling chat. Gitesh asked whether long haul (the A321XLR and the A350) should start only once an airline makes
enough money in a day to cover that aircraft's deposit. Figures: `airline_days` to 28 Oct (7-day averages),
`aircraft_types.price` (the order's up-front payment), `plan_lines` (empty).*

**Decision:** whether new long-haul flying waits until an airline's net cash a day covers one deposit of the type.
**Recommendation: B.** Yes, with four details: the 7-day average, per type, a started line is finished, and November's
long-haul trunks wait too. It ties long haul to scale, costs nothing today and settles the A350 question by numbers.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. No rule (judgement each time; A350 lines wait for the narrowbody-against-A350 question) | long haul whenever we choose | lower if lines start early: narrowbodies earn about 3× per unit of lease | an A350 line is about 49M of deposits; an early start can drain a mid-size airline | narrowbody openings and A320-family slots go to XLRs | high: the open question keeps coming back case by case | yes |
| **B. Net cash a day ≥ one deposit of the type (recommended)** | **long haul starts later: XLR lines roughly late Nov to early Dec, A350 lines roughly February (rough, from today's growth)** | **highest near term: every slot and dollar goes to narrowbodies until the airline is big enough** | **a line's daily deposit is paid by a day's earnings, so cash never dips below the cushion for it** | **long-haul markets left to rivals for a few more weeks (XLR) or months (A350)** | **low** | **yes (one number per type)** |
| C. Stricter: net cash a day ≥ the deposit **plus** one A321neo (2.4M), so narrowbody growth keeps its daily pace beside the line | long haul later still (XLR ≥ 5.26M a day, A350 ≥ 9.4M) | as B, a little more | safest | long haul pushed months further | rivals settle in long haul first | yes |
| D. A network trigger instead: long haul once the main hub reaches hubs first's 750 departures a week | ties to network shape, not cash | unclear: a big hub can still be cash-poor | not tested by it | as B | an airline could start a 49M A350 line on thin cash | yes |

## Background
- **What a deposit is.** An order pays its price up front (manual §9): A321XLR **2.86M**, A350-900 **7.01M**,
  A350-1000 **7.85M** (A321neo LIGHT 2.40M, E195-E2 1.77M). `aircraft_types.price`, 28 Oct.
- **Net cash a day**, the weekly report's figure (flight profit less leases and salaries), 7-day average to 28 Oct:

  | Airline | Net a day | Week before | Fleet now (week before) | XLR test 2.86M | A350-900 test 7.01M |
  |---|---|---|---|---|---|
  | Pan Am | 1.44M | 1.17M | 25 (21) | 50% there | 21% |
  | Kingfisher | 1.11M | 0.88M | 19 (17) | 39% | 16% |
  | Ryanair | 1.64M | 1.21M | 34 (30) | n/a (no long haul) | n/a |
  | Virgin | 1.67M | 1.19M | 27 (23) | 58% | 24% |
  | China Eastern | 1.77M | 1.41M | 28 (24) | 62% | 25% |
  | Malaysia | 1.77M | 1.39M | 27 (23) | 62% | 25% |

  Net cash a day rose 0.3 to 0.5M in a week as each airline added about 4 aircraft. At that pace (a straight line, so
  rough) China Eastern and Malaysia pass the XLR test in about 3 weeks, Pan Am and Virgin in 3 to 4, Kingfisher in
  about 5; the A350 test is about 13 weeks or more away.
- **Why scale matters for long haul.** Long haul flies in 7-aircraft lines (manual §4): an XLR line is 7 × 2.86M =
  20M of deposits, an A350 line 7 × 7.01M = 49M. At the test, a day's earnings pay a day's line aircraft, so a line
  is ordered in a week without stalling. The XLR also shares the A320-family delivery line with the narrowbodies
  (manual §3), so each XLR takes a slot a narrowbody would have had; the narrowbodies earn about 3 times as much per
  unit of lease (27 Oct long-haul brief).
- **What it costs today: nothing.** No line is open (`plan_lines` empty) and no long-haul order is planned. The
  current long-haul fleet (Pan Am's XLRs and A350-900ULR, Kingfisher's XLRs, Malaysia's XLRs and 9M-ABA's A321LR)
  stays as it is.
- **It answers a parked question.** The A350 lines were waiting for the narrowbody-against-A350 question; under B an
  airline starts A350s once it earns 7M a day, which answers it by scale rather than case by case.
- **Where it touches other rules.** November's trunks (manual §4) include long-haul trunks on the XLR and A350
  ("long-haul trunks are in too"); under B those wait for the test as well. Malaysia's long-haul trigger (§2, every
  4- and 5-star opening within the A320neo Heavy's reach flown) stays and both must be met. The A321LR is not long haul
  for this rule (it flies routes under 7,750 km, in the normal day).

## The details B needs
1. **The figure:** the 7-day average of net cash a day (flight profit less leases and salaries), as the weekly report
   shows it, so one strong or weak day doesn't decide.
2. **Per type:** an XLR line once it covers 2.86M a day; an A350-900 line once it covers 7.01M; the A350-1000 7.85M.
   One rule, the type's own price.
3. **A started line is finished:** once a line's first aircraft is ordered, its other six are ordered as the cash
   forecast allows even if net cash dips under the test; half a line leaves days with no flight (manual §4).
4. **November's long-haul trunks wait for it too;** the narrowbody trunks go ahead as planned.
The cash forecast's 0.5M cushion still applies to every order.

## Scenarios and the risk of waiting
- **Goes well:** narrowbody growth carries on at full pace; XLR lines open around late November to early December, one
  airline at a time, each line ordered in about a week; A350 lines follow once an airline is clearly large.
- **Goes badly:** a rival opens long haul on our pairs first (Icelandair is already one to watch at Gatwick), and we
  join a contested market later. Long-haul markets are big, so being second is a cost, but the game splits bookings by
  departures and fare, so a later daily line can still win share.
- **Risk of waiting to decide:** none today; it matters from the first long-haul order, at the latest in November's
  trunks.

## What would change the recommendation
- A rival starting heavily on one of our biggest long-haul pairs: a one-off exception, decided with its own brief.
- Narrowbody openings running out at a hub before the test is met: long haul would then be the only growth there.
- Evidence that a long-haul line earns as much per unit of lease as narrowbodies (the 3× gap closing).

## Outcome
**28 Oct 2026 (Gitesh): B, with the four details.** And November covers only trunks the A321LR or smaller can fly
(7,700 km); longer trunks wait for the cash test. Manual §3 (long haul waits for cash; fleet types; the openings in
November) and §4 (November's trunks; long haul in 7-day lines) changed the same night; old wording in
`rule-history.md`.

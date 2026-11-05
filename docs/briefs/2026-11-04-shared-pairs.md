# Shared city pairs: should two of our airlines fly the same pair? — 4 Nov 2026

*Scheduling chat. Raised by Gitesh: "routes which touch airports across airlines belong to both airlines? that way
whichever airline has money can operate and profits are divided across groups instead of some airlines struggling …
both get to operate higher profit routes … if same routes operate under different banners they should still share same
price." Figures: `route_profit()` and `airline_days` on 4 Nov, `flight_legs`, the AirlineSim handbook.*

**Decision:** whether a pair between two bases of different airlines of ours (a "shared pair": KUL–Delhi, Gatwick–Amsterdam,
JFK–Paris…) may be flown by both airlines, at one price, instead of by the one airline the country rule gives it (§2).

**Recommendation: C**, allow it in a narrow form now, without a build: either of the two airlines may add flights on a
shared pair while it sells out, priced at the owner's level, at most 6 such pairs until the planner can judge a pair
across airlines; decide the full build at the 5 Dec review. And treat the cash gap between airlines with the fare
ladder's speed (the lever that works), not with route sharing (which can't move cash).

## Four facts that decide it
1. **Cash can't move between our airlines.** Each is its own holding (house rules, §9). The handbook: "It's not possible
   to move money between a holding and a subsidiary, not even if you own 100% of the subsidiary shares", and our six
   aren't even subsidiaries of each other. Whoever flies a route keeps its profit. Sharing routes shares access, never
   profits.
2. **Which of our airlines flies a pair makes no difference to the passengers.** Bookings on a pair are divided among
   the flights on offer (§9), and connections across our airlines rate the same as within one: the handbook says
   interline transfers "follow the same transfer rules as your own flights", and the planning library already counts
   connections across all six. A Kingfisher flight on KUL–Delhi earns what a Malaysia flight earns there, feeds Delhi's
   bank as well as Kingfisher's own flights do, and feeds KUL's as well as Malaysia's do.
3. **There are no higher-profit routes to share.** Profit per aircraft hour, 7 days to 4 Nov (thousand AS$):

   | | Cross-airline trunks | Own trunks | Spokes |
   |---|---|---|---|
   | Pan Am | 6.0 | 6.2 | 5.9 |
   | Kingfisher | 6.1 | 6.5 | 5.4 |
   | Ryanair | — | 5.1 | 4.5 |
   | Virgin | 5.0 | 5.4 | 5.4 |
   | China Eastern | 0.8 (PVG–Kolkata) | 6.3 | 5.8 |
   | Malaysia | 6.5 | — | 5.4 |

   An aircraft earns 5–6.5k an hour wherever it flies. Cross trunks earn more per flight (51–58k on the Atlantic) only
   because each flight takes 8–10 hours. The airline with money gains nothing by flying another airline's trunk instead
   of its own full route, and loses nothing either.
4. **No airline is struggling per aircraft.** Flight profit a day per aircraft, 4 Nov: Pan Am 0.106M, China Eastern
   0.105, Malaysia 0.101, Kingfisher 0.100, Virgin 0.091, Ryanair 0.084. Cash differs (Kingfisher 3.0M, China Eastern
   3.6M) because of what each spent this week and the A350s Kingfisher returned, not because its routes pay less.

## What sharing would and wouldn't do
- **Wouldn't:** divide profits, or help a cash-poor airline. If Virgin flies Mumbai–Manchester, Virgin keeps the money.
  Kingfisher gets richer only by flying more itself, or by charging more.
- **Would:** let two airlines' cash go onto one trunk. In the trunk month that is the one real gain: a cross trunk
  owned by an airline that is short that evening still gets its flight, from the other end. Since profit an hour is
  the same everywhere, this costs the joining airline nothing.
- **Would, later:** give an airline somewhere to grow once its own region stops selling out (none is near that: 64 of
  65 trunks and nearly every spoke are 95%+).
- **Wouldn't cannibalise, if priced together:** the pair's demand splits across all flights whoever flies them, exactly
  as a second frequency by the owner would. The second airline only ever adds flights while the pair sells out, like
  any frequency (§3).

## Where it stands today
- **34 shared pairs are flown, each by one airline** (the country rule): Malaysia 11 (KUL–India and KUL–China, 322
  flights a week, 11.4M a week, 44% of Malaysia's profit), Virgin 15 (UK–Europe), Pan Am 5 (JFK–Europe), Kingfisher 2
  (Delhi–Paris, Delhi–Gatwick), China Eastern 1 (PVG–Kolkata, the one weak trunk).
- About 60 more shared pairs within the A321LR's reach are unflown (India–Europe 20, India–China 26, Chicago–Europe 8,
  JFK–Milan/Munich/Manchester, Dallas–Edinburgh, Seattle–Edinburgh, Kunming–Chennai). Under the 4 Nov rule the
  long-haul ones wait anyway.
- Correction to the Scheduling chat of 3 Nov: §4 does not let "any of our airlines" fly a trunk; §2's country rule
  still names one airline per cross trunk. This brief is where that changes, if it changes.

## What it would cost
- **One price needs one ladder.** Today each airline's ladder judges its own flights. Two airlines on a pair, each
  judged alone, drift apart within weeks: a new route holds 7 days while the other moves, Pan Am and China Eastern step
  7 points to the others' 5 and cap at 128% to 120%, Ryanair launches at 85% and caps at 105%. The fare plan would
  need one level per pair direction, judged on both airlines' flights, written as one row per airline (the game prices
  per airline), with the owner's step and cap.
- **Everything per route becomes per pair:** "fortified" and the sold-out signals (a Kingfisher flight added on
  KUL–Delhi must hold Malaysia's ladder for the week too, §5's capacity hold), route profit and the route page (two
  rows for one market), the weekly report, the evening proposal (which airline the next flight goes to). The rival
  pause and competition already treat our own airlines as "group", not rivals; the website's schedules and trip search
  already show all six.
- **Data:** a `routes` row per pair for the second airline (stars, market), about 90 rows; plan cards need it.
- **Ryanair:** its product (Standard cabin, service R) and ladder (85% launch, 105% cap) don't match a Virgin pair.
  At Virgin's price its flights still fill while the pair sells out; it just stops being the price airline there.
- **Two small game points:** the 60% fare floor applies "wherever another player flies the route, including our own
  airlines" (irrelevant above 85%); and if the game shares a market by airline rather than by flight (the manual says
  by flight), splitting our flights across two names could cost a little share against a rival. Watch a shared pair's
  combined load against an owner-only pair.
- **Tracking by hand until built:** the Saturday review sets the joiner's rows to the owner's level, reads the pair's
  loads across both airlines, and treats a joiner whose flights don't fill while the owner's do as a frequency to
  remove, not a price to cut.

## The options
| | A: as now | B: shared pairs, both operate, one price (full build first) | **C: shared pairs, narrow, no build** | D: no sharing; cash gap handled by the ladder |
|---|---|---|---|---|
| Who may fly a shared pair | the country-rule airline | both airlines whose bases it joins | **both, the second only to add a flight the owner can't fund that evening, while the pair sells out** | the country-rule airline |
| Price | each its own ladder | one level per pair, judged on all our flights | **the owner's level, copied to the joiner at each review** | — |
| Ryanair | — | at the pair's price | **decision: in at the owner's price, or out** | — |
| Build | none | ladder per pair, pair views, signals, report: 2–3 pull requests | **none now; at most 6 shared pairs until the 5 Dec review decides the build** | none |
| What it gains now | nothing new | the trunk month's cross trunks fortified from both ends | **the same, on the few pairs where it matters** | Kingfisher's cash grows faster (7-point steps, 128% cap, as Pan Am's since 22 Oct) |
| What it risks | a cross trunk stalls while its owner is short | a build on top of the default-price one; weeks of per-pair bookkeeping either way | **hand bookkeeping on a few pairs; a joiner's level drifting a step** | nothing on routes; fares a little above the cap we trusted |
| Undo | — | cancel the joiner's flights; the pair reverts | **the same, within the week** | lower the cap |

Why not B now: the gain is small (profit an hour is flat; every airline still has full routes of its own) and the
default-price build is already in the Building chat. Build B when a region saturates or the shared pairs pass six.
Why not A: the trunk month wants every cross trunk fortified, and the owner's cash is the only brake. Why D as well:
it is the only thing that changes an airline's cash, and it was the answer for Pan Am on 22 Oct.

## What C changes
- **Manual §2:** "One airline per city pair" gains the exception above (shared base pairs; the owner's level; the 6-pair
  limit until built; Ryanair per the decision). The route lists stay as they are; a joiner's `routes` row is added when
  it first flies the pair.
- **Manual §4:** in the trunk month, a cross trunk's next flight goes to whichever of its two airlines can fund it that
  evening, the owner first.
- **Manual §5:** on a shared pair the owner's ladder leads; the joiner's directions are set to the owner's level at the
  Saturday review (the planner's own moves for them are dropped before Put on the fare plan). A joiner's flights that
  don't fill while the owner's do are a frequency to take away, not a price to cut.
- **Manual §7, Saturday review:** the shared pairs' list: both airlines' flights, loads and levels together.
- **Decided, not yet built:** the pair-level ladder and views (option B's build), decided or dropped on 5 Dec.
- **Playbook:** step 7's evening proposal checks the owner's cash on a cross trunk before offering it to the other
  airline.
- **No game change:** prices are set per airline by the fares script as now; the interline between our airlines is in
  place.

## What would change the recommendation
- A region whose routes stop selling out while its airline has cash: build B then.
- A shared pair's combined load falling behind an owner-only pair's at the same price: the game shares by airline;
  stop joining.
- The game allowing cash between holdings (it doesn't today): sharing routes would then be the wrong tool twice over.

## Decisions needed
1. A, B, C (recommended) or D; C and D together is the full recommendation.
2. Ryanair on Virgin's UK–Europe pairs at Virgin's price: in or out.
3. For D: the 7-point step and 128% cap for Kingfisher now, or for any airline whose cash falls under 2M at the
   Saturday review.

Sources: AirlineSim handbook, Holdings vs. Subsidiaries (handbook.airlinesim.aero/en/docs/advanced/setup/holdings-vs-subsidiaries)
and Interlining (handbook.airlinesim.aero/en/docs/advanced/alliances-and-interlining/interlining); `route_profit()`,
`airline_days`, `flight_legs`, 4 Nov; manual §2, §3, §4, §5, §9; `rule-history.md` (21–22 Oct, the cap).

## Outcome
**4 Nov 2026 (Gitesh): A, as is.** "If you think not necessary let's leave as is." One airline per city pair (§2) stands;
no shared pairs, no build, no manual change. The fare-ladder lever for a cash-poor airline (D) was not taken up; it can
be raised at a Saturday review if an airline's cash falls behind.

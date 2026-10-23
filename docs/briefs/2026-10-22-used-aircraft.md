# The used aircraft market, starting with Pan Am's aircraft tonight — 22 Oct 2026

**Decision:** whether Pan Am's next aircraft comes from the used market (an auction) instead of a new order, and so
whether the used market becomes part of how we order.
**Recommendation:** B. Bid on **5Y-AAD**, an A320neo Light 3.6 years old, at the opening bid, flying the same JFK
schedule as a new A320neo SHARP. It costs 12% less a week, puts 0.24M less down, and the routes, connections and
maintenance are identical. If we're outbid, the new SHARP is ordered the next evening (A).

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A New A320neo SHARP | JFK–BOS ×2 (new 5-star pair), +1 JFK–ATL, +1 JFK–DTW: 56 departures a week, 103 connections | about 0.85M (flight profit ~1.05M less lease 0.206M) | **0.91M** (cash_forecast with the order) | Pan Am's A320 line is busy 21 h | Low: the usual new order | Lease, as every aircraft |
| B Used 5Y-AAD (A320neo Light, 3.6 y), opening bid | same schedule, same 103 connections | about 0.87M (lease 0.182M); less whatever age adds to maintenance | **about 1.14M** (forecast less the 1.82M deposit and the 0.16M cabin) | the A320 line stays free for the next evening's new order | Outbid: about a day of the aircraft lost (~0.15M of flight profit); maintenance cost of age unknown | Lease, as every aircraft |
| C Used 5Y-AAC (A320neo Light, 7.2 y), opening bid | same | about 0.90M (lease 0.150M); age costs more than B's | **about 1.47M** (1.50M deposit) | same as B | As B, with twice the age | Lease |
| D Buy any used aircraft now (no auction) | same | about 0.81M (110% of factory price: lease 0.236M) | about 0.73M | — | Pays 10% over a new order | Lease |

## Background
**Pan Am tonight** (capture 23 Oct 00:22 UTC, all six airlines "all good"):
- **Cash:** captured 3.92M, lowest point 3.13M at Friday's week-end closing (03:36 UTC). One aircraft fits within the
  0.5M cushion; a 189-seater and an E195 together do not (lowest −0.96M). `cash_forecast(1, p_orders)`.
- **The routes** (`competition(1)`, `route_profit(1)`, 7 days to 23 Oct): JFK–Boston is a 5-star pair Pan Am doesn't
  fly yet (Continental 48 and United 28 a week; rank 14 of Pan Am's openings and the top one allowed at JFK under hubs
  first, JFK at 259 of 750). JFK–Atlanta and JFK–Detroit are sold out on every departure and marked "add a flight";
  Pan Am is exempt from new routes only (manual §4). Boston 300 km (S1), Detroit 817 km (S2), Atlanta 1,222 km (S2).
- **The schedule** (`optimise`, rules_input of 23 Oct 01:20 UTC): JFK–ATL 10:40, JFK–BOS 16:56 and 21:00, JFK–DTW
  01:04 (local), 103 connections at JFK, maintenance 111%, 9.6 block hours a day. The optimiser gives the same answer
  for the A320neo SHARP, the A320neo Light and the A320neo. The ORD alternative (IAD, YYZ, MSP twice) opens three new
  pairs but makes 24 connections at 104%; set aside.
- **Cabin:** no route takes 65% of the block time, so Leisure (`320S-LEI`, or the Light's Leisure layout), fitted on
  arrival (manual §5).

**The used market** (the game's pages, 22 Oct, and AirlineSim's own documentation):
- Sellers are lessors (Tradewind Capital, Pacific Aero Leasing, GEMAS, Aircrest), as official offers. Each shows the
  next bid and the immediate purchase price, with the deposit and weekly lease for each, both 5% and 0.5% of the price,
  the same terms as a new order.
- An auction ends once an hour passes with no new bid; each bid restarts the hour. Money bid stays committed until it
  ends. Immediate purchase is 110% of the factory price (the E195-E2's 38.97M is 110% of its 35.4M list). Sources:
  [the aircraft market](https://www.airlinesim.aero/blog/2012/08/01/introduction-of-the-new-aircraft-market),
  [Handbook: building your fleet](https://handbook.airlinesim.aero/en/docs/beginners-guide/building-your-fleet/).
- Older aircraft cost more to maintain and, past about 20 years, put passengers off. None on offer is over 9 years.
- A new aircraft also ferries from the factory (tonight's arrivals sit at São José dos Campos and Toulouse), and the
  ferry costs nothing, so where a used aircraft is parked doesn't matter.
- On offer tonight, all on our default line: E195-E2 5Y-AAR (2.0 y), A320neo Light 5Y-AAD (3.6 y) and 5Y-AAC (7.2 y),
  A320neo HZ-ABA (3.9 y), A321neo Light VT-ABG (7.2 y) and VH-AGP (9.0 y), A321LR 5Y-AAE (4.4 y). At the opening bid
  they lease for 8–37% less than new; immediate purchase is always 10% more. Few players seem to be bidding (Gitesh).

## Scenarios and the risk of waiting
- **B goes well:** no one bids against us; the auction closes an hour after our bid, the aircraft is ours tonight,
  Pan Am saves 0.024M a week for as long as it flies, and the A320 line is still free for the next evening's order.
- **B goes badly:** someone outbids us. Pan Am has lost the hours the bid was open, and orders the new SHARP the next
  evening, about a day later than option A would have delivered (~0.15M of flight profit).
- **Age:** the extra maintenance of a 3.6-year-old aircraft is unknown. If it is more than 0.024M a week, B is no
  cheaper than A; the capture's statement shows each aircraft's maintenance costs, so a week of B answers it.
- **Waiting (no order tonight):** Pan Am's line idles a day, about 0.85M of a week's profit pushed back a day, and the
  growth rule (order every evening the forecast allows) is broken. Not proposed.

## What would change the recommendation
- A rival bid: we don't chase a price above the new aircraft's (factory price), so the most we bid is 42.9M's terms
  (deposit 2.15M, lease 0.215M a week), the A320neo Light's list price. Above that, A.
- Maintenance costs of age, once a week of a used aircraft is captured: if they eat the saving, used aircraft stop.
- If B works, the used market becomes a rule in manual §3 (opening bids up to the factory price, ages up to a limit
  to be set), decided after a week of data, not now.

## Outcome
**B, 22 Oct (Gitesh):** bid on 5Y-AAD at the opening bid. Gitesh also asked for the used offers to be checked every
day from now on, and noted that an aircraft gets cheaper the longer it stays unsold. Manual §3 (the used market in
each evening's proposal) and §9 (how auctions work) written the same evening. Whether age eats the saving is read from
a week of 5Y-AAD's captured costs.

**Won 22 Oct, about 21:45 Chicago:** Pan Am, at 38.61M (deposit 1.93M, lease 0.193M a week), one step above a
China Eastern bid placed by mistake. Registered N023AW (JFK); plan card 136.

# Point-to-point routes away from our bases — 22 Oct 2026

**Decision:** how the planner should hold, rank and plan city pairs that touch none of an airline's bases (Kingfisher
first: about 214 of Inter Connect's pairs, e.g. Lucknow–Patna, Ahmedabad–Pune).
**Recommendation:** B, a point-to-point kind of route. The pair is marked on the route itself, with one airline-wide
block of flight numbers, and no airport is made a base. Bases keep meaning bases, so nothing that treats a base as a
hub or focus city (hubs first, trunks, the website, the report) picks these pairs up by mistake.

The money columns of the usual table don't apply to the build itself; whether and when Kingfisher flies these pairs is
a strategy question under hubs first (below).

| Option | What it is | Build | Risk | Opportunity cost | Easy to undo? |
|---|---|---|---|---|---|
| A. A "station" role in `airline_bases` | Each outlying airport (Lucknow, Ahmedabad, Pune, Goa, Navi Mumbai, Bhubaneswar, Kochi, Thiruvananthapuram, Jewar and others) becomes a station row with no banks and its own flight-number block | About a day: a new role, then about 15 places taught to skip stations (trunks, hubs first, hub progress, Home map, airline cards, Reference, the website's hubs and trip search, briefing and report) | Every place that reads `airline_bases` as "our hubs and focus cities" is a place to miss; a missed one shows a station as a hub on the website or counts station pairs as November trunks | Kingfisher's blocks run 1000–6999; 9+ stations leave about 300 numbers each in 7000–9999 | Yes, with a removal migration you run by hand |
| **B. A point-to-point kind of route** | **A route row whose two ends are both non-bases, marked point to point; one airline-wide number block for them (Kingfisher 7000–9999)** | **About half a day: a route kind and a number block, flight numbers, the optimiser's airline lookup, competition() listing them, a "Point to point" group on Routes and the add-route form** | **Low: nothing that reads bases sees them; the trip search shows them as direct flights only, which is right** | **None** | **Yes** |
| C. Don't build; list them nowhere | The pairs stay in the review chat's notes | None | They can't be ranked, numbered or planned when the time comes | The 7 Nov strategy session would decide on secondary flying without the openings ranked | — |

## Background
Sources: the database (22 Oct) and a read-only survey of the repository at commit `aff99e2`.

- **Nothing in the database forces a route to start at a base.** `routes.hub_code` only has to be an airport; today every
  one of Kingfisher's 877 listed routes happens to start at one of its six bases (DEL, BOM, HYD, BLR, CCU, MAA). The
  only rule on legs is direction: leg 1 runs from `hub_code` to `dest_code`.
- **What already works for a non-base pair:** block times, turns, maintenance, the position check (each leg starts where
  the last ended), connections at both ends (they need only the airport's minimum connection time), filing a plan card
  (it auto-adds the route), route profit, the fare ladder, growth signals, the daily history.
- **What doesn't:** flight numbers (the next free pair comes from the base's block, so none is offered), the optimiser
  (it asks for a base unless told the airline), competition() (the pair is listed as "isn't one of its bases" and never
  allowed), and Routes (the base chips and the add-route form offer bases only).
- **In the game, bases don't exist.** An aircraft flies any loop of legs, each with its own flight number; a
  point-to-point leg isn't a tag flight, so the no-tag rule (manual §4) is untouched.
- **Inter Connect** (the review chat, 22 Oct) runs about 8,000 flights a week on these 214 pairs from bases we don't
  have: Lucknow, Ahmedabad, Pune, Goa, Navi Mumbai, Bhubaneswar, Kochi, Thiruvananthapuram and Jewar.

## Under today's rules
Hubs first (manual §3) sends every new aircraft to Delhi until it reaches 750 departures a week, with other places only
for contested routes. B lists the pairs and ranks them, marked "hubs first: point to point waits for DEL's 750", so they
are ready when the rule lets them fly. Whether Kingfisher flies point to point at all, and when, stays with the 7 Nov
strategy session in the review chat; this build doesn't change any rule.

## Scenarios and the risk of waiting
- **B goes well:** the pairs are on the list and ranked within a day, and the 7 Nov session decides with them in view.
  **Goes badly:** a screen that groups routes by base shows them oddly; fixed in the same pull request when the
  rehearsal's screenshots show it.
- **A goes well:** stations read naturally as "places we fly from". **Goes badly:** a station shows on the website as a
  hub, or counts in November's trunks, until each place is taught to skip it.
- **Waiting** costs nothing in the game while hubs first holds; the review chat can't load the list until one of A or B
  exists.

## What would change the recommendation
- If the 7 Nov session decides these cities should become real focus cities with banks, they'd be added as bases
  (focus) under today's model, and B's point-to-point kind would serve only the pairs between them that stay unbanked.
- If several airlines (not only Kingfisher) need dozens of outlying stations each with their own numbering, A's
  per-airport blocks start to matter more.

## Outcome
<to be decided>

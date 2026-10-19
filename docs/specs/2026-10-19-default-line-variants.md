# The default line's variants and cabins in the planner (19 Oct 2026)

Decided 18 Oct (manual §3, *Decided, not yet built*); figures from Gitesh's sheet of the game's aircraft pages, 19 Oct
("Default Line Variants", an artifact he filled in).

## The change (migration `20261019180000_default_line_variants.sql`)
- `aircraft_types.range_km` (new): range with a full load.
- 8 new types: E190-E2, A320neo SHARP, A320neo, A320neo Heavy, A321neo, A321LR, A350-900, A350-1000, each with its
  seats, range, deposit (`price`, what an order costs up front) and cruise speed. The game shows no turnaround, so each
  takes its family's turnaround, maintenance and ground figures (A320 family 66 min, 1.70/27.60, 72; E-jet E2 67,
  1.80/22.00, 72; A350 90, 2.00/37.00, 97).
- The 5 types we had take the sheet's figures: deposits to the thousand (E195 1.771M, A320neo LIGHT 2.145M, A321neo
  LIGHT 2.401M, A321XLR 2.862M, A350-900ULR 7.193M), cruise speeds (830, 840, 910) and the A350-900ULR's 440 seats.
- 28 new cabin layouts from the sheet's cabin tab (seats = business + economy; the seat products in the note), and the
  business and economy split filled in on the layouts we had. 321-STD keeps its 216 seats: the sheet's 180 economy
  doesn't add up to them, so its split waits for a check.
- Every one of our airlines may buy every new type (`airline_aircraft_types`), Ryanair no A350. An order's cabin for the
  cash forecast: Leisure on the new narrowbodies, Comfort on the A350s, as for the types we had; Ryanair's own Standard
  on the E190-E2 and A320neo SHARP (`airline_order_cabins`).

## Not in this change
- Plan cards checking each leg against the aircraft's reach (the decision's second half).
- The 359-LP layout's business seat name is cut off in the sheet ("Full Bed Wid…"); its note says so.

## Tests
- `database/tests/default_line_variants_test.sql`.
- While pending, the clean-up test puts the types' figures and who may buy which back to compare everything else with
  before; the rules-input and order-cabin tests take the new types and layouts out of their comparisons.
- The rehearsal's figures-moved artifact shows the cash forecast's types lists growing and its order prices moving by
  the corrected deposits.

# Scheduling handover: 2 Nov 2026, 16:45 UTC (10:45 Chicago)

To start, read the operating manual, `docs/decisions.md` and the playbook, then check the planner's live state.
The manual changed a lot in this chat. Mainly:
- §3: long haul waits for cash.
- §3: order across both delivery lines.
- §4: the trunk month runs 29 Oct–30 Nov at A321LR reach, and fillers are allowed.
- §4: Mumbai gets six aircraft.
- §4: flight numbers ascend through the aircraft's day.

## Do first, in this order
1. **File the 2 Nov orders as they arrive.** They run 2–5 Nov, with Mumbai's VT-ABI/ABJ/ABK still among them. Every
   one has a plan card, so Gitesh sets each up from its card, then you check it against the card after the capture:

   | Arrives (UTC) | Aircraft | Card | Base | Day |
   |---|---|---|---|---|
   | 2 Nov 10:01 | VT-ABI | 162 | BOM | (29 Oct order) |
   | 2 Nov 22:26 | N030AW | 176 | JFK | EDI |
   | 3 Nov 04:26 | N028AW | 177 | JFK | LAX + DFW |
   | 3 Nov 07:01 | VT-ABJ | 163 | BOM | (29 Oct order) |
   | 3 Nov 07:36 | VT-ABO | 180 | DEL | CCU + CNX + IXC |
   | 3 Nov 07:37 | EI-ACT | 183 | BCN | LPA + HEL |
   | 3 Nov 07:37 | G-AAGH | 186 | LGW | EDI + STR + HER |
   | 3 Nov 07:39 | 9M-ABF | 190 | KUL | CCU + CEB |
   | 3 Nov 13:36 | EI-ACR | 181 | CDG | MXP + BCN + TFS |
   | 3 Nov 13:37 | G-AAGF | 184 | EDI | MXP + BCN + CPH |
   | 3 Nov 13:38 | B-0451 | 187 | PVG | XIY + SZX + KMG |
   | 3 Nov 13:39 | 9M-ABE | 189 | KUL | DEL + NNG |
   | 4 Nov 01:26 | N029AW | 178 | ORD | SEA + LAX |
   | 4 Nov 04:01 | VT-ABK | 159 | BOM | (29 Oct order) |
   | 4 Nov 10:36 | EI-ACS | 182 | BCN | MUC + AMS + ATH |
   | 4 Nov 10:37 | G-AAGG | 185 | MAN | CDG + MXP + ATH |
   | 4 Nov 10:38 | B-0452 | 188 | PKX | SZX + CGO + CAN |
   | 5 Nov 01:01 | VT-ABN | 179 | HYD | BLR + MAA + SGN |

   The E195s (delivered at SJK) and the SHARPs (at TLS) ferry to base.
2. **China Eastern's E195 is on hold.** Its proposed day (Kunming: Kolkata + Jinan + Nanning) was dropped.
   - The reason: China Eastern's PVG–CCU runs at a 24% load, 0.9k an aircraft hour, marked "fix". Secondary
     China–India doesn't make sense yet (20 Oct brief).
   - Replan the day without Kolkata: E195 fillers to cities of 4★ or less, or a different base.
   - China Eastern has about 3.4M at its lowest point after the two SHARPs, enough for one E195 (1.8M).
3. **Next round of orders** once the cash forecast allows, trunks first (manual §4).
   - Open: to-do 185, Virgin MAN–AMS. KLM entered at 56 a week; weigh a second daily.
   - Open: to-do 186, the filler list.
   - Pan Am's next was noted on card 178: Dallas–Chicago, Dallas–San Francisco with Houston (12.0 h).

## Where things stand
- **Retimes:** all 113 flights are done (to-dos 182 and 183 closed). Pass 2 is to-do 184 on 12 Nov, Mumbai included.
  - Pass 2 must keep a safety margin on maintenance.
  - The reason: in pass 1, G-AADL relied on a ground stop of exactly 192 min (72 + 120), and the game doesn't count a
    stop exactly at that edge. Use a margin of 10 min or more.
  - The pass must also reject any move that creates or shortens a turn below the need. It compares the gaps themselves,
    not counts of bad turns.
- **Orders logged 2 Nov:** 15 aircraft (cards 176–190). The lowest points after them:

  | Pan Am | Kingfisher | Ryanair | Virgin | China Eastern | Malaysia |
  |---|---|---|---|---|---|
  | 1.3M | 0.9M | 0.8M | 1.6M | 3.4M | 3.8M |

- **To-do 187 is closed:** the three idle cards (9M-ABB, G-AAFL, VT-ABH) were filed and checked.
- **The A350s:** VT-AAA and VT-AAB were returned and renamed "(A350, returned …)". DEL–JFK route stays, per Gitesh.
- **Kolkata's numbers** (7 days to 2 Nov):

  | Route | Economy load | Sold out | Profit per aircraft hour |
  |---|---|---|---|
  | Kingfisher DEL–CCU | 98% | 88% | 6.4k |
  | Malaysia KUL–CCU | 98% | 83% | 6.3k |
  | China Eastern PVG–CCU | 24% | 0% | 0.9k |

  Kolkata is strong for Kingfisher and Malaysia and weak only for China Eastern.

## Lessons from this chat
- **Briefs:** full briefs go in chat. Gitesh won't open GitHub for them.
- **Order flow:** check the game against the planner, then Gitesh reschedules arrived aircraft, then we order. Plan with
  the latest times.
- **Proposals:**
  - Show each aircraft's block hours (12 h or more) and the cash left after the order.
  - Use both delivery lines (A320 family and E-jet).
  - No E195 to cities of 5★.
- **Cabins:**
  - The rule weighs block time with a 65% threshold, not the longest route. 9M-ABE flies KUL–DEL (3,850 km) and still
    gets 320S-LEI.
  - Ryanair is always Standard.
- **Cash test:** `cash_forecast(airline, '[{"aircraft_type_id":12,"count":2}]', now())`, then read
  `orders_tested.lowest`. Orders take `aircraft_type_id` or the exact `type` name.
- **Before logging:** check flight numbers against `flight_legs` and `plan_card_legs`. Run `mkcards.py` once per spec,
  because it appends legs to its input.

## Tools
The scratch scripts were in the old chat's workspace, which is gone. The library CLI (`lib/rules/dist/cli.js`
optimise, check-card, optimise-line) does the same jobs. Rebuild with `npx tsc -p lib/rules/tsconfig.build.json`.
`rules_input()` is about 2.6 MB: wrap it as `select jsonb_build_object('doc', public.rules_input()) x;`.

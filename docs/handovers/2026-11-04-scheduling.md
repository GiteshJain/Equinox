# Scheduling handover: 5 Nov 2026, 04:15 UTC (4 Nov 22:15 Chicago)

Chat "Scheduling · 2 Nov", 2–4 Nov. To start, read the operating manual, `docs/decisions.md` and the playbook, then
check the planner's live state. The manual changed in this chat:
- §3: the E195 at 5-star cities only as a fallback (its line would otherwise stand idle).
- §4: **the trunk month fortifies short-haul trunks first** (domestic and in-region, contested pairs against a top-3
  competitor ahead), long-haul trunks after (since 4 Nov, Gitesh: "long haul is not yet that competitive").
- §6: rewritten. One outside partner per foreign airport adding 3+ places beyond us and our signed partners; never a
  top-3 competitor, a hub carrier (judged from the scan: an airline whose hub takes our transfers) or a base-country
  airline; incoming requests accepted unless they work against us; our hubs come first; requests unanswered for two
  weeks re-checked at the Saturday review.
- §2: **shared pairs decided** (4 Nov, not yet built): a pair between two bases of two different airlines of ours,
  Ryanair out, may be flown by both at the owner's price; the joiner adds only while the pair sells out and when the
  owner can't fund it that evening. **Until the build merges, one airline per city pair stands.** Brief
  `docs/briefs/2026-11-04-shared-pairs.md`, spec `docs/specs/2026-11-05-shared-pairs.md` (built after the
  default-price change; one route page per pair with combined figures and story). Gitesh: the game shares a market
  by flight; Ryanair won't fly Virgin's routes.

## Do first
1. **File the 3 and 4 Nov orders as they land** (5 ordered 3 Nov, 6 on 4 Nov, plus B-0455 from 2 Nov). Every one has a plan card; Gitesh sets each up from its card, you check it
   after the capture.

   | Arrives (UTC) | Aircraft | Card | Base | Day | Cabin |
   |---|---|---|---|---|---|
   | 5 Nov 07:36 | EI-ACX | 199 | CDG | MXP + SKG + CFU | 320S-STD |
   | 5 Nov 07:37 | G-AAGJ | 200 | LGW | BCN + KEF + MUC | 320S-LEI |
   | 5 Nov 07:38 | B-0455 | 196 | PKX | CTU + XIY + SZX | (2 Nov order) |
   | 5 Nov 07:39 | 9M-ABI | 202 | KUL | KMG + BOM | 320S-LEI |
   | 5 Nov 17:34 | N033AW | 208 | JFK | STL + MSY + SAV (E195) | E195-LEI |
   | 5 Nov 22:01 | VT-ABP | 198 | CCU | HYD + BLR + MAA (first Kolkata-based) | 320S-LEI |
   | 5 Nov 23:18 | N032AW | 203 | JFK | ORD shuttle ×3 | 320S-LEI |
   | 6 Nov 04:36 | EI-ACZ | 205 | CDG | BCN + TLL + SOF | 320S-STD |
   | 6 Nov 04:38 | B-0461 | 201 | PVG | SZX + KWE + XIY | 320S-LEI |
   | 6 Nov 04:39 | 9M-ABJ | 207 | KUL | SZX + HYD | 320S-LEI |
   | 6 Nov 19:01 | VT-ABS | 204 | DEL | BOM shuttle ×3 | 320S-LEI |
   | 7 Nov 01:38 | B-0468 | 206 | KMG | XIY ×2 + PKX | 320S-LEI |

2. **Each evening's orders, the trunk push** (Gitesh: "full push"). On 3 Nov, 64 of 65 flown trunks were at 95%+
   economy (route_profit's loads, not growth_signals' sold-out list, which undercounts). Short-haul first:
   - Pan Am: SFO–SEA (we fly 14/wk against AA 98 + Alaska 84), LAX–SFO, LAX–SEA, the two unflown (DFW–SEA, ORD–SFO).
     Checked option: SHARP at SFO, SFO–SEA + SFO–ORD, 11.3 h.
   - Kingfisher: Mumbai's spokes against AirAsia India (54/40/40 a week, both ways, vs our 14 on each): best is BOM-based BLR + HYD ×3
     (4 round trips, 9.8 h, 100k a day). Delhi–Mumbai shuttle ordered (VT-ABS); watch flights 1087/1093 fill.
   - Ryanair: MXP–AMS, MXP–BCN, MXP–MUC, AMS–MUC (all full).
   - Virgin: LGW–CDG, LGW–AMS, MAN–AMS, MAN–MUC (full). Cash back about Friday.
   - China Eastern: PVG–PKX; Malaysia: KUL–DEL (1.29M a week), KUL–CCU, KUL–XIY.
   - Long haul (transatlantic, India–Europe) after these. Delhi–Paris (96%) and Delhi–Gatwick (100%) show it works.
3. **Short-haul SHARPs top out about 10–13 h a day** (maintenance per take-off and night bans): Europe and India fit
   three round trips; add a long filler (filler list, to-do 195, and growth_signals' sold-out routes) to reach 12 h.
   Gitesh wants 11+ h: "way too many under 10 hour flights".

## Where things stand
- **Cash cushion:** Kingfisher (VT-ABS) and Ryanair (EI-ACZ) were ordered under the 0.5M cushion on 4 Nov as Gitesh's
  one-off call (lowest 0.30M and 0.47M). The rule is unchanged.
- **Interline (all in `interline_agreements`):** signed earlier: ANA (Kingfisher, China Eastern, Malaysia), Garuda and
  Qantas/QantasLink (Malaysia), airBaltic (Ryanair), Etihad Cargo (Kingfisher); signed 3 Nov: TAP and Norra for Ryanair
  and Virgin. Requests out:
  Pan Am Aer Lingus, Air Canada (player looks inactive); Kingfisher VietJet; Ryanair Braathens; Virgin Braathens and
  the Aeroflot group (Rossiya, Aeroflot, Pobeda); China Eastern and Malaysia Cebu Pacific and VietJet. Aeromexico
  Connect rejected (Mexico: no partner). Deferred to 5 Dec: SWISS, Aer Lingus for Virgin, Garuda.
- **Players leaving next month** (Gitesh, 4 Nov; no to-do, it doesn't change strategy): CEODex (SWISS, Global,
  JetBlue, Cebu Pacific, LATAM, Riyadh Air), lunareunlar (China Airlines, Juneyao, VietJet), nikolai98 (Air Europa,
  Republic, Sichuan), builderwise (inactive). Their routes at our bases show up in the competition lists when they go.
- **Building:** Fare results board built (`fare_results()`; Performance → each airline, under the fare ladder). The default-price build is underway
  (`docs/specs/2026-11-04-fare-default-from-market.md`); until it lands, leave Ryanair's 7 "captured ~72–76% against
  85–90%" set-backs alone: the inferred baseline is probably wrong there. The Interline screen rebuild for §6 is still
  on the manual's *Decided, not yet built* list. Shared pairs follow the default-price build (see §2 above).
- **Fare ladder:** the 26 Oct step-ups (+5–7%) kept loads at 99–100% and raised profit a flight 7–11% (Ryanair flat).
  Gitesh may want a faster ladder: a Saturday review question.
- **Open to-dos for this chat:** 184 and 193 (retime pass 2, 12 Nov), 196 (one more short rotation for aircraft under
  10 h, 12 Nov), 195 (filler list).

## Lessons from this chat
- **Check before recommending.** Every option goes through the optimiser and check-card first (Gitesh, after a G-AAGI
  card failed maintenance).
- **Detailed analysis per partner and per option** ("detailed bitch"); no to-do board for work done together in chat.
- **Count carefully** (I called 6 orders 11 on 4 Nov).
- **The E195 at 5-star cities is a fallback only** (§3): when Gitesh picks an E195 to stay inside the cushion, it goes
  to full routes of 4 stars or less (N033AW: JFK–St. Louis, New Orleans, Savannah), not to a trunk.
- Loads: use `route_profit()` economy loads for "full"; growth_signals' sold-out list misses many full routes.

## Tools
- `rules_input()` (2.7 MB): `select rules_input()::text as j;` overflows to a tool-results file; parse it with
  python (`json.loads(result)` → the text between the `<untrusted-data-…>` tags → `[0]["j"]`) into `rules.json`.
- `node lib/rules/dist/cli.js optimise rules.json BASE D1,D2 --type "A320neo SHARP" --airline N --start 00:00-23:55
  --step 5`; repeat a destination for extra round trips (`BOM,BOM,BOM`).
- check-card needs the aircraft in the input: append an on_order aircraft with the registration, write the card
  (`aircraft`, `type`, `airline`, `config_id`, `legs`), run once, then take each leg's `service.wanted` and the cabin's
  `config_id` from the result and run again.
- Next flight numbers: the highest used in the base's range in `flight_legs` ∪ `plan_card_legs`, plus 1 (gaps may be
  numbers the game still holds: G-AAGH's 1155/1156 had to move to 1161/1162).
- `cash_forecast(airline, '[{"type":"A320neo SHARP"}]')->'orders_tested'->'lowest'` for the cash after an order.

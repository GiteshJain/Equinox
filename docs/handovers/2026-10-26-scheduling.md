# Scheduling chat handover — 26 Oct 2026, 17:10 UTC (12:10 Chicago)

Start as usual: read the operating manual, `docs/decisions.md` and the playbook, then check the planner's live state.
Figures below are from the captures of 26 Oct 16:15 UTC (all six "all good").

## Update, 26 Oct evening (Building chat)
- **The cabin suggestion by distance is built** (#101): a new card's suggestion now follows manual §5, so no card needs
  its cabin set by hand against a differing suggestion.
- **Closed since this note:** to-dos 171, 170, 146, 148 and 161.
- **Virgin and Malaysia have since ordered:** G-AAFL (LGW) and 9M-ABB (KUL), both E195-E2s due 27 Oct about 08:20 UTC
  (brief `docs/briefs/2026-10-26-e195-orders.md`).
- **Kingfisher's deposit aircraft go to Mumbai,** not Delhi (manual §3, hubs first's exception; commit b06721c).

## Working with Gitesh (this chat's lessons)
- **Every proposal shows each aircraft's flying hours a day** (block hours). He pushes back on aircraft under 12 h.
- **All airlines' orders are proposed first, then logged together** (cards, briefs) once he agrees.
- **Ask before pushing a variant past its full-load range** (manual §3, since 26 Oct), each time.
- Cabins by distance band, 65% of block time decides, else Leisure (manual §5, since 26 Oct; the planner's suggestion
  still uses the old market rule until to-do 170 is built, so a "differs" flag on a new card is expected).

## Since the last handover (23–26 Oct)
- Ordered and filed: N024AW (ORD), B-0382 (PVG), 9M-AAZ (KUL), G-AAFJ (LGW); on 25 Oct Gitesh ordered eight on his own
  (N025AW SFO, VT-ABF BOM, EI-ACG MUC, EI-ACH AMS, G-AAFK LGW, B-0398 SZX, B-0399 PVG, 9M-ABA KUL), routes agreed and
  filed 26 Oct (cards 145–152, brief `docs/briefs/2026-10-26-orders.md`).
- **9M-ABA (KUL), A321LR, KUL–Dubai with Pekanbaru:** Malaysia's first long-haul, an exception to the feeder-first
  trigger (manual §2, brief `2026-10-26-malaysia-a321lr-dubai.md`). Watch its loads after a week; if weak, Narita or
  back to Chengdu Tianfu and Guiyang.
- **VT-ABH (BOM)**, A320neo LIGHT, Doha and Jeddah, card 153, **arrives 27 Oct 13:07 UTC: file within a day.**
- Munich (EI-ACG) and Mumbai (VT-ABF, VT-ABH) opened as bases this week.

## Next orders
- **Virgin:** Gitesh chose to wait for an E195 rather than order an E190 (1.84M could be spent, the E195 needs 1.87M).
  At the next capture, if the E195 is safe, rerun LGW with Bologna, Algiers, Faro (the E190 gave 13.2 h, 143 connections)
  and show the hours.
- **Malaysia** could order an E195 on the 16:17 UTC capture (2.37M); not yet proposed.
- Everyone else from the next capture. Until 31 Oct only new routes (Pan Am and China Eastern exempt); from 1 Nov the
  trunk month (manual §4).
- **Kingfisher's A350s** (to-do 169): VT-AAA returns 28 Oct 05:11 UTC, VT-AAB 29 Oct 11:11 UTC; retire each, remove
  its legs, log the deposit; then Delhi narrowbodies.
- Used market: only an A321LR listed on 23 Oct; Gitesh expects new offers next month. Still ask for the screenshot.

## Open to-dos touching Scheduling
- 171 (31 Oct review): G-AAFK (LGW) Tel Aviv for St Petersburg, 12.7 to 16.1 h (past the SHARP's range, ask);
  B-0399 (PVG) Da Nang for Zhuhai, 11.5 to 13.6 h; VT-ABF (BOM) stays at 11.0 h.
- 169 Kingfisher A350 returns; 170 Building chat (cabin by distance); 146, 148, 161 Saturday chat.

## Tools that worked
- Optimiser and card check without the 2.6 MB `rules_input`: one SQL per base returns compact strings (legs, rotations,
  routes, airports, aircraft, bases for the base and its candidate destinations); the scratchpad script `gen.py` turns
  them into a rules file and `run.sh` runs `optimise` on many mixes at once. Rebuild them from this description if the
  scratchpad is gone. Add any aircraft filed since (from its card) before planning at the same base.
- `cash_forecast(id, '[{"aircraft_type_id":N,"count":1}]')->'orders_tested'->'lowest'` gives the lowest point with an
  order; `next_order.up_to` is what can be spent now.
- Flight numbers: check the airline's pool in both `flight_legs` and `plan_card_legs` before writing a card.

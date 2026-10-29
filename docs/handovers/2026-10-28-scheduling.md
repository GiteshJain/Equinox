# Scheduling handover — 28 Oct 2026, 02:20 UTC (21:20 Chicago)

Start as usual: read the operating manual (much changed since 26 Oct: §3's default line, §4's planning target and
lines, §7's audit limit), `docs/decisions.md` and the playbook, then check the planner's live state.

## Do first, in this order
1. **Three aircraft idle since 27 Oct, not yet scheduled in the game:** 9M-ABB (KUL, E195-E2, card 154: Surabaya,
   Palembang, Makassar), G-AAFL (LGW, E195-E2, card 155: Algiers, Bologna, Faro), VT-ABH (BOM, A320neo LIGHT, card 153:
   Doha, Jeddah). Their cards were timed under the old 8-hour scoring. Re-time each with the optimiser now that it
   scores connections within 4 hours (#117), keep the routes, update the cards, check them, and give Gitesh the times.
   Then he sets them up and files them.
2. **The retime pass at the five big hubs, Gatwick first** (brief `docs/briefs/2026-10-27-connection-waits.md`): moves
   of up to 60 minutes that gain the most connections within 4 hours, net of any they break, each checked at both ends;
   Gitesh makes them in the game and on Routes. Then PVG, KUL, JFK, DEL.
3. **Orders resume** once 1 and 2 are done (Gitesh paused all new orders on 27 Oct until everything was decided and
   built; not a rule). Kingfisher first: the Mumbai 4+4 (four A320neo SHARPs, four E195-E2s, §3's hubs-first exception;
   rank Mumbai's openings yourself, `competition()` marks them "hubs first"). Kingfisher's cash was 10.3M on 28 Oct with
   VT-AAA's deposit in; VT-AAB (DEL) returns 29 Oct 11:11 UTC (+7.19M). Then each airline the forecast allows.

## Decided 26–28 Oct (all in the manual and briefs)
- **New-routes-only retired** 27 Oct (4 days early): growth rules apply again.
- **Default line (§3):** reach is each variant's full-cabin distance in our seat type for the distance, from the
  game's evaluation tool (675 routes, `aircraft_eval_runs` / `aircraft_eval_results`, 9 hand checks all matching):
  E195 5,700, SHARP 4,100, LIGHT 5,200, Heavy 6,750, A321neo LIGHT 5,250, LR 7,700, XLR 8,600, A350-900 14,200,
  A350-1000 beyond (full to 15,200). E190-E2, A320neo, A321neo and ULR off the line and off the may-buy lists.
  Brief `2026-10-27-real-aircraft-reach.md`. "Smaller wins within a band" stays (the booking split favours departures).
- **Planning target (§4, #117):** plans and retimes aim for connections within 4 hours
  (`plan_connection_target_h`); a connection still counts up to 8 hours everywhere else. Audit retimes up to 30 min.
- **Long haul in 7-day lines (§4, #118–121):** routes beyond about 7,750 km fly in 7-aircraft rotating lines of one
  type, each a day apart; XLR lines first; A350 lines wait for the narrowbody-against-A350 question (narrowbodies earn
  about 3 times as much per unit of lease; a 7-A350 pool is about 52M). Maintenance stops at most 40 hours apart on
  every card. The line optimiser, lines in the planner, the line card check and pool progress on Orders are built.
- **Kingfisher's deposits** (14.39M) start Mumbai's network: 8 aircraft, §3's one-off hubs-first exception.
- **To-dos closed:** 170, 171 (G-AAFK, B-0399, VT-ABF stay as they are), 176, 178, 179, 180. **Open here:** 169
  (retire VT-AAA and VT-AAB after their returns, log the deposits; VT-AAA's is in).

## Working with Gitesh (this chat's lessons)
- By the book: rule and tool changes go through the Building chat with a spec, and the rule changes at the merge.
- One decision at a time, each with a full brief; he often asks for a deeper review before deciding: give one.
- Show airport codes for test routes. Every proposal shows each aircraft's block hours a day; he pushes back under 12 h.
- All of an airline's options are proposed first; orders logged together once he agrees.

## Tools that worked
- `rules_input()` is about 2.6 MB: select it wrapped as `select jsonb_build_object('doc', public.rules_input()) x;`
  (the result is saved to a file), then pull `doc` out with Python. A slice around one base is smaller.
- `node lib/rules/dist/cli.js optimise <rules> <base> <dests> --type "<variant>" --start 00:00-23:55 --step 5
  --airline <id>`; `check-card` with a card JSON (`type` and `airline` when the aircraft isn't in the input).
- The evaluation's results: `aircraft_eval_results` joined to `aircraft_eval_runs` on `run_id`.

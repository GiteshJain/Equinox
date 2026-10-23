# Malaysia's aircraft: Beijing and Bangkok Don Mueang — 22 Oct 2026

**Decision:** Malaysia's order tonight, and the routes it opens.
**Recommendation:** A. A new A320neo Heavy at KUL flying KUL–Beijing (PEK) and KUL–Bangkok Don Mueang (DMK) daily:
the top and third openings, 87 connections, 15.1 block hours a day. No used aircraft on offer reaches Beijing with a
full cabin.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A New A320neo Heavy: PEK + DMK** | 2 new 5-star cities (openings 1 and 3), 28 departures a week, 87 connections, 15.1 h a day | about 0.48M (28 flights at Malaysia's 0.025M a flight, less the 0.224M lease); Beijing's long legs likely earn more | **0.58M** (cash_forecast with the order) | E195 line stays idle (cash covers one aircraft) | Beijing has a rival (28 a week) | Lease |
| B New A320neo SHARP: Bali (DPS) + Guiyang (KWE) | 2 new 5-star cities (openings 5 and 7), 28 a week, 87 connections, 12.8 h a day | about 0.50M (lease 0.206M) | about 0.76M | Beijing, the top opening, waits | No rivals on either | Lease |
| C Used 5Y-AAC (A320neo Light, 7.2 y), opening bid: DPS + KWE | as B | about 0.56M (lease 0.150M), less the cost of age | about 1.3M (1.50M deposit, cabin) | as B, and the A320 line stays free | Outbid; age; 7.2 years | Lease |

## Background
- **Cash** (capture 23 Oct 00:23 UTC, "all good"): captured 3.66M, lowest 2.98M at Friday's week-end closing (05:30
  UTC). With the A320neo Heavy (2.40M with cabin) the lowest is 0.58M, safe. `cash_forecast(6, p_orders)`.
- **Openings** (`competition(6)`, scan of 23 Oct 00:23 UTC): every one is 5-star; Beijing is first (Malaysia's only
  top-30 opening with a rival, 28 a week), then Melbourne (needs the A321XLR, out of reach of tonight's cash),
  Bangkok Don Mueang, Hat Yai, Bali, Haikou, Guiyang. KUL is at 343 of 750 departures, so all go to KUL (hubs first).
  Until 31 Oct Malaysia opens new routes only (manual §4); both options do.
- **Variant:** Beijing is 4,414 km, beyond the A320neo's 4,045 km: the A320neo Heavy (4,708 km) is the cheapest that
  reaches it with a full cabin (default line, manual §3).
- **Schedule** (`optimise` and `check-card`, rules_input of 23 Oct 01:20 UTC): MH1123/1124 KUL–DMK 12:35, back 14:45;
  MH1125/1126 KUL–PEK 18:55, back 01:51 (KUL local). Check passes: maintenance 170%, no turn, night ban, gap or number
  problems, service codes S2 (DMK 1,248 km) and S3 (PEK). Cabin: Beijing is 75% of the block time, so its market's
  Leisure Plus (`320H-LP`, 147 seats).
- **Used market** (game, 22 Oct): HZ-ABA (A320neo, 4,045 km) can't fly Beijing full; the A321LR 5Y-AAE could, but a
  larger type where the smaller one fits breaks the default line. 5Y-AAC fits option C only.

## Scenarios and the risk of waiting
- A takes the biggest market first and uses the aircraft hardest; Beijing's rival may pull loads below a sell-out
  at first.
- B or C leave Beijing to a later evening; nobody flies Bali or Guiyang, so they don't run away.
- Waiting: Malaysia's lines idle a day. Not proposed.

## What would change the recommendation
- A used aircraft that reaches Beijing full, cheaper than new.
- Cash short of the Heavy at order time: then B (cash decides, manual §3).

## Outcome
<Gitesh's decision and the date>

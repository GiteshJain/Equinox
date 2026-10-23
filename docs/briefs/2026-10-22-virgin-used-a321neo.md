# Virgin's aircraft: a used A321neo Light for Paris Orly, Berlin and Antalya — 22 Oct 2026

**Decision:** Virgin's order tonight.
**Recommendation:** A. Bid on the used A321neo Light **VH-AGP** (9.0 years) at the opening 30.01M and fly it from
Gatwick to Paris Orly, Berlin and Antalya daily: three new 5-star routes, 132 connections, 12.5 block hours a day,
for a lower lease than any new aircraft Virgin can buy.

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A Used VH-AGP (A321neo Light, 9.0 y), opening bid: ORY, BER, AYT** | openings 9, 5 and 6, all 5-star, 42 departures a week, 132 connections, 12.5 h a day | about 0.57M (42 flights at Virgin's 0.017M a flight, less the 0.150M lease); age adds maintenance | **about 0.61M** (forecast 2.31M less the 1.50M deposit and 0.19M cabin) | none tonight: no new aircraft for 5-star cities is safe | Outbid; 9 years of age | Lease |
| B New E190-E2 | only 1- and 2-star openings (cash decides, manual §3) | smaller | about 0.6M | the 5-star openings wait | Low | Lease |
| C Nothing tonight; an A320neo SHARP once cash covers it | none tonight | — | — | a day of growth | Low | — |

## Background
- **Cash** (capture 23 Oct 00:23 UTC, "all good"): lowest 2.31M at 01:39 UTC on 23 Oct. A new E195 leaves 0.44M and a
  new A321neo Light −0.29M, both unsafe; the E190-E2 is the only safe new type. `cash_forecast(4, p_orders)`.
- **Openings** (`competition(4)`, scan of 23 Oct 00:23 UTC), all 5-star: Manchester–Heathrow and Edinburgh–Heathrow
  come first, but new Virgin Heathrow routes are a late-game step (manual §4, London), so they're set aside. Edinburgh–
  Amsterdam and Edinburgh–Copenhagen (contested routes) make 12 to 16 connections at Edinburgh. Next at Gatwick: Berlin
  (rival 14 a week), Antalya (rival 14), Paris Orly, Istanbul Sabiha Gökçen. Gatwick is at 427 of 750 departures.
  Until 31 Oct Virgin opens new routes only (manual §4); each route here is new and flown once a day.
- **Size:** 5-star cities take a mid or large aircraft (manual §3). No new mid or large type is safe tonight, so cash
  decides (manual §3): the biggest type cash allows, and the used A321neo Light is it, at a lower lease (0.150M) than a
  new E195-E2 (0.177M).
- **Schedule** (`optimise` and `check-card`, rules_input of 23 Oct 01:20 UTC), London local: VS1133/1134 LGW–AYT
  18:05, back 01:14; VS1135/1136 LGW–ORY 04:23, back 07:27; VS1137/1138 LGW–BER 08:31, back 12:20. Check passes:
  maintenance 128%, no turn, night ban, gap or number problems; service S1 (Orly 325 km), S2 (Berlin 950 km), S3
  (Antalya 2,908 km). Cabin: no route over 65% of block time, so Leisure (`321-LEI`). Istanbul instead of Antalya: 129
  connections, 160%, 11.5 hours.
- **Used market** (game, 22 Oct, 21:55 Chicago): VH-AGP at 30.01M (deposit 1.50M, lease 0.150M), VT-ABG (7.2 years)
  at 33.61M leaves Virgin 0.43M, under the cushion. The E195-E2 5Y-AAR is a small type, not for 5-star cities.

## Scenarios and the risk of waiting
- A goes well: three new 5-star routes tonight, 240 seats, the cheapest lease in Virgin's fleet.
- Outbid: Virgin can go one step higher (32.17M: deposit 1.61M, lowest about 0.51M); beyond that, nothing tonight.
- Waiting a day for a new A320neo SHARP costs a day of three routes.

## What would change the recommendation
- A rival bid past one step (cash).
- Maintenance of a 9-year-old aircraft eating the lease saving, seen in a week of captures (as with N023AW).

## Outcome
<Gitesh's decision and the date>

# Start the trunk month today? — 29 Oct 2026

*Scheduling chat. Gitesh asked whether to start November's trunk rule now for all airlines instead of opening
Mumbai's eight on its openings. Figures: `competition()` as on 1 Nov, the optimiser on Mumbai's trunks,
`cash_forecast()` 29 Oct, the 20 Oct November brief.*

**Decision:** whether the trunk month (§4) starts on 29 Oct instead of 1 Nov.
**Recommendation: C.** Start it today for every airline; Kingfisher's eight Mumbai aircraft stay as proposed (they
already open Mumbai's four domestic trunks; its other trunks are India–Europe, Kingfisher's weakest flying).

| Option | Growth | Profit a week | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Keep 1 Nov | as planned | unchanged | Kingfisher 1.28M with the eight | trunks wait 3 days | low | – |
| B. Start today, Mumbai's eight included | Mumbai's 4 domestic trunks plus about 6 single-route Europe aircraft (Heavies to Munich and Malpensa, A321LRs to Gatwick, Amsterdam, Paris, Edinburgh) | likely lower: 3–5 connections within 4 h per Europe aircraft (10–26 in the proposal); India–Europe is Kingfisher's weakest flying | about 20M for the eight against 17.2M safe today: over 2–3 days | Mumbai's contested pairs (Hong Kong, Riyadh, Bangkok, Muscat) wait | medium: types change from the decided 4 SHARPs and 4 E195-E2s; new 7,000 km routes | yes, but aircraft committed |
| **C. Start today; the Mumbai eight as proposed** | **trunks 3 days early at the other five airlines and Delhi; Mumbai opens its domestic trunks and contested pairs** | **likely highest** | **Kingfisher 1.28M; others by their forecasts** | **Mumbai's Europe trunks wait** | **low** | **yes (one setting)** |

## Background
- Starting today moves `settings.trunk_month_from` from 1 Nov to 29 Oct (end 30 Nov): three more evenings of trunk
  orders; Los Angeles and Dallas open three days sooner.
- Trunks within the A321LR's reach: Pan Am 26 (nine US pairs on SHARPs first), Kingfisher 34 (the southern triangle,
  Mumbai and Kolkata domestic, then 24 India–Europe pairs at 5,900–7,700 km), China Eastern 28 (mostly secondary
  China–India, judged not to make sense yet on 20 Oct), Virgin 8 short pairs, Malaysia 1 (KUL–Daxing), Ryanair 1
  (Malpensa–Munich); plus every flown trunk selling out at 95% or more.
- Mumbai's trunks on the optimiser: Hyderabad, Bengaluru and Chennai give a SHARP 8.5 h; adding Kolkata breaks
  maintenance. Europe flies one route an aircraft, 16–18.5 h a day, 3–5 connections within 4 h.
- India–Europe: Delhi–Paris at 31% and Delhi–Amsterdam marked fix on 20 Oct.

## What would change the recommendation
India–Europe selling well; Kingfisher's cash falling short of the eight.

## Outcome
**29 Oct 2026 (Gitesh): C, with Mumbai getting six aircraft and Delhi the remaining cash.** The trunk month runs 29 Oct
to 30 Nov (`trunk_month_from` 2026-10-29). Mumbai's six are the top six of the eight proposed (A320neo SHARPs: Riyadh,
Hyderabad, Bengaluru; Bangkok, Don Mueang; Chennai, Ho Chi Minh City. A320neo LIGHT: Hong Kong, Goa. E195-E2s: Muscat,
Kochi, Dhaka; Ahmedabad, Kolkata, Dammam); the rest of Kingfisher's cash goes to Delhi's trunks. Manual §2 (bases),
§3 (the openings; hubs first's exception) and §4 (the trunk month) changed the same day; old wording in
`rule-history.md`.

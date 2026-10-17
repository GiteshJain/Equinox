# EI-ABQ and EI-ABR, Barcelona's second and third A321neos: their routes — 17 Oct 2026

**Decision:** what the second and third aircraft of Ryanair's new Barcelona base fly (14 Oct Ryanair brief, option C:
three open Barcelona). EI-ABQ landed 16 Oct 22:33 UTC; EI-ABR lands 17 Oct 19:33 UTC. EI-ABP took Dublin, Munich and
Vienna on 16 Oct, and Zurich and Rome were first in line. Barcelona is a new base, so a full brief (manual §1); the two
Amsterdam aircraft (EI-ABS, EI-ABT) are frequency on sold-out routes and are recorded on their plan cards.
**Recommendation and outcome:** A for both. EI-ABQ: Zurich, Rome and Stockholm, about 112k a day, 12.1 hours. EI-ABR:
Berlin, Prague and Budapest, about 125k a day, 12.9 hours. Six new cities; with EI-ABP the base flies nine.

**EI-ABQ**

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A. Zurich + Rome + Stockholm** | **3 new (2 five-star) · 22 links · 12.1 h · maintenance 142%** | **~0.55M (~112k a day less a 34k lease)** | **no change (bought)** | **Oslo waits** | **few connections at a new base** | **yes** |
| B. Zurich + Rome + Oslo | 3 new · 22 links · 11.8 h · 152% | ~0.53M (~110k a day) | no change | — | as A | yes |
| C. Rome + Berlin + Warsaw | 3 new · 21 links · 12.6 h · 125% | ~0.62M (~122k a day) | no change | Zurich moves to EI-ABR (Zurich + Prague + Budapest, ~112k) | as A | yes |

**EI-ABR** (with EI-ABQ on A)

| Option | Growth | Profit a week (after lease) | Cash at the lowest point | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| **A. Berlin + Prague + Budapest** | **3 new 4-star, no rival · 20 links · 12.9 h · maintenance 113%** | **~0.64M (~125k a day)** | **no change** | **Hamburg waits** | **as EI-ABQ** | **yes** |
| B. Hamburg + Prague + Budapest | 3 new · 20 links · 12.9 h · 113% | ~0.64M (~125k a day) | no change | Berlin waits | as A | yes |
| C. Naples + Venice + Porto | 3 new · 21 links · 9.3 h · 236% | ~0.42M (~94k a day) | no change | 3½ idle hours a day | low | yes |

The two aircraft together earn about the same either way (A + A ~237k a day; C + Zurich, Prague, Budapest ~234k). Four
cities in a day don't fit from Barcelona: night closures and maintenance.

Profit is estimated from Ryanair's own A321 routes (route profit, 7 days to 17 Oct; E195 routes left out), which earn
about 5.5k plus 10.5k per 1,000 km a flight: Amsterdam–Lisbon (1,846 km) 26.0k, Porto (1,595) 23.6k, Madrid (1,459)
22.0k, Barcelona (1,241) 20.4k; Paris–Lisbon (1,470) 22.7k, Vienna (1,035) 18.7k, Munich (681) 14.2k. Routes past 1,900
km taken about 10% lower. So from Barcelona: Zurich and Rome about 14.5k, Stockholm 27k, Oslo 26k, Warsaw 25k, Budapest
21.5k, Berlin and Hamburg 21k, Prague 20k, Naples 16k, Venice 15.5k, Porto 15k. Nobody flies these from Barcelona (6 Oct
scan) except Alitalia on Rome (1 a week).

## The plan cards (option A for both)
Checked with the planning library's card check: no short turns, night bans, number clashes or same-route gaps. Flight
numbers from Barcelona's block; the base's last number is now 1022 (`airline_bases`).

| Aircraft | Flight | From | Leaves (local) | To | Arrives (local) |
|---|---|---|---|---|---|
| EI-ABQ | FR1011 | Barcelona | 04:40 | Zurich | 06:06 |
| EI-ABQ | FR1012 | Zurich | 07:22 | Barcelona | 08:48 |
| EI-ABQ | FR1013 | Barcelona | 10:04 | Rome | 11:30 |
| EI-ABQ | FR1014 | Rome | 12:46 | Barcelona | 14:12 |
| EI-ABQ | FR1015 | Barcelona | 15:28 | Stockholm | 18:38 |
| EI-ABQ | FR1016 | Stockholm | 19:54 | Barcelona | 23:04 |
| EI-ABR | FR1017 | Barcelona | 14:15 | Berlin | 16:27 |
| EI-ABR | FR1018 | Berlin | 17:43 | Barcelona | 19:55 |
| EI-ABR | FR1019 | Barcelona | 21:11 | Prague | 23:13 |
| EI-ABR | FR1020 | Prague | 00:29 | Barcelona | 02:31 |
| EI-ABR | FR1021 | Barcelona | 03:47 | Budapest | 06:01 |
| EI-ABR | FR1022 | Budapest | 07:17 | Barcelona | 09:31 |

Daily; service R; cabin 321-STD; fares 85% of standard, economy only (manual §5).

## The Amsterdam pair (frequency, decided the same night)
- **EI-ABS** (lands 18 Oct): second dailies to Lisbon (FR3053/3054), Barcelona (FR3055/3056) and Rome (FR3057/3058);
  65 links, 13.0 h, maintenance 112%, about 133k a day.
- **EI-ABT** (lands 19 Oct): second dailies to Porto (FR3059/3060) and Stockholm (FR3061/3062, today flown by an E195),
  third Madrid (FR3063/3064); 63 links, 12.5 h, 127%, about 126k a day.

## Background
- **Ryanair** (briefing, 17 Oct 07:33 UTC): profit 0.99M a day over 7 days, load 100%, cash 5.62M with 5.56M at the
  lowest point. Every route sells out; 24 are on the "ready for another flight" list.
- **The order queue:** with EI-ABT landed on 19 Oct, Ryanair's A320-family delivery line is idle (manual §3, since 17
  Oct).

## Outcome
**17 Oct: A for both,** and A for EI-ABS and EI-ABT, as above. Plan cards in the planner; EI-ABQ and EI-ABR logged as
big-market moves, EI-ABS and EI-ABT as frequency.

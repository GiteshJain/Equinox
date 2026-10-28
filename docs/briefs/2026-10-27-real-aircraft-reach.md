# The default line's reach, from the game's own evaluation — 27 Oct 2026

*Scheduling chat. Source: the aircraft evaluation script's 675 runs of 27 Oct (`aircraft_eval_runs`,
`aircraft_eval_results`; spec `docs/specs/2026-10-27-aircraft-evaluation-script.md`), 17 aircraft types each, all-economy
seats by distance band (Leisure under 3,500 km, Leisure Plus to 6,500, Comfort beyond; Standard for the Ryanair pass).*

## Decision and recommendation
**Recommendation:** replace the default line's reach column (manual §3, from the game's full-load ranges of 18 Oct)
with the distance each variant keeps its full cabin in the seat type we'd fly there, and drop the plain A321neo from
the line. Size by stars, hubs first and everything else stay as they are.

## What the game does
- **No hard range.** Past a point the game takes seats off, gradually, until none are left ("cannot operate" only at
  zero seats, or for an airport restriction).
- **Under 3,500 km every type keeps its full cabin** (Leisure).
- **Airports can cut seats too:** London City cut every type on LCY–Doha, and the E190-E2 can't fly between two
  size-10 airports. The figures below ignore single odd airports (a cut counts only when the routes after it stay cut).

## Reach with a full cabin (our seat type for the distance)

| Variant | Full cabin to (new) | 90% of seats to | Published, full load (today's line) |
|---|---|---|---|
| E195-E2 | **5,700 km** | 5,750 | 3,542 |
| A320neo SHARP | **4,100** | 4,780 | 3,355 |
| A320neo LIGHT | **5,200** | 5,900 | 3,690 |
| A320neo | **5,450** | 6,150 | 4,045 |
| A320neo Heavy | **6,750** | 7,000 | 4,708 |
| A321neo LIGHT | **5,250** | 5,400 | 4,192 |
| A321neo | 5,330 | 5,470 | 4,742 |
| A321LR | **7,700** | 7,900 | 5,809 |
| A321XLR | **8,600** | 8,800 | 6,939 |
| A350-900 | **14,200** | 14,850 | about 15,000 (manual, 21 Oct test) |
| A350-1000 | **over 16,000** | — | beyond 15,000 |

The plain A321neo reaches only 80 km further than the LIGHT and earns less at every distance, so it has no place on
the line. Not on our line but tested: A321neo Medium (full to 5,950), A321neo Heavy (6,990), A321XLR Light (8,290) and
Heavy (9,190).

## What earns most (margin at 80% load; weekly profit per unit of capital cost)

| Distance | Best | Next | E195-E2 | A320neo SHARP | A350-900 |
|---|---|---|---|---|---|
| Under 2,000 km | A321neo LIGHT 42%, 1.92 | A321neo 40%, 1.76 | 26%, 0.92 | 36%, 1.57 | — |
| 2,000–3,500 | A321neo LIGHT 45%, 2.05 | A321neo 44%, 1.88 | 31%, 1.07 | 41%, 1.75 | — |
| 3,500–5,000 | A321neo LIGHT 46%, 1.96 | A321neo 44%, 1.79 | 30%, 1.01 | 39%, 1.51 | — |
| 5,000–6,500 | A321LR 42%, 1.60 (A321neo Heavy 1.62) | A320neo Heavy 40%, 1.44 | 13%, 0.51 | 26%, 0.80 | — |
| 6,500–8,000 | A321LR 32%, 0.95 | A321XLR Light 32%, 0.97 | — | — | 27%, 0.69 |
| 8,000–11,000 | A350-900 26%, 0.64 | ULR 25%, 0.61 | — | — | — |
| 11,000–16,000 | A350-900 25%, 0.62 | ULR 25%, 0.59 | — | — | — |

The tool assumes the seats fill (80%), so a bigger aircraft only earns this where the market fills it; that is what
size by stars is for (§3). Two things stand out: per unit of capital the A321neo LIGHT earns about 15% more than the
SHARP and twice the E195; and narrowbodies earn about three times as much per unit of capital as the A350. Both are
questions for later, not part of this decision.

## Options

| Option | Growth | Profit | Cash | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|---|
| A. Keep the full-load ranges | as now | as now | as now | 3–9M too much on every order bought for reach | none | — |
| **B. Full-cabin reach in our seat type (recommended)** | **as now** | **lower lease on reach orders** | **3–9M of list price saved per order that drops a variant** | **none** | **low: a full cabin, from the game itself** | **yes** |
| C. 90%-of-seats reach | a little further per variant | lower still | more | up to 10% of seats lost on the longest routes | some seats lost | yes |

## What changes with B
- Routes of 3,355–4,100 km take the SHARP instead of the LIGHT or plain A320neo; 3,690–5,200 km the LIGHT instead of
  the plain A320neo or Heavy; up to 6,750 km the Heavy, where today nothing in the A320 family reaches.
- Large: the A321neo LIGHT to 5,250 km, then the LR to 7,700, then the XLR to 8,600 (today the XLR stops at 6,939, so
  routes of 6,939–8,600 km, e.g. Dallas–Gatwick 7,660, could fly a narrowbody instead of an A350).
- Small: the E195 to 5,700 km (today 3,542).
- `aircraft_types.range_km` (the planner's and `competition()`'s reach) is updated with the manual, and the A350
  rows' stale 11,102 km with them.
- Asking before pushing past a variant's reach (§3, since 26 Oct) stays, at the new figures.

## Review and outcome (27 Oct)
- **Review:** a stricter pass ignoring one-off airports (London City; the E190-E2's size-10 pairs) gave the same limits;
  the two route sets agree within about 100 km; neighbouring variants hand over on earnings within 250–500 km of their
  reach; Gitesh's 9 hand checks on routes the script never ran all matched (just inside: full; just past: a few seats
  fewer). Corrected in the review: the A350-1000 keeps its full cabin to about 15,200 km (376 of 416 seats on JFK–Sydney,
  16,014 km), not beyond 16,000; the ULR keeps the most seats only beyond about 16,500 km. Ryanair: the SHARP keeps a
  full Standard cabin to 3,600 km; Ryanair's longest listed route is 3,343 km.
- **Outcome: B, Gitesh, 27 Oct**, with the E190-E2, the A320neo and the A321neo off the line (and the ULR off the types
  each airline may buy). Manual §3, `aircraft_types.range_km` and `airline_aircraft_types` changed the same night;
  `competition()`'s -900/-1000 cut-over (15,000 km in its code) is listed under Decided, not yet built.

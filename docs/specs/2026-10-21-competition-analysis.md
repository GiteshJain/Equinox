# Build spec: competition analysis (21 Oct 2026)

**Why:** Gitesh, 20–21 Oct. This is step 3 of the planner work (brief `docs/briefs/2026-10-21-competition-analysis.md`,
and its outcome: the world scan now runs with the evening capture). Route first, then the airline (manual §3): each
evening's order proposal picks the route we most want to fly, and needs a ranked list. Market share first (manual §3):
we need to see our share and the rivals' moves.

**Outcome when done:**
- A **Competition** screen with market share, threats, ranked openings and rival profiles.
- Rival alerts on Today.
- The fare ladder's **rival pause** working (manual §5).
- One database call the Scheduling chat reads for the evening proposal.

## 1. The figure: `competition()` in the database
One home for the calculation: `private.fig_competition(p_airline_id, p_as_of)` and a staff function
`public.competition(p_airline_id, p_as_of)`, read with GET. New migration (adds or `CREATE OR REPLACE` only), with
descriptions, grants and a database test.

**The scans used:**
- **latest:** the latest finished scan by `p_as_of`;
- **week before:** the latest finished scan at least 6 days older than latest, else the oldest there is;
- **previous:** the latest finished scan before latest.

All three are named in the answer with their dates. Rivals are every airline in the scan that isn't one of ours
(groups kind `ours`).

### 1a. Market share (by the airline's markets)
- **Each of the airline's markets:**
  - the city pairs: its routes, flown or not, either direction;
  - our weekly departures on them (the airline's live legs);
  - each rival's weekly departures on the same pairs, from the latest scan's schedules (days per flight counted, as
    `gscan.py` counts `n_weekly`);
  - our share, and the top 5 rivals with theirs;
  - each figure's change against the week-before scan.
- **The group line:** our airlines' weekly departures against the world's (the latest scan's totals), with the change.

### 1b. Threats (since the previous scan)
- **What counts:** each city pair the airline flies where a rival started (no departures in the previous scan) or added
  at least `competition_threat_min_weekly` departures a week (new setting, 7, described).
- **What each threat shows:** the rival, their weekly departures then and now, and our own on the pair.
- **The window:** a threat stays listed for 7 days from the scan that first showed it.

### 1c. Openings, ranked (manual §3, market share first)
- **The candidates:** each route on the airline's list (`routes`, not removed) that no airline of ours flies, either
  direction.
- **Each opening gives:**
  - the city's stars;
  - the distance;
  - the rivals flying the pair and their weekly departures (latest scan);
  - the **variant** that reaches it, from the default line (manual §3; the cheapest variant whose `range_km` covers
    the distance within the stars' size band, as the manual's table does). Openings beyond every allowed type's
    reach are left out;
  - whether it's **allowed under hubs first** (manual §3: from the main hub while it's under `hub_first_departures`;
    from another base only if contested by the house rules' thresholds; Ryanair exempt), with the reason when it
    isn't.
- **The rank:**
  1. stars;
  2. then rivals' weekly departures on the pair;
  3. then the shorter distance;
  4. then the pair's code.

  Openings not allowed under hubs first are listed after the allowed ones, marked.
- **Size:** the top 50 by default; `p_limit` can give more.

### 1d. Rival profiles
- The rivals who fly most of our city pairs, the top 10 by pairs shared.
- For each: weekly departures (latest and week-before), airports, the pairs shared with us, and their biggest
  airports.

### The test
`database/tests/competition_test.sql`, on a world made inside the test with three scans:
- the share and its change;
- a threat appearing, and leaving after 7 days;
- openings ranked and the hubs-first marks;
- a variant chosen by reach;
- one left out beyond every type's reach;
- profiles.

## 2. The fare ladder's rival pause
- **In `private.fig_fare_ladder()`** (`CREATE OR REPLACE`): a route and cabin whose pair has a threat (1b) from a scan
  in the last 7 days **holds**.
  - Its reason: "rival Air China started here on 22 Oct: paused until 29 Oct".
  - The order of the checks: after `planned`, `young`, `few`, `held` and `added`, before the sold-out share.
  - Take the threat out of the notes. Read the threats from the same SQL as 1b, with a shared private function.
- **Tests:** the fare ladder test gets the rival case.

## 3. The planner
- **A new screen, Competition** (`/planner/competition`, `/planner/competition/<code>`), after Performance in the
  navigation. Phone first; the rules for every screen (`docs/specs/2026-10-20-today-performance-systems.md`). Its
  parts:
  - **Market share:** one card per market, our share with its arrow and the top rivals as a bar; the group line on
    top.
  - **Threats:** each with the rival, the pair, the numbers and the day.
  - **Openings:** the ranked table, with rank, pair, stars, distance, rivals, variant and allowed. Cut to 10 with
    "show all".
  - **Rival profiles:** cards.
  - The scans' dates at the top ("latest scan 21 Oct, compared with 14 Oct").
- **Today:** threats from the last scan in Needs attention ("Air China started on PVG–CAN, 14 a week"), linking to
  Competition. They aren't fare moves, so the manual's rule doesn't keep them off.
- **Small fixes from the scan build:**
  - the Systems board's scan line (`screens/systems/systems.ts`, `scanLine`) says the scan runs with the evening
    capture (`scan_every_days`), not at the Saturday review;
  - `scan_every_days` editable in Reference → constants, like the other settings there.

## 4. The Scheduling chat's call
- `competition()` is in the map's "Which call answers which question" ("which routes to open next, ranked"), with a
  tested example.
- The airline briefing (`private.briefing_doc`) carries the top 20 openings and the threats, so `brief.py` shows them.
  Update `brief.py`, its test and its sample if the shape needs it.

## Checks
- `bash tests/run_all.sh` green.
- The rehearsal green, with the new database tests on the copy.
- Screenshots of Competition at both widths.
- The pull request lists, from the copy:
  - each airline's top 5 openings;
  - the group's share;
  - any threats between the two scans (6 and 17 Oct).

## Docs
- Manual:
  - §3, the openings rule naming `competition()`;
  - §5, the rival pause built;
  - "Decided, not yet built": take out the rival pause note.
- `docs/planner-guide.md`: Competition, Today's threats, Systems and Reference.
- `docs/architecture.md`: the Planner row, the figures, the guide's row.
- `docs/playbook.md`: the evening proposal reads the openings; Saturday's competition step.
- `tests/README.md`.

## Not in this build
- The route page (step 4).
- Any change to how the scan reads the game.

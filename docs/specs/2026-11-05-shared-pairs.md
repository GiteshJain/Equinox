# Spec: shared city pairs, two of our airlines on one pair at one price

Decided by Gitesh, 4 Nov 2026 (brief `docs/briefs/2026-11-04-shared-pairs.md`, option B with Ryanair out: "I want b
tomorrow i think. It seems like how a real consortium would operate"). One build, two or three pull requests in the
order below. **Start from `main` after the default-price build has merged** (`docs/specs/2026-11-04-fare-default-from-market.md`):
both change `private.fig_fare_ladder`, and they are not to be built side by side. Read `CLAUDE.md`, the map
(`docs/architecture.md`), manual §2 (one airline per city pair), §3 (the openings), §4 (the trunk month), §5 (the fare
ladder) and the fare-ladder specs (`docs/specs/2026-10-21-fare-ladder.md`, `2026-10-26-fare-ladder-per-direction.md`)
first.

## The rule being built (manual §2, in force once this is merged)
- A **shared pair** is a city pair whose two airports are bases (hub or focus city, never a station) of two different
  airlines of ours, neither of them Ryanair. The airline §2's country rule gives the pair is its **owner**; in the data,
  the airline whose `routes` row for the pair exists today (every flown shared pair has exactly one). The other airline
  is the **joiner**.
- Both may fly it. Every flight on the pair, either airline's, sells at the pair's one price: **the owner's level** per
  direction and cabin (§5). The owner's ladder judges the pair on both airlines' flights; the joiner follows.
- A joiner adds a flight only while the pair sells out (§3's rule for any added frequency). The next flight on a shared
  pair goes to the owner when it can fund it that evening, otherwise to the joiner.
- Pairs inside one airline's region, Ryanair's pairs and pairs to stations are unchanged: one airline per city pair.
- For the first two Saturdays after the build, at most 6 pairs have a joiner, so the review can watch the pair ladder.

## 1. Data (one migration)
- `routes.shares_route_id bigint null`, a reference to the owner's `routes` row: same world, same two airports, a
  different airline. Described. A check that a row with it set has no `shares_route_id` of its own (one level of
  joining), and a unique index so an owner has at most one joiner. Grants unchanged (`routes` is read by the planner and
  the figures already).
- A world-level setting `shared_pairs_excluded_airlines` (jsonb list of airline ids, `[3]` for Ryanair), described,
  under Reference → constants.
- A view **`shared_pairs`** (described, same grants as `routes`): one row per pair whose two airports are bases of two
  different airlines of ours, neither excluded: `owner_airline_id`, `joiner_airline_id`, `owner_route_id`,
  `joiner_route_id` (null until joined), the two codes, `owner_flights_week`, `joiner_flights_week` (from
  `flight_legs`), `joined_on` (the joiner row's `created_at`). The owner of an unflown pair is the airline whose
  `routes` row exists; if neither has one, the country rule's airline is named in the view from a small mapping table or
  function the build adds (`private.pair_owner(a, b)`, the §2 rule as data: US/UK–India → Kingfisher, US–UK/Europe/China
  → Pan Am, UK–Europe/China/Malaysia → Virgin, Europe/India–China → China Eastern, Malaysia → Malaysia).
- **Joining a pair:** `public.join_pair(p_owner_route_id)` (security definer like the other saves, actor-logged) creates
  the joiner's `routes` row for the other base's airline, copying `stars`, `stars_override`, `market`, `distance_km`,
  `cabin_choice`, `market_layout` from the owner's, with `shares_route_id` set; refused when the pair isn't a shared pair,
  the joiner is excluded, a joiner row exists, or more than 6 pairs are joined and today is within 14 days of the
  build's `settings.shared_pairs_from` date. The Routes screen and the owner's route page get a **Join this pair**
  button (the joining airline named on it); the Scheduling chat may call the function directly.

## 2. The fare ladder (`private.fig_fare_ladder`)
- **The owner's ladder judges the pair on both routes' flights:** for an owner route with a joiner, each direction and
  cabin's sold-out share, departures (for `fare_ladder_min_departures`), load and the fare index come from the union of
  the owner's and the joiner's captured flights that way. The step, cap and launch level are the owner's (its
  `settings` rows). The capacity hold (`fare_ladder_capacity_hold_days`) counts a rotation added on either route. The
  rival pause and `contested` are per pair already.
- **The joiner follows:** a joiner route's rows show the pair's level and move (`follows`: the owner's airline and route
  id), never a move of their own. Its only actions are set-backs: any flight of its latest captured day that way more
  than a point off the **pair's** level lists one change for that direction at the pair's level, listed as today's
  set-backs are (first, any day, applied by the fares script). When the owner's fare plan moves the pair, the joiner's
  next ladder read lists the same level for the joiner as a set-back, so the joiner's price follows within a day of
  the owner's plan being applied (bookings open 3 days ahead, §9, so both airlines' new fares reach flights together).
- **Put on the fare plan** writes the owner's rows as today; the joiner's set-backs are written by the joiner's own
  Put on the fare plan (the review chat presses the owner's first, then the joiner's). `fare_plan` rows stay per
  airline and route; `planner_save()` unchanged.
- The joiner's first flights are not a "new route" for the ladder (they start at the pair's level, shown on the plan
  card); they are a new frequency for the capacity hold.
- `off_level` counts the joiner's directions off the pair's level. Keep the 30 s limit; the union adds one route's
  flights per shared pair.

## 3. Growth, openings and the evening proposal
- `growth_signals()`: sold out, ready for another flight and fix or reduce are judged per pair for shared pairs (both
  routes' flights), listed once under the owner with `shared_with` (the joiner's airline and whether it flies the pair),
  and under the joiner as `follows` the same figures.
- `competition()`'s openings: a shared pair that either airline flies is not an opening for the other; the joiner's
  unflown shared pairs appear in its openings only when the owner's cash forecast can't order that evening
  (`cash_forecast(owner)->'next_order'->>'when' <> 'now'`), marked "owner can't fund tonight". The evening proposal
  (manual §3, §4) offers a shared pair's next flight to the owner first, then the joiner, by that mark.
- `hub_progress()` unchanged (departures per airline base).

## 4. Views and the report
- `route_profit()`: a shared pair's rows carry `pair`: the other airline's flights a week, loads and profit on the
  pair, and `shared_role` (owner / joiner). The airline's Performance page marks them ("shared with Kingfisher: 14 a
  week, 100%").
- **The route page is one page per pair** (Gitesh, 4 Nov: combined figures and story). The owner's and the joiner's
  route addresses (`/performance/<code>/<route>`) open the same page, titled with both airlines. `route_story()` for a
  shared pair returns the pair: **combined where the market is one** (flights a week, seats, load, sold-out share, the
  fare level, both airlines' flights together, which is what the ladder judges), **separate where the money is** (each
  airline's flights, revenue and profit on their own beside the pair's totals, since each keeps what it flies), and
  **one timeline** of both airlines' events, each marked with its airline: schedule saves, fare moves, the day the
  joiner came in, rivals arriving. The charts draw the two airlines in two colours on one axis. The joiner's view says
  it follows the owner's ladder.
- **The Routes screen** marks a shared pair on both airlines' rows with the other airline's flights a week and role,
  so a joiner's 14 a week isn't read as the whole pair.
- `fare_results()` (built 4 Nov): a joiner direction's "moves" are the pair's; its before/after figures are its own.
- The weekly report (`scripts/report/build.py`): shared pairs listed once per pair in a "Shared pairs" line under the
  group, with both airlines' flights and loads; each airline's route profit table marks them.
- The group Performance page: a **Shared pairs** row listing every joined pair, both airlines' flights a week, the
  pair's load and level, and the 6-pair limit while it applies.

## 5. Plan cards and the library
- A joiner's plan card finds its route row as any card does (`lib/rules` looks routes up by pair and airline); its
  fare level per direction is the pair's (the owner's). check-card unchanged. The card's note names the owner.
- `connections.ts` already counts connections across our airlines; nothing changes.

## 6. Docs and tests
- Manual: §2's sentence (already written in the manual as decided; move it from *Decided, not yet built* to in force,
  with `settings.shared_pairs_from` set to the merge date), §3's openings line, §4's trunk-month line, §5's "Shared
  pairs have one ladder", §7's review line. `docs/architecture.md` (the view, the function, the ladder's pair
  judgement). `database/current/functions.sql`. Playbook: step 2 of the five things ("check no other airline of ours
  has the pair") gains "unless it's a shared pair: then the owner first", and §3's shape-of-the-group list.
- `database/tests/`: a shared pair with both airlines flying (the owner's rows judged on both routes' flights; the
  joiner's rows follow; a joiner flight off the pair level lists a set-back; a frequency added by the joiner holds the
  pair), `join_pair()` refusals (Ryanair, a station, a second joiner, the 6-pair limit), the openings mark. Planner
  unit tests for the Join button, the route page's two-airline story and the Shared pairs row. The report's and
  briefing's saved answers updated where they move.
- Run `bash tests/run_all.sh`; the pull request says which saved answers moved and why.

## Pull requests, in order
1. Data and the ladder (§1, §2) with its tests: nothing joins until the function exists.
2. Growth, openings, views, report, plan cards (§3–§5).
3. The Routes screen's Join button and the Performance rows, if not in 2.

## Out of scope
Ryanair on shared pairs (excluded by decision); pooling cash between airlines (the game can't); pairs to stations;
long-haul pairs beyond the A321LR's reach are shared pairs like any other but wait under §4's short-haul-first rule.

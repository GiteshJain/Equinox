# Build spec: cabins follow the new rule (21 Oct 2026)

**Why:** Gitesh, 21 Oct (Building chat). Since 20 Oct the cabin is chosen with each order (manual §5):
- if one route takes more than 65% of the aircraft's block time, the layout that route's market calls for
  (Standard, Leisure, Leisure Plus or Comfort);
- otherwise the layout with the most seats;
- Ryanair flies Standard only.

We no longer refit. Three parts of the planner still work the old way. Build this **after the fare ladder is merged**,
since both touch Performance, Systems and the tests.

**Outcome when done:**
- The plan card says which cabin the rule calls for and warns when the chosen one differs.
- Each market stores only its layout.
- Nothing suggests a refit any more.

## 1. Retire the Cabins board
- **Take out of the planner:**
  - the Cabins board on Systems;
  - its buttons (**Refitted to**, **Keep as is**, **Show again**);
  - the library's `cabins.fit` and refit cost, unless something else uses them.
- **Database (new migration):**
  - remove the settings `cabin_refit_cost` and `cabin_refit_share_pct`;
  - keep `aircraft_cabin_keeps` and its rows as history: describe it as retired, nothing writes to it;
  - past refits stay in `spending_log`.
- **Tests:**
  - `tests/planner_saves_test.py` loses the three Cabins kinds of save; say so in the pull request;
  - the figures test loses any Cabins figures.

## 2. Each market keeps only its layout
- **New migration on `markets`:**
  - add `layout` (text, one of Standard, Leisure, Leisure Plus, Comfort; a check constraint; described);
  - fill it from the cabin of the current `default_config_id` (the values are listed below; Ryanair's markets are
    Standard);
  - make it not null;
  - then drop `default_type_id`, `default_config_id`, `fare_y_pct` and `fare_j_pct`.

  Check first that nothing else in the database uses those columns (functions, views, `rules_input()`,
  `export_for_report`). Update anything that does in the same migration, and say so.
- **Where the planner used them:**
  - The Routes screen and route detail showed the market's type, cabin and fares. Show its layout instead.
  - Reference's market defaults becomes "Markets", with the layout editable (one `planner_save()` change).
  - The CSV export takes `layout` too.
  - Today's Game check, and the library's `game.ts`, used the market's type to estimate block time when a rotation
    had no aircraft. Use the airline's most-flown type instead, and say so.
  - A route's own `cabin_choice` still wins over its market's layout.
- `rules_input()` and the library's types carry `layout`. Regenerate `types.ts` and `data.md` from the rehearsal.
- **Today's values** (default cabin → layout):
  - Leisure Plus: every `-LP` cabin;
  - Comfort: every `-CMF` cabin;
  - Leisure: every `-LEI` cabin;
  - Standard: every `-STD` cabin (Ryanair).

## 3. The plan card suggests its cabin
- **In the library** (`lib/rules/`, beside the card check in `card.ts`), `cabinFor(rules, card)`:
  - **Block time:** each route's share of the card's block time, using its legs and the library's block-time rule.
  - **One route over the threshold:** if a route is over `cabin_route_share_pct` (a new setting, 65, described), the
    layout is that route's `cabin_choice`, else its market's `layout`.
  - **No route over the threshold:** the variant's layout with the most seats.
  - **Ryanair:** always Standard.
  - **From layout to cabin:** the cabin is the card's variant's `cabin_configs` row with that layout. If the variant has
    no layout of that name, use its layout with the most seats and say why.
  - **What it returns:** the suggested cabin, the reason in words ("JFK–LHR is 72% of block time: Leisure Plus" or
    "no route over 65%: the most seats"), and whether the card's `config_id` differs.
- **`checkCard` and the plan card check:** flag a card whose cabin is missing or differs from the suggestion, as an
  issue with the reason. This includes the command the other chats run (`check a plan card`).
- **Tails → Deliveries:**
  - the plan card shows "suggested: 321-LP" with its reason beside the Cabin box;
  - one tap, **Use the suggestion**, sets it (the existing card-cabin save, no new kind);
  - a differing cabin shows in amber.
- **Unit cases:**
  - a route over 65%, and exactly 65% (not over);
  - no route over 65%;
  - a route's own `cabin_choice`;
  - a variant without that layout;
  - Ryanair;
  - a card with no legs.

## Manual and docs, in the same pull request
- Manual §5:
  - the cabin rule names the setting `cabin_route_share_pct` and the market's `layout`;
  - drop "A refit costs about 0.2M (`settings.cabin_refit_cost`)";
  - drop "Prices per market are in the planner (`markets`)" from the fares rule;
  - move the refit wording to Retired rules.
- Remove this item from "Decided, not yet built".
- `docs/planner-guide.md`: Systems, Routes, Reference, Tails.
- `docs/architecture.md`: the Planner row and the Cabins mention.
- `docs/playbook.md`: any Cabins or refit step.
- `tests/README.md`.

## Checks
- `bash tests/run_all.sh` green; the rehearsal green (the migration on last night's backup, with a database test
  that every market has a layout and the dropped columns are gone).
- No figure moves except the removed Cabins ones; say which.
- The pull request lists, from the rehearsal's copy, the suggested cabin for every plan card not yet filed, and which
  differ from the card's cabin.

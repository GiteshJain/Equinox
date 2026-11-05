# Spec: the fare ladder reads the game's default price from the market pages

Decided by Gitesh, 4 Nov 2026 (Scheduling chat): "on the market analysis sheet, there is a market default rate and our
highest current price for that route. we would still need to step back incorrect fares as this would only tell us the
highest one for that route" — "do it". One pull request. Read `CLAUDE.md`, the map (`docs/architecture.md`), manual §5
(the fare ladder) and §7 (the market pages), and the specs `docs/specs/2026-10-21-fare-ladder.md`,
`2026-10-26-fare-ladder-per-direction.md` and `2026-10-30-market-pages.md` first.

## Why
The ladder never sees the game's default price. It infers each direction's level from fares: the first fare the
captures saw (`baseline_fare`) is taken to be at the launch level (100%, Ryanair 85%), and the level is the latest fare
against it. When the first capture wasn't at launch (a route opened mid-change, a new flight started at another price),
every level after it is wrong, and the set-back check corrects fares towards the wrong number.

A likely case on 4 Nov: Ryanair's CDG–Hamburg economy has `baseline_fare` 118 and today's average 100, so the ladder reads
"captured fare at 72%, level 85%" (100 ÷ 118 × 85) and lists a set-back. If 118 was in fact the default price (a route
launched at 100% by mistake), the fare is exactly at its 85% level and the set-back would raise it wrongly. The same
pattern (captured about 72–76% against 85–90%) appears on CDG–Menorca both ways, CDG–Thessaloniki both ways,
Seville–CDG, Malta–CDG and Budapest–Barcelona. Where the inference holds, the market page agrees: Kingfisher's
DEL–BOM economy, default 143 AS$ and current 150 AS$ on the saved page (`tests/fixtures/market_DELBOM_2026-10-30.html`),
105%, which is what the ladder has.

## 1. The capture (`capture/capture_all.user.js`)
- `readMarketPage()` also reads the page's **Pricing** panel: for each class row (Y, C, F, Cargo), **Current Price** and
  **Default Price** (AS$, as numbers). It only reads them: the capture still never submits the Pricing form.
- `marketPagePayload()` sends them as `pricing: [{class: "Y", current: 150, default: 143}, …]`. A page without the
  panel sends none (no error).
- Bump the capture's version. Extend `tests/capture_market_test.mjs` on both saved pages (DEL–BOM: Y 150/143, C 322/307,
  F 539/…; read DUB–AMS's from its fixture).

## 2. The database
- A new table **`market_prices`** (read_id, world_id, airline_id, service_class, current_price, default_price), one row
  per class of a read; described, with grants like `market_fares`. `capture_market()` writes it from `pricing`.
- A view or figure **`default_prices`**: for each airline, route (hub, dest), direction and cabin (economy = Y,
  business = C), the latest finished market run's default price and current price, the run's date, and the default
  in the run before it (so a change shows).

## 3. The ladder (`private.fig_fare_ladder`)
- **The level comes from the default price where the market pages have one:** a direction's level = its captured
  fares ÷ the default price × 100, rounded to 0.1 (the same fares the index uses today: `latest`, the latest captured
  day's average that way). `baseline_fare` becomes the default price; add `default_source`: `market` (with the run's
  date) or `inferred` (no market read for that direction yet: today's method unchanged).
- **The ladder's moves** (up, hold, down, the jumps, the cap, the floor) are unchanged: they start from that level.
- **The set-back check is unchanged in kind, measured against the default:** any flight of the direction's latest
  captured day more than a point off its level (its own fare ÷ default) lists one change for that direction at its
  level. The market page's current price is only the highest of our flights, so the per-flight fares still come from
  the nightly capture (Gitesh: "we would still need to step back incorrect fares").
- **Plan cards** show a new route's level in AS$ as well as %, from its default where the market pages have read the
  pair; otherwise as today.
- Keep the figures' time limit; `default_prices` is small.

## 4. The first run's check
When the first market run with prices lands, list every direction where the default-based level differs from the
inferred level by more than a point (a section on the Systems board's market line, or a one-off query result in the
pull request's notes if the run hasn't happened yet). Those directions were priced against a wrong baseline; the next
fare plan's set-backs correct them once.

## 5. Docs and tests
- Manual §5: replace the sentence that defines a level's baseline ("Each direction's level is its own latest fare plan
  row…" stays; the part on how captured fares are read against the level) with: the level is measured against the
  game's default price, read each week from the Market Analysis page; where a pair hasn't been read yet, against the
  first captured fare as before. §7's market-pages line: they also keep each class's default and current price.
  Log the old wording in `docs/rule-history.md`.
- `docs/architecture.md`, `database/current/functions.sql`.
- `database/tests/`: a direction with a market default (level from it, set-back against it), one without (inferred,
  as now), and one where the default changed between two runs (the level moves, a set-back is listed).
- Run `bash tests/run_all.sh`; say in the pull request which saved answers moved and why (the fare-ladder answers will,
  where the default differs from the inferred baseline).

## Out of scope
How often the market pages run (`market_every_days`, 7). Whether the default ever moves: the first two runs will show
it; if it does, nothing else changes, the ladder simply sets the affected directions back to their level.

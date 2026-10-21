# Build spec: the fares userscript (21 Oct 2026)

**Why:** Gitesh, 21 Oct. The fare ladder's changes go route by route, in both directions (manual §5), which is a few
hundred game changes on a Saturday. A userscript makes them for him, one at a time, while he watches. **His decision,
knowing the game's terms (simulogics §4 II) don't allow scripts** (manual, "Decided, not yet built").

Build this **after** `docs/specs/2026-10-21-fare-actions-by-route.md` is merged. It reads that list.

**Outcome when done:**
- In the game, one button, **Apply fare plan**, makes every planned fare change for every airline, then says what it
  did.
- The next capture ticks each change off on the fare plan.

## The game's form (from Gitesh's saved page, 21 Oct, v6.13.17)
- **The page:** `/action/enterprise/flightsPrices`, for the airline active in the session. Airlines switch as the
  capture does: `/app/enterprise/dashboard?select=<game id>`.
- **One change is one GET** to `flightsPrices` with:
  - `adjust=true`;
  - `fromCode=a:<id>` and `toCode=a:<id>`, the airports' game ids, read from the page's own `fromCode` and `toCode`
    options, whose text ends with "(IATA)". An option `c:<id>` is a country; never use one;
  - `serviceProfileId=0` (any);
  - `factor=1` (+) or `-1` (−);
  - `percent` 0 to 100, a whole number;
  - `base=standard` (default price);
  - `economy=true` and/or `business=true` for the classes.
- **The answer page lists "Changed Airport Pairs":** From, To, Service Class (Y, C), Old Price and New Price. That is
  how the script checks each change: one row per class it named, for that From and To.
- **A saved copy for the tests:** `tests/fixtures/flightsPrices_2026-10-21.html`, the form page, cut down to the form
  and its options, no account data. Gitesh's answer-page screenshot shows the result table; build a small fixture of
  it by hand from the screenshot (LHR→JFK, C 1,010 → 1,010, Y 407 → 407).

## 1. The database: what the script reads
- **New migration:** `public.capture_fare_actions(p_key text)`, run as owner, granted to anon and authenticated like
  `capture_airlines()`. With a valid capture key, for each active airline of the key's world, it returns that
  airline's `fare_ladder()` actions for routes that are **on the fare plan this week and not yet seen in the game**:
  `planned` and not `applied`.
  - Each action gives: the airline's game id, its name, n, from and to (IATA), sign, pct, the classes, and the
    route's plan row id(s).
  - With no valid key, it refuses as `capture_airlines()` does.
  - It carries a description and a database test (`database/tests/capture_fare_actions_test.sql`):
    - a bad key refused;
    - only planned and unseen rows listed;
    - another world's airlines left out.

## 2. The userscript: `capture/fares_apply.user.js`
- **Header:** a userscript like `capture_all.user.js`, with the key a placeholder (`__CAPTURE_KEY__`), `@match` the
  game, and a version.
- **One button, Apply fare plan.** It:
  1. reads `capture_fare_actions`;
  2. shows the count for each airline, and asks once in the page (not `confirm()`) to go ahead;
  3. for each airline: switches to it, opens `flightsPrices`, maps each IATA code to its `a:` id;
  4. makes each change with one GET;
  5. checks the answer's table for that From and To and each class named;
  6. waits **2 seconds** before the next one.
- **It stops at the first problem** and says which change and why:
  - an airport missing from the form;
  - an answer without the expected rows;
  - an HTTP error;
  - the session lost.

  What's done stays done. Run it again and it reads only what's still unseen, though changes made since the last
  capture show as unseen until then, and setting a level twice does no harm.
- **The panel**, like the capture's:
  - progress ("Pan Am: 12 of 50");
  - a **Stop** button;
  - at the end, each airline's count of changes made, and "the next capture ticks them off on the fare plan".
- **State is kept in `sessionStorage`,** as the capture does, so switching airlines (a page load) carries on where
  it was.
- **Nothing else in the game.** It reads only the fares page and its answers, and changes only prices.

## 3. Tests
- `tests/fares_userscript_test.mjs` (Node, no browser needed if the logic is split from the page code, as functions
  the test imports), on the fixtures:
  - the airport map read from the form page;
  - the GET address built for a + and a − change, with one class and with both;
  - the answer parsed, with the right rows found and a missing row caught.

  Added to `tests/run_all.sh` and `tests/README.md`.
- `tests/check_secrets.py` still passes: the key stays a placeholder.

## Docs
- `docs/architecture.md`:
  - a row for the fares userscript;
  - `capture_fare_actions()`;
  - the key table (the capture key now also lives in Gitesh's copy of the fares userscript).
- `docs/playbook.md`: the Saturday fare step. Put on the fare plan in Performance, then run **Apply fare plan** in the
  game, watching it. The next capture ticks the changes off.
- The manual: §5 names the userscript; remove it from "Decided, not yet built".
- `scripts/README.md` or `capture/README.md` if there is one: how to install it (as the capture script, the key in
  place of the placeholder).

## Not in this build
- Running it on a schedule, or without Gitesh watching.
- Any other change in the game.

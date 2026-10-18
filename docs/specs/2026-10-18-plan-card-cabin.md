# A plan card carries its cabin, and filing uses it (18 Oct 2026)

Bug report from Gitesh, 18 Oct (Building chat).

## The bug
- Filing (Tails → Deliveries → **File into planner**, or Home's) gave the aircraft its order's cabin
  (`aircraft.order_config_id`). Orders carry no cabin since 2 Oct (manual §3: the cabin is chosen when the aircraft
  arrives), so all 16 aircraft filed on 16–18 Oct ended up with no cabin.
- It logged the first fit in `spending_log` at the airline's default cabin for the type (`order_cabin()`: 321-LEI
  192,000 for an A321neo, XLR-CMF 211,400 for an XLR), not the cabin fitted. The game charged 206,400 (321-LP or XLR-LP)
  for B-0311, 9M-AAS, N017AW, VT-ABA, B-0312 and 9M-AAT. The Scheduling chat corrected spending_log 161, 162, 176, 178,
  183 and 185, and the 16 aircraft's cabins, by hand.
- Cause: `filingChanges()` in `app/planner/src/screens/tails/model.ts` took `a.order_config_id`, and `Filing.tsx` fell
  back to `order_cabin()`. Plan cards had no cabin field; the chosen cabin was written only in the card's note.

## The change
- `plan_cards.config_id` (migration `20261018090000_plan_card_cabin.sql`): the cabin chosen with the routes, a foreign
  key to `cabin_configs` within the world, described.
- The plan card shows its cabin beside the type ("no cabin chosen" when neither the card nor the order names one).
  Until the aircraft is filed, the card's **Cabin** box sets it (one `planner_save()` change on `plan_cards`).
- Filing (`filingCabin()`, `filingChanges()`): the card's cabin, else the order's, else none. With one, the aircraft
  gets that cabin and the first fit is logged at its `cabin_configs.cost`. With none, the aircraft keeps whatever cabin
  it has, nothing is logged, and the filed message says so. `order_cabin()` is no longer used by filing (it stays for
  the cash forecast and the briefing).
- The Scheduling chat writes `config_id` on each card it makes (manual §4). Its workaround until this is live (setting
  the aircraft's `order_config_id` to the planned cabin) keeps working, since the order's cabin is the second choice.

## Tests
- `tails.test.ts`: the card's cabin wins over the order's, and the first fit is logged at its price; the order's when
  the card has none; with neither, no cabin is set and nothing is logged, and a cabin set by hand is kept; choosing and
  clearing a card's cabin is one change on the card.
- `tests/planner_saves_test.py` and its saved answers: a new kind of save, "tails: choose a plan card's cabin" (one
  `plan_cards` update of `config_id`). Filing's saved answers don't change.

## Not in this change
- **Checking the game's charge** after the nightly capture against the logged fit (Gitesh's optional idea): its own
  item, not started.
- **The refit cost** (`settings.cabin_refit_cost` 200,000): the game's charges vary. Most refits on 15–17 Oct cost
  82,800, from 321-LEI OLD to 321-LEI, but two Pan Am charges on 15 Oct were 120,000. One setting can't be right, so the
  question goes to Gitesh separately.

# Build spec: Today, Performance and Systems, and Hubs retired (20 Oct 2026)

**Why:** Gitesh, 20 Oct (Building chat). Check and Review are tangled together, short on features and no fun to use,
and he never opens Hubs. This is step 1 of four, and it sets where everything lives. The later steps each get their own
spec: 2, the fare ladder; 3, the route page; 4, competition analysis.

**Outcome when done:** the planner's screens are grouped by when they're used, not by where their data comes from.
- **Today** answers "what do I do now?" It's the evening after a capture, or whenever one lands.
- **Performance** answers "how are we doing, and why?"
- **Systems** holds the plumbing, which is rarely opened.
- **Hubs** is gone.

Nothing is lost. Every board that stays keeps its figures, and every save writes the same rows as before.

## The screens and what moves where

| Today (`/planner/today`) | Performance (`/planner/performance`, `/performance/<code>`, `/performance/<code>/<route>`) | Systems (`/planner/systems`) |
|---|---|---|
| **The capture in one line:** "All six airlines captured, all good, 17:08" or what's missing, short or broken, with a link to Systems (`capture_status()`) | **Scorecards, one per airline:** Review's cards, each figure with its change against the same day last week from `airline_days`, and an arrow. Tap a card to open the airline | **Systems board**, as on Check now |
| **Orders:** for each airline, whether it can order now or from when, the types that are safe, and each delivery line with when it runs dry. From Check → Growth's "can order" and Order queues, and `cash_forecast()` | **The airline's page,** as Review's now: profit, cash for the next 14 days, route profit, aircraft, fare changes and the fare plan | **Capture details** and the backup line, from Check's Capture board |
| **Aircraft to file:** arrived with a plan card, with **File into planner** (from Home's Aircraft on order) | **Growth signals:** Ready for another flight, Raise fares, Fix or reduce, and Aircraft losing money after their lease (from Check → Growth) | **Manual entry**, from Review |
| **Needs attention**, moved whole from Home, with dismiss and show again | **Main hubs towards 750:** one bar per hub, with Hub readiness folded into its line | **Cabins**, from Check |
| **Game check**, from Check | **Flights by day:** Check's daily load report, renamed | **Aircraft checks**, from Check, shown only while the checks are on |
| **The to-do board and Coming up**, from Home | | |

**Home** keeps the globe, the network map, Aircraft on order (without the file button, which moves to Today) and the
airline cards. Needs attention, Coming up and the to-do board move to Today, so each thing lives in one place.

**The navigation:** Home, Today, Routes, Tails, Performance, Interline, Photos, Reference, Systems.

## Rules for every screen in this build
- **One question per screen,** answered at the top. Today ends with **All clear** when nothing is waiting: no order
  possible, nothing to file, no attention items, no Game check differences.
- **Colour means action.** Red and amber only on things that need doing. Nothing that's fine gets a pill.
- **Open by default.** Today and Performance show their boards open, with the most important first. Systems may fold.
  No "Collapse all" on Today.
- **Every number has a comparison** where one exists (the scorecards this build; the route table in step 2).
- **Tap to open the detail:** an airline opens its page, a route its row in route profit (its own page comes in step 3),
  an aircraft its pop-up.
- **Phone first:** at 380 px nothing scrolls sideways, cards stack, and wide tables scroll inside their own box.

## Addresses
- `web/_redirects` (301):
  - `/planner/check` → `/planner/today`;
  - `/planner/review` and `/planner/review/*` → `/planner/performance` and `/planner/performance/:splat`;
  - `/planner/hubs` and `/planner/hubs/*` → `/planner/performance`.
- `/planner/check?day=…` opened Check's load report on a day. Flights by day keeps `?day=` on Performance.
- Every link inside the planner moves to the new addresses: needs attention items (`screen: "review"` → performance),
  the search box, Home's links, `itemRoute()`, and `screens.ts`'s list.

## What goes
- **The Hubs screen** (`app/planner/src/screens/hubs/`) and its place in the navigation. The planning library's `hubs`
  functions stay while anything else uses them: Routes' bank fit, the connections checks, the briefing and the scripts.
  `tests/planner_figures.mjs` keeps the library's Hubs figures if the functions stay; if a function goes, its figures go
  too, and the pull request says which.
- **Check and Review as screens.** Their boards move as above; their files go once nothing imports them.

## Decisions (Gitesh, 20 Oct: "go", on the recommendations)
1. **Today**, not Tonight: captures land at any hour (20 Oct's came in at 11:16).
2. **The order rotation is retired** (Check → Growth → "Next move for each airline", with **Log an order as** Big,
   Frequency or Feeder). It came before "route first, then airline" (manual §3, 19 Oct): each evening's proposal now
   picks by the route we most want to fly. The board and its buttons go; `growth_log` keeps its rows, but nothing new
   is written. The manual's rule was retired on 20 Oct, directly, as a rule change.
3. **The to-do board leaves Home** for Today.

## Saves
Every action that moves keeps its `planner_save()` call and its rows. The actions are:
- File into planner;
- dismiss and show again;
- to-dos;
- Game check's fixes and adds;
- Refitted to, Keep as is and Show again;
- Mark checked;
- manual entry;
- the fare plan's add and remove.

`tests/planner_saves_test.py` drives each one from its new screen. **Its recorded rows don't change**, except Log an
order as, which goes (decision 2).

## Checks
- `bash tests/run_all.sh` all green.
- Unit tests beside the new screens' `model.ts`:
  - Today's All clear (and each thing that stops it);
  - the capture line's words for complete, missing, short and broken;
  - the scorecards' week-on-week change, including an airline with no day a week ago;
  - each old address mapping to its new one.
- `tests/planner_next_test.py`: every screen opens at 1280 and 380 px with no errors and no sideways scroll; Today,
  Performance and Systems have their boards; `/planner/hubs`, `/planner/check` and `/planner/review/VS` land where the
  redirects say; there is no Hubs link.
- `tests/planner_figures.mjs`: no figure moves. Any that does is named in the pull request with why.
- Screenshots of Today, Performance (group and one airline) and Systems at both widths, on the pull request (the run's
  planner-screens artifact).

## Docs, in the same pull request
- `docs/planner-guide.md`: Today, Performance and Systems replace Check, Review and Hubs; Home shortened.
- `docs/architecture.md`: the Planner row (screens, sources, saves).
- `docs/playbook.md`: every "Check → …" and "Review → …" path (24 of them), and the evening steps on Today.
- `docs/operating-manual.md`: the paths it names (13).
- `tests/README.md` where it names screens.
- The Building chat updates the project copies after the merge.

## Not in this build
- The fare ladder, the route table's sparklines and the fare on each route (step 2).
- The route page (step 3).
- Competition analysis and rival alerts on Today (step 4; they need the world scans compared).
- Any change to a figure, a database function or a rule, apart from removing the order rotation (decision 2).

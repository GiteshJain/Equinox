# Worlds, groups and airlines as data — 9 Oct 2026 (decision #14)

**Decision:** how the new tables (#13) identify things. Either everything stays tied to Gander and these six airlines,
or every row carries its world and airline, airlines and their settings become data instead of code, and possibly
other players get accounts.
**Recommendation:** C.
- Every row says which world and which airline it belongs to.
- Airlines and their settings are rows, not code.
- Groups (ours, and rival players' for competitor analysis) are rows too, each with an owner, which is only Gitesh for
  now.

This turns adding Serbia or Kenya, or starting in another world, into adding rows. It leaves room for a version for
other players later without re-keying every table. It's part of the #13 design, not a separate build.

*Columns adapted for a non-game decision. All four options cost $0 in money.*

| Option | What you get | Extra effort in the #13 build | Risk | Easy to undo? |
|---|---|---|---|---|
| A. As now: Gander, six airlines, names as keys | Nothing new | None | A 7th airline means edits in about ten places across six files, and one missed spot is a silent bug (below). A second world means a rebuild | — |
| B. Airlines as data, Gander assumed | One airlines table with stable IDs and each airline's settings. A new airline is a row | Small: #13 already plans an airlines table | A second world still needs every table re-keyed later | Yes |
| **C. World and airline on every row, groups as data** | **B, plus a world on every row and groups (ours and rivals) with an owner. A new airline or a new world is rows. Competitors can be grouped by player** | **Small to medium: one more column on each table, and every read filters by world** | **Little. The planner shows one world at a time, so nothing changes on screen** | **Yes, while the design is on paper; costly once data is in** |
| D. C plus accounts for other players | The shared planner-only version: each player signs in and sees only their own worlds, groups and airlines | Large: per-account access rules on every table, invitations, a capture key per player, support | Other people's data to protect, and AirlineSim's permission needed first | Hard once others rely on it |

## Background
**What's written into the code today** (repository, 9 Oct):
- **The planner** keeps the airlines in five tables inside its code:
  - flight codes (`CODE_AL`);
  - the airport each airline's times are shown in (`CAP_HOME`);
  - main hubs (`MAIN_HUB`);
  - the aircraft each airline may buy (`BUY_TYPES`);
  - default links to their game pages (enterprises 112 to 114).
- **The website** has the six airlines' names, codes, colours, descriptions and order in its code, and a title saying
  "six airlines".
- **The capture script** lists the six airlines with their game IDs, and only runs on `gander.airlinesim.aero`.
- **The database:**
  - the capture recognises each airline by the start of its name ("pan am…", "kingfisher…");
  - a day's loads count as complete when 6 airlines are captured.
- **The weekly report** names the airlines 68 times (`scripts/report/build.py`); the world scanner has the Gander
  address three times.
- **Everything is keyed by display name:** "Pan American", "Pan American|JFK|ORD" for a route, "Pan American|1019" for
  a flight's load.

**The silent bug a 7th airline would hit under A:** the "complete when 6 airlines are captured" rule would mark a day
complete once any six of seven are in. The missing airline's flights would then count as 95% full, which is the
planner's rule for unlisted flights on a complete day.

**How the group can grow** (Gander's house rules, and the to-do board):
- up to 8 holdings per player, two of which must be in low-demand countries;
- six are taken, and the two low-demand ones (Serbia first, Kenya when Mumbai opens) are on the board for the
  31 Oct review;
- 3 subsidiaries are allowed per holding, though they don't work well with Gander's demand model.

**Worlds don't last for ever:**
- AirlineSim's handbook says short-term worlds run about 8 to 10 months and then reset; long-term worlds have no end
  date.
- Gander is an exclusive (private, paid) world, so it runs as long as its owners keep it going. There's no published
  end date.
- You moved from Limatambo to Gander in August.

Over the ten years you've talked about, a second world is likely. Under C it starts as new rows beside Gander, with the
history kept. Under A or B it means a rebuild or a separate copy.

**Rival groups:** the weekly report looks at competitors by market. In Gander each player runs up to eight airlines,
so the real competitor is often the player, not one airline. The world scanner already stores every airline by its
game ID. With groups as data, rival airlines can be grouped by player for the report and gander monthly.

**The shared version for other players** (raised 8 Oct, not decided; to weigh here and at #11): a planner-only version
for other players across several worlds, no website, no AI.
- **Under C,** it stays possible later. Every row already traces to a group with an owner, so adding accounts means
  adding sign-ins and access rules, not re-keying tables.
- **Doing it now (D)** brings other people's data to protect, a capture key per player, support, and AirlineSim's
  permission before opening it. None of the rebuild needs it.

## What C would mean in practice
- **Worlds:** one row each (Gander now), with the game's address.
- **Groups:** one row each, in a world, with an owner: equinox. (yours), plus rival players' groups as the scanner and
  reports need them.
- **Airlines:** one row each, with a stable ID, the game's ID in that world, its group, code, name, colours, hubs, the
  airport its times are shown in, and the aircraft it may buy. The website's descriptions also move out of the code.
- **Every other table** (aircraft, flights, routes, loads, plans, to-dos, capture tables) carries its world, and its
  airline where it has one.
- **Settings by world or airline,** not in code: connection times, banks, markets and fares, curfews, interline
  partners, growth-rule thresholds.
- **The capture** reads its list of airlines from the database for the world it's in, and matches them by game ID, not
  name. "Complete" means all of that world's airlines are in, not 6.
- **On screen:** nothing changes until there's a second world. Then a world switcher appears.

## Scenarios and the risk of waiting
- **Serbia or Kenya is added on 31 Oct:**
  - under C, once the #13 build is in: rows, plus a logo;
  - under A: about ten edits across six files, with the risk of missing one, as above.
  - If it comes before the #13 build lands, the old code needs those edits once, either way.
- **Gander closes, or you start in another world:** under C the planner, reports and history carry on. Under A or B
  it's a rebuild.
- **The shared version goes ahead:**
  - under C: accounts and access rules on top;
  - under A or B: a redesign first.
- **Waiting:** this only costs something once the #13 tables are built. Adding a world column to tables full of data
  is a migration of every table and every query, which is why it's decided now.

## What would change the recommendation
- **If you're sure you'll never play another world:** B, with a little less to build.
- **If you want the shared version for other players soon:** D. Better to design accounts in from the start than
  bolt them on.
- **If the two low-demand holdings are dropped** and the group stays at six: still C, for the world reason.

## Sources
- Repository, 9 Oct: `web/planner/index.html` (`CODE_AL`, `CAP_HOME`, `MAIN_HUB`, `BUY_TYPES`, game links),
  `web/assets/site.js` (`AL`, `ORDER`), `capture/capture_all.user.js`, `database/current/functions.sql`
  (`capture_ingest`, `apply_loads_from_capture`), `scripts/report/build.py`, `scripts/scanner/gscan.py`.
- `docs/decisions.md`: #11, and "Ideas to weigh" (the shared version).
- Planner to-do board: the low-demand holdings decision for 31 Oct.
- AirlineSim handbook, general FAQ (short-term worlds 8–10 months, long-term worlds no end date, exclusive worlds):
  https://handbook.airlinesim.aero/en/docs/faqs/general/
- AirlineSim forum, "How to know when a new server will be open?" (25 Jun 2026):
  https://forums.airlinesim.aero/t/how-to-know-when-a-new-server-will-be-open/27702

## Outcome
9 Oct 2026: Gitesh chose **C, without accounts**. The shared version for other players is dropped. He added two
points:
- worlds have different rules, so each world's rules are data;
- some worlds allow only a single airline, so nothing may assume several.

Both are in the decision log. No manual change yet: the rules about how data is kept change when the #13 build merges.

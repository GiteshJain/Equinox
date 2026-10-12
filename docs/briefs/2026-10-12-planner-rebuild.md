# The planner rebuilt as a proper app — 12 Oct 2026 (decision #18)

**Decision:**
1. Whether to rebuild the planner as a proper app now, and with which framework.
2. How it rolls out: screen by screen beside the old planner, or all at once.

**Recommendation:** C. React with TypeScript, built with Vite. The new planner grows at `/planner/next/` beside the
old one, one screen per pull request, each checked against the old screen's numbers on the same data. `/planner/`
switches over once every screen has passed and you've used it for a few days; then the adapter and the frozen rows
go. React because it's what a helper starting with a fresh memory writes most reliably. TypeScript because types
generated from the database turn a renamed column into a red check instead of a broken screen. $0 a month.

*Columns adapted for a non-game decision.*

| Option | What changes | Cost a month | Effort | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Keep the one file | Nothing. The adapter and the frozen rows stay | $0 | None now; every later change goes into a 584 KB file | Each opening downloads about 1.8 MB of data and each save sends 230 KB, both growing with the fleet. The adapter and its tests stay for good. A second world (#14) means changes in old code | Yes |
| B. Rebuild in plain JavaScript files, no framework | Screens in separate files, calculations split out. No build step; Cloudflare serves the files as now | $0 | About 12 pull requests, plus our own code for redrawing screens and holding state | Screens are still built as HTML text by hand, which is today's design. No type checks unless tooling is added | Yes: the old planner stays until you switch |
| **C. React + TypeScript (Vite)** | **Each screen its own file. Each screen loads only what it shows and saves only the row that changed. Types from the database checked on every pull request. Every screen works on a phone** | **$0** | **About 12 pull requests, one to two weeks** | **A rebuilt screen gets a number wrong. Caught by comparing it with the old screen on the same data, and the old planner stays live until you switch** | **Yes: switching back is one redirect line** |
| D. Svelte 5 + TypeScript (Vite) | As C, smaller (12 KB against 69 KB compressed for an empty app) and a little less code per screen | $0 | As C | As C, plus: Svelte changed how it's written in October 2024 and has about a thirtieth of React's downloads, so a fresh helper is likelier to mix old and new styles, with fewer ready-made parts to use | Yes |

## Background

### The planner today
From the repository (`main` at `fd6b213`, 12 Oct) and the live database (12 Oct).
- **One file of 584 KB** (187 KB compressed) and 3,488 lines:
  - about 295 KB of screen code;
  - 22 KB of calculations kept apart from the screens;
  - 80 KB of styles;
  - 95 KB of world-map outlines and 75 KB of airline logos, embedded as text. The website already keeps both as
    separate files (`web/assets/world.js`, `logos.js`).

  The Supabase library and three.js (the globe on Home) come from a CDN. `CLAUDE.md` tells every helper to search the
  file rather than read it.
- **Nine screens:** Home, Routes, Tails, Hubs, Check, Review (with a page per airline), Interline, Photos and Reference.
  Plus six pop-ups: plan card, route, aircraft, paste, file check, game check.
- **How it draws:** one shared state. After any change, the whole screen and any open pop-up are rebuilt as HTML text:
  about 400 HTML templates, and about 60 places in the code that redraw everything.
- **Where the money logic sits:** the cash forecast, which decides every order (manual §3), and the other money figures
  sit inside the screen code, not with the separate calculations. They can only be tested by opening screens. Where
  shared calculations should live is decision #19.
- **It still speaks the old format.** Since the switch-over (10 Oct), the adapter builds the old one-document format
  from the tables on every opening (`planner_state_get()`, 230 KB today) and splits it back on every save. Each save
  sends the whole 230 KB document, 0.3 seconds after every change, and the database works out which rows changed.
- **What each opening downloads,** whatever screen you open (live, 12 Oct, before compression):

  | Data | Size |
  |---|---|
  | 9 days of loads (`game_loads`) | 584 KB |
  | 8 days of flight money (`game_flight_pnl`) | 479 KB |
  | The route research (4,522 routes) | 456 KB |
  | The planner document | 230 KB |
  | The loads document | 52 KB |
  | Payments ahead | 22 KB |
  | **Total** | **about 1.8 MB** |

  Loads and flight money grow with every flight added. Supabase's free plan allows 5 GB of egress a month; ours isn't
  measured yet (the monthly usage check, manual §7).
- **Waiting for #18:**
  - dropping `planner_state`, `planner_loads` and the renamed old tables (design §3.13);
  - the check that keeps the old planner's own copies of the rule numbers equal to `settings` and `world_rules`
    (manual §1);
  - a world switcher, once there's a second world (#14);
  - an item's history on screen (#15's brief).

### What a framework does
A screen is described once, as "this is what it shows for this data". When the data changes, the framework updates
only the parts of the page that changed. Today the planner does that by hand, by rebuilding the screen. A framework
also brings ready-made parts (tables that sort and filter, charts, date handling) and a standard way to split the app
into small files.

### The candidates
npm downloads for 12 Sep to 11 Oct 2026; empty apps built with Vite on 12 Oct.

| Framework | Version | Downloads last month | Empty app, compressed | Notes |
|---|---|---|---|---|
| React | 19.3 | 816 million | 69 KB | The most used by far. The most ready-made parts. Its way of writing has been stable for years |
| Svelte | 5.57 | 28 million | 12 KB | Compiles to small plain JavaScript; reads closest to plain HTML. Version 5 (October 2024) changed how state is written |
| Vue | 3.5 | 74 million | not built | Sits between the two; no advantage here over either |
| Preact | 11.0 | 159 million, mostly inside other tools | not built | React's way of writing in 4 KB, usable without a build step. Not a separate option: with a build, C is the same with more support; without one, it's B with a helper library |
| Plain JavaScript | — | — | 0 KB | Option B |

**Why React over Svelte.** Claude writes all of this code, and each build goes to a helper starting with a fresh
memory (#26). What matters most is how reliably that helper writes the framework correctly the first time. React has
about thirty times Svelte's use, and its way of writing hasn't changed in years. Svelte rewrote its own in version 5,
and much of what's written about Svelte still uses the old way. Size doesn't decide it: React's extra 57 KB
compressed is small next to today's 187 KB page and the data each opening loads.

**TypeScript and the database.** Supabase generates TypeScript types from the database's tables and functions. The
rehearsal already starts a full local Supabase on last night's copy (#17). Every pull request can regenerate the types
there, and the new planner must still build with them. A renamed or dropped column then fails the check before merge,
instead of breaking a screen after it. This works with C and D, and with B only with extra tooling.

**The build step.** Vite turns the source files into the files Cloudflare serves; each empty app built in under a
second. Cloudflare Pages runs the build on every deploy (free plan: 500 builds a month, 20 minutes each). Every push
is a build already, docs-only commits included: 142 commits reached `main` from 8 to 12 Oct. That isn't part of this
decision. If the Cloudflare dashboard shows the count getting close, build watch paths can skip docs-only changes.

### How the rollout would go (C)
1. **The shell**, at `/planner/next/`:
   - sign-in, navigation, and look-only previews (#8);
   - reading the tables directly, with generated types;
   - saving single rows, logged as `planner` in the change log, with a clash check like today's;
   - its own automatic checks.
2. **The calculations** moved out of the screens: block times, connections, maintenance, the cash forecast and the
   growth signals, with tests against today's saved answers. #19 decides where they live.
3. **One screen per pull request:** Home, Routes, Tails, Hubs, Check, Review (two pull requests), then Interline,
   Photos and Reference together. Each shows the same numbers as the old screen on the test sample, and works on a
   phone.
4. **Your trial:** you use `/planner/next/` beside the old planner. When you're happy, `/planner/` switches to the new
   one, and the old one moves to `/planner/old/`.
5. **The clean-up:** the adapter, `planner_state`, `planner_loads`, the renamed old tables, `/planner/old/` and the
   rule-number cross-check are removed. Removals are a file you run in Supabase's SQL editor (manual §1).

About 12 to 13 pull requests in all. #13's nine took a day and a half; screens take longer to review, so plan on one to
two weeks.

**Both planners save to the same tables during the rebuild:** the old one through the adapter, the new one row by row.
The adapter's clash check already treats the other's changes as newer and reloads, as it does with Claude's changes
today.

**A rule for the rebuild, if you agree:** until the switch-over, the old planner gets fixes only, and new features go
into the new one, so nothing is built twice. It would go in the manual (§1).

## Scenarios and the risk of waiting
- **It goes well:** in one to two weeks, each screen is its own file a helper can read whole. An opening loads only
  that screen's data, a save sends one row, and the adapter is gone.
- **A rebuilt screen gets a number wrong** (the cash forecast, say): the comparison with the old screen fails on the
  pull request. If something slips past, the old planner is still at `/planner/` until you switch, and at
  `/planner/old/` until the clean-up. Going back is one redirect line.
- **React fights a screen** (the Hubs grid, the globe): it shows in the first two screen pull requests, when switching
  to Svelte costs little.
- **Waiting:** no cash cost. The costs are in work: every planner feature added meanwhile is built twice, the adapter
  and the frozen rows stay, and the downloads grow with the fleet. The shell could start as soon as #19 and #20 are
  decided, since both shape it.

## What would change the recommendation
- **If you want to read or tweak the planner's code yourself:** Svelte reads closer to plain HTML. Take D.
- **If speed on a weak phone connection matters most:** D is smaller, though the data dwarfs the difference.
- **If you'd rather have no build step or npm at all:** B, accepting hand-written redraws.
- **If you want no new planner features for months:** A, and revisit then.

## Sources
- Repository `GiteshJain/Equinox`, `main` at `fd6b213` (12 Oct): `web/planner/index.html`, `docs/planner-guide.md`,
  `docs/architecture.md`, `docs/design/2026-10-09-data-model.md` §3.13 and §11, `tests/README.md`, `CLAUDE.md`.
- Live database, 12 Oct: size 40 MB; `planner_state_get()` 230 KB; `planner_loads_get()` 52 KB; the route research
  456 KB (4,522 routes); the planner's own queries on `game_loads` (9 days) 584 KB, `game_flight_pnl` (8 days) 479 KB,
  `game_events` 22 KB; 102 aircraft (87 flying).
- npm downloads, 12 Sep to 11 Oct 2026: https://api.npmjs.org/downloads/point/last-month/react,vue,svelte,preact,lit,solid-js
- npm registry, latest versions on 12 Oct: React 19.3.0, Svelte 5.57.2, Vue 3.5.43, Preact 11.0.1, Vite 8.3.4,
  TypeScript 7.0.2.
- Empty apps built with Vite's React and Svelte TypeScript starters, 12 Oct: 69.3 KB and 12.4 KB of compressed
  JavaScript.
- Svelte 5's release (October 2024): https://svelte.dev/blog/svelte-5-is-alive
- Supabase, generating TypeScript types: https://supabase.com/docs/guides/api/rest/generating-types
- Cloudflare Pages limits (free: 500 builds a month, 20-minute builds): https://developers.cloudflare.com/pages/platform/limits/
- Cloudflare Pages build watch paths: https://developers.cloudflare.com/pages/configuration/build-watch-paths/

## Outcome
12 Oct 2026: Gitesh chose **C**, React with TypeScript. Recorded in `docs/decisions.md` and the manual's *Decided, not
yet built*. Same day: the game is paused until the new planner is done, with the evening capture the only game task,
so the old planner is frozen with no exceptions (manual §1). The proposed "fixes only" rule above is replaced by that.

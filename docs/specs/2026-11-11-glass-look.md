# Spec: the glass look on every planner screen

To-do 225. Why, the options and Gitesh's five decisions (11 Nov, Main chat, all option A) are in the brief,
`docs/briefs/2026-11-11-glass-look.md`; the settled look is in to-do 225's note. This spec doesn't repeat them. Read
`CLAUDE.md`, the map (`docs/architecture.md`, then `docs/map/planner.md`), manual §1 and the brief first.

## What it does, in one paragraph
Every planner screen, the landing page and the sign-in page get the glass look from the mock-up "Planner glass look":
a picture behind everything that follows the computer's clock (Day, Dusk, Night), cards of dark glass, tables on a
nearly solid panel, the ten screens as pills across the top and the six airlines as a rail on the left. It is built in
six pull requests. Until the last one, the glass look shows only to someone who turns it on in the account menu, and is
kept in that browser; everyone else sees today's light look, unchanged. The last pull request makes glass the only look
and removes the light one. Nothing the planner reads, saves, works out or links to changes.

## The settled look (to-do 225's note and the mock-up's files)
The mock-up: `project/Main.dc.html` (Home), `project/Performance.dc.html` (a table screen), `project/Landing.dc.html`.

| Part | Value |
|---|---|
| Typefaces | Unbounded for headings and big figures, Manrope for text (already loaded, `app/planner/index.html`) |
| Behind everything | `#0A1230`, with the period's picture over it, `background-size: cover`, centred, fixed to the window |
| Cards | `rgba(10,18,48,0.52)`; Day `0.66` (decision 2); blur 24 px with saturate 150%; 1 px border `rgba(255,255,255,0.18)`; corners 22 px; shadow `0 12px 40px rgba(4,7,24,.35), inset 0 1px 0 rgba(255,255,255,.14)` |
| Tables | on a panel `rgba(10,18,48,0.82)`, corners 22 px, no blur (brief, "Not his choice"); rows ruled `rgba(255,255,255,0.12)`; hover `rgba(255,255,255,0.07)`; figures in tabular numbers |
| Bars (the header's pills and buttons, the rail) | `rgba(10,18,48, card + 0.08)`: 0.60, Day 0.74; the same border, blur and shadow `0 10px 30px rgba(4,7,24,.3), inset 0 1px 0 rgba(255,255,255,.14)` |
| The page you're on | a white pill with night text (`#FFFFFF` / `#0A1230`) |
| Text | white; labels and lesser text `rgba(255,255,255,0.92)` (decision 2; the mock-up's 0.82–0.86 fail on Day) |
| Status pills | the mock-up's: ok `#B9F7DB` on `rgba(143,240,196,.20)`, warn `#FFE0A6` on `rgba(246,180,75,.24)`, bad `#FFD0DD` on `rgba(232,106,146,.28)`, plain `#FFFFFF` on `rgba(255,255,255,.18)`, each subject to the contrast check below |
| Lift | cards rise 4 px on hover (0.18 s); none when reduced motion is asked for |
| Periods (the computer's own clock) | Day 07:00–16:59, Dusk 17:00–19:59 and 05:00–06:59, Night 20:00–04:59 |
| Pictures | the mock-up's three (decision 3): Day 65,137 bytes, Dusk 82,138, Night 57,137 (JPEG; 204,412 in all, the mock-up's asset list, 11 Nov) |
| Globe on Home | as it is today (`screens/home/Hero.tsx`, `heroScene.ts`): no change to the globe or its colours |

## The five decisions, as built requirements
1. **A switch** in the account menu, kept in this browser (`localStorage`, as the Local/UTC choice is). Off unless turned
   on. Six pull requests; the sixth makes glass the only look and removes the switch.
2. **Day glass at 0.66** (cards; bars 0.74), Dusk and Night 0.52 (bars 0.60). Labels at 0.92 white. A new check measures
   text against the brightest part of each picture (step 1, *The checks*).
3. **The mock-up's three pictures**, one file each, in `app/planner/src/ui/look/`. Swapping one later is a file change.
4. **The rail picks the airline where a screen shows one airline at a time,** and that screen's own airline buttons go:
   Routes (`/routes/<code>`), Tails (`?airline=<code>`), Performance (`/performance/<code>`) and Competition
   (`/competition/<code>`). On Home, Today, Interline, Photos and Systems, "All" is lit and an airline opens its
   Performance page. **Reference: see question 1.** While the switch exists, a screen's own buttons are hidden under
   glass only, and removed from the code in step 6.
5. **The look only.** No table becomes a chart (that is to-do 232). The charts that exist are redrawn for dark glass, the
   chart kit's colours in step 1 and each screen's own colours in its step.

## How the look is put together (all steps)
- **Named colours by role.** Every colour a screen uses comes from a named colour that says what it colours (below).
  The light values are today's, exactly, so with the switch off nothing changes. The glass values are set once, in
  `:root[data-look="glass"]`, and the Day ones in `:root[data-look="glass"][data-period="day"]`. The existing names
  (`--ink`, `--paper` and the rest, 41 colours in `styles.css` lines 7–22) stay as the light palette until step 6.
  Don't reuse the existing `--glass` name (today's white map buttons).
- **Each step replaces its screens' typed-in colours with named ones,** in `styles.css` and in the code (charts' colours
  included), and lowers the typed-in colour ceiling (below) to its new count.
- **The look is two attributes on `<html>`:** `data-look="glass"` when the switch is on (none when off) and
  `data-period="day|dusk|night"`. Every glass rule hangs off `[data-look="glass"]`, so with the switch off no glass rule
  applies.

### The named colours (step 1 adds them; light = today's value)

| Name | Colours | Light | Glass (Dusk, Night) | Glass, Day |
|---|---|---|---|---|
| `--page-bg` | behind everything | `var(--porcelain)` | `#0A1230` (the picture over it) | same |
| `--card-bg` | cards, boards, tiles | `var(--paper)` | `rgba(10,18,48,.52)` | `rgba(10,18,48,.66)` |
| `--panel-bg` | table panels (and chart boards, question 3) | `var(--paper)` | `rgba(10,18,48,.82)` | same |
| `--bar-bg` | header pills and buttons, the rail, menus | `var(--night)` | `rgba(10,18,48,.60)` | `rgba(10,18,48,.74)` |
| `--card-edge` | card and bar borders | `var(--line)` | `rgba(255,255,255,.18)` | same |
| `--card-shadow` | card shadow | `var(--shadow)` | the settled shadow above | same |
| `--card-blur` | `backdrop-filter` on cards and bars | `none` | `blur(24px) saturate(150%)` | same |
| `--text` | text | `var(--ink)` | `#FFFFFF` | same |
| `--text-2` | lesser text, labels | `var(--muted)` | `rgba(255,255,255,.92)` | same |
| `--text-3` | the faintest text | `var(--faint)` | `rgba(255,255,255,.92)` | same |
| `--rule` | table and board rules | `var(--line)` | `rgba(255,255,255,.12)` | same |
| `--rule-2` | lighter rules | `var(--line-2)` | `rgba(255,255,255,.08)` | same |
| `--row-hover` | row hover, light fills | `var(--fill)` | `rgba(255,255,255,.07)` | same |
| `--row-group` | group rows | `var(--group)` | `rgba(255,255,255,.05)` | same |
| `--sel-bg` | a selected row | `var(--sel)` | `rgba(255,255,255,.14)` | same |
| `--link` | links | `var(--violet)` | `#FFFFFF`, underlined | same |
| `--on-bg`, `--on-text` | the page you're on, the chosen button | today's active nav colours | `#FFFFFF`, `#0A1230` | same |
| `--ok-text`, `--ok-fill` | ok pills and marks | `var(--ok)`, `var(--ok-soft)` | `#B9F7DB`, `rgba(143,240,196,.20)` | the check decides |
| `--warn-text`, `--warn-fill` | warn | `var(--warn)`, `var(--warn-soft)` | `#FFE0A6`, `rgba(246,180,75,.24)` | the check decides |
| `--bad-text`, `--bad-fill` | bad | `var(--bad)`, `var(--bad-soft)` | `#FFD0DD`, `rgba(232,106,146,.28)` | the check decides |
| `--mute-text`, `--mute-fill` | plain pills | `var(--muted)`, `var(--mute-soft)` | `#FFFFFF`, `rgba(255,255,255,.18)` | the check decides |
| `--focus` | the focus ring | `var(--amber)` | `var(--amber)` | same |
| `--chart-1` … `--chart-8` | chart series | `layout.ts`'s `SERIES`, in order | a light set made for dark glass, each 3:1 against its board | the check decides |
| `--chart-ok`, `-warn`, `-bad`, `-mute`, `-ink` | chart tones | `layout.ts`'s `TONE` | light tones, each 3:1 | the check decides |
| `--chart-axis`, `--chart-grid` | axis text, grid lines | today's | `--text-2`, `--rule` | same |

"The check decides": measured 11 Nov, the mock-up's pill colours on 0.66 glass over pure white are 3.5–4.0:1, under
4.5. Whether that fails depends on how bright the real Day picture is behind the cards, which the contrast check
measures. Where a pair fails, the builder makes the text lighter (towards white) or the pill's fill stronger until it
passes, and says which in the pull request. White text on 0.66 over pure white is 6.0:1 and passes on any picture.

## Step 1: the frame, Home, the landing page and sign-in (the switch, off by default)
The first preview. After it merges, Gitesh can turn the glass look on for himself on live. Under glass, the screens not
yet done show the glass frame with their own parts partly restyled (the shared classes change); that's expected and only
visible with the switch on.

### Files
New, in `app/planner/src/ui/look/`:
- `look.ts`: the switch and the period. `LOOK_STORAGE_KEY` (`"equinox-planner-look"`, added to `data/config.ts` beside
  `TIME_MODE_STORAGE_KEY`); `readLook()` (`"glass"` only when the stored value is exactly `"glass"`; anything else, nothing
  stored or storage blocked is off); `setLook(on)` (writes or removes the key, sets or removes `data-look` on `<html>`,
  tells listeners; storage blocked means for this page only); `useLook()` (as `useTimeMode()`, with
  `useSyncExternalStore`); `periodOf(hour)` (a pure function on the computer's local hour: 7–16 day, 17–19 and 5–6 dusk,
  20–4 night).
- `look.test.ts`: the boundaries (04:59 night, 05:00 dusk, 06:59 dusk, 07:00 day, 16:59 day, 17:00 dusk, 19:59 dusk,
  20:00 night); the stored value (missing, `"glass"`, `"GLASS"`, `"1"`, storage that throws); `setLook` writes, removes
  and sets the attribute.
- `Backdrop.tsx`: the fixed layer behind everything (`position: fixed; inset: 0; z-index: -1`), shown only under
  glass. It takes the moment from `useNow()` (so the screen checks' frozen clock decides the period) and sets
  `data-period` on `<html>` each minute.
- `rail.ts` and `rail.test.ts`: `railTarget(pathname, search, code | "all")`, the address the rail goes to, and
  `railCurrent(pathname, search)`, which button is lit. Per decision 4: Performance and Competition keep the rest of the
  address where it still makes sense (a route page `/performance/FR/AMS-BCN` with VS picked goes to `/performance/VS`);
  Routes keeps its filters but not the pair; Tails goes to `/tails?airline=<code>` (no `airline` for the first airline,
  as Tails does); on Routes and Tails "All" is shown but not clickable (`aria-disabled`, title "Routes shows one airline
  at a time"), since they have no all-airline view; on Home, Today, Interline, Photos and Systems (and Reference until
  question 1 is answered) "All" is lit and an airline goes to `/performance/<code>`. Tests for each screen and both kinds
  of button.
- `AirlineRail.tsx`: All and the six airlines from `useOurAirlines()`, in their order; 44 px round buttons with the
  airline's code, `aria-label` its name, `aria-current` on the lit one; a vertical bar on the left, sticky under the
  header, from 761 px wide; a row above the screen at 760 px and under. Rendered only when the look is glass.
- `backdrop-day.jpg`, `backdrop-dusk.jpg`, `backdrop-night.jpg`: the mock-up's three pictures, unchanged. Their sha256:
  Day `4bf07ea3dc49d4d18488a44df84f8b929e67e9f9fee4a203db0d3efffa13c105`, Dusk
  `16027a1107ad3f155820a6222d02c991a5ef554774ba61ede706e97d3b6d82e4`, Night
  `e6b3262dfba4ce1a6fd4a1d066dc8bec2978a9a963cf623785d0913280725abb`. **The Main chat supplies them** (see *Before the
  build*). Referenced from `styles.css` with `url()`, so Vite fingerprints them into `web/app/assets/`.

Changed:
- `src/main.tsx`: sets `data-look` from `readLook()` on `<html>` before the first render, so the sign-in page and the
  landing page open in the right look with no flash of the other.
- `src/App.tsx`: `<Backdrop />` in `Root` (behind sign-in, the landing page and the screens); in `Opened`, the rail and
  the screen side by side (`<div className="eq-body">`), the rail only under glass.
- `src/ui/Header.tsx`: in the account menu, a button after Times in UTC/Local, like it: "Glass look" with "On"/"Off"
  (`id="lookmode"`, `data-look-mode="glass|light"`), calling `setLook`. Under glass the bar shows all ten screens as
  pills, More's menu dissolving into the row (the same `NavLink`s, so every `data-screen-link` stays once); the search
  box, the UTC clock, the save state, the Local/UTC switch, Website and Sign out all stay. At 1280 px the bar may take two
  rows (brand, search and buttons; then the ten pills); on a phone the menu button and its menu stay, the menu in glass.
  The twilight line is hidden under glass. With the switch off the header is exactly as today.
- `src/ui/styles.css`: the named colours (both looks) at the top; the glass rules for the page, the header, the rail,
  the shared classes (cards, boards, fold boards, pills, tables, buttons, form fields, menus, the attention list,
  messages, error boxes, the preview notice, the stale-figures line), Home, the landing page and sign-in, all under
  `[data-look="glass"]`; the frame's, Home's, the landing page's and sign-in's typed-in colours replaced by named ones.
- `src/ui/charts/layout.ts` and `Charts.tsx`: `TONE` and `SERIES` read from the named colours (`--chart-*`), so every
  chart is drawn in the light set when off and the glass set when on. The colours go into `style` (CSS custom
  properties don't work in SVG presentation attributes).
- Home: `screens/home/Home.tsx`, `AirlineCards.tsx`, `NetworkMap.tsx` (the map's buttons, key and tip on `--bar-bg`
  under glass; its airline colours stay the airlines' own) and `Hero.tsx` only as far as its frame (corners, border):
  needs attention's cards as the mock-up's (glass cards, status pill, heading, detail, a white button), the network
  map in a glass card, the airline cards as the mock-up's (code, name, pill, six figures, the ground line, a button to
  Performance). The airline cards are Performance's scorecards, so these change on Performance too under glass.
- `src/ui/landing/Landing.tsx` (and only its styles, as its note says): the brand top left; the line and the detail in
  one glass card in the middle (the mock-up's: 600 px wide, corners 28 px, padding 36 px, heading in Unbounded 30 px).
  **Not taken from the mock-up:** its "Continue to Home" link (Gitesh, 11 Nov: no way past the landing page but its time
  limits, `Landing.tsx`'s note) and its three-step list (new content; question 2). Today's words and when it shows are
  unchanged (`model.ts`).
- `src/ui/SignIn.tsx`'s styles: the form in one glass card on the backdrop, as the landing page.

### What the pull request must show
- The preview, opened with the switch off: every screen as today.
- The preview with the switch on (account menu → Glass look → On): the frame, the rail, Home, the landing page (reload
  to see it) and sign-in (sign out to see it) in the glass look, at the period of the computer's clock; screenshots of
  Home at Day, Dusk and Night at 1280 px and at 380 px (from the rehearsal's screenshots, or forced with a test-only
  `?period=` that exists only in the unit tests, not in the build).
- *Outside the spec*, the pictures' sizes as served (the built files in `web/app/assets/`) and whether any was
  re-compressed (it shouldn't be), and the Day picture's brightest blurred patch as the contrast check found it.

### The checks
1. **The usual checks,** `bash tests/run_all.sh`: type check, lint, unit tests (with `look.test.ts` and `rail.test.ts`),
   build. The screens' figures (`planner_figures.mjs`) and the saves (`planner_saves_test.py`) don't move: no saved
   answer changes.
2. **New: text against the glass,** `tests/glass_contrast_test.py`, in `run_all.sh`. With Pillow (installed with
   matplotlib, already in `checks.yml`), for each picture: scaled to cover 1280 × 900 and to 380 × 800, blurred as the
   glass does (Gaussian, 24 px), its brightest pixel; then each glass surface for that picture's period (`--card-bg`,
   `--bar-bg`, `--panel-bg`, read from `styles.css`'s glass blocks) laid over that pixel, and every text named colour
   on it at 4.5:1 or more (`--text`, `--text-2`, `--text-3`, `--link`, each status text over its fill over the surface,
   `--on-text` on `--on-bg`) and every chart colour at 3:1 or more on the surface charts sit on. It names any pair that
   fails, with its ratio, picture and surface. It also fails if a period has no picture or a glass block is missing.
3. **New: typed-in colours don't grow,** `tests/look_colours_test.py`, in `run_all.sh`. It counts colour values typed in
   directly (hex `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, and `rgb(`/`rgba(` with numbers) in `app/planner/src/ui/styles.css`
   outside the `:root` blocks of named colours, and in `app/planner/src/**/*.ts(x)` outside tests, and fails if either
   count is over its ceiling, saved in the test with the date. **Starting counts, measured at `a0be3d4`: 413 in the
   stylesheet, 113 in the code (19 files).** Step 1 sets the ceilings to its own counts, which must be lower, and says
   both in the pull request.
4. **The rehearsal's screen checks, with the switch off and on** (`tests/planner_next_test.py`, `screens()`): the
   existing run at 1280, 380, 1700 and 2000 px is unchanged (the switch off: nothing in storage). Then a second run at
   1280 and 380 px only with the switch on (`Planner.open(init=...)` sets `localStorage["equinox-planner-look"] =
   "glass"` before the page loads): every screen, the airline's Performance and Competition pages and the two route
   pages, ready, no errors, no sideways scroll, the charts readable (the existing `charts_readable_and_open`); plus
   `<html data-look="glass">`, `data-period` equal to `periodOf` of the frozen moment's hour in the browser's time zone,
   the rail present with seven buttons and the right one lit (All on Home; the airline on its Performance page), every
   screen's link in the header once. Screenshots named `…-glass` in `PLANNER_SCREENS_DIR`. The rehearsal takes about
   15–30 minutes (limit 45); the glass run adds two browser passes, estimated 3–6 minutes. Say the measured time in the
   pull request. `planner_saves_test.py` runs with the switch off only (saves don't depend on the look).

### Database
**None.** The switch is kept in the browser, as the Local/UTC choice is, and the pictures are files in the planner's
build. No migration, no grants, no change to live.

### Documents (in the same pull request)
- `docs/planner-guide.md`: the Glass look switch (where it is, that it's kept in this browser, that it's being built and
  which screens are done), the backdrop by the clock, the rail.
- `docs/map/planner.md`: a dated note (11 Nov or the build's date): the look's two attributes, `ui/look/`, the named
  colours, the switch's key, the two new checks.
- `tests/README.md`: the two new checks in the table, and the screen checks' glass run.
- Manual §1, *Automatic checks*: the two new checks and the glass run named in the list (wording proposed in the pull
  request; the Main chat logs it in `docs/rule-history.md` and updates the project copy).
- The README: no change unless it lists the planner's checks.

### Size
About 20 files: 8 new in `ui/look/` (3 of them pictures), `main.tsx`, `App.tsx`, `Header.tsx`, `config.ts`, `styles.css`,
the chart kit's two files, Home's four, `Landing.tsx` and `SignIn.tsx` (styles only, if their class names suffice), two
new tests, `planner_next_test.py`, `run_all.sh` and four documents. Estimated half a day to a day for a build worker,
plus the rehearsal.

### Before the build
- **The pictures.** The mock-up's assets can't be read by the tools a worker has (`read_asset` refuses assets of an
  artifact made from a type; the three are not on this machine). Whoever made the mock-up, or Gitesh, needs to save the
  three files from it; the Main chat checks them against the sha256 above and gives them to the step 1 worker.
- Questions 1 and 3 below (question 1 only touches step 5; question 3 touches Home's chart boards in step 1).

## Steps 2 to 6
Each step: its screens' rules under `[data-look="glass"]`, their typed-in colours replaced by named ones (stylesheet and
code), their own chart colours on the named chart colours, the typed-in ceiling lowered to the new counts, the planner
guide's list of done screens updated, and the map file's dated note. Each pull request shows the switch-off preview
unchanged and the switch-on screenshots of its screens at 1280 and 380 px, each period for at least one of them. The
checks: as step 1's (both screen-check runs, the contrast check, the colour count); no saved answer moves.

| Step | Screens | Files (planner `src/`, and `styles.css` sections by line at `a0be3d4`) | Risks |
|---|---|---|---|
| 2 | Today, Tails | `screens/today/*` (`OrdersChart.tsx`, 2 colours), `screens/tails/*` (`TailsChart.tsx`, 2); styles 616–666, 876–893, 1137–1244, 1806–1952, and Check's 667–730 that they still use. Tails' own airline buttons (`Tails.tsx` around line 305) hidden under glass | the to-do board's fields and the plan card's form on dark glass; Tails' week strip and plan-card marks use status colours |
| 3 | Routes, Performance | `screens/routes/*` (`Routes.tsx` buttons around line 317), `screens/performance/*` (16 tables; `model.ts` 10 colours, `Charts.tsx` 9, `PerfCharts.tsx` 4, `charts.ts` 3, `RoutePage.tsx`, `RouteStory.tsx`, `FareLadder.tsx`); styles 418–615, 731–778, 894–914, 947–1016, 1245–1377, 1452–1585. Both screens' own airline buttons hidden under glass | the largest step (about 3,300 lines of screen code): if its diff goes well past a normal step, the Main chat asks Gitesh before splitting it, since he decided on six; the fare ladder's and income/cost charts' colour sets; the route page's since-launch chart |
| 4 | Competition, Interline | `screens/competition/*` (`CompCharts.tsx` 2, `charts.ts` 4, `Competition.tsx` 1; own buttons around line 119), `screens/interline/*`; styles 796–804, 915–946, 1586–1752 | rivals' colours on the share bars must stay apart from ours on dark glass |
| 5 | Photos, Reference, Systems | `screens/photos/*`, `screens/reference/*` (8 tables of editable boxes), `screens/systems/*` (`SystemsCharts.tsx`, `charts.ts`, `ManualEntry.tsx`); styles 805–854, 870–875, 1378–1451, 1753–1805, 1953–1998. Reference's rail per question 1 | many form fields (Reference's boxes, manual entry's cash boxes, photo uploads) on dark glass; the Systems board's marks |
| 6 | Glass for everyone | the switch and `LOOK_STORAGE_KEY` removed (`data-look="glass"` always set; a stored key left behind is harmless); the light values and the old names (`--ink`, `--paper` …) removed; the screens' own airline buttons and More's menu removed from the code; the twilight line gone; the ceilings to their final counts: 0 in the stylesheet outside the named colours, and in the code only the globe's (`heroScene.ts`, `map.ts`), listed in the test; the screen checks back to one run (glass) at all four widths; the rail and header tests updated; the guide and map without the switch | live changes for everyone at merge; reverting this one pull request brings the switch back |

## Questions for Gitesh (the spec doesn't settle these)
1. **Reference and the rail.** Decision 4 lists Reference among the screens where the rail picks the airline, but
   Reference shows all six airlines at once and has no airline buttons or one-airline view; the brief was wrong on this.
   Either Reference is treated like Home (All lit, an airline opens its Performance page: no new filtering, the reason
   for 4A), or Reference gets a new one-airline view. This touches step 5 only; step 1 treats Reference like Home until
   he answers.
2. **The landing page's three-step list.** The mock-up shows the landing page with a progress bar and three steps
   (capture read, figures worked out, loaded into this browser). Today's landing page has one line and a detail line.
   Step 1 draws today's content in glass. Does he want the steps as well (a small change to the landing model, its own
   pull request after step 1)?
3. **Charts on a Day picture.** On 0.66 glass over a white patch of sky, chart colours light enough to keep the six
   airlines and the status tones apart reach about 2.1–3.7:1, under the 3:1 graphics need (measured 11 Nov with a
   pastel set). The spec's default puts boards whose main content is a chart on the 0.82 panel, as tables are; most
   boards on Today, Performance and Systems are charts since 30 Oct, so those screens would show less glass. The
   alternative keeps them on 0.66 glass with paler, closer chart colours. The contrast check decides whether it bites on
   the real Day picture, so step 1's measurement may make this moot.

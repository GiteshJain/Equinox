# The planner's new look, step 1: the foundation (22 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 22 Oct). This is step 1: the website's look
carried into the planner on every screen. Layouts stay as they are; Today, Routes and Systems get their own builds later.
The mockups Gitesh approved ("right direction") are summarised below; build to this spec, not to pixel-copy them.

## The look, as tokens (in `app/planner/src/ui/styles.css`, `:root`)
Take the website's values (`web/assets/site.css`), the same names where they exist:
- Colours: `--night #0A1230`, `--night-2 #121C44`, `--night-3 #1B2759`, `--violet #4B3BA8`, `--rose #E86A92`,
  `--amber #F6B44B`, `--porcelain #EEF1F6` (page ground), `--paper #FFFFFF` (cards), `--ink #0E1630`, `--muted #5D6785`,
  `--faint #8C94AD`, `--line rgba(14,22,48,.10)`, `--twilight` (the website's gradient). Keep the planner's status
  colours (`--ok`, `--warn`, `--bad` and their `-soft`) and the airline colours as they are. Every colour pair must keep
  text contrast at 4.5:1 or better.
- Type: display `Unbounded` (500, letter-spacing about -0.03em), text `Manrope`. A small scale, used everywhere:
  `--t-display 56px` (a screen's title; 40px under 640px wide), `--t-h2 32px` (section heads; 24px on phones),
  `--t-h3 18px` (card heads, Manrope 800), `--t-body 15px`, `--t-small 13px`. Nothing smaller than 13px: replace the
  11–12.5px rules. Big numbers on cards in Unbounded.
- Shape and space: `--r-lg 24px` (cards), `--r-md 16px` (inner blocks), pills fully round; card padding 28–32px (20px
  on phones); 20px between cards; 48–56px between sections; content max width 1440px with 40px side padding (16px on
  phones).
- Buttons and pills: at least 44px tall to tap, 14–15px text. Primary = night with white text; the one action to take
  now = amber with night text; secondary = porcelain. Selected tab or pill = night.

## The shell (`App.tsx`, `ui/Header.tsx`, `ui/Clocks.tsx`)
- **One slim top bar on night, 64px:** the wordmark "equinox." (Unbounded, amber full stop) with "planner" in faint;
  the nav: Home, Today, Routes, Tails, Performance, Competition, and **More** (a menu with every other screen:
  Interline, Reference, Photos, Systems, and any others the router has); search on the right; one round account
  button opening a menu with the save state ("saved", "Local"), the Website link and Sign out. Under the bar, the
  website's twilight gradient as a 2px line. On phones the nav goes into a menu button; nothing scrolls sideways.
- **The clocks leave the top of every screen.** A small clock button in the bar shows UTC now; it opens a panel with
  the same game clocks (`Clocks`, the same data and order). The hidden band (`Band`) can go.
- **No dark banner on each screen.** The page head (`.vh` and each screen's banner) becomes: a small uppercase line
  in muted (the screen's context, as now), then the title in display type on the porcelain ground, then the screen's
  existing one-line description in muted body text. Home keeps its globe hero as it is, restyled to the tokens.

## Every screen
Apply the tokens through the shared classes (cards, boards, pills, tables, buttons, the attention list) rather than
per screen. Tables: 15px rows, 13px uppercase muted heads, hairline row borders. Section heads in Unbounded at
`--t-h2`. Do not change what any screen shows, its order, its numbers or its saves.

## Checks
- `bash tests/run_all.sh` green; the database rehearsal green: every screen opens at 1280 and 380 px with no errors
  and no sideways scroll, and every save still works. The screens' figures tests must not move (no numbers change).
- Update `docs/planner-guide.md` where it describes the header, the clocks or the banners, and the README if it shows
  them. The pull request includes before and after screenshots of Home, Today and Routes at 1280 and 380 px (from the
  rehearsal's planner-screens artifact).

## Not in this build
New layouts for Today, Routes or Systems (steps 2 to 4); any change to data, figures or saves.

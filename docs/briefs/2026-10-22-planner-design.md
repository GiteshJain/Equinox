# The planner's look — 22 Oct 2026

**Decision:** how to bring the planner up to the website's standard of design.
**Recommendation:** C, mockups first. Three key screens are designed as pictures you can judge and mark up, and nothing
is built until you've picked a direction. It costs about an hour and rules nothing out.

The money columns of the usual table don't apply here (no game cash or routes move), so this table compares effort and
what you get instead.

| Option | What changes | Time to build | Risk | Opportunity cost | Easy to undo? |
|---|---|---|---|---|---|
| A. New foundation, applied everywhere | One type scale, spacing and colour set shared with the website; a calmer top bar; every screen restyled, same layouts | About half a day: one build, every screen's checks | Every screen changes at once; the layouts that are the real problem (long lists, stacked boxes) stay | Building time that would go to other planner work | Yes: revert one pull request |
| B. A, plus the worst layouts reworked | A, then Today, Routes and Systems rebuilt to be shorter (a list beside its detail, summaries first, the rest folded away) | About a day and a half: A plus three builds | Bigger change to screens you use daily; habits change | As A, three times over | Yes, screen by screen |
| **C. Mockups first, then A or B** | **Home, Today and Routes designed as pictures in the website's style; you mark them up; the build follows the one you pick** | **About an hour before any build** | **Low: nothing live changes until you choose** | **An hour** | **Nothing to undo** |
| D. Leave it | Nothing | None | The planner stays the tool you don't enjoy opening | None | — |

## Background
Sources: the database rehearsal's screenshots of every planner screen (pull request #70, 22 Oct, at 1280 px), the live
website (22 Oct) and `app/planner/src/ui/styles.css`.

- **Same fonts, used differently.** Both load Manrope and the display font Unbounded. The website sets its headings in
  Unbounded at 60–90 px with plenty of room. The planner uses Unbounded only in the dark banner at the top of each
  screen; everything else is Manrope at 11–14 px. The stylesheet has 17 different text sizes, and 46 rules use 12.5 px.
- **The top of every screen is crowded.** The nav, search, "saved", "Local", sign out and Website share one bar, with a
  row of seven world clocks under it. Then each screen opens with a large dark banner that mostly repeats the screen's
  name.
- **Everything is a white box on grey, stacked.** Today is 5,012 px tall, Systems 11,531 px and Routes 19,772 px: Routes
  shows every route of an airline in one list before you pick one.
- **Lots of small pills and chips.** Airline filters, bases, stars and markets are all rows of small pills, so nothing
  stands out as the thing to look at first.
- **How it got here.** The website was designed as one piece. The planner was rebuilt screen by screen from 12 to 21 Oct
  (decision #18), each screen matching the old planner's numbers first; its look grew one rule at a time in a
  1,009-line stylesheet.

## Scenarios and the risk of waiting
- **C goes well:** you see the direction before anything changes and the build is aimed at it. **Goes badly:** none of
  the three mockups is right, and another round costs another hour.
- **A goes well:** the planner looks of a piece with the website within a day. **Goes badly:** it looks nicer but still
  long and busy, because the layouts are the bigger part of the problem.
- **B goes well:** the daily screens become short and clear. **Goes badly:** a familiar screen moves under you in a busy
  week; mitigated by doing one screen per pull request.
- **Waiting** costs nothing in the game. Each new screen or feature built on the current look adds to what has to be
  restyled later.

## What would change the recommendation
- If you already know you want the website's look exactly, carried over, A can start straight away without mockups.
- If one screen bothers you far more than the rest, start B with that screen alone.

## Outcome
22 Oct 2026, Gitesh: **C**. Mockups of Home, Today and Routes first; the build (A or B) follows the direction he picks.
22 Oct 2026, after the mockups ("right direction"), Gitesh: **B, in steps**. First the foundation on every screen (option A), then Today, Routes and Systems rebuilt one at a time, each its own pull request. Mockups: the "equinox. planner redesign" canvas.

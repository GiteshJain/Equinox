# The glass look on every planner screen — 11 Nov 2026

Main chat, to-do 225. Gitesh decided on 11 Nov (Audit chat) that the planner gets the glass look from the mock-up
"Planner glass look", on every screen: "i want it to be coherent so i think we need it everywhere?" The look itself is
settled (to-do 225's note, items 1–8: colours, typefaces, the glass, tables at 82%, the ten pills, the airline rail, the
backdrop by the clock, the globe kept, the landing page included). This brief covers only what is still open. Five
decisions, one at a time; the first is the one the others hang on.

The money columns of the usual table don't apply: no game cash, routes or growth move. The tables compare effort, risk,
what he sees and when, and how easy each is to undo.

---

## Decision 1: how the new look reaches the live planner

**Decision:** while the screens are restyled one batch at a time, what does the live planner look like in between?
**Recommendation: A, a switch.** Every step merges small and safe, but the live planner keeps today's look until the
last step. Gitesh can turn the glass look on for himself (in the account menu) at any time, on his own computer and
real data, which is the only true test of speed. Turning it off undoes it at once.

| | A. Behind a switch, on for all at the end | B. Each step goes live as it merges | C. One long preview, merged at the end |
|---|---|---|---|
| Pull requests | 6: frame + Home + landing page; Today + Tails; Routes + Performance; Competition + Interline; Photos + Reference + Systems; switch on for good and the old look removed | 5 (the same, without the last) | 5, stacked on one branch, merged together |
| Time | about 2–4 days of building, plus his reviews (the light look's first five steps were built and live in one day, 22 Oct) | the same | the same, plus the merge at the end |
| What he sees, and when | the first preview after step 1 (frame, Home, landing page); the switch on live from step 1's merge; everyone on glass after step 6 | the same preview; live is glass frame with light screens inside for the 2–4 days | previews only, until the end; nothing on live until it is all done |
| Risk | two looks live side by side in the stylesheet for a few days; the switch is one more thing to test (the screen checks run with it on and off) | the planner looks half-done on live, which is what "coherent" was meant to avoid | a branch open for days in the file every planner build touches; any other planner build in that time means conflicts. Previews don't save, so he can't use it for real |
| Easy to undo? | yes, at once: the switch | revert each pull request | revert one large merge |

## Decision 2: keeping text readable on the Day backdrop

**Decision:** the settled glass (night at 52%) is too thin over a bright Day picture. What gives?
**Recommendation: A, darker glass on Day only.** Cards go from 52% to about 66% between 07:00 and 17:00 and stay at 52%
at Dusk and Night. The Day picture stays bright between the cards; the cards are a little less see-through by day.

The rule is 4.5:1 for text on every backdrop (to-do 225). Measured on the mock-up's settings, white text on 52% glass
over a white or near-white patch of sky is **3.7:1**, and the small grey-white labels (84% white) are **3.1:1**. Both
fail. Over the Dusk and Night pictures they pass easily (above 10:1). Full figures under Background.

| | A. Darker glass by day (about 66%) | B. A dim veil over the Day picture (cards stay 52%) | C. Keep 52%; choose a Day picture with no pale areas |
|---|---|---|---|
| Text on white sky | 6.0:1; labels 4.8:1 | about the same (6.0:1; labels 4.8:1 with a 30% veil) | depends on the picture; fails wherever sky shows pale behind a card |
| How Day looks | bright picture, slightly thicker cards | the whole picture dimmed, as late afternoon | as the mock-up |
| Effort | none extra: one value | none extra: one layer | none in code, but every new Day picture has to be checked |
| Risk | low | Day looks less like day | a later picture or a wide screen that shows more sky fails the rule |
| Easy to undo? | yes, one value | yes, one value | yes |

Under any option the small labels go from 84% to about 92% white (one sensible way, below), and an automatic check
measures text against the brightest part of each picture behind the cards, so a new picture can't break the rule
unnoticed.

## Decision 3: the backdrop pictures

**Decision:** which pictures sit behind the glass. The note says the mock-up's three are drawn stand-ins and the real
ones are his choice.
**Recommendation: A, the mock-up's three for now.** He has seen them and liked the look ("Everything else looks
awesome"). Each is one file, so swapping in others later is a small change.

| | A. The mock-up's three drawn pictures | B. Three photographs he chooses | C. No pictures: drawn skies made in the stylesheet |
|---|---|---|---|
| Effort | none extra | he picks three; any free-licensed photo or one of the website's destination photos (the Photos screen holds them) | a little more design work in step 1 |
| What it looks like | as the mock-up | real places; busier behind the cards, so check 2's measure matters more | smooth colour, no detail; the glass shows less |
| Download | one picture at a time, kept by the browser after the first load (estimated 150–400 KB each; measured in step 1) | the same | nothing |
| Easy to undo? | yes: one file each | yes | yes |

## Decision 4: what the airline rail does

**Decision:** the rail of six airlines on the left is new. What happens when he clicks one?
**Recommendation: A.** On the five screens that already show one airline at a time (Routes, Tails, Performance,
Competition, Reference), the rail picks the airline, and those screens' own airline buttons go. On the five screens that
show all six (Home, Today, Interline, Photos, Systems), "All" is lit and clicking an airline opens its Performance page.
This is what the mock-up shows (on Performance, the rail has Ryanair picked), and it adds no new filtering.

| | A. Picks the airline where a screen has one | B. One airline for the whole planner | C. A shortcut to each airline's Performance page |
|---|---|---|---|
| Effort | inside step 1 and each screen's step | 1–2 more pull requests: Home, Today, Interline, Photos and Systems each learn to show one airline | inside step 1 |
| What changes | one place to pick an airline instead of a row of buttons on each screen | pick Ryanair once and every screen, Today's to-dos included, shows only Ryanair until he picks "All" | nothing else; the screens keep their own buttons, so there are two ways to pick on those screens |
| Risk | low; addresses stay as they are (/planner/performance/FR) | a filter left on hides things (a to-do for another airline) | two pickers that can disagree |
| Easy to undo? | yes | yes | yes |

## Decision 5: tables into charts in the same build?

**Decision:** his standing preference is charts instead of text or tables wherever possible. This build touches every
screen. Does it also turn tables into charts?
**Recommendation: A, not in this build.** The restyle changes how each screen looks, not what it shows, so the screen
checks and the saved answers stay the same and every step is quick to review. Turning tables into charts is its own
to-do, screen by screen, once the glass look is in. Existing charts are redrawn in the glass colours here.

| | A. Look only; charts after, as their own to-do | B. Charts as each screen is restyled |
|---|---|---|
| Effort | 6 pull requests, about 2–4 days | each screen step gets a chart decision first (which tables, which chart), then the build: about twice the time |
| Risk | low | every step mixes a new look with new content; harder to review, and the screen checks' saved answers move |
| What he sees | the coherent look sooner; charts later | both at once, later |

---

## Not his choice: one sensible way
These follow from what is settled or from the rules. The spec will do them unless he says otherwise.
- **The typed-in colours.** Each screen's step replaces its typed-in colours with named ones, so by the end the look is
  one set of named colours (light and glass during the switch, glass alone after). A check counts the typed-in colours and
  fails if the count grows. A separate "name them all first" step would change nothing he can see and nothing the checks
  can verify, so it isn't offered.
- **Charts' colours.** The charts are drawn in colours made for white cards (`src/ui/charts/layout.ts`: ink #0E1630 and
  violet #4B3BA8 among them). On dark glass these fall below 3:1, so the charts get a set made for dark glass, in each
  screen's step.
- **Status colours** (ok, warn, bad) are dark text on pale fills today. They become pale text on tinted glass, as the
  mock-up's "To file" and "Add" pills, each pair checked at 4.5:1.
- **The header keeps what the mock-up didn't draw:** the search box, the save state and the Local/UTC switch stay. With
  ten pills instead of six plus More, the bar may take two rows at 1280 px; the screen checks show whether it fits.
- **Speed.** Table panels at 82% get no blur: at that strength it barely shows, and leaving it off roughly halves the
  blurred areas on the table-heavy screens. Lift on hover stays off when reduced motion is asked for. The cost on his
  computer can't be measured from here; under decision 1A he tries it on live and turns it off if it isn't smooth.
- **The phone (380 px):** the rail becomes a row above the screen, as in the mock-up, and the screen checks still require
  no sideways scroll.
- **The globe on Home** stays as it is, set inside the glass layout.

## Background
**The mock-up:** "Planner glass look" (to-do 225's note; its files `project/Main.dc.html` for Home,
`project/Performance.dc.html` for a table screen, `project/Landing.dc.html`). Cards rgba(10,18,48,0.52), blur 24 px with
saturate 150%, 1 px white border at 18%, corners 22 px; tables on a panel at 82%; ten pills across the top; the airline
rail on the left; the backdrop by the clock (Day 07:00–17:00, Dusk 17:00–20:00 and 05:00–07:00, Night 20:00–05:00). Its
Home was set to show Day.

**Today's planner is light, and this flips it to dark.** Since 22 Oct (`docs/specs/2026-10-22-planner-look-foundation.md`)
the planner wears the website's light look: porcelain page, white cards, dark ink text (`app/planner/src/ui/styles.css`,
lines 7–33). The glass look is white text on dark glass. So this is not a frame around today's screens: every colour
that assumes a white card changes.

**What the build touches** (measured in the repository at commit bc7612e, 11 Nov):
- `app/planner/src/ui/styles.css`: 158,744 characters, 2,180 lines. 20 named colours and settings, used 1,044 times.
  Outside the named list, 413 colours typed in directly (307 hex, 106 rgb/rgba), 192 different ones across the file.
  76 of them are white or near-white (the white-card assumption). The Audit chat's 324 counted differently; the size of
  the job is the same.
- Colours typed into the code, not the stylesheet: 113, in 19 files, mostly charts (`src/ui/charts/layout.ts`,
  `src/screens/performance/model.ts` and `Charts.tsx`, Competition's and Systems' charts, the globe). The Audit chat's
  count didn't include these.
- Ten screens, 39 screen component files, 51 tables (16 on Performance, 8 on Reference, 6 each on Tails and Systems).
  Performance is the largest screen (2,258 lines of screen code), then Tails (1,197) and Routes (1,048).
- The frame is `src/App.tsx` and `src/ui/Header.tsx`; the landing page is `src/ui/landing/Landing.tsx` (its own note
  says a restyle changes only it and its styles).
- Five screens pick an airline through the address (Routes, Tails, Performance, Competition, Reference); three of them
  draw their own airline buttons (Routes, Performance, Competition).
- No animation or icon library is used, and none is needed.

**Text against the glass** (worked out with the standard contrast formula, white text over night glass over a flat
patch of backdrop; blur averages the picture, so a pale patch of sky behaves like this):

| Behind the card | Glass 52% | 60% | 66% | 82% (tables) |
|---|---|---|---|---|
| White sky | 3.7 (labels 3.1) | 4.9 (4.0) | 6.0 (4.8) | 10.8 (8.2) |
| Pale blue sky | 4.8 (3.9) | 6.1 (4.9) | 7.3 (5.7) | 11.9 (8.9) |
| Mid blue sky | 7.4 (5.8) | 8.8 (6.8) | 10.0 (7.6) | 13.9 (10.2) |
| Dusk | 10.8 (8.2) | 12.1 (9.0) | 13.0 (9.7) | 15.7 (11.4) |
| Night | 17.8 (12.7) | 17.9 (12.7) | 18.0 (12.8) | 18.2 (12.9) |

Labels are the mock-up's 84% white. 4.5:1 is the rule.

**How the last restyle went:** the light look (brief `docs/briefs/2026-10-22-planner-design.md`) was built in steps:
the foundation and three screens built and live on 22 Oct (#71–#74), Performance the same day (#79), the other six
screens on 23 Oct (`docs/specs/2026-10-23-planner-look-*.md`). That is the basis for "2–4 days"; this one is a little
bigger because every colour flips from light to dark.

**The checks:** the Database rehearsal opens every screen at 1280 and 380 px, with no errors and no sideways scroll
(manual §1). It doesn't compare pictures, so it can't tell whether a screen looks right; the previews and his eye do
that. The contrast check above would be new.

## Scenarios and the risk of waiting
- **Goes well (1A):** after step 1 he sees the frame, Home and the landing page on a preview, then on live with the
  switch. Each following step adds screens. At step 6 the switch goes and everyone has the glass look.
- **Goes badly:** the blur is not smooth on his computer, or a screen reads poorly on the Day picture. Under 1A he turns
  the switch off and carries on in the light look while the cause is fixed. The usual fix for slowness is blur on the
  bars and rail only, with cards at a plain 70% and no blur.
- **Waiting:** nothing breaks. The cost is that every planner build in the meantime adds styles in the light look that
  then have to be redone, and the landing page stays in the light look.

## What would change the recommendation
- If he doesn't want a switch in the account menu even for a few days: **1C**, previews only, with no other planner
  build allowed until it merges.
- If 66% looks heavy by day on the preview: **2B**, the veil, or a Day picture that is darker overall.
- If he wants the planner to remember one airline everywhere (for example to work through Ryanair's day): **4B**.
- If he'd rather wait a little longer and get charts at the same time: **5B**.

## Outcome
<Gitesh's decisions and the date>

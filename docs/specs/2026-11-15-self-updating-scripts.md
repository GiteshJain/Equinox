# Spec: scripts that update themselves, the key kept in the browser, and the fares script's own limit

To-do 247 (decided by Gitesh, 15 Nov, option B of two: "the scripts update themselves"), with the fares script's limit
from to-do 218 step 3 (option B). Comes before the salary table (to-do 245), so 245's new capture version arrives by
itself. Read `CLAUDE.md`, the map's rows for the capture, the fares userscript and the unattended capture (and their
files in `docs/map/`), manual §5 (the fares userscript, the ladder's floor and caps) and §7 (the capture), and the two
scripts' headers first.

**Status: decided and built.** Gitesh decided every choice on 15 Nov, 08:46 to 08:51 India time (in the Main chat; the
outcomes are at the bottom, each under its choice). Built in one pull request on branch
`build-247-self-updating-scripts`: capture 1.17, fares 1.5, migration `20261115170000_fares_script_limit.sql`.

**A new fact since the draft:** Gitesh moves from the Userscripts app to **Tampermonkey in Safari on the Mac**, which has an
"Automatic installation" setting (Tampermonkey's changelog, 5.6.6240/6241, July 2026, as the Main chat reported it), so
updates arrive there by themselves and the guard (§4) is the net. His words: "Tampermonkey worked ok with our scripts on
windows". Tampermonkey in Mac Safari is the target; the scripts use only the async `GM.*` calls that both apps have, so
they still work in the Userscripts app at no extra cost. No scripts on the iPhone.

## What it does, in one paragraph
Gitesh installs each script (capture and fares) one last time, on his Mac only, in Tampermonkey in Safari, from its raw
address on `main`. From then on the script's text never holds the key: the first time he presses its button, the script
asks for the key once in the browser's own box and keeps it in Tampermonkey's own storage, which the game's page can't
reach. A merge to `main` that raises a script's version reaches the Mac by itself (Tampermonkey's automatic
installation); a copy that is still behind stops before doing anything and says to update. The unattended run keeps
working unchanged: the file keeps the key placeholder, which the job fills. The fares script also gets a limit of its
own: it refuses any change whose level is under 55% or over 135% of the default price, stops before making anything and
says which change and why. (Drafted first for the Userscripts app on the Mac and the iPhone; §1 is that research, kept
because the scripts still run there.)

## 1. What the Userscripts app really does (researched 15 Nov)
Source read: the app's own repository, `github.com/quoid/userscripts`, branch `main` at commit `8b743e3` (10 May 2026):
its README and its source. Not read: the version on Gitesh's devices (the App Store version may differ from `main`), and
the issues (issue #248, which the README cites for updates, could not be opened from here).

- **It never installs an update by itself.** The only code that installs one is the popup's **Update** and **Update
  All** buttons (`src/ext/action-popup/App.svelte`, `updateItem()` and `updateAll()`, which send `POPUP_UPDATE_SINGLE`
  and `POPUP_UPDATE_ALL` to the app; `xcode/Ext-Safari/Functions.swift`, `updateAllFiles()`), and on the Mac the
  editor's Update button (README, "Editor buttons"). There is a setting "Scripts Updates Automatically" ("Script silently
  auto-updates in the background, which is dangerous…", `public/ext/shared/_locales/en/messages.json`), but it is
  marked `disable: true` in `src/ext/shared/settings.js` (hidden outside development) and no code reads it.
- **It checks only when the popup opens**, and only when the setting "Scripts Update Check Interval" is set: its values
  are Never, 1, 3, 7, 15 or 30 days, **default Never** (`settings.js`, `scripts_update_check_interval`, default 0;
  `App.svelte`, `shouldCheckForUpdates()`). When a check finds a newer version it lists it in the popup's updates view;
  the view also has a **Check Updates** button (`Components/Views/UpdateView.svelte`). The README's line "the extension
  periodically checks…" means this check when the popup opens.
- **What counts as newer:** the script needs both `@version` and `@updateURL` (`Functions.swift`, `canUpdate`). The app
  reads the file at `@updateURL` and compares its `@version` number by number (`isVersionNewer()`); only a higher one is
  offered. Then it downloads `@downloadURL` (or `@updateURL` when there's none) and writes it over the local file,
  whole (`updateAllFiles()`). Both addresses must be `https` (an `http` one is changed to `https`) and end in `.js`
  (`validateUrl()`); `@downloadURL` must end in `.user.js` with no `?` or `#` part (README). **A lower version is never
  offered**, so a rollback must carry a higher number (§7).
- **One unreachable address spoils the check for every script:** `checkForRemoteUpdates()` answers nothing at all
  ("failed to check for updates") when any one script's `@updateURL` doesn't answer 200 within 30 s.
- **Storage:** with `@grant` it offers `GM.setValue`, `GM.getValue`, `GM.deleteValue`, `GM.listValues`, and also
  `GM.xmlHttpRequest`, `GM.getTab`/`GM.saveTab` and the rest (README, "API"). The values are kept in the extension's own
  storage, `browser.storage.local`, under `<the script's file name>---<key>` (`src/ext/content-scripts/api.js`). So:
  kept per script and per device (not synced), kept across updates (an update rewrites the same file), **lost if the
  script's `@name` changes** (the file name follows it).
- **Where the script runs:** with no `@grant` (both scripts today, `@grant none`) and `@inject-into` left at `auto`, the
  app puts the code into the page itself as a `<script>` tag (`entry-userscripts.js`, `world === "page"`). With any
  `@grant`, it runs it in the extension's content world instead ("When using API methods, it's only possible to inject
  into the content script scope", README; `entry-userscripts.js` switches `auto` to `content`). The content world shares
  the page's HTML, `sessionStorage`, `localStorage` and cookies but not its JavaScript.
- **iPhone:** the same extension code runs (README: no editor on iOS; installing is "Visit a `.user.js` URL in Safari,
  then open the extension popup"; iOS 15.1 or later).

**What this means for the key (question 2).** Today the key is in the script's text and the script runs inside the
game's page, so the page's own JavaScript could read it (for example by watching `fetch` calls, which carry `p_key`).
With `@grant GM.getValue, GM.setValue, GM.deleteValue` the script runs in the content world: the key sits in the
extension's storage and the script's own variables, neither of which the page can reach, and the script's `fetch` calls
are its own, not the page's. The one moment the page could see it is while it is typed, if it is typed into a box on
the game's page (choice 3). It must never go into `sessionStorage` or `localStorage`, which the page can read.

**Not confirmed without Gitesh's devices** (each is a step of the first install, §6):
1. that the App Store versions on his Mac and iPhone behave as `main` does (the check interval setting is there, and
   no automatic install);
2. where the settings page is on the iPhone (the popup links to a "Settings page"; whether the interval can be set
   there on iOS is not shown by the source);
3. that the scripts work unchanged in the content world on Safari: their `fetch` calls to the game's own pages (the
   capture reads dozens; the salaries and the fares are posts and GETs that change the game) carrying the game's
   cookies, and their calls to Supabase. Other Safari extensions do this routinely, but this spec could not test it;
4. that `prompt()` works from the content world on the iPhone (only if choice 3 picks it).

### Tampermonkey in Safari (added 15 Nov, after the decisions)
Not researched from its source here (it isn't open source); what this build relies on, and what the Main chat should
check with Gitesh after the merge:
- **Relied on, standard in Tampermonkey:** `@updateURL` and `@downloadURL`, a higher `@version` offered as an update,
  `@grant GM.getValue`, `GM.setValue` and `GM.deleteValue` (the async forms), and with any `@grant` the script running
  in Tampermonkey's own sandbox rather than the page's (the game's JavaScript can't read the key there); `prompt()`
  from the script.
- **Not confirmed without his Mac:** how often Tampermonkey in Safari checks for updates (its "Check interval"
  setting; the build asks him to set it to the shortest he's happy with); whether "Automatic installation" really
  installs with no tap in Safari (the changelog's word; the guard stops an old copy either way); whether the scripts'
  `fetch` calls to the game (with its cookies) and to Supabase and raw.githubusercontent.com work from Tampermonkey's
  sandbox in Safari as they did on Windows with `@grant none`; and whether the fares script can still read the game's
  `frontendSettings` from the sandbox (if not, it uses the cookie's usual name, as it always could).

## 2. The update address (choice 2)
Each script gets, in its header:
```
// @version      <n>
// @updateURL    <address>/capture_all.user.js
// @downloadURL  <address>/capture_all.user.js
// @grant        GM.getValue
// @grant        GM.setValue
// @grant        GM.deleteValue
```
(the same for `fares_apply.user.js`). The address is choice 2. Facts checked on 15 Nov: the repository is public
(`gh api repos/GiteshJain/Equinox --jq .private` answered `false`); raw.githubusercontent.com serves the capture's file
with `cache-control: max-age=300` and `access-control-allow-origin: *`, so a merge is seen within 5 minutes; the
website (Cloudflare Pages, folder `web`) serves `no-cache` on its pages and would need the two files copied into `web`
at each build. The unattended run already downloads the raw file from `main` (spec
`docs/specs/2026-11-10-unattended-capture.md` §2.1).

## 3. The key in the browser
- `KEY` stays in the text as `"__CAPTURE_KEY__"` (choice 4 says whether it is still filled in anywhere).
- **When the placeholder is filled in** (the unattended run, choice 4 A), the script uses it and never calls `GM`.
- **Otherwise** it reads `GM.getValue("capture_key")`. With none stored, its first press asks for the key once (choice
  3), stores it with `GM.setValue` and goes on. The key is never written to the page, `sessionStorage`, `localStorage`,
  the panel or the console.
- **A wrong key** (the database answers with the wrong-key error) clears the stored one (`GM.deleteValue`) and asks
  again, once, saying "the database didn't accept this key". A leaked key is then: issue a new one, and each script asks
  for it on its next press.
- Each script keeps its own (storage is per script): two entries per device, four in all. The aircraft evaluation
  userscript is outside this to-do and keeps its key in its text.
- The scripts' `@name` must never change again (the stored key would be lost); a check guards it (§8).

## 4. Old code on his own presses (the guard)
Whatever choice 1 picks, a device can hold an older version for a while (until the popup is opened, or until a tap).
So **on a device** (the placeholder not filled), each press first reads its `@updateURL` (the script's own `fetch`, no
key sent) and compares versions with its own (`GM.info.script.version`):
- **behind:** it stops before doing anything: "This is capture 1.17; 1.18 is out. Open the Userscripts popup and tap
  Update, then reload the page and press again." Nothing is captured, no salary set, no fare changed;
- **the address doesn't answer** (5 s): a panel line "couldn't check for a newer version" and the press goes on, so a
  GitHub or website outage never stops the evening;
- **a version changes mid-run** (the run's state in `sessionStorage` carries the version it started with): it stops,
  "updated during the run: press again"; what's done stays done, as now.
In the unattended run (placeholder filled) there is no guard: the run already downloads `main` each time.

## 5. The unattended run keeps working (question 3)
What this repository says about it (`docs/specs/2026-11-10-unattended-capture.md` §2, `docs/map/unattended-capture.md`;
`equinox-backups` itself was not read): the job downloads `capture/capture_all.user.js` from `main`, puts the
`CAPTURE_KEY_UNATTENDED` secret in place of `__CAPTURE_KEY__`, checks `@version` is 1.16 or later, and injects the
script into each page with Playwright, where there is no `GM`. How it keeps working is choice 4. Either way:
- the script must run with no `GM` defined (it checks `typeof GM`), as a test proves (§8);
- the header's new lines don't matter to the job (it ignores the header except `@version`);
- the first scheduled run after the merge (09:30 or 21:30 UTC) is the proof; a broken one fails and GitHub emails him.

## 6. The one last install, on the Mac only (rewritten 15 Nov for the decisions)
Steps for Gitesh, one at a time, after the merge (the Main chat sends them; no key is ever typed in a chat):
1. **Install Tampermonkey** for Safari on the Mac (App Store), and switch it on in Safari's settings → Extensions, allowed
   on `gander.airlinesim.aero` (and raw.githubusercontent.com, for the install pages).
2. **Tampermonkey's settings** (its menu → Dashboard → Settings, config mode Advanced if the options are hidden): under
   Script Update, switch on **automatic installation** and set the **check interval** (every 6 hours, or the shortest
   offered).
3. **Install each script from its raw address**, in Safari:
   `https://raw.githubusercontent.com/GiteshJain/Equinox/main/capture/capture_all.user.js`, then
   `https://raw.githubusercontent.com/GiteshJain/Equinox/main/capture/fares_apply.user.js`; Tampermonkey shows its
   install page for each: Install.
4. **Remove the old copies in the Userscripts app on the Mac:** in its editor, select "equinox. capture all airlines" and
   "equinox. apply fare plan" and trash each (or switch the app off for the game). Two copies of a script would both
   draw their buttons and both run. Leave the aircraft evaluation userscript where it is (outside this to-do).
5. **First press of each, in the game:** Capture all airlines asks for the key once in a browser box: paste it from where
   he keeps it. The capture then runs as usual. Apply fare plan asks for it once too, then reads the plan and asks before
   changing anything, so its first press can be stopped at "Cancel".
6. **The iPhone:** open the Userscripts app's all-scripts view and delete the old capture script (it has the key in its
   text and no guard), and the fares script if it is there. Then no equinox. script is left on the phone.
7. Report back on the to-do: the version each script shows in Tampermonkey (1.17 and 1.5), and, after the next merge
   that raises a version, whether it arrived without a tap.

## 7. Rolling back a bad version
- The app only offers a higher version (§1), so a rollback is a pull request that puts back the last good code **with
  a new, higher version** (bad 1.18 → 1.19 holding 1.17's code), merged on "merge" as any change. The guard (§4) then
  stops the bad one on its next press.
- Until then, on the Mac: switch the script off in Tampermonkey's menu (its switch beside the script), or edit it there
  and paste an older file over it; the stored key stays (the same script).
- A version number is never lowered or reused; a check guards it (§8).

## 8. The fares script's own limit
- Gitesh's decision (to-do 218 step 3, option B): the fares script refuses any change whose level is **under 55% or
  over 135%** of the default price. 55 and 135 themselves pass.
- **The level of a change** is what the script would send: baseline default price, so `100 − pct` for `−` and
  `100 + pct` for `+`. A change whose `level` field (fare_ladder()'s) disagrees with that is refused too ("level 120%
  but the change says +25%").
- **Checked before anything is made:** in `actionProblem()`, which `planOf()` runs over every airline's changes before
  the one ask; so a change outside the limit stops the run with nothing made, naming the airline, the change's text and
  why ("Pan Am, From JFK to LHR: 140% of the default price is over the fares script's limit of 135%").
- **Missing limits** (an older database answer without them) refuse the whole plan: "the database didn't give the
  fares script's limits".
- **Why these numbers:** just outside what the ladder can produce today (manual §5): the floor is 60%
  (`world_rules.fare_floor_pct`, and the last under-launch level, `fare_under_launch_levels`, 60); the highest cap is
  launch plus `fare_ladder_cap_pts`: 120%, Ryanair 105%, Pan Am and China Eastern 128%.
- **Where the two numbers live** is choice 5a (fixed rows, or worked out from the ladder's reach); in
  every option they are in `settings` (manual §1: the one source for rule numbers), described, and the database gives
  them to the script in `capture_fare_actions_by_airline()`'s list answer (`limits: {min_pct, max_pct}`). A copy in the
  script's text is not offered: it would break manual §1.

## 9. Files
- `capture/capture_all.user.js`: header (§2), the key (§3), the guard (§4); version 1.17.
- `capture/fares_apply.user.js`: the same, plus the limit (§8); version 1.5.
- `database/migrations/<date>_fares_script_limit.sql`: the settings rows (choice 5), `capture_fare_actions_by_airline()`
  answering `limits`; described; `database/current/` updated.
- Website build, only if choice 2 is B: the copy of the two files into `web/scripts/`, and a check that they match.
- Tests (below). Documents (below).

## 10. What the checks should show
- `tests/userscript_key_test.mjs` (new; runs both files in Node with stand-ins for `GM`, `fetch` and the page):
  placeholder filled → uses it and never touches `GM`; no `GM` at all → runs (the unattended run's case); a stored key
  → used; none → asks once and stores it; a wrong-key answer → cleared and asked again once; the key never appears in
  `sessionStorage`, `localStorage`, the panel or the console; the guard: behind stops before any call, the same passes,
  an address that doesn't answer goes on with its line, a version change mid-run stops.
- A header test (in the same file): both scripts have `@version`, `@updateURL` and `@downloadURL` at the chosen
  address ending `.user.js`, the three `@grant` lines and no `@grant none`; `@name` unchanged; the capture's `VERSION`
  equals its `@version`; each `@version` higher than on `main` when the file changed (so no change ships unoffered and
  no number goes back).
- `tests/fares_userscript_test.mjs`: 54% and 136% refused, 55% and 135% pass, a `level` that disagrees refused, missing
  limits refuse the plan, and a plan with one change outside the limit makes nothing.
- `tests/check_secrets.py` unchanged and green (the placeholder stays).
- Database rehearsal: a new test that the rows exist and are described, that the list answer carries them, and that
  the ladder's reach (the highest launch plus cap over our airlines, the lowest floor and under-launch level) stays
  strictly inside them, so lifting a cap without moving the limit turns the check red (choice 5 A), or that the limit
  follows it (choice 5 B).

## 11. Documents (in the build's pull request)
- Manual §5, the fares userscript paragraph: the limit and its two rows. §7: where the scripts come from and that
  they update (as chosen in choice 1), the key kept in the browser. Rule history with why.
- The map: the parts table's capture and fares rows only if their short description changes; "Where keys are kept"
  (the capture key in each device's Userscripts storage, per script; the unattended key unchanged); "When something
  breaks" (a key leaked: issue a new one and each script asks on its next press; a bad version: §7).
- `docs/map/capture.md` and `docs/map/fares-userscript.md`: dated notes.
- `equinox-backups`' README, only if choice 4 is B.

## 12. Built in one pull request
`Equinox` only (choice 4 A), or two (choice 4 B: `equinox-backups` first, then `Equinox`).

---

## Choices for Gitesh, and his decisions (15 Nov, 08:46 to 08:51 India time)

### Choice 1: the app only updates on a tap (decided)
The app checks for a newer version only when its popup opens, and installs it only when he taps Update (§1). "The
scripts update themselves" isn't possible in the app as it is.

| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. Tap to update, with the guard (§4) | The app's own update path. Each merge: open the popup, tap Update, once per device. Old code never runs on his presses: it stops and says so | One tap per device per merge; a press blocked until he taps | A forgotten device just refuses, it never runs old code | Yes |
| B. A small loader pasted once, which fetches and runs the current code at every page load | Truly by itself: no tap ever | A bigger change: the loader keeps a last good copy for when the address is down; every page load fetches the code (cached 5 min); the capture's page loads must all run the same version | Anything merged runs at the next page load with no install step; untested whether Safari allows it on the game's pages (the app runs content-world code the same way, so likely) | Yes, by pasting the script back |
| C. Tap to update, no guard | Simplest | As A, minus the guard's code | An old version on a device still runs old code on his presses, which is what 247 is meant to stop | Yes |

**Recommendation (only):** A. It keeps every update visible as a tap, and the guard removes the old-code risk, which is
the reason for 247.

**Outcome (Gitesh, 15 Nov): A.** The update address plus a guard on each press that stops an out-of-date script before
it does anything and says to update; no loader. On the Mac he moves to Tampermonkey, whose automatic installation takes
updates by itself ("Tampermonkey worked ok with our scripts on windows"); the guard is the net.

### Choice 2: where the update address is served from (decided)

| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. raw.githubusercontent.com, `GiteshJain/Equinox/main/capture/` | No build change; the same file the unattended run downloads; a merge is seen within 5 minutes | Nothing more | Works only while the repository is public; if it's made private, updates stop (and, §1, one failing address spoils the app's check for all scripts) | Yes, by a version with a new address |
| B. equinox-alliance.com/scripts/ (Cloudflare Pages) | Our own address; works if the repository goes private | A build step copying the files into `web`, and a check that they match | A failed site build holds updates back; two copies to keep equal | Yes, the same way |

**Recommendation (only):** A, while the repository is public.

**Outcome (Gitesh, 15 Nov): A.** GitHub's raw file on `main`.

### Choice 3: where the key is entered (decided)

| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. A box in the script's own panel, on the first press | Matches the panels (no browser dialogs) | Nothing more | The game's page could read the box while it's typed (it's on the page); a one-time, theoretical exposure | Yes |
| B. The browser's own `prompt()` box, on the first press | The page can't see what's typed: it goes straight to the script | Breaks the "no browser dialogs" habit, once per script per device | Not confirmed on the iPhone (§1) | Yes |

**Recommendation (only):** B, since it's the only one that meets "the game's page can't read it"; fall back to A if it
doesn't work on the iPhone.

**Outcome (Gitesh, 15 Nov): B.** Typed once into the browser's own `prompt()` box.

### Choice 4: how the unattended run gets its key (decided)

| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. Keep `__CAPTURE_KEY__` in the text: the job fills it as now; a device uses storage | `equinox-backups` unchanged; one pull request | Two paths in the script (tested) | Low: a filled-in key only ever exists in the job's copy | Yes |
| B. No placeholder: the job gives the script a stand-in `GM` holding its key | One path in the script | A pull request in `equinox-backups` too, merged first, which this spec couldn't read | If the order slips, the 09:30 or 21:30 run fails (GitHub emails him) | Yes |

**Recommendation (only):** A.

**Outcome (Gitesh, 15 Nov): A.** The job is left as it is: the script keeps the placeholder for the job to fill;
`equinox-backups` unchanged; with the placeholder unfilled the script reads the key from the app's storage.

### Choice 5: the limit's two numbers, and the iPhone (decided)

**5a. How the limit moves with the cap**

| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. Two rows, `fares_script_min_pct` 55 and `fares_script_max_pct` 135; the rehearsal turns red when a cap or floor change reaches them | The limit catches a wrong cap too (a mistyped `fare_ladder_cap_pts` is refused in the game) | Lifting a cap means moving the limit in the same rule change (manual §1 already asks for both together) | A forgotten move shows as a red check, never as a wrong price | Yes, a data change |
| B. Worked out: the ladder's highest reach plus a margin row (7 points), its lowest floor minus one (5) | Moves by itself when the cap is lifted | Nothing at rule changes | A wrong cap row widens the limit with it, so the limit no longer catches it | Yes |

**Recommendation (only):** A.

**Outcome (Gitesh, 15 Nov): A.** Two fixed `settings` rows, 55 and 135, with a check that goes red if a cap change
reaches them.

**5b. The iPhone's capture.** Memory (not this repository) says that on 30 Oct Gitesh installed capture 1.9 (the
market pages) only on the Mac and kept an older capture on the iPhone on purpose. With updates (and the guard), the
iPhone either takes every version or refuses to run.

| Option | What it gives | Cost | Risk | Easy to undo? |
|---|---|---|---|---|
| A. The iPhone takes the same versions | One script everywhere; old code never runs | A phone press reads the world scan and market pages when they're due (10 to 15 minutes more, tab open) | A long run on a phone that sleeps; it carries on from `sessionStorage` when reopened | Yes |
| B. The same versions, but on a phone the capture skips the scan and market pages (left for the Mac or the unattended run) | Short phone runs | A small change: "on an iPhone" read from the browser | A wrong reading of the device | Yes |
| C. No capture on the iPhone (the unattended run covers it); fares there or not as he likes | Nothing to keep up on the phone | One script less | None new | Yes, paste it back |

**Recommendation (only):** C if he no longer presses capture on the phone since the unattended run started, else A.

**Outcome (Gitesh, 15 Nov): C, Mac only.** No scripts on the iPhone: "I'll only do it on Mac since captures run
automatically anyways". The rollout (§6) deletes the old capture script from the iPhone's Userscripts app and removes
the old copies from the Userscripts app on the Mac.

**The aircraft evaluation userscript** stays out of this build (the Main chat is asking Gitesh); it keeps its key in its
text and its `@grant none`.

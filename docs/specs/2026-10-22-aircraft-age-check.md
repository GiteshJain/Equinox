# Spec: aircraft age check and replacement warning — 22 Oct 2026

Brief: `docs/briefs/2026-10-22-aircraft-age-check.md` (option B, simplified: the game's age, no built date).
Rule: manual §3, *Replacement by age*: an aircraft we ordered new is replaced at 3 years, one from the used market at 10.

## What and why
Today nothing in the planner knows which aircraft came used (only `aircraft.order_note`, in prose), and nothing warns
when an aircraft nears its replacement age. The capture already reads each aircraft's age every night
(`game_fleet.age_years`, in tenths of a year), and `fleet_checks()` feeds Today's Fleet group and Systems' Fleet board.
This build adds a new-or-used mark on each aircraft, the rule's numbers as settings, and two new fleet-check kinds.

## 1. Database (one migration)
- `aircraft.acquired`: text, not null, default `'new'`, check in (`'new'`, `'used'`), with a column description
  ("how we got the aircraft: new from the factory, or used from the game's Aircraft Market; decides its replacement
  age, manual §3"). Backfill `used` for N023AW, 9M-AAY and G-AAFB (aircraft ids 283, 284, 285; their `order_note`
  starts "Used,"). Staff already read and write `aircraft`; check the planner's saves still pass.
- `settings` (world rows, no airline overrides), each with unit, description, since 22 Oct and the reason
  "manual §3, replacement by age (Gitesh, 22 Oct)":
  - `replace_new_years` = 3 (years)
  - `replace_used_years` = 10 (years)
  - `replace_warn_days` = 60 (days): how long before the replacement age the warning starts.
- `private.fig_fleet_checks()` (behind `public.fleet_checks()`): for each aircraft in the latest night,
  - add `acquired` and `replace_at_years` (3 or 10 from the settings) to its row;
  - **kind `replace`** when `age_years >= replace_at_years - replace_warn_days / 365.25`. Words:
    "N001AW (JFK): replace at 3 years (now 2.9): order its replacement". Once at or past the age:
    "N001AW (JFK): past its replacement age (3 years, now 3.0)".
  - **kind `age`** (the cross-check) when an aircraft marked `new` is older in the game than its time with us by more
    than 0.2 years: `age_years - (night − delivery_at) / 365.25 > 0.2`. Words:
    "N023AW (JFK): looks used (3.6 years in the game), marked new". Skip it when `delivery_at` is null.
  - add both to `counts` and `problems`, in the same shape as the existing kinds.
- Update `database/current/functions.sql` and the table guide comes from the descriptions as usual.
- A database test in `database/tests/` (beside `fleet_capture_test.sql`): on the rehearsal's copy, set one new
  aircraft's latest `age_years` to 2.9 → `replace`; to 3.1 → the past-age words; a `used` one at 9.9 → `replace` at
  10; a `new` one delivered last month with age 3.6 → `age`; the three backfilled aircraft are `used`.

## 2. Planner (`app/planner/`)
- Today's Fleet group (`src/screens/today/attention.ts`) lists the two new kinds with the existing ones, using the
  words from `fleet_checks()`.
- Systems' Fleet board (`src/screens/systems/`): add the age and the replacement age per aircraft, and mark the rows
  with a `replace` or `age` item.
- Tails' pop-up: show "came new / used, replace at N years".
- Regenerate `src/db/types.ts` from the database. Unit tests beside each `model.ts`, and the screens' saved answers
  updated if any move (say which in the pull request).

## 3. Documents (same pull request)
- Manual §3, *Replacement by age*: name the rows (`settings.replace_new_years`, `replace_used_years`,
  `replace_warn_days`) and say Today's Fleet group warns from 60 days before. Log nothing in rule-history (the rule
  itself doesn't change; only where its numbers live).
- Manual §3, *The used market too*: when Claude logs a won auction, it sets `aircraft.acquired` to `used`.
- Manual §7, *The fleet pages*: add the two new items to the list of what Today's Fleet group shows.
- `docs/architecture.md`, `docs/planner-guide.md`, `docs/playbook.md` (logging a used order), `database/current/`.

## What the checks should show
All green: *Checks* (types, lint, unit tests, build, saved answers) and the *Database rehearsal* (the migration on
last night's backup, the new test, every screen at 1280 and 380 px). On live today the new kinds show nothing:
the oldest aircraft is 0.1 years and the three used ones arrive marked `used`.

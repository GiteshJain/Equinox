# Build spec: the one-week aircraft checks turned off — 15 Oct 2026

**Why:** Gitesh no longer wants the one-week aircraft checks (manual §1, retired 15 Oct). The planner still raises them
on Home (needs attention and Coming up), on Check (the *Aircraft checks* board) and in Tails (the aircraft pop-up's check
line and *Mark checked*). Turn them off without losing the way back.

## 1. The setting turns them off
`aircraft_check_after_days` set to 0 (or missing) means **off**: the library's `checks.oneWeek()` (`lib/rules/src/checks.ts`)
gives no checks. Any number above 0 works as today. A unit test for each.

## 2. The screens follow
When the checks are off:
- **Home:** no check items in needs attention or Coming up (they follow from the empty list; a test shows it).
- **Check:** the *Aircraft checks* board isn't shown (its count and hint go with it).
- **Tails:** the aircraft pop-up shows no check line and no *Mark checked*.
Nothing else moves. With the setting above 0, every screen is exactly as today.

## 3. Data
No migration. After "merge" the Building chat sets `aircraft_check_after_days` to 0 (not before: the library live today
would make every aircraft due at once).

## Checks and proof
- `bash tests/run_all.sh` passes. Saved answers move only where the setting is 0 in a test.
- **A deliberate failure,** seen to fail then removed: the off switch ignored (the new library test must go red).

## Docs
`docs/planner-guide.md` (Home, Check, Tails), `lib/rules` notes where the rule is described, design §16 if it lists the
checks. The manual is already updated.

## Rules for the helper
- Follow `CLAUDE.md`. **Work lean.** **Never connect to the live database or use the Supabase connector tools.** Never
  commit a key.
- Work on branch `aircraft-checks-off`, open the pull request with the REST API, and don't merge.

## Done when
Every check is green and the deliberate failure was seen to fail, then removed. The pull request says what changed, that
nothing moves while the setting is above 0, the step after "merge", and how to roll back (set the number back).

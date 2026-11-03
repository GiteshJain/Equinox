# Interline: tracking replies to our requests

Spec from the Building chat, 3 Nov 2026. Decided by Gitesh the same day: option A of the chat's brief, built to match
manual §6 as committed on 3 Nov ("requests unanswered for two weeks" listed at the Saturday review).

## Why
Interline requests we send sit in `interline_agreements` with status `to_sign`, and the date each was sent lives only in
the free-text note ("Requested 2 Nov …", "Request sent 3 Nov …"). Nothing can count how long a request has waited, so the
Saturday review can't list the ones unanswered for two weeks (§6) without reading every note. 16 requests were waiting
on 3 Nov, all sent 2–3 Nov.

## What
1. **Database** (one migration, `database/migrations/20261103010000_interline_requested_on.sql` or the next free
   version):
   - `interline_agreements.requested_on date` (null allowed), with a column description: the day we sent the request;
     set while the row waits on the other airline (status `to_sign`).
   - Fill it for existing `to_sign` rows from the note: the first "Requested <d> <Mon>" or "Request sent <d> <Mon>"
     (year 2026), else the row's `decided_on`, else `created_at`'s UTC date. Run with logging off as earlier data loads
     do, or with `equinox.actor` set to `claude` and detail `building interline replies` (either is fine; say which).
   - A setting `interline_reply_wait_days` = 14 (world-level `settings` row, with its description pointing at manual §6),
     shown under Reference → constants like the other numbers.
   - `planner_save()` must be able to write the new column (check whether its column list needs it).
   - The column comment on `status` stays as it is; don't add statuses.
2. **Planner, Interline screen** (`app/planner/src/screens/interline/`):
   - A new board at the top, **Waiting for a reply**: every row of the world with status `to_sign` and a partner,
     oldest first: airline (its mark), country, partner, requested on (as words, "2 Nov"), days waiting. A row at or
     over `interline_reply_wait_days` is marked in amber "no reply in two weeks" (the words built from the setting:
     14 → "two weeks", other values "N days"). The board's line says how many wait and how many are past the mark;
     with none it says "No requests waiting". Phone-first, no sideways scroll at 380 px. No chart (Gitesh, 3 Nov).
   - Editing a row: when its status becomes `to_sign` and it has no `requested_on`, the save sets it to today (UTC
     date); a `requested on` date box on the row lets him change it; any other status leaves the date as it is
     (history). One `planner_save()` call per action, as now.
   - Its logic in `model.ts` with unit tests (sorting, days waiting, the mark at exactly the setting, the words).
   - Nothing on Today, Home or Needs attention.
3. **Docs** in the same pull request: the map (`docs/architecture.md`, Interline's row: the board, its source and its
   save), the planner guide, the playbook's Saturday step for §6's unanswered requests (point to the board; don't
   restate the rule), `database/current/` if anything there changes, and the generated `docs/data.md` and
   `app/planner/src/db/types.ts` from the rehearsal's artifacts.

## What the checks should show
- All green, including the database rehearsal, its types and the planner's saves test (record the new save's rows in
  `tests/fixtures/planner_saves.expected.json` if the Interline save's rows change).
- The rehearsal on last night's copy fills `requested_on` for every `to_sign` row (a test in `database/tests/` that no
  `to_sign` row with a partner is left null after the migration, and that the note's date wins where there is one).
- Screens open at 1280 and 380 px with the new board and no sideways scroll.

## Out of scope
Reading replies from the game (option B), anything on Today, changing §6, and the QantasLink note on Malaysia's
Australia row (the Building chat raises that with Gitesh).

# Spec: the capture stops rewriting bank-statement lines it already has

To-do 204, step 2 (from the audit of 10 Nov; Gitesh agreed). Step 1, rebuilding `game_statement`, was done on 10 Nov
(117 MB to 21 MB, no rows changed). One pull request, one migration. Read `CLAUDE.md`, the map and manual §7 first.

## Why
Every statement page a capture stores writes every one of its lines again, even when nothing changed, in three places:
1. `private.capture_page()`'s statement branch ends `on conflict on constraint game_statement_pkey do update set blk =
   excluded.blk`: an unchanged line is updated anyway.
2. `private.fold_statement()` step 1 sets `flight_id` to null on every line of the page's minutes...
3. ...and step 4 sets it again on every flight line.

So each line is rewritten up to three times a capture. With capture 1.16 reading the whole 24 hours (about 9,400 lines
across the six airlines) and the unattended capture running twice a day besides Gitesh's press, that is 60,000 to
90,000 dead rows a day in a table of about 85,000. Autovacuum reuses the space, but the table and its indexes swell
between vacuums, and the database pays for every write (it grew `game_statement` to 117 MB by 10 Nov).

## What to change (one migration)
- **The upsert:** add `where game_statement.blk is distinct from excluded.blk` to the statement branch's
  `on conflict ... do update`.
- **`fold_statement()` step 1:** release a line from its flight only when that flight is about to be deleted or have
  its money taken off in step 2, or when the line's own block no longer matches its flight's (`statement_blk`). A line
  whose flight stays as it is keeps its `flight_id` untouched. Check whether `game_statement.flight_id` has a foreign
  key to `game_flights` and make sure step 2's delete can never meet a line still pointing at a deleted flight.
- **`fold_statement()` step 4:** set `flight_id` only where it differs (`s.flight_id is distinct from f.id`).
- **Step 5 (payments) must see the same lines as now:** it reads lines with `flight_id is null` after step 4; a flight
  line kept tied is not a payment, as today. Verify nothing else reads the window between steps 1 and 4.
- **The end state must be exactly today's** for any page: the same `game_statement`, `game_flights` and
  `game_payments` rows. Only the number of writes changes.
- Note in the pull request, without changing it: step 3's upsert on `game_flights` rewrites every flight each capture,
  because `money_captured_at` is always the new capture's time. Measure how many `game_flights` rows a repeated page
  rewrites, so Gitesh can decide later whether that is worth a change of its own (it changes what that column means).

## What the checks should show
- **A new `database/tests/statement_no_rewrite_test.sql`:**
  - the copy's latest ok statement page, stored again a minute later as the capture stores it, writes no
    `game_statement` row: none carries this transaction's id, `xmin = pg_current_xact_id()::xid`;
  - a line whose block was set wrong by hand is put right by the same page read again;
  - a flight whose block disappears from a page read again loses its lines' `flight_id`, as today.
- **Replay:** every kept capture page replayed (`capture_data_replay_test.sql`) gives the same rows as before, and the
  capture checks (`capture_checks_test.sql`, including the statement in parts) pass unchanged.
- `database/current/` and the map's How data moves (step 1, the statement) updated.

## After the merge
Claude applies it to live. Two captures later, compare `pg_stat_user_tables.n_tup_upd` for `game_statement` before and
after a capture: it should drop from about the page's line count to about the new lines.

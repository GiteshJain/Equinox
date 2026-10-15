-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, for
-- database/tests/pilot_training_test.sql and clean_up_test.sql (20261015200000, spec docs/specs/2026-10-15-small-fixes.md
-- §1): each payment the capture stored as unnamed (game_payments kind other), by id, so the tests can show which
-- payments the re-sort named and put their kinds back to compare everything else with before. Nothing is printed.
create table rehearsal_before.payment_kinds as
  select p.id, p.kind, p.descr from public.game_payments p where p.kind = 'other';

-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and read afterwards by
-- database/tests/interline_requested_on_test.sql (spec docs/specs/2026-11-03-interline-replies.md): whether
-- interline_agreements had requested_on yet. Without it, 20261103010000_interline_requested_on.sql runs in this rehearsal
-- and its fill is checked exactly; once it is live, the planner has been writing the column, so only what still holds is.
create table rehearsal_before.interline_requested_on (had_column boolean not null);
insert into rehearsal_before.interline_requested_on (had_column)
select exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'interline_agreements' and column_name = 'requested_on');

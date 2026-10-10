-- Before the new migrations (#13 build, pull request 9): whether the old planner rows were already frozen in last
-- night's backup, so a test can tell the night of the switch-over (the rows frozen during this rehearsal, still equal to
-- the getters) from any night after it (the rows older than the tables by design).
create table rehearsal_before.planner_frozen as
select exists (select 1 from pg_catalog.pg_trigger t
                where t.tgrelid = 'public.planner_state'::regclass and t.tgname = 'planner_frozen') as frozen;

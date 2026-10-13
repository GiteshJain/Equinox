-- #18 build pull request 5 (Home, spec docs/specs/2026-10-13-home.md §1): saved before the new migrations, for
-- database/tests/rules_input_test.sql. rules_input()'s document as the copy gives it before this rehearsal's changes,
-- so the test can show that 'all' (the default) is unchanged once rules_input() takes p_routes. Run as postgres, which
-- rules_input() lets through as it lets staff. The call is made by name at run time: before this change the copy has
-- only rules_input(bigint), after it (on later nights) only rules_input(bigint, text).
create table rehearsal_before.rules_input (doc jsonb);
do $$
begin
  if to_regprocedure('public.rules_input(bigint, text)') is not null then
    execute 'insert into rehearsal_before.rules_input (doc) select public.rules_input(null::bigint, ''all''::text)';
  elsif to_regprocedure('public.rules_input(bigint)') is not null then
    execute 'insert into rehearsal_before.rules_input (doc) select public.rules_input(null::bigint)';
  end if;
end
$$;

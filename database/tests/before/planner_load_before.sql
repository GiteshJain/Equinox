-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and read afterwards by
-- database/tests/planner_load_flights_test.sql (#13 build, pull request 4): how many of the capture's flights had both
-- their money and their loads before the airports had time zones. A copy from before pull request 3 has no game_flights
-- yet, and saves nothing.
create table rehearsal_before.game_flights_sides (both_sides bigint, money_only bigint, loads_only bigint);
do $$
begin
  if to_regclass('public.game_flights') is not null then
    execute $q$insert into rehearsal_before.game_flights_sides
               select count(*) filter (where flight_no is not null and posted_at is not null),
                      count(*) filter (where flight_no is null), count(*) filter (where posted_at is null)
                 from public.game_flights$q$;
  end if;
end
$$;

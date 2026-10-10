-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared
-- afterwards by database/tests/capture_data_compat_test.sql (#13 build, pull request 3): once the capture data lives in
-- game_flights and game_payments, the three capture views, export_capture(), export_for_report('planner'),
-- site_public() and planner_loads must come out exactly as they did before.
create table rehearsal_before.game_loads as select * from public.game_loads;
create table rehearsal_before.game_flight_pnl as select * from public.game_flight_pnl;
create table rehearsal_before.game_ops_recent as select * from public.game_ops_recent;
create table rehearsal_before.planner_loads as select * from public.planner_loads;
create table rehearsal_before.outputs (name text primary key, value jsonb);

-- The export functions need the ingest secret, which backups never hold: a throwaway one, removed again. 3650 days
-- takes in every captured row, so the result doesn't depend on the minutes between this and the test.
do $$
declare s text := 'rehearsal-' || gen_random_uuid();
begin
  insert into public.ingest_secret (secret) values (s);
  insert into rehearsal_before.outputs (name, value) values
    ('export_capture', public.export_capture(s, 3650)),
    ('export_for_report planner', public.export_for_report(s, 'planner')),
    ('site_public', public.site_public());
  delete from public.ingest_secret where secret = s;
end
$$;

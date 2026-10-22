-- The report's figures get time to finish (migration 20261017170000_figures_timeout.sql). Run by database/rehearse.sh
-- on the copy of last night's backup, after the new migrations, inside a transaction that is rolled back.
--   1. export_for_report carries its own statement limit of 30 seconds, and keeps its empty search_path.
--   2. The planner's twelve figure functions carry the same 30 second limit (migration 20261022050000: Performance reads
--      about twenty at once and some crossed staff's 8 s), and no other function in public carries a statement limit but
--      capture_fare_actions() (the fares userscript's list, migration 20261021210000; its own test checks its 30 s) and
--      fleet_checks() (the fleet capture, migration 20261022070000; fleet_capture_test.sql checks its 30 s), so the roles'
--      limits (anon 3 s, staff 8 s) still hold everywhere else.
--   3. The figures still come back in one call on the copy, within the 30 seconds.

do $test$
declare cfg text[]; t0 timestamptz; missing text; v jsonb; others text; s text := 'figures-timeout-test-' || gen_random_uuid()::text;
begin
  -- the copy carries no ingest secret (the backup leaves the key tables out): one of its own, rolled back with the test
  insert into public.ingest_secret (secret) values (s);
  select p.proconfig into cfg from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'export_for_report';
  assert cfg @> array['statement_timeout=30s'], 'export_for_report has no 30 s statement limit: ' || coalesce(cfg::text, 'none');
  assert cfg @> array['search_path=""'], 'export_for_report lost its empty search_path: ' || coalesce(cfg::text, 'none');

  select string_agg(f, ', ') into missing from unnest(array['airline_cards', 'airline_profit', 'cash_forecast', 'route_profit',
         'aircraft_profit', 'fare_changes', 'fare_plan_status', 'fare_ladder', 'growth_signals', 'hub_progress', 'route_loads',
         'route_story']) f
   where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = f and p.proconfig @> array['statement_timeout=30s', 'search_path=""']);
  assert missing is null, 'figure functions without the 30 s limit (or without their empty search_path): ' || missing;

  select string_agg(p.proname, ', ') into others from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname not in ('export_for_report', 'capture_fare_actions', 'fleet_checks', 'airline_cards', 'airline_profit',
         'cash_forecast', 'route_profit', 'aircraft_profit', 'fare_changes', 'fare_plan_status', 'fare_ladder', 'growth_signals',
         'hub_progress', 'route_loads', 'route_story')
     and exists (select 1 from unnest(p.proconfig) c where c like 'statement_timeout=%');
  assert others is null, 'other functions carry a statement limit: ' || others;

  t0 := clock_timestamp();
  v := public.export_for_report(s, 'figures', '{}');
  assert v ? 'airlines', 'the figures came back without their airlines';
  assert clock_timestamp() - t0 < interval '30 seconds', 'the figures took 30 seconds or more on the copy';

  raise notice 'figures timeout: export_for_report has its own 30 s limit (search_path kept), the twelve figure functions have it too, no other function has one but capture_fare_actions and fleet_checks, and the figures came back in % ms on the copy',
    round(extract(epoch from clock_timestamp() - t0) * 1000);
end
$test$;

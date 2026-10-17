-- The report's figures get time to finish (migration 20261017170000_figures_timeout.sql). Run by database/rehearse.sh
-- on the copy of last night's backup, after the new migrations, inside a transaction that is rolled back.
--   1. export_for_report carries its own statement limit of 30 seconds, and keeps its empty search_path.
--   2. No other function in public carries a statement limit, so the roles' limits (anon 3 s, staff 8 s) still hold
--      everywhere else.
--   3. The figures still come back in one call on the copy, within the 30 seconds.

do $test$
declare cfg text[]; t0 timestamptz; v jsonb; others text; s text := 'figures-timeout-test-' || gen_random_uuid()::text;
begin
  -- the copy carries no ingest secret (the backup leaves the key tables out): one of its own, rolled back with the test
  insert into public.ingest_secret (secret) values (s);
  select p.proconfig into cfg from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'export_for_report';
  assert cfg @> array['statement_timeout=30s'], 'export_for_report has no 30 s statement limit: ' || coalesce(cfg::text, 'none');
  assert cfg @> array['search_path=""'], 'export_for_report lost its empty search_path: ' || coalesce(cfg::text, 'none');

  select string_agg(p.proname, ', ') into others from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname <> 'export_for_report'
     and exists (select 1 from unnest(p.proconfig) c where c like 'statement_timeout=%');
  assert others is null, 'other functions carry a statement limit: ' || others;

  t0 := clock_timestamp();
  v := public.export_for_report(s, 'figures', '{}');
  assert v ? 'airlines', 'the figures came back without their airlines';
  assert clock_timestamp() - t0 < interval '30 seconds', 'the figures took 30 seconds or more on the copy';

  raise notice 'figures timeout: export_for_report has its own 30 s limit (search_path kept), no other function has one, and the figures came back in % ms on the copy',
    round(extract(epoch from clock_timestamp() - t0) * 1000);
end
$test$;

-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and compared
-- afterwards by database/tests/clean_up_test.sql (the clean-up, #18 build pull request 14):
--   clean_up_aircraft: each aircraft's place in the old planner's two lists (aircraft.extra tails_index and
--     deliveries_index), its tail notes (extra.tail), status and delivery, so the test can show the planner's lists are
--     the same without them;
--   clean_up_outputs: the captured figures for every airline (export_for_report('figures')'s document, from
--     private.fig_export()) at one moment, kept with it, and each loads day of the last two weeks as the old planner read
--     it (planner_loads_get()), while it is there;
--   clean_up_archive: each archived table's manifest for last month (private.archive_manifest(): its layout, rows and
--     checksum), so the test can show the archive still runs and keeps its layout.
-- Nothing is printed.
create table rehearsal_before.clean_up_aircraft as
  select a.id, a.airline_id, a.status, a.delivery_at,
         a.extra ? 'tails_index' as on_tails, (a.extra ->> 'tails_index')::int as tails_place,
         a.extra ? 'deliveries_index' as on_deliveries, a.extra -> 'tail' as tail
    from public.aircraft a;

create table rehearsal_before.clean_up_outputs (name text primary key, value jsonb);
do $$
declare w bigint := (select x.id from public.worlds x where x.is_default);
  v_at timestamptz := date_trunc('minute', coalesce((select max(r.captured_at) from public.game_capture_raw r), now())) + interval '1 hour';
  v_today date := (now() at time zone 'UTC')::date;
begin
  insert into rehearsal_before.clean_up_outputs (name, value) values
    ('as_of', to_jsonb(v_at)),
    ('figures', private.fig_export(w, v_at)),
    -- whether the age condition's setting (20261016120000) was there before the pending changes: if not, the figures
    -- are saved without it, and the clean-up test puts the age at 0 days to compare them
    ('new_route_days_set', to_jsonb(exists (select 1 from public.settings s where s.key = 'growth_new_route_days')));
  if to_regprocedure('public.planner_loads_get(bigint)') is not null then
    execute $q$
      insert into rehearsal_before.clean_up_outputs (name, value)
      select 'loads', coalesce(jsonb_object_agg(d.key, d.value), '{}'::jsonb)
        from public.planner_loads_get($1) g cross join lateral jsonb_each(g.json::jsonb) d
       where d.key::date between $2 - 13 and $2$q$ using w, v_today;
  end if;
end
$$;

create table rehearsal_before.clean_up_archive as
  select t.table_name, private.archive_manifest((date_trunc('month', now() at time zone 'UTC') - interval '1 month')::date, t.table_name) as manifest
    from private.archive_tables() t;

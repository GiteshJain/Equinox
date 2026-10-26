-- The clean-up (#18 build pull request 14; spec docs/specs/2026-10-14-clean-up.md): the old planner's adapter and its
-- tables are gone, the leftovers in the data cleared, and nothing the planner, the website, the figures or the archive
-- give has changed. Run by database/rehearse.sh on the copy of last night's backup, after the new migrations (both files:
-- the one Claude applies and the removals Gitesh runs), inside a transaction that is rolled back. Compares with what
-- database/tests/before/clean_up_before.sql saved before them. A failed check stops with an error that says which
-- (counts, ids and keys, never figures).
--   1. Gone: the tables planner_state, planner_loads, planner_meta, planner_data, game_loads_before_13 and
--      backup_runs_before_13, the view adapter_check_days, and the adapter's functions. loads_by_day() is there, staff
--      only, runs as owner with an empty search path.
--   2. The leftovers: no aircraft keeps a place in the old lists or an old delivery item, no plan card, to-do or fare
--      plan keeps an old field; every aircraft keeps its tail notes. On the night it runs (the copy still had the
--      places): Tails' list (status active) is the old tails list and the deliveries board (a delivery, not retired) the
--      old deliveries list, aircraft by aircraft; how many aircraft lost a delivery the old list didn't hold, and how many
--      tails now stand in another place in their airline's list, are printed.
--   3. The figures: export_for_report('figures')'s document for every airline at the same moment is exactly as before
--      (the UTC fix moves nothing while no airport has a correction; how many have one is printed), apart from the
--      latest verdicts the capture checks (#21) added to capture_status(), and with the payments the pilot-training
--      re-sort named (20261015200000) given their kinds from before back, since moving those figures is its purpose
--      (pilot_training_test.sql checks it; the rehearsal's figures-moved artifact says by how much). With a correction
--      put on an airline's home airport here, each of its payments moves by exactly that much (private.fig_events()).
--   4. Loads by hand: loads_by_day() gives each day of the last two weeks as the old planner read it
--      (planner_loads_get(), saved before): the same loads, complete marks, capture marks and saved times.
--   5. The archive: archive_due() runs, and every archived table's manifest for last month has the same layout, rows
--      and checksum as before.

-- every "up_to" key, at any depth (the cash forecast's up to, 20261026140000), for comparing with figures from before it
create or replace function pg_temp.without_up_to(j jsonb) returns jsonb language sql immutable as $f$
  select case jsonb_typeof(j)
           when 'object' then coalesce((select jsonb_object_agg(k, pg_temp.without_up_to(v)) from jsonb_each(j) e(k, v) where k <> 'up_to'), '{}'::jsonb)
           when 'array' then coalesce((select jsonb_agg(pg_temp.without_up_to(v) order by i) from jsonb_array_elements(j) with ordinality e(v, i)), '[]'::jsonb)
           else j end
$f$;

do $test$
declare
  w bigint := (select id from public.worlds where is_default);
  bad text; n int; n2 int; n3 int; v_at timestamptz; a jsonb; b jsonb; v_al bigint; v_code text; v_off numeric;
  v_strict boolean;
begin
  -- ---------------------------------------------------------------- 1. gone, and what replaces them
  select string_agg(x, ', ') into bad from unnest(array['public.planner_state', 'public.planner_loads', 'public.planner_meta',
    'public.planner_data', 'public.game_loads_before_13', 'public.backup_runs_before_13', 'public.adapter_check_days']) x
   where to_regclass(x) is not null;
  assert bad is null, 'still there: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname in ('public', 'private')
     and p.proname in ('planner_state_get', 'planner_state_put', 'planner_state_version', 'planner_loads_get', 'save_loads',
                       'planner_item_put', 'planner_item_delete', 'export_planner_data', 'apply_loads_from_capture', 'loads_day_captured',
                       'freeze_planner_state', 'unfreeze_planner_state', 'planner_frozen', 'adapter_clean_days', 'adapter_mirror_state',
                       'adapter_mirror_loads', 'load_planner', 'planner_apply', 'loads_mirror_days', 'fig_eq_off', 'touch_updated_at');
  assert bad is null, 'still there: ' || bad;
  assert has_function_privilege('authenticated', 'public.loads_by_day(bigint, date, date)', 'execute')
     and not has_function_privilege('anon', 'public.loads_by_day(bigint, date, date)', 'execute'),
    'loads_by_day() isn''t for signed-in accounts only';
  assert (select p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'public.loads_by_day(bigint, date, date)'::regprocedure), 'loads_by_day() doesn''t run as owner with an empty search path';

  -- ---------------------------------------------------------------- 2. the leftovers
  select count(*) into n from public.aircraft a where a.extra ?| array['tails_index', 'deliveries_index', 'delivery'];
  assert n = 0, format('%s aircraft keep a place in the old lists or an old delivery item', n);
  select (select count(*) from public.plan_cards x where x.extra <> '{}'::jsonb) + (select count(*) from public.todos x where x.extra <> '{}'::jsonb)
       + (select count(*) from public.fare_plan x where x.extra <> '{}'::jsonb) into n;
  assert n = 0, format('%s plan cards, to-dos or fare plans keep an old field', n);
  select count(*) into n from rehearsal_before.clean_up_aircraft o join public.aircraft a on a.id = o.id
   where o.tail is not null and a.extra -> 'tail' is distinct from o.tail;
  assert n = 0, format('%s aircraft lost their tail notes', n);
  v_strict := exists (select 1 from rehearsal_before.clean_up_aircraft o where o.on_tails or o.on_deliveries);
  if v_strict then
    select string_agg(o.id::text, ', ') into bad from rehearsal_before.clean_up_aircraft o join public.aircraft a on a.id = o.id
     where o.on_tails <> (a.status = 'active');
    assert bad is null, 'Tails'' list isn''t the old tails list for aircraft: ' || bad;
    select string_agg(o.id::text, ', ') into bad from rehearsal_before.clean_up_aircraft o join public.aircraft a on a.id = o.id
     where o.on_deliveries <> (a.delivery_at is not null and a.status <> 'retired');
    assert bad is null, 'the deliveries board isn''t the old deliveries list for aircraft: ' || bad;
    select count(*) into n2 from rehearsal_before.clean_up_aircraft o join public.aircraft a on a.id = o.id
     where o.delivery_at is not null and a.delivery_at is null;
    select count(*) into n3 from (
      select o.id, row_number() over (partition by o.airline_id order by o.tails_place, o.id) as was,
             row_number() over (partition by o.airline_id order by o.id) as now
        from rehearsal_before.clean_up_aircraft o join public.aircraft a on a.id = o.id where o.on_tails) x
     where x.was <> x.now;
    raise notice 'the old lists: Tails and the deliveries board hold the same aircraft as before (% tails, % deliveries); % aircraft lost a delivery the old list didn''t hold; % tails stand in another place in their airline''s list (by when they were added)',
      (select count(*) from rehearsal_before.clean_up_aircraft where on_tails), (select count(*) from rehearsal_before.clean_up_aircraft where on_deliveries), n2, n3;
  else
    raise notice 'the old lists: the copy had no places in them any more (cleaned up already), so only the clearing was checked';
  end if;

  -- ---------------------------------------------------------------- 3. the figures
  v_at := (select (value #>> '{}')::timestamptz from rehearsal_before.clean_up_outputs where name = 'as_of');
  b := (select value from rehearsal_before.clean_up_outputs where name = 'figures');
  -- the pilot-training re-sort (20261015200000) moves the figures on purpose (the rehearsal's figures-moved artifact
  -- says how): the payments it named get their kind from before the changes back here (rolled back with the test), so
  -- everything else must still be exactly as before. Once it is live, the copy has nothing for it to name.
  if to_regclass('rehearsal_before.payment_kinds') is not null then
    update public.game_payments p set kind = k.kind
      from rehearsal_before.payment_kinds k where k.id = p.id and p.kind is distinct from k.kind;
  end if;
  -- the age condition (20261016120000, new routes aren't judged for a week) moves the marks of routes launched in the last
  -- 7 days on purpose (new_route_age_test.sql checks it): with its setting at 0 days nothing counts as new, so while it is
  -- pending (the copy didn't have the setting before the changes) everything must still be exactly as before. Once it is
  -- live, the figures before carry the condition too and nothing is changed here.
  if not coalesce((select (value #>> '{}')::boolean from rehearsal_before.clean_up_outputs where name = 'new_route_days_set'), true) then
    update public.settings set value = '0'::jsonb where key = 'growth_new_route_days';
  end if;
  -- add or raise by aircraft hour (20261017180000) moves the sold-out routes' marks on purpose (add_or_raise_test.sql
  -- checks it): while it is pending (route profit's definition before the changes has no aircraft hours), that
  -- definition is put back here (rolled back with the test), so everything else must still be exactly as before. Once
  -- it is live, the definition before carries it too and nothing is changed here.
  if (select value #>> '{}' from rehearsal_before.clean_up_outputs where name = 'route_profit_def') not like '%aircraft_hours%' then
    execute (select value #>> '{}' from rehearsal_before.clean_up_outputs where name = 'route_profit_def');
  end if;
  -- the default line's variants (20261019180000) add types every airline may buy and correct the deposits and cruise
  -- speeds on purpose (default_line_variants_test.sql checks them): while it is pending (the copy had fewer
  -- aircraft types before), the types' figures and who may buy which are put back here (rolled back with the test), so everything else
  -- must still be exactly as before. Once it is live, the figures before carry it too and nothing is changed here.
  if to_regclass('rehearsal_before.clean_up_types') is not null
     and (select count(*) from public.aircraft_types) > (select count(*) from rehearsal_before.clean_up_types) then
    delete from public.airline_order_cabins x where not exists (select 1 from rehearsal_before.clean_up_own_cabins b where b.airline_id = x.airline_id and b.aircraft_type_id = x.aircraft_type_id);
    delete from public.airline_aircraft_types x where not exists (select 1 from rehearsal_before.clean_up_may_buy b where b.airline_id = x.airline_id and b.aircraft_type_id = x.aircraft_type_id);
    update public.aircraft_types t set price = b.price, seats_max = b.seats_max, cruise_kmh = b.cruise_kmh, order_config_id = b.order_config_id
      from rehearsal_before.clean_up_types b where b.id = t.id;
  end if;
  a := private.fig_export(w, v_at);
  -- the capture checks (#21, build 20261014220000) added each airline's latest verdicts to capture_status() on purpose:
  -- they're left out here, so the rest must still be exactly as before. Left out of both sides: once 20261014220000 is
  -- live, the copy's figures before the pending changes carry them too (and a pending capture check may judge anew)
  a := jsonb_set(a, '{capture_status,airlines}', coalesce((select jsonb_agg(x - array['last_at', 'verdict', 'verdict_words', 'verdict_at', 'verdict_day', 'verdicts'] order by i)
                                                            from jsonb_array_elements(a #> '{capture_status,airlines}') with ordinality e(x, i)), '[]'::jsonb));
  if b #> '{capture_status,airlines}' is not null then
    b := jsonb_set(b, '{capture_status,airlines}', coalesce((select jsonb_agg(x - array['last_at', 'verdict', 'verdict_words', 'verdict_at', 'verdict_day', 'verdicts'] order by i)
                                                              from jsonb_array_elements(b #> '{capture_status,airlines}') with ordinality e(x, i)), '[]'::jsonb));
  end if;
  -- the weekly report's three biggest competitors (20261022040000) add each airline's competitors, self and scans to the
  -- figures on purpose (competition_test.sql and report_competitors_test.sql check them): while it is pending (the figures
  -- before have none), they're left out here, so the rest must still be exactly as before. Once it is live, the figures
  -- before carry them too and nothing is left out.
  if not exists (select 1 from jsonb_array_elements(b -> 'airlines') x where x ? 'competitors') then
    a := jsonb_set(a, '{airlines}', coalesce((select jsonb_agg(x - array['competitors', 'self', 'scans'] order by i)
                                              from jsonb_array_elements(a -> 'airlines') with ordinality e(x, i)), '[]'::jsonb));
  end if;
  -- rivals' fleets (20261023120000) add each airline's order_flags and each competitor's fleet to the figures on purpose
  -- (rival_fleets_test.sql checks them): while it is pending (the figures before have no order_flags), exactly those are
  -- left out here, so the rest must still be exactly as before. Once it is live, the figures before carry them too and
  -- nothing is left out.
  if not exists (select 1 from jsonb_array_elements(b -> 'airlines') x where x ? 'order_flags') then
    a := jsonb_set(a, '{airlines}', coalesce((select jsonb_agg(
                                                case when x ? 'competitors' and jsonb_typeof(x -> 'competitors') = 'array'
                                                     then jsonb_set(x - 'order_flags', '{competitors}',
                                                                    coalesce((select jsonb_agg(c - 'fleet' order by j)
                                                                                from jsonb_array_elements(x -> 'competitors') with ordinality f(c, j)), '[]'::jsonb))
                                                     else x - 'order_flags' end order by i)
                                              from jsonb_array_elements(a -> 'airlines') with ordinality e(x, i)), '[]'::jsonb));
  end if;
  -- rivals' connections (20261023140000) add each competitor's connecting_weekly, connecting_pairs and connecting_via to
  -- the figures on purpose (rival_connections_test.sql checks them): while it is pending (no competitor in the figures
  -- before has connecting_weekly), exactly those are left out here, so the rest must still be exactly as before. Once it
  -- is live, the figures before carry them too and nothing is left out.
  if not exists (select 1 from jsonb_array_elements(b -> 'airlines') x
                  cross join lateral jsonb_array_elements(case when jsonb_typeof(x -> 'competitors') = 'array' then x -> 'competitors' else '[]'::jsonb end) c
                  where c ? 'connecting_weekly') then
    a := jsonb_set(a, '{airlines}', coalesce((select jsonb_agg(
                                                case when x ? 'competitors' and jsonb_typeof(x -> 'competitors') = 'array'
                                                     then jsonb_set(x, '{competitors}',
                                                                    coalesce((select jsonb_agg(c - array['connecting_weekly', 'connecting_pairs', 'connecting_via'] order by j)
                                                                                from jsonb_array_elements(x -> 'competitors') with ordinality f(c, j)), '[]'::jsonb))
                                                     else x end order by i)
                                              from jsonb_array_elements(a -> 'airlines') with ordinality e(x, i)), '[]'::jsonb));
  end if;
  -- the cash forecast's up to (20261026140000) adds up_to to every cash forecast and next order in the figures on purpose
  -- (captured_figures_test.sql checks it): while it is pending (the figures before have none), exactly those are left
  -- out here, so the rest must still be exactly as before. Once it is live, the figures before carry it too.
  if b::text not like '%"up_to"%' then
    a := pg_temp.without_up_to(a);
  end if;
  if a is distinct from b then
    select string_agg(k, ', ' order by k) into bad
      from (select k from jsonb_object_keys(a) k union select k from jsonb_object_keys(b) k) x(k) where a -> k is distinct from b -> k;
    raise exception 'the captured figures as of % differ from before at: %', v_at, coalesce(bad, 'the whole document');
  end if;
  select count(*) into n from public.world_airports x where x.world_id = w and x.utc_offset_override is not null;
  -- a correction on an airline's home airport moves each of its payments by exactly that much
  select e.airline_id, h.code into v_al, v_code
    from private.fig_events(w, v_at) e
    join public.airlines al on al.id = e.airline_id
    left join public.airline_bases mb on mb.airline_id = al.id and mb.is_main
    cross join lateral (select coalesce(mb.airport_code, al.home_airport_code) as code) h
   where h.code is not null
   order by e.airline_id limit 1;
  if v_al is null then
    raise notice 'the figures: exactly as before as of % (% airports with a correction); no payments to try a correction on', v_at, n;
  else
    v_off := coalesce(private.airport_offset_min(w, v_code), 0) / 60.0;
    create temporary table t_events on commit drop as select x.at, x.descr, x.event_date, x.event_time from private.fig_events(w, v_at, v_al) x;
    insert into public.world_airports as x (world_id, airport_code, utc_offset_override) values (w, v_code, v_off + 1)
    on conflict (world_id, airport_code) do update set utc_offset_override = excluded.utc_offset_override;
    select count(*), count(*) filter (where e.at = o.at - interval '1 hour') into n2, n3
      from t_events o join private.fig_events(w, v_at, v_al) e
        on (e.descr, e.event_date, e.event_time) is not distinct from (o.descr, o.event_date, o.event_time);
    assert n2 > 0 and n3 = n2, format('with an hour''s correction on %s, %s of %s payments moved by exactly an hour', v_code, n3, n2);
    raise notice 'the figures: exactly as before as of % (% airports with a correction); with an hour''s correction on an airline''s home airport, all % of its payments move by an hour',
      v_at, n, n2;
  end if;

  -- ---------------------------------------------------------------- 4. loads by hand
  b := (select value from rehearsal_before.clean_up_outputs where name = 'loads');
  if b is null then
    raise notice 'loads by hand: the copy had no planner_loads_get() any more, so nothing to compare';
  else
    a := public.loads_by_day(w, (now() at time zone 'UTC')::date - 13, (now() at time zone 'UTC')::date);
    select string_agg(d, ', ' order by d) into bad
      from (select k as d from jsonb_object_keys(a) k union select k from jsonb_object_keys(b) k) x
     where (coalesce(a -> d -> 'f', '{}') <> '{}' or coalesce(b -> d -> 'f', '{}') <> '{}'
            or coalesce((a -> d ->> 'done')::boolean, false) or coalesce((b -> d ->> 'done')::boolean, false))
       and (coalesce(a -> d -> 'f', '{}') is distinct from coalesce(b -> d -> 'f', '{}')
            or coalesce((a -> d ->> 'done')::boolean, false) is distinct from coalesce((b -> d ->> 'done')::boolean, false)
            or (a -> d -> 'savedAt') is distinct from (b -> d -> 'savedAt'));
    assert bad is null, 'loads_by_day() gives these days otherwise than planner_loads_get() did (loads, complete mark or saved time): ' || bad;
    -- the capture mark only names how a complete day is shown (captured, or entered by hand): the figures' rule (a capture
    -- with loads reached the day) can differ from the old document's (any capture of an airline flying it), so counted
    select count(*) into n from (select k as d from jsonb_object_keys(a) k) x
     where ((a -> d ->> 'done')::boolean or (b -> d ->> 'done')::boolean) and (a -> d ->> 'source') is distinct from (b -> d ->> 'source');
    raise notice 'loads by hand: loads_by_day() gives the last two weeks as the old planner read them (% days with loads or marked complete, % flights); % complete days marked captured on one side only',
      (select count(*) from jsonb_each(a) d where d.value -> 'f' <> '{}' or (d.value ->> 'done')::boolean),
      (select count(*) from jsonb_each(a) d, jsonb_object_keys(d.value -> 'f') f), n;
  end if;

  -- ---------------------------------------------------------------- 5. the archive
  perform * from private.archive_due();
  select string_agg(o.table_name, ', ') into bad
    from rehearsal_before.clean_up_archive o
    cross join lateral (select private.archive_manifest(((o.manifest ->> 'month') || '-01')::date, o.table_name) as m) x
   where (x.m -> 'layout', x.m -> 'rows', x.m -> 'checksum') is distinct from (o.manifest -> 'layout', o.manifest -> 'rows', o.manifest -> 'checksum');
  assert bad is null, 'the archive''s manifest for last month changed (layout, rows or checksum) for: ' || bad;
  raise notice 'the archive: archive_due() runs, and last month''s manifest of each of the % archived tables has the same layout, rows and checksum as before',
    (select count(*) from rehearsal_before.clean_up_archive);
end
$test$;

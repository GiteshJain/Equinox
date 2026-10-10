-- The adapter's write side, section by section (#13 build, pull request 5; design §8, §9). Run by database/rehearse.sh
-- on the copy of last night's backup, after the new migrations, inside a transaction that is rolled back. A failed check
-- stops with an error that says where (paths and counts, never values).
--   1. Round trip: planner_state_put(planner_state_get()) changes no rows and writes no change-log row.
--   2. One item of each section of design §8's table changed through planner_state_put(), and read back through
--      planner_state_get() unchanged (only the differences design §9 allows): an aircraft (a tail and a delivery), a
--      frequency including its return day, a plan card's legs, a to-do and its steps, a route added and a route edit,
--      money spent and a growth move, an interline, a monthly check, a dismissal, ref values (a constant and a hub's
--      banks) and a typed cash figure. Every change-log row it wrote names actor planner and the tab.
--   3. The whole document saved into emptied planner tables gives it back, so every writer is tried on real data.

create function pg_temp.differs(p_old jsonb, p_new jsonb) returns text language sql as $$
  select string_agg(x.place || ' ×' || x.n, ', ' order by x.place)
    from (select private.planner_place(d.path) as place, count(*) as n from private.planner_json_diff(p_old, p_new) d
           where d.kind = 'differs' group by 1) x
$$;
-- what the rows keep in extra (beyond each aircraft's place in the lists): a save must not need it for what the
-- columns hold, or a writer that drops something would still read back unchanged
create function pg_temp.extras() returns table (section text, item text, key text) language sql as $$
  select 'tails', a.registration, e.key from public.aircraft a, jsonb_each(coalesce(a.extra -> 'tail', '{}'::jsonb)) e
  union all select 'deliveries', a.registration, e.key from public.aircraft a, jsonb_each(coalesce(a.extra -> 'delivery', '{}'::jsonb)) e
  union all select 'freqs', r.legacy_key, e.key from public.rotations r, jsonb_each(r.extra) e
  union all select 'plans', a.registration, e.key from public.plan_cards p join public.aircraft a on a.id = p.aircraft_id, jsonb_each(p.extra) e
  union all select 'todos', t.legacy_key, e.key from public.todos t, jsonb_each(t.extra) e
  union all select 'farePlan', f.legacy_key, e.key from public.fare_plan f, jsonb_each(f.extra) e
$$;
create function pg_temp.extras_new(p_since jsonb) returns text language sql as $$
  select string_agg(x.section || '.' || x.key || ' (' || x.item || ')', ', ' order by x.section, x.key, x.item)
    from (select * from pg_temp.extras() except select s ->> 0, s ->> 1, s ->> 2 from jsonb_array_elements(p_since) s) x
$$;
create function pg_temp.extras_now() returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_array(section, item, key)), '[]'::jsonb) from pg_temp.extras()
$$;
create temporary table t_doc (k text primary key, v jsonb) on commit drop;

-- ---------------------------------------------------------------- 1. round trip
do $test$
declare v_log bigint := coalesce((select max(id) from public.change_log), 0); r jsonb; t text; n bigint; bad text;
begin
  r := public.planner_state_put(public.planner_state_get() ->> 'json', null, null, 'round-trip-tab');
  assert (r ->> 'applied')::int = 0 and (r ->> 'skipped')::int = 0 and not (r ->> 'reload')::boolean,
    format('the round trip wrote or skipped items: applied %s, skipped %s', r ->> 'applied', r ->> 'skipped');
  assert not exists (select 1 from public.change_log where id > v_log), 'the round trip wrote change-log rows';
  for t in select unnest(array['airline_bases', 'world_airports', 'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps',
                               'markets', 'service_profiles', 'routes', 'rotations', 'flight_legs', 'plan_cards', 'plan_card_legs',
                               'todos', 'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements',
                               'monthly_checks', 'dismissals', 'cash_entries', 'settings', 'world_rules', 'airports', 'countries']) loop
    execute format('select count(*) from public.%I where xmin = pg_current_xact_id()::xid', t) into n;
    if n > 0 then bad := concat_ws(', ', bad, t || ' ' || n); end if;
  end loop;
  assert bad is null, 'the round trip changed rows: ' || bad;
  raise notice 'round trip: planner_state_put(planner_state_get()) wrote no row and no change-log row';
end
$test$;

-- ---------------------------------------------------------------- 2. one item of each section
do $test$
declare d jsonb := (public.planner_state_get() ->> 'json')::jsonb; v_log bigint := coalesce((select max(id) from public.change_log), 0);
  r jsonb; g jsonb; bad text; i int; k text; al text; hub text; dest text; reg text; fid text; v jsonb; leg1 record; leg2 record;
  v_tables text; v_extras jsonb := pg_temp.extras_now();
begin
  -- an aircraft: the first tail's maintenance note and the first delivery's plan note
  assert jsonb_array_length(d -> 'tails') > 0 and jsonb_array_length(d -> 'deliveries') > 0, 'the copy has no tails or deliveries';
  d := jsonb_set(d, '{tails,0,maint}', '"adapter section test"');
  d := jsonb_set(d, '{deliveries,0,plan}', '"adapter section test"');
  -- a frequency including its return day: Mon, Wed, Fri, out 21:00 and in 23:30 local, back at 01:00, which is before the
  -- arrival, so the return leaves the next day (the old planner's rule, design §4)
  fid := d -> 'freqs' -> 0 ->> 'id';
  d := jsonb_set(d, '{freqs,0}', (d -> 'freqs' -> 0) || '{"days": "135", "depHub": "21:00", "arrDest": "23:30", "depDest": "01:00", "arrHub": "03:30"}');
  -- a plan card's legs: the first card's first leg moves 15 minutes later (departure and arrival), and a leg is added
  reg := (select min(x) from jsonb_object_keys(d -> 'plans') x
           where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(d #> array['plans', x, 'legs']) = 'array' then d #> array['plans', x, 'legs'] end) l
                          where private.clock_min(l ->> 'dep') is not null and private.clock_min(l ->> 'arr') is not null));
  assert reg is not null, 'the copy has no plan card with timed legs';
  v := d #> array['plans', reg, 'legs'];
  i := (select (e.ord - 1)::int from jsonb_array_elements(v) with ordinality e(l, ord)
         where private.clock_min(e.l ->> 'dep') is not null and private.clock_min(e.l ->> 'arr') is not null order by e.ord limit 1);
  v := jsonb_set(v, array[i::text, 'dep'], to_jsonb(to_char(make_time(((private.clock_min(v -> i ->> 'dep') + 15) % 1440) / 60, ((private.clock_min(v -> i ->> 'dep') + 15) % 1440) % 60, 0), 'HH24:MI')));
  v := jsonb_set(v, array[i::text, 'arr'], to_jsonb(to_char(make_time(((private.clock_min(v -> i ->> 'arr') + 15) % 1440) / 60, ((private.clock_min(v -> i ->> 'arr') + 15) % 1440) % 60, 0), 'HH24:MI')));
  v := v || jsonb_build_array((v -> i) || '{"no": "9999"}');
  d := jsonb_set(d, array['plans', reg, 'legs'], v);
  -- a to-do and its steps
  d := jsonb_set(d, '{todos,0}', (d -> 'todos' -> 0) || '{"title": "adapter section test", "items": ["step one", "step two"]}');
  -- a route added, and a route edit on a research route nothing edits yet
  select al2.planner_name, r2.hub_code into al, hub from public.routes r2 join public.airlines al2 on al2.id = r2.airline_id
   where r2.source = 'research' and not r2.removed and r2.removed_note is null and r2.city_override is null and r2.distance_override_km is null
     and r2.market_override_id is null and r2.stars_override is null and r2.cabin_choice is null
   order by r2.id limit 1;
  select r2.dest_code into dest from public.routes r2 join public.airlines al2 on al2.id = r2.airline_id
   where al2.planner_name = al and r2.hub_code = hub and r2.source = 'research' and not r2.removed and r2.removed_note is null
     and r2.city_override is null and r2.cabin_choice is null order by r2.id limit 1;
  assert dest is not null, 'the copy has no research route to edit';
  d := jsonb_set(d, '{routeEdits}', coalesce(d -> 'routeEdits', '{}') || jsonb_build_object(al || '|' || hub || '|' || dest,
                 '{"removed": true, "note": "adapter section test"}'::jsonb));
  k := (select a.code from public.airports a where a.code not in (select r2.dest_code from public.routes r2 join public.airlines al2 on al2.id = r2.airline_id
                                                                    where al2.planner_name = al and r2.hub_code = hub)
                                               and a.code <> hub and a.utc_offset is not null order by a.code limit 1);
  d := jsonb_set(d, '{routesAdded}', coalesce(d -> 'routesAdded', '[]') || jsonb_build_array(jsonb_build_array(al, hub, k, 'Adapter test', 'ZZ', 1234,
                 (select m.name from public.markets m join public.airlines a2 on a2.id = m.airline_id where a2.planner_name = al order by m.id limit 1), 3)));
  -- money spent and a growth move
  d := jsonb_set(d, '{capex}', coalesce(d -> 'capex', '[]') || jsonb_build_array(jsonb_build_object('date', '2026-10-10', 'airline', al,
                 'amountM', 1.25, 'kind', 'loss', 'note', 'adapter section test')));
  d := jsonb_set(d, '{growthLog}', coalesce(d -> 'growthLog', '[]') || jsonb_build_array(jsonb_build_object('date', '2026-10-10',
                 'airline', al, 'move', 'feeder', 'note', 'adapter section test')));
  -- an interline, a monthly check, a dismissal
  d := jsonb_set(d, '{interline}', coalesce(d -> 'interline', '{}') || jsonb_build_object(al || '|ZZ',
                 '{"status": "declined", "partner": "Adapter test (1)", "date": "2026-10-10", "notes": "adapter section test"}'::jsonb));
  d := jsonb_set(d, '{monthly}', coalesce(d -> 'monthly', '{}') || jsonb_build_object('Equinox',
                 coalesce(d #> '{monthly,Equinox}', '{}') || '{"adapter-test": "2026-10-10"}'::jsonb));
  d := jsonb_set(d, '{dismissed}', coalesce(d -> 'dismissed', '{}') || '{"adapter|test": "2026-10-10"}');
  -- ref values: a constant and a hub's banks
  d := jsonb_set(d, '{ref,consts,turnMargin}', '13');
  d := jsonb_set(d, '{ref,hubs,0,banks}', '["07:00", "", "13:30", ""]');
  -- a typed cash figure, on a date the capture doesn't have
  d := jsonb_set(d, '{cash}', coalesce(d -> 'cash', '{}') || jsonb_build_object('2026-09-21', jsonb_build_object(al, 123.45)));

  r := public.planner_state_put(d::text, (extract(epoch from clock_timestamp()) * 1000)::bigint, null, 'section-test-tab');
  assert (r ->> 'skipped')::int = 0, 'the save skipped items: ' || (r -> 'skipped_items')::text;
  g := (public.planner_state_get() ->> 'json')::jsonb;
  bad := pg_temp.differs(d, g);
  assert bad is null, 'after the save, planner_state_get() differs from what was saved at: ' || bad;
  bad := pg_temp.extras_new(v_extras);
  assert bad is null, 'the save kept in extra what the columns should hold: ' || bad;

  -- the return leaves the day after the outbound lands (local days at each end)
  select * into leg1 from public.flight_legs_local l join public.rotations r2 on r2.id = l.rotation_id where r2.legacy_key = fid and l.leg_no = 1;
  select * into leg2 from public.flight_legs_local l join public.rotations r2 on r2.id = l.rotation_id where r2.legacy_key = fid and l.leg_no = 2;
  assert leg1.days_local = '{1,3,5}' and leg1.dep_local = '21:00' and leg1.arr_local = '23:30',
    format('frequency %s: the outbound reads back %s %s-%s, not Mon, Wed, Fri 21:00-23:30', fid, leg1.days_local, leg1.dep_local, leg1.arr_local);
  assert leg2.dep_local = '01:00' and leg2.arr_local = '03:30'
     and leg2.days_local = private.shift_weekdays('{1,3,5}', leg1.arr_local_day_offset + 1),
    format('frequency %s: the return reads back %s %s-%s, not the day after the outbound lands', fid, leg2.days_local, leg2.dep_local, leg2.arr_local);

  -- every change-log row names the planner and the tab
  assert not exists (select 1 from public.change_log where id > v_log and (actor <> 'planner' or actor_detail is distinct from 'section-test-tab')),
    'a change-log row of the save doesn''t name actor planner and the tab';
  select string_agg(t.table_name || ' ' || t.n, ', ' order by t.table_name) into v_tables
    from (select table_name, count(*) as n from public.change_log where id > v_log group by 1) t;
  assert v_tables is not null, 'the save wrote no change-log row';
  raise notice 'each section: % items changed through planner_state_put() and read back unchanged, nothing new kept in extra (the return the next day); logged as planner: %',
    r ->> 'applied', v_tables;
  insert into t_doc values ('changed', d), ('extras', pg_temp.extras_now());
end
$test$;

-- ---------------------------------------------------------------- 3. the whole document into emptied tables
do $test$
declare d jsonb := (select v from t_doc where k = 'changed'); w bigint := (select id from public.worlds where is_default); r jsonb; bad text;
  t0 timestamptz;
begin
  perform set_config('equinox.change_log', 'off', true), set_config('equinox.actor', 'migration', true);
  delete from public.load_entries; delete from public.load_days; delete from public.cash_entries;
  delete from public.dismissals; delete from public.monthly_checks; delete from public.interline_agreements;
  delete from public.fare_plan; delete from public.spending_log; delete from public.growth_log; delete from public.todos;
  delete from public.plan_cards; delete from public.rotations; delete from public.aircraft_cabin_keeps;
  update public.game_flights set aircraft_id = null, route_id = null; update public.game_payments set aircraft_id = null;
  delete from public.aircraft; delete from public.routes; delete from public.markets; delete from public.service_profiles;
  update public.airline_bases set parent_base_id = null; delete from public.airline_bases;
  delete from public.airline_aircraft_types; delete from public.cabin_configs; delete from public.aircraft_types;
  delete from public.world_airports;
  perform set_config('equinox.change_log', '', true), set_config('equinox.actor', '', true);
  t0 := clock_timestamp();
  r := private.planner_apply(w, d, 'mirror', null, null, 'planner', 'whole-document test');
  bad := pg_temp.differs(d, (public.planner_state_get() ->> 'json')::jsonb);
  assert bad is null, 'the whole document saved into emptied tables doesn''t come back: ' || bad;
  -- and it needs exactly the extras the loader needed, no more
  bad := pg_temp.extras_new((select v from t_doc where k = 'extras'));
  assert bad is null, 'the whole document saved into emptied tables kept more in extra than the loader did: ' || bad;
  assert jsonb_array_length(pg_temp.extras_now()) = jsonb_array_length((select v from t_doc where k = 'extras')),
    'the whole document saved into emptied tables kept less in extra than the loader did';
  raise notice 'the whole document saved into emptied tables comes back unchanged, with the loader''s extras (%): % items, % ms',
    coalesce((select string_agg(x ->> 0 || '.' || (x ->> 2), ', ') from jsonb_array_elements((select v from t_doc where k = 'extras')) x), 'none'),
    r ->> 'applied', round(extract(epoch from clock_timestamp() - t0) * 1000);
end
$test$;

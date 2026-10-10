-- The planner's data load on the frozen sample (#13 build, pull request 4; design §9, "Proving old and new are the
-- same"). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a
-- transaction that is rolled back. A failed check stops with an error that says where (paths and counts, never values).
-- The copy is emptied (the planner tables back to their reference rows, the old storage and the capture tables
-- cleared), then tests/fixtures/sample_2026-10-08.json.gz is loaded the way the old planner and the capture had it:
-- planner_state, planner_loads, planner_data, site_content.mct, and the capture's reads. The sample has money per flight
-- but no statement lines, so game_flights' money comes from its game_flight_pnl rows (design §9), and its loads from
-- its game_loads rows, written at their airline's latest loads capture.
--   1. private.load_planner() and the capture's matching run on it;
--   2. planner_state_get() equals the sample's planner_state, and planner_loads_get() its loads, with only the
--      differences design §9 allows (printed with how often);
--   3. design §4's worked example, Kingfisher's DEL-JFK frequency z5qbaeg, as stored.
\set sample `gzip -dc tests/fixtures/sample_2026-10-08.json.gz`
create temporary table t_sample on commit drop as select :'sample'::jsonb as j;
\unset sample

create function pg_temp.places(p_old jsonb, p_new jsonb) returns table (kind text, place text, n bigint) language sql as $$
  select d.kind,
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(d.path, '\[\d+\]', '[]', 'g'),
           '^(\$\.(plans|cash|fixed7|interline|routeEdits|routeCabin|monthly|dismissed|cabinKeep|ref\.markets|ref\.curfews|ref\.gameLinks|ref\.utcOverrides))\.[^.\[]+', '\1.{}'),
           '^\$\.\d{4}-\d{2}-\d{2}', '$.{day}'), '\.f\..+$', '.f.{flight}'),
         count(*)
    from private.planner_json_differences(p_old, p_new) d
   group by 1, 2
$$;

-- ---------------------------------------------------------------- the copy, emptied, and the sample in its place
do $load$
declare j jsonb := (select j from t_sample); w bigint := (select id from public.worlds where is_default);
begin
  perform set_config('equinox.change_log', 'off', true), set_config('equinox.actor', 'migration', true);
  delete from public.game_statement; delete from public.game_payments; delete from public.game_flights;
  delete from public.game_events; delete from public.game_balance; delete from public.game_pnl; delete from public.game_capture_raw;
  delete from public.load_entries; delete from public.load_days; delete from public.cash_entries;
  delete from public.dismissals; delete from public.monthly_checks; delete from public.interline_agreements;
  delete from public.fare_plan; delete from public.spending_log; delete from public.growth_log; delete from public.todos;
  delete from public.plan_cards; delete from public.rotations; delete from public.aircraft_cabin_keeps; delete from public.aircraft;
  delete from public.routes; delete from public.markets; delete from public.service_profiles;
  update public.airline_bases set parent_base_id = null; delete from public.airline_bases;
  delete from public.airline_aircraft_types; delete from public.cabin_configs; delete from public.aircraft_types;
  delete from public.settings; delete from public.world_rules; delete from public.world_airports;
  update public.airlines set country_code = null;
  delete from public.airports where code not in (select home_airport_code from public.airlines where home_airport_code is not null);
  update public.airports set city = null, country_code = null, lat = null, lon = null, utc_offset = null;
  delete from public.countries;
  delete from public.planner_state; delete from public.planner_loads;
  delete from public.planner_data where key = 'DATA'; delete from public.site_content where key = 'mct';

  insert into public.planner_state (id, json, saved_at) values ('main', (j -> 'planner_state')::text, (j -> 'planner_state' ->> 'savedAt')::bigint);
  insert into public.planner_loads (month, json, saved_at)
  select m ->> 'month', m ->> 'json', (m ->> 'saved_at')::bigint from jsonb_array_elements(j -> 'planner_loads') m;
  insert into public.planner_data (key, value) values ('DATA', j -> 'planner_data');
  insert into public.site_content (key, value) values ('mct', j -> 'site_public' -> 'content' -> 'mct');
  insert into public.game_balance (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
  select w, a.id, a.planner_name, (b ->> 'captured_on')::date, private.capture_day(w, (b ->> 'captured_at')::timestamptz),
         '2800 Bank account', (b ->> 'amount')::numeric, (b ->> 'captured_at')::timestamptz
    from jsonb_array_elements(j -> 'tables' -> 'game_balance') b join public.airlines a on a.world_id = w and a.planner_name = b ->> 'airline';
  insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, debit)
  select w, a.id, a.planner_name, (e ->> 'event_date')::date, e ->> 'event_time', e ->> 'descr', (e ->> 'debit')::numeric
    from jsonb_array_elements(j -> 'tables' -> 'game_events') e join public.airlines a on a.world_id = w and a.planner_name = e ->> 'airline'
  on conflict do nothing;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, rows, captured_at)
  select w, a.id, a.planner_name, r ->> 'kind', '[]'::jsonb, (r ->> 'captured_at')::timestamptz
    from jsonb_array_elements(j -> 'tables' -> 'game_capture_raw') r join public.airlines a on a.world_id = w and a.planner_name = r ->> 'airline';
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, arr_local,
         registration, eco_pct, bus_pct, fst_pct, cargo_pct, eco_pax, eco_seats, bus_pax, bus_seats, fst_pax, fst_seats,
         eco_fare, bus_fare, loads_captured_at)
  select w, a.id, (l ->> 'flight_date')::date, (substring(l ->> 'code' from '(\d+)$'))::int, l ->> 'origin', l ->> 'dest',
         l ->> 'dep_time', l ->> 'arr_time', l ->> 'tail', (l ->> 'eco')::numeric, (l ->> 'bus')::numeric, (l ->> 'fst')::numeric,
         (l ->> 'cargo')::numeric, (l ->> 'eco_pax')::int, (l ->> 'eco_seats')::int, (l ->> 'bus_pax')::int, (l ->> 'bus_seats')::int,
         (l ->> 'fst_pax')::int, (l ->> 'fst_seats')::int, (l ->> 'eco_fare')::numeric, (l ->> 'bus_fare')::numeric,
         (select max((r ->> 'captured_at')::timestamptz) from jsonb_array_elements(j -> 'tables' -> 'game_capture_raw') r
           where r ->> 'airline' = l ->> 'airline' and r ->> 'kind' = 'loads')
    from jsonb_array_elements(j -> 'tables' -> 'game_loads') l join public.airlines a on a.world_id = w and a.planner_name = l ->> 'airline';
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, dep_at,
         maint_registration, statement_pax, pax_income, cargo_income, fuel, onboard, handling, landing, atc, maintenance,
         income_total, cost_total, money_captured_at)
  select w, a.id, (p ->> 'ts')::timestamptz, (p ->> 'blk')::smallint, (p ->> 'routes_n')::smallint,
         split_part(p ->> 'route', '-', 1), split_part(p ->> 'route', '-', 2), (p ->> 'ts')::timestamptz, p ->> 'tail',
         (p ->> 'pax')::int, (p ->> 'pax_income')::numeric, (p ->> 'cargo_income')::numeric, (p ->> 'fuel')::numeric,
         (p ->> 'onboard')::numeric, (p ->> 'handling')::numeric, (p ->> 'landing')::numeric, (p ->> 'atc')::numeric,
         (p ->> 'maintenance')::numeric, (p ->> 'pax_income')::numeric + (p ->> 'cargo_income')::numeric,
         (p ->> 'pax_income')::numeric + (p ->> 'cargo_income')::numeric - (p ->> 'profit')::numeric, (p ->> 'ts')::timestamptz
    from jsonb_array_elements(j -> 'tables' -> 'game_flight_pnl') p join public.airlines a on a.world_id = w and a.planner_name = p ->> 'airline'
   where (p ->> 'routes_n')::int >= 1;
  perform set_config('equinox.change_log', '', true), set_config('equinox.actor', '', true);
end
$load$;

-- ---------------------------------------------------------------- 1 and 2. the load, and the getters against the sample
do $test$
declare w bigint := (select id from public.worlds where is_default); j jsonb := (select j from t_sample);
  v_res jsonb; v_new jsonb; bad text; used text; v_months int;
begin
  v_res := private.load_planner(w);
  perform private.capture_refresh(w);
  perform private.fill_flight_links(w);
  v_new := (public.planner_state_get() ->> 'json')::jsonb;
  select string_agg(place || ' ×' || n, ', ' order by place) into bad from pg_temp.places(j -> 'planner_state', v_new) where kind = 'differs';
  assert bad is null, 'on the sample, planner_state_get() differs from its planner_state at: ' || bad;
  select string_agg(kind || ' ×' || n || ' (' || places || ')', '; ' order by kind) into used
    from (select kind, sum(n) as n, string_agg(place, ', ' order by place) as places from pg_temp.places(j -> 'planner_state', v_new) group by kind) x;
  raise notice 'sample: planner_state_get() equals its planner_state (% tails, % frequencies, % plan cards); allowed differences used: %; kept in extra: %',
    jsonb_array_length(v_new -> 'tails'), jsonb_array_length(v_new -> 'freqs'), (select count(*) from jsonb_object_keys(v_new -> 'plans')),
    coalesce(used, 'none'), (select coalesce(string_agg(k || ' ×' || n, ', '), 'nothing') from jsonb_each_text(v_res -> 'kept in extra') as e(k, n));

  select string_agg(coalesce(o ->> 'month', g.month), ', ') into bad
    from jsonb_array_elements(j -> 'planner_loads') o full join public.planner_loads_get() g on g.month = o ->> 'month'
   where o is null or g.month is null;
  assert bad is null, 'on the sample, planner_loads_get() and its loads don''t have the same months: ' || bad;
  select string_agg(x.place || ' ×' || x.n, ', ' order by x.place) into bad
    from (select p.place, p.n from jsonb_array_elements(j -> 'planner_loads') o join public.planner_loads_get() g on g.month = o ->> 'month'
            cross join lateral pg_temp.places((o ->> 'json')::jsonb, g.json::jsonb) p where p.kind = 'differs') x;
  assert bad is null, 'on the sample, planner_loads_get() differs from its loads at: ' || bad;
  select string_agg(kind || ' ×' || n, '; ') into used
    from (select y.kind, sum(y.n) as n
            from (select p.kind, p.n from jsonb_array_elements(j -> 'planner_loads') o join public.planner_loads_get() g on g.month = o ->> 'month'
                    cross join lateral pg_temp.places((o ->> 'json')::jsonb, g.json::jsonb) p
                  union all
                  select 'savedAt and version (the month''s saved_at)', count(*) from jsonb_array_elements(j -> 'planner_loads') o
                    join public.planner_loads_get() g on g.month = o ->> 'month' where g.saved_at <> (o ->> 'saved_at')::bigint) y
           where y.n > 0 group by y.kind) x;
  select count(*) into v_months from public.planner_loads_get();
  raise notice 'sample: planner_loads_get() equals its loads (% month(s), % typed loads and % day flags kept); allowed differences used: %',
    v_months, (select count(*) from public.load_entries), (select count(*) from public.load_days), coalesce(used, 'none');
end
$test$;

-- ---------------------------------------------------------------- 3. design §4's worked example, as stored
do $test$
declare r record; l1 record; l2 record; v record;
begin
  select ro.*, rt.hub_code, rt.dest_code, al.planner_name into r
    from public.rotations ro join public.routes rt on rt.id = ro.route_id join public.airlines al on al.id = ro.airline_id
   where ro.legacy_key = 'z5qbaeg';
  assert r.id is not null, 'the sample''s frequency z5qbaeg has no rotation';
  assert r.planner_name = 'Kingfisher' and r.hub_code = 'DEL' and r.dest_code = 'JFK' and r.service_code = 'S3'
     and r.fare_pct = 100 and r.launched_on = '2026-09-22',
    'z5qbaeg''s rotation isn''t Kingfisher DEL-JFK, S3, 100%, launched 22 Sep';
  select * into l1 from public.flight_legs where rotation_id = r.id and leg_no = 1;
  select * into l2 from public.flight_legs where rotation_id = r.id and leg_no = 2;
  assert l1.origin_code = 'DEL' and l1.dest_code = 'JFK' and l1.flight_no = 1001 and l1.days_utc = '{2,4,7}'
     and l1.dep_utc_min = 1200 and l1.block_min = 799,
    format('z5qbaeg leg 1 is %s-%s %s on %s at %s for %s min, expected DEL-JFK 1001 on {2,4,7} at 1200 for 799',
           l1.origin_code, l1.dest_code, l1.flight_no, l1.days_utc, l1.dep_utc_min, l1.block_min);
  assert l2.origin_code = 'JFK' and l2.dest_code = 'DEL' and l2.flight_no = 1002 and l2.days_utc = '{1,3,5}'
     and l2.dep_utc_min = 750 and l2.block_min = 799,
    format('z5qbaeg leg 2 is %s-%s %s on %s at %s for %s min, expected JFK-DEL 1002 on {1,3,5} at 750 for 799',
           l2.origin_code, l2.dest_code, l2.flight_no, l2.days_utc, l2.dep_utc_min, l2.block_min);
  select * into v from public.flight_legs_local where id = l1.id;
  assert v.days_local = '{1,3,5}' and v.dep_local = '01:30' and v.arr_local = '04:19' and v.arr_local_day_offset = 0
     and v.arr_utc_min = 559 and v.arr_utc_day_offset = 1,
    'z5qbaeg''s outbound doesn''t read back as Mon, Wed, Fri 01:30 -> 04:19, landing 09:19 UTC the next day';
  select * into v from public.flight_legs_local where id = l2.id;
  assert v.days_local = '{1,3,5}' and v.dep_local = '07:30' and v.arr_local = '07:19' and v.arr_local_day_offset = 1
     and v.arr_utc_min = 109 and v.arr_utc_day_offset = 1,
    'z5qbaeg''s return doesn''t read back as Mon, Wed, Fri 07:30 -> 07:19 the next day, landing 01:49 UTC';
  raise notice 'sample: DEL-JFK z5qbaeg is design §4''s example exactly: leg 1 {2,4,7} 20:00 UTC, 799 min; leg 2 {1,3,5} 12:30 UTC, 799 min';
end
$test$;

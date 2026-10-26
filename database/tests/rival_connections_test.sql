-- Rivals' connecting options on our pairs (spec docs/specs/2026-10-23-rival-connections.md §1–§3, §5; migration
-- 20261023140000_rival_connections.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes, counts
-- and words of the hand-made world only). Everything is made in a world of its own, so nothing on the copy is touched or
-- counted; the copy's own numbers and the timing are printed at the end (counts only).
--   1. The two tables (RLS on, no rule, no access for anon or authenticated, every column described), the setting
--      rival_connection_detour_max 1.5 in every world (described, since 23 Oct, with its reason), the two new internal
--      functions (closed to everyone, empty search path, described), and the archive's list with scan_rival_connections.
--   2. A world of its own (our airline C1 at YC1, flying YC1–YC3 and with YC1–YC5 on its list) and a hand-made scan,
--      finished through private.scan_ingest() as the capture finishes one. Rival CR1 (hub YH1, on the way): a connection
--      inside the window (YC1→YH1→YC3, 2 h, daily: 7 a week), one under the minimum connection time (YH1's mct 60: 45
--      minutes, left out), one over 8 hours (left out), one over midnight (lands 23:30, onward 02:00 the next day: days
--      1 3 5 arriving, onward days 2 4 6, so 3 a week), two onward options from one flight (counted once a day, the
--      shorter gap kept), and a route at 1.6 times the direct distance through YF1 (left out). A freighter (CF2) and our
--      own C2 connecting the same way (left out). The week table's totals and top airports; the finish note; the
--      calculation again by hand gives the same rows.
--   3. The archive takes scan_rival_connections by its scan's time, three months back: due exactly as made, its manifest,
--      the delete; the week table stays.
--   4. competition() and route_story(): connecting figures beside direct on markets, openings, profiles and competitors,
--      and on the route page's rivals; with and without the connection rows, every other field the same (share, threats,
--      openings and their order, contested, hubs first, the three competitors).
--   On the copy: the latest finished scan's connections, timed.

create temporary table t_rc (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_rc to anon, authenticated;

-- a flight in a scan's schedule: [code, number, from, to, weekdays, departure, arrival, type, operator]
create function pg_temp.rc_fl(code text, no int, o text, d text, days text, dep text, arr text, ty text default '320') returns jsonb language sql immutable as $f$
  select jsonb_build_array(code, no::text, o, d, days, dep, arr, ty, '')
$f$;
-- a document without its connecting fields (every key starting "connecting", at any depth, and the notes about them):
-- what it would be without the connection rows
create function pg_temp.rc_strip(j jsonb) returns jsonb language plpgsql immutable as $f$
begin
  if jsonb_typeof(j) = 'object' then
    return coalesce((select jsonb_object_agg(k, case when k = 'notes' and jsonb_typeof(v) = 'array'
                                                     then coalesce((select jsonb_agg(n order by i) from jsonb_array_elements(v) with ordinality x(n, i)
                                                                     where lower(coalesce(n #>> '{}', '')) not like 'connecting (since 23 oct)%'), '[]'::jsonb)
                                                     else pg_temp.rc_strip(v) end)
                       from jsonb_each(j) e(k, v) where k not like 'connecting%'), '{}'::jsonb);
  elsif jsonb_typeof(j) = 'array' then
    return coalesce((select jsonb_agg(pg_temp.rc_strip(x) order by i) from jsonb_array_elements(j) with ordinality y(x, i)), '[]'::jsonb);
  end if;
  return j;
end
$f$;

-- ---------------------------------------------------------------- 1. the tables, the setting, who may call what
do $test$
declare t text; n_worlds int := (select count(*) from public.worlds); g text; bad text;
begin
  foreach t in array array['scan_rival_connections', 'scan_rival_connections_week'] loop
    assert (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), t || ' has no RLS';
    assert not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t), t || ' has an access rule: it''s read through functions only';
    select string_agg(r || ' ' || p, ', ') into bad from unnest(array['anon', 'authenticated']) r
     cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p
     where has_table_privilege(r, 'public.' || t, p);
    assert bad is null, t || ' is open to: ' || bad;
    assert length(coalesce(obj_description(('public.' || t)::regclass, 'pg_class'), '')) > 200, t || ' has no description';
    select string_agg(a.attname, ', ') into bad from pg_attribute a
     where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped
       and a.attname not in ('scan_id', 'world_id') and col_description(a.attrelid, a.attnum) is null;
    assert bad is null, t || ': columns without a description: ' || bad;
  end loop;
  assert (select array_agg(a.attname::text order by a.attnum) from pg_attribute a where a.attrelid = 'public.scan_rival_connections'::regclass and a.attnum > 0 and not a.attisdropped)
       = array['scan_id', 'world_id', 'airline_id', 'origin', 'dest', 'via', 'weekly_departures', 'best_gap_min'],
    'scan_rival_connections'' columns aren''t the spec''s';
  assert (select count(*) from public.settings s where s.key = 'rival_connection_detour_max' and s.airline_id is null and s.value = '1.5'::jsonb
            and length(coalesce(s.description, '')) > 80 and s.since = date '2026-10-23' and s.reason like 'Gitesh, 23 Oct%') = n_worlds,
    'rival_connection_detour_max isn''t 1.5 in every world, described, since 23 Oct, with its reason';
  foreach g in array array['private.scan_connection_via(jsonb)', 'private.scan_connections(bigint)'] loop
    assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute')
       and not has_function_privilege('service_role', g, 'execute'), g || ' can be called from outside';
    assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                        where p.oid = g::regprocedure and a.grantee = 0), g || ' is open to public';
    assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 150, g || ' has no description';
  end loop;
  assert (select 'enable_nestloop=off' = any (p.proconfig) from pg_proc p where p.oid = 'private.scan_connections(bigint)'::regprocedure),
    'private.scan_connections() doesn''t turn nested loops off (minutes on a real scan without)';
  assert exists (select 1 from private.archive_tables() t where t.table_name = 'scan_rival_connections' and t.keep_months = 1)
     and not exists (select 1 from private.archive_tables() t where t.table_name = 'scan_rival_connections_week'),
    'the archive doesn''t take scan_rival_connections after one month, or takes the week table';
  assert position('Connecting (since 23 Oct' in obj_description('public.competition(bigint, timestamptz, integer)'::regprocedure, 'pg_proc')) > 0
     and position('Fleets (since 23 Oct' in obj_description('public.competition(bigint, timestamptz, integer)'::regprocedure, 'pg_proc')) > 0
     and position('Connecting (since 23 Oct' in obj_description('public.route_story(bigint, timestamptz)'::regprocedure, 'pg_proc')) > 0
     and position('private.scan_connections()' in obj_description('private.scan_ingest(bigint, text, jsonb)'::regprocedure, 'pg_proc')) > 0,
    'a description doesn''t say what changed, or lost what it said before (competition()''s fleets)';
  raise notice 'scan_rival_connections and scan_rival_connections_week: RLS on with no rule, closed to anon and authenticated, every column described; rival_connection_detour_max 1.5 in each of the % world(s); scan_connection_via() and scan_connections() internal, nested loops off in the calculation; the archive takes the detail table only; the descriptions say so', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. the world, the scan and the calculation
-- On a line of longitude 0, so distances are easy: YC1 at 0°, YH1 at 1° (on the way), YC3 at 2°, YC5 at 3°, YF1 1.25°
-- off the line at 1° (a dogleg: YC1→YF1→YC3 is 1.6 times YC1–YC3), YX1 far away (not on any pair of ours).
do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; c1 bigint; c2 bigint; ty bigint; r record; ids jsonb := '{}'::jsonb; s bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'rival connections test', true);
  insert into public.airports (code, utc_offset, lat, lon) values
    ('YC1', 0, 0, 0), ('YH1', 0, 1, 0), ('YC3', 0, 2, 0), ('YC5', 0, 3, 0), ('YF1', 0, 1, 1.25), ('YX1', 0, 40, 40), ('YC2', 0, 0.5, 0)
  on conflict (code) do update set utc_offset = excluded.utc_offset, lat = excluded.lat, lon = excluded.lon;
  insert into public.worlds (name, game_host, kind) values ('rival connections test', 'rival-connections.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s2.key, s2.value, s2.unit, s2.description from public.settings s2 where s2.world_id = dw and s2.airline_id is null;
  insert into public.world_airports (world_id, airport_code, mct_min) values (w, 'YH1', 60);
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990901, 'Conn One', 'Conn One', 'C1', 'YC1', true, 1) returning id into c1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990902, 'Conn Two', 'Conn Two', 'C2', 'YC2', true, 2) returning id into c2;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, c1, 'YC1', 'hub', true, 1), (w, c2, 'YC2', 'hub', true, 1);
  insert into public.aircraft_types (world_id, name, seats_max, range_km, price, cruise_kmh, min_turn_min)
  values (w, 'RC A320', 180, 6000, 2000000, 840, 60) returning id into ty;
  insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) values (w, c1, ty), (w, c2, ty);
  -- C1 flies YC1–YC3 (a route with a rotation and legs) and has YC1–YC5 on its list (an opening)
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, source) values
    (w, c1, 'YC1', 'YC3', 222, 4, 'research'), (w, c1, 'YC1', 'YC5', 333, 4, 'research');
  insert into public.rotations (world_id, airline_id, route_id, launched_on)
  select w, c1, x.id, date '2030-01-01' from public.routes x where x.world_id = w and x.dest_code = 'YC3';
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code, acquired) values (w, c1, 'YC-1', ty, 'active', 'YC1', 'new');
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min)
  select w, c1, ro.id, l.n, 100 + l.n, case when l.n = 1 then 'YC1' else 'YC3' end, case when l.n = 1 then 'YC3' else 'YC1' end,
         (select id from public.aircraft where registration = 'YC-1' and world_id = w), '{1,2,3,4,5,6,7}', 400 + 200 * l.n, 60
    from public.rotations ro cross join (values (1), (2)) l(n) where ro.world_id = w;
  for r in select * from (values ('cr1', 990911, 'Conn Rival One'), ('cr2', 990912, 'Conn Rival Two'), ('cf2', 990913, 'Conn Cargo')) v(k, gid, name) loop
    ids := ids || jsonb_build_object(r.k, private.scan_airline(w, r.gid, r.name));
  end loop;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_rc values ('w', to_jsonb(w)), ('c1', to_jsonb(c1)), ('c2', to_jsonb(c2)), ('ids', ids);
end
$setup$;

-- the scan, as the capture sends it, finished through private.scan_ingest() (kind finish)
do $setup$
declare w bigint := (select (v #>> '{}')::bigint from t_rc where k = 'w'); c2 bigint := (select (v #>> '{}')::bigint from t_rc where k = 'c2');
  ids jsonb := (select v from t_rc where k = 'ids'); s bigint;
begin
  s := (private.scan_ingest(w, 'start', '{"week": "43", "note": "rival connections test"}') ->> 'snapshot_id')::bigint;
  update public.game_scans set taken_at = timestamptz '2030-03-08 08:00:00+00' where id = s;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
    (s, w, (ids ->> 'cr1')::bigint, jsonb_build_array(
       -- inside the window: lands YH1 08:00, onward 10:00 (2 h), daily: 7 a week YC1→YC3
       pg_temp.rc_fl('R1', 1, 'YC1', 'YH1', '1234567', '07:00', '08:00'), pg_temp.rc_fl('R1', 2, 'YH1', 'YC3', '1234567', '10:00', '11:00'),
       -- two onward options for one flight (10:00 and 12:00): YC1→YC3 still 7 a week, the 2 h gap kept
       pg_temp.rc_fl('R1', 3, 'YH1', 'YC3', '1234567', '12:00', '13:00'),
       -- under the minimum connection time at YH1 (60): lands 14:00, onward 14:45 (45 minutes), YC1→YC3 days 1–7: left out
       pg_temp.rc_fl('R1', 4, 'YC1', 'YH1', '1234567', '13:00', '14:00'), pg_temp.rc_fl('R1', 5, 'YH1', 'YC3', '1234567', '14:45', '15:45'),
       -- over 8 hours: YC3 lands YH1 06:00, onward to YC1 at 15:00 (9 h): left out (that pairing; the 07:30 option below counts)
       pg_temp.rc_fl('R1', 6, 'YC3', 'YH1', '1234567', '05:00', '06:00'), pg_temp.rc_fl('R1', 7, 'YH1', 'YC1', '1234567', '15:00', '16:00'),
       -- over midnight: YC5 leaves 22:30 days 1 3 5 and lands YH1 00:30, so on days 2 4 6 there; onward to YC1 02:30
       -- days 2 4 6: 3 a week YC5→YC1, gap 2 h
       pg_temp.rc_fl('R1', 8, 'YC5', 'YH1', '135', '22:30', '00:30'), pg_temp.rc_fl('R1', 9, 'YH1', 'YC1', '246', '02:30', '03:30'),
       -- the same night's onward flight on days 1 3 5 doesn't connect (it left the day before the first landed)
       pg_temp.rc_fl('R1', 10, 'YH1', 'YC1', '135', '02:45', '03:45'),
       -- YC3→YH1→YC1 inside the window on days 1 2: 06:00 lands, 07:30 onward (90 minutes, at YH1's 60): 2 a week
       pg_temp.rc_fl('R1', 11, 'YH1', 'YC1', '12', '07:30', '08:30'))),
    (s, w, (ids ->> 'cr2')::bigint, jsonb_build_array(
       -- a dogleg through YF1 (about 1.6 times YC1–YC3): left out
       pg_temp.rc_fl('R2', 1, 'YC1', 'YF1', '1234567', '07:00', '08:00'), pg_temp.rc_fl('R2', 2, 'YF1', 'YC3', '1234567', '10:00', '11:00'),
       -- and a direct flight on our pair, 7 a week, so it is a rival on it too
       pg_temp.rc_fl('R2', 3, 'YC1', 'YC3', '1234567', '09:00', '10:00'),
       -- a pair that isn't ours (YC1–YX1 through YH1): never kept
       pg_temp.rc_fl('R2', 4, 'YC1', 'YH1', '1234567', '06:00', '07:00'), pg_temp.rc_fl('R2', 5, 'YH1', 'YX1', '1234567', '09:00', '15:00'))),
    (s, w, (ids ->> 'cf2')::bigint, jsonb_build_array(
       -- a freighter connecting the same way: left out
       pg_temp.rc_fl('RF', 1, 'YC1', 'YH1', '1234567', '07:00', '08:00', '77F'), pg_temp.rc_fl('RF', 2, 'YH1', 'YC3', '1234567', '10:00', '11:00', '77F'))),
    (s, w, c2, jsonb_build_array(
       -- our own C2 connecting the same way: left out
       pg_temp.rc_fl('C2', 1, 'YC1', 'YH1', '1234567', '07:00', '08:00'), pg_temp.rc_fl('C2', 2, 'YH1', 'YC3', '1234567', '10:00', '11:00')));
  perform private.scan_ingest(w, 'finish', jsonb_build_object('snapshot_id', s, 'note', 'full scan: 4 enterprises'));
  insert into t_rc values ('s', to_jsonb(s));
end
$setup$;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rc where k = 'w'); s bigint := (select (v #>> '{}')::bigint from t_rc where k = 's');
  ids jsonb := (select v from t_rc where k = 'ids'); got text; again jsonb; before jsonb;
begin
  select string_agg(format('%s %s>%s via %s: %s a week, gap %s', a.game_name, c.origin, c.dest, c.via, c.weekly_departures, c.best_gap_min), '; '
                    order by a.game_name, c.origin, c.dest, c.via)
    into got from public.scan_rival_connections c join public.airlines a on a.id = c.airline_id where c.scan_id = s;
  assert got = 'Conn Rival One YC1>YC3 via YH1: 7 a week, gap 120; Conn Rival One YC3>YC1 via YH1: 2 a week, gap 90; Conn Rival One YC5>YC1 via YH1: 3 a week, gap 120',
    'the connections aren''t YC1>YC3 7 (two onward options once, the 45-minute one left out), YC3>YC1 2 (the 9-hour one left out) and YC5>YC1 3 (over midnight); no dogleg, freighter, ours or pair not ours: ' || coalesce(got, 'none');
  select string_agg(format('%s %s-%s %s/%s/%s %s', a.game_name, x.airport_a, x.airport_b, x.weekly_a_to_b, x.weekly_b_to_a, x.weekly_departures, x.vias), '; '
                    order by a.game_name, x.airport_a, x.airport_b)
    into got from public.scan_rival_connections_week x join public.airlines a on a.id = x.airline_id where x.scan_id = s;
  assert got = 'Conn Rival One YC1-YC3 7/2/9 [{"via": "YH1", "weekly": 9}]; Conn Rival One YC1-YC5 0/3/3 [{"via": "YH1", "weekly": 3}]',
    'the week table isn''t each pair''s directions and top airports: ' || coalesce(got, 'none');
  assert (select note from public.game_scans where id = s) = 'full scan: 4 enterprises · connections: 1 rivals on 2 of our pairs',
    'the finish note doesn''t say the connections: ' || coalesce((select note from public.game_scans where id = s), 'none');
  -- by hand, again: the same rows, replaced not added
  select jsonb_agg(to_jsonb(c) order by c.airline_id, c.origin, c.dest, c.via) into before from public.scan_rival_connections c where c.scan_id = s;
  again := private.scan_connections(s);
  assert again ->> 'rows' = '3' and again ->> 'rivals' = '1' and again ->> 'pairs' = '2' and again ->> 'weekly' = '12' and again ->> 'left_out_no_coordinates' = '0'
     and (select jsonb_agg(to_jsonb(c) order by c.airline_id, c.origin, c.dest, c.via) from public.scan_rival_connections c where c.scan_id = s) = before,
    'the calculation by hand didn''t give the same rows: ' || again::text;
  -- the detour limit: at 1.7 the dogleg through YF1 counts too
  update public.settings set value = '1.7' where world_id = w and airline_id is null and key = 'rival_connection_detour_max';
  perform private.scan_connections(s);
  assert exists (select 1 from public.scan_rival_connections c where c.scan_id = s and c.via = 'YF1' and c.weekly_departures = 7),
    'at 1.7 the dogleg through YF1 (about 1.6 times) isn''t counted';
  update public.settings set value = '1.5' where world_id = w and airline_id is null and key = 'rival_connection_detour_max';
  perform private.scan_connections(s);
  assert not exists (select 1 from public.scan_rival_connections c where c.scan_id = s and c.via = 'YF1'), 'back at 1.5 the dogleg still counts';
  -- an airport without coordinates: the routing is left out and counted
  update public.airports set lat = null where code = 'YC5';
  again := private.scan_connections(s);
  assert again ->> 'left_out_no_coordinates' = '1' and not exists (select 1 from public.scan_rival_connections c where c.scan_id = s and c.origin = 'YC5'),
    'a routing with an airport lacking coordinates isn''t left out and counted: ' || again::text;
  update public.airports set lat = 3 where code = 'YC5';
  perform private.scan_connections(s);
  -- a calculation that fails never stops the finish: the note says so
  update public.settings set value = '"x"' where world_id = w and airline_id is null and key = 'rival_connection_detour_max';
  update public.game_scans set status = 'running', note = 'second try' where id = s;
  perform private.scan_ingest(w, 'finish', jsonb_build_object('snapshot_id', s));
  assert (select status = 'done' and note like 'second try · connections not worked out: setting rival_connection_detour_max%' from public.game_scans where id = s),
    'a failed calculation stopped the finish or wasn''t noted: ' || (select note from public.game_scans where id = s);
  assert (select count(*) from public.scan_rival_connections c where c.scan_id = s) = 3, 'a failed calculation lost the rows it had';
  update public.settings set value = '1.5' where world_id = w and airline_id is null and key = 'rival_connection_detour_max';
  raise notice 'the calculation: YC1>YC3 7 a week via YH1 (two onward options counted once, the 2 h gap kept; 45 minutes under YH1''s 60 left out), YC3>YC1 2 (9 hours left out), YC5>YC1 3 (over midnight, the next day''s flight only); the 1.6 dogleg, a freighter, our own airline and a pair not ours left out; the week table and the finish note right; by hand the same; the detour setting moves the line; an airport without coordinates left out and counted; a failed calculation never stops the finish';
end
$test$;

-- ---------------------------------------------------------------- 3. the archive takes the detail table, not the week table
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rc where k = 'w'); s bigint := (select (v #>> '{}')::bigint from t_rc where k = 's');
  m date := (date_trunc('month', now() at time zone 'UTC') - interval '3 months')::date; old bigint; mf jsonb; res jsonb; n_week int;
begin
  -- a copy of the scan three months back (its own row, its own connections)
  insert into public.game_scans (world_id, taken_at, status, note) values (w, (m + 4)::timestamp at time zone 'UTC', 'done', 'rival connections test, old')
  returning id into old;
  insert into public.scan_rival_connections (scan_id, world_id, airline_id, origin, dest, via, weekly_departures, best_gap_min)
  select old, c.world_id, c.airline_id, c.origin, c.dest, c.via, c.weekly_departures, c.best_gap_min from public.scan_rival_connections c where c.scan_id = s;
  insert into public.scan_rival_connections_week (scan_id, world_id, airline_id, airport_a, airport_b, weekly_a_to_b, weekly_b_to_a, weekly_departures, vias)
  select old, x.world_id, x.airline_id, x.airport_a, x.airport_b, x.weekly_a_to_b, x.weekly_b_to_a, x.weekly_departures, x.vias
    from public.scan_rival_connections_week x where x.scan_id = s;
  assert exists (select 1 from private.archive_due() d where d.table_name = 'scan_rival_connections' and d.month = m
                   and d.rows = (select count(*) from public.scan_rival_connections c join public.game_scans g on g.id = c.scan_id
                                  where date_trunc('month', g.taken_at at time zone 'UTC')::date = m)),
    'the old scan''s connections aren''t due in their month';
  assert not exists (select 1 from private.archive_due() d where d.table_name = 'scan_rival_connections' and d.month >= private.archive_kept_from('scan_rival_connections', (now() at time zone 'UTC')::date)),
    'connections inside the kept window are due';
  mf := private.archive_manifest(m, 'scan_rival_connections');
  assert (mf ->> 'rows')::int >= 3 and mf ->> 'primary_key_order' like '%scan_id%via%' and (mf ->> 'due')::boolean, 'the manifest isn''t right: ' || (mf - 'layout')::text;
  select count(*) into n_week from public.scan_rival_connections_week where scan_id = old;
  res := private.archive_delete(m, 'scan_rival_connections', (mf ->> 'rows')::bigint, mf ->> 'checksum');
  assert (res ->> 'deleted')::int = (mf ->> 'rows')::int and not exists (select 1 from public.scan_rival_connections where scan_id = old)
     and (select count(*) from public.scan_rival_connections where scan_id = s) = 3
     and (select count(*) from public.scan_rival_connections_week where scan_id = old) = n_week and n_week = 2,
    'the archive''s delete didn''t take exactly the month''s connections, or touched the week table: ' || res::text;
  raise notice 'the archive: scan_rival_connections due in its scan''s month (% rows three months back), its manifest by scan, rival, pair and via; the guarded delete took exactly them, the latest scan''s stayed, the week table kept for good',
    mf ->> 'rows';
end
$test$;

-- ---------------------------------------------------------------- 4. competition() and route_story()
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rc where k = 'w'); c1 bigint := (select (v #>> '{}')::bigint from t_rc where k = 'c1');
  s bigint := (select (v #>> '{}')::bigint from t_rc where k = 's'); t timestamptz := timestamptz '2030-03-08 12:00:00+00';
  d jsonb; e jsonb; rs jsonb; rs0 jsonb; r_id bigint; o jsonb; p jsonb; m jsonb; saved jsonb; saved_w jsonb;
begin
  d := private.fig_competition(c1, t);
  -- the market (both pairs have no market): direct 7 (CR2 on YC1–YC3), connecting 12 via YH1, never in total or share
  m := d -> 'markets' -> 0;
  assert m ->> 'rivals' = '7' and m ->> 'connecting_weekly' = '12' and m -> 'connecting_via' = '[{"via": "YH1", "weekly": 12}]'::jsonb
     and (m ->> 'total')::int = (m ->> 'ours')::int + 7,
    'the market isn''t 7 direct beside 12 connecting via YH1 (total without them): ' || (m - 'top')::text;
  -- the opening YC1–YC5: no direct rival, CR1 connecting 3 via YH1
  o := (select x from jsonb_array_elements(d -> 'openings') x where x ->> 'pair' = 'YC1-YC5');
  assert o ->> 'rivals_weekly' = '0' and o ->> 'connecting_weekly' = '3' and o -> 'connecting' -> 0 ->> 'name' = 'Conn Rival One'
     and o -> 'connecting' -> 0 -> 'via' = '[{"via": "YH1", "weekly": 3}]'::jsonb,
    'the opening YC1–YC5 isn''t 0 direct beside 3 connecting (Conn Rival One via YH1): ' || coalesce(o::text, 'none');
  -- the profiles and the competitors: CR2 flies the pair direct (7), with no connections; CR1 only connects, so it is in
  -- neither list (both are chosen by direct departures)
  p := (select x from jsonb_array_elements(d -> 'profiles') x where x ->> 'name' = 'Conn Rival Two');
  assert p ->> 'weekly_on_pairs' = '7' and p ->> 'connecting_weekly' = '0' and p -> 'connecting_via' = '[]'::jsonb
     and not exists (select 1 from jsonb_array_elements(d -> 'profiles') x where x ->> 'name' = 'Conn Rival One'),
    'the profiles aren''t Conn Rival Two 7 direct, 0 connecting, and no Conn Rival One: ' || (d -> 'profiles')::text;
  assert (select string_agg(x ->> 'name' || ' ' || (x ->> 'on_pairs') || '/' || (x ->> 'connecting_weekly'), ', ') from jsonb_array_elements(d -> 'competitors') x)
         = 'Conn Rival Two 7/0', 'the competitors aren''t Conn Rival Two alone (7 direct, 0 connecting): ' || (d -> 'competitors')::text;

  -- without the connection rows: every other field the same, and no connecting fields at all
  select jsonb_agg(to_jsonb(c)) into saved from public.scan_rival_connections c where c.scan_id = s;
  select jsonb_agg(to_jsonb(x)) into saved_w from public.scan_rival_connections_week x where x.scan_id = s;
  delete from public.scan_rival_connections where scan_id = s;
  delete from public.scan_rival_connections_week where scan_id = s;
  e := private.fig_competition(c1, t);
  assert pg_temp.rc_strip(e) - 'notes' = e - 'notes', 'with no connections worked out, the answer still has connecting fields';
  assert pg_temp.rc_strip(d) = pg_temp.rc_strip(e),
    'with the connection rows, more than the connecting fields changed (share, threats, openings, contested, hubs first or the competitors)';
  insert into public.scan_rival_connections select (jsonb_populate_record(null::public.scan_rival_connections, x)).* from jsonb_array_elements(saved) x;
  insert into public.scan_rival_connections_week select (jsonb_populate_record(null::public.scan_rival_connections_week, x)).* from jsonb_array_elements(saved_w) x;

  -- the route page: YC1–YC3's rivals, CR2 7 direct and 0 connecting; CR1 only connects (9 a week, via YH1)
  select r.id into r_id from public.routes r where r.world_id = w and r.dest_code = 'YC3';
  rs := private.fig_route_story(r_id, t);
  assert rs #> '{rivals,airlines}' = ('[{"airline_id": ' || ((select v ->> 'cr2' from t_rc where k = 'ids')) || ', "name": "Conn Rival Two", "weekly": 7, "change": null, "weekly_before": null, "connecting_via": [], "connecting_weekly": 0}]')::jsonb,
    'the route''s rivals aren''t Conn Rival Two 7 direct, 0 connecting: ' || (rs #> '{rivals,airlines}')::text;
  assert rs #>> '{rivals,connecting_weekly}' = '9' and rs #> '{rivals,connecting_only,0,name}' = '"Conn Rival One"'
     and rs #> '{rivals,connecting_only,0,connecting_via}' = '[{"via": "YH1", "weekly": 9}]'::jsonb
     and rs #>> '{rivals,rivals_weekly}' = '7'
     and jsonb_array_length(rs #> '{rivals,connecting_scans}') = 1 and rs #>> '{rivals,connecting_scans,0,weekly}' = '9',
    'the route''s connecting figures aren''t 9 (Conn Rival One only connecting, via YH1), with rivals_weekly still 7: ' || (rs -> 'rivals')::text;
  delete from public.scan_rival_connections where scan_id = s;
  delete from public.scan_rival_connections_week where scan_id = s;
  rs0 := private.fig_route_story(r_id, t);
  assert pg_temp.rc_strip(rs) = pg_temp.rc_strip(rs0) and pg_temp.rc_strip(rs0) - 'notes' = rs0 - 'notes', 'on the route page, more than the connecting fields changed with the connection rows';
  raise notice 'competition(): the market 7 direct beside 12 connecting via YH1 (total and share direct only), the opening YC1–YC5 0 direct beside 3 connecting, the profile and the only competitor Conn Rival Two (chosen by direct, 0 connecting), and without the rows nothing else moves; route_story(): Conn Rival Two 7 direct, 0 connecting, Conn Rival One only connecting (9 via YH1), rivals_weekly 7, and nothing else moves';
end
$test$;

-- ---------------------------------------------------------------- the copy (counts and timing only)
do $test$
declare dw bigint := (select id from public.worlds where is_default); s bigint; r jsonb; t0 timestamptz; a bigint; d jsonb; ms int;
begin
  select x.id into s from public.game_scans x where x.world_id = dw and x.status = 'done'
     and exists (select 1 from public.game_scan_schedules y where y.scan_id = x.id) order by x.taken_at desc, x.id desc limit 1;
  if s is null then
    raise notice 'on the copy: no finished scan with its schedules to time';
    return;
  end if;
  t0 := clock_timestamp();
  r := private.scan_connections(s);
  ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
  select al.airline_id into a from private.fig_airlines(dw) al order by al.ord limit 1;
  t0 := clock_timestamp();
  if a is not null then d := private.fig_competition(a, now()); end if;
  raise notice 'on the copy: private.scan_connections() on the latest finished scan (%) took % ms: % (% rows, % connecting departures a week, % left out for want of coordinates); the first airline''s competition() then took % ms, its markets % connecting a week',
    s, ms, r ->> 'words', r ->> 'rows', r ->> 'weekly', r ->> 'left_out_no_coordinates', round(extract(epoch from clock_timestamp() - t0) * 1000),
    (select sum((x ->> 'connecting_weekly')::int) from jsonb_array_elements(coalesce(d -> 'markets', '[]')) x);
  assert ms < 20000, format('private.scan_connections() took %s ms on the copy: the brief''s trigger is a few seconds', ms);
end
$test$;

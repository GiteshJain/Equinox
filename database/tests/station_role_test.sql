-- Stations (manual §2, and §3 hubs first; migration 20261022060000_station_role.sql and its removals file; spec
-- docs/specs/2026-10-22-station-role.md). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes, counts
-- and words of the hand-made world only). Everything is made in a world of its own, so nothing on the copy is touched or
-- counted; for site_public() the hand-made world is made the default inside the transaction, which the rollback undoes.
--   The world: two of our airlines and a rival. S1 has its main hub YS1, the focus city YS2 and two stations, ZT1 and ZT2.
--   It flies YS1–ZD1 daily both ways (7 departures a week from its main hub, as hub_progress() counts them; under the 750). Its list: YS1–ZD3 (from the
--   main hub), ZT1–ZT2 (a station pair), ZT1–ZD2 (from a station, contested both ways: the rival has 300 departures a week
--   at ZT1 and 21 a week on ZT1–ZD2), YS2–ZT2 (a focus city to a station), YS1–YS2 (a trunk in November) and YS1–ZT9
--   (to S2's station). S2 (hub first exempt, as Ryanair) has its hub YR1 and the station ZT9, and flies ZT9–ZD9.
--   1. The role's rules: a station with no banks (none, or every slot empty), no block, no parent and not the main hub is
--      accepted; one with a bank time, a block, a parent or as the main hub isn't; no fourth role; the old rule is gone.
--      The settings station_flight_no_from 100 and station_flight_no_to 999 in every world, described.
--   2. competition(): a station opening is listed and ranked, not allowed with "hubs first: stations wait for YS1's 750",
--      contested or not; once the main hub reaches its target (S1's own hub_first_departures, moved under its 7 here) it
--      is allowed; S2 (exempt) is allowed from its station.
--   3. November: a pair with a station end (S1's own, or another airline's) is never a trunk; YS1–YS2 is.
--   4. hub_progress() lists no station beside the main hub, and site_public()'s hubs leave stations out (a station route
--      still flies on the website's schedule).

create temporary table t_st (k text primary key, v jsonb) on commit drop;

-- ---------------------------------------------------------------- the hand-made world
create function pg_temp.st_route(w bigint, al bigint, hub text, dest text, stars int, dist int, flown boolean, ty bigint, k int)
returns bigint language plpgsql as $f$
declare r bigint; rot bigint; ac bigint;
begin
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, source)
  values (w, al, hub, dest, dist, stars, 'research') returning id into r;
  if flown then
    insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, al, r, date '2030-01-01') returning id into rot;
    insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code, acquired)
    values (w, al, 'YS-' || k, ty, 'active', hub, 'new') returning id into ac;
    insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
      (w, al, rot, 1, 100 + k * 2 + 1, hub, dest, ac, '{1,2,3,4,5,6,7}', 600, 90),
      (w, al, rot, 2, 100 + k * 2 + 2, dest, hub, ac, '{1,2,3,4,5,6,7}', 800, 90);
  end if;
  return r;
end
$f$;

do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; s1 bigint; s2 bigint; r1 bigint; ty bigint; sc bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'station role test', true);
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['YS1', 'YS2', 'YR1', 'ZT1', 'ZT2', 'ZT9', 'ZD1', 'ZD2', 'ZD3', 'ZD9', 'ZX1', 'ZX2', 'ZX3', 'ZX4', 'ZX5']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('station test', 'station.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  -- the house rules' thresholds as the manual has them (manual §3), whatever the copy holds
  update public.settings set value = v.v from (values ('hub_first_departures', '750'::jsonb), ('contested_rival_weekly', '250'::jsonb),
                                                      ('contested_rival_daily', '2'::jsonb), ('hub_first_exempt', 'false'::jsonb)) v(k, v)
   where world_id = w and airline_id is null and key = v.k;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990801, 'Station One', 'Station One', 'S1', 'YS1', true, 1) returning id into s1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990802, 'Station Two', 'Station Two', 'S2', 'YR1', true, 2) returning id into s2;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, null, 990891, 'Rival Station', true) returning id into r1;
  insert into public.settings (world_id, airline_id, key, value, unit, description) values (w, s2, 'hub_first_exempt', 'true'::jsonb, null, 'test');
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, parent_base_id, bank_times, flight_no_from, position) values
    (w, s1, 'YS1', 'hub', true, null, '{06:00,14:00,22:00}', 1000, 1),
    (w, s1, 'YS2', 'focus', false, null, null, 2000, 2),
    (w, s1, 'ZT1', 'station', false, null, null, null, 3),
    (w, s1, 'ZT2', 'station', false, null, '{NULL,NULL,NULL,NULL}', null, 4),
    (w, s2, 'YR1', 'hub', true, null, '{08:00}', 3000, 1),
    (w, s2, 'ZT9', 'station', false, null, null, null, 2);
  insert into public.aircraft_types (world_id, name, seats_max, range_km, price, cruise_kmh, min_turn_min)
  values (w, 'ST E195', 146, 3542, 1771000, 840, 60) returning id into ty;
  insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) values (w, s1, ty), (w, s2, ty);

  perform pg_temp.st_route(w, s1, 'YS1', 'ZD1', 5, 1000, true, ty, 1);
  perform pg_temp.st_route(w, s1, 'YS1', 'ZD3', 3, 1200, false, null, 0);
  perform pg_temp.st_route(w, s1, 'ZT1', 'ZT2', 4, 800, false, null, 0);
  perform pg_temp.st_route(w, s1, 'ZT1', 'ZD2', 3, 900, false, null, 0);
  perform pg_temp.st_route(w, s1, 'YS2', 'ZT2', 3, 700, false, null, 0);
  perform pg_temp.st_route(w, s1, 'YS1', 'YS2', 2, 300, false, null, 0);
  perform pg_temp.st_route(w, s1, 'YS1', 'ZT9', 2, 600, false, null, 0);
  perform pg_temp.st_route(w, s2, 'ZT9', 'ZD9', 3, 500, true, ty, 2);
  perform pg_temp.st_route(w, s2, 'ZT9', 'ZD2', 2, 800, false, null, 0);

  -- one finished scan: the rival has 300 departures a week at ZT1 (over 250) and 21 a week on ZT1–ZD2 (over 2 a day)
  insert into public.game_scans (world_id, taken_at, status) values (w, timestamptz '2030-02-12 08:00:00+00', 'done') returning id into sc;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
    (sc, w, r1, jsonb_build_array(jsonb_build_array('RS', 1, 'ZT1', 'ZD2', '1234567', '08:00', '10:00', '320', ''),
                                  jsonb_build_array('RS', 2, 'ZT1', 'ZD2', '1234567', '12:00', '14:00', '320', ''),
                                  jsonb_build_array('RS', 3, 'ZT1', 'ZD2', '1234567', '16:00', '18:00', '320', '')));
  insert into public.scan_airline_airports (scan_id, world_id, airline_id, airport_code, weekly_departures, destinations) values
    (sc, w, r1, 'ZT1', 300, 12), (sc, w, r1, 'YS2', 30, 2);

  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_st values ('w', to_jsonb(w)), ('s1', to_jsonb(s1)), ('s2', to_jsonb(s2)), ('t', to_jsonb(timestamptz '2030-02-13 12:00:00+00'));
end
$setup$;

-- ---------------------------------------------------------------- 1. the role's rules, and the station pool's settings
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_st where k = 'w'); s1 bigint := (select (v #>> '{}')::bigint from t_st where k = 's1');
  s3 bigint; g bigint; hub bigint; c text; x record; n_worlds int;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'station role test', true);
  assert (select count(*) from public.airline_bases b where b.world_id = w and b.role = 'station') = 3, 'the three stations weren''t accepted';
  assert not exists (select 1 from pg_constraint where conrelid = 'public.airline_bases'::regclass and conname = 'airline_bases_role_check'),
    'the old role rule (hub or focus only) is still there';
  assert (select count(*) from pg_constraint where conrelid = 'public.airline_bases'::regclass
            and conname in ('airline_bases_role_kinds', 'airline_bases_station_shape')
            and length(coalesce(obj_description(oid, 'pg_constraint'), '')) > 60) = 2,
    'airline_bases_role_kinds and airline_bases_station_shape aren''t there, described';
  -- an airline with no main hub yet, so the main-hub case meets the station rule rather than the one-main index
  select a.group_id into g from public.airlines a where a.id = s1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code, active, position) values (w, g, 990803, 'Station Three', 'S3', true, 3) returning id into s3;
  select b.id into hub from public.airline_bases b where b.airline_id = s1 and b.airport_code = 'YS1';
  for x in select * from (values
      ('a bank time', 'ZX1', null::boolean, '{06:00,NULL,NULL,NULL}'::time[], null::int, false, 'airline_bases_station_shape'),
      ('a block', 'ZX2', null, null, 100, false, 'airline_bases_station_shape'),
      ('a hub it feeds', 'ZX3', true, null, null, false, 'airline_bases_station_shape'),
      ('the main hub', 'ZX4', null, null, null, true, 'airline_bases_station_shape')) v(what, code, with_parent, banks, block, main, want) loop
    c := null;
    begin
      insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, parent_base_id, bank_times, flight_no_from)
      values (w, case when x.with_parent then s1 else s3 end, x.code, 'station', x.main, case when x.with_parent then hub end, x.banks, x.block);
    exception when check_violation then get stacked diagnostics c = constraint_name;
    end;
    assert c = x.want, format('a station with %s wasn''t refused by %s (refused by %s)', x.what, x.want, coalesce(c, 'nothing'));
  end loop;
  c := null;
  begin
    insert into public.airline_bases (world_id, airline_id, airport_code, role) values (w, s3, 'ZX5', 'gate');
  exception when check_violation then get stacked diagnostics c = constraint_name;
  end;
  assert c = 'airline_bases_role_kinds', 'a fourth role wasn''t refused by airline_bases_role_kinds: ' || coalesce(c, 'accepted');
  -- a hub keeps its banks and block; a station made a hub again keeps none and is fine
  update public.airline_bases set role = 'hub' where world_id = w and airline_id = s1 and airport_code = 'ZT2';
  update public.airline_bases set role = 'station' where world_id = w and airline_id = s1 and airport_code = 'ZT2';
  -- the station pool, in every world but this test's own (which copied the default world's rows without date and reason)
  n_worlds := (select count(*) from public.worlds wo where wo.id <> w);
  assert (select count(*) from public.settings s where s.airline_id is null and s.world_id <> w and s.unit = 'flight number'
            and length(coalesce(s.description, '')) > 60 and s.since = date '2026-10-22' and s.reason is not null
            and ((s.key = 'station_flight_no_from' and s.value = '100'::jsonb) or (s.key = 'station_flight_no_to' and s.value = '999'::jsonb))) = 2 * n_worlds,
    'station_flight_no_from 100 and station_flight_no_to 999 aren''t in every world, described, since 22 Oct, with their reason';
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  raise notice 'the station role: stations with no banks (none, or every slot empty), no block, no parent and not the main hub accepted; a bank time, a block, a hub it feeds and the main hub refused by airline_bases_station_shape, a fourth role by airline_bases_role_kinds; the old hub-or-focus rule gone; station_flight_no_from 100 and station_flight_no_to 999 in each of the % world(s), described', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. competition(): stations wait for the main hub's 750
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_st where k = 'w'); s1 bigint := (select (v #>> '{}')::bigint from t_st where k = 's1');
  s2 bigint := (select (v #>> '{}')::bigint from t_st where k = 's2'); t timestamptz := (select (v #>> '{}')::timestamptz from t_st where k = 't');
  d jsonb; got text; want text;
begin
  d := private.fig_competition(s1, t);
  select string_agg((x ->> 'rank') || '. ' || (x ->> 'route') || ' ' || coalesce(x ->> 'allowed_by', 'NOT') || case when (x ->> 'trunk')::boolean then ' trunk' else '' end,
                    '; ' order by (x ->> 'rank')::int) into got
    from jsonb_array_elements(d -> 'openings') x;
  -- the allowed first (stars, then the shorter distance), then those hubs first doesn't allow: ZT1–ZT2 (4 stars), then the 3-star
  -- ones by rivals' departures (ZT1–ZD2's 21 a week first)
  want := '1. YS1–ZD3 main hub; 2. YS1–YS2 main hub; 3. YS1–ZT9 main hub; 4. ZT1–ZT2 NOT; 5. ZT1–ZD2 NOT; 6. YS2–ZT2 NOT';
  assert got = want, 'S1''s openings are ' || coalesce(got, 'none');
  assert (select string_agg((x ->> 'route') || ': ' || (x ->> 'reason'), ' | ' order by (x ->> 'rank')::int) from jsonb_array_elements(d -> 'openings') x
           where x ->> 'route' in ('ZT1–ZT2', 'ZT1–ZD2'))
         = 'ZT1–ZT2: hubs first: stations wait for YS1''s 750 | ZT1–ZD2: hubs first: stations wait for YS1''s 750',
    'a station opening (contested or not) isn''t marked "hubs first: stations wait for YS1''s 750": ' || (d -> 'openings')::text;
  assert (select x ->> 'reason' from jsonb_array_elements(d -> 'openings') x where x ->> 'route' = 'YS2–ZT2') like 'hubs first: YS1 at 7 of 750 departures a week, and YS2 isn''t contested%',
    'a focus city''s opening to a station doesn''t keep the focus city''s own hubs-first reason: ' || (d -> 'openings')::text;
  assert (d ->> 'openings_count')::int = 6 and (d ->> 'openings_allowed')::int = 3 and (d ->> 'openings_left_out')::int = 0 and (d ->> 'openings_trunks')::int = 0,
    'S1''s counts aren''t 6 openings, 3 allowed, none left out, no trunks: ' || jsonb_build_object('n', d -> 'openings_count', 'allowed', d -> 'openings_allowed', 'out', d -> 'openings_left_out', 'trunks', d -> 'openings_trunks')::text;
  -- once the main hub reaches its target (S1's own 5, under its 7), the stations open too
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'station role test', true);
  insert into public.settings (world_id, airline_id, key, value, unit, description) values (w, s1, 'hub_first_departures', '5'::jsonb, 'departures', 'test');
  d := private.fig_competition(s1, t);
  assert (select string_agg((x ->> 'route') || ' ' || coalesce(x ->> 'allowed_by', 'NOT'), '; ' order by x ->> 'route') from jsonb_array_elements(d -> 'openings') x
           where x ->> 'route' in ('ZT1–ZT2', 'ZT1–ZD2'))
         = 'ZT1–ZD2 main hub at its target; ZT1–ZT2 main hub at its target' and (d ->> 'openings_allowed')::int = 6,
    'with the main hub at its target the station openings aren''t allowed: ' || (d -> 'openings')::text;
  delete from public.settings where world_id = w and airline_id = s1 and key = 'hub_first_departures';
  -- hub_first_exempt (Ryanair): S2 opens from its station as from anywhere
  d := private.fig_competition(s2, t);
  assert (select string_agg((x ->> 'route') || ' ' || coalesce(x ->> 'allowed_by', 'NOT'), '; ') from jsonb_array_elements(d -> 'openings') x) = 'ZT9–ZD2 exempt',
    'S2 (exempt) isn''t allowed from its station: ' || (d -> 'openings')::text;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  raise notice 'competition(): station openings listed and ranked after the allowed ones, each "hubs first: stations wait for YS1''s 750", ZT1–ZD2 too though contested by the base and the route; a focus city''s opening to a station keeps the focus city''s reason; allowed ("main hub at its target") once the main hub reaches its target; S2 (exempt) allowed from its station';
end
$test$;

-- ---------------------------------------------------------------- 3. November: a station end is never a trunk
do $test$
declare s1 bigint := (select (v #>> '{}')::bigint from t_st where k = 's1'); d jsonb; got text;
begin
  d := private.fig_competition(s1, timestamptz '2026-11-10 12:00:00+00');
  select string_agg((x ->> 'route') || case when (x ->> 'trunk')::boolean then ' trunk' else '' end || ' ' || coalesce(x ->> 'allowed_by', 'NOT'),
                    '; ' order by (x ->> 'rank')::int) into got
    from jsonb_array_elements(d -> 'openings') x;
  -- (no scan by then, so no rivals: the 3-star ones by distance)
  assert got = 'YS1–YS2 trunk November trunk; YS1–ZD3 main hub; YS1–ZT9 main hub; ZT1–ZT2 NOT; YS2–ZT2 NOT; ZT1–ZD2 NOT' and (d ->> 'openings_trunks')::int = 1,
    'on 10 Nov a pair with a station end is a trunk, or YS1–YS2 isn''t: ' || coalesce(got, 'none');
  raise notice 'November: YS1–YS2 (main hub and focus city) the one trunk; ZT1–ZT2, YS2–ZT2 and YS1–ZT9 (to another airline''s station) never trunks, the stations still waiting for the 750';
end
$test$;

-- ---------------------------------------------------------------- 4. hub_progress() and site_public() leave stations out
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_st where k = 'w'); s1 bigint := (select (v #>> '{}')::bigint from t_st where k = 's1');
  s2 bigint := (select (v #>> '{}')::bigint from t_st where k = 's2'); t timestamptz := (select (v #>> '{}')::timestamptz from t_st where k = 't');
  d jsonb; a jsonb;
begin
  d := private.fig_hub_progress(w, t);
  select x into a from jsonb_array_elements(d -> 'airlines') x where (x ->> 'airline_id')::bigint = s1;
  assert a ->> 'main_hub' = 'YS1' and (a ->> 'departures')::int = 7
     and (select string_agg(b ->> 'code' || ' ' || (b ->> 'role'), ', ') from jsonb_array_elements(a -> 'bases') b) = 'YS2 focus',
    'S1''s hub progress doesn''t list only its focus city YS2 beside the main hub: ' || a::text;
  select x into a from jsonb_array_elements(d -> 'airlines') x where (x ->> 'airline_id')::bigint = s2;
  assert jsonb_array_length(a -> 'bases') = 0, 'S2''s hub progress lists its station: ' || a::text;

  -- the website shows the default world: this test's, until the rollback
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'station role test', true);
  update public.worlds set is_default = false where is_default;
  update public.worlds set is_default = true where id = w;
  d := public.site_public();
  assert (select string_agg(h ->> 'code' || ' ' || (h ->> 'role'), ', ' order by h ->> 'code') from jsonb_array_elements(d -> 'hubs') h) = 'YS1 hub',
    'site_public()''s hubs aren''t YS1 alone (no station): ' || (d -> 'hubs')::text;
  assert exists (select 1 from jsonb_array_elements(d -> 'freqs') f where f ->> 'r' = 'Station Two|ZT9|ZD9'),
    'the station route ZT9–ZD9 isn''t on the website''s schedule: ' || (d -> 'freqs')::text;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  raise notice 'hub_progress(): S1''s bases beside its main hub are YS2 (focus) alone, S2''s none; site_public(): hubs YS1 alone, the station route ZT9–ZD9 still on the schedule';
end
$test$;

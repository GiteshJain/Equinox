-- A 7-day line in the captured figures (spec docs/specs/2026-10-27-long-haul-lines.md §4, pull request 3 of 4; manual §3
-- profit per aircraft hour, §7 the capture's page checks). No migration: the database already reads each leg on its own
-- weekdays (flight_legs.days_utc), so a line needs no change; this test holds that. Run by database/rehearse.sh on the
-- copy of last night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops
-- with an error that says which (the hand-made rows' names and figures only). Everything is made in a world of its own.
--   One airline at ZL1 (UTC). One aircraft type: turnaround 60 minutes; the world's turn margin 10 minutes. Two routes,
--   each 10 hours each way, each flown 14 times a week, each with 7 flights captured in the last day at 20k profit each:
--     ZL2, a line: 7 aircraft (ZL-L0 to ZL-L6), aircraft k out on weekday k + 1 at 06:00 and back three days later at
--          02:00, each leg on its one weekday (one rotation each);
--     ZL3, plain: one aircraft (ZL-P) out daily at 06:00 and back at 20:00.
--   1. route_profit(): both routes' aircraft hours a flight are (600 + 60 + 10) / 60 = 11.17, both fly 14 flights a week,
--      and their profit an aircraft hour is the same: the line's hours are each leg's on its own day, across the 7
--      aircraft that fly it, not one aircraft's day.
--   2. aircraft_profit(): a line aircraft flies 2 flights a week, so its flight profit a day is 20k × 2 / 7; the plain
--      one 20k × 14 / 7.
--   3. The capture's loads check: a loads page at 11:30 on Tuesday expects 4 flights in its 24 hours: the line's 06:00
--      Tuesday (aircraft ZL-L1) and 02:00 Tuesday (ZL-L5, back from Saturday), and the plain aircraft's 06:00 and 20:00.
--      Read as if each line aircraft repeated its day, it would expect 16.

do $test$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; a1 bigint; ty bigint; ac bigint; r2 bigint; r3 bigint; rot bigint; k int; i int; rid bigint;
  t timestamptz := '2030-01-15 11:00:00+00';   -- a Tuesday
  v_posted timestamptz; r jsonb; e jsonb; hours text; a jsonb;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'long haul lines figures test', true);
  insert into public.airports (code, utc_offset) values ('ZL1', 0.00), ('ZL2', 0.00), ('ZL3', 0.00)
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('long haul lines figures test', 'lines-figures.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  update public.settings set value = '10'::jsonb where world_id = w and airline_id is null and key = 'turn_margin_min';
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990401, 'Line One', 'One', 'L1', 'ZL1', true, 1) returning id into a1;
  insert into public.aircraft_types (world_id, name, min_turn_min, cruise_kmh) values (w, 'LINE TEST TYPE', 60, 900) returning id into ty;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZL1', 'ZL2', 9000, 'research') returning id into r2;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZL1', 'ZL3', 9000, 'research') returning id into r3;

  -- the line: aircraft k out on weekday k + 1, back on weekday ((k + 3) mod 7) + 1, one rotation each
  for k in 0..6 loop
    insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code, acquired)
    values (w, a1, 'ZL-L' || k, ty, 'active', 'ZL1', 'new') returning id into ac;
    insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r2, date '2029-12-01') returning id into rot;
    insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
      (w, a1, rot, 1, 4001, 'ZL1', 'ZL2', ac, array[k + 1]::smallint[], 360, 600),
      (w, a1, rot, 2, 4002, 'ZL2', 'ZL1', ac, array[((k + 3) % 7) + 1]::smallint[], 120, 600);
  end loop;
  -- the plain aircraft
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code, acquired)
  values (w, a1, 'ZL-P', ty, 'active', 'ZL1', 'new') returning id into ac;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r3, date '2029-12-01') returning id into rot;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, a1, rot, 1, 4101, 'ZL1', 'ZL3', ac, '{1,2,3,4,5,6,7}', 360, 600), (w, a1, rot, 2, 4102, 'ZL3', 'ZL1', ac, '{1,2,3,4,5,6,7}', 1200, 600);

  -- 7 flights captured on each route in the last day, each with its loads row (and its aircraft) at its own minute
  for i in 1..7 loop
    for k in 2..3 loop
      v_posted := t - make_interval(mins => i * 120 + k);
      insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code,
                                       pax_income, cargo_income, fuel, income_total, cost_total, money_captured_at)
      values (w, a1, v_posted, 1, 1, 'ZL1', 'ZL' || k, 50000, 0, 30000, 50000, 30000, t);
      insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, registration, eco_pct, eco_fare, loads_captured_at)
      values (w, a1, (v_posted at time zone 'UTC')::date, 5000 + k * 10 + i, 'ZL1', 'ZL' || k, to_char(v_posted at time zone 'UTC', 'HH24:MI'),
              case when k = 2 then 'ZL-L' || (i - 1) else 'ZL-P' end, 80, 100, t);
    end loop;
  end loop;

  -- ---------------------------------------------------------------- 1. route_profit(): the line's aircraft hours
  r := private.fig_route_profit(a1, 7, t + interval '1 hour');
  assert (select count(*) from jsonb_array_elements(r -> 'routes') x where (x ->> 'with_loads')::int = 7) = 2,
    'both routes should have their 7 flights matched: ' || (r -> 'routes')::text;
  select string_agg(x ->> 'dest' || '=' || coalesce(round((x ->> 'aircraft_hours')::numeric, 2)::text, 'none') || '/' || (x ->> 'flights_week')
                    || '/' || coalesce(round((x ->> 'profit_per_aircraft_hour')::numeric * 1000000)::text, 'none'), ' ' order by x ->> 'dest') into hours
    from jsonb_array_elements(r -> 'routes') x;
  -- 20,000 a flight over 11.17 hours: 1,791 an aircraft hour, on both
  assert hours = 'ZL2=11.17/14/1791 ZL3=11.17/14/1791', 'the hours a flight, flights a week and profit an aircraft hour are ' || hours;

  -- ---------------------------------------------------------------- 2. aircraft_profit(): a line aircraft's day
  select y into a from jsonb_array_elements(r -> 'aircraft') y where y ->> 'registration' = 'ZL-L3';
  assert a is not null and (a ->> 'flights')::int = 1, 'ZL-L3 should have its one flight: ' || coalesce(a::text, 'none');
  assert round((a ->> 'flight_profit_day')::numeric * 1000000) = round(20000 * 2 / 7.0),
    'a line aircraft''s flight profit a day should be 20k × 2 / 7, not ' || (a ->> 'flight_profit_day');
  select y into a from jsonb_array_elements(r -> 'aircraft') y where y ->> 'registration' = 'ZL-P';
  assert round((a ->> 'flight_profit_day')::numeric * 1000000) = 40000,
    'the plain aircraft''s flight profit a day should be 20k × 14 / 7, not ' || coalesce(a ->> 'flight_profit_day', 'none');

  -- ---------------------------------------------------------------- 3. the loads check: that weekday's flights only
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (w, a1, 'Line One', 'loads', '/test', '[]', t + interval '30 minutes') returning id into rid;
  e := private.capture_expect(rid);
  assert (e ->> 'scheduled')::int = 4, 'a loads page''s window should hold 4 flights (2 of the line''s, 2 of the plain aircraft''s), not '
    || coalesce(e ->> 'scheduled', 'none') || ': ' || e::text;

  raise notice 'long haul lines: a line route''s aircraft hours a flight are 11.17 across its 7 aircraft (as a plain route''s), 14 flights a week, the same profit an aircraft hour; a line aircraft''s flight profit a day is 2 flights over 7 days; the loads check expects that weekday''s line flights only (4 in the window)';
end
$test$;

-- Add a flight or raise fares, by profit per aircraft hour (manual §3; migration
-- 20261017180000_add_or_raise_aircraft_hour.sql; brief docs/briefs/2026-10-17-add-or-raise.md). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (names, hours and marks of the hand-made routes only).
-- Everything is made in a world of its own, so nothing on the copy is touched.
--   One airline flying from ZZ1, five routes launched long ago, each with 6 flights in its last 24 hours of bank statement
--   and loads matched to every one, all sold out (economy 100%), at T = 2030-01-15 11:00 UTC. One aircraft type: turnaround
--   60 minutes, 800 km/h; the world's turn margin 10 minutes and block allowance 25.
--     route  block out/back      aircraft hours          profit a flight   an aircraft hour
--     ZZ2    60 / 60             (60+60+10)/60 = 2.17    10k               4.6k
--     ZZ3    420 / 420           (420+70)/60 = 8.17      30k               3.7k
--     ZZ4    180 / 180           (180+70)/60 = 4.17      20k               4.8k
--     ZZ5    120 / untimed       untimed = 25 + 1000 km ÷ 800 = 100, so (110+70)/60 = 3.00   12k   4.0k
--     ZZ6    no legs on record   none                    25k               none
--   1. The hours and the profit an aircraft hour are as above.
--   2. The marks: the middle route by the hour is ZZ2 (4.6k), so ZZ2 and ZZ4 add, ZZ3 and ZZ5 raise; ZZ6, with no hours,
--      is compared by profit a flight (middle 20k), so add. By profit a flight alone ZZ2 would raise and ZZ3 add.
--   3. The why says which: an aircraft hour for ZZ2, a flight for ZZ6.
--   4. The turn margin is read for the airline: at 70 minutes the hours grow (ZZ2 3.17, ZZ3 9.17, ZZ4 5.17, ZZ5 4.00),
--      the middle route becomes ZZ3 (3.3k), and ZZ2 now raises while ZZ3 adds.

do $test$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; a1 bigint; ty bigint; ac bigint; r_id bigint; rot bigint;
  t timestamptz := '2030-01-15 11:00:00+00';
  d text; k int; i int; v_out int; v_back int; v_profit numeric; v_posted timestamptz;
  r jsonb; marks text; hours text;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'add or raise test', true);

  -- ---------------------------------------------------------------- the hand-made world
  insert into public.airports (code, utc_offset) values ('ZZ1', 5.50), ('ZZ2', 0.00), ('ZZ3', 0.00), ('ZZ4', 0.00), ('ZZ5', 0.00), ('ZZ6', 0.00)
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('add or raise test', 'add-or-raise.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  update public.settings set value = '10'::jsonb where world_id = w and airline_id is null and key = 'turn_margin_min';
  update public.settings set value = '25'::jsonb where world_id = w and airline_id is null and key = 'block_allowance_min';
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990201, 'Hour One', 'One', 'H1', 'ZZ1', true, 1) returning id into a1;
  insert into public.aircraft_types (world_id, name, min_turn_min, cruise_kmh) values (w, 'HOUR TEST TYPE', 60, 800) returning id into ty;

  -- five routes: (destination, block out, block back (null = untimed, -1 = no legs), profit a flight); every flight sold out
  for d, v_out, v_back, v_profit in
    select * from (values ('ZZ2', 60, 60, 10000), ('ZZ3', 420, 420, 30000), ('ZZ4', 180, 180, 20000),
                          ('ZZ5', 120, null::int, 12000), ('ZZ6', -1, -1, 25000)) x(d, o, b, p)
  loop
    k := right(d, 1)::int;
    insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZZ1', d, 1000, 'research') returning id into r_id;
    insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r_id, date '2029-12-01') returning id into rot;
    if v_out >= 0 then
      insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code, acquired)
      values (w, a1, 'ZZ-HR' || k, ty, 'active', 'ZZ1', 'new') returning id into ac;
      insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
        (w, a1, rot, 1, 3000 + k * 2, 'ZZ1', d, ac, '{1,2,3,4,5,6,7}', 360, v_out),
        (w, a1, rot, 2, 3001 + k * 2, d, 'ZZ1', ac, '{1,2,3,4,5,6,7}', 720, v_back);
    end if;
    for i in 1..6 loop
      v_posted := t - make_interval(mins => i * 60 + k);   -- every route's blocks at their own minutes
      insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code,
                                       pax_income, cargo_income, fuel, income_total, cost_total, money_captured_at)
      values (w, a1, v_posted, 1, 1, 'ZZ1', d, 30000 + v_profit, 0, 30000, 30000 + v_profit, 30000, t);
      -- the loads row departs at the block's own time (ZZ1 is UTC+5:30), so each block is matched to it
      insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, eco_pct, eco_fare, loads_captured_at)
      values (w, a1, ((v_posted at time zone 'UTC') + interval '330 minutes')::date, 4000 + k * 10 + i, 'ZZ1', d,
              to_char((v_posted at time zone 'UTC') + interval '330 minutes', 'HH24:MI'), 100, 100, t);
    end loop;
  end loop;

  -- ---------------------------------------------------------------- 1. the hours and the profit an aircraft hour
  r := private.fig_route_profit(a1, 7, t + interval '1 hour');
  assert (select count(*) from jsonb_array_elements(r -> 'routes') x where (x ->> 'with_loads')::int = 6 and (x ->> 'sold_out')::int = 6) = 5,
    'every route should have its 6 flights matched and sold out: ' || (r -> 'routes')::text;
  select string_agg(x ->> 'dest' || '=' || coalesce(round((x ->> 'aircraft_hours')::numeric, 2)::text, 'none'), ' ' order by x ->> 'dest') into hours
    from jsonb_array_elements(r -> 'routes') x;
  assert hours = 'ZZ2=2.17 ZZ3=8.17 ZZ4=4.17 ZZ5=3.00 ZZ6=none', 'the aircraft hours are ' || hours;
  select string_agg(x ->> 'dest' || '=' || coalesce(round((x ->> 'profit_per_aircraft_hour')::numeric * 1000, 1)::text, 'none'), ' ' order by x ->> 'dest') into hours
    from jsonb_array_elements(r -> 'routes') x;
  assert hours = 'ZZ2=4.6 ZZ3=3.7 ZZ4=4.8 ZZ5=4.0 ZZ6=none', 'the profit an aircraft hour (k) is ' || hours;

  -- ---------------------------------------------------------------- 2. the marks
  select string_agg(x ->> 'dest' || '=' || (x ->> 'mark'), ' ' order by x ->> 'dest') into marks from jsonb_array_elements(r -> 'routes') x;
  assert marks = 'ZZ2=add ZZ3=raise ZZ4=add ZZ5=raise ZZ6=add', 'the marks are ' || marks || ', not ZZ2=add ZZ3=raise ZZ4=add ZZ5=raise ZZ6=add';

  -- ---------------------------------------------------------------- 3. the why
  assert (select x ->> 'why' from jsonb_array_elements(r -> 'routes') x where x ->> 'dest' = 'ZZ2')
         = 'sold out on 6 of 6 departures, profit an aircraft hour at or above the airline''s middle route',
    'ZZ2''s why: ' || (select x ->> 'why' from jsonb_array_elements(r -> 'routes') x where x ->> 'dest' = 'ZZ2');
  assert (select x ->> 'why' from jsonb_array_elements(r -> 'routes') x where x ->> 'dest' = 'ZZ3')
         = 'sold out on 6 of 6 departures, profit an aircraft hour below the airline''s middle route',
    'ZZ3''s why: ' || (select x ->> 'why' from jsonb_array_elements(r -> 'routes') x where x ->> 'dest' = 'ZZ3');
  assert (select x ->> 'why' from jsonb_array_elements(r -> 'routes') x where x ->> 'dest' = 'ZZ6')
         = 'sold out on 6 of 6 departures, profit a flight at or above the airline''s middle route',
    'ZZ6''s why: ' || (select x ->> 'why' from jsonb_array_elements(r -> 'routes') x where x ->> 'dest' = 'ZZ6');

  -- ---------------------------------------------------------------- 4. the airline's own turn margin
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  values (w, a1, 'turn_margin_min', '70'::jsonb, 'min', 'test: this airline turns with 70 minutes'' margin');
  r := private.fig_route_profit(a1, 7, t + interval '1 hour');
  select string_agg(x ->> 'dest' || '=' || coalesce(round((x ->> 'aircraft_hours')::numeric, 2)::text, 'none'), ' ' order by x ->> 'dest') into hours
    from jsonb_array_elements(r -> 'routes') x;
  assert hours = 'ZZ2=3.17 ZZ3=9.17 ZZ4=5.17 ZZ5=4.00 ZZ6=none', 'with a 70-minute margin the aircraft hours are ' || hours;
  select string_agg(x ->> 'dest' || '=' || (x ->> 'mark'), ' ' order by x ->> 'dest') into marks from jsonb_array_elements(r -> 'routes') x;
  assert marks = 'ZZ2=raise ZZ3=add ZZ4=add ZZ5=raise ZZ6=add', 'with a 70-minute margin the marks are ' || marks;

  raise notice 'add or raise: aircraft hours are block + turnaround + margin (an untimed leg estimated), profit an aircraft hour against the airline''s middle route marks add and raise, a route with no legs falls back to profit a flight, and the airline''s own margin is read';
end
$test$;

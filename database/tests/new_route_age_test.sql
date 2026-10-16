-- New routes aren't judged for a week (manual §3; migration 20261016120000_new_route_age.sql; spec
-- docs/specs/2026-10-16-new-route-age.md). Run by database/rehearse.sh on the copy of last night's backup, after the
-- new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (names
-- and marks of the hand-made routes only). Everything is made in a world of its own, so nothing on the copy is touched.
--   One airline flying from ZZ1, five routes, each with 6 flights in its last 24 hours of bank statement and loads
--   matched to every one (economy 50%), at T = 2030-01-15 11:00 UTC:
--     ZZ2  launched long ago, each flight loses 10k   -> losing
--     ZZ3  launched 12 Jan (3 days old at T), loses   -> hold while young, losing once old
--     ZZ4  launched long ago, earns 10k, economy 50%  -> fix
--     ZZ5  launched 12 Jan, earns 10k, economy 50%    -> hold while young, fix once old
--     ZZ6  no launch day on record, loses             -> losing (no launch day counts as old)
--   1. growth_new_route_days is a setting in every world, 7 in the default world, described.
--   2. At T the marks are as above: young routes get no problem mark.
--   3. The edge: 6 days old (18 Jan) still young, 7 days old (19 Jan) judged, and 8 days (20 Jan) too.
--   4. With the setting at 0 nothing is young: ZZ3 is losing and ZZ5 is fix at T.
--   5. An airline's own value wins over the world's: with 60 days for the airline, every route with a launch day is
--      still young at T (ZZ2 and ZZ4 launched 45 days earlier), and only ZZ6 is judged.

do $test$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; a1 bigint;
  t timestamptz := '2030-01-15 11:00:00+00';
  d text; k int; i int; v_launch date; v_inc numeric; v_posted timestamptz;
  r jsonb; got text;
  -- the marks of the five routes at a moment, by destination, as 'ZZ2=losing ZZ3=hold ...'
  marks text;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'new route age test', true);

  -- ---------------------------------------------------------------- 1. the setting
  assert not exists (select 1 from public.worlds x
                      where not exists (select 1 from public.settings s where s.world_id = x.id and s.airline_id is null
                                           and s.key = 'growth_new_route_days' and s.description is not null and s.unit = 'days')),
    'a world has no described growth_new_route_days setting';
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'growth_new_route_days') = '7'::jsonb,
    'growth_new_route_days isn''t 7 in the default world';

  -- ---------------------------------------------------------------- the hand-made world
  insert into public.airports (code, utc_offset) values ('ZZ1', 5.50), ('ZZ2', 0.00), ('ZZ3', 0.00), ('ZZ4', 0.00), ('ZZ5', 0.00), ('ZZ6', 0.00)
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('new route age test', 'new-route-age.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990101, 'Age One', 'One', 'A1', 'ZZ1', true, 1) returning id into a1;

  -- five routes: (destination, launch day, income per flight, cost per flight); the loads are 50% economy on every flight
  for d, v_launch, v_inc in
    select * from (values ('ZZ2', date '2029-12-01', 20000), ('ZZ3', date '2030-01-12', 20000), ('ZZ4', date '2029-12-01', 40000),
                          ('ZZ5', date '2030-01-12', 40000), ('ZZ6', null::date, 20000)) x(d, l, inc)
  loop
    k := right(d, 1)::int;
    declare r_id bigint;
    begin
      insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZZ1', d, 1000, 'research') returning id into r_id;
      insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r_id, v_launch);
    end;
    for i in 1..6 loop
      v_posted := t - make_interval(mins => i * 60 + k);   -- every route's blocks at their own minutes
      insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code,
                                       pax_income, cargo_income, fuel, income_total, cost_total, money_captured_at)
      values (w, a1, v_posted, 1, 1, 'ZZ1', d, v_inc, 0, 30000, v_inc, 30000, t);
      -- the loads row departs at the block's own time (ZZ1 is UTC+5:30), so each block is matched to it
      insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, eco_pct, eco_fare, loads_captured_at)
      values (w, a1, ((v_posted at time zone 'UTC') + interval '330 minutes')::date, 2000 + k * 10 + i, 'ZZ1', d,
              to_char((v_posted at time zone 'UTC') + interval '330 minutes', 'HH24:MI'), 50, 100, t);
    end loop;
  end loop;

  -- ---------------------------------------------------------------- 2. at T
  r := private.fig_route_profit(a1, 7, t + interval '1 hour');
  assert (r ->> 'flights')::int = 30, format('the 5 routes'' blocks: %s flights, not 30', r ->> 'flights');
  assert (select count(*) from jsonb_array_elements(r -> 'routes') x where (x ->> 'with_loads')::int = 6) = 5,
    'a route''s loads weren''t matched to its 6 flights: ' || (r -> 'routes')::text;
  select string_agg(x ->> 'dest' || '=' || (x ->> 'mark'), ' ' order by x ->> 'dest') into marks from jsonb_array_elements(r -> 'routes') x;
  assert marks = 'ZZ2=losing ZZ3=hold ZZ4=fix ZZ5=hold ZZ6=losing', 'at T the marks are ' || marks || ', not ZZ2=losing ZZ3=hold ZZ4=fix ZZ5=hold ZZ6=losing';
  assert (select x ->> 'why' from jsonb_array_elements(r -> 'routes') x where x ->> 'dest' = 'ZZ3') = '',
    'a young route held back from the problem marks still carries a reason: it should carry none';

  -- ---------------------------------------------------------------- 3. the edge: launched 12 Jan, young under 7 days
  for d, got in select * from (values ('2030-01-18 11:00:00+00', 'ZZ2=losing ZZ3=hold ZZ4=fix ZZ5=hold ZZ6=losing'),
                                      ('2030-01-19 11:00:00+00', 'ZZ2=losing ZZ3=losing ZZ4=fix ZZ5=fix ZZ6=losing'),
                                      ('2030-01-20 11:00:00+00', 'ZZ2=losing ZZ3=losing ZZ4=fix ZZ5=fix ZZ6=losing')) x(at, want)
  loop
    r := private.fig_route_profit(a1, 7, d::timestamptz);
    select string_agg(x ->> 'dest' || '=' || (x ->> 'mark'), ' ' order by x ->> 'dest') into marks from jsonb_array_elements(r -> 'routes') x;
    assert marks = got, format('at %s the marks are %s, not %s', d, marks, got);
  end loop;

  -- ---------------------------------------------------------------- 4. the setting at 0: nothing is young
  update public.settings set value = '0'::jsonb where world_id = w and airline_id is null and key = 'growth_new_route_days';
  r := private.fig_route_profit(a1, 7, t + interval '1 hour');
  select string_agg(x ->> 'dest' || '=' || (x ->> 'mark'), ' ' order by x ->> 'dest') into marks from jsonb_array_elements(r -> 'routes') x;
  assert marks = 'ZZ2=losing ZZ3=losing ZZ4=fix ZZ5=fix ZZ6=losing', 'with the setting at 0 the marks are ' || marks;

  -- ---------------------------------------------------------------- 5. the airline's own value wins over the world's
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  values (w, a1, 'growth_new_route_days', '60'::jsonb, 'days', 'test: this airline waits 60 days');
  r := private.fig_route_profit(a1, 7, t + interval '1 hour');
  select string_agg(x ->> 'dest' || '=' || (x ->> 'mark'), ' ' order by x ->> 'dest') into marks from jsonb_array_elements(r -> 'routes') x;
  -- 60 days: even the routes launched 45 days before T are young, so only the one with no launch day on record is judged
  assert marks = 'ZZ2=hold ZZ3=hold ZZ4=hold ZZ5=hold ZZ6=losing', 'with 60 days for the airline the marks are ' || marks;

  raise notice 'new routes: growth_new_route_days is 7 in every world, described; at T the 3-day-old routes get no problem mark (hold) while the old ones and the one with no launch day do; 6 days old is still young, 7 is judged; 0 turns it off and an airline''s own value of 60 days holds back even the 45-day-old routes';
end
$test$;

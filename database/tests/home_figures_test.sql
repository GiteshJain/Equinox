-- Home's figures in the database (decision #19, build pull request 5, the Building chat's review): the two settings
-- that were numbers in the old planner's code, route_loads() (the old planner's loadStats), the group's average economy
-- load in airline_cards() and growth_signals()'s profit_captured. Run by database/rehearse.sh on the copy of last
-- night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an error
-- that says where (names and figures of the hand-made rows only). Everything else is made in a world of its own, so
-- nothing on the copy is touched or counted:
--   airline One (home and hub ZZ1, UTC; ZZ2 UTC too) flies ZZ1-ZZ2 daily both ways (flights 101 and 102), launched on
--   Sun 11 Jan 2030. Load reports typed before T1 = Tue 15 Jan 2030 12:00 UTC: 10 Jan (before the launch), 11, 12 and
--   13 Jan done, with loads for some flights (a 0 among them); 14 Jan typed after T1. The loads pages captured on
--   17 Jan, after T1: flights dated 9, 10, 16 (one flight twice) and 17 Jan, one with no economy load, one captured
--   later still. A bank-statement line posted on 12 Jan, its money captured on 16 Jan.
--   1. The settings: airport_cap_warning_pct 80 and aircraft_check_after_days in every world, with unit, description,
--      since and reason; rules_input() carries them (aircraft_check_after_days set to 7 by the test, since 15 Oct).
--   2. Who may call route_loads(): signed in only, stable, as owner with an empty search path, described; its builder
--      is internal (captured_figures_test.sql checks every private.fig_* builder).
--   3. route_loads() at T1: the done days of the last 7, none before the launch, a flight without a load (or typed 0)
--      as 97.5%; departures, sum, average, bands and days. 3b (build pull request 6): the same for each flight number,
--      adding up to its route's.
--   4. airline_cards()'s group load: at T1 from the reports (as route_loads() counts them), at T2 = Thu 17 Jan 12:00
--      from the captures (one per date and flight, the latest row, from 7 days before today, captured by then), and
--      none before anything was reported or captured.
--   5. growth_signals()'s profit_captured: false at T1 (the statement's money not yet captured), true at T2.
--   6. Signed out and an account that isn't staff are refused route_loads(); staff get what postgres gets.

create temporary table t_hf (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_hf to authenticated, anon;
insert into public.planner_users (email) values ('home-figures-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the settings
-- aircraft_check_after_days is Gitesh's to change since 15 Oct (0 turns the one-week checks off, spec
-- docs/specs/2026-10-15-aircraft-checks-off.md), so the test sets it to 7 itself (rolled back with the rest) rather than
-- hang on the value, or the date, last night's backup holds
update public.settings set value = '7'::jsonb where key = 'aircraft_check_after_days' and airline_id is null;
do $test$
declare n_worlds int := (select count(*) from public.worlds); doc jsonb;
begin
  assert (select count(*) from public.settings s where s.key = 'airport_cap_warning_pct' and s.airline_id is null and s.value = '80'::jsonb
            and s.unit = '% of the cap' and s.since = date '2026-10-13' and s.description like '%cap%' and s.reason like '%4,000 of the 5,000%') = n_worlds,
    'airport_cap_warning_pct isn''t 80 (% of the cap, since 13 Oct, with its reason) in every world';
  assert (select count(*) from public.settings s where s.key = 'aircraft_check_after_days' and s.airline_id is null and s.value = '7'::jsonb
            and s.unit = 'days' and s.since >= date '2026-10-13' and s.description like '%one-week check%' and s.reason is not null) = n_worlds,
    'aircraft_check_after_days isn''t in every world (days, since 13 Oct or later, with its reason)';
  doc := private.rules_input_doc(null, 'flown');
  assert doc -> 'settings' -> 'airport_cap_warning_pct' = '80'::jsonb and doc -> 'settings' -> 'aircraft_check_after_days' = '7'::jsonb,
    'rules_input() doesn''t carry the two settings';
  raise notice 'the settings: airport_cap_warning_pct 80 and aircraft_check_after_days (7, set by the test) in each of the % world(s), described, since 13 Oct or later with their reasons; rules_input() carries them', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. who may call route_loads()
do $test$
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'public.route_loads(bigint, timestamptz)'::regprocedure), 'route_loads() isn''t stable, run as owner with an empty search path';
  assert not has_function_privilege('anon', 'public.route_loads(bigint, timestamptz)', 'execute'), 'signed out, route_loads() can be called';
  assert has_function_privilege('authenticated', 'public.route_loads(bigint, timestamptz)', 'execute'), 'signed in, route_loads() can''t be called';
  assert obj_description('public.route_loads(bigint, timestamptz)'::regprocedure, 'pg_proc') like '%loadStats%', 'route_loads() has no description';
  assert not has_function_privilege('authenticated', 'private.fig_route_loads(bigint, timestamptz)', 'execute'), 'route_loads()''s builder can be called from outside';
  raise notice 'who may call route_loads(): signed in only, stable, as owner with an empty search path, described; its builder internal';
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
do $setup$
declare
  w bigint; g bigint; a1 bigint; r1 bigint; rot bigint; ac bigint;
  t1 timestamptz := '2030-01-15 12:00:00+00'; cap timestamptz := '2030-01-17 10:00:00+00';
  dw bigint := (select id from public.worlds where is_default);
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'home figures test', true);
  insert into public.airports (code, utc_offset) values ('ZZ1', 0), ('ZZ2', 0) on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('home figures test', 'home-figures.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990101, 'Loads One', 'One', 'L1', 'ZZ1', true, 1) returning id into a1;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, a1, 'ZZ1', 'hub', true, 0);
  insert into public.aircraft (world_id, airline_id, registration, status, base_code, acquired) values (w, a1, 'L1-001', 'active', 'ZZ1', 'new') returning id into ac;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZZ1', 'ZZ2', 500, 'research') returning id into r1;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r1, '2030-01-11') returning id into rot;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min)
  values (w, a1, rot, 1, 101, 'ZZ1', 'ZZ2', ac, '{1,2,3,4,5,6,7}', 360, 60), (w, a1, rot, 2, 102, 'ZZ2', 'ZZ1', ac, '{1,2,3,4,5,6,7}', 600, 60);

  -- the load reports, typed before T1 (14 Jan's after it)
  insert into public.load_days (world_id, game_date, done, entered_at) values
    (w, '2030-01-10', true, t1 - interval '5 days'), (w, '2030-01-11', true, t1 - interval '4 days'),
    (w, '2030-01-12', true, t1 - interval '3 days'), (w, '2030-01-13', true, t1 - interval '2 days'), (w, '2030-01-14', true, t1 + interval '1 hour');
  insert into public.load_entries (world_id, airline_id, game_date, flight_no, eco_pct, entered_at) values
    (w, a1, '2030-01-10', 101, 40, t1 - interval '5 days'),
    (w, a1, '2030-01-11', 101, 90, t1 - interval '4 days'), (w, a1, '2030-01-11', 102, 0, t1 - interval '4 days'),
    (w, a1, '2030-01-12', 101, 72, t1 - interval '3 days'),
    (w, a1, '2030-01-13', 101, 60, t1 - interval '2 days'), (w, a1, '2030-01-13', 102, 88, t1 - interval '2 days'),
    (w, a1, '2030-01-14', 101, 30, t1 + interval '1 hour');

  -- the loads pages, captured on 17 Jan (after T1): 9 Jan is outside the 7 days before T2's 17 Jan; 16 Jan's 102 came
  -- twice (the later row counts); one row has no economy load; 17 Jan's 102 was captured after T2
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, registration, eco_pct, loads_captured_at) values
    (w, a1, '2030-01-09', 101, 'ZZ1', 'ZZ2', '06:00', 'L1-001', 10, cap),
    (w, a1, '2030-01-10', 101, 'ZZ1', 'ZZ2', '06:00', 'L1-001', 80, cap),
    (w, a1, '2030-01-16', 101, 'ZZ1', 'ZZ2', '06:00', 'L1-001', 100, cap),
    (w, a1, '2030-01-16', 102, 'ZZ2', 'ZZ1', '10:00', 'L1-001', 50, cap),
    (w, a1, '2030-01-16', 102, 'ZZ2', 'ZZ1', '10:05', 'L1-001', 70, cap),
    (w, a1, '2030-01-17', 101, 'ZZ1', 'ZZ2', '06:00', 'L1-001', 95, cap),
    (w, a1, '2030-01-17', 103, 'ZZ1', 'ZZ2', '08:00', 'L1-001', null, cap),
    (w, a1, '2030-01-17', 102, 'ZZ2', 'ZZ1', '10:00', 'L1-001', 20, cap + interval '3 hours');
  -- a bank-statement line posted on 12 Jan, its money captured on 16 Jan
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code,
                                   pax_income, cargo_income, fuel, income_total, cost_total, money_captured_at)
  values (w, a1, '2030-01-12 08:00:00+00', 1, 1, 'ZZ1', 'ZZ2', 50000, 0, 30000, 50000, 30000, '2030-01-16 10:00:00+00');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_hf values ('w', to_jsonb(w)), ('a1', to_jsonb(a1)), ('r1', to_jsonb(r1));
end
$setup$;

-- ---------------------------------------------------------------- 3. route_loads() at T1
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_hf where k = 'w'); d jsonb; r jsonb;
begin
  d := private.fig_route_loads(w, '2030-01-15 12:00:00+00');
  assert d ->> 'from' = '2030-01-09' and d ->> 'to' = '2030-01-15', 'route_loads(): the 7 days aren''t 9 to 15 Jan: ' || (d ->> 'from') || ' to ' || (d ->> 'to');
  assert jsonb_array_length(d -> 'routes') = 1, 'route_loads(): not one route';
  r := d -> 'routes' -> 0;
  -- 11 Jan: 90 and 0 (as 97.5); 12 Jan: 72 and 102 not reported (97.5); 13 Jan: 60 and 88. Not 10 Jan (before the launch),
  -- 14 Jan (typed after T1) or 15 Jan (not done)
  assert (r ->> 'hub') = 'ZZ1' and (r ->> 'dest') = 'ZZ2' and (r ->> 'departures')::int = 6 and (r ->> 'sum')::numeric = 505
     and (r ->> 'days')::int = 3 and (r ->> 'full')::int = 2 and (r ->> 'under_95')::int = 2 and (r ->> 'under_85')::int = 1 and (r ->> 'under_70')::int = 1
     and abs((r ->> 'average')::numeric - 505 / 6.0) < 1e-9,
    'route_loads(): ZZ1-ZZ2 isn''t 6 departures, sum 505, average 84.17, 3 days, bands 2/2/1/1: ' || r::text;
  raise notice 'route_loads() at T1: ZZ1-ZZ2 6 departures on 3 reported days (none before the launch, none typed later, a 0 and a missing load as 97.5%%), average %, bands 2 full, 2 under 95, 1 under 85, 1 under 70',
    round((r ->> 'average')::numeric, 2);
end
$test$;

-- ---------------------------------------------------------------- 3b. route_loads()'s flights at T1 (build pull request 6)
-- The Routes screen's lines: each flight number's loads over the same flights as its route's (loadStats' "F|airline|no")
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_hf where k = 'w'); d jsonb; f1 jsonb; f2 jsonb;
begin
  d := private.fig_route_loads(w, '2030-01-15 12:00:00+00');
  assert jsonb_array_length(d -> 'flights') = 2, 'route_loads(): not two flights: ' || (d -> 'flights')::text;
  f1 := d -> 'flights' -> 0;
  f2 := d -> 'flights' -> 1;
  -- 101: 90, 72 and 60 on 11 to 13 Jan; 102: 0 (as 97.5) on the 11th, not reported (97.5) on the 12th, 88 on the 13th
  assert (f1 ->> 'flight_no')::int = 101 and (f1 ->> 'departures')::int = 3 and (f1 ->> 'sum')::numeric = 222 and (f1 ->> 'average')::numeric = 74
     and (f1 ->> 'full')::int = 0 and (f1 ->> 'under_95')::int = 1 and (f1 ->> 'under_85')::int = 1 and (f1 ->> 'under_70')::int = 1 and (f1 ->> 'days')::int = 3,
    'route_loads(): flight 101 isn''t 3 departures, sum 222, bands 0/1/1/1, 3 days: ' || f1::text;
  assert (f2 ->> 'flight_no')::int = 102 and (f2 ->> 'departures')::int = 3 and (f2 ->> 'sum')::numeric = 283
     and (f2 ->> 'full')::int = 2 and (f2 ->> 'under_95')::int = 1 and (f2 ->> 'under_85')::int = 0 and (f2 ->> 'under_70')::int = 0 and (f2 ->> 'days')::int = 3,
    'route_loads(): flight 102 isn''t 3 departures, sum 283, bands 2/1/0/0, 3 days: ' || f2::text;
  assert (f1 ->> 'departures')::int + (f2 ->> 'departures')::int = (d -> 'routes' -> 0 ->> 'departures')::int
     and (f1 ->> 'sum')::numeric + (f2 ->> 'sum')::numeric = (d -> 'routes' -> 0 ->> 'sum')::numeric,
    'route_loads(): the flights don''t add up to their route';
  raise notice 'route_loads()''s flights at T1: 101 three departures averaging 74 (bands 0/1/1/1), 102 three averaging 94.33 (2/1/0/0), adding up to ZZ1-ZZ2''s 6';
end
$test$;

-- ---------------------------------------------------------------- 4. the group's average load in airline_cards()
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_hf where k = 'w'); c jsonb;
begin
  c := private.fig_airline_cards(w, '2030-01-15 12:00:00+00');
  assert c ->> 'load_7_days_from' = 'reports' and (c ->> 'load_7_days_flights')::int = 6 and abs((c ->> 'load_7_days')::numeric - 505 / 6.0) < 1e-9,
    'airline_cards() at T1: the group load isn''t the reports'' 505 / 6: ' || (c - 'airlines' - 'group_today')::text;
  c := private.fig_airline_cards(w, '2030-01-17 12:00:00+00');
  -- 10 Jan 80, 16 Jan 100 and 70 (the later of 102's two rows), 17 Jan 95; not 9 Jan, not the row with no load, not 17 Jan's 102
  assert c ->> 'load_7_days_from' = 'captures' and (c ->> 'load_7_days_flights')::int = 4 and (c ->> 'load_7_days')::numeric = 86.25,
    'airline_cards() at T2: the group load isn''t the captures'' 86.25 over 4 flights: ' || (c - 'airlines' - 'group_today')::text;
  c := private.fig_airline_cards(w, '2030-01-01 12:00:00+00');
  assert c -> 'load_7_days' = 'null'::jsonb and (c ->> 'load_7_days_flights')::int = 0 and c -> 'load_7_days_from' = 'null'::jsonb,
    'airline_cards() before anything: the group load isn''t empty: ' || (c - 'airlines' - 'group_today')::text;
  raise notice 'airline_cards()''s group load: at T1 from the reports (84.17 over 6 flights), at T2 from the captures (86.25 over 4: one per date and flight, the latest row, 7 days back, captured by then), none before either';
end
$test$;

-- ---------------------------------------------------------------- 5. growth_signals()'s profit_captured
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_hf where k = 'w');
begin
  assert private.fig_growth_signals(w, '2030-01-15 12:00:00+00') -> 'profit_captured' = 'false'::jsonb, 'growth_signals() at T1: profit_captured isn''t false';
  assert private.fig_growth_signals(w, '2030-01-17 12:00:00+00') -> 'profit_captured' = 'true'::jsonb, 'growth_signals() at T2: profit_captured isn''t true';
  assert private.fig_growth_signals(w, '2030-01-25 12:00:00+00') -> 'profit_captured' = 'false'::jsonb, 'growth_signals() 13 days on: profit_captured isn''t false';
  raise notice 'growth_signals()''s profit_captured: false before the statement''s money was captured, true after, false once it''s older than the 8 days';
end
$test$;

-- ---------------------------------------------------------------- 6. who is refused
set local role anon;
do $test$
declare refused boolean := false;
begin
  begin perform public.route_loads(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'signed out, route_loads() wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d1", "email": "home-figures-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  begin perform public.route_loads(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff wasn''t refused route_loads()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d2", "email": "home-figures-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_hf where k = 'w');
begin
  insert into t_hf values ('staff', public.route_loads(w, '2030-01-15 12:00:00+00'));
end
$test$;
reset role;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_hf where k = 'w');
begin
  assert (select v from t_hf where k = 'staff') = private.fig_route_loads(w, '2030-01-15 12:00:00+00'), 'staff don''t get what postgres gets from route_loads()';
  raise notice 'signed out and an account that isn''t staff are refused route_loads(); staff get what postgres gets';
end
$test$;

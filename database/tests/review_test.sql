-- The new planner's Review and the plan card's service check in the database (decision #18, build pull request 10, spec
-- docs/specs/2026-10-14-review.md): rules_input()'s service profiles, cash_log() (the old planner's finSeries,
-- applyCaptureCash and cashEntryHtml), fare_plan_status() (routeFares and farePlanStatus), and the three figures the old
-- Review worked out on its screen, now in airline_profit(), route_profit() and airline_cards(). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (names and figures of the hand-made rows only, counts on the
-- copy). The hand-made rows are in a world of their own, so nothing on the copy is touched or counted:
--   airline Review One (home and hub ZR1, UTC) with route ZR1-ZR2. The moment M = Tue 15 Jan 2030 12:00 UTC.
--   Balances (account 2800): 1 Jan 4.00M, 13 Jan 8.00M (captured M - 2 d 1 h), 15 Jan 10,004,999 AS$ (M - 1 h); typed:
--   1 Jan 5.00M with 0.70M fixed costs, and 15 Jan 12.34M with 1.50M. The events page: the week-end closing (1.00M) on
--   18 Jan 17:30 and a lease (0.25M) on 20 Jan 17:30.
--   Loads with economy fares on ZR1-ZR2, both ways: 5 Jan (outside the 9 days), 10 Jan (100 and 110; 90% and 80%),
--   12 Jan (104; 85%), 13 Jan (108 and 110; 70% and 60%), 14 Jan (112; 50%), and one captured after M. A fare change
--   planned on 11 Jan: +10% from 100; another dropped.
--   1. rules_input() carries the world's service profiles, every row, with 'all' and 'flown' alike; the setting
--      fare_plan_raise_pct (5) is in every world.
--   2. Who may call cash_log() and fare_plan_status(): signed in only, stable, as owner with an empty search path,
--      described; their builders internal.
--   3. cash_log() at M: each reported day's cash and fixed costs as the old planner shows them, and today's figures
--      (shown, stored, captured, the typed row).
--   4. fare_plan_status() at M: the fare now, the target, seen on 13 Jan (the first day with at least half the change),
--      the economy load before and after over every flight, the dropped change left out, each route's latest fare.
--   5. On the copy, every airline: airline_profit()'s per_aircraft_day is profit a day over the aircraft flying; the
--      average flight's profit is its income less its costs, and its margin profit over income; the group today's
--      leases_and_closing_day is leases plus closing.
--   6. Signed out and an account that isn't staff are refused both new functions; staff get what postgres gets.

create temporary table t_rv (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_rv to authenticated, anon;
insert into public.planner_users (email) values ('review-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. rules_input()'s service profiles
do $test$
declare d_all jsonb := private.rules_input_doc(null, 'all'); d_flown jsonb := private.rules_input_doc(null, 'flown');
  w bigint := (select id from public.worlds where is_default); n int;
begin
  n := (select count(*) from public.service_profiles s where s.world_id = w);
  assert jsonb_typeof(d_all -> 'service_profiles') = 'array' and jsonb_array_length(d_all -> 'service_profiles') = n,
    format('rules_input() doesn''t carry the world''s %s service profiles', n);
  assert d_all -> 'service_profiles' = d_flown -> 'service_profiles', 'rules_input()''s service profiles differ between all and flown';
  assert not exists (select 1 from public.service_profiles s where s.world_id = w
                      and not exists (select 1 from jsonb_array_elements(d_all -> 'service_profiles') x
                                       where (x ->> 'id')::bigint = s.id and x ->> 'code' is not distinct from s.code
                                         and (x ->> 'airline_id')::bigint is not distinct from s.airline_id
                                         and (x ->> 'up_to_km')::int is not distinct from s.up_to_km)),
    'rules_input()''s service profiles aren''t the table''s rows';
  raise notice 'rules_input() carries the world''s % service profiles (% of them an airline''s own), the same with all and flown', n,
    (select count(*) from public.service_profiles s where s.world_id = w and s.airline_id is not null);
end
$test$;

-- the fare plan's rise, a number the old planner kept in its code
do $test$
declare n_worlds int := (select count(*) from public.worlds);
begin
  assert (select count(*) from public.settings s where s.key = 'fare_plan_raise_pct' and s.airline_id is null and s.value = '5'::jsonb
            and s.unit = 'percent' and s.since = date '2026-10-14' and s.description like '%+ fare plan%' and s.reason is not null) = n_worlds,
    'fare_plan_raise_pct isn''t 5 (percent, since 14 Oct, with its reason) in every world';
  assert private.rules_input_doc(null, 'flown') -> 'settings' -> 'fare_plan_raise_pct' = '5'::jsonb, 'rules_input() doesn''t carry fare_plan_raise_pct';
  raise notice 'the setting fare_plan_raise_pct is 5 in each of the % world(s), described, since 14 Oct with its reason; rules_input() carries it', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. who may call the two new functions
do $test$
declare f text;
begin
  foreach f in array array['public.cash_log(bigint, timestamptz)', 'public.fare_plan_status(bigint, timestamptz)'] loop
    assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
      f || ' isn''t stable, run as owner with an empty search path';
    assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
    assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
    assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 100, f || ' has no description';
  end loop;
  foreach f in array array['private.fig_cash_log(bigint, timestamptz)', 'private.fig_fare_plan(bigint, timestamptz)'] loop
    assert not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f || ' can be called from outside';
    assert obj_description(f::regprocedure, 'pg_proc') is not null, f || ' has no description';
  end loop;
  raise notice 'who may call cash_log() and fare_plan_status(): signed in only, stable, as owner with an empty search path, described; their builders internal';
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
do $setup$
declare
  w bigint; g bigint; a1 bigint; r1 bigint;
  m timestamptz := '2030-01-15 12:00:00+00';
  dw bigint := (select id from public.worlds where is_default);
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'review test', true);
  insert into public.airports (code, utc_offset) values ('ZR1', 0), ('ZR2', 0) on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('review test', 'review.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990201, 'Review One', 'One', 'R1', 'ZR1', true, 1) returning id into a1;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, a1, 'ZR1', 'hub', true, 0);
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZR1', 'ZR2', 900, 'research') returning id into r1;

  -- cash: the captured balances and the typed figures
  insert into public.game_balance (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at) values
    (w, a1, 'Review One', '2030-01-01', '2030-01-01', '2800 Bank account', 4000000, m - interval '14 days'),
    (w, a1, 'Review One', '2030-01-13', '2030-01-13', '2800 Bank account', 8000000, m - interval '49 hours'),
    (w, a1, 'Review One', '2030-01-15', '2030-01-15', '2800 Bank account', 10004999, m - interval '1 hour');
  insert into public.cash_entries (world_id, airline_id, day, cash, fixed_next7, entered_at) values
    (w, a1, '2030-01-01', 5000000, 700000, m - interval '14 days'),
    (w, a1, '2030-01-15', 12340000, 1500000, m - interval '2 hours');
  -- the events page (ZR1 is on UTC): 18 Jan 17:30 is M + 3 d 5.5 h, 20 Jan 17:30 is M + 5 d 5.5 h
  insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, debit, captured_at, due_at) values
    (w, a1, 'Review One', '2030-01-18', '17:30', 'Week-end closing of Review One', 1000000, m - interval '1 hour', '2030-01-18 17:30:00+00'),
    (w, a1, 'Review One', '2030-01-20', '17:30', 'Leasing payment for R1-001 (Test Jet)', 250000, m - interval '1 hour', '2030-01-20 17:30:00+00');

  -- loads with economy fares on the route, both ways
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, registration, eco_pct, eco_fare, loads_captured_at) values
    (w, a1, '2030-01-05', 101, 'ZR1', 'ZR2', '06:00', 'R1-001', 99, 50, m - interval '10 days'),
    (w, a1, '2030-01-10', 101, 'ZR1', 'ZR2', '06:00', 'R1-001', 90, 100, m - interval '5 days'),
    (w, a1, '2030-01-10', 102, 'ZR2', 'ZR1', '10:00', 'R1-001', 80, 110, m - interval '5 days'),
    (w, a1, '2030-01-12', 101, 'ZR1', 'ZR2', '06:00', 'R1-001', 85, 104, m - interval '3 days'),
    (w, a1, '2030-01-13', 101, 'ZR1', 'ZR2', '06:00', 'R1-001', 70, 108, m - interval '2 days'),
    (w, a1, '2030-01-13', 102, 'ZR2', 'ZR1', '10:00', 'R1-001', 60, 110, m - interval '2 days'),
    (w, a1, '2030-01-14', 101, 'ZR1', 'ZR2', '06:00', 'R1-001', 50, 112, m - interval '1 day'),
    (w, a1, '2030-01-15', 101, 'ZR1', 'ZR2', '06:00', 'R1-001', 40, 200, m + interval '1 hour');
  insert into public.fare_plan (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from, proposed_on, status, reason) values
    (w, a1, r1, 'fp-review-test-1', 'economy', 10, 100, '2030-01-11', 'planned', 'sells out'),
    (w, a1, r1, 'fp-review-test-2', 'economy', 5, 100, '2030-01-09', 'dropped', 'test: dropped');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_rv values ('w', to_jsonb(w)), ('a1', to_jsonb(a1)), ('r1', to_jsonb(r1)), ('m', to_jsonb(m));
end
$setup$;

-- ---------------------------------------------------------------- 3. cash_log() at M
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rv where k = 'w'); m timestamptz := (select (v #>> '{}')::timestamptz from t_rv where k = 'm');
  d jsonb; a jsonb; t jsonb;
begin
  d := private.fig_cash_log(w, m);
  assert d ->> 'today' = '2030-01-15' and jsonb_array_length(d -> 'airlines') = 1, 'cash_log(): not one airline on 15 Jan: ' || d::text;
  a := d -> 'airlines' -> 0;
  -- 1 Jan: older than 7 days, so the typed figures (5.00M, 0.70M); 13 Jan: captured, its fixed costs the closing in the 7
  -- days after its balance (the lease falls after them); 15 Jan: the capture's 10.00M (10,004,999 rounded) and both payments
  assert a -> 'days' = '[{"day": "2030-01-01", "cash": 5, "fixed": 0.7}, {"day": "2030-01-13", "cash": 8, "fixed": 1}, {"day": "2030-01-15", "cash": 10, "fixed": 1.25}]'::jsonb,
    'cash_log(): the days aren''t 1 Jan 5.00 / 0.70, 13 Jan 8.00 / 1.00, 15 Jan 10.00 / 1.25: ' || (a -> 'days')::text;
  t := a -> 'today';
  assert (t ->> 'shown_cash')::numeric = 10 and (t ->> 'shown_fixed')::numeric = 1.25 and (t ->> 'stored_cash')::numeric = 12.34
     and (t ->> 'stored_fixed')::numeric = 1.5 and (t ->> 'captured_cash')::numeric = 10 and (t ->> 'captured_fixed')::numeric = 1.25
     and (t #>> '{entry,cash}')::numeric = 12340000 and (t #>> '{entry,fixed_next7}')::numeric = 1500000 and t #>> '{entry,updated_at}' is not null,
    'cash_log(): today isn''t shown 10.00 / 1.25, stored 12.34 / 1.50, captured 10.00 / 1.25, typed 12,340,000 / 1,500,000: ' || t::text;
  insert into t_rv values ('cash_log', d);
  raise notice 'cash_log() at M: 3 reported days (a typed figure kept before the last 7 days, the capture''s within them, each day''s fixed costs the payments in the 7 days after its balance); today shown 10.00 / 1.25M against stored 12.34 / 1.50M, captured 10.00 / 1.25M and the typed row';
end
$test$;

-- ---------------------------------------------------------------- 4. fare_plan_status() at M
do $test$
declare a1 bigint := (select (v #>> '{}')::bigint from t_rv where k = 'a1'); r1 bigint := (select (v #>> '{}')::bigint from t_rv where k = 'r1');
  m timestamptz := (select (v #>> '{}')::timestamptz from t_rv where k = 'm'); d jsonb; p jsonb;
begin
  d := private.fig_fare_plan(a1, m);
  assert jsonb_array_length(d -> 'plan') = 1, 'fare_plan_status(): not one change planned (the dropped one left out): ' || (d -> 'plan')::text;
  p := d -> 'plan' -> 0;
  -- 12 Jan's 104 is under half the change (105); 13 Jan's average 109 is over it. Before: 90, 80 and 85; after: 70, 60 and 50
  assert (p ->> 'route_id')::bigint = r1 and p ->> 'hub' = 'ZR1' and p ->> 'dest' = 'ZR2' and (p ->> 'change_pct')::numeric = 10
     and (p ->> 'fare_from')::numeric = 100 and (p ->> 'target')::numeric = 110 and (p ->> 'fare_now')::numeric = 112
     and (p ->> 'applied')::boolean and p ->> 'seen_on' = '2030-01-13'
     and (p ->> 'economy_before')::numeric = 85 and (p ->> 'economy_after')::numeric = 60 and p ->> 'updated_at' is not null and p ->> 'legacy_key' = 'fp-review-test-1',
    'fare_plan_status(): the change isn''t +10% from 100 to 110, fare now 112, seen on 13 Jan, loads 85% before and 60% after: ' || p::text;
  assert d -> 'fares' = jsonb_build_array(jsonb_build_object('route_id', r1, 'hub', 'ZR1', 'dest', 'ZR2', 'day', '2030-01-14', 'fare', 112)),
    'fare_plan_status(): the route''s latest fare isn''t 112 on 14 Jan (5 Jan outside the 9 days, 15 Jan captured after M): ' || (d -> 'fares')::text;
  -- before the fare shows: not applied, no loads before and after
  p := private.fig_fare_plan(a1, '2030-01-13 00:00:00+00') -> 'plan' -> 0;
  assert not (p ->> 'applied')::boolean and p -> 'seen_on' = 'null'::jsonb and p -> 'economy_before' = 'null'::jsonb and (p ->> 'fare_now')::numeric = 104,
    'fare_plan_status() on 13 Jan 00:00: the change shows already, or the fare now isn''t 12 Jan''s 104: ' || p::text;
  insert into t_rv values ('fare', d);
  raise notice 'fare_plan_status() at M: +10%% from 100 (target 110), fare now 112, seen on 13 Jan (12 Jan''s 104 under half the change), economy 85%% before and 60%% after over every flight; the dropped change left out; not seen yet on 13 Jan 00:00; the route''s latest fare 112';
end
$test$;

-- ---------------------------------------------------------------- 5. the three figures the old Review worked out on its screen, on the copy
do $test$
declare al record; p jsonb; dd int; a jsonb; bad text; n_days int := 0; n_routes int := 0; m timestamptz := now();
  c jsonb := public.airline_cards(null, now());
begin
  for al in select x.airline_id from private.fig_airlines(private.fig_world(null)) x loop
    p := public.airline_profit(al.airline_id, m);
    select string_agg(x ->> 'date', ', ') into bad from jsonb_array_elements(p -> 'days') x
     where (x -> 'per_aircraft_day') is distinct from (case when coalesce((x ->> 'aircraft')::int, 0) <> 0
                                                            then to_jsonb((x ->> 'profit_day')::numeric / (x ->> 'aircraft')::int) else 'null'::jsonb end);
    assert bad is null, format('airline_profit(%s): per_aircraft_day isn''t profit a day over the aircraft on %s', al.airline_id, bad);
    n_days := n_days + jsonb_array_length(p -> 'days');
    foreach dd in array array[1, 3, 7] loop
      a := public.route_profit(al.airline_id, dd, m) -> 'average_flight';
      continue when a is null or a = 'null'::jsonb;
      assert (a ->> 'income')::numeric = (a ->> 'passengers')::numeric + (a ->> 'cargo')::numeric
         and (a ->> 'costs')::numeric = (a ->> 'fuel')::numeric + (a ->> 'handling')::numeric + (a ->> 'onboard')::numeric + (a ->> 'landing')::numeric
                                        + (a ->> 'air_traffic')::numeric + (a ->> 'maintenance')::numeric
         and (a ->> 'profit')::numeric = (a ->> 'income')::numeric - (a ->> 'costs')::numeric
         and (a -> 'margin') is not distinct from (case when (a ->> 'income')::numeric <> 0
                                                        then to_jsonb(((a ->> 'income')::numeric - (a ->> 'costs')::numeric) / (a ->> 'income')::numeric) else 'null'::jsonb end),
        format('route_profit(%s, %s): the average flight''s income, costs, profit or margin don''t add up: %s', al.airline_id, dd, a);
      n_routes := n_routes + 1;
    end loop;
  end loop;
  select string_agg(x ->> 'code', ', ') into bad from jsonb_array_elements(c -> 'group_today') x
   where (x ->> 'leases_and_closing_day')::numeric is distinct from (x ->> 'leases_day')::numeric + (x ->> 'closing_day')::numeric;
  assert bad is null, 'airline_cards(): leases_and_closing_day isn''t leases plus closing for ' || bad;
  raise notice 'on the copy: per_aircraft_day on % reported days, the average flight''s sums, profit and margin in % answers of route_profit(), leases and closing together on % rows of the group today',
    n_days, n_routes, jsonb_array_length(c -> 'group_today');
end
$test$;

-- ---------------------------------------------------------------- 6. who is refused; staff get what postgres gets
set local role anon;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rv where k = 'w'); a1 bigint := (select (v #>> '{}')::bigint from t_rv where k = 'a1'); n int := 0;
begin
  begin perform public.cash_log(w); exception when insufficient_privilege then n := n + 1; end;
  begin perform public.fare_plan_status(a1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 2, format('signed out, only %s of the 2 functions were refused', n);
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d1", "email": "review-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rv where k = 'w'); a1 bigint := (select (v #>> '{}')::bigint from t_rv where k = 'a1'); n int := 0;
begin
  begin perform public.cash_log(w); exception when insufficient_privilege then n := n + 1; end;
  begin perform public.fare_plan_status(a1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 2, format('an account that isn''t staff had only %s of the 2 functions refused', n);
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d2", "email": "review-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rv where k = 'w'); a1 bigint := (select (v #>> '{}')::bigint from t_rv where k = 'a1');
  m timestamptz := (select (v #>> '{}')::timestamptz from t_rv where k = 'm');
begin
  assert public.cash_log(w, m) = (select v from t_rv where k = 'cash_log'), 'staff don''t get what postgres gets from cash_log()';
  assert public.fare_plan_status(a1, m) = (select v from t_rv where k = 'fare'), 'staff don''t get what postgres gets from fare_plan_status()';
end
$test$;
reset role;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused both; staff get what postgres gets'; end $test$;

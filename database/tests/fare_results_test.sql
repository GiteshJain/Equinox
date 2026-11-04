-- Fare results (migration 20261103020000_fare_results.sql; spec docs/specs/2026-11-03-fare-results.md). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (codes and figures of the hand-made routes only). Everything is
-- made in a world of its own, so nothing on the copy is touched or counted.
--   The moment T is Tuesday 15 Jan 2030, 12:00 UTC (this Saturday: 12 Jan). One airline, FR (launch 100%, cap 20 points:
--   120%), hub ZF1; every evening from 31 Dec to 14 Jan captured complete (airline_days, taken 22:00 that day), so the latest
--   7 complete days by T are 8 to 14 Jan. Every route flies 2 flights a day each way unless said, each day's route_days
--   row 360 economy seats.
--     R1 ZF1–ZF2: out stepped up to 120% (the cap) on 5 Jan from 300 (+20%); the captured flights out show 300 to 6 Jan and
--        360 from 7 Jan (seen 7 Jan), back at 300 throughout. A step down to 115% put on the fare plan on 12 Jan (this
--        week) isn't seen yet: pending, and the level stays 120. Out: before (31 Dec to 6 Jan) 300 AS$, 100% full, 20,000
--        profit a day (10,000 a flight); now (8 to 14 Jan; 7 Jan is complete but not among the latest 7) 360 AS$, 95%
--        full, 26,000 a day (13,000 a flight): +30%, 14 flights a week, +42,000 a week. Its back direction has no change:
--        it is part of the baseline.
--     R2 ZF1–ZF3: no change seen; a change planned on it but never made doesn't make it repriced. The baseline with R1
--        back: 10,000 a flight before, 10,100 now (+1%), 3 directions.
--     R3 ZF1–ZF5: a both-directions row (written before 26 Oct, no direction) down to 95% on 9 Jan from 300; no flights
--        left, only the daily history, both ways at 300 to 12 Jan and 285 from 13 Jan: seen 13 Jan on both directions'
--        fares, so both directions are repriced, 2 complete days since (too soon). Out: 3 flights a day since (21 a week
--        against 14: frequency changed), 90% full against 100% (load fell), 9,000 a flight against 10,000: −21,000 a
--        week. Back: 10,500 against 10,000 a flight, 14 a week: +7,000 a week.
--   1. Who may call fare_results(): signed in only, stable, as owner with an empty search path, its own 30 s limit,
--      described; its builder internal. export_for_report() kind fare_results gives the same document with the secret.
--   2. The rows: which directions, their order (profit a week), levels, moves, pending, before, now, change, flags.
--   3. The baseline and the totals.
--   4. Signed out and an account that isn't staff are refused; staff get what postgres gets.
--   5. On the copy: every airline of the default world in one call each, under 10 seconds each, and the spec's hand-worked
--      check (directions whose economy fare went up on 26 Oct 2026 and were seen on 30 or 31 Oct), as the function gives
--      them and as worked out straight from route_days: printed per airline (counts and AS$ figures, never rows).

create temporary table t_fr (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_fr to authenticated, anon;
insert into public.planner_users (email) values ('fare-results-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. who may call fare_results()
do $test$
declare f text := 'public.fare_results(bigint, timestamptz)'; g text := 'private.fig_fare_results(bigint, timestamptz)';
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false)
                 and p.proconfig @> array['statement_timeout=30s', 'plan_cache_mode=force_custom_plan'] from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path, its own 30 s limit and each call planned afresh';
  assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 400, f || ' has no description';
  assert not has_function_privilege('authenticated', g, 'execute') and not has_function_privilege('anon', g, 'execute'), g || ' can be called from outside';
  assert (select not p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
    g || ' runs as owner, isn''t stable or has no empty search path';
  assert obj_description(g::regprocedure, 'pg_proc') is not null, g || ' has no description';
  assert obj_description('public.export_for_report(text, text, text)'::regprocedure, 'pg_proc') like '%Needs the ingest secret.%kind fare_results%',
    'export_for_report() lost words of its description, or doesn''t describe kind fare_results';
  raise notice 'fare_results(): signed in only, stable, as owner with an empty search path and its own 30 s limit, described; its builder internal; export_for_report() describes kind fare_results';
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
do $setup$
declare
  w bigint; g bigint; al bigint; r1 bigint; r2 bigint; r3 bigint; d date; x record;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'fare results test', true);
  insert into public.airports (code, utc_offset) select c, 0 from unnest(array['ZF1', 'ZF2', 'ZF3', 'ZF5']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('fare results test', 'fare-results.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description) values
    (w, null, 'fare_launch_pct', '100', '%', 'test'), (w, null, 'fare_ladder_cap_pts', '20', 'points', 'test');
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select w, 'fare_floor_pct', '60'::jsonb, r2.kind, r2.unit, 'test' from public.world_rules r2 where r2.key = 'fare_floor_pct' limit 1;
  if not exists (select 1 from public.world_rules where world_id = w and key = 'fare_floor_pct') then
    insert into public.world_rules (world_id, key, value, kind, unit, description) values (w, 'fare_floor_pct', '60'::jsonb, 'number', '%', 'test');
  end if;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990401, 'Fare Results', 'Fare Results', 'FR', 'ZF1', true, 1) returning id into al;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, al, 'ZF1', 'ZF2', 1200, 'research') returning id into r1;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, al, 'ZF1', 'ZF3', 900, 'research') returning id into r2;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, al, 'ZF1', 'ZF5', 2000, 'research') returning id into r3;
  -- every evening captured complete, taken at 22:00 UTC that day
  insert into public.airline_days (world_id, airline_id, day, complete, source, taken_at)
  select w, al, d0::date, true, 'capture', (d0::date + time '22:00') at time zone 'UTC' from generate_series(date '2029-12-31', date '2030-01-14', interval '1 day') d0;
  -- R1's captured flights (fare_plan_status()'s day fares): out 300 to 6 Jan, 360 from 7 Jan; back 300
  for d in select generate_series(date '2030-01-01', date '2030-01-14', interval '1 day')::date loop
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at) values
      (w, al, d, 6001, 'ZF1', 'ZF2', '08:00', (d + time '08:00') at time zone 'UTC', 180, 180, 100, case when d < date '2030-01-07' then 300 else 360 end, (d + time '22:00') at time zone 'UTC'),
      (w, al, d, 6003, 'ZF1', 'ZF2', '14:00', (d + time '14:00') at time zone 'UTC', 180, 180, 100, case when d < date '2030-01-07' then 300 else 360 end, (d + time '22:00') at time zone 'UTC'),
      (w, al, d, 6002, 'ZF2', 'ZF1', '11:00', (d + time '11:00') at time zone 'UTC', 180, 180, 100, 300, (d + time '22:00') at time zone 'UTC'),
      (w, al, d, 6004, 'ZF2', 'ZF1', '17:00', (d + time '17:00') at time zone 'UTC', 180, 180, 100, 300, (d + time '22:00') at time zone 'UTC');
  end loop;
  -- the daily history, 31 Dec to 14 Jan: (route, origin, dest, day, flights, eco pax, eco seats, eco fare, revenue, profit)
  for d in select generate_series(date '2029-12-31', date '2030-01-14', interval '1 day')::date loop
    insert into public.route_days (world_id, airline_id, route_id, origin_code, dest_code, day, flights, passengers, seats, revenue, costs, profit,
                                   eco_fare_avg, eco_pax, eco_seats)
    select w, al, v.r, v.o, v.t, d, v.f, v.p, v.s, v.rev, v.rev - v.pr, v.pr, v.fare, v.p, v.s
      from (values
        -- R1 out: 300 and full before 7 Jan, then 360 at 95%
        (r1, 'ZF1', 'ZF2', 2, case when d < date '2030-01-07' then 360 else 342 end, 360,
         case when d < date '2030-01-07' then 300 else 360 end, case when d < date '2030-01-07' then 60000 else 66000 end,
         case when d < date '2030-01-07' then 20000 else 26000 end),
        -- R1 back and R2 both ways (the baseline): 10,000 a flight before 7 Jan, 10,100 after
        (r1, 'ZF2', 'ZF1', 2, 360, 360, 300, 60000, case when d < date '2030-01-07' then 20000 else 20200 end),
        (r2, 'ZF1', 'ZF3', 2, 360, 360, 250, 50000, case when d < date '2030-01-07' then 20000 else 20200 end),
        (r2, 'ZF3', 'ZF1', 2, 360, 360, 250, 50000, case when d < date '2030-01-07' then 20000 else 20200 end),
        -- R3 out: from 13 Jan 285, 3 flights a day, 90% full, 9,000 a flight
        (r3, 'ZF1', 'ZF5', case when d < date '2030-01-13' then 2 else 3 end, case when d < date '2030-01-13' then 360 else 486 end,
         case when d < date '2030-01-13' then 360 else 540 end, case when d < date '2030-01-13' then 300 else 285 end,
         case when d < date '2030-01-13' then 60000 else 85500 end, case when d < date '2030-01-13' then 20000 else 27000 end),
        -- R3 back: from 13 Jan 285, 10,500 a flight
        (r3, 'ZF5', 'ZF1', 2, 360, 360, case when d < date '2030-01-13' then 300 else 285 end, case when d < date '2030-01-13' then 60000 else 57000 end,
         case when d < date '2030-01-13' then 20000 else 21000 end)) v (r, o, t, f, p, s, fare, rev, pr);
  end loop;
  insert into public.fare_plan (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from, proposed_on, status, reason, level_pct, ladder_move, direction) values
    (w, al, r1, 'fr-test-1', 'economy', 20, 300, date '2030-01-05', 'planned', 'sold out 7 of 7', 120, 'up', 'out'),
    (w, al, r1, 'fr-test-2', 'economy', -4.2, 360, date '2030-01-12', 'planned', 'test', 115, 'down', 'out'),
    (w, al, r2, 'fr-test-3', 'economy', 5, 250, date '2030-01-05', 'planned', 'never made', 105, 'up', 'out'),
    (w, al, r2, 'fr-test-4', 'economy', 50, 250, date '2030-01-05', 'dropped', 'dropped', 150, 'up', 'back'),
    (w, al, r3, 'fr-test-5', 'economy', -5, 300, date '2030-01-09', 'planned', 'before 26 Oct', 95, 'down', null);
  insert into t_fr values ('ids', jsonb_build_object('w', w, 'al', al, 'r1', r1, 'r2', r2, 'r3', r3));
  insert into t_fr values ('doc', private.fig_fare_results(al, timestamptz '2030-01-15 12:00:00+00'));
end
$setup$;

-- ---------------------------------------------------------------- 2. the rows
do $test$
declare d jsonb := (select v from t_fr where k = 'doc'); ids jsonb := (select v from t_fr where k = 'ids'); r jsonb; o jsonb; b jsonb; s text; v jsonb;
begin
  s := (select string_agg((e ->> 'from') || '>' || (e ->> 'to'), ' ' order by i) from jsonb_array_elements(d -> 'routes') with ordinality t(e, i));
  assert s = 'ZF1>ZF2 ZF5>ZF1 ZF1>ZF5', 'the repriced directions, by profit a week: ' || coalesce(s, 'none');
  assert d #>> '{days,from}' = '2030-01-08' and d #>> '{days,to}' = '2030-01-14' and (d #>> '{days,count}')::int = 7, 'the complete days: ' || (d -> 'days')::text;
  r := d -> 'routes' -> 0;
  assert (r ->> 'route_id')::bigint = (ids ->> 'r1')::bigint and r ->> 'hub' = 'ZF1' and r ->> 'dest' = 'ZF2' and r ->> 'direction' = 'out' and (r ->> 'km')::int = 1200,
    'R1 out: its route: ' || r::text;
  assert (r ->> 'economy_level')::numeric = 120 and r -> 'business_level' = 'null'::jsonb and (r ->> 'at_cap')::boolean and not (r ->> 'at_floor')::boolean,
    'R1 out: level 120 (this week''s step down not seen yet), no business, at the cap: ' || r::text;
  assert (r #>> '{moves,count}')::int = 1 and r #>> '{moves,first_seen}' = '2030-01-07'
     and r #>> '{moves,latest,move}' = 'up' and (r #>> '{moves,latest,level}')::numeric = 120 and r #>> '{moves,latest,proposed_on}' = '2030-01-05'
     and r #>> '{moves,latest,seen_on}' = '2030-01-07',
    'R1 out: one change, seen 7 Jan: ' || (r -> 'moves')::text;
  assert r #>> '{moves,pending,proposed_on}' = '2030-01-12' and r #>> '{moves,pending,move}' = 'down' and (r #>> '{moves,pending,level}')::numeric = 115
     and (r #>> '{moves,pending,count}')::int = 1,
    'R1 out: the step down planned on 12 Jan is pending: ' || (r #> '{moves,pending}')::text;
  b := r -> 'before'; o := r -> 'now';
  assert b ->> 'from' = '2029-12-31' and b ->> 'to' = '2030-01-06' and (b ->> 'flights')::int = 14 and (b ->> 'flights_week')::numeric = 14
     and (b ->> 'economy_fare')::numeric = 300 and (b ->> 'economy_load')::numeric = 100 and b -> 'business_load' = 'null'::jsonb
     and (b ->> 'revenue_per_flight')::numeric = 30000 and (b ->> 'profit_per_flight')::numeric = 10000,
    'R1 out: before: ' || b::text;
  assert o ->> 'from' = '2030-01-08' and o ->> 'to' = '2030-01-14' and (o ->> 'days')::int = 7 and (o ->> 'flights')::int = 14 and (o ->> 'flights_week')::numeric = 14
     and (o ->> 'economy_fare')::numeric = 360 and (o ->> 'economy_load')::numeric = 95 and (o ->> 'revenue_per_flight')::numeric = 33000
     and (o ->> 'profit_per_flight')::numeric = 13000,
    'R1 out: now (8 to 14 Jan; 7 Jan isn''t among the latest 7 complete days): ' || o::text;
  assert (r #>> '{change,economy_fare_pct}')::numeric = 20 and (r #>> '{change,economy_load_pts}')::numeric = -5 and (r #>> '{change,profit_per_flight_pct}')::numeric = 30
     and (r #>> '{change,revenue_per_flight_pct}')::numeric = 10 and (r #>> '{change,flights_week}')::numeric = 0 and (r ->> 'profit_week')::numeric = 42000,
    'R1 out: the change and profit a week: ' || (r -> 'change')::text || ' ' || (r ->> 'profit_week');
  assert r -> 'flags' = '["at_cap"]'::jsonb, 'R1 out: only at cap (95% full isn''t under 95): ' || (r -> 'flags')::text;

  -- R3 back: the both-directions row seen on the daily history's fares
  r := d -> 'routes' -> 1;
  assert r ->> 'direction' = 'back' and r ->> 'from' = 'ZF5' and r ->> 'to' = 'ZF1' and (r ->> 'economy_level')::numeric = 95
     and r #>> '{moves,first_seen}' = '2030-01-13' and r #>> '{moves,latest,move}' = 'down' and r #> '{moves,pending}' = 'null'::jsonb
     and r #>> '{before,from}' = '2030-01-06' and (r #>> '{now,days}')::int = 2 and (r #>> '{now,flights_week}')::numeric = 14
     and (r #>> '{before,profit_per_flight}')::numeric = 10000 and (r #>> '{now,profit_per_flight}')::numeric = 10500 and (r ->> 'profit_week')::numeric = 7000
     and r -> 'flags' = '["too_soon"]'::jsonb,
    'R3 back: a both-directions row, seen 13 Jan on the daily history, 2 days since: ' || r::text;
  r := d -> 'routes' -> 2;
  assert r ->> 'direction' = 'out' and (r #>> '{now,flights_week}')::numeric = 21 and (r #>> '{before,flights_week}')::numeric = 14
     and (r #>> '{now,economy_load}')::numeric = 90 and (r #>> '{now,economy_fare}')::numeric = 285 and (r #>> '{now,profit_per_flight}')::numeric = 9000
     and (r ->> 'profit_week')::numeric = -21000 and (r #>> '{change,economy_fare_pct}')::numeric = -5
     and r -> 'flags' = '["load_fell", "frequency_changed", "too_soon"]'::jsonb,
    'R3 out: load fell, frequency changed, too soon: ' || r::text;
  assert not exists (select 1 from jsonb_array_elements(d -> 'routes') e where (e ->> 'route_id')::bigint = (ids ->> 'r2')::bigint),
    'R2, with a change planned but never seen (and one dropped), is repriced';
  -- the same day fare_plan_status() gives, within its window of 9 days
  v := (select e from jsonb_array_elements(private.fig_fare_plan((ids ->> 'al')::bigint, timestamptz '2030-01-15 12:00:00+00') -> 'plan') e where e ->> 'legacy_key' = 'fr-test-1');
  assert (v ->> 'applied')::boolean and v ->> 'seen_on' = '2030-01-07', 'fare_plan_status() sees R1''s step up on another day: ' || coalesce(v::text, 'none');
  raise notice 'the rows: R1 out, R3 back and R3 out in order of profit a week (+42,000, +7,000, −21,000); a direction''s own row and a both-directions row; seen on the captured flights (the day fare_plan_status() gives) and on the daily history; this week''s unseen move pending with the level kept; before the 7 days before the first seen day, now the latest complete days on or after it; the four flags';
end
$test$;

-- ---------------------------------------------------------------- 3. the baseline and the totals
do $test$
declare d jsonb := (select v from t_fr where k = 'doc'); t jsonb := d -> 'totals'; b jsonb := d -> 'baseline';
begin
  assert (b ->> 'directions')::int = 3 and b #>> '{before,from}' = '2029-12-31' and b #>> '{before,to}' = '2030-01-06'
     and b #>> '{now,from}' = '2030-01-08' and b #>> '{now,to}' = '2030-01-14'
     and (b #>> '{before,profit_per_flight}')::numeric = 10000 and (b #>> '{now,profit_per_flight}')::numeric = 10100 and (b ->> 'profit_per_flight_pct')::numeric = 1,
    'the baseline: R1 back and R2 both ways, before the 7 days before 7 Jan, now 8 to 14 Jan, +1%: ' || b::text;
  assert (t ->> 'directions')::int = 3 and (t ->> 'up')::int = 1 and (t ->> 'down')::int = 2 and (t ->> 'at_cap')::int = 1 and (t ->> 'load_fell')::int = 1
     and (t ->> 'frequency_changed')::int = 1 and (t ->> 'too_soon')::int = 2,
    'the totals'' counts: ' || t::text;
  assert (t #>> '{before,flights}')::int = 42 and (t #>> '{before,profit_per_flight}')::numeric = 10000
     and (t #>> '{now,flights}')::int = 24 and (t #>> '{now,profit_per_flight}')::numeric = 11583 and (t ->> 'profit_per_flight_pct')::numeric = 15.8
     and (t ->> 'baseline_profit_per_flight_pct')::numeric = 1 and (t ->> 'profit_week')::numeric = 28000,
    'the totals'' money, weighted by flights: ' || t::text;
  assert (d #>> '{settings,cap_pct}')::numeric = 120 and (d #>> '{settings,launch_pct}')::numeric = 100 and (d #>> '{settings,floor_pct}')::numeric = 60,
    'the settings used: ' || (d -> 'settings')::text;
  raise notice 'the baseline (3 directions, +1%%) and the totals (3 directions, 1 up, 2 down, 1 at cap, 1 load fell; 10,000 → 11,583 a flight, +15.8%%, +28,000 a week)';
end
$test$;

-- ---------------------------------------------------------------- 4. who may read it, and the report's kind
do $test$
declare ids jsonb := (select v from t_fr where k = 'ids'); al bigint := (ids ->> 'al')::bigint; w bigint := (ids ->> 'w')::bigint;
        s text := 'fare-results-test-' || gen_random_uuid()::text; staff uuid := gen_random_uuid(); other uuid := gen_random_uuid(); v jsonb;
begin
  insert into public.ingest_secret (secret) values (s);
  v := public.export_for_report(s, 'fare_results', jsonb_build_object('airline', 'FR', 'world', w, 'as_of', '2030-01-15T12:00:00Z')::text);
  assert v = (select t.v from t_fr t where t.k = 'doc'), 'export_for_report(fare_results) isn''t fare_results()''s document';
  begin
    perform public.export_for_report(s, 'fare_results', jsonb_build_object('world', w)::text);
    assert false, 'export_for_report(fare_results) took no airline';
  exception when invalid_parameter_value then null;
  end;
  insert into auth.users (id, email) values (staff, 'fare-results-staff@example.com'), (other, 'fare-results-other@example.com');
  perform set_config('role', 'anon', true);
  begin
    perform public.fare_results(al, timestamptz '2030-01-15 12:00:00+00');
    assert false, 'signed out, fare_results() answered';
  exception when insufficient_privilege then null;
  end;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', other, 'email', 'fare-results-other@example.com', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', other::text, true);
  begin
    perform public.fare_results(al, timestamptz '2030-01-15 12:00:00+00');
    assert false, 'an account that isn''t staff read fare_results()';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', staff, 'email', 'fare-results-staff@example.com', 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', staff::text, true);
  v := public.fare_results(al, timestamptz '2030-01-15 12:00:00+00');
  perform set_config('role', 'postgres', true);
  assert v = (select t.v from t_fr t where t.k = 'doc'), 'staff don''t get what postgres gets';
  raise notice 'fare_results(): signed out and an account that isn''t staff refused, staff get what postgres gets; export_for_report() kind fare_results gives the same with the secret, and needs an airline';
end
$test$;

-- ---------------------------------------------------------------- 5. on the copy: speed, and the spec's hand-worked check
do $test$
declare a record; t0 timestamptz; ms int; d jsonb; n int; h record; f record; total_ms int := 0; slowest int := 0; lines text[] := '{}';
begin
  for a in select al.airline_id, al.iata_code, al.name from private.fig_airlines(private.fig_world(null)) al order by al.ord loop
    t0 := clock_timestamp();
    d := private.fig_fare_results(a.airline_id, now());
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    total_ms := total_ms + ms; slowest := greatest(slowest, ms);
    assert ms < 10000, format('%s: fare_results() took %s ms on the copy (the group page reads six)', a.iata_code, ms);
    -- the spec's hand-worked check: directions with an economy step up proposed on 26 Oct and seen on 30 or 31 Oct, before
    -- the 7 days before that day, since the latest complete days on or after it; as the function gives them (rows whose
    -- first seen day is that day, so its windows are the same) and straight from route_days
    with c as (select e as row, (x ->> 'seen_on')::date as seen
                 from jsonb_array_elements(d -> 'routes') e
                 cross join lateral jsonb_array_elements(e #> '{moves,changes}') x
                where x ->> 'cabin' = 'economy' and x ->> 'move' = 'up' and x ->> 'proposed_on' = '2026-10-26' and x ->> 'seen_on' in ('2026-10-30', '2026-10-31')),
         fn as (select count(*)::int as n,
                       sum((row #>> '{sums,before_profit}')::numeric) / nullif(sum((row #>> '{sums,before_flights}')::numeric), 0) as b,
                       sum((row #>> '{sums,now_profit}')::numeric) / nullif(sum((row #>> '{sums,now_flights}')::numeric), 0) as s
                  from c where row #>> '{moves,first_seen}' = seen::text),
         cd as (select (select array_agg(x.day) from (select ad.day from public.airline_days ad
                                                        where ad.airline_id = a.airline_id and ad.complete and ad.taken_at <= now()
                                                        order by ad.day desc limit 7) x) as days),
         hw as (select count(distinct (c.row ->> 'from', c.row ->> 'to'))::int as n,
                       sum(rd.profit) filter (where rd.day < c.seen) / nullif(sum(rd.flights) filter (where rd.day < c.seen and rd.profit is not null), 0) as b,
                       sum(rd.profit) filter (where rd.day >= c.seen) / nullif(sum(rd.flights) filter (where rd.day >= c.seen and rd.profit is not null), 0) as s,
                       100.0 * sum(rd.eco_pax) filter (where rd.day < c.seen and rd.eco_seats > 0) / nullif(sum(rd.eco_seats) filter (where rd.day < c.seen and rd.eco_seats > 0), 0) as lb,
                       100.0 * sum(rd.eco_pax) filter (where rd.day >= c.seen and rd.eco_seats > 0) / nullif(sum(rd.eco_seats) filter (where rd.day >= c.seen and rd.eco_seats > 0), 0) as ls
                  from c cross join cd
                  join public.route_days rd on rd.airline_id = a.airline_id and rd.origin_code = c.row ->> 'from' and rd.dest_code = c.row ->> 'to'
                   and ((rd.day >= c.seen - 7 and rd.day < c.seen) or (rd.day >= c.seen and rd.day = any (cd.days))))
    select fn.n as fn_n, round(fn.b) as fn_b, round(fn.s) as fn_s, hw.n as hw_n, round(hw.b) as hw_b, round(hw.s) as hw_s, round(hw.lb, 1) as lb, round(hw.ls, 1) as ls
      into h from fn, hw;
    lines := lines || format('%s: %s ms, %s repriced (profit a flight %s → %s, %s, the rest %s, %s a week); 26 Oct economy ups seen 30–31 Oct: %s, profit a flight %s → %s (route_days directly: %s, %s → %s, economy load %s → %s)',
      a.iata_code, ms, d #>> '{totals,directions}', coalesce(d #>> '{totals,before,profit_per_flight}', '—'), coalesce(d #>> '{totals,now,profit_per_flight}', '—'),
      coalesce((d #>> '{totals,profit_per_flight_pct}') || '%', '—'), coalesce((d #>> '{totals,baseline_profit_per_flight_pct}') || '%', '—'), d #>> '{totals,profit_week}',
      h.fn_n, coalesce(h.fn_b::text, '—'), coalesce(h.fn_s::text, '—'), h.hw_n, coalesce(h.hw_b::text, '—'), coalesce(h.hw_s::text, '—'),
      coalesce(h.lb::text || '%', '—'), coalesce(h.ls::text || '%', '—'));
  end loop;
  -- one notice (the rehearsal prints a test's first six)
  raise notice 'fare results on the copy: every airline of the default world, % ms in all, the slowest % ms; %', total_ms, slowest, array_to_string(lines, '; ');
end
$test$;

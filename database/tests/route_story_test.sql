-- The route page's figure (spec docs/specs/2026-10-21-route-page.md §1–2; migration 20261022000000_route_story.sql). Run
-- by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is
-- rolled back. A failed check stops with an error that says which (codes, counts and words of the hand-made world only).
--   1. route_days' new columns (eco_pax, eco_seats, bus_pax, bus_seats, bus_fare_avg, block_min), each described;
--      route_story() signed in only, stable, as owner with an empty search path, described; its builder and the writer
--      (private.history_flows()) internal, with an empty search path.
--   2. On the copy (counts, codes and timings only; printed first, since the rehearsal prints a passing test's first six
--      notices): route_story() for each airline's busiest route, timed (under the 8 s staff limit); one route's story in
--      numbers (its launch, how its days are matched, the last 7 days against the 7 before, its events) and every flown
--      route's events by kind; then no first-class seats in game_flights (so route_days has no first-class columns), and
--      the migration's backfill giving exactly what the writer gives, worked out again for every day of game_flights the
--      daily history has written; how many route days have the new columns.
--   3. A world of its own: airline RS (ours) flies QS1–QS2 from 1 Mar 2030, daily both ways, with business seats; its
--      flights 2 to 21 Mar (each direction's own loads), and on 10 Mar a flight known only from the bank statement. The
--      writer (history_flows) keeps each cabin's passengers and seats, the business fare and the block; the story counts
--      both directions together, by day and by week; its events: a frequency added (the launch's own rotation not
--      repeated), two fare plan rows (a ladder move and a dropped fare test), a cabin change, a retime, an aircraft
--      change, a migration's change left out, and rivals between scans (Rival One started; Rival Two added 7, while 3
--      added isn't one; our other airline and a freighter never rivals); the rivals table and our share at each scan
--      since launch; the same as of an earlier moment; a route with no flights yet.
--   4. Signed out and an account that isn't staff are refused; staff get what postgres gets.

create temporary table t_rs (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_rs to authenticated, anon;
insert into public.planner_users (email) values ('route-story-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the columns, and who may call route_story()
do $test$
declare f text := 'public.route_story(bigint, timestamptz)'; g text; c text; bad text;
begin
  select string_agg(x.c, ', ') into bad
    from (values ('eco_pax', 'integer'), ('eco_seats', 'integer'), ('bus_pax', 'integer'), ('bus_seats', 'integer'),
                 ('bus_fare_avg', 'numeric(14,2)'), ('block_min', 'integer')) x(c, t)
   where (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
           where a.attrelid = 'public.route_days'::regclass and a.attname = x.c and not a.attisdropped) is distinct from x.t
      or length(coalesce(col_description('public.route_days'::regclass,
                 (select a.attnum from pg_attribute a where a.attrelid = 'public.route_days'::regclass and a.attname = x.c)), '')) < 40;
  assert bad is null, 'route_days is missing a new column, its type or its description: ' || bad;
  assert not exists (select 1 from pg_attribute a where a.attrelid = 'public.route_days'::regclass and a.attname like 'fst%' and not a.attisdropped),
    'route_days has first-class columns, but no layout has first-class seats';
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path';
  assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 400, f || ' has no description';
  foreach g in array array['private.fig_route_story(bigint, timestamptz)', 'private.history_flows(bigint, date, date)'] loop
    assert not has_function_privilege('authenticated', g, 'execute') and not has_function_privilege('anon', g, 'execute'), g || ' can be called from outside';
    assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 60, g || ' has no description';
  end loop;
  assert (select p.provolatile = 's' from pg_proc p where p.oid = 'private.fig_route_story(bigint, timestamptz)'::regprocedure), 'fig_route_story() isn''t stable';
  assert obj_description('private.history_flows(bigint, date, date)'::regprocedure, 'pg_proc') like '%block_min%', 'history_flows()''s description doesn''t name the new columns';
  raise notice 'route_days has eco_pax, eco_seats, bus_pax, bus_seats, bus_fare_avg and block_min, each described, and no first-class columns; route_story(): signed in only, stable, as owner with an empty search path, described; fig_route_story() and history_flows() internal';
end
$test$;

-- ---------------------------------------------------------------- 2. the copy (counts, codes and timings only)
-- 2a. route_story() for each airline's busiest route, timed, and the first one's story in numbers (before 2b works the
-- daily history out again)
do $test$
declare w bigint := (select id from public.worlds where is_default); t0 timestamptz; ms int; worst int := 0; al record; d jsonb; first_doc jsonb;
  times text[] := '{}'; wk0 jsonb; wk1 jsonb; kinds text; newest text; m record;
begin
  -- each airline's busiest route (the most flights in the daily history over its last 14 days), timed
  for al in select fa.airline_id, fa.iata_code,
                   (select x.route_id from public.route_days x where x.airline_id = fa.airline_id and x.route_id is not null
                       and x.day > (select max(y.day) from public.route_days y where y.airline_id = fa.airline_id) - 14
                     group by x.route_id order by sum(x.flights) desc, x.route_id limit 1) as route_id
              from private.fig_airlines(w) fa order by fa.ord loop
    continue when al.route_id is null;
    t0 := clock_timestamp();
    d := public.route_story(al.route_id, now());
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    worst := greatest(worst, ms);
    first_doc := coalesce(first_doc, d);
    times := times || format('%s %s–%s %s ms (%s days, %s weeks, %s events, %s rivals, %s scans since launch)', al.iata_code,
      d #>> '{route,hub}', d #>> '{route,dest}', ms, jsonb_array_length(d -> 'days'), jsonb_array_length(d -> 'weeks'),
      jsonb_array_length(d -> 'events'), jsonb_array_length(d #> '{rivals,airlines}'), jsonb_array_length(d #> '{scans,since_launch}'));
  end loop;
  assert worst < 8000, format('route_story() took %s ms on the copy: over the 8 s staff limit', worst);
  raise notice '%', format('on the copy, route_story() for each airline''s busiest route: %s; the slowest %s ms (staff limit 8 s)',
    coalesce(nullif(array_to_string(times, '; '), ''), 'no route with flights'), worst);
  -- one route's story in numbers: the first airline's busiest route, and how its days in the daily history are matched
  if first_doc is not null then
    wk0 := first_doc #> '{weeks,0}'; wk1 := first_doc #> '{weeks,1}';
    select count(distinct x.day) filter (where x.route_id = (first_doc ->> 'route_id')::bigint) as mine,
           count(distinct x.day) filter (where x.route_id is null) as none,
           count(distinct x.day) filter (where x.route_id <> (first_doc ->> 'route_id')::bigint) as other,
           (select count(distinct y.day) from public.route_days y where y.airline_id = (first_doc #>> '{route,airline,id}')::bigint) as airline_days,
           min(x.day) as d0
      into m
      from public.route_days x
     where x.airline_id = (first_doc #>> '{route,airline,id}')::bigint and x.flights > 0
       and ((x.origin_code = first_doc #>> '{route,hub}' and x.dest_code = first_doc #>> '{route,dest}')
         or (x.origin_code = first_doc #>> '{route,dest}' and x.dest_code = first_doc #>> '{route,hub}'));
    raise notice '%', format('on the copy, %s %s–%s: launched %s (%s, %s days ago), latest day %s; %s a week out, %s back on %s; %s days with flights (its airports in the daily history from %s: %s days matched to it, %s to no route, %s to another route; the airline has %s days); the last 7 days (%s to %s) against the 7 before (%s to %s): flights %s / %s, load %s%% / %s%% (economy %s%% / %s%%, business %s%% / %s%%), profit %sM / %sM, %sM / %sM an aircraft hour, fares %s / %s economy and %s / %s business; rivals %s, our share %s%% (%s%% a week before)',
      first_doc #>> '{route,airline,code}', first_doc #>> '{route,hub}', first_doc #>> '{route,dest}', first_doc #>> '{route,launched}',
      first_doc #>> '{route,launched_from}', first_doc #>> '{route,launched_days}', first_doc ->> 'latest_day',
      first_doc #>> '{now,departures,out}', first_doc #>> '{now,departures,back}',
      (select string_agg(t ->> 'type', ', ') from jsonb_array_elements(first_doc #> '{now,types}') t),
      jsonb_array_length(first_doc -> 'days'), m.d0, m.mine, m.none, m.other, m.airline_days,
      wk0 ->> 'from', wk0 ->> 'to', wk1 ->> 'from', wk1 ->> 'to', wk0 ->> 'flights', wk1 ->> 'flights', wk0 ->> 'load_pct', wk1 ->> 'load_pct',
      wk0 ->> 'eco_load_pct', wk1 ->> 'eco_load_pct', wk0 ->> 'bus_load_pct', wk1 ->> 'bus_load_pct', wk0 ->> 'profit', wk1 ->> 'profit',
      wk0 ->> 'profit_per_hour', wk1 ->> 'profit_per_hour', wk0 ->> 'eco_fare', wk1 ->> 'eco_fare', wk0 ->> 'bus_fare', wk1 ->> 'bus_fare',
      jsonb_array_length(first_doc #> '{rivals,airlines}'), first_doc #>> '{rivals,share}', first_doc #>> '{rivals,share_before}');
    select string_agg(format('%s %s', x.n, x.k), ', ' order by x.n desc, x.k) into kinds
      from (select e ->> 'kind' as k, count(*) as n from jsonb_array_elements(first_doc -> 'events') e group by 1) x;
    select string_agg(format('%s %s: %s', e ->> 'day', e ->> 'kind', e ->> 'words'), '; ' order by i) into newest
      from jsonb_array_elements(first_doc -> 'events') with ordinality x(e, i) where i <= 8;
    t0 := clock_timestamp();
    raise notice '%', format('on the copy, its events (%s): %s; the newest: %s; every flown route''s events by kind: %s (%s ms for all of them)',
      jsonb_array_length(first_doc -> 'events'), coalesce(kinds, 'none'), coalesce(newest, 'none'),
      coalesce((select string_agg(format('%s %s', z.n, z.k), ', ' order by z.n desc, z.k)
                  from (select e ->> 'kind' as k, count(*) as n
                          from public.routes r
                          join private.fig_airlines(w) fa on fa.airline_id = r.airline_id
                          cross join lateral jsonb_array_elements(private.fig_route_story(r.id, now()) -> 'events') e
                         where not r.removed and exists (select 1 from public.rotations rt where rt.route_id = r.id)
                         group by 1) z), 'none'),
      round(extract(epoch from clock_timestamp() - t0) * 1000));
  end if;
end
$test$;

-- 2b. no first-class seats, and the migration's backfill against the writer: every day of game_flights that the daily
-- history has written, worked out again by history_flows() (rolled back with the test)
do $test$
declare w bigint := (select id from public.worlds where is_default); n int; n_rows int; n_diff int; n_only int; d0 date; d1 date;
begin
  -- no first-class seats: the route_days columns for first are left out (spec §1)
  select count(*) into n from public.game_flights f where coalesce(f.fst_seats, 0) > 0 or coalesce(f.fst_pax, 0) > 0;
  assert n = 0, format('game_flights has %s rows with first-class seats on the copy: route_days needs fst_pax, fst_seats and fst_fare_avg (spec §1)', n);
  select min(coalesce((f.dep_at at time zone 'UTC')::date, f.game_date)),
         least(max(coalesce((f.dep_at at time zone 'UTC')::date, f.game_date)), (select max(r.day) from public.route_days r where r.world_id = w))
    into d0, d1 from public.game_flights f where f.world_id = w;
  if d0 is not null and d1 >= d0 then
    create temporary table t_rs_filled on commit drop as
      select rd.airline_id, rd.origin_code, rd.dest_code, rd.day, rd.eco_pax, rd.eco_seats, rd.bus_pax, rd.bus_seats, rd.bus_fare_avg, rd.block_min
        from public.route_days rd where rd.world_id = w and rd.day between d0 and d1;
    get diagnostics n_rows = row_count;
    perform private.history_flows(w, d0, d1);
    select count(*) filter (where (a.eco_pax, a.eco_seats, a.bus_pax, a.bus_seats, a.bus_fare_avg, a.block_min)
                                  is distinct from (b.eco_pax, b.eco_seats, b.bus_pax, b.bus_seats, b.bus_fare_avg, b.block_min)
                              and a.day is not null and b.day is not null),
           count(*) filter (where a.day is null or b.day is null)
      into n_diff, n_only
      from t_rs_filled a
      full join public.route_days b on b.world_id = w and b.airline_id = a.airline_id and b.origin_code = a.origin_code
                                    and b.dest_code = a.dest_code and b.day = a.day
     where b.day is null or (b.world_id = w and b.day between d0 and d1);
    assert n_diff = 0, format('%s route days of %s to %s have new columns the migration filled back differently from the writer', n_diff, d0, d1);
  end if;
  raise notice '%', format('on the copy: no first-class seats in game_flights; the backfill equals the writer on every one of the %s route days the daily history has from %s to %s (%s only on one side: a route day the captures changed since it was written); route days with the cabins kept: %s of %s, block hours on %s',
    coalesce(n_rows, 0), coalesce(d0::text, 'none'), coalesce(d1::text, 'none'), coalesce(n_only, 0),
    (select count(*) from public.route_days x where x.world_id = w and x.eco_pax is not null), (select count(*) from public.route_days x where x.world_id = w),
    (select count(*) from public.route_days x where x.world_id = w and x.block_min is not null));
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
-- a flight of RS on a day: out (QS1→QS2) at 06:00 or back at 10:00 UTC, two hours, its own loads by direction
create function pg_temp.rs_flight(w bigint, al bigint, d date, out_way boolean, eco_pax int, k int default 0)
returns void language sql as $f$
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, arr_local, dep_at, arr_at,
                                   registration, eco_pax, eco_seats, eco_pct, eco_fare, bus_pax, bus_seats, bus_pct, bus_fare,
                                   income_total, cost_total, pax_income, loads_captured_at, money_captured_at, posted_at, statement_blk, statement_routes)
  select w, al, d, case when out_way then 101 else 102 end + k * 2, case when out_way then 'QS1' else 'QS2' end, case when out_way then 'QS2' else 'QS1' end,
         to_char(t, 'HH24:MI'), to_char(t + interval '2 hours', 'HH24:MI'), t at time zone 'UTC', (t + interval '2 hours') at time zone 'UTC',
         'QS-1', eco_pax, 168, round(100.0 * eco_pax / 168), 300, 10, 12, 83, 900, 50000, 30000, 45000,
         (d + 1)::timestamp at time zone 'UTC', (d + 1)::timestamp at time zone 'UTC', t at time zone 'UTC', 1, 1
    from (select d::timestamp + case when out_way then interval '6 hours' else interval '10 hours' end as t) x
$f$;

-- a scan's schedule entry: [code, number, from, to, weekdays, departure, arrival, type, operator]
create function pg_temp.rs_fl(code text, no int, o text, d text, days text, ty text default '320') returns jsonb language sql immutable as $f$
  select jsonb_build_array(code, no, o, d, days, '08:00', '10:00', ty, '')
$f$;

-- the change log rows written since a mark become one save, at a moment
create function pg_temp.rs_save(w bigint, mark bigint, k bigint, at timestamptz) returns bigint language sql as $f$
  update public.change_log set txid = 9900000 + k, changed_at = at where world_id = w and id > mark;
  select coalesce(max(id), 0) from public.change_log
$f$;

do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; gr bigint; rs bigint; c2 bigint; r1 bigint; r2 bigint; rv1 bigint; rv2 bigint; cg bigint; ty bigint; cj bigint; m1 bigint;
  ac1 bigint; ac2 bigint; rot1 bigint; rot2 bigint; s bigint; sc jsonb := '{}'::jsonb; mark bigint; dd date; x record;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'route story test', true);
  insert into public.airports (code, utc_offset) select c, 0 from unnest(array['QS1', 'QS2', 'QS3', 'QS4']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('route story test', 'route-story.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s2.key, s2.value, s2.unit, s2.description from public.settings s2 where s2.world_id = dw and s2.airline_id is null;
  update public.settings set value = '7'::jsonb where world_id = w and airline_id is null and key = 'competition_threat_min_weekly';
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select w, r2.key, r2.value, r2.kind, r2.unit, r2.description from public.world_rules r2 where r2.world_id = dw;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.groups (world_id, name, kind) values (w, 'rivals', 'rival') returning id into gr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990801, 'Story One', 'Story Air', 'RS', 'QS1', true, 1) returning id into rs;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990802, 'Story Two', 'Story Two', 'RT', 'QS2', true, 2) returning id into c2;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990891, 'Rival One', true) returning id into rv1;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, null, 990892, 'Rival Two', true) returning id into rv2;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990893, 'Cargo Three', true) returning id into cg;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, rs, 'QS1', 'hub', true, 1), (w, c2, 'QS2', 'hub', true, 1);
  insert into public.aircraft_types (world_id, name, min_turn_min, cruise_kmh, seats_max) values (w, 'RS TEST TYPE', 60, 800, 180) returning id into ty;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats) values
    (w, 'RS-J', ty, 'Leisure', 180, 12, 168) returning id into cj;
  insert into public.markets (world_id, airline_id, name, layout) values (w, rs, 'Story market', 'Leisure') returning id into m1;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code)
  values (w, rs, 'QS-1', ty, cj, 'active', 'QS1') returning id into ac1;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code)
  values (w, rs, 'QS-2', ty, cj, 'active', 'QS1') returning id into ac2;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, city, distance_km, stars, market_id, source)
  values (w, rs, 'QS1', 'QS2', 'Story City', 1000, 4, m1, 'research') returning id into r1;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, city, distance_km, stars, market_id, source)
  values (w, rs, 'QS1', 'QS3', 'Quiet City', 1200, 3, m1, 'research') returning id into r2;

  -- save 1, 1 Mar: the launch, daily both ways (its own rotation isn't a "frequency added")
  mark := (select coalesce(max(id), 0) from public.change_log);
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, rs, r1, date '2030-03-01') returning id into rot1;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, rs, rot1, 1, 101, 'QS1', 'QS2', ac1, '{1,2,3,4,5,6,7}', 360, 120), (w, rs, rot1, 2, 102, 'QS2', 'QS1', ac1, '{1,2,3,4,5,6,7}', 600, 120);
  mark := pg_temp.rs_save(w, mark, 1, timestamptz '2030-03-01 09:00:00+00');

  -- the flights, 2 to 21 Mar: out 160 and back 140 in economy (300 a day), 10 in business each way; on 10 Mar one more out
  -- known only from the bank statement (no loads, no arrival): its passengers count, its seats and block don't
  for dd in select generate_series(date '2030-03-02', date '2030-03-21', interval '1 day')::date loop
    perform pg_temp.rs_flight(w, rs, dd, true, 160);
    perform pg_temp.rs_flight(w, rs, dd, false, 140);
  end loop;
  insert into public.game_flights (world_id, airline_id, game_date, origin_code, dest_code, dep_at, posted_at, statement_pax, pax_income,
                                   income_total, cost_total, money_captured_at, statement_blk, statement_routes)
  values (w, rs, date '2030-03-10', 'QS1', 'QS2', timestamptz '2030-03-10 15:00:00+00', timestamptz '2030-03-10 15:00:00+00', 100, 20000,
          20000, 10000, timestamptz '2030-03-11 00:00:00+00', 1, 1);
  insert into t_rs values ('flows', private.history_flows(w, date '2030-03-01', date '2030-03-22'));

  -- save 2, 15 Mar: a second frequency, days 1, 3 and 5, on QS-1
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, rs, r1, date '2030-03-16') returning id into rot2;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, rs, rot2, 1, 103, 'QS1', 'QS2', ac1, '{1,3,5}', 900, 120), (w, rs, rot2, 2, 104, 'QS2', 'QS1', ac1, '{1,3,5}', 1140, 120);
  mark := pg_temp.rs_save(w, mark, 2, timestamptz '2030-03-15 09:00:00+00');
  -- fare plan rows: a fare test on 5 Mar, dropped; the ladder's move on 16 Mar
  insert into public.fare_plan (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from, proposed_on, status, reason)
  values (w, rs, r1, 'rs-test-1', 'economy', 5, 300, date '2030-03-05', 'dropped', 'sells out');
  insert into public.fare_plan (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from, proposed_on, status, reason, level_pct, ladder_move)
  values (w, rs, r1, 'rs-test-2', 'economy', 5, 300, date '2030-03-16', 'planned', 'sold out 14 of 14', 105, 'up');
  mark := pg_temp.rs_save(w, mark, 3, timestamptz '2030-03-16 10:00:00+00');
  -- a migration's change on 17 Mar (a data fix) isn't an event
  perform set_config('equinox.actor', 'migration', true);
  update public.flight_legs set block_min = 125 where rotation_id = rot1 and leg_no = 2;
  perform set_config('equinox.actor', 'claude', true);
  mark := pg_temp.rs_save(w, mark, 4, timestamptz '2030-03-17 10:00:00+00');
  -- save 5, 18 Mar: the route's own cabin
  update public.routes set cabin_choice = 'Leisure Plus' where id = r1;
  mark := pg_temp.rs_save(w, mark, 5, timestamptz '2030-03-18 10:00:00+00');
  -- save 6, 19 Mar: RS 101 an hour later
  update public.flight_legs set dep_utc_min = 420 where rotation_id = rot1 and leg_no = 1;
  mark := pg_temp.rs_save(w, mark, 6, timestamptz '2030-03-19 10:00:00+00');
  -- save 7, 20 Mar: the first frequency moves to QS-2
  update public.flight_legs set aircraft_id = ac2 where rotation_id = rot1;
  mark := pg_temp.rs_save(w, mark, 7, timestamptz '2030-03-20 10:00:00+00');

  -- the scans (08:00 UTC): s1 20 Feb (before launch), s2 5 Mar, s3 12 Mar, s4 19 Mar, and one still running on 20 Mar
  --   RS: none in s1, daily both ways in s2 and s3 (14), and the second frequency in s4 (20)
  --   Rival One: starts in s3, daily both ways (14): an event
  --   Rival Two: 7 in s1 and s2, 10 in s3 (3 added: no event), 17 in s4 (7 added: an event)
  --   Story Two (ours) 7 from s4, and Cargo Three's freighters (77F) from s3: never rivals
  for x in select * from (values
      ('s1', timestamptz '2030-02-20 08:00:00+00', 'done', 0, 0, 7, 0),
      ('s2', timestamptz '2030-03-05 08:00:00+00', 'done', 7, 0, 7, 0),
      ('s3', timestamptz '2030-03-12 08:00:00+00', 'done', 7, 7, 10, 7),
      ('s4', timestamptz '2030-03-19 08:00:00+00', 'done', 10, 7, 17, 7),
      ('s5', timestamptz '2030-03-20 08:00:00+00', 'running', 10, 7, 30, 7)) v(k, at, status, rs_n, r1_each, r2_n, cg_n) loop
    insert into public.game_scans (world_id, taken_at, status) values (w, x.at, x.status) returning id into s;
    sc := sc || jsonb_build_object(x.k, s);
    insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
      (s, w, rs, case when x.rs_n = 0 then '[]'::jsonb
                      else jsonb_build_array(pg_temp.rs_fl('RS', 101, 'QS1', 'QS2', '1234567'), pg_temp.rs_fl('RS', 102, 'QS2', 'QS1', '1234567'))
                           || case when x.rs_n = 10 then jsonb_build_array(pg_temp.rs_fl('RS', 103, 'QS1', 'QS2', '135'), pg_temp.rs_fl('RS', 104, 'QS2', 'QS1', '135'))
                                   else '[]'::jsonb end end),
      (s, w, rv1, case when x.r1_each = 0 then '[]'::jsonb
                       else jsonb_build_array(pg_temp.rs_fl('R1', 1, 'QS1', 'QS2', '1234567'), pg_temp.rs_fl('R1', 2, 'QS2', 'QS1', '1234567')) end),
      (s, w, rv2, case x.r2_n when 7 then jsonb_build_array(pg_temp.rs_fl('R2', 1, 'QS2', 'QS1', '1234567'))
                              when 10 then jsonb_build_array(pg_temp.rs_fl('R2', 1, 'QS2', 'QS1', '1234567'), pg_temp.rs_fl('R2', 2, 'QS1', 'QS2', '135'))
                              when 17 then jsonb_build_array(pg_temp.rs_fl('R2', 1, 'QS2', 'QS1', '1234567'), pg_temp.rs_fl('R2', 2, 'QS1', 'QS2', '1234567'),
                                                             pg_temp.rs_fl('R2', 3, 'QS1', 'QS2', '135'))
                              else jsonb_build_array(pg_temp.rs_fl('R2', 1, 'QS2', 'QS1', '1234567'), pg_temp.rs_fl('R2', 2, 'QS1', 'QS2', '1234567'),
                                                     pg_temp.rs_fl('R2', 3, 'QS1', 'QS2', '1234567'), pg_temp.rs_fl('R2', 4, 'QS2', 'QS1', '1234567'),
                                                     pg_temp.rs_fl('R2', 5, 'QS1', 'QS2', '12')) end),
      (s, w, c2, case when x.k in ('s4', 's5') then jsonb_build_array(pg_temp.rs_fl('RT', 1, 'QS2', 'QS1', '1234567')) else '[]'::jsonb end),
      (s, w, cg, case when x.cg_n > 0 then jsonb_build_array(pg_temp.rs_fl('C3', 1, 'QS1', 'QS2', '1234567', '77F')) else '[]'::jsonb end);
  end loop;

  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_rs values ('w', to_jsonb(w)), ('rs', to_jsonb(rs)), ('r1', to_jsonb(r1)), ('r2', to_jsonb(r2)), ('scans', sc),
                          ('rv1', to_jsonb(rv1)), ('rv2', to_jsonb(rv2)), ('t', to_jsonb(timestamptz '2030-03-21 12:00:00+00'));
end
$setup$;

-- ---------------------------------------------------------------- 3a. the writer keeps the cabins and the block
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rs where k = 'w'); x record;
begin
  select * into x from public.route_days where world_id = w and origin_code = 'QS1' and dest_code = 'QS2' and day = date '2030-03-02';
  assert (x.flights, x.passengers, x.seats, x.eco_pax, x.eco_seats, x.bus_pax, x.bus_seats, x.eco_fare_avg, x.bus_fare_avg, x.block_min)
         = (1, 170, 180, 160, 168, 10, 12, 300::numeric, 900::numeric, 120),
    format('QS1→QS2 on 2 Mar isn''t 1 flight, 170 passengers, 180 seats, economy 160 of 168, business 10 of 12, fares 300 and 900, block 120: %s', to_jsonb(x));
  select * into x from public.route_days where world_id = w and origin_code = 'QS2' and dest_code = 'QS1' and day = date '2030-03-02';
  assert (x.eco_pax, x.eco_seats, x.bus_pax, x.bus_seats, x.block_min) = (140, 168, 10, 12, 120), 'QS2→QS1 on 2 Mar doesn''t keep its own loads';
  -- 10 Mar: a flight known only from the bank statement counts its passengers and money, never seats, cabins or block
  select * into x from public.route_days where world_id = w and origin_code = 'QS1' and dest_code = 'QS2' and day = date '2030-03-10';
  assert (x.flights, x.passengers, x.seats, x.eco_pax, x.eco_seats, x.bus_pax, x.block_min, x.profit) = (2, 270, 180, 160, 168, 10, 120, 30000::numeric),
    format('QS1→QS2 on 10 Mar, with a flight from the statement only: %s', to_jsonb(x));
  assert (select count(*) from public.route_days where world_id = w) = 40 and (select (v ->> 'route_days')::int from t_rs where k = 'flows') = 40,
    'history_flows() didn''t write 40 route days (20 days both ways)';
  raise notice 'the writer (history_flows) keeps each direction''s economy and business passengers and seats, the business fare weighted by its passengers and the block (arr_at − dep_at); a flight known only from the statement adds its passengers and money, not seats, cabins or block';
end
$test$;

-- ---------------------------------------------------------------- 3b. the story: route, now, days and weeks
do $test$
declare r1 bigint := (select (v #>> '{}')::bigint from t_rs where k = 'r1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_rs where k = 't');
  d jsonb; x jsonb;
begin
  d := private.fig_route_story(r1, t);
  insert into t_rs values ('doc', d);
  assert d #>> '{route,hub}' = 'QS1' and d #>> '{route,dest}' = 'QS2' and d #>> '{route,pair}' = 'QS1-QS2' and d #>> '{route,city}' = 'Story City'
     and (d #>> '{route,stars}')::int = 4 and (d #>> '{route,distance_km}')::int = 1000 and d #>> '{route,market,name}' = 'Story market'
     and d #>> '{route,airline,code}' = 'RS' and d #>> '{route,airline,name}' = 'Story Air',
    'the route isn''t QS1–QS2, Story City, 4 stars, 1,000 km, Story market, RS: ' || (d -> 'route')::text;
  assert d #>> '{route,cabin,layout}' = 'Leisure Plus' and (d #>> '{route,cabin,own}')::boolean and d #>> '{route,cabin,market_layout}' = 'Leisure',
    'the cabin isn''t its own Leisure Plus over its market''s Leisure: ' || (d #> '{route,cabin}')::text;
  assert d #>> '{route,launched}' = '2030-03-01' and d #>> '{route,launched_from}' = 'rotation' and (d #>> '{route,launched_days}')::int = 20,
    'launched isn''t 1 Mar (its first rotation), 20 days before: ' || (d -> 'route')::text;
  assert d ->> 'latest_day' = '2030-03-21', 'the latest captured day isn''t 21 Mar: ' || coalesce(d ->> 'latest_day', 'none');
  -- now: daily and days 1, 3, 5 each way; one type on two aircraft; the fare ladder's rows, economy first
  assert (d #>> '{now,departures,out}')::int = 10 and (d #>> '{now,departures,back}')::int = 10 and (d #>> '{now,rotations}')::int = 2,
    'departures a week aren''t 10 out and 10 back on 2 rotations: ' || (d -> 'now')::text;
  assert jsonb_array_length(d #> '{now,types}') = 1 and d #>> '{now,types,0,type}' = 'RS TEST TYPE' and (d #>> '{now,types,0,aircraft}')::int = 2,
    'the types aren''t RS TEST TYPE on 2 aircraft: ' || (d #> '{now,types}')::text;
  assert jsonb_array_length(d #> '{now,fares}') = 2 and d #>> '{now,fares,0,cabin}' = 'economy' and d #>> '{now,fares,1,cabin}' = 'business'
     and (d #>> '{now,fares,0,level}') is not null and d #> '{now,fares,0}' ? 'move' and d #> '{now,fares,0}' ? 'reason' and d #> '{now,fares,0}' ? 'applied'
     and (d #>> '{now,launch_pct}')::numeric = 100,
    'the fare ladder''s rows for the route aren''t economy then business with their level, move, reason and applied: ' || (d #> '{now,fares}')::text;
  -- days: 2 to 21 Mar, both directions together
  assert jsonb_array_length(d -> 'days') = 20 and d #>> '{days,0,day}' = '2030-03-02' and d #>> '{days,19,day}' = '2030-03-21',
    'the days aren''t 2 to 21 Mar: ' || jsonb_array_length(d -> 'days');
  x := d #> '{days,0}';
  assert (x ->> 'flights')::int = 2 and (x ->> 'passengers')::int = 320 and (x ->> 'seats')::int = 360 and (x ->> 'load_pct')::numeric = 88.9
     and (x ->> 'eco_pax')::int = 300 and (x ->> 'eco_seats')::int = 336 and (x ->> 'eco_load_pct')::numeric = 89.3
     and (x ->> 'bus_pax')::int = 20 and (x ->> 'bus_seats')::int = 24 and (x ->> 'bus_load_pct')::numeric = 83.3
     and (x ->> 'eco_fare')::numeric = 300 and (x ->> 'bus_fare')::numeric = 900
     and (x ->> 'revenue')::numeric = 0.1 and (x ->> 'costs')::numeric = 0.06 and (x ->> 'profit')::numeric = 0.04
     and (x ->> 'block_hours')::numeric = 4 and (x ->> 'profit_per_hour')::numeric = 0.01,
    '2 Mar, both ways: 2 flights, 320 passengers, 360 seats, 88.9%, economy 300 of 336, business 20 of 24, fares 300 and 900, profit 0.04M over 4 hours: ' || x::text;
  x := (select e from jsonb_array_elements(d -> 'days') e where e ->> 'day' = '2030-03-10');
  assert (x ->> 'flights')::int = 3 and (x ->> 'passengers')::int = 420 and (x ->> 'load_pct')::numeric = 88.9 and (x ->> 'profit')::numeric = 0.05
     and (x ->> 'block_hours')::numeric = 4 and (x ->> 'profit_per_hour')::numeric = 0.0125,
    '10 Mar: 3 flights, 420 passengers, the load from the flights with loads, profit 0.05M over 4 block hours: ' || x::text;
  -- weeks: 15–21 Mar, 8–14 Mar and 2–7 Mar (6 days), newest first
  assert jsonb_array_length(d -> 'weeks') = 3, 'not 3 weeks: ' || (d -> 'weeks')::text;
  assert d #>> '{weeks,0,from}' = '2030-03-15' and d #>> '{weeks,0,to}' = '2030-03-21' and (d #>> '{weeks,0,days}')::int = 7
     and d #>> '{weeks,1,from}' = '2030-03-08' and d #>> '{weeks,1,to}' = '2030-03-14' and (d #>> '{weeks,1,days}')::int = 7
     and d #>> '{weeks,2,from}' = '2030-03-01' and d #>> '{weeks,2,to}' = '2030-03-07' and (d #>> '{weeks,2,days}')::int = 6,
    'the weeks aren''t 15–21, 8–14 and 1–7 Mar (6 days with flights): ' || (d -> 'weeks')::text;
  x := d #> '{weeks,1}';
  assert (x ->> 'flights')::int = 15 and (x ->> 'profit')::numeric = 0.29 and (x ->> 'block_hours')::numeric = 28 and (x ->> 'profit_per_hour')::numeric = 0.01036
     and (x ->> 'load_pct')::numeric = 88.9 and (x ->> 'eco_fare')::numeric = 300,
    '8–14 Mar: 15 flights, profit 0.29M over 28 block hours (0.01036M an hour): ' || x::text;
  raise notice 'the story of QS1–QS2: launched 1 Mar (its first rotation), its own cabin over its market''s, 10 departures a week each way on one type and two aircraft, the fare ladder''s two cabins; 20 days both ways together (2 Mar: 320 passengers, 88.9%%, economy 89.3%%, business 83.3%%, fares 300 and 900, 0.04M over 4 block hours), and a statement-only flight''s passengers and money counted without its seats; 3 weeks newest first (8–14 Mar 0.29M over 28 hours)';
end
$test$;

-- ---------------------------------------------------------------- 3c. the events, the rivals and the share
do $test$
declare d jsonb := (select v from t_rs where k = 'doc'); sc jsonb := (select v from t_rs where k = 'scans'); got text; want text;
  rv2 bigint := (select (v #>> '{}')::bigint from t_rs where k = 'rv2');
begin
  select string_agg(format('%s %s: %s', e ->> 'day', e ->> 'kind', e ->> 'words'), ' | ' order by i) into got
    from jsonb_array_elements(d -> 'events') with ordinality x(e, i);
  want := '2030-03-20 aircraft changed: RS 101/102 now on QS-2'
       || ' | 2030-03-19 rival: Rival Two added 7 a week (10 → 17)'
       || ' | 2030-03-19 retimed: RS 101 06:00 → 07:00 UTC'
       || ' | 2030-03-18 cabin: cabin set to Leisure Plus'
       || ' | 2030-03-16 fare: economy up to 105%'
       || ' | 2030-03-15 frequency added: RS 103/104 added, days 135'
       || ' | 2030-03-12 rival: Rival One started here, 14 a week'
       || ' | 2030-03-05 fare: economy +5% fare test, dropped'
       || ' | 2030-03-01 launched: launched';
  assert got = want, E'the events aren''t, newest first:\n' || want || E'\nbut:\n' || coalesce(got, 'none');
  assert (select (e ->> 'dropped')::boolean and (e ->> 'change_pct')::numeric = 5 and e ->> 'level' is null from jsonb_array_elements(d -> 'events') e
           where e ->> 'kind' = 'fare' and e ->> 'day' = '2030-03-05')
     and (select (e ->> 'level')::numeric = 105 and e ->> 'move' = 'up' and not (e ->> 'dropped')::boolean from jsonb_array_elements(d -> 'events') e
           where e ->> 'kind' = 'fare' and e ->> 'day' = '2030-03-16'),
    'a fare event doesn''t carry its level or change, move and whether it was dropped';
  assert (select (e ->> 'rival_id')::bigint = rv2 and e ->> 'change' = 'added' and (e ->> 'then')::int = 10 and (e ->> 'now')::int = 17
            and (e ->> 'scan_id')::bigint = (sc ->> 's4')::bigint from jsonb_array_elements(d -> 'events') e where e ->> 'kind' = 'rival' and e ->> 'day' = '2030-03-19'),
    'Rival Two''s event doesn''t carry its id, added, 10 then and 17 now, and the scan';
  -- the rivals: the latest scan s4 against s3 (the latest at least 6 days older); ours from the live schedule
  assert d #>> '{rivals,scan,id}' = sc ->> 's4' and d #>> '{rivals,week_before,id}' = sc ->> 's3'
     and d #>> '{scans,latest,id}' = sc ->> 's4' and d #>> '{scans,week_before,id}' = sc ->> 's3',
    'the scans aren''t s4 against s3 (the running s5 left out): ' || (d -> 'scans')::text;
  select string_agg(format('%s %s (%s, %s)', e ->> 'name', e ->> 'weekly', e ->> 'weekly_before', e ->> 'change'), ', ' order by i) into got
    from jsonb_array_elements(d #> '{rivals,airlines}') with ordinality x(e, i);
  assert got = 'Rival Two 17 (10, 7), Rival One 14 (14, 0)', 'the rivals on the pair aren''t Rival Two 17 (+7) and Rival One 14 (Story Two ours, Cargo Three''s freighter left out): ' || coalesce(got, 'none');
  assert (d #>> '{rivals,ours}')::int = 20 and (d #>> '{rivals,rivals_weekly}')::int = 31 and (d #>> '{rivals,share}')::numeric = 39.2
     and (d #>> '{rivals,ours_before}')::int = 14 and (d #>> '{rivals,rivals_before}')::int = 24 and (d #>> '{rivals,share_before}')::numeric = 36.8,
    'ours 20 against 31 (39.2%), before 14 against 24 (36.8%): ' || (d -> 'rivals')::text;
  select string_agg(format('%s %s/%s %s', left(e ->> 'taken_at', 10), e ->> 'ours', e ->> 'rivals', e ->> 'share'), ', ' order by i) into got
    from jsonb_array_elements(d #> '{rivals,shares}') with ordinality x(e, i);
  assert got = '2030-03-05 14/7 66.7, 2030-03-12 14/24 36.8, 2030-03-19 20/31 39.2',
    'our share at each scan since launch (s1 before it left out) isn''t 66.7, 36.8, 39.2: ' || coalesce(got, 'none');
  assert jsonb_array_length(d #> '{scans,since_launch}') = 3, 'the scans since launch aren''t s2, s3 and s4';
  raise notice 'events newest first: an aircraft change, Rival Two''s 7 more between s3 and s4 (its 3 more before that not one), a retime, the cabin, the ladder''s move, a frequency added (the launch''s own not repeated), Rival One''s start, a dropped fare test, the launch; a migration''s change left out; rivals from s4 against s3 (Rival Two 17, +7; Rival One 14; our other airline and a freighter left out), ours 20 against 31, 39.2%% (36.8%% a week before), and our share at each scan since launch';
end
$test$;

-- ---------------------------------------------------------------- 3d. an earlier moment, and a route not flown yet
do $test$
declare r1 bigint := (select (v #>> '{}')::bigint from t_rs where k = 'r1'); r2 bigint := (select (v #>> '{}')::bigint from t_rs where k = 'r2');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_rs where k = 't'); sc jsonb := (select v from t_rs where k = 'scans'); d jsonb;
begin
  -- as of 14 Mar noon: the days to 14 Mar, the scan of 12 Mar, and nothing after it
  d := private.fig_route_story(r1, timestamptz '2030-03-14 12:00:00+00');
  assert d ->> 'latest_day' = '2030-03-14' and jsonb_array_length(d -> 'days') = 13 and d #>> '{rivals,scan,id}' = sc ->> 's3'
     and d #>> '{rivals,week_before,id}' = sc ->> 's2'
     and not exists (select 1 from jsonb_array_elements(d -> 'events') e where (e ->> 'day')::date > date '2030-03-14'),
    'as of 14 Mar the story reaches past it: ' || jsonb_array_length(d -> 'days') || ' days, scan ' || coalesce(d #>> '{rivals,scan,id}', 'none');
  assert (select string_agg(e ->> 'kind', ', ' order by i) from jsonb_array_elements(d -> 'events') with ordinality x(e, i)) = 'rival, fare, launched',
    'as of 14 Mar the events aren''t Rival One''s start, the fare test and the launch';
  -- QS1–QS3: on the list, never flown
  d := private.fig_route_story(r2, t);
  assert d #>> '{route,launched}' is null and d #>> '{route,launched_from}' is null and jsonb_array_length(d -> 'days') = 0
     and jsonb_array_length(d -> 'weeks') = 0 and jsonb_array_length(d -> 'events') = 0
     and (d #>> '{now,departures,out}')::int = 0 and jsonb_array_length(d #> '{now,types}') = 0 and jsonb_array_length(d #> '{now,fares}') = 0
     and (d #>> '{rivals,ours}')::int = 0 and d #>> '{rivals,share}' is null and jsonb_array_length(d #> '{rivals,airlines}') = 0
     and jsonb_array_length(d #> '{rivals,shares}') = 0 and d #>> '{rivals,scan,id}' = sc ->> 's4',
    'a route not flown yet: ' || d::text;
  begin
    perform private.fig_route_story(-1, t);
    assert false, 'a route that isn''t there gave a story';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'as of 14 Mar: the days to 14 Mar, the scan of 12 Mar against 5 Mar, and only the events by then; a route not flown yet: no launch, days, weeks or events, no departures, types or fares, the latest scan with no rival and no share; a route that isn''t there refused';
end
$test$;

-- ---------------------------------------------------------------- 4. who is refused; staff get what postgres gets
set local role anon;
do $test$
declare r1 bigint := (select (v #>> '{}')::bigint from t_rs where k = 'r1'); n int := 0;
begin
  begin perform public.route_story(r1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, route_story() wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e1", "email": "route-story-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r1 bigint := (select (v #>> '{}')::bigint from t_rs where k = 'r1'); n int := 0;
begin
  begin perform public.route_story(r1); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused route_story()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e2", "email": "route-story-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r1 bigint := (select (v #>> '{}')::bigint from t_rs where k = 'r1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_rs where k = 't');
begin
  assert public.route_story(r1, t) = (select v from t_rs where k = 'doc'), 'staff don''t get what postgres gets from route_story()';
end
$test$;
reset role;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused route_story(); staff get what postgres gets'; end $test$;

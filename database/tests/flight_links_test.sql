-- Flights linked to their routes and aircraft as they are captured, and the fill-back (migration
-- 20261022030000_flight_links.sql; spec docs/specs/2026-10-21-links-and-business-index.md §1, and §2's numbers on the copy).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is
-- rolled back. A failed check stops with an error that says which (codes and counts only).
--   1. The replaced functions stay internal, with an empty search path, described with what changed on 22 Oct.
--   2. On the copy, before the hand-made world is made (counts and timings only): the fill-back (with a route and with
--      an aircraft, before and after, from database/tests/before/flight_links_before.sql), nothing left that could be
--      linked, what is left without and why, links to a removed route where the pair has a live one; how long
--      private.fill_flight_links() takes for a capture page (with nothing to link, and with the latest loads page's
--      flights to link again, each linked as before) and its plan; and the fare ladder's rows whose baseline or index the
--      business index from the daily history changes (spec §2: expected none while game_flights holds every day since
--      6 Oct), read against the same ladder with the daily history's business fares hidden; nothing else may move.
--   3. In a world of its own made inside the test, through the capture's own path (private.capture_store(), which calls
--      private.capture_page()), with every airport on UTC. Links Test Air flies QLA–QLB (rotation LK 101 out, LK 102 back on
--      LK-AAA) and has a research route the other way round (QLB–QLA); a removed QLA–QLC and a live QLC–QLA; only a removed
--      QLA–QLD. The evening of 10 Apr 2099: the statement, then the loads page with LK 101, LK 301 (QLA→QLC) and LK 401
--      (QLA→QLD); LK 102's money comes that evening and its loads the next; one block QLC→QLA never gets loads.
--      a. As each page is stored, each flight gets its route and aircraft: LK 101 its leg's route and the aircraft the
--         statement names; LK 301 the live QLC–QLA, not the removed QLA–QLC that way round; LK 401 the removed QLA–QLD (the
--         only one); a money-only block by its airports (QLB→QLA: QLB–QLA, that way round first; QLC→QLA: QLC–QLA).
--      b. The next evening LK 102's loads join its money: the flight takes its leg's route (QLA–QLB), not the QLB–QLA its
--         money-only row was linked by, and its aircraft.
--      c. A flight with a link is never touched again, and capture_refresh() says what it linked.
--      d. The daily snapshot links first: with every link taken away, private.take_snapshot() links each flight again
--         (its answer says how many) and each route day it writes has its route.

create temporary table t_lk (k text primary key, v bigint) on commit drop;

-- statement lines of one flight: [time, text, amount], newest first, as the bank statement lists them (with a maintenance
-- line naming the aircraft when p_reg is given; as capture_data_matching_test.sql makes them)
create function pg_temp.lk_lines(p_at timestamptz, p_route text, p_reg text default null) returns jsonb language sql as $$
  select (case when p_reg is null then '[]'::jsonb
               else jsonb_build_array(jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'),
                                                        'Maintenance of ' || p_reg || ' (90 maintenance ratio)', '5,000 AS$ D')) end)
         || jsonb_build_array(
              jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'), 'Passenger transport income', '20,000 AS$ C'),
              jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'), 'On-board services (' || p_route || ')', '1,000 AS$ D'),
              jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'), 'Air traffic control fee (' || p_route || ')', '500 AS$ D'))
$$;
-- one loads-page row (every airport here on UTC): departure p_dep, arrival two hours later
create function pg_temp.lk_row(p_no int, p_reg text, p_origin text, p_dest text, p_dep timestamptz) returns jsonb language sql as $$
  select jsonb_build_array('LK ' || p_no, p_reg, p_origin, to_char(p_dep at time zone 'UTC', 'DD.MM. HH24:MI') || ' LT', p_dest,
           to_char((p_dep at time zone 'UTC') + interval '2 hours', 'DD.MM. HH24:MI') || ' LT',
           '100 AS$', '100 / 150 (67%)', '-', '-', '-', '-', '1 AS$', '1 / 10 (10%)', 'finished', 'details')
$$;
-- the test airline's flights in one line, by statement time (else departure): "HH:MI flight route aircraft", the route as
-- hub–dest (with "removed") and the aircraft by registration, "-" where there is none
create function pg_temp.lk_flights(p_airline bigint) returns text language sql as $$
  select string_agg(to_char(coalesce(f.posted_at, f.dep_at) at time zone 'UTC', 'HH24:MI') || ' ' || coalesce(f.flight_no::text, '-') || ' '
                    || coalesce(r.hub_code || '–' || r.dest_code || case when r.removed then ' removed' else '' end, '-') || ' '
                    || coalesce(a.registration, '-'), '; ' order by coalesce(f.posted_at, f.dep_at), f.flight_no)
    from public.game_flights f
    left join public.routes r on r.id = f.route_id
    left join public.aircraft a on a.id = f.aircraft_id
   where f.airline_id = p_airline
$$;

-- ---------------------------------------------------------------- 1. the replaced functions
do $test$
declare f text; bad text := '';
begin
  foreach f in array array['private.fill_flight_links(bigint)', 'private.merge_flight(bigint, bigint)', 'private.capture_page(bigint)',
                           'private.capture_refresh(bigint)', 'private.take_snapshot(bigint, date, timestamptz, text, boolean)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or (select p.prosecdef or not coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure)
       or coalesce(obj_description(f::regprocedure, 'pg_proc'), '') not ilike '%since 22 Oct%' then
      bad := bad || f || ' ';
    end if;
  end loop;
  assert bad = '', 'not internal, with an empty search path and described with what changed on 22 Oct: ' || bad;
  assert obj_description('private.fill_flight_links(bigint)'::regprocedure, 'pg_proc') like '%isn''t removed first%'
     and obj_description('public.fare_ladder(bigint, timestamptz)'::regprocedure, 'pg_proc') like '%bus_fare_avg on a day with business passengers%'
     and col_description('public.route_days'::regclass, (select attnum from pg_attribute where attrelid = 'public.route_days'::regclass and attname = 'route_id')) like '%22 Oct%',
    'fill_flight_links(), fare_ladder() or route_days.route_id isn''t described with the 22 Oct rule';
  raise notice 'fill_flight_links(), merge_flight(), capture_page(), capture_refresh() and take_snapshot(): internal, an empty search path, described with what changed on 22 Oct; fare_ladder() and route_days.route_id described';
end
$test$;

-- ---------------------------------------------------------------- 2. the copy (counts, timings and route ids only), before the hand-made world is made
-- 2a. the fill-back, and what is left without a link
do $test$
declare w bigint := (select id from public.worlds where is_default); b record; a record; n_route int; n_aircraft int; n_days int; d record;
  n_removed int; n_days_removed int;
begin
  select count(*) as n, count(f.route_id) as with_route, count(f.aircraft_id) as with_aircraft,
         count(*) filter (where f.route_id is null and (f.origin_code is null or f.dest_code is null)) as no_airports,
         count(*) filter (where f.aircraft_id is null and coalesce(f.registration, f.maint_registration) is null) as no_registration
    into a from public.game_flights f;
  -- nothing left that the rule could link
  select count(*) into n_route from public.game_flights f
   where f.route_id is null and f.origin_code is not null and f.dest_code is not null
     and exists (select 1 from public.routes r where r.airline_id = f.airline_id
                    and ((r.hub_code, r.dest_code) = (f.origin_code, f.dest_code) or (r.hub_code, r.dest_code) = (f.dest_code, f.origin_code)));
  select count(*) into n_aircraft from public.game_flights f
   where f.aircraft_id is null and exists (select 1 from public.aircraft x where x.world_id = f.world_id and x.registration = coalesce(f.registration, f.maint_registration));
  select count(*) as n, count(r.route_id) as with_route,
         count(*) filter (where r.route_id is null and exists (select 1 from public.routes x where x.airline_id = r.airline_id
                    and ((x.hub_code, x.dest_code) = (r.origin_code, r.dest_code) or (x.hub_code, x.dest_code) = (r.dest_code, r.origin_code)))) as could
    into d from public.route_days r;
  assert n_route = 0 and n_aircraft = 0 and d.could = 0,
    format('after the fill-back, %s flights could have a route, %s an aircraft and %s route days a route', n_route, n_aircraft, d.could);
  -- links to a removed route where the pair has a live one (the data load's, left as they were: only flights without a
  -- link are filled)
  select count(*) into n_removed from public.game_flights f join public.routes r on r.id = f.route_id
   where r.removed and exists (select 1 from public.routes x where x.airline_id = f.airline_id and not x.removed
                                  and ((x.hub_code, x.dest_code) = (f.origin_code, f.dest_code) or (x.hub_code, x.dest_code) = (f.dest_code, f.origin_code)));
  select count(*) into n_days_removed from public.route_days d2 join public.routes r on r.id = d2.route_id
   where r.removed and exists (select 1 from public.routes x where x.airline_id = d2.airline_id and not x.removed
                                  and ((x.hub_code, x.dest_code) = (d2.origin_code, d2.dest_code) or (x.hub_code, x.dest_code) = (d2.dest_code, d2.origin_code)));
  if to_regclass('rehearsal_before.flight_links') is not null then
    select * into b from rehearsal_before.flight_links;
    raise notice '%', format('on the copy, game_flights: %s rows, with a route %s before the fill-back and %s after, with an aircraft %s and %s; route_days: %s rows, with a route %s and %s',
                             a.n, b.flights_with_route, a.with_route, b.flights_with_aircraft, a.with_aircraft, d.n, b.route_days_with_route, d.with_route);
  else
    raise notice '%', format('on the copy, game_flights: %s rows, %s with a route, %s with an aircraft; route_days: %s rows, %s with a route (nothing saved before the changes)',
                             a.n, a.with_route, a.with_aircraft, d.n, d.with_route);
  end if;
  raise notice '%', format('on the copy, left without a link, none the rule could fill: %s flights without a route (%s with no airports, %s on airports the airline has no route on), %s without an aircraft (%s naming no registration, %s one that isn''t an aircraft of the world), %s route days without a route; linked to a removed route where the pair has a live one: %s flights, %s route days',
                           a.n - a.with_route, a.no_airports, a.n - a.with_route - a.no_airports, a.n - a.with_aircraft, a.no_registration,
                           a.n - a.with_aircraft - a.no_registration, d.n - d.with_route, n_removed, n_days_removed);
end
$test$;

-- 2b. how long the links take for a capture page, and their plan
do $test$
declare w bigint := (select id from public.worlds where is_default); pg record; t0 timestamptz; ms numeric; best numeric; v jsonb; n int; bad int;
  i int; v_plan jsonb; plans text := '';
begin
  -- with nothing to link (every evening once the page's flights are linked), best of 3
  for i in 1 .. 3 loop
    t0 := clock_timestamp();
    v := private.fill_flight_links(w);
    ms := extract(epoch from clock_timestamp() - t0) * 1000;
    best := least(coalesce(best, ms), ms);
  end loop;
  assert v = '{"routes": 0, "aircraft": 0}'::jsonb, 'fill_flight_links() still found links to fill after the fill-back: ' || v::text;
  -- the plan of its two updates (the scans only)
  foreach i in array array[1, 2] loop
    execute case i
      when 1 then format('explain (format json) update public.game_flights f set route_id = null where f.world_id = %s and f.route_id is null and f.origin_code is not null and f.dest_code is not null', w)
      else format('explain (format json) update public.game_flights f set aircraft_id = a.id from public.aircraft a where f.world_id = %s and f.aircraft_id is null and a.world_id = f.world_id and a.registration = coalesce(f.registration, f.maint_registration)', w) end
      into v_plan;
    plans := plans || case when i = 1 then 'route: ' else '; aircraft: ' end
             || coalesce((select string_agg(distinct (n_ ->> 'Node Type') || coalesce(' using ' || (n_ ->> 'Index Name'), '') || ' on ' || (n_ ->> 'Relation Name'), ', ')
                            from jsonb_path_query(v_plan, 'strict $.**') n_ where jsonb_typeof(n_) = 'object' and n_ ? 'Relation Name'), '?');
  end loop;
  -- with one capture page's flights to link: the latest loads page's, their links taken away, linked again as before
  select r.airline_id, r.captured_at into pg from public.game_capture_raw r where r.world_id = w and r.kind = 'loads' order by r.captured_at desc, r.id desc limit 1;
  if pg.airline_id is null then
    raise notice 'on the copy, fill_flight_links() with nothing to link: % ms (best of 3); no loads page kept to time one page; plan: %', round(best, 1), plans;
    return;
  end if;
  create temporary table t_lk_page on commit drop as
    select f.id, f.route_id, f.aircraft_id from public.game_flights f where f.airline_id = pg.airline_id and f.loads_captured_at = pg.captured_at;
  update public.game_flights f set route_id = null, aircraft_id = null from t_lk_page x where f.id = x.id;
  t0 := clock_timestamp();
  v := private.fill_flight_links(w);
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into n from t_lk_page;
  select count(*) into bad from public.game_flights f join t_lk_page x on x.id = f.id
   where (f.route_id, f.aircraft_id) is distinct from (x.route_id, x.aircraft_id);
  assert bad = 0, format('%s of the latest loads page''s %s flights were linked otherwise the second time', bad, n);
  assert ms < 1000, format('fill_flight_links() took %s ms for one loads page''s flights on the copy', round(ms));
  raise notice '%', format('on the copy, fill_flight_links() with nothing to link: %s ms (best of 3); with the latest loads page''s %s flights (airline %s, %s) to link again: %s ms, %s routes and %s aircraft, each as before; plan: %s',
                           round(best, 1), n, pg.airline_id, to_char(pg.captured_at at time zone 'UTC', 'DD Mon HH24:MI'), round(ms, 1),
                           v ->> 'routes', v ->> 'aircraft', plans);
end
$test$;

-- 2c. the fare ladder's rows the business index from the daily history changes (spec §2), at the planner's frozen moment
-- (the copy's latest capture plus an hour): each of our airlines' ladder as it reads now, against the same ladder with the
-- daily history's business fares hidden (route_days.bus_fare_avg emptied inside this rolled-back test), which is exactly
-- the step before 22 Oct. Read this way, the copy's other pending changes to the ladder can't show up as this build's.
do $test$
declare v_at timestamptz := date_trunc('minute', coalesce((select max(r.captured_at) from public.game_capture_raw r), now())) + interval '1 hour';
  al record; v_k text; n_rows int; n_bus int; n_hist int; n_bus_moved int; n_new int; n_fix int; n_other int; ids text; others text;
begin
  -- since 26 Oct a row per direction (spec docs/specs/2026-10-26-fare-ladder-per-direction.md): matched by its direction too
  create temporary table t_lk_ladder (which text, airline_id bigint, iata text, route_id bigint, direction text, cabin text, baseline_fare numeric,
    baseline_on date, fare_index numeric, index_matches boolean, level numeric, move text, new_level numeric, fix boolean) on commit drop;
  select count(*) into n_hist from public.route_days d where d.bus_pax > 0 and d.bus_fare_avg > 0;
  foreach v_k in array array['now', 'before'] loop
    if v_k = 'before' then
      update public.route_days set bus_fare_avg = null where bus_fare_avg is not null;
    end if;
    for al in select x.airline_id, a.iata_code from private.fig_airlines(private.fig_world(null)) x join public.airlines a on a.id = x.airline_id loop
      insert into t_lk_ladder
      select v_k, al.airline_id, al.iata_code, (e ->> 'route_id')::bigint, e ->> 'direction', e ->> 'cabin', (e ->> 'baseline_fare')::numeric,
             (e ->> 'baseline_on')::date, (e ->> 'fare_index')::numeric, (e ->> 'index_matches')::boolean, (e ->> 'level')::numeric,
             e ->> 'move', (e ->> 'new_level')::numeric, (e ->> 'fix')::boolean
        from jsonb_array_elements(private.fig_fare_ladder(al.airline_id, v_at) -> 'routes') e;
    end loop;
  end loop;
  select count(*), count(*) filter (where n.cabin = 'business') into n_rows, n_bus from t_lk_ladder n where n.which = 'now';
  with n as (select * from t_lk_ladder x where x.which = 'now'), b as (select * from t_lk_ladder x where x.which = 'before'),
  j as (select coalesce(n.iata, b.iata) as iata, coalesce(n.route_id, b.route_id) as route_id, coalesce(n.direction, b.direction) as direction,
               coalesce(n.cabin, b.cabin) as cabin,
               n.route_id is null or b.route_id is null as came_or_went,
               (n.baseline_fare, n.baseline_on, n.fare_index, n.index_matches) is distinct from (b.baseline_fare, b.baseline_on, b.fare_index, b.index_matches) as index_moved,
               (n.level, n.move, n.new_level) is distinct from (b.level, b.move, b.new_level) as move_moved,
               n.fix is distinct from b.fix as fix_moved,
               b.baseline_fare is null and n.baseline_fare is not null as new_baseline
          from n full join b on b.airline_id = n.airline_id and b.route_id = n.route_id and b.direction is not distinct from n.direction and b.cabin = n.cabin)
  select count(*) filter (where j.cabin = 'business' and j.index_moved),
         string_agg(distinct j.iata || ' ' || j.route_id, ', ') filter (where j.cabin = 'business' and j.index_moved),
         count(*) filter (where j.cabin = 'business' and j.new_baseline),
         count(*) filter (where j.cabin = 'business' and j.fix_moved),
         count(*) filter (where j.came_or_went or j.move_moved or (j.cabin <> 'business' and (j.index_moved or j.fix_moved))),
         string_agg(j.iata || ' ' || j.route_id || ' ' || coalesce(j.direction, '') || ' ' || j.cabin, ', ' order by j.iata, j.route_id, j.direction)
           filter (where j.came_or_went or j.move_moved or (j.cabin <> 'business' and (j.index_moved or j.fix_moved)))
    into n_bus_moved, ids, n_new, n_fix, n_other, others
    from j;
  assert n_other = 0, format('the business index from the daily history moved %s other row(s) of the ladder (a level, a move, an economy row, a row that came or went): %s', n_other, others);
  raise notice '%', format('on the copy, the fare ladder at %s: %s rows, %s in business; the daily history''s business days with a fare: %s; business rows whose baseline or index the daily history''s business fare changed: %s%s (%s with a baseline they had none before; %s set-back changes added or taken away); nothing else in the ladder moved',
                           to_char(v_at at time zone 'UTC', 'DD Mon HH24:MI'), n_rows, n_bus, n_hist, n_bus_moved,
                           case when ids is null then '' else ' (route ids ' || ids || ')' end, n_new, n_fix);
end
$test$;

-- ---------------------------------------------------------------- 3. the hand-made world
do $setup$
declare dw bigint := (select id from public.worlds where is_default); w bigint; g bigint; al bigint; ac_a bigint; ac_b bigint; r_ab bigint; rot bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'flight links test', true);
  insert into public.airports (code, utc_offset) select c, 0 from unnest(array['QLA', 'QLB', 'QLC', 'QLD']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('flight links test', 'flight-links.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  -- not active: its pages never complete a capture day, so no snapshot is taken unless the test takes one
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code, home_airport_code, active)
  values (w, g, 990801, 'Links Test Air', 'LK', 'QLA', false) returning id into al;
  insert into public.aircraft (world_id, airline_id, registration, status, base_code) values (w, al, 'LK-AAA', 'active', 'QLA') returning id into ac_a;
  insert into public.aircraft (world_id, airline_id, registration, status, base_code) values (w, al, 'LK-AAB', 'active', 'QLA') returning id into ac_b;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, al, 'QLA', 'QLB', 1000, 'research') returning id into r_ab;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source, removed) values
    (w, al, 'QLB', 'QLA', 1000, 'research', false), (w, al, 'QLA', 'QLC', 1000, 'research', true),
    (w, al, 'QLC', 'QLA', 1000, 'research', false), (w, al, 'QLA', 'QLD', 1000, 'research', true);
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, al, r_ab, date '2099-04-01') returning id into rot;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, al, rot, 1, 101, 'QLA', 'QLB', ac_a, '{1,2,3,4,5,6,7}', 480, 120),
    (w, al, rot, 2, 102, 'QLB', 'QLA', ac_a, '{1,2,3,4,5,6,7}', 720, 120);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_lk values ('w', w), ('airline', al);
end
$setup$;

do $test$
declare w bigint := (select v from t_lk where k = 'w'); al bigint := (select v from t_lk where k = 'airline');
  d1 timestamptz := '2099-04-10 00:00+00'; res jsonb; got text; v jsonb; n int;
begin
  -- a. the evening of 10 Apr: the statement, then the loads page
  res := private.capture_store(w, '990801', 'statement', '/test', '[["Date", "Text", "Amount"]]'::jsonb
    || pg_temp.lk_lines(d1 + interval '14 hours 5 minutes', 'QLC-QLA')              -- money only: its loads never come
    || pg_temp.lk_lines(d1 + interval '12 hours 5 minutes', 'QLB-QLA')              -- LK 102: its loads the next evening
    || pg_temp.lk_lines(d1 + interval '10 hours 5 minutes', 'QLA-QLD')              -- LK 401
    || pg_temp.lk_lines(d1 + interval '9 hours 5 minutes', 'QLA-QLC')               -- LK 301
    || pg_temp.lk_lines(d1 + interval '8 hours 5 minutes', 'QLA-QLB', 'LK-AAA'),    -- LK 101, naming its aircraft
    d1 + interval '23 hours', false);
  assert (res ->> 'ok')::boolean, 'the statement page wasn''t taken: ' || res::text;
  got := pg_temp.lk_flights(al);
  assert got = '08:05 - QLA–QLB LK-AAA; 09:05 - QLC–QLA -; 10:05 - QLA–QLD removed -; 12:05 - QLB–QLA -; 14:05 - QLC–QLA -',
    'after the statement page, the money-only flights aren''t linked by their airports (a live route first, that way round next) and the aircraft the statement names: ' || coalesce(got, 'none');
  res := private.capture_store(w, '990801', 'loads', '/test', '[["Flight", "Aircraft"]]'::jsonb || jsonb_build_array(
      pg_temp.lk_row(101, 'LK-AAA', 'QLA', 'QLB', d1 + interval '8 hours'),
      pg_temp.lk_row(301, 'LK-AAB', 'QLA', 'QLC', d1 + interval '9 hours'),
      pg_temp.lk_row(401, 'LK-AAB', 'QLA', 'QLD', d1 + interval '10 hours')),
    d1 + interval '23 hours 1 minute', false);
  assert (res ->> 'ok')::boolean, 'the loads page wasn''t taken: ' || res::text;
  got := pg_temp.lk_flights(al);
  assert got = '08:05 101 QLA–QLB LK-AAA; 09:05 301 QLC–QLA LK-AAB; 10:05 401 QLA–QLD removed LK-AAB; 12:05 - QLB–QLA -; 14:05 - QLC–QLA -',
    'after the loads page, the flights aren''t linked as the rule says (LK 101 its leg''s route, LK 301 the live QLC–QLA, LK 401 the removed QLA–QLD, each its aircraft): ' || coalesce(got, 'none');

  -- b. the next evening: LK 102's loads join its money, and the flight takes its leg's route
  res := private.capture_store(w, '990801', 'statement', '/test', '[["Date", "Text", "Amount"]]'::jsonb
    || pg_temp.lk_lines(d1 + interval '12 hours 5 minutes', 'QLB-QLA'), d1 + interval '1 day 23 hours', false);
  res := private.capture_store(w, '990801', 'loads', '/test', '[["Flight", "Aircraft"]]'::jsonb || jsonb_build_array(
      pg_temp.lk_row(102, 'LK-AAA', 'QLB', 'QLA', d1 + interval '12 hours')), d1 + interval '1 day 23 hours 1 minute', false);
  assert (res ->> 'ok')::boolean, 'the second loads page wasn''t taken: ' || res::text;
  got := pg_temp.lk_flights(al);
  assert got = '08:05 101 QLA–QLB LK-AAA; 09:05 301 QLC–QLA LK-AAB; 10:05 401 QLA–QLD removed LK-AAB; 12:05 102 QLA–QLB LK-AAA; 14:05 - QLC–QLA -',
    'LK 102, its money first, didn''t take its leg''s route (QLA–QLB) and aircraft when its loads joined it: ' || coalesce(got, 'none');
  select count(*) into n from public.game_flights where airline_id = al;
  assert n = 5, format('the test airline has %s flights, not 5 (LK 102''s money and loads not joined?)', n);

  -- c. a flight with a link is never touched again; capture_refresh() says what it linked
  update public.game_flights f set route_id = (select r.id from public.routes r where r.airline_id = al and r.hub_code = 'QLA' and r.dest_code = 'QLC'),
                                   aircraft_id = (select a.id from public.aircraft a where a.world_id = w and a.registration = 'LK-AAB')
   where f.airline_id = al and f.flight_no is null;
  v := private.fill_flight_links(w);
  assert v = '{"routes": 0, "aircraft": 0}'::jsonb, 'fill_flight_links() changed flights that had their links: ' || v::text;
  assert pg_temp.lk_flights(al) like '%; 14:05 - QLA–QLC removed LK-AAB', 'a flight with its links was linked again: ' || pg_temp.lk_flights(al);
  v := private.capture_refresh(w);
  assert v -> 'links' = '{"routes": 0, "aircraft": 0}'::jsonb, 'capture_refresh() doesn''t say what it linked: ' || v::text;

  -- d. the daily snapshot links first: every link taken away, then the snapshot of 10 Apr
  update public.game_flights set route_id = null, aircraft_id = null where airline_id = al;
  delete from public.route_days where world_id = w;
  v := private.take_snapshot(w, date '2099-04-10', d1 + interval '1 day 23 hours 30 minutes', 'capture');
  assert v -> 'links' = '{"routes": 5, "aircraft": 4}'::jsonb and (v ->> 'route_days')::int = 5,
    'the snapshot didn''t link the 5 flights (4 with an aircraft) before writing 5 route days: ' || v::text;
  assert pg_temp.lk_flights(al) = '08:05 101 QLA–QLB LK-AAA; 09:05 301 QLC–QLA LK-AAB; 10:05 401 QLA–QLD removed LK-AAB; 12:05 102 QLA–QLB LK-AAA; 14:05 - QLC–QLA -',
    'the snapshot linked the flights otherwise: ' || pg_temp.lk_flights(al);
  select string_agg(d.origin_code || '→' || d.dest_code || ' ' || coalesce(r.hub_code || '–' || r.dest_code, '-'), '; ' order by d.origin_code, d.dest_code)
    into got
    from public.route_days d left join public.routes r on r.id = d.route_id
   where d.world_id = w and d.day = '2099-04-10';
  assert got = 'QLA→QLB QLA–QLB; QLA→QLC QLC–QLA; QLA→QLD QLA–QLD; QLB→QLA QLA–QLB; QLC→QLA QLC–QLA',
    'the snapshot''s route days don''t each have their flights'' route: ' || coalesce(got, 'none');
  raise notice 'a world of its own, through the capture''s path: each flight linked as its page is stored (by its leg; by its airports, a live route before a removed one, that way round first; the aircraft named); a flight whose money came first takes its leg''s route when its loads join it; a linked flight never touched again; capture_refresh() and the daily snapshot link first (5 routes, 4 aircraft), and each of the snapshot''s 5 route days has its route';
end
$test$;

do $$ begin raise notice 'flights linked to their routes and aircraft: all checks passed'; end $$;

-- Shared city pairs, the figures (spec docs/specs/2026-11-05-shared-pairs.md §3, §4 and §6; migration
-- 20261105010000_shared_pairs_figures.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. Last night's backup has no joined pair, so every case is built
-- here in a world of its own. A failed check stops with an error that says which (codes, counts and marks of the
-- hand-made world only, never rows of the copy).
--   1. The objects: fig_route_pair(), fig_pair_side() and fig_pair_story() internal and described; shared_pairs_status()
--      staff only, as owner with an empty search path and its own 30 s limit, described; the descriptions of
--      route_profit(), growth_signals(), competition(), fare_results() and route_story() say how a shared pair is read.
--   2. The hand-made world, Saturday 19 Jan 2030 12:00 UTC: OA (India: hub QA1, focus QA2), JB (US: hub QB1, focus QB2), RX
--      excluded as Ryanair is. QA1–QB1 joined by JB: OA's 14 flights of the week sold out, JB's 14 at 60%. QA2–QB1 joined by
--      JB: both airlines' 14 sold out. OA has QA1–QB2 on its list, unflown and unjoined.
--   3. route_profit(): OA's QA1–QB1 is the owner's row with JB's side (14 flights, 60%) and the pair's 28; judged on both
--      airlines' flights, 14 of 28 sold out is hold, where OA's own 14 of 14 would be sold out; JB's row is the joiner's
--      with OA's side. A route on no joined pair is as before.
--   4. growth_signals(): QA2–QB1 listed once, under OA, with shared_with JB (flies); JB's row in follows with OA's mark;
--      neither airline lists QA1–QB1.
--   5. competition(): JB's unflown QB2–QA1 (on OA's list, not JB's) waits for OA while OA's cash forecast says it can
--      order tonight (openings_owner_first), and is JB's opening marked "owner can't fund tonight" when it can't; OA's
--      opening on it carries shared, role owner.
--   6. fare_results(): JB's QB1–QA1 directions take OA's fare plan rows on QA1–QB1, the other way round, marked follows.
--   7. route_story(): OA's and JB's routes give one page: both airlines' 28 flights a week, the days combined, each
--      airline's own money in pair.airlines, one timeline with JB's joining, the title with both airlines; from JB's side
--      its directions and follows.
--   8. shared_pairs_status(): the two joined pairs, both airlines' flights a week, the pair's load (80% on QA1–QB1), OA's
--      level each way, the limit (6, 4 left); signed out and an account that isn't staff refused.
--   9. On the copy: competition(), growth_signals(), route_profit() and route_story() for each of our airlines after the
--      change, beside the same calls before it where database/tests/before/ saved them, each under 30 s.

create temporary table t_sf (k text primary key, v jsonb) on commit drop;
grant select on t_sf to anon, authenticated;
-- the owner's cash forecast's next order for the openings test (section 5), read by the stand-in below
create temporary table t_sf_fund (airline_id bigint primary key, next_when text) on commit drop;
grant select on t_sf_fund to anon, authenticated;
insert into public.planner_users (email) values ('shared-figures-staff@example.com') on conflict do nothing;
create function pg_temp.sf_id(name text) returns bigint language sql as $f$ select (v #>> '{}')::bigint from t_sf where k = name $f$;

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare f text; r text;
begin
  foreach f in array array['private.fig_route_pair(bigint)', 'private.fig_pair_side(bigint, integer, timestamptz)', 'private.fig_pair_story(bigint, timestamptz)'] loop
    assert not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute'), f || ' can be called from outside';
    assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  end loop;
  f := 'public.shared_pairs_status(bigint, timestamptz)';
  assert (select p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=""', 'statement_timeout=30s'] from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, as owner with an empty search path and its 30 s limit';
  assert not has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute'), f || ' isn''t signed in only';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  foreach r in array array['public.route_profit(bigint, integer, timestamptz)', 'public.growth_signals(bigint, timestamptz)', 'public.competition(bigint, timestamptz, integer)',
                           'public.fare_results(bigint, timestamptz)', 'public.route_story(bigint, timestamptz)'] loop
    assert obj_description(r::regprocedure, 'pg_proc') like '%Shared pairs (since 5 Nov%', r || '''s description doesn''t say how a shared pair is read';
  end loop;
  raise notice 'fig_route_pair(), fig_pair_side() and fig_pair_story() internal and described; shared_pairs_status() signed in only, as owner, 30 s, described; route_profit(), growth_signals(), competition(), fare_results() and route_story() describe shared pairs';
end
$test$;

-- ---------------------------------------------------------------- 9 (run second, before the hand-made world). On the copy: the timings
do $test$
declare dw bigint := (select id from public.worlds where is_default); al record; t0 timestamptz; words text := ''; d jsonb; r bigint;
  ms int; was int; worst int := 0; slower text := ''; has_before boolean := to_regclass('rehearsal_before.shared_figures_ms') is not null; fn text;
begin
  t0 := clock_timestamp();
  perform private.fig_growth_signals(dw, now());
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if has_before then execute 'select ms from rehearsal_before.shared_figures_ms where fn = ''growth_signals''' into was; end if;
  words := format('growth_signals %s ms (before %s); ', ms, coalesce(was::text, '—'));
  worst := ms;
  if was is not null and ms > was * 1.25 + 1000 then slower := slower || 'growth_signals '; end if;
  for al in select a.id, a.iata_code from private.fig_airlines(dw) x join public.airlines a on a.id = x.airline_id order by x.ord loop
    select ro.id into r from public.routes ro where ro.airline_id = al.id and not ro.removed
     order by (select count(*) from public.rotations rt where rt.route_id = ro.id) desc, ro.id limit 1;
    words := words || al.iata_code || ':';
    foreach fn in array array['fare_ladder', 'competition', 'route_profit', 'route_story'] loop
      if fn = 'route_story' and r is null then continue; end if;
      t0 := clock_timestamp();
      case fn
        when 'fare_ladder' then perform private.fig_fare_ladder(al.id, now());
        when 'competition' then d := private.fig_competition(al.id, now(), 50);
        when 'route_profit' then perform private.fig_route_profit(al.id, 7, now());
        else perform public.route_story(r, now());
      end case;
      ms := extract(epoch from clock_timestamp() - t0) * 1000;
      was := null;
      if has_before then execute 'select ms from rehearsal_before.shared_figures_ms where airline_id = $1 and fn = $2' into was using al.id, fn; end if;
      worst := greatest(worst, ms);
      if was is not null and ms > was * 1.25 + 1000 then slower := slower || al.iata_code || ' ' || fn || ' '; end if;
      words := words || format(' %s %s ms (before %s)', fn, ms, coalesce(was::text, '—'));
    end loop;
    words := words || format(', openings %s, %s waiting for their owner, %s owner can''t fund tonight; ', jsonb_array_length(d -> 'openings'),
                             coalesce(d ->> 'openings_owner_first', '0'), (select count(*) from jsonb_array_elements(d -> 'openings') e where e #>> '{shared,mark}' is not null));
  end loop;
  assert worst < 30000, 'a figure took 30 s or more on the copy: ' || words;
  assert slower = '', 'noticeably slower than before (over a quarter and a second more): ' || slower || '— ' || words;
  raise notice 'on the copy: %', words;
end
$test$;

-- ---------------------------------------------------------------- 2. the hand-made world
-- a route's week: a rotation launched on 1 Dec 2029, an aircraft, its two legs daily, and 7 flights each way from 12 to 18
-- Jan 2030 with their loads and their money in one row each (economy only, pct full, the fare, profit 20,000 a flight)
create function pg_temp.sf_fly(w bigint, al bigint, r bigint, k int, ty bigint, cfg bigint, pct int, fare numeric)
returns bigint language plpgsql as $f$
declare rot bigint; ac bigint; i int; t timestamptz; hub text; dest text;
begin
  select ro.hub_code, ro.dest_code into hub, dest from public.routes ro where ro.id = r;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, al, r, date '2029-12-01') returning id into rot;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code, acquired)
  values (w, al, 'SF-' || k, ty, cfg, 'active', hub, 'new') returning id into ac;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, al, rot, 1, 8000 + k * 2, hub, dest, ac, '{1,2,3,4,5,6,7}', 840, 60),
    (w, al, rot, 2, 8001 + k * 2, dest, hub, ac, '{1,2,3,4,5,6,7}', 1080, 60);
  for i in 0 .. 13 loop
    t := timestamptz '2030-01-12 14:00:00+00' + make_interval(days => i / 2, hours => (i % 2) * 4, mins => k * 10);
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                     eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at,
                                     posted_at, statement_blk, statement_routes, maint_registration, pax_income, cargo_income,
                                     fuel, onboard, handling, landing, atc, maintenance, income_total, cost_total, money_captured_at)
    values (w, al, (t at time zone 'UTC')::date, 8000 + k * 2 + i % 2, case when i % 2 = 0 then hub else dest end,
            case when i % 2 = 0 then dest else hub end, to_char(t at time zone 'UTC', 'HH24:MI'), t, 'SF-' || k,
            pct * 180 / 100, 180, pct, fare, timestamptz '2030-01-19 11:00:00+00',
            t, 1, 1, 'SF-' || k, 50000, 0, 20000, 2000, 3000, 2000, 1000, 2000, 50000, 30000, timestamptz '2030-01-19 11:00:00+00');
  end loop;
  return rot;
end
$f$;

do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; oa bigint; jb bigint; rx bigint; ty bigint; cy bigint; j jsonb;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'shared pairs figures test', true);
  insert into public.countries (code, name, region) values ('IN', 'India', 'South Asia'), ('US', 'United States', 'North America'), ('FR', 'France', 'Europe')
  on conflict (code) do nothing;
  insert into public.airports (code, city, country_code, utc_offset)
  select c, 'City ' || c, case when c like 'QA%' then 'IN' when c like 'QR%' then 'FR' else 'US' end, 0
    from unnest(array['QA1', 'QA2', 'QB1', 'QB2', 'QR1']) c
  on conflict (code) do update set city = excluded.city, country_code = excluded.country_code, utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('shared pairs figures test', 'shared-figures.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select w, r2.key, r2.value, r2.kind, r2.unit, r2.description from public.world_rules r2 where r2.world_id = dw;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position) values
    (w, g, 990701, 'Figures OA', 'OA', 'OA', 'QA1', true, 1),
    (w, g, 990702, 'Figures JB', 'JB', 'JB', 'QB1', true, 2),
    (w, g, 990703, 'Figures RX', 'RX', 'RX', 'QR1', true, 3);
  select id into oa from public.airlines where world_id = w and iata_code = 'OA';
  select id into jb from public.airlines where world_id = w and iata_code = 'JB';
  select id into rx from public.airlines where world_id = w and iata_code = 'RX';
  update public.settings set value = jsonb_build_array(rx) where world_id = w and airline_id is null and key = 'shared_pairs_excluded_airlines';
  update public.settings set value = to_jsonb('2030-01-10'::text) where world_id = w and airline_id is null and key = 'shared_pairs_from';
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, oa, 'QA1', 'hub', true, 1), (w, oa, 'QA2', 'focus', false, 2), (w, jb, 'QB1', 'hub', true, 1), (w, jb, 'QB2', 'focus', false, 2),
    (w, rx, 'QR1', 'focus', false, 1);
  insert into public.aircraft_types (world_id, name, min_turn_min, cruise_kmh, seats_max, range_km, price)
  values (w, 'FIGURES TEST TYPE', 60, 800, 180, 6000, 50) returning id into ty;
  insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) select w, a, ty from unnest(array[oa, jb]) a;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats) values
    (w, 'SF-Y', ty, 'Leisure', 180, 0, 180) returning id into cy;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, cabin_choice, source)
  select w, oa, x.h, x.d, 1200, 4, 'Leisure', 'research' from (values ('QA1', 'QB1'), ('QA2', 'QB1'), ('QA1', 'QB2')) x (h, d);
  insert into t_sf values ('w', to_jsonb(w)), ('oa', to_jsonb(oa)), ('jb', to_jsonb(jb)), ('ty', to_jsonb(ty)), ('cy', to_jsonb(cy)),
    ('t', to_jsonb(timestamptz '2030-01-19 12:00:00+00'));
  insert into t_sf select 'r ' || ro.hub_code || '-' || ro.dest_code, to_jsonb(ro.id) from public.routes ro where ro.world_id = w;
  -- JB joins QA1–QB1 and QA2–QB1 (the limit's 14 days run from 10 Jan 2030, so the real date is past them: no limit)
  j := public.join_pair(pg_temp.sf_id('r QA1-QB1'));
  insert into t_sf values ('j QB1-QA1', j -> 'route_id');
  j := public.join_pair(pg_temp.sf_id('r QA2-QB1'));
  insert into t_sf values ('j QB1-QA2', j -> 'route_id');
  update public.routes set created_at = timestamptz '2030-01-05 10:00:00+00' where id in (pg_temp.sf_id('j QB1-QA1'), pg_temp.sf_id('j QB1-QA2'));
  perform pg_temp.sf_fly(w, oa, pg_temp.sf_id('r QA1-QB1'), 1, ty, cy, 100, 220);
  perform pg_temp.sf_fly(w, jb, pg_temp.sf_id('j QB1-QA1'), 2, ty, cy, 60, 220);
  perform pg_temp.sf_fly(w, oa, pg_temp.sf_id('r QA2-QB1'), 3, ty, cy, 100, 220);
  perform pg_temp.sf_fly(w, jb, pg_temp.sf_id('j QB1-QA2'), 4, ty, cy, 100, 220);
  -- OA's fare plan on QA1–QB1: up to 110 out (from QA1), 105 back, proposed on 12 Jan
  insert into public.fare_plan (world_id, airline_id, route_id, proposed_on, cabin_class, direction, level_pct, ladder_move, change_pct, fare_from, status, reason)
  values (w, oa, pg_temp.sf_id('r QA1-QB1'), date '2030-01-12', 'economy', 'out', 110, 'up', 10, 200, 'planned', 'shared pairs figures test'),
         (w, oa, pg_temp.sf_id('r QA1-QB1'), date '2030-01-12', 'economy', 'back', 105, 'up', 5, 200, 'planned', 'shared pairs figures test');
end
$setup$;

-- ---------------------------------------------------------------- 3. route profit
do $test$
declare oa bigint := pg_temp.sf_id('oa'); jb bigint := pg_temp.sf_id('jb'); t timestamptz := (select (v #>> '{}')::timestamptz from t_sf where k = 't');
  d jsonb; x jsonb; y jsonb;
begin
  d := private.fig_route_profit(oa, 7, t);
  select e into x from jsonb_array_elements(d -> 'routes') e where (e ->> 'route_id')::bigint = pg_temp.sf_id('r QA1-QB1');
  assert x ->> 'shared_role' = 'owner' and (x #>> '{pair,airline_id}')::bigint = jb and (x #>> '{pair,flights}')::int = 14
     and (x #>> '{pair,flights_week}')::int = 14 and round((x #>> '{pair,economy}')::numeric) = 60 and (x #>> '{pair,sold_out}')::int = 0,
    'OA''s QA1–QB1 doesn''t carry JB''s side (14 flights, 14 a week, 60%, none sold out): ' || coalesce(x::text, 'no row');
  assert (x ->> 'flights')::int = 14 and (x ->> 'sold_out')::int = 14 and (x #>> '{pair,combined,flights}')::int = 28
     and (x #>> '{pair,combined,sold_out}')::int = 14 and (x #>> '{pair,combined,sold_out_share}')::numeric = 0.5
     and round((x #>> '{pair,combined,economy}')::numeric) = 80 and (x #>> '{pair,combined,flights_week}')::int = 28,
    'OA''s QA1–QB1 pair figures aren''t 28 flights, 14 sold out, 80%: ' || (x -> 'pair')::text;
  assert x ->> 'mark' = 'hold', 'QA1–QB1 judged on both airlines'' flights (14 of 28 sold out) isn''t hold: ' || (x ->> 'mark');
  select e into y from jsonb_array_elements(d -> 'routes') e where (e ->> 'route_id')::bigint = pg_temp.sf_id('r QA2-QB1');
  assert y ->> 'shared_role' = 'owner' and y ->> 'mark' in ('add', 'sold_out') and y ->> 'why' like '%sold out on 28 of 28 departures%both airlines'' flights, with JB''s%',
    'OA''s QA2–QB1 (28 of 28 sold out) isn''t sold out on both airlines'' flights: ' || coalesce(y::text, 'no row');
  d := private.fig_route_profit(jb, 7, t);
  select e into x from jsonb_array_elements(d -> 'routes') e where (e ->> 'route_id')::bigint = pg_temp.sf_id('j QB1-QA1');
  assert x ->> 'shared_role' = 'joiner' and (x #>> '{pair,airline_id}')::bigint = oa and (x #>> '{pair,flights}')::int = 14 and x ->> 'mark' = 'hold'
     and (x #>> '{pair,combined,flights}')::int = 28,
    'JB''s QB1–QA1 isn''t the joiner''s row with OA''s side and the pair''s 28 flights: ' || coalesce(x::text, 'no row');
  raise notice 'route_profit(): OA''s QA1–QB1 the owner''s row with JB''s side (14 flights, 14 a week, 60%%) and the pair''s 28 flights, 14 sold out, 80%%: hold on both airlines'' flights, where OA''s own 14 of 14 would be sold out; QA2–QB1 sold out on 28 of 28; JB''s rows the joiner''s with OA''s side';
end
$test$;

-- ---------------------------------------------------------------- 4. growth signals
do $test$
declare w bigint := pg_temp.sf_id('w'); oa bigint := pg_temp.sf_id('oa'); jb bigint := pg_temp.sf_id('jb'); t timestamptz := (select (v #>> '{}')::timestamptz from t_sf where k = 't');
  d jsonb; n int; x jsonb; f jsonb;
begin
  d := private.fig_growth_signals(w, t);
  select count(*)::int into n from jsonb_array_elements((d -> 'ready_for_another_flight') || (d -> 'sold_out') || (d -> 'fix_or_reduce')) e
   where (e ->> 'route_id')::bigint in (pg_temp.sf_id('r QA2-QB1'), pg_temp.sf_id('j QB1-QA2'), pg_temp.sf_id('r QA1-QB1'), pg_temp.sf_id('j QB1-QA1'));
  select e into x from jsonb_array_elements((d -> 'ready_for_another_flight') || (d -> 'sold_out')) e where (e ->> 'route_id')::bigint = pg_temp.sf_id('r QA2-QB1');
  assert n = 1 and (x ->> 'airline_id')::bigint = oa and (x #>> '{shared_with,airline_id}')::bigint = jb and (x #>> '{shared_with,flies}')::boolean
     and (x #>> '{shared_with,flights_week}')::int = 14,
    'QA2–QB1 isn''t listed once, under OA with shared_with JB (flies, 14 a week): ' || n || ' ' || coalesce(x::text, 'none');
  select e into f from jsonb_array_elements(d -> 'follows') e where (e ->> 'route_id')::bigint = pg_temp.sf_id('j QB1-QA2');
  assert (f ->> 'airline_id')::bigint = jb and f ->> 'mark' = x ->> 'mark' and (f #>> '{follows,airline_id}')::bigint = oa
     and (f #>> '{follows,route_id}')::bigint = pg_temp.sf_id('r QA2-QB1'),
    'JB''s QB1–QA2 isn''t in follows with OA''s mark: ' || coalesce(f::text, 'none');
  assert not exists (select 1 from jsonb_array_elements(d -> 'follows') e where (e ->> 'route_id')::bigint = pg_temp.sf_id('j QB1-QA1')),
    'JB''s QB1–QA1 follows a hold';
  raise notice 'growth_signals(): QA2–QB1 listed once, under OA (%) with shared_with JB, flying 14 a week; JB''s QB1–QA2 in follows with OA''s mark; QA1–QB1 (hold on both airlines'' flights) in no list', x ->> 'mark';
end
$test$;

-- ---------------------------------------------------------------- 5. competition: the owner first
-- a stand-in for the owner's cash forecast, inside this rolled-back transaction only: its next order from t_sf_fund
create or replace function private.fig_cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone, p_lease_map jsonb default null)
 returns jsonb language sql stable set search_path to '' as $f$
  select jsonb_build_object('airline_id', p_airline_id, 'status', 'ok',
                            'next_order', jsonb_build_object('when', coalesce((select x.next_when from pg_temp.t_sf_fund x where x.airline_id = p_airline_id), 'now')))
$f$;
do $test$
declare oa bigint := pg_temp.sf_id('oa'); jb bigint := pg_temp.sf_id('jb'); t timestamptz := (select (v #>> '{}')::timestamptz from t_sf where k = 't');
  d jsonb; x jsonb;
begin
  insert into t_sf_fund values (oa, 'now');
  d := private.fig_competition(jb, t);
  assert not exists (select 1 from jsonb_array_elements(d -> 'openings') e where e ->> 'pair' = 'QA1-QB2') and (d ->> 'openings_owner_first')::int = 1,
    'JB''s QB2–QA1 doesn''t wait for OA, who can order tonight: ' || (d -> 'openings')::text || ' owner first ' || coalesce(d ->> 'openings_owner_first', 'none');
  -- flown or joined pairs are never openings
  assert not exists (select 1 from jsonb_array_elements(d -> 'openings') e where e ->> 'pair' in ('QA1-QB1', 'QA2-QB1')), 'a joined pair is an opening for JB';
  update t_sf_fund set next_when = 'later' where airline_id = oa;
  d := private.fig_competition(jb, t);
  select e into x from jsonb_array_elements(d -> 'openings') e where e ->> 'pair' = 'QA1-QB2';
  assert x ->> 'route' = 'QB2–QA1' and x #>> '{shared,role}' = 'joiner' and (x #>> '{shared,airline_id}')::bigint = oa
     and x #>> '{shared,mark}' = 'owner can''t fund tonight' and x #>> '{shared,owner_next_order}' = 'later'
     and (x #>> '{shared,owner_route_id}')::bigint = pg_temp.sf_id('r QA1-QB2') and (x ->> 'stars')::int = 4 and (d ->> 'openings_owner_first')::int = 0,
    'JB''s QB2–QA1 isn''t its opening marked "owner can''t fund tonight" while OA can''t order: ' || coalesce(x::text, 'none');
  -- with p_limit 0 (the report's) the owner's cash isn't read: the pair waits
  assert (private.fig_competition(jb, t, 0) ->> 'openings_owner_first')::int = 1, 'with p_limit 0 JB''s shared opening doesn''t wait for its owner';
  d := private.fig_competition(oa, t);
  select e into x from jsonb_array_elements(d -> 'openings') e where e ->> 'pair' = 'QA1-QB2';
  assert x #>> '{shared,role}' = 'owner' and (x #>> '{shared,airline_id}')::bigint = jb and x #> '{shared,mark}' is null,
    'OA''s QA1–QB2 opening doesn''t carry shared, role owner, JB: ' || coalesce(x::text, 'none');
  raise notice 'competition(): JB''s QB2–QA1 (on OA''s list only) waits while OA can order tonight (openings_owner_first 1) and is JB''s opening, "owner can''t fund tonight", when OA can''t; with p_limit 0 it waits; joined pairs no opening; OA''s opening carries shared, role owner';
end
$test$;

-- ---------------------------------------------------------------- 6. fare results
do $test$
declare oa bigint := pg_temp.sf_id('oa'); jb bigint := pg_temp.sf_id('jb'); d jsonb; x jsonb; got text;
begin
  -- the fares seen: JB's flights at 220 from 12 Jan are OA's +10% on 200 (its route's back is OA's out)
  d := private.fig_fare_results(jb, timestamptz '2030-01-19 12:00:00+00');
  select string_agg(format('%s %s→%s %s', e ->> 'direction', e ->> 'from', e ->> 'to', e #>> '{moves,latest,level}'), '; ' order by e ->> 'direction') into got
    from jsonb_array_elements(d -> 'routes') e where (e ->> 'route_id')::bigint = pg_temp.sf_id('j QB1-QA1');
  select e into x from jsonb_array_elements(d -> 'routes') e where (e ->> 'route_id')::bigint = pg_temp.sf_id('j QB1-QA1') and e ->> 'direction' = 'back';
  assert x is not null and x ->> 'from' = 'QA1' and x ->> 'to' = 'QB1' and (x #>> '{moves,latest,level}')::numeric = 110 and (x #>> '{follows,airline_id}')::bigint = oa
     and (x #>> '{follows,route_id}')::bigint = pg_temp.sf_id('r QA1-QB1'),
    'JB''s QB1–QA1 back (from QA1) doesn''t take OA''s out move to 110, marked follows: ' || coalesce(got, 'none') || ' ' || coalesce(x::text, '');
  raise notice 'fare_results(): JB''s QB1–QA1 directions take OA''s QA1–QB1 moves the other way round (%), marked follows OA', got;
end
$test$;

-- ---------------------------------------------------------------- 7. the route story: one page per pair
do $test$
declare oa bigint := pg_temp.sf_id('oa'); jb bigint := pg_temp.sf_id('jb'); t timestamptz := (select (v #>> '{}')::timestamptz from t_sf where k = 't');
  a jsonb; b jsonb; n int;
begin
  a := public.route_story(pg_temp.sf_id('r QA1-QB1'), t);
  b := public.route_story(pg_temp.sf_id('j QB1-QA1'), t);
  assert a #>> '{pair,role}' = 'owner' and b #>> '{pair,role}' = 'joiner' and (b #>> '{pair,follows}')::boolean and not (a #>> '{pair,follows}')::boolean
     and a #>> '{pair,title}' = 'OA · JB' and b #>> '{pair,title}' = 'OA · JB' and (a #>> '{pair,owner,route_id}')::bigint = pg_temp.sf_id('r QA1-QB1')
     and (a #>> '{pair,joiner,route_id}')::bigint = pg_temp.sf_id('j QB1-QA1') and a #>> '{pair,joiner,joined_on}' = '2030-01-05',
    'route_story() isn''t one page for OA''s and JB''s routes: ' || coalesce((a -> 'pair')::text, 'no pair');
  assert (a #>> '{now,departures,out}')::int = 14 and (a #>> '{now,departures,back}')::int = 14 and (a #>> '{now,rotations}')::int = 2
     and (b #>> '{now,departures,out}')::int = 14 and b #>> '{route,hub}' = 'QB1' and a #>> '{route,hub}' = 'QA1',
    'the pair''s departures aren''t both airlines'' 14 each way: ' || (a -> 'now')::text;
  assert jsonb_array_length(a #> '{pair,airlines}') = 2 and a #>> '{pair,airlines,0,code}' = 'OA' and a #>> '{pair,airlines,1,code}' = 'JB'
     and (a #>> '{pair,airlines,1,departures}')::int = 14,
    'pair.airlines isn''t OA then JB with their own departures: ' || (a #> '{pair,airlines}')::text;
  select count(*)::int into n from jsonb_array_elements(a -> 'events') e where e ->> 'kind' = 'joined' and e ->> 'airline' = 'JB' and e ->> 'day' = '2030-01-05';
  assert n = 1 and (select bool_and(e ? 'airline') from jsonb_array_elements(a -> 'events') e),
    'the timeline doesn''t have JB joining on 5 Jan with every event marked with its airline: ' || (a -> 'events')::text;
  -- one timeline: the same events on both pages, a fare event's direction from each page's side (OA's out is JB's back)
  assert (select jsonb_agg(e - 'direction') from jsonb_array_elements(a -> 'events') e) = (select jsonb_agg(e - 'direction') from jsonb_array_elements(b -> 'events') e)
     and exists (select 1 from jsonb_array_elements(a -> 'events') e where e ->> 'kind' = 'fare' and e ->> 'direction' = 'out' and (e ->> 'level')::numeric = 110)
     and exists (select 1 from jsonb_array_elements(b -> 'events') e where e ->> 'kind' = 'fare' and e ->> 'direction' = 'back' and (e ->> 'level')::numeric = 110),
    'OA''s and JB''s pages don''t have one timeline, each fare event from its own side';
  assert jsonb_array_length(a -> 'fares') is null and jsonb_array_length(a #> '{now,fares}') >= 0, 'the story lost its fares';
  raise notice 'route_story(): OA''s QA1–QB1 and JB''s QB1–QA1 one page, "OA · JB": 14 a week each way and 2 rotations together, from each route''s side; pair.airlines OA then JB with their own money; one timeline, every event marked, JB joined on 5 Jan; from JB''s side follows';
end
$test$;

-- ---------------------------------------------------------------- 8. the Shared pairs row
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "shared-figures-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare d jsonb; x jsonb;
begin
  d := public.shared_pairs_status(pg_temp.sf_id('w'), timestamptz '2030-01-19 12:00:00+00');
  select e into x from jsonb_array_elements(d -> 'pairs') e where (e ->> 'owner_route_id')::bigint = pg_temp.sf_id('r QA1-QB1');
  assert jsonb_array_length(d -> 'pairs') = 2 and (d ->> 'joined')::int = 2 and (d #>> '{limit,pairs}')::int = 6 and (d #>> '{limit,left}')::int = 4
     and d #>> '{limit,until}' = '2030-01-24',
    'shared_pairs_status() isn''t the 2 joined pairs with the limit (6, 4 left, until 24 Jan 2030): ' || (d - 'pairs' - 'notes')::text;
  assert x ->> 'owner_code' = 'OA' and x ->> 'joiner_code' = 'JB' and (x ->> 'owner_flights_week')::int = 14 and (x ->> 'joiner_flights_week')::int = 14
     and (x ->> 'load')::numeric = 80 and (x ->> 'owner_load')::numeric = 100 and (x ->> 'joiner_load')::numeric = 60
     and (select string_agg(l ->> 'direction' || ' ' || (l ->> 'level'), ', ') from jsonb_array_elements(x -> 'levels') l) = 'out 110, back 105',
    'QA1–QB1''s row isn''t OA 14 and JB 14 a week, 80%% together, OA''s 110 out and 105 back: ' || coalesce(x::text, 'none');
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "shared-figures-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare n int := 0;
begin
  begin perform public.shared_pairs_status(null, null); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused shared_pairs_status()';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
set local role anon;
do $test$
declare n int := 0;
begin
  begin perform public.shared_pairs_status(null, null); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, shared_pairs_status() wasn''t refused';
end
$test$;
reset role;
do $test$ begin raise notice 'shared_pairs_status(): the 2 joined pairs, QA1–QB1 OA 14 and JB 14 a week, 80%% together (100%% and 60%%), OA''s 110 out and 105 back, the limit 6 with 4 left until 24 Jan 2030; signed out and an account that isn''t staff refused'; end $test$;


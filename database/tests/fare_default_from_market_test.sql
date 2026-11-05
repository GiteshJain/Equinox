-- The fare ladder reads the game's default price from the market pages (spec docs/specs/2026-11-04-fare-default-from-market.md;
-- migration 20261104000000_fare_default_from_market.sql). Run by database/rehearse.sh on the copy of last night's backup,
-- after the new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which
-- (codes, levels and prices of the hand-made world only, never rows of the copy).
--   1. The objects: market_prices (RLS on, exactly one staff read rule, select for authenticated only, nothing for anon,
--      every column described, every foreign key indexed, its read's key cascading); default_prices() signed in only,
--      as owner with an empty search path, described, no statement limit of its own; its builder internal.
--   2. capture_market() keeps the Pricing panel: a world of its own with its own key, our airline flying MA1–MB1; a page
--      with pricing (DEL→BOM's figures: Y 150 / 143, C 322 / 307, F 539 / 539, Cargo 104 / 104) gives one market_prices row
--      a class; the same page sent again replaces them; a page without pricing writes none; pricing that doesn't read (a
--      class it doesn't know, a price that isn't a number above 0, a class twice) is refused, writing nothing.
--   3. The ladder (spec §5), at Saturday 19 Jan 2030 12:00 UTC, every route flown daily, each direction 7 departures in the
--      week, launched 1 Dec 2029 with its first captured fares the next day:
--      - MA (launch 85%, as Ryanair), MA1–MB2, the CDG–Hamburg case: first captured fare 118, today 100, the market's
--        default 118 both ways: the level is 85 from the default (fare index 84.7, matches), no set-back; read the old way
--        it would be 72.0 (inferred_index) and set back. default_source market, baseline_fare 118, default_on 14 Jan.
--      - MA, MA1–MB3: no market read, as today: inferred, first fare 255 and today 255, index 85.0 against it.
--      - MC (launch 100%), MC1–MD1: default 200 both ways, first fare 180: the back direction at 200 is at its level by
--        the default (100.0; it would read 111.1 the old way), the out direction's latest flight at 210 is set back
--        against the default ("captured fare at 105%, level 100%"), first in the actions.
--      - MC, MC1–MD2: the default changed between two runs: 300 on 10 Jan, then 330 out on 17 Jan (back stays 300).
--        Before the second run the out direction is at 100.0, no set-back; after it the level moves to 90.9 and a set-back
--        is listed for out only; default_prices() shows 330 against 300 before it (default_changed) and run_on 17 Jan.
--      default_prices(): one row per route, direction and cabin read (business from C), economy first.
--   4. Signed out and an account that isn't staff are refused default_prices(); staff get what postgres gets.
--   5. On the copy: fare_ladder()'s builder timed for every one of our airlines after the changes, beside the same calls
--      before them (rehearsal_before.fare_ladder_ms, database/tests/before/frequencies_and_fares_before.sql); each under
--      the 30 s limit and not more than a quarter (plus a second) slower than before. Timed by running spec §4's one-off
--      query (the directions whose default-based level differs from the inferred one by more than a point) for each
--      airline, so the pull request's query is known to run; its rows are counted, never shown.

create temporary table t_dm (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_dm to anon, authenticated;
insert into public.planner_users (email) values ('fare-default-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare bad text; r text; p text; f text := 'public.default_prices(bigint, timestamptz)'; g text := 'private.fig_default_prices(bigint, timestamptz)';
begin
  assert (select relrowsecurity from pg_class where oid = 'public.market_prices'::regclass), 'market_prices has no RLS';
  assert (select count(*) from pg_policies where schemaname = 'public' and tablename = 'market_prices') = 1
     and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'market_prices' and policyname = 'staff read'
                    and cmd = 'SELECT' and roles = '{authenticated}' and qual like '%is_planner_user%'),
    'market_prices should have exactly one rule: staff read (select for authenticated, is_planner_user())';
  foreach r in array array['anon', 'authenticated'] loop
    foreach p in array array['insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
      assert not has_table_privilege(r, 'public.market_prices', p), r || ' has ' || p || ' on market_prices';
    end loop;
  end loop;
  assert not has_table_privilege('anon', 'public.market_prices', 'select'), 'signed out can read market_prices';
  assert has_table_privilege('authenticated', 'public.market_prices', 'select'), 'staff can''t read market_prices';
  assert length(coalesce(obj_description('public.market_prices'::regclass, 'pg_class'), '')) > 200, 'market_prices has no description';
  select string_agg(a.attname, ', ') into bad from pg_attribute a
   where a.attrelid = 'public.market_prices'::regclass and a.attnum > 0 and not a.attisdropped and coalesce(col_description(a.attrelid, a.attnum), '') = '';
  assert bad is null, 'market_prices columns without a description: ' || bad;
  select string_agg(x.conname, ', ') into bad from pg_constraint x
   where x.conrelid = 'public.market_prices'::regclass and x.contype = 'f'
     and not exists (select 1 from pg_index i where i.indrelid = x.conrelid and i.indkey[0] = x.conkey[1]);
  assert bad is null, 'market_prices foreign keys without an index: ' || bad;
  assert (select confdeltype from pg_constraint where conname = 'market_prices_read_world_fkey') = 'c',
    'market_prices'' read key doesn''t cascade (the archive deletes reads after a month)';
  -- default_prices(): signed in only, as owner, empty search path, no statement limit of its own (it is small)
  assert (select p2.prosecdef and p2.provolatile = 's' and coalesce('search_path=""' = any (p2.proconfig), false)
                 and not exists (select 1 from unnest(p2.proconfig) c where c like 'statement_timeout=%') from pg_proc p2 where p2.oid = f::regprocedure),
    f || ' isn''t stable, as owner with an empty search path and no limit of its own';
  assert not has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute'), f || ' isn''t signed in only';
  assert not exists (select 1 from pg_proc p2 cross join aclexplode(coalesce(p2.proacl, acldefault('f', p2.proowner))) a
                      where p2.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute'), g || ' can be called from outside';
  assert (select not p2.prosecdef and p2.provolatile = 's' and coalesce('search_path=""' = any (p2.proconfig), false) from pg_proc p2 where p2.oid = g::regprocedure),
    g || ' runs as owner, isn''t stable or has no empty search path';
  assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 100, g || ' has no description';
  assert obj_description('public.fare_ladder(bigint, timestamptz)'::regprocedure, 'pg_proc') like '%default_source is inferred%',
    'fare_ladder()''s description doesn''t say how the default price is read';
  raise notice 'market_prices: RLS on, staff read only, columns described, foreign keys indexed, its read''s key cascading; default_prices() signed in only, as owner, no limit of its own, described; its builder internal';
end
$test$;

-- ---------------------------------------------------------------- the hand-made world
-- one route: its rotation, an aircraft, its two legs, its first fares the day after it launched (1 Dec 2029) and 7 days
-- each way in the week before Saturday 19 Jan 2030 12:00 UTC (12 to 18 Jan), all economy, sold out, at `fare`
create function pg_temp.dm_route(w bigint, al bigint, hub text, dest text, k int, ty bigint, cfg bigint, base numeric, fare numeric)
returns bigint language plpgsql as $f$
declare r bigint; rot bigint; ac bigint; i int; t timestamptz;
begin
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, al, hub, dest, 1000, 'research') returning id into r;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, al, r, date '2029-12-01') returning id into rot;
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code, acquired)
  values (w, al, 'ZM-' || k, ty, cfg, 'active', hub, 'new') returning id into ac;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, al, rot, 1, 7000 + k * 2, hub, dest, ac, '{1,2,3,4,5,6,7}', 840, 60),
    (w, al, rot, 2, 7001 + k * 2, dest, hub, ac, '{1,2,3,4,5,6,7}', 1080, 60);
  for i in 0 .. 1 loop
    t := timestamptz '2029-12-02 14:00:00+00' + make_interval(hours => i * 4);
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                     eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
    values (w, al, date '2029-12-02', 7000 + k * 2 + i, case when i = 0 then hub else dest end, case when i = 0 then dest else hub end,
            to_char(t, 'HH24:MI'), t, 'ZM-' || k, 180, 180, 100, base, t + interval '1 day');
  end loop;
  for i in 0 .. 13 loop
    t := timestamptz '2030-01-12 14:00:00+00' + make_interval(days => i / 2, hours => (i % 2) * 4);
    insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, dep_at, registration,
                                     eco_pax, eco_seats, eco_pct, eco_fare, loads_captured_at)
    values (w, al, (t at time zone 'UTC')::date, 7000 + k * 2 + i % 2, case when i % 2 = 0 then hub else dest end,
            case when i % 2 = 0 then dest else hub end, to_char(t at time zone 'UTC', 'HH24:MI'), t, 'ZM-' || k, 180, 180, 100, fare,
            timestamptz '2030-01-19 11:00:00+00');
  end loop;
  return r;
end
$f$;

-- a finished market run and its reads with their prices: pages [[origin, dest, Y default, Y current, C default, C current]]
create function pg_temp.dm_run(w bigint, al bigint, started timestamptz, pages jsonb)
returns bigint language plpgsql as $f$
declare run bigint; rd bigint; p jsonb;
begin
  insert into public.market_runs (world_id, started_at, finished_at, status, pages_read, pages_failed)
  values (w, started, started + interval '15 minutes', 'done', jsonb_array_length(pages), 0) returning id into run;
  for p in select x from jsonb_array_elements(pages) x loop
    insert into public.market_reads (run_id, world_id, airline_id, origin, dest, read_at, ok)
    values (run, w, al, p ->> 0, p ->> 1, started + interval '5 minutes', true) returning id into rd;
    insert into public.market_prices (read_id, world_id, airline_id, service_class, current_price, default_price) values
      (rd, w, al, 'Y', (p ->> 3)::numeric, (p ->> 2)::numeric), (rd, w, al, 'C', (p ->> 5)::numeric, (p ->> 4)::numeric);
  end loop;
  return run;
end
$f$;

-- a ladder's row for one direction, as "level fare_index/inferred_index source fix"
create function pg_temp.dm_line(d jsonb, dest text, dir text) returns text language sql as $f$
  select format('%s %s/%s %s %s', x ->> 'level', coalesce(x ->> 'fare_index', '-'), coalesce(x ->> 'inferred_index', '-'), x ->> 'default_source',
                case when (x ->> 'fix')::boolean then 'fix' else 'ok' end)
    from jsonb_array_elements(d -> 'routes') x where x ->> 'dest' = dest and x ->> 'direction' = dir and x ->> 'cabin' = 'economy'
$f$;

do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; ma bigint; mc bigint; ty bigint; cy bigint; r bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'fare default test', true);
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['MA1', 'MB1', 'MB2', 'MB3', 'MC1', 'MD1', 'MD2']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('fare default test', 'fare-default.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select w, r2.key, r2.value, r2.kind, r2.unit, r2.description from public.world_rules r2 where r2.world_id = dw;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position) values
    (w, g, 990501, 'Default A', 'D A', 'MA', 'MA1', true, 1),
    (w, g, 990502, 'Default C', 'D C', 'MC', 'MC1', true, 2);
  select id into ma from public.airlines where world_id = w and iata_code = 'MA';
  select id into mc from public.airlines where world_id = w and iata_code = 'MC';
  insert into public.settings (world_id, airline_id, key, value, unit, description) values
    (w, ma, 'fare_launch_pct', '85'::jsonb, '% of standard', 'test: launches at 85%, as Ryanair');
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, ma, 'MA1', 'hub', true, 1), (w, mc, 'MC1', 'hub', true, 1);
  insert into public.aircraft_types (world_id, name, min_turn_min, cruise_kmh) values (w, 'DEFAULT TEST TYPE', 60, 800) returning id into ty;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats) values
    (w, 'DEF-Y', ty, 'Standard', 180, 0, 180) returning id into cy;

  r := pg_temp.dm_route(w, ma, 'MA1', 'MB1', 1, ty, cy, 255, 255);   -- the capture's pair (2.)
  r := pg_temp.dm_route(w, ma, 'MA1', 'MB2', 2, ty, cy, 118, 100);
  r := pg_temp.dm_route(w, ma, 'MA1', 'MB3', 3, ty, cy, 255, 255);
  r := pg_temp.dm_route(w, mc, 'MC1', 'MD1', 4, ty, cy, 180, 200);
  -- MC1–MD1's out flight on 18 Jan, its latest captured day that way, at 210
  update public.game_flights set eco_fare = 210 where airline_id = mc and registration = 'ZM-4' and game_date = '2030-01-18' and origin_code = 'MC1';
  r := pg_temp.dm_route(w, mc, 'MC1', 'MD2', 5, ty, cy, 300, 300);

  -- the market runs: MA's on 14 Jan (MB2 both ways at 118); MC's on 10 Jan (MD1 at 200, MD2 at 300, both ways)
  perform pg_temp.dm_run(w, ma, timestamptz '2030-01-14 02:00:00+00', '[["MA1", "MB2", 118, 100, 300, 300], ["MB2", "MA1", 118, 100, 300, 300]]');
  perform pg_temp.dm_run(w, mc, timestamptz '2030-01-10 02:00:00+00',
    '[["MC1", "MD1", 200, 210, 500, 500], ["MD1", "MC1", 200, 200, 500, 500], ["MC1", "MD2", 300, 300, 700, 700], ["MD2", "MC1", 300, 300, 700, 700]]');

  insert into public.capture_keys (label, key_hash, world_id) values ('fare default test', extensions.crypt('fare-default-test-key', extensions.gen_salt('bf')), w);
  insert into t_dm values ('w', to_jsonb(w)), ('ma', to_jsonb(ma)), ('mc', to_jsonb(mc)), ('t', to_jsonb(timestamptz '2030-01-19 12:00:00+00'));
end
$setup$;

-- ---------------------------------------------------------------- 2. capture_market() keeps the Pricing panel
set local role anon;
do $test$
declare k text := 'fare-default-test-key'; run bigint; r jsonb; pg jsonb;
  pricing jsonb := '[{"class": "Y", "current": 150, "default": 143}, {"class": "C", "current": 322, "default": 307}, {"class": "F", "current": 539, "default": 539}, {"class": "Cargo", "current": 104, "default": 104}]';
begin
  r := public.capture_market(k, 'start', '{"version": "1.11", "total": 2}');
  assert (r ->> 'ok')::boolean, 'start refused: ' || r::text;
  run := (r ->> 'run_id')::bigint;
  pg := jsonb_build_object('run_id', run, 'airline', 990501, 'origin', 'MA1', 'dest', 'MB1', 'ok', true, 'fares', '[]'::jsonb, 'shares', '[]'::jsonb, 'weeks', '[]'::jsonb);
  r := public.capture_market(k, 'page', pg || jsonb_build_object('pricing', pricing));
  assert (r ->> 'ok')::boolean and (r ->> 'prices')::int = 4, 'the page with pricing didn''t write four prices: ' || r::text;
  insert into t_dm values ('read1', r -> 'read_id');
  -- sent again: replaced (Y's default now 145)
  r := public.capture_market(k, 'page', pg || jsonb_build_object('pricing', jsonb_set(pricing, '{0,default}', '145')));
  assert (r ->> 'ok')::boolean and (r ->> 'prices')::int = 4, 'the page sent again didn''t write four prices: ' || r::text;
  insert into t_dm values ('read2', r -> 'read_id');
  -- the other way, without the panel: none, no error
  r := public.capture_market(k, 'page', jsonb_set(pg, '{origin}', '"MB1"') || '{"dest": "MA1"}');
  assert (r ->> 'ok')::boolean and (r ->> 'prices')::int = 0, 'a page without pricing wasn''t read, or wrote prices: ' || r::text;
  insert into t_dm values ('read3', r -> 'read_id');
  -- refused, writing nothing
  r := public.capture_market(k, 'page', jsonb_set(pg, '{origin}', '"MB3"') || '{"dest": "MA1", "pricing": [{"class": "W", "current": 1, "default": 1}]}');
  assert not (r ->> 'ok')::boolean and r ->> 'error' like 'pricing that doesn''t read: W%', 'a class it doesn''t know wasn''t refused: ' || r::text;
  r := public.capture_market(k, 'page', jsonb_set(pg, '{origin}', '"MB3"') || '{"dest": "MA1", "pricing": [{"class": "Y", "current": "150 AS$", "default": 143}]}');
  assert not (r ->> 'ok')::boolean and r ->> 'error' like 'pricing that doesn''t read: Y%', 'a price that isn''t a number wasn''t refused: ' || r::text;
  r := public.capture_market(k, 'page', jsonb_set(pg, '{origin}', '"MB3"') || '{"dest": "MA1", "pricing": [{"class": "Y", "current": 150, "default": 0}]}');
  assert not (r ->> 'ok')::boolean and r ->> 'error' like 'pricing that doesn''t read: Y%', 'a default of 0 wasn''t refused: ' || r::text;
  r := public.capture_market(k, 'page', jsonb_set(pg, '{origin}', '"MB3"') || '{"dest": "MA1", "pricing": [{"class": "Y", "current": 150, "default": 143}, {"class": "Y", "current": 150, "default": 143}]}');
  assert not (r ->> 'ok')::boolean and r ->> 'error' like 'pricing with a class twice: Y%', 'a class twice wasn''t refused: ' || r::text;
  r := public.capture_market(k, 'page', jsonb_set(pg, '{origin}', '"MB3"') || '{"dest": "MA1", "pricing": {"Y": 1}}');
  assert not (r ->> 'ok')::boolean and r ->> 'error' like '%must be lists%', 'pricing that isn''t a list wasn''t refused: ' || r::text;
  insert into t_dm values ('run_c', to_jsonb(run));
end
$test$;
reset role;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_dm where k = 'w'); ma bigint := (select (v #>> '{}')::bigint from t_dm where k = 'ma');
  run bigint := (select (v #>> '{}')::bigint from t_dm where k = 'run_c'); got text;
begin
  assert not exists (select 1 from public.market_prices where read_id = (select (v #>> '{}')::bigint from t_dm where k = 'read1')),
    'the first read''s prices are still there after the page was sent again';
  select string_agg(p.service_class || ' ' || p.current_price || '/' || p.default_price, ', ' order by p.service_class) into got
    from public.market_prices p join public.market_reads m on m.id = p.read_id
   where m.run_id = run and m.origin = 'MA1' and m.dest = 'MB1' and p.airline_id = ma and p.world_id = w;
  assert got = 'C 322/307, Cargo 104/104, F 539/539, Y 150/145', 'MA1→MB1''s prices aren''t the page''s: ' || coalesce(got, 'none');
  assert not exists (select 1 from public.market_prices p join public.market_reads m on m.id = p.read_id where m.run_id = run and m.origin = 'MB1'),
    'the page without pricing has prices';
  assert not exists (select 1 from public.market_reads m where m.run_id = run and m.origin = 'MB3'), 'a refused page was written';
  assert (select count(*) from public.market_prices p join public.market_reads m on m.id = p.read_id where m.run_id = run) = 4,
    'the run doesn''t hold exactly the one page''s four prices';
  -- a read deleted (as the monthly archive deletes it) takes its prices
  delete from public.market_reads where id = (select (v #>> '{}')::bigint from t_dm where k = 'read2');
  assert (select count(*) from public.market_prices p join public.market_reads m on m.id = p.read_id where m.run_id = run) = 0
     and not exists (select 1 from public.market_prices where read_id = (select (v #>> '{}')::bigint from t_dm where k = 'read2')),
    'deleting a read left its prices';
  -- the open run isn't finished, so the ladder never reads it; it is dropped here so later checks see only the made runs
  delete from public.market_reads where run_id = run;
  delete from public.market_runs where id = run;
  raise notice 'capture_market(): a page with pricing writes one market_prices row a class (C 322/307, Cargo 104/104, F 539/539, Y 150/145), sent again replaces them, without pricing writes none; a class it doesn''t know, a price that isn''t a number above 0, a class twice or a list that isn''t one refused, writing nothing; a read deleted takes its prices';
end
$test$;

-- ---------------------------------------------------------------- 3. the ladder against the default
do $test$
declare ma bigint := (select (v #>> '{}')::bigint from t_dm where k = 'ma'); mc bigint := (select (v #>> '{}')::bigint from t_dm where k = 'mc');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_dm where k = 't'); d jsonb; x jsonb; got text;
begin
  d := private.fig_fare_ladder(ma, t);
  -- MB2: the CDG–Hamburg case, at its 85% level by the default
  assert pg_temp.dm_line(d, 'MB2', 'out') = '85 84.7/72.0 market ok' and pg_temp.dm_line(d, 'MB2', 'back') = '85 84.7/72.0 market ok',
    'MA1–MB2 isn''t at 85 by its default of 118 (read the old way 72.0): ' || coalesce(pg_temp.dm_line(d, 'MB2', 'out'), 'no row') || ' · ' || coalesce(pg_temp.dm_line(d, 'MB2', 'back'), 'no row');
  select e into x from jsonb_array_elements(d -> 'routes') e where e ->> 'dest' = 'MB2' and e ->> 'direction' = 'out';
  assert (x ->> 'baseline_fare')::numeric = 118 and x ->> 'baseline_on' = '2030-01-14' and x ->> 'default_on' = '2030-01-14'
     and (x ->> 'index_matches')::boolean and x ->> 'fix_reason' is null,
    'MA1–MB2''s baseline isn''t its default (118, read on 14 Jan): ' || x::text;
  -- MB3: no market read, as before
  assert pg_temp.dm_line(d, 'MB3', 'out') = '85 85.0/85.0 inferred ok', 'MA1–MB3 isn''t inferred as before: ' || coalesce(pg_temp.dm_line(d, 'MB3', 'out'), 'no row');
  select e into x from jsonb_array_elements(d -> 'routes') e where e ->> 'dest' = 'MB3' and e ->> 'direction' = 'back';
  assert (x ->> 'baseline_fare')::numeric = 255 and x ->> 'baseline_on' = '2029-12-02' and x ->> 'default_on' is null,
    'MA1–MB3''s baseline isn''t its first captured fare: ' || x::text;
  assert not exists (select 1 from jsonb_array_elements(d -> 'actions') a where a ->> 'route' in ('MA1–MB2', 'MA1–MB3') and (a ->> 'fix')::boolean),
    'MA has a set-back change';
  assert (d #>> '{notes,0}') like 'Since 4 Nov the fare index measures each flight%', 'the notes don''t say how the index reads now';

  d := private.fig_fare_ladder(mc, t);
  -- MD1: back at its level by the default; out set back against it
  assert pg_temp.dm_line(d, 'MD1', 'back') = '100 100.0/111.1 market ok', 'MD1→MC1 isn''t at 100 by its default: ' || coalesce(pg_temp.dm_line(d, 'MD1', 'back'), 'no row');
  assert pg_temp.dm_line(d, 'MD1', 'out') = '100 105.0/116.7 market fix', 'MC1→MD1 isn''t set back against its default: ' || coalesce(pg_temp.dm_line(d, 'MD1', 'out'), 'no row');
  select e into x from jsonb_array_elements(d -> 'routes') e where e ->> 'dest' = 'MD1' and e ->> 'direction' = 'out';
  assert x ->> 'fix_reason' = 'captured fare at 105%, level 100%', 'MC1→MD1''s set-back reason: ' || coalesce(x ->> 'fix_reason', 'none');
  assert (d #>> '{actions,0,fix}')::boolean and d #>> '{actions,0,from}' = 'MC1' and d #>> '{actions,0,to}' = 'MD1' and (d #>> '{actions,0,level}')::numeric = 100,
    'the first action isn''t MC1→MD1''s set-back to 100: ' || coalesce(d #>> '{actions,0}', 'none');
  -- MD2 before its default changed: at 100 both ways
  assert pg_temp.dm_line(d, 'MD2', 'out') = '100 100.0/100.0 market ok' and pg_temp.dm_line(d, 'MD2', 'back') = '100 100.0/100.0 market ok',
    'MC1–MD2 isn''t at 100 by its default of 300 before the second run: ' || coalesce(pg_temp.dm_line(d, 'MD2', 'out'), 'no row');
  assert (d ->> 'off_level')::int = 1, 'MC has another count of directions set back than one: ' || (d ->> 'off_level');
  insert into t_dm values ('mc_before', d);
  raise notice 'the ladder: MA1–MB2 (first fare 118, today 100) at 85 by its default of 118 (84.7; 72.0 the old way, which would set it back), no change; MA1–MB3 with no market read inferred as before (85.0); MC1–MD1 back at 100 by its default of 200 (111.1 the old way), out set back against it (105%%), first in the actions';
end
$test$;

-- the second run: MD2's default out 300 → 330 on 17 Jan (back unchanged)
do $setup$
declare w bigint := (select (v #>> '{}')::bigint from t_dm where k = 'w'); mc bigint := (select (v #>> '{}')::bigint from t_dm where k = 'mc');
begin
  perform pg_temp.dm_run(w, mc, timestamptz '2030-01-17 02:00:00+00', '[["MC1", "MD2", 330, 300, 700, 700], ["MD2", "MC1", 300, 300, 720, 700]]');
end
$setup$;

do $test$
declare mc bigint := (select (v #>> '{}')::bigint from t_dm where k = 'mc'); t timestamptz := (select (v #>> '{}')::timestamptz from t_dm where k = 't');
  d jsonb; p jsonb; got text;
begin
  d := private.fig_fare_ladder(mc, t);
  assert pg_temp.dm_line(d, 'MD2', 'out') = '100 90.9/100.0 market fix', 'MC1→MD2 didn''t move to 90.9 with a set-back after its default went to 330: ' || coalesce(pg_temp.dm_line(d, 'MD2', 'out'), 'no row');
  assert pg_temp.dm_line(d, 'MD2', 'back') = '100 100.0/100.0 market ok', 'MD2→MC1 moved though its default didn''t: ' || coalesce(pg_temp.dm_line(d, 'MD2', 'back'), 'no row');
  assert (select e ->> 'fix_reason' from jsonb_array_elements(d -> 'routes') e where e ->> 'dest' = 'MD2' and e ->> 'direction' = 'out') = 'captured fare at 90.9%, level 100%',
    'MC1→MD2''s set-back reason isn''t against 330';
  assert (select e ->> 'default_on' from jsonb_array_elements(d -> 'routes') e where e ->> 'dest' = 'MD2' and e ->> 'direction' = 'out') = '2030-01-17',
    'MC1→MD2''s default isn''t the 17 Jan run''s';
  assert (d ->> 'off_level')::int = 2 and (select count(*) from jsonb_array_elements(d -> 'actions') a where (a ->> 'fix')::boolean) = 2,
    'MC doesn''t have two directions set back (MC1→MD1 and MC1→MD2): ' || (d ->> 'off_level');
  -- before the second run finished (as of 17 Jan 02:10), the first run's default still holds
  assert (select e.default_price from private.fig_default_prices(mc, timestamptz '2030-01-17 02:10:00+00') e
           where e.dest = 'MD2' and e.direction = 'out' and e.cabin = 'economy') = 300,
    'a run not finished by the moment was read';

  -- default_prices(): the rows, economy first, the change shown
  p := public.default_prices(mc, t);
  select string_agg(format('%s %s %s %s/%s%s', e ->> 'from', e ->> 'to', e ->> 'cabin', e ->> 'default_price', coalesce(e ->> 'previous_default', '-'),
                           case when (e ->> 'default_changed')::boolean then ' changed' else '' end), '; ' order by o) into got
    from jsonb_array_elements(p -> 'prices') with ordinality as x(e, o);
  assert got = 'MC1 MD1 economy 200/-; MC1 MD1 business 500/-; MD1 MC1 economy 200/-; MD1 MC1 business 500/-; '
            || 'MC1 MD2 economy 330/300 changed; MC1 MD2 business 700/700; MD2 MC1 economy 300/300; MD2 MC1 business 720/700 changed',
    'default_prices() isn''t as made: ' || coalesce(got, 'none');
  assert (select e ->> 'run_on' = '2030-01-17' and e ->> 'previous_run_on' = '2030-01-10' and (e ->> 'current_price')::numeric = 300
                 and (e ->> 'current_pct')::numeric = 90.9 and e ->> 'direction' = 'out' and e ->> 'hub' = 'MC1'
            from jsonb_array_elements(p -> 'prices') e where e ->> 'to' = 'MD2' and e ->> 'cabin' = 'economy'),
    'default_prices()''s MC1→MD2 economy row isn''t as made';
  insert into t_dm values ('mc_prices', p);
  raise notice 'the default changed between two runs: MC1→MD2 300 → 330 moves its level from 100.0 to 90.9 and lists a set-back (out only); a run not finished by the moment isn''t read; default_prices(): 8 rows, business from C, economy first, the change shown';
end
$test$;

-- ---------------------------------------------------------------- 4. who is refused; staff get what postgres gets
set local role anon;
do $test$
declare mc bigint := (select (v #>> '{}')::bigint from t_dm where k = 'mc'); n int := 0;
begin
  begin perform public.default_prices(mc); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, default_prices() wasn''t refused';
  begin perform 1 from public.market_prices limit 1; exception when insufficient_privilege then n := n + 1; end;
  assert n = 2, 'signed out, market_prices could be read';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d1", "email": "fare-default-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare mc bigint := (select (v #>> '{}')::bigint from t_dm where k = 'mc'); n int := 0;
begin
  begin perform public.default_prices(mc); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused default_prices()';
  assert (select count(*) from public.market_prices) = 0, 'an account that isn''t staff sees market_prices rows';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d2", "email": "fare-default-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare mc bigint := (select (v #>> '{}')::bigint from t_dm where k = 'mc'); t timestamptz := (select (v #>> '{}')::timestamptz from t_dm where k = 't');
begin
  assert public.default_prices(mc, t) = (select v from t_dm where k = 'mc_prices'), 'staff don''t get what postgres gets from default_prices()';
  assert (select count(*) from public.market_prices p join public.market_reads m on m.id = p.read_id where m.airline_id = mc) = 12,
    'staff don''t see the made runs'' prices';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused default_prices() and see no market_prices; staff get what postgres gets'; end $test$;

-- ---------------------------------------------------------------- 5. on the copy: the time, and spec §4's one-off query
-- The query below is the pull request's (one airline at a time; there it names the airline by its code): every direction
-- whose level by the market's default differs from the inferred one by more than a point.
do $test$
declare x record; t0 timestamptz; ms int; n int; before_ms int; lines text[] := '{}'; total int := 0; total_before int := 0; slowest int := 0;
  n_dirs int := 0;
begin
  for x in select a.id, a.iata_code from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
            where a.world_id = (select id from public.worlds where is_default) and g.kind = 'ours' and a.active
              and a.id in (select f.airline_id from private.fig_airlines(private.fig_world(null)) f)
            order by a.position nulls last, a.id loop
    t0 := clock_timestamp();
    select count(*) into n from (
      select a.iata_code as airline, e ->> 'from' as "from", e ->> 'to' as "to", e ->> 'cabin' as cabin, (e ->> 'level')::numeric as level,
             (e ->> 'fare_index')::numeric as by_default, (e ->> 'inferred_index')::numeric as inferred,
             (e ->> 'baseline_fare')::numeric as default_price, e ->> 'default_on' as read_on, (e ->> 'fix')::boolean as set_back
        from public.airlines a
        join public.groups g on g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
       cross join lateral jsonb_array_elements(private.fig_fare_ladder(a.id, now()) -> 'routes') e
       where a.world_id = (select id from public.worlds where is_default) and a.iata_code = x.iata_code
         and e ->> 'default_source' = 'market'
         and abs((e ->> 'fare_index')::numeric - (e ->> 'inferred_index')::numeric) > 1
       order by 2, 3, 4) q;
    ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    before_ms := null;
    if to_regclass('rehearsal_before.fare_ladder_ms') is not null then
      execute 'select b.ms from rehearsal_before.fare_ladder_ms b where b.airline_id = $1' into before_ms using x.id;
    end if;
    assert ms < 30000, format('%s: fare_ladder()''s builder took %s ms on the copy (its limit is 30 s)', x.iata_code, ms);
    assert before_ms is null or ms <= before_ms * 1.25 + 1000,
      format('%s: fare_ladder()''s builder took %s ms on the copy, %s ms before the changes (more than a quarter and a second slower)', x.iata_code, ms, before_ms);
    n_dirs := n_dirs + n; total := total + ms; total_before := total_before + coalesce(before_ms, 0); slowest := greatest(slowest, ms);
    lines := lines || format('%s %s ms (before %s ms), %s direction(s) off', x.iata_code, ms, coalesce(before_ms::text, '—'), n);
  end loop;
  raise notice 'on the copy, fare_ladder()''s builder for each of our airlines after the changes (before them): %; % ms in all (% before), the slowest % ms; spec §4''s one-off query ran for each: % direction(s) whose level by the default differs from the inferred one by more than a point (none until a market run with prices)',
    coalesce(array_to_string(lines, '; '), 'no airlines'), total, total_before, slowest, n_dirs;
end
$test$;

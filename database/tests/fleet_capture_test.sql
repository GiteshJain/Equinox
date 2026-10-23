-- The fleet in the evening capture (migration 20261022070000_fleet_capture.sql; spec
-- docs/specs/2026-10-22-fleet-capture.md §2; manual §7). Run by database/rehearse.sh on the copy of last night's backup,
-- after the new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which
-- (codes, registrations and counts of the hand-made world only).
--   1. The objects: game_fleet has RLS with one staff read rule, signed out holds nothing on it, signed in may only read
--      it, a description on it and every column, every foreign key indexed, one row per aircraft per capture day;
--      fleet_checks() signed in only, stable, as owner with an empty search path and its own 30 s limit, described; its
--      builder and private.capture_fleet() internal, with an empty search path, described.
--   2. A world of its own, made inside the test, with its own capture key: two airlines of ours (FA, FB, whose own
--      maintenance_min_pct is 105) and a third (FC) that sends no fleet pages; the planner's aircraft and cabins.
--      The page kind and its check: through capture_ingest(), signed out with the key, as Capture all airlines 1.6 sends
--      it, a fleet page is taken, read and judged ok ("fleet ZF1 3 aircraft"); a bad kind is still refused. Through the
--      capture's own store at chosen moments: a fleet page with no aircraft rows is short ("fleet ZF2: no aircraft
--      rows"); one sent with its error, one that isn't a fleet page and one with a row without its registration are
--      broken and write nothing; fleet pages take no part in the day's completeness.
--   3. The matching and the night: one row per aircraft per capture day (10:00 to 10:00 UTC: a page at 09:59 belongs to
--      the evening before), its aircraft by registration within the airline (null for one the planner doesn't know, and
--      not another airline's aircraft of the same registration), the latest capture of the day winning, and a page from
--      earlier in the day sent late changing nothing.
--   4. The airline's verdict and capture_status(): FA all good with its fleet pages counted ("fleet 2 pages, 8
--      aircraft"); FB broken, its broken fleet page named in the words; FC, with no fleet pages, has no fleet and is
--      judged on its other pages as before; its latest page counts its fleet pages.
--   5. fleet_checks(): each problem kind with its words, worst first (maintenance, crew, cabin, not in the planner, not
--      in the game), the airline's own maintenance limit, at the limit not a problem, the night it read and the counts;
--      the rule "not in the game only when every fleet page of its airline came in ok that night": FB's aircraft missing
--      from its pages isn't listed while its latest run has a broken page, and is once a later run comes in whole; an
--      earlier run's short page doesn't count against a later whole run; a retired aircraft is never missing.
--   6. As staff, fleet_checks() gives what postgres gets; signed out and an account that isn't staff are refused.

create temporary table t_fc (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_fc to authenticated, anon;
insert into public.planner_users (email) values ('fleet-capture-staff@example.com') on conflict do nothing;

-- one aircraft as the capture's readFleetPage() gives it
create function pg_temp.fc_ac(reg text, maint numeric, cond numeric, y int, c int, f int, pilots boolean default true,
                              loc_from text default 'ZF1', loc_to text default null, flight text default null)
returns jsonb language sql as $f$
  select jsonb_build_object('registration', reg, 'nickname', null, 'type', 'Airbus A321NEO Light', 'type_id', 3155, 'from', loc_from,
                            'to', loc_to, 'flight', flight, 'age_years', 0.1, 'condition_pct', cond, 'maintenance_pct', maint,
                            'y', y, 'c', c, 'f', f, 'pilots', pilots, 'owned', false, 'contract', 'active', 'game_id', 1873)
$f$;
-- a fleet page as the capture's fleetPayload() gives it: the run, which page of how many, the fleet, the airline's fleets
create function pg_temp.fc_page(run text, page int, of_ int, fleet_id int, fleet text, aircraft jsonb, error text default null)
returns jsonb language sql as $f$
  select jsonb_build_object('run', run, 'page', page, 'of', of_, 'fleet', jsonb_build_object('id', fleet_id, 'name', fleet),
                            'fleets', jsonb_build_array(jsonb_build_object('id', null, 'name', 'Default', 'aircraft', 0),
                                                        jsonb_build_object('id', 231, 'name', 'ZF1', 'aircraft', 7),
                                                        jsonb_build_object('id', 235, 'name', 'ZF2', 'aircraft', 2)))
         || case when error is null then jsonb_build_object('aircraft', aircraft) else jsonb_build_object('error', error) end
$f$;

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare c record; bad text; f text := 'public.fleet_checks(bigint, timestamptz)'; g text;
begin
  assert (select relrowsecurity from pg_class where oid = 'public.game_fleet'::regclass), 'game_fleet has no RLS';
  assert (select count(*) from pg_policies where schemaname = 'public' and tablename = 'game_fleet') = 1
     and exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'game_fleet' and policyname = 'staff read'
                    and cmd = 'SELECT' and roles = '{authenticated}' and qual like '%is_planner_user%'),
    'game_fleet should have exactly one rule: staff read (select for authenticated, is_planner_user())';
  assert not has_table_privilege('anon', 'public.game_fleet', 'select, insert, update, delete, truncate, references, trigger'),
    'signed out holds something on game_fleet';
  assert has_table_privilege('authenticated', 'public.game_fleet', 'select')
     and not has_table_privilege('authenticated', 'public.game_fleet', 'insert, update, delete, truncate'),
    'signed in should only read game_fleet';
  assert length(coalesce(obj_description('public.game_fleet'::regclass, 'pg_class'), '')) > 200, 'game_fleet has no description';
  select string_agg(a.attname, ', ') into bad from pg_attribute a
   where a.attrelid = 'public.game_fleet'::regclass and a.attnum > 0 and not a.attisdropped
     and coalesce(col_description(a.attrelid, a.attnum), '') = '';
  assert bad is null, 'game_fleet columns without a description: ' || bad;
  select string_agg(x.conname, ', ') into bad from pg_constraint x
   where x.conrelid = 'public.game_fleet'::regclass and x.contype = 'f'
     and not exists (select 1 from pg_index i where i.indrelid = x.conrelid and i.indkey[0] = any (x.conkey));
  assert bad is null, 'game_fleet foreign keys without an index: ' || bad;
  assert exists (select 1 from pg_constraint x where x.conrelid = 'public.game_fleet'::regclass and x.contype = 'u'
                    and pg_get_constraintdef(x.oid) = 'UNIQUE (airline_id, capture_day, registration)'),
    'game_fleet isn''t one row per aircraft per capture day';
  assert not exists (select 1 from information_schema.triggers t where t.event_object_schema = 'public' and t.event_object_table = 'game_fleet'
                       and t.action_statement like '%log_change%'), 'game_fleet is in the change log';

  assert (select p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=""', 'statement_timeout=30s'] from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, run as owner with an empty search path and its own 30 s limit';
  assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 400, f || ' has no description';
  foreach g in array array['private.fig_fleet_checks(bigint, timestamptz)', 'private.capture_fleet(bigint)'] loop
    assert not has_function_privilege('authenticated', g, 'execute') and not has_function_privilege('anon', g, 'execute'), g || ' can be called from outside';
    assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 60, g || ' has no description';
  end loop;
  assert obj_description('public.capture_ingest(text, text, text, text, jsonb)'::regprocedure, 'pg_proc') like '%fleet%'
     and col_description('public.game_capture_raw'::regclass, (select attnum from pg_attribute where attrelid = 'public.game_capture_raw'::regclass and attname = 'kind')) like '%fleet%',
    'capture_ingest() and game_capture_raw.kind don''t mention the fleet page';
  raise notice 'game_fleet: RLS with one staff read rule, signed out nothing, signed in read only, described with every column, foreign keys indexed, one row per aircraft per capture day, not in the change log; fleet_checks() signed in only, stable, as owner, 30 s, described; its builder and capture_fleet() internal';
end
$test$;

-- ---------------------------------------------------------------- 2. a world of its own; the page kind and its check
do $setup$
declare w bigint; g bigint; gr bigint; fa bigint; fb bigint; fc bigint; rv bigint; ty bigint; c1 bigint; i int;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'fleet capture test', true);
  insert into public.airports (code, utc_offset) values ('ZF1', 0.00), ('ZF2', 0.00), ('ZF3', 0.00) on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('fleet capture test', 'fleet-capture.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s
    join public.worlds x on x.id = s.world_id and x.is_default where s.airline_id is null;
  update public.settings set value = '100'::jsonb where world_id = w and airline_id is null and key = 'maintenance_min_pct';
  insert into public.settings (world_id, airline_id, key, value) values (w, null, 'maintenance_min_pct', '100'::jsonb) on conflict do nothing;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.groups (world_id, name, kind) values (w, 'rivals', 'rival') returning id into gr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990701, 'Fleet A', 'Fleet A', 'FA', 'ZF1', true, 1) returning id into fa;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990702, 'Fleet B', 'Fleet B', 'FB', 'ZF2', true, 2) returning id into fb;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990703, 'Fleet C', 'Fleet C', 'FC', 'ZF3', true, 3) returning id into fc;
  insert into public.airlines (world_id, group_id, game_id, game_name, active) values (w, gr, 990709, 'Fleet Rival', true) returning id into rv;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  values (w, fb, 'maintenance_min_pct', '105'::jsonb, '%', 'Fleet B''s own limit, for the test');
  insert into public.aircraft_types (world_id, name) values (w, 'FLEET TEST TYPE') returning id into ty;
  insert into public.cabin_configs (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats)
  values (w, 'FT-166', ty, 'Standard', 166, 16, 150) returning id into c1;
  -- FA: 001 at the limit, 002 under it, 003 without pilots, 004 another layout, 005 no cabin in the planner, 006 not on
  -- the game's pages, 007 retired and not on them either; FA-099 on the game's pages only
  for i in 1 .. 7 loop
    insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code)
    values (w, fa, 'FA-00' || i, ty, case when i = 5 then null else c1 end, case when i = 7 then 'retired' else 'active' end,
            case when i = 6 then 'ZF2' else 'ZF1' end);
  end loop;
  -- FB: 001 under its own 105, 002 not on its pages; FB-777 an aircraft of FB whose registration FA's page also shows
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, status, base_code)
  values (w, fb, 'FB-001', ty, c1, 'active', 'ZF2'), (w, fb, 'FB-002', ty, c1, 'active', 'ZF2'), (w, fb, 'FB-777', ty, c1, 'active', 'ZF2');
  insert into public.capture_keys (label, key_hash, world_id)
  values ('fleet capture test', extensions.crypt('fleet-capture-test-key', extensions.gen_salt('bf')), w);
  insert into t_fc values ('w', to_jsonb(w)), ('fa', to_jsonb(fa)), ('fb', to_jsonb(fb)), ('fc', to_jsonb(fc)), ('rv', to_jsonb(rv));
end
$setup$;

-- signed out, as the userscript sends a page
set local role anon;
do $test$
declare r jsonb; b jsonb;
begin
  r := public.capture_ingest('fleet-capture-test-key', '990703', 'fleet', '/app/fleets/231',
         pg_temp.fc_page('2030-03-06T19:00:00Z', 1, 1, 231, 'ZF1',
           jsonb_build_array(pg_temp.fc_ac('FC-001', 120, 95, 150, 16, 0), pg_temp.fc_ac('FC-002', 130, 96, 150, 16, 0), pg_temp.fc_ac('FC-003', 140, 97, 150, 16, 0))));
  b := public.capture_ingest('fleet-capture-test-key', '990703', 'fleets', '/app/fleets/231', '[]');
  insert into t_fc values ('ingest', r), ('bad kind', b);
end
$test$;
reset role;

do $test$
declare r jsonb := (select v from t_fc where k = 'ingest'); fc bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fc');
begin
  assert (r ->> 'ok')::boolean and (r ->> 'rows')::int = 3 and r ->> 'kind' = 'fleet', 'capture_ingest() didn''t take a fleet page: ' || r::text;
  assert r #>> '{verdict,verdict}' = 'ok' and r #>> '{verdict,note}' = 'fleet ZF1 3 aircraft' and (r #>> '{verdict,listed}')::int = 7
     and (r #>> '{verdict,page}')::int = 1 and (r #>> '{verdict,of}')::int = 1,
    'the fleet page''s verdict isn''t ok, "fleet ZF1 3 aircraft", with the fleet list''s count: ' || (r -> 'verdict')::text;
  assert (select v from t_fc where k = 'bad kind') = '{"ok": false, "error": "bad kind"}'::jsonb, 'a bad kind wasn''t refused';
  assert (select count(*) from public.game_fleet f where f.airline_id = fc) = 3, 'the page''s three aircraft aren''t in game_fleet';
  assert (select count(*) from public.game_capture_raw x where x.airline_id = fc and x.kind = 'fleet') = 1, 'the raw page wasn''t kept';
  raise notice 'through capture_ingest(), signed out with the key: a fleet page taken, read (3 aircraft) and judged ok, "fleet ZF1 3 aircraft", with what the fleet list said; a bad kind refused';
end
$test$;

-- the night of 6 March 2030, through the capture's own store at chosen moments
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fc where k = 'w'); fa bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fa');
  fb bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fb'); r jsonb; n_before int; e text;
  t1 timestamptz := '2030-03-06 19:00+00'; t2 timestamptz := '2030-03-06 21:00+00';
begin
  -- the evening before (5 March): FA-002 was fine then
  r := private.capture_store(w, '990701', 'fleet', '/app/fleets/231',
         pg_temp.fc_page('2030-03-05T19:00:00Z', 1, 1, 231, 'ZF1', jsonb_build_array(pg_temp.fc_ac('FA-002', 104.0, 90, 150, 16, 0))), '2030-03-05 19:00+00');
  -- 09:59 UTC on 6 March still belongs to the 5 March evening
  r := private.capture_store(w, '990701', 'fleet', '/app/fleets/231',
         pg_temp.fc_page('2030-03-06T09:59:00Z', 1, 1, 231, 'ZF1', jsonb_build_array(pg_temp.fc_ac('FA-002', 101.0, 88, 150, 16, 0))), '2030-03-06 09:59+00');
  -- FA's first run on 6 March: its ZF2 page came in short (no aircraft rows)
  r := private.capture_store(w, '990701', 'fleet', '/app/fleets/235', pg_temp.fc_page('2030-03-06T18:00:00Z', 2, 2, 235, 'ZF2', '[]'), '2030-03-06 18:00+00');
  assert r #>> '{verdict,verdict}' = 'short' and r #>> '{verdict,note}' = 'fleet ZF2: no aircraft rows', 'a fleet page with no aircraft rows isn''t short: ' || (r -> 'verdict')::text;
  -- and FA's whole second run: ZF1 (seven aircraft) and ZF2 (two)
  r := private.capture_store(w, '990701', 'fleet', '/app/fleets/231', pg_temp.fc_page('2030-03-06T19:00:00Z', 1, 2, 231, 'ZF1', jsonb_build_array(
         pg_temp.fc_ac('FA-001', 100.0, 91, 150, 16, 0, true, 'ZF1', 'ZF2', 'FA 1001'),
         pg_temp.fc_ac('FA-002', 80.0, 85, 150, 16, 0),
         pg_temp.fc_ac('FA-003', 120.0, 95, 150, 16, 0, false),
         pg_temp.fc_ac('FA-004', 130.0, 96, 180, 15, 0),
         pg_temp.fc_ac('FA-005', 140.0, 97, 150, 16, 0),
         pg_temp.fc_ac('fa-099', 150.0, 98, 150, 16, 0),
         pg_temp.fc_ac('FB-777', 150.0, 98, 150, 16, 0))), t1);
  assert r #>> '{verdict,verdict}' = 'ok' and r #>> '{verdict,note}' = 'fleet ZF1 7 aircraft', 'FA''s ZF1 page isn''t ok: ' || (r -> 'verdict')::text;
  r := private.capture_store(w, '990701', 'fleet', '/app/fleets/235', pg_temp.fc_page('2030-03-06T19:00:00Z', 2, 2, 235, 'ZF2', jsonb_build_array(
         pg_temp.fc_ac('FA-002', 0.0, 83, 150, 16, 0, true, 'ZF2'))), t1 + interval '1 minute');
  assert r #>> '{verdict,verdict}' = 'ok', 'FA''s ZF2 page isn''t ok: ' || (r -> 'verdict')::text;
  -- FB's run: its ZF2 page read, its ZF1 page sent with the error the capture met
  r := private.capture_store(w, '990702', 'fleet', '/app/fleets/235', pg_temp.fc_page('2030-03-06T19:05:00Z', 1, 2, 235, 'ZF2', jsonb_build_array(
         pg_temp.fc_ac('FB-001', 103.0, 92, 150, 16, 0, true, 'ZF2'), pg_temp.fc_ac('FB-777', 120.0, 93, 150, 16, 0, true, 'ZF2'))), t1 + interval '5 minutes');
  r := private.capture_store(w, '990702', 'fleet', '/app/fleets/231', pg_temp.fc_page('2030-03-06T19:05:00Z', 2, 2, 231, 'ZF1', null, 'HTTP 502'), t1 + interval '6 minutes');
  assert not (r ->> 'ok')::boolean and r #>> '{verdict,verdict}' = 'broken' and r #>> '{verdict,note}' = 'fleet ZF1 didn''t read (parse: HTTP 502)',
    'a fleet page sent with its error isn''t broken: ' || r::text;
  -- pages that don't read write nothing: not a fleet page, and a row without its registration
  select count(*) into n_before from public.game_fleet;
  r := private.capture_store(w, '990702', 'fleet', '/app/fleets/231', '[["N001AW", "x"]]', t1 + interval '7 minutes');
  assert r #>> '{verdict,verdict}' = 'broken' and r #>> '{verdict,note}' like 'fleet list didn''t read%', 'a page that isn''t a fleet page isn''t broken: ' || (r -> 'verdict')::text;
  r := private.capture_store(w, '990702', 'fleet', '/app/fleets/239', pg_temp.fc_page('x', 1, 1, 239, 'ZF9',
         jsonb_build_array(pg_temp.fc_ac('FB-500', 120, 90, 1, 1, 0), pg_temp.fc_ac('', 120, 90, 1, 1, 0))), t1 + interval '8 minutes');
  assert r #>> '{verdict,verdict}' = 'broken' and r #>> '{verdict,note}' like 'fleet ZF9 didn''t read (parse: an aircraft row without its registration%',
    'a fleet page with a row without its registration isn''t broken: ' || (r -> 'verdict')::text;
  assert (select count(*) from public.game_fleet) = n_before, 'a page that didn''t read wrote rows';
  -- those two were tries of the test, not the capture: taken out again, so FB's evening is the run above
  delete from public.game_capture_raw x where x.airline_id = fb and x.captured_at in (t1 + interval '7 minutes', t1 + interval '8 minutes');
  -- fleet pages take no part in the day's completeness
  assert not private.capture_day_complete(w, date '2030-03-06'), 'fleet pages alone completed the day''s capture';
  -- and a page from earlier in the day sent late changes nothing (FA-002's 80.0% from 19:00 against its 0.0% at 19:01)
  r := private.capture_store(w, '990701', 'fleet', '/app/fleets/231', pg_temp.fc_page('2030-03-06T17:00:00Z', 1, 1, 231, 'ZF1',
         jsonb_build_array(pg_temp.fc_ac('FA-002', 99.0, 84, 150, 16, 0))), '2030-03-06 17:00+00');
  -- that late page is FA's latest raw page by id but not by time: taken out, so the runs stay the capture's
  delete from public.game_capture_raw x where x.airline_id = fa and x.captured_at = '2030-03-06 17:00+00';
  insert into t_fc values ('t1', to_jsonb(t1)), ('t2', to_jsonb(t2));
  raise notice 'the page check: no aircraft rows short ("fleet ZF2: no aircraft rows"); sent with its error, not a fleet page, or a row without its registration broken, writing nothing; fleet pages don''t complete the day';
end
$test$;

-- ---------------------------------------------------------------- 3. the matching and the night
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fc where k = 'w'); fa bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fa');
  fb bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fb'); x record;
begin
  assert (select count(*) from public.game_fleet f where f.airline_id = fa and f.capture_day = date '2030-03-06') = 7,
    'FA should have 7 aircraft on 6 March (FA-002 read on ZF1, then on ZF2), has ' || (select count(*) from public.game_fleet f where f.airline_id = fa and f.capture_day = date '2030-03-06');
  select * into x from public.game_fleet f where f.airline_id = fa and f.registration = 'FA-002' and f.capture_day = date '2030-03-05';
  assert x.maintenance_pct = 101.0 and x.condition_pct = 88, 'the 09:59 UTC page isn''t the 5 March evening''s latest: ' || coalesce(x.maintenance_pct::text, 'none');
  select * into x from public.game_fleet f where f.airline_id = fa and f.registration = 'FA-002' and f.capture_day = date '2030-03-06';
  assert x.maintenance_pct = 0.0 and x.condition_pct = 83 and x.fleet_name = 'ZF2' and x.fleet_game_id = 235 and x.captured_at = '2030-03-06 19:01+00',
    'FA-002''s 6 March row isn''t the latest capture of the day (0.0% on ZF2 at 19:01): ' || row_to_json(x)::text;
  assert x.aircraft_id = (select a.id from public.aircraft a where a.airline_id = fa and a.registration = 'FA-002'), 'FA-002 isn''t matched to its aircraft';
  select * into x from public.game_fleet f where f.airline_id = fa and f.registration = 'FA-001' and f.capture_day = date '2030-03-06';
  assert x.location_from = 'ZF1' and x.location_to = 'ZF2' and x.flight = 'FA 1001' and x.seats_y = 150 and x.seats_c = 16 and x.seats_f = 0
     and x.pilots and not x.owned and x.contract_status = 'active' and x.type_name = 'Airbus A321NEO Light' and x.age_years = 0.1 and x.nickname is null,
    'FA-001''s row doesn''t hold what the page said: ' || row_to_json(x)::text;
  assert (select f.aircraft_id is null from public.game_fleet f where f.airline_id = fa and f.registration = 'FA-099' and f.capture_day = date '2030-03-06'),
    'FA-099 (written fa-099 on the page) isn''t in capitals or is matched to an aircraft';
  assert (select f.aircraft_id is null from public.game_fleet f where f.airline_id = fa and f.registration = 'FB-777'),
    'FA''s FB-777 was matched to Fleet B''s aircraft';
  assert (select f.aircraft_id = (select a.id from public.aircraft a where a.airline_id = fb and a.registration = 'FB-777')
            from public.game_fleet f where f.airline_id = fb and f.registration = 'FB-777'), 'FB''s FB-777 isn''t matched to its aircraft';
  raise notice 'game_fleet: one row per aircraft per capture day (09:59 UTC with the evening before), matched by registration within the airline (capitals; another airline''s aircraft never), the latest capture winning, a late earlier page changing nothing';
end
$test$;

-- ---------------------------------------------------------------- 4. the airline's verdict and capture_status()
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fc where k = 'w'); fa bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fa');
  fb bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fb'); fc bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fc');
  t2 timestamptz := (select (v #>> '{}')::timestamptz from t_fc where k = 't2'); v jsonb; c jsonb; x jsonb; k text;
begin
  -- the other five pages of each airline, all good, before the fleets (FC's evening has those only)
  for x in select jsonb_build_object('al', a.game_id, 'id', a.id) from public.airlines a where a.id in (fa, fb, fc) loop
    foreach k in array array['events', 'statement', 'pnl', 'balance', 'loads'] loop
      insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at, verdict, verdict_note)
      values (w, (x ->> 'id')::bigint, 'x', k, '/test', '[]', '2030-03-06 18:30+00', 'ok', k || ' ok');
    end loop;
  end loop;
  v := private.capture_airline_verdict(fa, t2);
  assert v ->> 'verdict' = 'ok' and v ->> 'words' = 'all good' and v #>> '{pages,fleet,verdict}' = 'ok'
     and v #>> '{pages,fleet,note}' = 'fleet 2 pages, 8 aircraft' and (v #>> '{pages,fleet,pages}')::int = 2 and (v #>> '{pages,fleet,aircraft}')::int = 8
     and v ->> 'at' = '2030-03-06T19:01:00.000Z',
    'FA''s verdict with its fleet pages isn''t all good, "fleet 2 pages, 8 aircraft", at its last fleet page: ' || v::text;
  v := private.capture_airline_verdict(fb, t2);
  assert v ->> 'verdict' = 'broken' and v ->> 'words' = 'broken: fleet ZF1 didn''t read (parse: HTTP 502)' and v #>> '{pages,fleet,verdict}' = 'broken'
     and (v #>> '{pages,fleet,ok}')::int = 1,
    'FB''s broken fleet page doesn''t make its verdict broken, named: ' || v::text;
  v := private.capture_airline_verdict(fc, '2030-03-06 18:31+00');
  assert v ->> 'verdict' = 'ok' and v ->> 'words' = 'all good' and not (v -> 'pages') ? 'fleet'
     and v ->> 'at' = '2030-03-06T18:30:00.000Z', 'an evening without fleet pages isn''t judged as before: ' || v::text;
  c := private.fig_capture_status(w, t2);
  select e into x from jsonb_array_elements(c -> 'airlines') e where (e ->> 'airline_id')::bigint = fa;
  assert x ->> 'last_at' = '2030-03-06T19:01:00.000Z' and x #>> '{fleet,note}' = 'fleet 2 pages, 8 aircraft' and x ->> 'verdict' = 'ok'
     and x -> 'missing' = '[]'::jsonb and x ->> 'status' = 'complete',
    'capture_status() doesn''t give FA''s fleet pages beside it, or counts them as a kind: ' || x::text;
  select e into x from jsonb_array_elements(c -> 'airlines') e where (e ->> 'airline_id')::bigint = fb;
  assert x ->> 'verdict' = 'broken' and x ->> 'verdict_words' like '%fleet ZF1 didn''t read%' and x #>> '{fleet,verdict}' = 'broken',
    'capture_status() doesn''t give FB''s broken fleet page: ' || x::text;
  -- FC's own fleet page (through capture_ingest() above) was at the transaction's start, before this evening's moments:
  -- at 18:31 its day has none
  select e into x from jsonb_array_elements(private.fig_capture_status(w, '2030-03-06 18:31+00') -> 'airlines') e where (e ->> 'airline_id')::bigint = fc;
  assert not x ? 'fleet', 'capture_status() gives a fleet to an airline whose day has no fleet pages: ' || x::text;
  raise notice 'the airline''s verdict: FA all good with "fleet 2 pages, 8 aircraft"; FB broken, "fleet ZF1 didn''t read (parse: HTTP 502)"; FC without fleet pages judged as before, no fleet; capture_status() gives the fleet beside each airline that has some, its latest page counting them, no kind missing';
end
$test$;

-- ---------------------------------------------------------------- 5. fleet_checks()
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fc where k = 'w'); fa bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fa');
  fb bigint := (select (v #>> '{}')::bigint from t_fc where k = 'fb'); t2 timestamptz := (select (v #>> '{}')::timestamptz from t_fc where k = 't2');
  d jsonb; got text; want text; x jsonb; r jsonb;
begin
  d := private.fig_fleet_checks(w, t2);
  assert d ->> 'night' = '2030-03-06', 'the night isn''t 6 March: ' || coalesce(d ->> 'night', 'none');
  select string_agg((p ->> 'kind') || ' ' || (p ->> 'registration'), ', ' order by o) into got from jsonb_array_elements(d -> 'problems') with ordinality e(p, o);
  want := 'maintenance FA-002, maintenance FB-001, crew FA-003, cabin FA-004, cabin FA-005, not_in_planner FA-099, not_in_planner FB-777, not_in_game FA-006';
  assert got = want, format('the problems should be %s, worst first; got %s', want, coalesce(got, 'none'));
  select string_agg(p ->> 'words', ' | ' order by o) into got from jsonb_array_elements(d -> 'problems') with ordinality e(p, o);
  want := 'FA-002 (ZF1): maintenance 0.0%, condition 83% | FB-001 (ZF2): maintenance 103.0%, condition 92% | FA-003 (ZF1): no pilots'
       || ' | FA-004 (ZF1): seats 180/15/0 in the game, 150/16/0 in the planner (FT-166) | FA-005 (ZF1): no cabin in the planner (150/16/0 in the game)'
       || ' | FA-099: in the game (ZF1 fleet), not in the planner | FB-777: in the game (ZF1 fleet), not in the planner'
       || ' | FA-006 (ZF2): in the planner, not on the game''s fleet pages';
  assert got = want, format('the words should be %s; got %s', want, got);
  -- (replace and age since 22 Oct, migration 20261022090000: none here, every aircraft 0.1 years and none with a delivery date)
  assert d -> 'counts' = '{"maintenance": 2, "crew": 1, "cabin": 2, "not_in_planner": 2, "not_in_game": 1, "replace": 0, "age": 0, "problems": 8}'::jsonb,
    'the counts: ' || (d -> 'counts')::text;
  select e into x from jsonb_array_elements(d -> 'problems') e where e ->> 'registration' = 'FA-002';
  assert x ->> 'code' = 'FA' and x ->> 'base' = 'ZF1' and (x ->> 'aircraft_id')::bigint = (select a.id from public.aircraft a where a.airline_id = fa and a.registration = 'FA-002'),
    'a problem doesn''t carry its airline, base and aircraft: ' || x::text;
  select e into x from jsonb_array_elements(d -> 'airlines') e where (e ->> 'airline_id')::bigint = fa;
  assert jsonb_array_length(x -> 'aircraft') = 7 and x -> 'pages' = '{"read": 2, "ok": 2, "expected": 2, "all_ok": true}'::jsonb
     and (x ->> 'maintenance_min_pct')::numeric = 100,
    'FA''s fleet that night: ' || (x - 'aircraft')::text;
  assert (select a -> 'problems' from jsonb_array_elements(x -> 'aircraft') a where a ->> 'registration' = 'FA-002') = '["maintenance"]'::jsonb
     and (select a -> 'problems' from jsonb_array_elements(x -> 'aircraft') a where a ->> 'registration' = 'FA-001') = '[]'::jsonb,
    'the fleet''s rows don''t mark their problems';
  select e into x from jsonb_array_elements(d -> 'airlines') e where (e ->> 'airline_id')::bigint = fb;
  assert x -> 'pages' = '{"read": 2, "ok": 1, "expected": 2, "all_ok": false}'::jsonb and (x ->> 'maintenance_min_pct')::numeric = 105,
    'FB''s pages that night: ' || (x - 'aircraft')::text;
  -- FB's next run comes in whole: FB-002 is missing from its pages, and now that is listed
  r := private.capture_store(w, '990702', 'fleet', '/app/fleets/235', pg_temp.fc_page('2030-03-06T21:30:00Z', 1, 2, 235, 'ZF2', jsonb_build_array(
         pg_temp.fc_ac('FB-001', 106.0, 92, 150, 16, 0, true, 'ZF2'), pg_temp.fc_ac('FB-777', 120.0, 93, 150, 16, 0, true, 'ZF2'))), t2 + interval '30 minutes');
  r := private.capture_store(w, '990702', 'fleet', '/app/fleets/231', pg_temp.fc_page('2030-03-06T21:30:00Z', 2, 2, 231, 'ZF1', '[]'::jsonb || pg_temp.fc_ac('FB-888', 120.0, 93, 150, 16, 0)),
         t2 + interval '31 minutes');
  d := private.fig_fleet_checks(w, t2 + interval '1 hour');
  select string_agg((p ->> 'kind') || ' ' || (p ->> 'registration'), ', ' order by o) into got from jsonb_array_elements(d -> 'problems') with ordinality e(p, o);
  want := 'maintenance FA-002, crew FA-003, cabin FA-004, cabin FA-005, not_in_planner FA-099, not_in_planner FB-777, not_in_planner FB-888, not_in_game FA-006, not_in_game FB-002';
  assert got = want, format('after FB''s whole run the problems should be %s; got %s', want, coalesce(got, 'none'));
  insert into t_fc values ('doc', private.fig_fleet_checks(w, t2 + interval '1 hour'));
  raise notice 'fleet_checks(): maintenance under the limit (an airline''s own 105; 100.0%% at 100 is fine), no pilots, another layout or no cabin, in the game only, in the planner only, worst first with their words; not in the game only once every page of the airline''s latest run came in ok (an earlier short run not counting); a retired aircraft never missing; the night and the counts';
end
$test$;

-- ---------------------------------------------------------------- 6. who may read it
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "fleet-capture-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fc where k = 'w'); t2 timestamptz := (select (v #>> '{}')::timestamptz from t_fc where k = 't2');
begin
  insert into t_fc values ('staff', public.fleet_checks(w, t2 + interval '1 hour'));
  insert into t_fc values ('staff rows', to_jsonb((select count(*) from public.game_fleet f where f.world_id = w)));
end
$test$;
reset role;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_fc where k = 'w');
begin
  assert (select v from t_fc where k = 'staff') = (select v from t_fc where k = 'doc'), 'staff don''t get what postgres gets from fleet_checks()';
  assert (select (v #>> '{}')::int from t_fc where k = 'staff rows') = (select count(*) from public.game_fleet f where f.world_id = w), 'staff can''t read game_fleet';
end
$test$;

set local role anon;
do $test$
declare n int := 0;
begin
  begin perform public.fleet_checks(); exception when insufficient_privilege then n := n + 1; end;
  begin perform 1 from public.game_fleet; exception when insufficient_privilege then n := n + 1; end;
  assert n = 2, 'signed out, fleet_checks() or game_fleet wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "fleet-capture-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare n int := 0;
begin
  begin perform public.fleet_checks(); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused fleet_checks()';
  assert (select count(*) from public.game_fleet) = 0, 'an account that isn''t staff reads game_fleet''s rows';
end
$test$;
reset role;

do $$ begin raise notice 'as staff fleet_checks() gives what postgres gets and game_fleet reads; signed out and an account that isn''t staff refused'; end $$;
do $$ begin raise notice 'fleet capture: all checks passed'; end $$;

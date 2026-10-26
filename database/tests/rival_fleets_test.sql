-- Rivals' fleets in the world scan (spec docs/specs/2026-10-23-rival-fleets.md §3, §4, §6; migration
-- 20261023120000_rival_fleets.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes, counts
-- and words of the hand-made world only). Everything is made in a world of its own, so nothing on the copy is touched
-- or counted; the copy's own numbers are printed at the end (counts only).
--   1. The tables (RLS on, no rule, no access for anon or authenticated, described, every column), the settings
--      rival_orders_flag_pct 25 and rival_orders_flag_min 5 in every world (described, since 23 Oct, with a reason), the
--      new internal functions (closed, run as the caller, empty search path, described), and capture_scan() and
--      ingest_snapshot() taking kind fleet.
--   2. A world of its own (our two airlines F1 at XA1 and F2 at XB1) with its own key: a scan started through
--      capture_scan(); Icelandair-like FR1 (game 990801: Capture all airlines' parse of the saved page, 8 types, 99
--      aircraft, 44 on order) sent as kind fleet: stored by type and its totals and profile; sent again, replaced, not
--      added; a page that didn't read (error) kept as read_ok false and never replacing one that read; a payload without
--      enterprise_id refused, writing nothing; an airline only the overview page sees placed in the key's world. Then the
--      airlines and the finish: the scan finishes with a failed fleet page in it. Through ingest_snapshot() (the default
--      world, as gscan.py sends it) the same page gives the same rows.
--   3. competition() on two finished scans a week apart (s1, s2): each competitor and rival profile has its fleet, the
--      week's change (+6 on order), null when the week-before scan didn't read it; order_flags: FR1 (44 of 99, 44.4%,
--      orders), FR2 (on order, no flights: starting), not FR3 (20%: 10 of 50), not FR4 (4 on order of 8, 50%), not our
--      own F2 (30 of 40), not the freighter FX5 (10 of 20); the same list for both our airlines, each marked whether it
--      meets the airline (FR1 on F1's pair; FR2 at none; F2's answer FR1 not meeting); the threshold settings move it.
--      Nothing else in the document moves with the fleets: the openings, the threats and the markets are as without them.
--   4. system_status()'s scan gives fleet_pages and fleet_failed.
--   On the copy: the latest finished scan's fleet pages (read, failed) and the flags in the first airline's answer.

create temporary table t_rf (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_rf to anon, authenticated;
insert into public.planner_users (email) values ('rival-fleets-staff@example.com') on conflict do nothing;

-- Icelandair's overview page as Capture all airlines 1.8 reads it (tests/capture_scan_test.mjs checks the parse of
-- tests/fixtures/enterprise_overview_101_2026-10-23.html gives exactly these rows, and gscan.py's the same)
insert into t_rf values ('fr1', jsonb_build_object('enterprise_id', 990801, 'name', 'Fleet Rival One',
  'types', '[{"type": "Airbus A321LR", "type_id": 3167, "owned": 0, "leased": 21, "overall": 21, "leased_out": 0, "on_offer": 0, "on_order": 10, "avg_age_years": 0.1},
             {"type": "Airbus A321XLR", "type_id": 3171, "owned": 0, "leased": 23, "overall": 23, "leased_out": 0, "on_offer": 0, "on_order": 10, "avg_age_years": 0.2},
             {"type": "Boeing 737-10 HGW", "type_id": 12593, "owned": 0, "leased": 9, "overall": 9, "leased_out": 0, "on_offer": 0, "on_order": 9, "avg_age_years": 0},
             {"type": "Boeing 737-8 HGW", "type_id": 12316, "owned": 0, "leased": 16, "overall": 16, "leased_out": 0, "on_offer": 0, "on_order": 10, "avg_age_years": 0.2},
             {"type": "Boeing 737-9 HGW", "type_id": 12591, "owned": 0, "leased": 23, "overall": 23, "leased_out": 0, "on_offer": 0, "on_order": 5, "avg_age_years": 0.1},
             {"type": "Boeing 757-200", "type_id": 14300, "owned": 0, "leased": 4, "overall": 4, "leased_out": 0, "on_offer": 0, "on_order": 0, "avg_age_years": 24.1},
             {"type": "Boeing 767-300ER", "type_id": 15200, "owned": 0, "leased": 1, "overall": 1, "leased_out": 0, "on_offer": 0, "on_order": 0, "avg_age_years": 13},
             {"type": "DHC Dash 8-400 BASIC", "type_id": 16710, "owned": 0, "leased": 2, "overall": 2, "leased_out": 0, "on_offer": 0, "on_order": 0, "avg_age_years": 0.1}]'::jsonb,
  'totals', '{"owned": 0, "leased": 99, "overall": 99, "leased_out": 0, "on_offer": 0, "on_order": 44, "avg_age_years": 2.1}'::jsonb,
  'profile', '{"code": "FI", "alliance": "oneworld Alliance", "alliance_id": 88, "headquarters": "KEF", "parent_id": 100, "parent": "Icelandair Group",
               "founded": "2026-08-18", "passengers": 1320382, "stations": 55, "fleet_size": 99, "staff": 3305}'::jsonb));

-- an overview page made from its totals: one type, the totals the same
create function pg_temp.rf_page(eid int, name text, overall int, on_order int, ty text default 'Airbus A320neo') returns jsonb language sql immutable as $f$
  select jsonb_build_object('enterprise_id', eid, 'name', name,
    'types', jsonb_build_array(jsonb_build_object('type', ty, 'type_id', 1, 'owned', 0, 'leased', overall, 'overall', overall, 'leased_out', 0,
                                                  'on_offer', 0, 'on_order', on_order, 'avg_age_years', 1.5)),
    'totals', jsonb_build_object('owned', 0, 'leased', overall, 'overall', overall, 'leased_out', 0, 'on_offer', 0, 'on_order', on_order, 'avg_age_years', 1.5),
    'profile', jsonb_build_object('code', null, 'stations', 3, 'fleet_size', overall, 'staff', 10, 'passengers', 1000))
$f$;
-- a flight in a scan's schedule: [code, number, from, to, weekdays, departure, arrival, type, operator]
create function pg_temp.rf_fl(code text, no int, o text, d text, days text, ty text default '320') returns jsonb language sql immutable as $f$
  select jsonb_build_array(code, no::text, o, d, days, '08:00', '10:00', ty, '')
$f$;

-- ---------------------------------------------------------------- 1. the tables, the settings, who may call what
do $test$
declare t text; c record; n_worlds int := (select count(*) from public.worlds); g text; bad text;
begin
  foreach t in array array['scan_airline_fleet', 'scan_airline_profile'] loop
    assert (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), t || ' has no RLS';
    assert not exists (select 1 from pg_policies where schemaname = 'public' and tablename = t), t || ' has an access rule: it''s read through functions only';
    select string_agg(r || ' ' || p, ', ') into bad from unnest(array['anon', 'authenticated']) r
     cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p
     where has_table_privilege(r, 'public.' || t, p);
    assert bad is null, t || ' is open to: ' || bad;
    assert length(coalesce(obj_description(('public.' || t)::regclass, 'pg_class'), '')) > 200, t || ' has no description';
    select string_agg(a.attname, ', ') into bad from pg_attribute a
     where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped
       and a.attname not in ('scan_id', 'world_id', 'airline_id') and col_description(a.attrelid, a.attnum) is null;
    assert bad is null, t || ': columns without a description: ' || bad;
  end loop;
  assert (select array_agg(a.attname::text order by a.attnum) from pg_attribute a where a.attrelid = 'public.scan_airline_fleet'::regclass and a.attnum > 0 and not a.attisdropped)
       = array['scan_id', 'world_id', 'airline_id', 'type_name', 'game_type_id', 'owned', 'leased', 'overall', 'leased_out', 'on_offer', 'on_order', 'avg_age_years'],
    'scan_airline_fleet''s columns aren''t the spec''s';
  for c in select * from (values ('rival_orders_flag_pct', '25'::jsonb, '%'), ('rival_orders_flag_min', '5'::jsonb, 'aircraft')) v(k, v, u) loop
    assert (select count(*) from public.settings s where s.key = c.k and s.airline_id is null and s.value = c.v and s.unit = c.u
              and length(coalesce(s.description, '')) > 80 and s.since = date '2026-10-23' and s.reason is not null) = n_worlds,
      c.k || ' isn''t ' || c.v || ' in every world, described, since 23 Oct, with its reason';
  end loop;
  foreach g in array array['private.scan_fleet(bigint, bigint, bigint)', 'private.scan_order_flags(bigint, bigint, bigint, text[])'] loop
    assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute'), g || ' can be called from outside';
    assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                        where p.oid = g::regprocedure and a.grantee = 0), g || ' is open to public';
    assert (select not p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner, isn''t stable or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 200, g || ' has no description';
  end loop;
  assert position('kind fleet' in obj_description('public.ingest_snapshot(text, text, jsonb)'::regprocedure, 'pg_proc')) > 0
     and position('fleet (since 23 Oct' in obj_description('public.capture_scan(text, text, jsonb)'::regprocedure, 'pg_proc')) > 0
     and position('Fleets (since 23 Oct' in obj_description('public.competition(bigint, timestamptz, integer)'::regprocedure, 'pg_proc')) > 0
     and position('Stations (since 22 Oct' in obj_description('public.competition(bigint, timestamptz, integer)'::regprocedure, 'pg_proc')) > 0
     and position('fleet_pages' in obj_description('public.system_status(bigint, timestamptz)'::regprocedure, 'pg_proc')) > 0,
    'a description doesn''t say what changed, or lost what it said before (competition()''s stations)';
  raise notice 'scan_airline_fleet and scan_airline_profile: RLS on with no rule, closed to anon and authenticated, every column described; rival_orders_flag_pct 25 and rival_orders_flag_min 5 in each of the % world(s); scan_fleet() and scan_order_flags() internal; the descriptions say so', n_worlds;
end
$test$;

-- ---------------------------------------------------------------- 2. the world, and the pages stored
do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; f1 bigint; f2 bigint; r record; ids jsonb := '{}'::jsonb; ty bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'rival fleets test', true);
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['XA1', 'XA2', 'XB1', 'XB2', 'XC1', 'XC2', 'XC3']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('rival fleets test', 'rival-fleets.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s2.key, s2.value, s2.unit, s2.description from public.settings s2 where s2.world_id = dw and s2.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990701, 'Fleet One', 'Fleet One', 'F1', 'XA1', true, 1) returning id into f1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990702, 'Fleet Two', 'Fleet Two', 'F2', 'XB1', true, 2) returning id into f2;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, f1, 'XA1', 'hub', true, 1), (w, f2, 'XB1', 'hub', true, 1);
  insert into public.aircraft_types (world_id, name, seats_max, range_km, price, cruise_kmh, min_turn_min)
  values (w, 'RF A320', 180, 6000, 2000000, 840, 60) returning id into ty;
  insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) values (w, f1, ty), (w, f2, ty);
  -- F1 flies XA1–XA2 and has XA1–XC1 on its list (an opening); F2 flies XB1–XB2
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, source) values
    (w, f1, 'XA1', 'XA2', 800, 4, 'research'), (w, f1, 'XA1', 'XC1', 900, 4, 'research'), (w, f2, 'XB1', 'XB2', 700, 3, 'research');
  insert into public.rotations (world_id, airline_id, route_id, launched_on)
  select w, x.airline_id, x.id, date '2030-01-01' from public.routes x where x.world_id = w and x.dest_code in ('XA2', 'XB2');
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code, acquired) values
    (w, f1, 'XF-1', ty, 'active', 'XA1', 'new'), (w, f2, 'XF-2', ty, 'active', 'XB1', 'new');
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min)
  select w, ro.airline_id, ro.id, l.n, case when ro.airline_id = f1 then 100 else 200 end + l.n, case when l.n = 1 then x.hub_code else x.dest_code end,
         case when l.n = 1 then x.dest_code else x.hub_code end, ac.id, '{1,2,3,4,5,6,7}', 600 + 200 * l.n, 90
    from public.rotations ro join public.routes x on x.id = ro.route_id
    join public.aircraft ac on ac.airline_id = ro.airline_id cross join (values (1), (2)) l(n)
   where ro.world_id = w;
  insert into public.capture_keys (label, key_hash, world_id)
  values ('rival fleets test', extensions.crypt('rival-fleets-test-key', extensions.gen_salt('bf')), w);
  insert into public.ingest_secret (secret) values ('rival-fleets-test-secret');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_rf values ('w', to_jsonb(w)), ('f1', to_jsonb(f1)), ('f2', to_jsonb(f2));
end
$setup$;

-- the capture, signed out, as Capture all airlines 1.8 sends the pages
set local role anon;
do $test$
declare v_key text := 'rival-fleets-test-key'; s bigint; r jsonb; page jsonb := (select t.v from t_rf t where t.k = 'fr1');
begin
  r := public.capture_scan(v_key, 'start', '{"week": "43", "note": "rival fleets test"}');
  s := (r ->> 'snapshot_id')::bigint;
  insert into t_rf values ('cap_scan', to_jsonb(s));
  insert into t_rf values ('r_fleet', public.capture_scan(v_key, 'fleet', page || jsonb_build_object('snapshot_id', s)));
  -- sent again (a reload carries on): replaced, not added
  insert into t_rf values ('r_again', public.capture_scan(v_key, 'fleet', page || jsonb_build_object('snapshot_id', s)));
  -- a page that didn't read, for another airline, and then for FR1 (never replaces the page that read)
  insert into t_rf values ('r_err', public.capture_scan(v_key, 'fleet', jsonb_build_object('snapshot_id', s, 'enterprise_id', 990899, 'name', 'Fleet Only Seen Here', 'error', 'HTTP 500')));
  insert into t_rf values ('r_err_fr1', public.capture_scan(v_key, 'fleet', jsonb_build_object('snapshot_id', s, 'enterprise_id', 990801, 'name', 'Fleet Rival One', 'error', 'timeout')));
  -- no enterprise: refused, writing nothing
  insert into t_rf values ('r_bad', public.capture_scan(v_key, 'fleet', jsonb_build_object('snapshot_id', s, 'types', '[]'::jsonb)));
  -- then the airline itself and the finish: a failed fleet page doesn't stop it
  insert into t_rf values ('r_al', public.capture_scan(v_key, 'airline', jsonb_build_object('snapshot_id', s, 'enterprise_id', 990801, 'name', 'Fleet Rival One',
    'flights', jsonb_build_array(pg_temp.rf_fl('FR', 1, 'XA1', 'XA2', '1234567')), 'n_flights', 1, 'n_weekly', 7, 'n_airports', 2)));
  insert into t_rf values ('r_fin', public.capture_scan(v_key, 'finish', jsonb_build_object('snapshot_id', s, 'note', 'full scan: 2 enterprises, 0 airports (Capture all airlines 1.8; 0 airline pages failed, 0 airports without an id; 2 fleet pages, 1 failed)')));
end
$test$;
reset role;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rf where k = 'w'); s bigint := (select (v #>> '{}')::bigint from t_rf where k = 'cap_scan');
  fr1 bigint; got text; p record; dw bigint := (select id from public.worlds where is_default); s2 bigint; got2 text;
begin
  assert (select v from t_rf where k = 'r_fleet') = jsonb_build_object('ok', true, 'read_ok', true, 'rows', 8, 'snapshot_id', s),
    'the fleet page wasn''t stored with its 8 types: ' || (select v from t_rf where k = 'r_fleet')::text;
  select a.id into fr1 from public.airlines a where a.world_id = w and a.game_id = 990801;
  assert fr1 is not null, 'FR1 isn''t placed in the key''s world';
  select string_agg(format('%s %s/%s/%s/%s/%s/%s %s %s', f.type_name, f.owned, f.leased, f.overall, f.leased_out, f.on_offer, f.on_order, f.avg_age_years, f.game_type_id), '; ' order by f.type_name)
    into got from public.scan_airline_fleet f where f.scan_id = s and f.airline_id = fr1;
  assert got = 'Airbus A321LR 0/21/21/0/0/10 0.1 3167; Airbus A321XLR 0/23/23/0/0/10 0.2 3171; Boeing 737-10 HGW 0/9/9/0/0/9 0.0 12593; Boeing 737-8 HGW 0/16/16/0/0/10 0.2 12316; '
            || 'Boeing 737-9 HGW 0/23/23/0/0/5 0.1 12591; Boeing 757-200 0/4/4/0/0/0 24.1 14300; Boeing 767-300ER 0/1/1/0/0/0 13.0 15200; DHC Dash 8-400 BASIC 0/2/2/0/0/0 0.1 16710',
    'FR1''s types are ' || coalesce(got, 'none');
  assert (select count(*) from public.scan_airline_fleet f where f.scan_id = s and f.airline_id = fr1) = 8 and (select v ->> 'rows' from t_rf where k = 'r_again') = '8',
    'sending the page again added rows';
  select * into p from public.scan_airline_profile x where x.scan_id = s and x.airline_id = fr1;
  assert p.read_ok and p.fleet_size = 99 and p.on_order = 44 and p.avg_age_years = 2.1 and p.stations = 55 and p.staff = 3305 and p.passengers = 1320382
     and p.alliance = 'oneworld Alliance' and p.parent_game_id = 100 and p.founded = date '2026-08-18' and p.note is null and p.world_id = w,
    'FR1''s profile isn''t 99 aircraft, 44 on order, 2.1 years, 55 stations, 3,305 staff, 1,320,382 passengers, oneworld, parent 100, founded 18 Aug: ' || to_jsonb(p)::text;
  -- the failed pages: another airline's kept as such (and the airline placed), FR1's didn't replace the page it read
  assert (select v from t_rf where k = 'r_err') = jsonb_build_object('ok', true, 'read_ok', false, 'rows', 0, 'snapshot_id', s)
     and (select v from t_rf where k = 'r_err_fr1') ->> 'ok' = 'true',
    'a failed page wasn''t answered ok with read_ok false: ' || (select v from t_rf where k = 'r_err')::text;
  assert (select x.read_ok = false and x.note = 'HTTP 500' and x.fleet_size is null from public.scan_airline_profile x
            join public.airlines a on a.id = x.airline_id where x.scan_id = s and a.game_id = 990899 and a.world_id = w),
    'the failed page wasn''t kept as read_ok false with its reason, or its airline wasn''t placed in the key''s world';
  assert (select x.read_ok and x.on_order = 44 from public.scan_airline_profile x where x.scan_id = s and x.airline_id = fr1),
    'a failed read replaced the page the same scan read';
  assert (select v ->> 'ok' from t_rf where k = 'r_bad') = 'false'
     and (select count(*) from public.scan_airline_profile x where x.scan_id = s) = 2,
    'a page without enterprise_id wasn''t refused, or wrote something: ' || (select v from t_rf where k = 'r_bad')::text;
  assert (select v ->> 'ok' from t_rf where k = 'r_fin') = 'true' and (select status from public.game_scans where id = s) = 'done',
    'the scan with a failed fleet page in it didn''t finish';
  assert (select count(*) from public.change_log c where c.table_name = 'airlines' and c.actor = 'capture'
            and (c.new_values ->> 'game_id')::int in (990801, 990899)) >= 2,
    'the airlines the overview pages placed weren''t logged as the capture';

  -- the same page through ingest_snapshot() (the default world, as gscan.py sends it): the same rows
  perform set_config('equinox.actor', '', true);
  s2 := (public.ingest_snapshot('rival-fleets-test-secret', 'start', '{"week": "43", "note": "rival fleets test (gscan)"}') ->> 'snapshot_id')::bigint;
  assert (public.ingest_snapshot('rival-fleets-test-secret', 'fleet', (select v from t_rf where k = 'fr1') || jsonb_build_object('snapshot_id', s2)))
         = '{"ok": true, "read_ok": true, "rows": 8}'::jsonb, 'ingest_snapshot() kind fleet didn''t answer as private.scan_ingest() does';
  select string_agg(format('%s %s/%s/%s/%s/%s/%s %s %s', f.type_name, f.owned, f.leased, f.overall, f.leased_out, f.on_offer, f.on_order, f.avg_age_years, f.game_type_id), '; ' order by f.type_name)
    into got2 from public.scan_airline_fleet f where f.scan_id = s2;
  assert got2 = got and (select to_jsonb(x) - 'scan_id' - 'world_id' - 'airline_id' - 'read_at' from public.scan_airline_profile x where x.scan_id = s2)
                       = (select to_jsonb(x) - 'scan_id' - 'world_id' - 'airline_id' - 'read_at' from public.scan_airline_profile x where x.scan_id = s and x.airline_id = fr1)
     and (select world_id from public.scan_airline_profile where scan_id = s2) = dw,
    'ingest_snapshot() (gscan.py) didn''t store the same rows in the default world';
  raise notice 'capture_scan() kind fleet, signed out: FR1''s 8 types and its profile (99 aircraft, 44 on order, 2.1 years, 55 stations, 3,305 staff, oneworld, parent 100, founded 18 Aug) stored; sent again, replaced; a page that didn''t read kept as read_ok false with its reason, its airline placed, never replacing a read; no enterprise refused; the scan finished with a failed fleet page in it; ingest_snapshot() (gscan.py) gives the same rows in the default world';
end
$test$;

-- ---------------------------------------------------------------- 3. competition(): fleets, the week's change and the flags
-- Two finished scans a week apart. In both, FR1 flies XA1–XA2 (F1's pair, 14 a week) and XA1–XC2; FR3 flies XA2–XC3;
-- FR4 XC1–XC2; FX5 freighters only on XA1–XA2; F1 and F2 their own pairs; FR2 nothing (a schedule with no flights).
-- Fleets: s1 FR1 99/38, FR3 50/10; s2 FR1 99/44 (+6 on order), FR2 0/12 (starting), FR3 50/10 (20%), FR4 8/4 (50%, but
-- under 5), F2 40/30 (ours), FX5 20/10 (freighters only). FR2, FR4 and FX5 have no page in s1, so their change is null.
do $setup$
declare w bigint := (select (v #>> '{}')::bigint from t_rf where k = 'w'); f1 bigint := (select (v #>> '{}')::bigint from t_rf where k = 'f1');
  f2 bigint := (select (v #>> '{}')::bigint from t_rf where k = 'f2'); x record; s bigint; a record; ids jsonb := '{}'::jsonb; sc jsonb := '{}'::jsonb;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'rival fleets test', true);
  for a in select * from (values ('fr1', 990801, 'Fleet Rival One'), ('fr2', 990802, 'Fleet Rival Two'), ('fr3', 990803, 'Fleet Rival Three'),
                                 ('fr4', 990804, 'Fleet Rival Four'), ('fx5', 990805, 'Fleet Cargo Five')) v(k, gid, name) loop
    ids := ids || jsonb_build_object(a.k, private.scan_airline(w, a.gid, a.name));
  end loop;
  for x in select * from (values ('s1', timestamptz '2030-03-01 08:00:00+00', 38), ('s2', timestamptz '2030-03-08 08:00:00+00', 44)) v(k, at, fr1_order) loop
    insert into public.game_scans (world_id, taken_at, status) values (w, x.at, 'done') returning id into s;
    sc := sc || jsonb_build_object(x.k, s);
    insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
      (s, w, f1, jsonb_build_array(pg_temp.rf_fl('F1', 101, 'XA1', 'XA2', '1234567'), pg_temp.rf_fl('F1', 102, 'XA2', 'XA1', '1234567'))),
      (s, w, f2, jsonb_build_array(pg_temp.rf_fl('F2', 201, 'XB1', 'XB2', '1234567'), pg_temp.rf_fl('F2', 202, 'XB2', 'XB1', '1234567'))),
      (s, w, (ids ->> 'fr1')::bigint, jsonb_build_array(pg_temp.rf_fl('FR', 1, 'XA1', 'XA2', '1234567'), pg_temp.rf_fl('FR', 2, 'XA2', 'XA1', '1234567'),
                                                        pg_temp.rf_fl('FR', 3, 'XA1', 'XC2', '1234567'))),
      (s, w, (ids ->> 'fr2')::bigint, '[]'::jsonb),
      (s, w, (ids ->> 'fr3')::bigint, jsonb_build_array(pg_temp.rf_fl('FT', 1, 'XA2', 'XC3', '1234567'))),
      (s, w, (ids ->> 'fr4')::bigint, jsonb_build_array(pg_temp.rf_fl('FV', 1, 'XC1', 'XC2', '135'))),
      (s, w, (ids ->> 'fx5')::bigint, jsonb_build_array(pg_temp.rf_fl('FX', 1, 'XA1', 'XA2', '1234567', '77F')));
    perform private.scan_summarise(s);
    perform private.scan_ingest(w, 'fleet', (select v from t_rf where k = 'fr1') || jsonb_build_object('snapshot_id', s,
              'totals', '{"owned": 0, "leased": 99, "overall": 99, "leased_out": 0, "on_offer": 0, "on_order": 0, "avg_age_years": 2.1}'::jsonb || jsonb_build_object('on_order', x.fr1_order)));
    perform private.scan_ingest(w, 'fleet', pg_temp.rf_page(990803, 'Fleet Rival Three', 50, 10) || jsonb_build_object('snapshot_id', s));
    perform private.scan_ingest(w, 'fleet', pg_temp.rf_page(990702, 'Fleet Two', 40, 30) || jsonb_build_object('snapshot_id', s));
    if x.k = 's2' then
      perform private.scan_ingest(w, 'fleet', pg_temp.rf_page(990802, 'Fleet Rival Two', 0, 12) || jsonb_build_object('snapshot_id', s));
      perform private.scan_ingest(w, 'fleet', pg_temp.rf_page(990804, 'Fleet Rival Four', 8, 4) || jsonb_build_object('snapshot_id', s));
      perform private.scan_ingest(w, 'fleet', pg_temp.rf_page(990805, 'Fleet Cargo Five', 20, 10, 'Boeing 777F') || jsonb_build_object('snapshot_id', s));
    end if;
  end loop;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_rf values ('ids', ids), ('scans', sc), ('t', to_jsonb(timestamptz '2030-03-08 12:00:00+00'));
end
$setup$;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rf where k = 'w'); f1 bigint := (select (v #>> '{}')::bigint from t_rf where k = 'f1');
  f2 bigint := (select (v #>> '{}')::bigint from t_rf where k = 'f2'); t timestamptz := (select (v #>> '{}')::timestamptz from t_rf where k = 't');
  ids jsonb := (select v from t_rf where k = 'ids'); d jsonb; e jsonb; c jsonb; got text; plain jsonb;
begin
  d := private.fig_competition(f1, t);
  assert d #>> '{scans,week_before,taken_at}' = '2030-03-01T08:00:00.000Z', 'the week-before scan isn''t 1 Mar: ' || (d -> 'scans')::text;
  -- F1's competitors: FR1 on its pair (14 a week); FX5 is freighters only, never a competitor
  c := d -> 'competitors' -> 0;
  assert c ->> 'name' = 'Fleet Rival One' and jsonb_array_length(d -> 'competitors') = 1, 'F1''s competitors aren''t FR1 alone: ' || (d -> 'competitors')::text;
  assert (c -> 'fleet') - 'types' = '{"overall": 99, "on_order": 44, "avg_age_years": 2.1, "types_count": 8, "overall_before": 99, "on_order_before": 38, "overall_change": 0, "on_order_change": 6}'::jsonb,
    'FR1''s fleet isn''t 99 aircraft, 44 on order (+6 on the week), 2.1 years, 8 types: ' || (c -> 'fleet')::text;
  select string_agg(format('%s %s/%s', x ->> 'type', x ->> 'overall', x ->> 'on_order'), ', ' order by i) into got
    from jsonb_array_elements(c #> '{fleet,types}') with ordinality e(x, i);
  assert got = 'Airbus A321XLR 23/10, Boeing 737-9 HGW 23/5, Airbus A321LR 21/10, Boeing 737-8 HGW 16/10, Boeing 737-10 HGW 9/9',
    'FR1''s top 5 types aren''t by overall, then on order: ' || coalesce(got, 'none');
  -- the rival profiles carry the same fleet
  assert (select x -> 'fleet' from jsonb_array_elements(d -> 'profiles') x where x ->> 'name' = 'Fleet Rival One') = c -> 'fleet',
    'FR1''s rival profile doesn''t carry its fleet';

  -- the flags: the world's list, biggest share first
  select string_agg(format('%s %s %s/%s %s%% weekly %s change %s meets %s (pairs %s, bases %s)', x ->> 'name', x ->> 'kind', x ->> 'on_order', x ->> 'fleet',
                           coalesce(x ->> 'share', '-'), coalesce(x ->> 'weekly', '-'), coalesce(x ->> 'on_order_change', '-'), x ->> 'meets', x ->> 'on_pairs', x ->> 'at_bases'), '; ' order by i)
    into got from jsonb_array_elements(d -> 'order_flags') with ordinality e(x, i);
  assert got = 'Fleet Rival Two starting 12/0 -% weekly 0 change - meets false (pairs false, bases false); Fleet Rival One orders 44/99 44.4% weekly 21 change 6 meets true (pairs true, bases true)',
    'F1''s order flags are ' || coalesce(got, 'none');
  assert (select x ->> 'words' from jsonb_array_elements(d -> 'order_flags') x where x ->> 'kind' = 'orders') = 'Fleet Rival One: 44 on order, 44.4% of its 99 aircraft'
     and (select x ->> 'words' from jsonb_array_elements(d -> 'order_flags') x where x ->> 'kind' = 'starting') = 'Fleet Rival Two: 12 on order and no flights yet',
    'the flags'' words: ' || (d -> 'order_flags')::text;
  -- F2's answer: the same list, marked for F2 (FR1 meets none of its pairs or bases)
  e := private.fig_competition(f2, t);
  assert (select jsonb_agg(x - 'on_pairs' - 'at_bases' - 'meets') from jsonb_array_elements(e -> 'order_flags') x)
       = (select jsonb_agg(x - 'on_pairs' - 'at_bases' - 'meets') from jsonb_array_elements(d -> 'order_flags') x)
     and not exists (select 1 from jsonb_array_elements(e -> 'order_flags') x where (x ->> 'meets')::boolean),
    'F2''s order flags aren''t the same list, none meeting it: ' || (e -> 'order_flags')::text;

  -- the thresholds: at 45% FR1 isn't flagged; at a minimum of 45 it isn't either; FR3 at 20% is with the line at 20
  update public.settings set value = '45' where world_id = w and airline_id is null and key = 'rival_orders_flag_pct';
  assert not exists (select 1 from jsonb_array_elements(private.fig_competition(f1, t) -> 'order_flags') x where x ->> 'kind' = 'orders'), 'FR1 flagged at 45%';
  update public.settings set value = '20' where world_id = w and airline_id is null and key = 'rival_orders_flag_pct';
  select string_agg(x ->> 'name', ', ' order by i) into got from jsonb_array_elements(private.fig_competition(f1, t) -> 'order_flags') with ordinality e(x, i) where x ->> 'kind' = 'orders';
  assert got = 'Fleet Rival One, Fleet Rival Three', 'at 20%, the orders flags are ' || coalesce(got, 'none');
  update public.settings set value = '25' where world_id = w and airline_id is null and key = 'rival_orders_flag_pct';
  update public.settings set value = '45' where world_id = w and airline_id is null and key = 'rival_orders_flag_min';
  assert not exists (select 1 from jsonb_array_elements(private.fig_competition(f1, t) -> 'order_flags') x where x ->> 'kind' = 'orders'), 'FR1 flagged with a minimum of 45';
  update public.settings set value = '4' where world_id = w and airline_id is null and key = 'rival_orders_flag_min';
  assert exists (select 1 from jsonb_array_elements(private.fig_competition(f1, t) -> 'order_flags') x where x ->> 'name' = 'Fleet Rival Four'),
    'FR4 (4 on order, 50%) isn''t flagged with a minimum of 4';
  update public.settings set value = '5' where world_id = w and airline_id is null and key = 'rival_orders_flag_min';

  -- FR4's fleet in a profile? It flies no pair of F1's, so no; its change is null (no page in s1)
  assert (private.scan_fleet((d #>> '{scans,latest,id}')::bigint, (d #>> '{scans,week_before,id}')::bigint, (ids ->> 'fr4')::bigint))
         ->> 'on_order_change' is null, 'FR4 (no page in the week-before scan) has a change';
  assert private.scan_fleet((d #>> '{scans,week_before,id}')::bigint, null, (ids ->> 'fr4')::bigint) is null, 'FR4''s fleet in a scan that didn''t read it isn''t null';

  -- nothing else moves with the fleets: without the fleet pages the document is the same but for fleet and order_flags
  plain := d;
  delete from public.scan_airline_fleet where scan_id in ((d #>> '{scans,latest,id}')::bigint, (d #>> '{scans,week_before,id}')::bigint);
  delete from public.scan_airline_profile where scan_id in ((d #>> '{scans,latest,id}')::bigint, (d #>> '{scans,week_before,id}')::bigint);
  e := private.fig_competition(f1, t);
  assert e -> 'order_flags' = '[]'::jsonb and (e #> '{competitors,0,fleet}') = 'null'::jsonb, 'with no fleet pages there are flags or a fleet';
  assert (e - 'competitors' - 'profiles' - 'order_flags' - 'notes') = (plain - 'competitors' - 'profiles' - 'order_flags' - 'notes')
     and (select jsonb_agg(x - 'fleet') from jsonb_array_elements(e -> 'competitors') x) = (select jsonb_agg(x - 'fleet') from jsonb_array_elements(plain -> 'competitors') x)
     and (select jsonb_agg(x - 'fleet') from jsonb_array_elements(e -> 'profiles') x) = (select jsonb_agg(x - 'fleet') from jsonb_array_elements(plain -> 'profiles') x),
    'the fleets moved more than fleet and order_flags (the openings, threats, markets or the competitors'' other figures)';
  raise notice 'competition(): FR1''s fleet on F1''s competitors and profiles, 99 aircraft, 44 on order (+6 on the week), 2.1 years, its top 5 types; order_flags FR2 starting (12 on order, no flights) and FR1 orders (44 of 99, 44.4%%), meeting F1 on its pair and at its base; not FR3 (20%%), FR4 (4 on order), our F2 (30 of 40) or the freighter FX5; the same list for F2, meeting none; the settings move the line; without fleet pages only fleet and order_flags change';
end
$test$;

-- ---------------------------------------------------------------- 4. system_status(): the fleet pages the latest scan read
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_rf where k = 'w'); s bigint := (select (v #>> '{}')::bigint from t_rf where k = 'cap_scan'); d jsonb;
begin
  -- the capture's scan (one page read, one failed; its finish built its airport summary) made the latest
  assert exists (select 1 from public.scan_airline_airports x where x.scan_id = s), 'the capture''s scan has no airport summary';
  update public.game_scans set taken_at = '2030-03-09 08:00:00+00' where id = s;
  perform set_config('request.jwt.claims', '{"role": "authenticated", "email": "rival-fleets-staff@example.com"}', true);
  set local role authenticated;
  d := public.system_status(w, '2030-03-09 12:00:00+00');
  reset role;
  assert d #>> '{scan,fleet_pages}' = '1' and d #>> '{scan,fleet_failed}' = '1' and d #>> '{scan,taken_at}' = '2030-03-09T08:00:00.000Z',
    'system_status()''s scan doesn''t say 1 fleet page read and 1 failed: ' || coalesce((d -> 'scan')::text, 'none');
  raise notice 'system_status()''s scan: 1 fleet page read, 1 failed';
end
$test$;

-- ---------------------------------------------------------------- the copy (counts only)
do $test$
declare dw bigint := (select id from public.worlds where is_default); s bigint; a bigint; d jsonb;
begin
  select x.id into s from public.game_scans x where x.world_id = dw and x.status = 'done' order by x.taken_at desc, x.id desc limit 1;
  select al.airline_id into a from private.fig_airlines(dw) al order by al.ord limit 1;
  if a is not null then d := private.fig_competition(a, now()); end if;
  raise notice 'on the copy: the latest finished scan (%) read % fleet pages, % failed; the first airline''s answer has % order flags (% orders, % starting), % of its competitors with a fleet',
    coalesce(s::text, 'none'), (select count(*) from public.scan_airline_profile p where p.scan_id = s and p.read_ok),
    (select count(*) from public.scan_airline_profile p where p.scan_id = s and not p.read_ok),
    coalesce(jsonb_array_length(d -> 'order_flags'), 0),
    (select count(*) from jsonb_array_elements(coalesce(d -> 'order_flags', '[]')) x where x ->> 'kind' = 'orders'),
    (select count(*) from jsonb_array_elements(coalesce(d -> 'order_flags', '[]')) x where x ->> 'kind' = 'starting'),
    (select count(*) from jsonb_array_elements(coalesce(d -> 'competitors', '[]')) x where x -> 'fleet' <> 'null'::jsonb);
end
$test$;

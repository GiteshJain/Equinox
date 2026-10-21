-- The world scan in Capture all airlines (spec docs/specs/2026-10-21-scan-in-capture.md §1; migration
-- 20261021233000_scan_in_capture.sql; manual §7). Run by database/rehearse.sh on the copy of last night's backup, after the
-- new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes,
-- ids and counts of the hand-made world only, never rows of the copy).
--   1. Who may call what: capture_scan() signed out and signed in, as owner with an empty search path, described, not
--      open to public; capture_airlines() and ingest_snapshot() as before; the three new internal functions closed, run as
--      the caller with an empty search path, described. The setting scan_every_days in every world, 1 in the default
--      world, in days, described.
--   2. On the copy: Gander's capture_airlines() with a key of its own, signed out, as the capture calls it: scan_due as
--      the copy's latest finished scan and the setting say, scan_airports our bases first, then gscan.py's hubs, then the
--      latest finished scan's busiest airports, each once (counts and milliseconds only).
--   3. A world of its own with its own key (our airline at ZS1 and ZS2): a bad key and a bad kind refused as the capture
--      refuses them; no finished scan yet, so a scan is due.
--   4. The same scan sent twice, signed out: through ingest_snapshot() with the ingest secret (the default world, as
--      gscan.py does) and through capture_scan() with the key (the key's world): start, two airlines (a rival flying from
--      22 airports, and our airline under another name), one airport (with an airline seen only there) and finish. The
--      rows in game_scans, game_scan_airlines, game_scan_schedules, game_scan_airports and scan_airline_airports are
--      exactly as ingest_snapshot() makes them; the airlines are placed in the key's world (logged as capture), ours left
--      as it is. A second start within the hour gets the same id; a scan of another world, and a payload that doesn't
--      read, are refused, writing nothing.
--   5. scan_due around the setting (1, 3, 0 and none) as the scan ages by capture days; scan_open within the hour and not
--      after; the airports to read: the bases, the hubs, then the scan's 20 busiest airports without repeats.
--   6. Scans that stop part-way (migration 20261022010000; spec docs/specs/2026-10-21-tidy-ups.md §1): a scan left
--      unfinished after one airline, a new one started two hours later: the first one stopped with its note ("stopped
--      part-way after 1 of 2 airlines and 0 of 1 airports"), system_status()'s scan_stopped before and after, cleared once
--      a scan finishes after it; one started within the hour still reused as now; a start in another world leaves it
--      alone. On the copy, the scans marked stopped (ids and days) and the scans by status.

create temporary table t_cs (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_cs to anon, authenticated;

-- the payloads, as scripts/scanner/gscan.py sends them: a rival (990701) flying from Z01..Z22 to JFK, 23 - n flights from
-- Zn each on Mondays (so Z01 has 22 departures a week and Z22 one), and JFK to LHR four days a week; our airline of the
-- hand-made world (990700), sent under another name, between its two bases daily; and the airport page of ZS1, with the
-- rival and an airline seen only there (990702)
insert into t_cs values ('rival', jsonb_build_object('enterprise_id', 990701, 'name', 'Scan Test Rival',
  'flights', (select jsonb_agg(jsonb_build_array('ST', (100 + 30 * n + i)::text, 'Z' || lpad(n::text, 2, '0'), 'JFK', '1', '08:00', '10:00', '32N', 'Scan Test Rival') order by n, i)
                from generate_series(1, 22) n cross join lateral generate_series(1, 23 - n) i)
             || jsonb_build_array(jsonb_build_array('ST', '1', 'JFK', 'LHR', '1357', '09:00', '21:00', '359', '')),
  'n_flights', 254, 'n_weekly', 257, 'n_airports', 24));
insert into t_cs values ('ours', jsonb_build_object('enterprise_id', 990700, 'name', 'Scan Test Sent Name',
  'flights', '[["SO", "10", "ZS1", "ZS2", "1234567", "07:00", "08:30", "32N", ""], ["SO", "11", "ZS2", "ZS1", "1234567", "09:30", "11:00", "32N", ""]]'::jsonb,
  'n_flights', 2, 'n_weekly', 14, 'n_airports', 2));
insert into t_cs values ('airport', jsonb_build_object('code', 'ZS1', 'airport_id', 4711,
  'info', '{"size": "Large airport", "runway": "3,200 m", "country": "Nowhere", "continent": "Asia", "night_ban": "no nighttime ban", "min_transfer": "01:00 h", "slots_per_5min": "12", "slot_availability": "88%"}'::jsonb,
  'stations', '[{"enterprise_id": 990700, "name": "Scan Test Sent Name", "weekly": 7, "alliance": null, "interline": false}, {"enterprise_id": 990702, "name": "Scan Test Station Only", "weekly": 3, "alliance": 77, "interline": true}]'::jsonb,
  'news', '[{"at": "2026-10-20 08:00", "text": "Scan Test Rival has opened a new station at Nowhere ."}]'::jsonb));

-- ---------------------------------------------------------------- 1. who may call what
do $test$
declare f text := 'public.capture_scan(text, text, jsonb)'; g text; dw bigint := (select id from public.worlds where is_default); bad text;
begin
  assert (select p.prosecdef and p.provolatile = 'v' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' doesn''t run as owner with an empty search path, or isn''t volatile';
  assert has_function_privilege('anon', f, 'execute'), 'signed out (the capture), ' || f || ' can''t be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  -- the two it changes, called as before
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid in ('public.ingest_snapshot(text, text, jsonb)'::regprocedure, 'public.capture_airlines(text)'::regprocedure)
     and not (p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false)
              and has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute'));
  assert bad is null, 'not callable as before, or not as owner with an empty search path: ' || bad;
  assert (select p.provolatile = 's' from pg_proc p where p.oid = 'public.capture_airlines(text)'::regprocedure), 'capture_airlines() isn''t stable any more';
  -- the new internal ones
  foreach g in array array['private.scan_ingest(bigint, text, jsonb)', 'private.scan_open(bigint, timestamptz)', 'private.capture_scan_plan(bigint, timestamptz)'] loop
    assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute'), g || ' can be called from outside';
    assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                        where p.oid = g::regprocedure and a.grantee = 0), g || ' is open to public';
    assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner or has no empty search path';
    assert obj_description(g::regprocedure, 'pg_proc') is not null, g || ' has no description';
  end loop;
  -- the setting
  assert not exists (select 1 from public.worlds w where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null
                                           and s.key = 'scan_every_days' and s.unit = 'days' and length(coalesce(s.description, '')) > 50)),
    'a world has no described scan_every_days setting in days';
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'scan_every_days') = '1'::jsonb,
    'scan_every_days isn''t 1 in the default world';
  raise notice 'capture_scan(): signed out and signed in, as owner with an empty search path, described; ingest_snapshot() and capture_airlines() called as before; scan_ingest(), scan_open() and capture_scan_plan() internal; scan_every_days 1, described, in every world';
end
$test$;

-- ---------------------------------------------------------------- 2. on the copy: Gander, as the capture calls it
do $setup$
begin
  insert into public.capture_keys (label, key_hash, world_id)
  select 'capture scan test, Gander', extensions.crypt('capture-scan-gander-key', extensions.gen_salt('bf')), w.id
    from public.worlds w where w.is_default;
end
$setup$;

set local role anon;
do $test$
declare t0 timestamptz := clock_timestamp(); r jsonb;
begin
  r := public.capture_airlines('capture-scan-gander-key');
  insert into t_cs values ('gander', r), ('gander_ms', to_jsonb(round(extract(epoch from clock_timestamp() - t0) * 1000)));
end
$test$;
reset role;

do $test$
declare r jsonb := (select v from t_cs where k = 'gander'); ms numeric := (select (v #>> '{}')::numeric from t_cs where k = 'gander_ms');
  dw bigint := (select id from public.worlds where is_default); v_every int; v_latest bigint; v_latest_at timestamptz; v_due boolean;
  v_bases jsonb; n_bases int; n_list int; bad text;
  c_hubs text[] := array['JFK', 'ORD', 'DFW', 'LAX', 'SFO', 'SEA', 'DEL', 'BOM', 'HYD', 'BLR', 'CCU', 'MAA', 'CDG', 'AMS', 'BCN', 'MXP',
    'MUC', 'LGW', 'MAN', 'EDI', 'PVG', 'PKX', 'SZX', 'KMG', 'XIY', 'KUL', 'LHR', 'SIN', 'DXB', 'DOH', 'AUH', 'IST', 'HKG', 'ICN', 'BKK', 'PEK',
    'CAN', 'CTU', 'HND', 'NRT', 'FRA', 'MAD', 'FCO', 'ATL', 'EWR', 'IAD', 'MIA', 'YYZ', 'MEX', 'SYD', 'CGK', 'MNL', 'SGN', 'DUB', 'ZRH', 'VIE', 'CPH'];
begin
  assert r ->> 'ok' = 'true' and jsonb_typeof(r -> 'airlines') = 'array' and jsonb_array_length(r -> 'airlines') > 0,
    'Gander''s key didn''t answer with its airlines: ' || coalesce(r ->> 'error', 'no error');
  -- due, worked out here from the copy: the latest finished scan's capture day against today's (the 10:00-to-10:00 UTC
  -- day the capture uses, private.capture_day())
  select (s.value #>> '{}')::numeric::int into v_every from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'scan_every_days';
  select s.id, s.taken_at into v_latest, v_latest_at from public.game_scans s where s.world_id = dw and s.status = 'done' order by s.taken_at desc, s.id desc limit 1;
  v_due := v_latest is null or private.capture_day(dw, now()) - private.capture_day(dw, v_latest_at) >= v_every;
  assert (r ->> 'scan_due')::boolean = v_due and (r ->> 'scan_every_days')::int = v_every,
    format('Gander: scan_due %s, scan_every_days %s, but the latest finished scan (%s) and the setting (%s) say %s', r ->> 'scan_due', r ->> 'scan_every_days', v_latest, v_every, v_due);
  assert (r #>> '{scan_latest,id}')::bigint is not distinct from v_latest, 'Gander''s scan_latest isn''t its latest finished scan';
  -- the airports: our bases first (in our airlines' order, main hub first), every hub, codes only, no repeats
  select jsonb_agg(code order by k), count(*) into v_bases, n_bases from (
    select distinct on (b.airport_code) b.airport_code as code,
           row_number() over (order by a.position nulls last, a.id, b.is_main desc, b.position nulls last, b.id) as k
      from public.airline_bases b join public.airlines a on a.id = b.airline_id join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = dw and a.active and g.kind = 'ours'
     order by b.airport_code, k) x;
  n_list := jsonb_array_length(r -> 'scan_airports');
  assert (select jsonb_agg(e order by i) from jsonb_array_elements(r -> 'scan_airports') with ordinality as t(e, i) where i <= n_bases) = v_bases,
    'Gander''s airports to read don''t start with our bases in order';
  select string_agg(h, ', ') into bad from unnest(c_hubs) h where not (r -> 'scan_airports') ? h;
  assert bad is null, 'Gander''s airports to read miss these hubs of gscan.py''s list: ' || bad;
  assert (select count(distinct e) from jsonb_array_elements_text(r -> 'scan_airports') e) = n_list, 'Gander''s airports to read have repeats';
  assert n_list <= n_bases + cardinality(c_hubs) + 20, 'Gander has more airports to read than its bases, the hubs and 20 more';
  assert not exists (select 1 from jsonb_array_elements_text(r -> 'scan_airports') e where e !~ '^[A-Z0-9]{3}$'), 'an airport to read isn''t a code';
  raise notice 'on the copy, Gander signed out: scan due %, every % day(s), latest finished scan % (% capture day(s) old); % airports to read (% bases, % hubs, the rest the busiest); open scan %; in % ms',
    v_due, v_every, coalesce(v_latest::text, 'none'),
    coalesce((private.capture_day(dw, now()) - private.capture_day(dw, v_latest_at))::text, '-'),
    n_list, n_bases, cardinality(c_hubs), coalesce(r ->> 'scan_open', 'none'), ms;
end
$test$;

-- ---------------------------------------------------------------- 3. a world of its own
do $setup$
declare dw bigint := (select id from public.worlds where is_default); w bigint; g bigint; al bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'capture scan test', true);
  insert into public.airports (code, utc_offset)
  select c, 0 from unnest(array['ZS1', 'ZS2']) c
  on conflict (code) do nothing;
  insert into public.worlds (name, game_host, kind) values ('capture scan test', 'capture-scan.test', 'exclusive') returning id into w;
  -- with the default world's settings (the capture day, scan_every_days)
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, game_name, iata_code, home_airport_code, active, position)
  values (w, g, 990700, 'Scan Test Planner', 'Scan Test', 'Scan Test Ours', 'SO', 'ZS1', true, 1) returning id into al;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values
    (w, al, 'ZS2', 'hub', false, 2), (w, al, 'ZS1', 'hub', true, 1);
  insert into public.capture_keys (label, key_hash, world_id)
  values ('capture scan test', extensions.crypt('capture-scan-test-key', extensions.gen_salt('bf')), w);
  insert into public.ingest_secret (secret) values ('capture-scan-test-secret');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_cs values ('w', to_jsonb(w)), ('ours_id', to_jsonb(al)), ('log_from', to_jsonb(coalesce((select max(id) from public.change_log), 0)));
end
$setup$;

set local role anon;
do $test$
declare r jsonb;
begin
  -- a bad key, as the capture refuses one
  assert public.capture_scan('not the key', 'start', '{}') = '{"ok": false, "error": "bad key"}'::jsonb, 'a wrong key wasn''t refused as the capture refuses one';
  assert public.capture_scan(null, 'start', '{}') = '{"ok": false, "error": "bad key"}'::jsonb, 'a missing key wasn''t refused';
  assert public.capture_airlines('not the key') = '{"ok": false, "error": "bad key"}'::jsonb, 'capture_airlines() doesn''t refuse a wrong key as before';
  -- a bad kind: markets stays the weekly report's, through ingest_snapshot()
  assert public.capture_scan('capture-scan-test-key', 'markets', '{}') = '{"ok": false, "error": "bad kind"}'::jsonb, 'kind markets wasn''t refused';
  assert public.capture_scan('capture-scan-test-key', null, '{}') = '{"ok": false, "error": "bad kind"}'::jsonb, 'no kind wasn''t refused';
  -- no finished scan yet: due, nothing open, the bases then the hubs
  r := public.capture_airlines('capture-scan-test-key');
  assert r ->> 'ok' = 'true' and r ->> 'world' = 'capture scan test' and r -> 'airlines' -> 0 ->> 'game_id' = '990700',
    'the hand-made world''s key didn''t answer with its airline: ' || r::text;
  assert (r ->> 'scan_due')::boolean and r -> 'scan_open' = 'null'::jsonb and r -> 'scan_latest' = 'null'::jsonb and (r ->> 'scan_every_days')::int = 1,
    'with no finished scan, a scan isn''t due (or something is open): ' || (r - 'airlines' - 'scan_airports')::text;
  insert into t_cs values ('plan0', r);
end
$test$;
reset role;

-- ---------------------------------------------------------------- 4. the same scan through ingest_snapshot() and capture_scan()
set local role anon;
do $test$
declare s text := 'capture-scan-test-secret'; v_key text := 'capture-scan-test-key'; r jsonb; a bigint; b bigint;
  p_rival jsonb := (select v from t_cs where k = 'rival'); p_ours jsonb := (select v from t_cs where k = 'ours'); p_airport jsonb := (select v from t_cs where k = 'airport');
begin
  -- the scanner's way, left open while the capture starts: an open scan of another world is no reason to carry on
  r := public.ingest_snapshot(s, 'start', '{"week": "43", "note": "capture scan test"}');
  a := (r ->> 'snapshot_id')::bigint;
  assert r = jsonb_build_object('snapshot_id', a), 'ingest_snapshot()''s start didn''t answer as before: ' || r::text;
  -- the capture's way
  r := public.capture_scan(v_key, 'start', '{"week": "43", "note": "capture scan test"}');
  b := (r ->> 'snapshot_id')::bigint;
  assert r = jsonb_build_object('ok', true, 'snapshot_id', b, 'carried_on', false) and b <> a,
    'capture_scan()''s start didn''t start a scan of its own: ' || r::text;
  -- a second start within the hour: the same scan
  r := public.capture_scan(v_key, 'start', '{"week": "43", "note": "capture scan test, again"}');
  assert r = jsonb_build_object('ok', true, 'snapshot_id', b, 'carried_on', true), 'a second start within the hour didn''t carry on with the same scan: ' || r::text;
  assert (public.capture_airlines(v_key) ->> 'scan_open')::bigint = b, 'capture_airlines() doesn''t give the open scan';
  -- the pages, each way
  assert public.ingest_snapshot(s, 'airline', p_rival || jsonb_build_object('snapshot_id', a)) = '{"ok": true}'::jsonb, 'ingest_snapshot() refused the rival';
  assert public.ingest_snapshot(s, 'airline', p_ours || jsonb_build_object('snapshot_id', a)) = '{"ok": true}'::jsonb, 'ingest_snapshot() refused our airline';
  assert public.ingest_snapshot(s, 'airport', p_airport || jsonb_build_object('snapshot_id', a)) = '{"ok": true}'::jsonb, 'ingest_snapshot() refused the airport';
  r := public.capture_scan(v_key, 'airline', p_rival || jsonb_build_object('snapshot_id', b));
  assert r = jsonb_build_object('ok', true, 'snapshot_id', b), 'capture_scan() didn''t take the rival: ' || r::text;
  assert public.capture_scan(v_key, 'airline', p_ours || jsonb_build_object('snapshot_id', b)) = jsonb_build_object('ok', true, 'snapshot_id', b), 'capture_scan() didn''t take our airline';
  assert public.capture_scan(v_key, 'airport', p_airport || jsonb_build_object('snapshot_id', b)) = jsonb_build_object('ok', true, 'snapshot_id', b), 'capture_scan() didn''t take the airport';
  -- refused, writing nothing (checked below, as postgres): the other world's scan, a scan that isn't there, a payload
  -- that doesn't read
  r := public.capture_scan(v_key, 'airline', p_rival || jsonb_build_object('snapshot_id', a, 'enterprise_id', 990703));
  assert r ->> 'ok' = 'false' and r ->> 'error' like 'no such scan in this capture key''s world: %', 'a scan of another world wasn''t refused: ' || r::text;
  r := public.capture_scan(v_key, 'finish', jsonb_build_object('snapshot_id', a));
  assert r ->> 'ok' = 'false', 'finishing a scan of another world wasn''t refused: ' || r::text;
  r := public.capture_scan(v_key, 'airport', '{"code": "ZS2"}');
  assert r ->> 'ok' = 'false' and r ->> 'error' like 'no such scan%', 'a page without its scan wasn''t refused: ' || r::text;
  r := public.capture_scan(v_key, 'airline', jsonb_build_object('snapshot_id', b, 'enterprise_id', 'not a number', 'name', 'x'));
  assert r ->> 'ok' = 'false' and r ->> 'error' like '%integer%', 'a payload that doesn''t read wasn''t refused: ' || r::text;
  -- finish, each way
  assert public.ingest_snapshot(s, 'finish', jsonb_build_object('snapshot_id', a, 'note', 'full scan: 3 enterprises, 1 airports')) = '{"ok": true}'::jsonb,
    'ingest_snapshot()''s finish didn''t answer as before';
  assert public.capture_scan(v_key, 'finish', jsonb_build_object('snapshot_id', b, 'note', 'full scan: 3 enterprises, 1 airports')) = jsonb_build_object('ok', true, 'snapshot_id', b),
    'capture_scan()''s finish didn''t answer ok';
  insert into t_cs values ('a', to_jsonb(a)), ('b', to_jsonb(b));
end
$test$;
reset role;

do $test$
declare a bigint := (select (v #>> '{}')::bigint from t_cs where k = 'a'); b bigint := (select (v #>> '{}')::bigint from t_cs where k = 'b');
  w bigint := (select (v #>> '{}')::bigint from t_cs where k = 'w'); dw bigint := (select id from public.worlds where is_default);
  ours bigint := (select (v #>> '{}')::bigint from t_cs where k = 'ours_id'); x jsonb; y jsonb; got text;
begin
  -- the scans: each in its world, finished, with the same week and note
  assert (select jsonb_agg(jsonb_build_array(s.world_id = case when s.id = a then dw else w end, s.status, s.week, s.note) order by s.id)
            from public.game_scans s where s.id in (a, b))
         = '[[true, "done", "43", "full scan: 3 enterprises, 1 airports"], [true, "done", "43", "full scan: 3 enterprises, 1 airports"]]'::jsonb,
    'the two scans aren''t each in its world, finished, with the week and note sent';
  -- the airlines' totals, by game ID, exactly as ingest_snapshot() made them (the airlines row aside: its world differs)
  select jsonb_agg(jsonb_build_array(t.enterprise_id, t.name, t.n_flights, t.n_weekly, t.n_airports, t.position, al.game_id, al.world_id = t.world_id) order by t.enterprise_id)
    into x from public.game_scan_airlines t join public.airlines al on al.id = t.airline_id where t.scan_id = a;
  select jsonb_agg(jsonb_build_array(t.enterprise_id, t.name, t.n_flights, t.n_weekly, t.n_airports, t.position, al.game_id, al.world_id = t.world_id) order by t.enterprise_id)
    into y from public.game_scan_airlines t join public.airlines al on al.id = t.airline_id where t.scan_id = b;
  assert x = y and jsonb_array_length(y) = 2, 'game_scan_airlines differs from ingest_snapshot()''s: ' || coalesce(y::text, 'none') || ' against ' || coalesce(x::text, 'none');
  assert y -> 0 = '[990700, "Scan Test Sent Name", 2, 14, 2, 2, 990700, true]'::jsonb and y -> 1 = '[990701, "Scan Test Rival", 254, 257, 24, 1, 990701, true]'::jsonb,
    'game_scan_airlines isn''t as sent: ' || y::text;
  -- the schedules, by game ID
  select jsonb_object_agg(al.game_id, t.flights) into x from public.game_scan_schedules t join public.airlines al on al.id = t.airline_id where t.scan_id = a;
  select jsonb_object_agg(al.game_id, t.flights) into y from public.game_scan_schedules t join public.airlines al on al.id = t.airline_id where t.scan_id = b;
  assert x = y and y -> '990701' = (select v -> 'flights' from t_cs where k = 'rival') and y -> '990700' = (select v -> 'flights' from t_cs where k = 'ours'),
    'game_scan_schedules differs from ingest_snapshot()''s, or from what was sent';
  assert (select bool_and(t.world_id = w) from public.game_scan_schedules t where t.scan_id = b), 'a schedule isn''t in the key''s world';
  -- the airport page
  select jsonb_agg(jsonb_build_array(t.airport_code, t.game_airport_id, t.info, t.stations, t.news, t.position)) into x from public.game_scan_airports t where t.scan_id = a;
  select jsonb_agg(jsonb_build_array(t.airport_code, t.game_airport_id, t.info, t.stations, t.news, t.position)) into y from public.game_scan_airports t where t.scan_id = b;
  assert x = y and jsonb_array_length(y) = 1 and y -> 0 ->> 0 = 'ZS1' and (y -> 0 ->> 1)::int = 4711, 'game_scan_airports differs from ingest_snapshot()''s: ' || coalesce(y::text, 'none');
  assert (select bool_and(t.world_id = w) from public.game_scan_airports t where t.scan_id = b), 'the airport page isn''t in the key''s world';
  -- the airport summaries, built at finish
  select jsonb_object_agg(al.game_id || ' ' || t.airport_code, jsonb_build_array(t.weekly_departures, t.destinations)) into x
    from public.scan_airline_airports t join public.airlines al on al.id = t.airline_id where t.scan_id = a;
  select jsonb_object_agg(al.game_id || ' ' || t.airport_code, jsonb_build_array(t.weekly_departures, t.destinations)) into y
    from public.scan_airline_airports t join public.airlines al on al.id = t.airline_id where t.scan_id = b;
  assert x = y and jsonb_typeof(y) = 'object' and y -> '990701 Z01' = '[22, 1]'::jsonb and y -> '990701 JFK' = '[4, 1]'::jsonb and y -> '990700 ZS1' = '[7, 1]'::jsonb,
    'scan_airline_airports differs from ingest_snapshot()''s: ' || coalesce(y::text, 'none');
  -- the refused pages wrote nothing: two airlines in each scan, none with the game ID only a refused page named
  assert (select count(*) from public.game_scan_airlines where scan_id = a) = 2 and (select count(*) from public.game_scan_airlines where scan_id = b) = 2
     and not exists (select 1 from public.game_scan_airlines where enterprise_id = 990703) and not exists (select 1 from public.airlines where game_id = 990703)
     and (select count(*) from public.game_scan_airports where scan_id in (a, b)) = 2,
    'a refused page wrote something';
  -- the airlines placed in the key's world: the rival and the one seen only at the airport, added and logged as the capture;
  -- ours left as it is (its name not the one sent)
  select string_agg(al.game_id || ' ' || coalesce(al.game_name, '-') || ' ' || (al.group_id is null), ', ' order by al.game_id) into got
    from public.airlines al where al.world_id = w;
  assert got = '990700 Scan Test Ours false, 990701 Scan Test Rival true, 990702 Scan Test Station Only true',
    'the airlines in the key''s world aren''t placed as ingest_snapshot() places them: ' || coalesce(got, 'none');
  select string_agg(l.actor || '/' || l.actor_detail || ' ' || (l.new_values ->> 'game_id'), ', ' order by l.new_values ->> 'game_id') into got
    from public.change_log l where l.id > (select (v #>> '{}')::bigint from t_cs where k = 'log_from')
     and l.table_name = 'airlines' and l.op = 'insert' and l.world_id = w;
  assert got = 'capture/capture_scan 990701, capture/capture_scan 990702', 'the airlines the capture''s scan added aren''t logged as the capture: ' || coalesce(got, 'none');
  assert (select count(*) from public.change_log l where l.id > (select (v #>> '{}')::bigint from t_cs where k = 'log_from')
            and l.table_name = 'airlines' and l.world_id = dw and l.actor = 'script' and l.actor_detail = 'ingest_snapshot') = 3,
    'ingest_snapshot() didn''t log its three new airlines as the script, as before';
  assert (select count(*) from public.change_log l where l.id > (select (v #>> '{}')::bigint from t_cs where k = 'log_from')
            and l.table_name = 'airlines' and l.row_key = jsonb_build_object('id', ours)) = 0,
    'the scan changed our airline';
  raise notice 'the same scan through ingest_snapshot() (default world) and capture_scan() (the key''s world): game_scans, game_scan_airlines, game_scan_schedules, game_scan_airports and scan_airline_airports the same; 2 airlines placed in the key''s world, logged as the capture, ours left as it is; a second start within the hour carried on; another world''s scan, a missing scan and a payload that doesn''t read refused, writing nothing';
end
$test$;

-- ---------------------------------------------------------------- 5. scan_due, scan_open and the airports to read
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_cs where k = 'w'); b bigint := (select (v #>> '{}')::bigint from t_cs where k = 'b');
  v_key text := 'capture-scan-test-key'; r jsonb; got text; c bigint; d bigint;
  c_hubs text[] := array['JFK', 'ORD', 'DFW', 'LAX', 'SFO', 'SEA', 'DEL', 'BOM', 'HYD', 'BLR', 'CCU', 'MAA', 'CDG', 'AMS', 'BCN', 'MXP',
    'MUC', 'LGW', 'MAN', 'EDI', 'PVG', 'PKX', 'SZX', 'KMG', 'XIY', 'KUL', 'LHR', 'SIN', 'DXB', 'DOH', 'AUH', 'IST', 'HKG', 'ICN', 'BKK', 'PEK',
    'CAN', 'CTU', 'HND', 'NRT', 'FRA', 'MAD', 'FCO', 'ATL', 'EWR', 'IAD', 'MIA', 'YYZ', 'MEX', 'SYD', 'CGK', 'MNL', 'SGN', 'DUB', 'ZRH', 'VIE', 'CPH'];
begin
  -- before the scan: the bases (main hub first), then gscan.py's hubs, in its order
  r := (select v from t_cs where k = 'plan0');
  assert r -> 'scan_airports' = to_jsonb(array['ZS1', 'ZS2'] || c_hubs), 'before any scan, the airports to read aren''t the bases then the hubs: ' || (r -> 'scan_airports')::text;
  -- finished today: not due, the scan the latest; then the busiest 20 of it after the hubs, each once: Z01 to Z18 (ZS1 and
  -- ZS2, among the 20 with 7 departures each, are bases already; JFK, a hub, has 4; Z19 to Z22 aren't among the 20)
  r := public.capture_airlines(v_key);
  assert not (r ->> 'scan_due')::boolean and (r #>> '{scan_latest,id}')::bigint = b and r -> 'scan_open' = 'null'::jsonb,
    'just after the scan finished, a scan is due, or it isn''t the latest: ' || (r - 'airlines' - 'scan_airports')::text;
  assert r -> 'scan_airports' = to_jsonb(array['ZS1', 'ZS2'] || c_hubs || array(select 'Z' || lpad(n::text, 2, '0') from generate_series(1, 18) n)),
    'the airports to read aren''t the bases, the hubs and the scan''s busiest 20 without repeats: ' || (r -> 'scan_airports')::text;
  -- by capture day (10:00 to 10:00 UTC), around the setting
  update public.game_scans set taken_at = taken_at - interval '1 day' where id = b;
  assert (public.capture_airlines(v_key) ->> 'scan_due')::boolean, 'a scan a capture day old isn''t due with scan_every_days 1';
  update public.settings set value = '3'::jsonb where world_id = w and airline_id is null and key = 'scan_every_days';
  assert not (public.capture_airlines(v_key) ->> 'scan_due')::boolean, 'a scan a capture day old is due with scan_every_days 3';
  update public.game_scans set taken_at = taken_at - interval '1 day' where id = b;
  assert not (public.capture_airlines(v_key) ->> 'scan_due')::boolean, 'a scan two capture days old is due with scan_every_days 3';
  update public.game_scans set taken_at = taken_at - interval '1 day' where id = b;
  assert (public.capture_airlines(v_key) ->> 'scan_due')::boolean, 'a scan three capture days old isn''t due with scan_every_days 3';
  -- the capture day, not the UTC date: a scan at 00:30 UTC (an evening in Chicago) is due again at 23:30 UTC the same
  -- date (the next evening), and not at 01:00 UTC (the same evening, captured again after midnight UTC)
  update public.settings set value = '1'::jsonb where world_id = w and airline_id is null and key = 'scan_every_days';
  update public.game_scans set taken_at = timestamptz '2026-10-22 00:30+00' where id = b;
  assert (private.capture_scan_plan(w, timestamptz '2026-10-22 23:30+00') ->> 'scan_due')::boolean,
    'a scan at 00:30 UTC isn''t due at 23:30 UTC the same date (the next evening)';
  assert not (private.capture_scan_plan(w, timestamptz '2026-10-22 01:00+00') ->> 'scan_due')::boolean,
    'a scan at 00:30 UTC is due again at 01:00 UTC, the same evening';
  update public.game_scans set taken_at = timestamptz '2026-10-21 23:30+00' where id = b;
  assert not (private.capture_scan_plan(w, timestamptz '2026-10-22 00:30+00') ->> 'scan_due')::boolean,
    'a scan at 23:30 UTC is due again at 00:30 UTC, the same evening across midnight UTC';
  update public.game_scans set taken_at = now() where id = b;
  -- 0: every capture; no setting: never
  update public.settings set value = '0'::jsonb where world_id = w and airline_id is null and key = 'scan_every_days';
  assert (public.capture_airlines(v_key) ->> 'scan_due')::boolean, 'with scan_every_days 0, a scan finished today isn''t due';
  delete from public.settings where world_id = w and airline_id is null and key = 'scan_every_days';
  r := public.capture_airlines(v_key);
  assert not (r ->> 'scan_due')::boolean and r -> 'scan_every_days' = 'null'::jsonb, 'without the setting, a scan is due: ' || (r - 'airlines' - 'scan_airports')::text;
  update public.game_scans set taken_at = taken_at - interval '30 days' where id = b;
  assert not (public.capture_airlines(v_key) ->> 'scan_due')::boolean, 'without the setting, a scan 30 days old is due';
  -- open within the hour, not after; a start after the hour starts another
  insert into public.game_scans (world_id, week, note, taken_at) values (w, '43', 'capture scan test, open', now() - interval '59 minutes') returning id into c;
  assert (public.capture_airlines(v_key) ->> 'scan_open')::bigint = c, 'an unfinished scan 59 minutes old isn''t open';
  update public.game_scans set taken_at = now() - interval '61 minutes' where id = c;
  assert public.capture_airlines(v_key) -> 'scan_open' = 'null'::jsonb, 'an unfinished scan 61 minutes old is still open';
  r := public.capture_scan(v_key, 'start', '{"week": "43"}');
  d := (r ->> 'snapshot_id')::bigint;
  assert r ->> 'ok' = 'true' and (r ->> 'carried_on')::boolean is false and d not in (b, c), 'a start after the hour didn''t start another scan: ' || r::text;
  assert (public.capture_airlines(v_key) ->> 'scan_open')::bigint = d, 'the new scan isn''t open';
  -- a finished scan is never open
  update public.game_scans set status = 'done' where id = d;
  assert public.capture_airlines(v_key) -> 'scan_open' = 'null'::jsonb, 'a finished scan is open';
  raise notice 'scan_due by capture day: 1 day old due with 1, not with 3 until 3 days; 00:30 UTC due again at 23:30 UTC the same date, not at 01:00; 23:30 UTC not again at 00:30; 0 always; no setting never. scan_open within the hour only, a start after it a new scan; the airports to read: 2 bases, % hubs, then the busiest 20 less the 2 bases',
    cardinality(c_hubs);
end
$test$;

-- ---------------------------------------------------------------- 6. scans that stop part-way (spec docs/specs/2026-10-21-tidy-ups.md §1)
-- In the hand-made world: the finished scan b (two airlines, one airport) a day old, and a scan left unfinished two hours
-- ago after one airline. Systems sees it stopped (nothing carries it on), and the next start marks it stopped with its note;
-- a start within the hour still carries on; once a scan finishes after it, Systems says nothing. A start in another world
-- leaves this world's scans alone. On the copy: the scans marked stopped.
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_cs where k = 'w'); b bigint := (select (v #>> '{}')::bigint from t_cs where k = 'b');
  dw bigint := (select id from public.worlds where is_default); p_rival jsonb := (select v from t_cs where k = 'rival'); e bigint; s jsonb;
  v_note text;
begin
  -- the funcs: internal, run as the caller with an empty search path, described
  foreach v_note in array array['private.scan_progress(bigint)', 'private.scan_stop_unfinished(bigint, timestamptz)'] loop
    assert not has_function_privilege('anon', v_note, 'execute') and not has_function_privilege('authenticated', v_note, 'execute'), v_note || ' can be called from outside';
    assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = v_note::regprocedure),
      v_note || ' runs as owner or has no empty search path';
    assert length(coalesce(obj_description(v_note::regprocedure, 'pg_proc'), '')) > 100, v_note || ' has no description';
  end loop;
  assert col_description('public.game_scans'::regclass, (select attnum from pg_attribute where attrelid = 'public.game_scans'::regclass and attname = 'status')) like '%stopped%',
    'game_scans.status doesn''t say what stopped means';

  -- the world as section 5 left it: b finished a day ago is the latest finished, and nothing else
  delete from public.game_scans where world_id = w and id <> b;
  update public.game_scans set taken_at = now() - interval '1 day', status = 'done' where id = b;
  insert into public.game_scans (world_id, week, note, taken_at) values (w, '43', 'Capture all airlines 1.5', now() - interval '2 hours') returning id into e;
  perform private.scan_ingest(w, 'airline', p_rival || jsonb_build_object('snapshot_id', e));
  assert private.scan_progress(e) = jsonb_build_object('airlines', 1, 'airports', 0, 'before_id', b, 'before_at', private.fig_ts(now() - interval '1 day'),
                                                       'airlines_expected', 2, 'airports_expected', 1),
    'the unfinished scan''s progress isn''t 1 of 2 airlines and 0 of 1 airports, against b: ' || private.scan_progress(e)::text;
  -- Systems, before anything marks it: unfinished for over an hour, nothing carries it on
  s := public.system_status(w, now()) -> 'scan_stopped';
  assert (s ->> 'id')::bigint = e and s ->> 'status' = 'running' and (s ->> 'airlines')::int = 1 and (s ->> 'airlines_expected')::int = 2,
    'system_status() doesn''t give the scan left unfinished two hours ago: ' || coalesce(s::text, 'null');
  -- a start in another world leaves it alone
  perform private.scan_ingest(dw, 'start', '{"week": "43", "note": "capture scan test, the default world"}');
  assert (select status from public.game_scans where id = e) = 'running', 'a start in another world stopped this world''s scan';
  insert into t_cs values ('e', to_jsonb(e));
end
$test$;

set local role anon;
do $test$
declare e bigint := (select (v #>> '{}')::bigint from t_cs where k = 'e'); v_key text := 'capture-scan-test-key'; r jsonb; f bigint;
begin
  -- the next evening's capture starts a scan: the one left unfinished is stopped, and a new one starts
  assert (public.capture_airlines(v_key) -> 'scan_open') = 'null'::jsonb, 'a scan unfinished for two hours is open';
  r := public.capture_scan(v_key, 'start', '{"week": "43", "note": "Capture all airlines 1.5"}');
  f := (r ->> 'snapshot_id')::bigint;
  assert r ->> 'ok' = 'true' and (r ->> 'carried_on')::boolean is false and f <> e, 'the next start didn''t start a new scan: ' || r::text;
  -- a start within the hour still carries on with it, as before
  r := public.capture_scan(v_key, 'start', '{"week": "43", "note": "again"}');
  assert r = jsonb_build_object('ok', true, 'snapshot_id', f, 'carried_on', true), 'a start within the hour didn''t carry on: ' || r::text;
  insert into t_cs values ('f', to_jsonb(f));
end
$test$;
reset role;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_cs where k = 'w'); e bigint := (select (v #>> '{}')::bigint from t_cs where k = 'e');
  f bigint := (select (v #>> '{}')::bigint from t_cs where k = 'f'); s jsonb; v_note text; v_copy text;
begin
  select note into v_note from public.game_scans where id = e and status = 'stopped';
  assert v_note ~ '^stopped part-way after 1 of 2 airlines and 0 of 1 airports \(marked \d{2} [A-Z][a-z]{2} \d{2}:\d{2} UTC\) · Capture all airlines 1\.5$',
    'the scan left unfinished isn''t stopped with its note: ' || coalesce(v_note, '(not stopped)');
  assert (select status from public.game_scans where id = f) = 'running', 'the new scan was stopped';
  s := public.system_status(w, now()) -> 'scan_stopped';
  assert (s ->> 'id')::bigint = e and s ->> 'status' = 'stopped' and s ->> 'note' = v_note and (s ->> 'airports_expected')::int = 1,
    'system_status() doesn''t give the stopped scan: ' || coalesce(s::text, 'null');
  -- a scan that finishes after it: Systems says nothing more
  perform private.scan_ingest(w, 'finish', jsonb_build_object('snapshot_id', f, 'note', 'full scan'));
  assert public.system_status(w, now()) -> 'scan_stopped' = 'null'::jsonb, 'a stopped scan still shows after a finished one';
  -- a stopped scan is read by nothing that reads finished scans: capture_airlines()'s latest is the finished one
  assert (private.capture_scan_plan(w, now()) #>> '{scan_latest,id}')::bigint = f, 'the latest finished scan isn''t the new one';
  -- the copy: the scans the migration marked stopped (ids, days and counts only; this test's own scans left out)
  select string_agg(format('%s of %s', s2.id, to_char(s2.taken_at at time zone 'UTC', 'DD Mon')), ', ' order by s2.id) into v_copy
    from public.game_scans s2 where s2.status = 'stopped' and s2.world_id <> w and s2.taken_at < now();
  raise notice 'scans that stop part-way: left unfinished two hours, Systems shows it (1 of 2 airlines); the next start marks it stopped ("stopped part-way after 1 of 2 airlines and 0 of 1 airports"), a start within the hour still carries on, a start in another world leaves it alone, and a finished scan after it clears Systems. On the copy, stopped scans: %; the copy''s scans by status: %',
    coalesce(v_copy, 'none'),
    (select string_agg(x.status || ' ' || x.n, ', ' order by x.status)
       from (select s3.status, count(*) as n from public.game_scans s3 where s3.world_id <> w and s3.taken_at < now() group by 1) x);
end
$test$;

do $$ begin raise notice 'capture scan: all checks passed'; end $$;

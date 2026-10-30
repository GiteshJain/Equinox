-- The market pages' service codes as the planner writes them (migration 20261031120000; the first live market run of
-- 30 Oct stored the game's whole names, "S2 (min 800km)"). Run by database/rehearse.sh on the copy of last night's backup,
-- after the new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which
-- (codes and counts of the hand-made world only, never rows of the copy).
--   1. private.market_service_token(): internal, immutable, empty search path, described; the leading token before " (".
--   2. A world of its own (our MS on QS1–QS2, 1,000 km: S2; QS1–QS3, 500 km: S1; the planner's legs agreeing): a finished
--      run whose reads hold the game's whole names, as the 30 Oct run's do. The service check reads them by their token:
--      "S2 (min 800km)" on QS1–QS2 both ways and "S1 (max 800km)" on QS3→QS1 are no mismatch; "S2 (min 800km)" on
--      QS1→QS3 is one, game_code S2 against the distance's S1.
--   3. capture_market() keeps the token: a page sent with "S3 (min 1500km)" is stored as S3, one with "R" as R, one with
--      none as null.
--   4. On the copy (counts only): the reads holding a name with " (" and the check's answer for the world.

create temporary table t_st (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_st to anon, authenticated;

-- ---------------------------------------------------------------- 1. the token
do $test$
declare g text := 'private.market_service_token(text)';
begin
  assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute'), g || ' can be called from outside';
  assert (select not p.prosecdef and p.provolatile = 'i' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
    g || ' isn''t immutable, runs as owner or has no empty search path';
  assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 100, g || ' has no description';
  assert private.market_service_token('S2 (min 800km)') = 'S2' and private.market_service_token('S3 (min 1500km)') = 'S3'
     and private.market_service_token('R') = 'R' and private.market_service_token('  S1  ') = 'S1'
     and private.market_service_token('') is null and private.market_service_token(null) is null,
    'the token isn''t the leading code';
  assert position('leading token (since 31 Oct' in obj_description('private.fig_market_service_checks(bigint, bigint, timestamptz)'::regprocedure, 'pg_proc')) > 0
     and position('leading token (since 31 Oct' in obj_description('private.market_ingest(bigint, text, jsonb)'::regprocedure, 'pg_proc')) > 0
     and position('leading token (since 31 Oct' in obj_description('public.market_service_checks(bigint, timestamptz)'::regprocedure, 'pg_proc')) > 0
     and position('The service check' in obj_description('public.market_service_checks(bigint, timestamptz)'::regprocedure, 'pg_proc')) > 0,
    'a description lost its words or doesn''t say what changed';
  raise notice 'market_service_token(): internal, immutable, described; "S2 (min 800km)" → S2, R → R, empty → null';
end
$test$;

-- ---------------------------------------------------------------- 2. the check on the game's whole names
do $setup$
declare dw bigint := (select id from public.worlds where is_default); w bigint; g bigint; ms bigint; r1 bigint; r2 bigint; rot1 bigint; rot2 bigint; run bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'market service token test', true);
  insert into public.airports (code, utc_offset) select c, 0 from unnest(array['QS1', 'QS2', 'QS3']) c on conflict (code) do nothing;
  insert into public.worlds (name, game_host, kind) values ('market service token test', 'market-service-token.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.service_profiles (world_id, airline_id, code, up_to_km) values (w, null, 'S1', 800), (w, null, 'S2', 1500), (w, null, 'S3', 99999);
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, game_name, iata_code, home_airport_code, active, position)
  values (w, g, 990971, 'Service Token', 'Service Token', 'Service Token', 'MS', 'QS1', true, 1) returning id into ms;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, source) values (w, ms, 'QS1', 'QS2', 1000, 4, 'research') returning id into r1;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, source) values (w, ms, 'QS1', 'QS3', 500, 4, 'research') returning id into r2;
  insert into public.rotations (world_id, airline_id, route_id, launched_on, service_code) values (w, ms, r1, date '2030-03-01', 'S2') returning id into rot1;
  insert into public.rotations (world_id, airline_id, route_id, launched_on, service_code) values (w, ms, r2, date '2030-03-01', 'S1') returning id into rot2;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min) values
    (w, ms, rot1, 1, 401, 'QS1', 'QS2', '{1,2,3,4,5,6,7}', 360, 120), (w, ms, rot1, 2, 402, 'QS2', 'QS1', '{1,2,3,4,5,6,7}', 600, 120),
    (w, ms, rot2, 1, 501, 'QS1', 'QS3', '{1,2,3,4,5,6,7}', 420, 60), (w, ms, rot2, 2, 502, 'QS3', 'QS1', '{1,2,3,4,5,6,7}', 540, 60);
  -- a finished run whose reads hold the game's whole names, as the reads of 30 Oct do (written as capture 1.9 left them)
  insert into public.market_runs (world_id, started_at, finished_at, status, pages_read, pages_failed, capture_version)
  values (w, now() - interval '2 hours', now() - interval '1 hour', 'done', 4, 0, '1.9') returning id into run;
  insert into public.market_reads (run_id, world_id, airline_id, origin, dest, read_at, ok, share_week, service_code, service_profile_game_id) values
    (run, w, ms, 'QS1', 'QS2', now() - interval '2 hours', true, '2030-44', 'S2 (min 800km)', 308),
    (run, w, ms, 'QS2', 'QS1', now() - interval '2 hours', true, '2030-44', 'S2 (min 800km)', 308),
    (run, w, ms, 'QS1', 'QS3', now() - interval '2 hours', true, '2030-44', 'S2 (min 800km)', 308),
    (run, w, ms, 'QS3', 'QS1', now() - interval '2 hours', true, '2030-44', 'S1 (max 800km)', 307);
  insert into public.capture_keys (label, key_hash, world_id)
  values ('market service token test', extensions.crypt('market-service-token-test-key', extensions.gen_salt('bf')), w);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_st values ('w', to_jsonb(w)), ('ms', to_jsonb(ms)), ('r2', to_jsonb(r2));
end
$setup$;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_st where k = 'w'); r2 bigint := (select (v #>> '{}')::bigint from t_st where k = 'r2'); e jsonb;
begin
  e := private.fig_market_service_checks(w, null, now());
  assert (e ->> 'checked')::int = 4, 'the check didn''t look at the four reads: ' || coalesce(e ->> 'checked', 'none');
  assert jsonb_array_length(e -> 'mismatches') = 1, 'the game''s whole names read as mismatches: ' || (e -> 'mismatches')::text;
  assert (select jsonb_build_array(x ->> 'route_id', x ->> 'from', x ->> 'to', x ->> 'game_code', x ->> 'distance_code', x ->> 'kind')
            from jsonb_array_elements(e -> 'mismatches') x) = jsonb_build_array(r2::text, 'QS1', 'QS3', 'S2', 'S1', 'distance'),
    'the one mismatch isn''t QS1→QS3, S2 in the game against the S1 its 500 km call for: ' || (e -> 'mismatches')::text;
  raise notice 'the service check on reads holding the game''s whole names: 4 checked, S2 (min 800km) on a 1,000 km pair and S1 (max 800km) on a 500 km one no mismatch, S2 (min 800km) on the 500 km one a mismatch with game_code S2';
end
$test$;

-- ---------------------------------------------------------------- 3. capture_market() keeps the token
set local role anon;
do $test$
declare v_key text := 'market-service-token-test-key'; r jsonb; run bigint;
  base jsonb := '{"airline": 990971, "ok": true, "week": "2030-45", "fares": [], "shares": [], "weeks": []}'::jsonb;
begin
  r := public.capture_market(v_key, 'start', '{"version": "1.10", "total": 3}');
  run := (r ->> 'run_id')::bigint;
  assert r ->> 'ok' = 'true', 'start refused: ' || r::text;
  r := public.capture_market(v_key, 'page', base || jsonb_build_object('run_id', run, 'origin', 'QS1', 'dest', 'QS2', 'service', '{"code": "S3 (min 1500km)", "game_id": 309}'::jsonb));
  assert r ->> 'ok' = 'true', 'a page with the game''s whole name refused: ' || r::text;
  r := public.capture_market(v_key, 'page', base || jsonb_build_object('run_id', run, 'origin', 'QS2', 'dest', 'QS1', 'service', '{"code": "R", "game_id": 318}'::jsonb));
  assert r ->> 'ok' = 'true', 'a page with R refused: ' || r::text;
  r := public.capture_market(v_key, 'page', base || jsonb_build_object('run_id', run, 'origin', 'QS1', 'dest', 'QS3'));
  assert r ->> 'ok' = 'true', 'a page without a service refused: ' || r::text;
  insert into t_st values ('run2', to_jsonb(run));
end
$test$;
reset role;
do $test$
declare run bigint := (select (v #>> '{}')::bigint from t_st where k = 'run2');
begin
  assert (select jsonb_agg(jsonb_build_array(m.origin || '-' || m.dest, m.service_code, m.service_profile_game_id) order by m.origin, m.dest)
            from public.market_reads m where m.run_id = run)
         = '[["QS1-QS2", "S3", 309], ["QS1-QS3", null, null], ["QS2-QS1", "R", 318]]'::jsonb,
    'capture_market() didn''t keep the token: ' || (select jsonb_agg(jsonb_build_array(m.origin, m.dest, m.service_code)) from public.market_reads m where m.run_id = run)::text;
  raise notice 'capture_market(): "S3 (min 1500km)" stored as S3, R as R, none as null';
end
$test$;

-- ---------------------------------------------------------------- 4. on the copy
do $test$
declare n_named int; n_reads int; e jsonb;
begin
  select count(*) filter (where m.service_code like '% (%'), count(*) into n_named, n_reads
    from public.market_reads m join public.market_runs r on r.id = m.run_id
   where r.world_id = (select id from public.worlds where is_default);
  e := private.fig_market_service_checks((select id from public.worlds where is_default), null, now());
  assert jsonb_typeof(e -> 'mismatches') = 'array', 'the world''s service check didn''t answer';
  assert not exists (select 1 from jsonb_array_elements(e -> 'mismatches') x where x ->> 'game_code' like '% (%'),
    'a mismatch on the copy still carries the game''s whole name';
  raise notice 'on the copy: % of % market reads hold the game''s whole name; the check (latest finished run %) looks at %, % mismatch(es), none with a whole name',
    n_named, n_reads, coalesce(e #>> '{run,id}', 'none'), e ->> 'checked', jsonb_array_length(e -> 'mismatches');
end
$test$;

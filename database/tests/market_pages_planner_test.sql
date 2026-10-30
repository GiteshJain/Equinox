-- The market pages, part 2 (spec docs/specs/2026-10-30-market-pages-planner.md; migration
-- 20261030180000_market_pages_planner.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes, ids
-- and counts of the hand-made world only, never rows of the copy). The market reads here go in only through
-- capture_market(), as the capture sends them; never live data.
--   1. The objects: market_service_checks() signed in only, stable, as owner with an empty search path, its own 30 s
--      limit planned afresh, described; its builder and private.fig_market_pair() internal; route_story(),
--      competition(), fig_export() and export_for_report() keep their earlier words and add the new keys'.
--   2. On the copy (counts only): route_story() for each airline's busiest route has the three new keys (market null for a
--      pair no finished run has read); market_service_checks() for the world and each airline answers (run null and no
--      row while no run has finished); competition()'s game_share is null on every market with no read; the figures
--      export carries contested and market_run.
--   3. A world of its own: our airline MP flies QM1–QM2 (1,000 km: S2) and QM1–QM3 (500 km: S1; a second rotation set
--      S3), and has QM1–QM4 on its list, never read; two finished scans; route days by direction. Before any finished run:
--      route_story()'s market null, the check's run null, game_share null, contested without market. Then a run through
--      capture_market(): four pages (QM2→QM1 set S1 in the game, the rest as the distance says), and the check finds
--      QM2→QM1 against the distance first, then both ways of QM1–QM3 against the planner's S3; route_story()'s new keys;
--      competition()'s game_share (38%, weighted by seats; 2 of 3 pairs read) and contested QM1–QM2 with each way's
--      fares and share; a later run that isn't finished changes nothing; an airline's own check.
--   4. Signed out and an account that isn't staff are refused market_service_checks(); staff get what postgres gets.

create temporary table t_mp (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_mp to anon, authenticated;
insert into public.planner_users (email) values ('market-pages-planner-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare f text := 'public.market_service_checks(bigint, timestamptz)'; g text; x record;
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false)
                 and coalesce('statement_timeout=30s' = any (p.proconfig), false) and coalesce('plan_cache_mode=force_custom_plan' = any (p.proconfig), false)
            from pg_proc p where p.oid = f::regprocedure),
    f || ' isn''t stable, as owner with an empty search path and a 30 s limit planned afresh';
  assert not has_function_privilege('anon', f, 'execute'), 'signed out, ' || f || ' can be called';
  assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 400, f || ' has no description';
  foreach g in array array['private.fig_market_service_checks(bigint, bigint, timestamptz)', 'private.fig_market_pair(bigint, bigint, text, text, bigint)'] loop
    assert not has_function_privilege('authenticated', g, 'execute') and not has_function_privilege('anon', g, 'execute'), g || ' can be called from outside';
    assert (select not p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner, isn''t stable or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 200, g || ' has no description';
  end loop;
  -- the descriptions it adds to keep every earlier word (their first words and an earlier part still there)
  for x in select * from (values
      ('public.route_story(bigint, timestamptz)', 'A route''s story since launch', 'Weekly points (since 23 Oct', 'days_by_direction'),
      ('public.competition(bigint, timestamptz, integer)', '', 'connecting', 'game_share'),
      ('private.fig_export(bigint, timestamptz)', '', 'competitors', 'contested'),
      ('public.export_for_report(text, text, text)', '', 'figures', 'contested')) v(f, starts, keeps, adds) loop
    g := obj_description(x.f::regprocedure, 'pg_proc');
    assert g like x.starts || '%' and g like '%' || x.keeps || '%' and g like '%' || x.adds || '%' and g like '%market-pages-planner.md%',
      x.f || '''s description lost its earlier words or lacks the market part';
  end loop;
  raise notice 'market_service_checks(): signed in only, stable, as owner, 30 s planned afresh, described; its builder and fig_market_pair() internal; route_story(), competition(), fig_export() and export_for_report() keep their descriptions and add the new keys';
end
$test$;

-- ---------------------------------------------------------------- 2. on the copy (counts only)
do $test$
declare w bigint := (select id from public.worlds where is_default); al record; d jsonb; n_routes int := 0; n_market int := 0; n_hist int := 0;
  n_dir int := 0; c jsonb; e jsonb; n_mk int := 0; n_gs int := 0; n_cont int := 0; runs int; t0 timestamptz; ms int; worst int := 0;
begin
  select count(*) into runs from public.market_runs r where r.world_id = w and r.status = 'done';
  for al in select fa.airline_id, fa.iata_code,
                   (select x.route_id from public.route_days x where x.airline_id = fa.airline_id and x.route_id is not null
                     group by x.route_id order by sum(x.flights) desc, x.route_id limit 1) as route_id
              from private.fig_airlines(w) fa order by fa.ord loop
    if al.route_id is not null then
      t0 := clock_timestamp();
      d := public.route_story(al.route_id, now());
      worst := greatest(worst, round(extract(epoch from clock_timestamp() - t0) * 1000)::int);
      assert d ? 'days_by_direction' and d ? 'market' and d -> 'rivals' ? 'history', al.iata_code || '''s route story lacks a new key';
      assert jsonb_typeof(d -> 'days_by_direction') = 'array' and jsonb_typeof(d #> '{rivals,history}') = 'array', 'the new keys aren''t lists';
      assert jsonb_typeof(d -> 'market') in ('null', 'object'), 'market is neither null nor an object';
      assert runs > 0 or d -> 'market' = 'null'::jsonb, 'with no finished market run, a route story has a market';
      n_routes := n_routes + 1;
      n_market := n_market + (d -> 'market' <> 'null'::jsonb)::int;
      n_hist := n_hist + jsonb_array_length(d #> '{rivals,history}');
      n_dir := n_dir + jsonb_array_length(d -> 'days_by_direction');
    end if;
    c := private.fig_competition(al.airline_id, now(), 0);
    assert c ? 'contested' and c ? 'market_run' and jsonb_typeof(c -> 'contested') = 'array', al.iata_code || '''s competition() lacks contested or market_run';
    n_mk := n_mk + jsonb_array_length(c -> 'markets');
    n_gs := n_gs + (select count(*) from jsonb_array_elements(c -> 'markets') m where m -> 'game_share' <> 'null'::jsonb)::int;
    n_cont := n_cont + jsonb_array_length(c -> 'contested');
    assert runs > 0 or not exists (select 1 from jsonb_array_elements(c -> 'markets') m where m -> 'game_share' <> 'null'::jsonb),
      'with no finished market run, a market has a game share';
    assert runs > 0 or not exists (select 1 from jsonb_array_elements(c -> 'contested') x where x -> 'market' <> 'null'::jsonb),
      'with no finished market run, a contested pair has market figures';
    e := private.fig_market_service_checks(w, al.airline_id, now());
    assert runs > 0 or (e -> 'run' = 'null'::jsonb and e -> 'mismatches' = '[]'::jsonb), 'with no finished run, the service check found something';
  end loop;
  e := private.fig_market_service_checks(w, null, now());
  assert jsonb_typeof(e -> 'mismatches') = 'array' and (e ? 'run') and (e ? 'checked'), 'the world''s service check isn''t {run, checked, mismatches}';
  raise notice 'on the copy: % finished market run(s); route_story() for % busiest routes with days_by_direction (% rows), rivals.history (% scans) and market (% read), slowest % ms; competition(): % of % markets with a game share, % contested pairs; the service check: % directions checked, % mismatches',
    runs, n_routes, n_dir, n_hist, n_market, worst, n_gs, n_mk, n_cont, coalesce(e ->> 'checked', '0'), jsonb_array_length(e -> 'mismatches');
end
$test$;

-- ---------------------------------------------------------------- 3. the hand-made world
do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; gr bigint; mp bigint; ra bigint; rb bigint; m1 bigint; r1 bigint; r2 bigint; r3 bigint;
  rot1 bigint; rot2 bigint; rot3 bigint; s1 bigint; s2 bigint; dd date;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'market pages planner test', true);
  insert into public.airports (code, utc_offset) select c, 0 from unnest(array['QM1', 'QM2', 'QM3', 'QM4']) c
  on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('market pages planner test', 'market-pages-planner.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s where s.world_id = dw and s.airline_id is null;
  insert into public.world_rules (world_id, key, value, kind, unit, description)
  select w, r.key, r.value, r.kind, r.unit, r.description from public.world_rules r where r.world_id = dw;
  -- the shared service profiles, as manual §4 has them: S1 under 800 km, S2 to 1,500, S3 beyond
  insert into public.service_profiles (world_id, airline_id, code, up_to_km) values (w, null, 'S1', 800), (w, null, 'S2', 1500), (w, null, 'S3', 99999);
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.groups (world_id, name, kind) values (w, 'rivals', 'rival') returning id into gr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, game_name, iata_code, home_airport_code, active, position)
  values (w, g, 990901, 'Market Planner', 'Market Air', 'Market Air', 'MP', 'QM1', true, 1) returning id into mp;
  insert into public.airlines (world_id, group_id, game_id, game_name, iata_code, active) values (w, gr, 990951, 'Rival Alpha', 'RA', true) returning id into ra;
  insert into public.airlines (world_id, group_id, game_id, game_name, iata_code, active) values (w, gr, 990952, 'Rival Beta', 'RB', true) returning id into rb;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, mp, 'QM1', 'hub', true, 1);
  insert into public.markets (world_id, airline_id, name, layout) values (w, mp, 'Planner test market', 'Leisure') returning id into m1;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, city, distance_km, stars, market_id, source) values
    (w, mp, 'QM1', 'QM2', 'Two City', 1000, 4, m1, 'research') returning id into r1;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, city, distance_km, stars, market_id, source) values
    (w, mp, 'QM1', 'QM3', 'Three City', 500, 3, m1, 'research') returning id into r2;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, city, distance_km, stars, market_id, source) values
    (w, mp, 'QM1', 'QM4', 'Four City', 2000, 3, m1, 'research') returning id into r3;
  -- QM1–QM2 daily both ways on S2; QM1–QM3 daily on S1 and a second rotation, days 1, set S3 in the planner
  insert into public.rotations (world_id, airline_id, route_id, launched_on, service_code) values (w, mp, r1, date '2030-03-01', 'S2') returning id into rot1;
  insert into public.rotations (world_id, airline_id, route_id, launched_on, service_code) values (w, mp, r2, date '2030-03-01', 'S1') returning id into rot2;
  insert into public.rotations (world_id, airline_id, route_id, launched_on, service_code) values (w, mp, r2, date '2030-03-10', 'S3') returning id into rot3;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min) values
    (w, mp, rot1, 1, 201, 'QM1', 'QM2', '{1,2,3,4,5,6,7}', 360, 120), (w, mp, rot1, 2, 202, 'QM2', 'QM1', '{1,2,3,4,5,6,7}', 600, 120),
    (w, mp, rot2, 1, 301, 'QM1', 'QM3', '{1,2,3,4,5,6,7}', 420, 60), (w, mp, rot2, 2, 302, 'QM3', 'QM1', '{1,2,3,4,5,6,7}', 540, 60),
    (w, mp, rot3, 1, 303, 'QM1', 'QM3', '{1}', 900, 60), (w, mp, rot3, 2, 304, 'QM3', 'QM1', '{1}', 1020, 60);
  -- the daily history, 2 to 15 Mar: out 150 of 168 in economy, back 120 of 168; business 10 of 12 out, 6 of 12 back
  for dd in select generate_series(date '2030-03-02', date '2030-03-15', interval '1 day')::date loop
    insert into public.route_days (world_id, airline_id, route_id, origin_code, dest_code, day, flights, passengers, seats, eco_pax, eco_seats, bus_pax, bus_seats)
    values (w, mp, r1, 'QM1', 'QM2', dd, 1, 160, 180, 150, 168, 10, 12), (w, mp, r1, 'QM2', 'QM1', dd, 1, 126, 180, 120, 168, 6, 12);
  end loop;
  -- two finished scans: on 5 Mar Rival Alpha 7 a week on QM1–QM2; on 12 Mar Rival Alpha 14 and Rival Beta 7; ours daily
  -- both ways in each
  insert into public.game_scans (world_id, taken_at, status) values (w, timestamptz '2030-03-05 08:00:00+00', 'done') returning id into s1;
  insert into public.game_scans (world_id, taken_at, status) values (w, timestamptz '2030-03-12 08:00:00+00', 'done') returning id into s2;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
    (s1, w, mp, '[["MP", 201, "QM1", "QM2", "1234567", "06:00", "08:00", "320", ""], ["MP", 202, "QM2", "QM1", "1234567", "10:00", "12:00", "320", ""]]'),
    (s1, w, ra, '[["RA", 1, "QM1", "QM2", "1234567", "07:00", "09:00", "320", ""]]'),
    (s1, w, rb, '[]'),
    (s2, w, mp, '[["MP", 201, "QM1", "QM2", "1234567", "06:00", "08:00", "320", ""], ["MP", 202, "QM2", "QM1", "1234567", "10:00", "12:00", "320", ""]]'),
    (s2, w, ra, '[["RA", 1, "QM1", "QM2", "1234567", "07:00", "09:00", "320", ""], ["RA", 2, "QM2", "QM1", "1234567", "11:00", "13:00", "320", ""]]'),
    (s2, w, rb, '[["RB", 1, "QM2", "QM1", "1234567", "12:00", "14:00", "320", ""]]');
  insert into public.capture_keys (label, key_hash, world_id)
  values ('market pages planner test', extensions.crypt('market-pages-planner-test-key', extensions.gen_salt('bf')), w);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_mp values ('w', to_jsonb(w)), ('mp', to_jsonb(mp)), ('ra', to_jsonb(ra)), ('rb', to_jsonb(rb)), ('r1', to_jsonb(r1)),
                          ('r2', to_jsonb(r2)), ('r3', to_jsonb(r3)), ('t', to_jsonb(timestamptz '2030-03-15 12:00:00+00'));
end
$setup$;

-- 3a. before any finished run: nothing from the market pages, and nothing errors
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mp where k = 'w'); mp bigint := (select (v #>> '{}')::bigint from t_mp where k = 'mp');
  r1 bigint := (select (v #>> '{}')::bigint from t_mp where k = 'r1'); t timestamptz := (select (v #>> '{}')::timestamptz from t_mp where k = 't');
  d jsonb; c jsonb; e jsonb;
begin
  d := private.fig_route_story(r1, t);
  assert d -> 'market' = 'null'::jsonb, 'with no read, route_story()''s market isn''t null: ' || (d -> 'market')::text;
  c := private.fig_competition(mp, t, 0);
  assert c -> 'market_run' = 'null'::jsonb and (c #> '{markets,0}') ? 'game_share' and c #> '{markets,0,game_share}' = 'null'::jsonb,
    'with no read, competition() has a market run or a game share: ' || (c -> 'markets')::text;
  assert jsonb_array_length(c -> 'contested') = 1 and c #> '{contested,0,market}' = 'null'::jsonb,
    'with no read, contested isn''t QM1–QM2 alone with no market figures: ' || (c -> 'contested')::text;
  e := private.fig_market_service_checks(w, null, t);
  assert e -> 'run' = 'null'::jsonb and (e ->> 'checked')::int = 0 and e -> 'mismatches' = '[]'::jsonb,
    'with no finished run, the service check isn''t empty: ' || e::text;
  raise notice 'before any finished market run: route_story()''s market null, competition()''s game_share and market_run null (contested QM1–QM2 without market figures), the service check''s run null with nothing checked';
end
$test$;

-- 3b. a run, as the capture sends it (signed out, with the capture key): four pages, then finish
set local role anon;
do $test$
declare v_key text := 'market-pages-planner-test-key'; r jsonb; run bigint;
  base jsonb := '{"airline": 990901, "ok": true, "week": "2030-11", "previous_week": "2030-10"}'::jsonb;
begin
  r := public.capture_market(v_key, 'start', '{"version": "1.9", "total": 4}');
  run := (r ->> 'run_id')::bigint;
  assert r ->> 'ok' = 'true', 'start refused: ' || r::text;
  -- QM1→QM2: S2 as the distance says; MP 100, Rival Alpha 120 (business 300), Rival Beta 90; shares Alpha 60, MP 30 (−2), Beta 10
  r := public.capture_market(v_key, 'page', base || jsonb_build_object('run_id', run, 'origin', 'QM1', 'dest', 'QM2', 'service', '{"code": "S2", "game_id": 412}'::jsonb,
         'fares', '[{"code": "MP", "cls": "Y", "flights": 7, "low": 100, "avg": 100, "high": 100, "finished": 2, "sold_out": 1},
                    {"code": "RA", "cls": "Y", "flights": 14, "low": 110, "avg": 120, "high": 130, "finished": 4, "sold_out": 4},
                    {"code": "RA", "cls": "C", "flights": 14, "low": 300, "avg": 300, "high": 300, "finished": 4, "sold_out": 0},
                    {"code": "RB", "cls": "Y", "flights": 7, "low": 90, "avg": 90, "high": 90, "finished": 2, "sold_out": 0}]'::jsonb,
         'shares', '[{"kind": "passengers", "enterprise_id": 990951, "name": "Rival Alpha", "share": 60, "change": 5},
                     {"kind": "passengers", "enterprise_id": 990901, "name": "Market Air", "share": 30, "change": -2},
                     {"kind": "passengers", "enterprise_id": 990952, "name": "Rival Beta", "share": 10, "change": -3},
                     {"kind": "cargo", "enterprise_id": 990951, "name": "Rival Alpha", "share": 100, "change": 0}]'::jsonb,
         'weeks', '[{"week": "2030-10", "seats": 1000, "price": 110}, {"week": "2030-11", "seats": 1200, "price": 112}]'::jsonb));
  assert r ->> 'ok' = 'true', 'QM1→QM2 refused: ' || r::text;
  -- QM2→QM1: S1 in the game, where the distance calls for S2; MP 105, Rival Alpha 115; shares 50 and 50
  r := public.capture_market(v_key, 'page', base || jsonb_build_object('run_id', run, 'origin', 'QM2', 'dest', 'QM1', 'service', '{"code": "S1", "game_id": 411}'::jsonb,
         'fares', '[{"code": "MP", "cls": "Y", "flights": 7, "low": 105, "avg": 105, "high": 105, "finished": 2, "sold_out": 0},
                    {"code": "RA", "cls": "Y", "flights": 7, "low": 115, "avg": 115, "high": 115, "finished": 2, "sold_out": 2}]'::jsonb,
         'shares', '[{"kind": "passengers", "enterprise_id": 990901, "name": "Market Air", "share": 50, "change": 0},
                     {"kind": "passengers", "enterprise_id": 990951, "name": "Rival Alpha", "share": 50, "change": 0}]'::jsonb,
         'weeks', '[{"week": "2030-11", "seats": 800, "price": 108}]'::jsonb));
  assert r ->> 'ok' = 'true', 'QM2→QM1 refused: ' || r::text;
  -- QM1–QM3 both ways: S1 as the distance says (the planner also has S3 there); no weeks
  r := public.capture_market(v_key, 'page', base || jsonb_build_object('run_id', run, 'origin', 'QM1', 'dest', 'QM3', 'service', '{"code": "S1", "game_id": 411}'::jsonb,
         'fares', '[{"code": "MP", "cls": "Y", "flights": 8, "low": 80, "avg": 80, "high": 80, "finished": 2, "sold_out": 0}]'::jsonb,
         'shares', '[{"kind": "passengers", "enterprise_id": 990901, "name": "Market Air", "share": 100, "change": 0}]'::jsonb, 'weeks', '[]'::jsonb));
  assert r ->> 'ok' = 'true', 'QM1→QM3 refused: ' || r::text;
  r := public.capture_market(v_key, 'page', base || jsonb_build_object('run_id', run, 'origin', 'QM3', 'dest', 'QM1', 'service', '{"code": "S1", "game_id": 411}'::jsonb,
         'fares', '[]'::jsonb, 'shares', '[]'::jsonb, 'weeks', '[]'::jsonb));
  assert r ->> 'ok' = 'true', 'QM3→QM1 refused: ' || r::text;
  r := public.capture_market(v_key, 'finish', jsonb_build_object('run_id', run));
  assert r ->> 'ok' = 'true', 'finish refused: ' || r::text;
  insert into t_mp values ('run', to_jsonb(run));
end
$test$;
reset role;

-- 3c. the service check
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mp where k = 'w'); mp bigint := (select (v #>> '{}')::bigint from t_mp where k = 'mp');
  r1 bigint := (select (v #>> '{}')::bigint from t_mp where k = 'r1'); r2 bigint := (select (v #>> '{}')::bigint from t_mp where k = 'r2');
  run bigint := (select (v #>> '{}')::bigint from t_mp where k = 'run'); t timestamptz := (select (v #>> '{}')::timestamptz from t_mp where k = 't');
  e jsonb; got text;
begin
  e := private.fig_market_service_checks(w, null, now());
  insert into t_mp values ('checks', e);
  assert (e #>> '{run,id}')::bigint = run and (e #>> '{run,pages_read}')::int = 4 and (e #>> '{run,pages_failed}')::int = 0 and (e ->> 'checked')::int = 4,
    'the check didn''t look at the run''s four pages: ' || (e - 'notes')::text;
  select string_agg(format('%s %s>%s %s game %s distance %s planner %s route %s', x ->> 'kind', x ->> 'from', x ->> 'to', x ->> 'direction',
                           coalesce(x ->> 'game_code', '-'), coalesce(x ->> 'distance_code', '-'), x ->> 'planner_codes',
                           case (x ->> 'route_id')::bigint when r1 then 'r1' when r2 then 'r2' else '?' end), ' | ' order by i) into got
    from jsonb_array_elements(e -> 'mismatches') with ordinality y(x, i);
  assert got = 'distance QM2>QM1 back game S1 distance S2 planner ["S2"] route r1'
            || ' | planner QM1>QM3 out game S1 distance S1 planner ["S1", "S3"] route r2'
            || ' | planner QM3>QM1 back game S1 distance S1 planner ["S1", "S3"] route r2',
    E'the mismatches aren''t QM2→QM1 against the distance, then QM1–QM3 both ways against the planner''s S3:\n' || coalesce(got, 'none');
  assert (select (x ->> 'off_planner')::boolean and (x ->> 'distance_km')::int = 1000 and x ->> 'code' = 'MP' and x ->> 'hub' = 'QM1' and x ->> 'dest' = 'QM2'
            from jsonb_array_elements(e -> 'mismatches') x where x ->> 'kind' = 'distance'),
    'the distance row doesn''t carry the planner''s difference too, its 1,000 km, the airline and the route';
  -- one airline's own: the same; another airline's: none; as of before the run: nothing
  assert private.fig_market_service_checks(w, mp, now()) -> 'mismatches' = e -> 'mismatches', 'the airline''s own check differs from the world''s';
  assert private.fig_market_service_checks(w, (select (v #>> '{}')::bigint from t_mp where k = 'ra'), now()) -> 'mismatches' = '[]'::jsonb,
    'a rival''s check found something';
  assert private.fig_market_service_checks(w, null, now() - interval '1 day') -> 'run' = 'null'::jsonb, 'as of the day before, the run counts';
  raise notice 'the service check on the run''s four pages: QM2→QM1 set S1 in the game against the S2 its 1,000 km calls for (first), then QM1–QM3 both ways set S1 against the planner''s S1 and S3; one airline''s own the same, a rival''s none, and none as of before the run';
end
$test$;

-- 3d. route_story()'s new keys
do $test$
declare r1 bigint := (select (v #>> '{}')::bigint from t_mp where k = 'r1'); r3 bigint := (select (v #>> '{}')::bigint from t_mp where k = 'r3');
  run bigint := (select (v #>> '{}')::bigint from t_mp where k = 'run'); t timestamptz := (select (v #>> '{}')::timestamptz from t_mp where k = 't');
  d jsonb; x jsonb; got text;
begin
  -- as of 15 Mar 2030 (the hand-made world's days and scans), after the run (read now)
  d := private.fig_route_story(r1, greatest(t, now() + interval '1 hour'));
  assert jsonb_array_length(d -> 'days_by_direction') = 28, 'not 14 days both ways: ' || jsonb_array_length(d -> 'days_by_direction');
  x := d #> '{days_by_direction,0}';
  assert x ->> 'day' = '2030-03-02' and x ->> 'direction' = 'out' and (x ->> 'eco_pax')::int = 150 and (x ->> 'eco_seats')::int = 168
     and (x ->> 'eco_load_pct')::numeric = 89.3 and (x ->> 'bus_load_pct')::numeric = 83.3 and (x ->> 'flights')::int = 1,
    '2 Mar out isn''t 150 of 168 (89.3%), business 83.3%: ' || x::text;
  x := d #> '{days_by_direction,1}';
  assert x ->> 'direction' = 'back' and (x ->> 'eco_load_pct')::numeric = 71.4 and (x ->> 'bus_load_pct')::numeric = 50,
    '2 Mar back isn''t 71.4% and 50%: ' || x::text;
  -- rivals.history: at each scan since launch, ours and each rival
  select string_agg(format('%s: %s', left(h ->> 'taken_at', 10),
                           (select string_agg(format('%s %s%s', a ->> 'name', a ->> 'weekly', case when (a ->> 'ours')::boolean then ' ours' else '' end), ', ' order by j)
                              from jsonb_array_elements(h -> 'airlines') with ordinality z(a, j))), ' | ' order by i) into got
    from jsonb_array_elements(d #> '{rivals,history}') with ordinality y(h, i);
  assert got = '2030-03-05: Market Air 14 ours, Rival Alpha 7 | 2030-03-12: Market Air 14 ours, Rival Alpha 14, Rival Beta 7',
    'rivals.history isn''t ours then each rival at each scan: ' || coalesce(got, 'none');
  -- the market: both directions of the run
  x := d -> 'market';
  assert (x #>> '{run,id}')::bigint = run and x #>> '{out,from}' = 'QM1' and x #>> '{back,from}' = 'QM2' and x #>> '{out,service_code}' = 'S2'
     and x #>> '{back,service_code}' = 'S1' and x #>> '{out,week}' = '2030-11',
    'the market isn''t the run''s two directions with their service codes: ' || left(x::text, 500);
  select string_agg(format('%s %s %s %s%s', f ->> 'code', f ->> 'name', f ->> 'class', trim_scale((f ->> 'avg')::numeric), case when (f ->> 'ours')::boolean then ' ours' else '' end), ', ' order by i)
    into got from jsonb_array_elements(x #> '{out,fares}') with ordinality y(f, i);
  assert got = 'MP Market Air Y 100 ours, RA Rival Alpha Y 120, RA Rival Alpha C 300, RB Rival Beta Y 90',
    'the out fares aren''t ours first, then each rival by class: ' || coalesce(got, 'none');
  select string_agg(format('%s %s %s %s', s ->> 'name', s ->> 'share', s ->> 'change', s ->> 'before'), ', ' order by i)
    into got from jsonb_array_elements(x #> '{out,shares}') with ordinality y(s, i);
  assert got = 'Rival Alpha 60.00 5.00 55.00, Market Air 30.00 -2.00 32.00, Rival Beta 10.00 -3.00 13.00',
    'the out passenger shares (cargo left out) aren''t Alpha 60, ours 30 (32 before), Beta 10: ' || coalesce(got, 'none');
  select string_agg(format('%s %s %s', k ->> 'direction', k ->> 'week', k ->> 'seats'), ', ' order by i)
    into got from jsonb_array_elements(x -> 'weeks') with ordinality y(k, i);
  assert got = 'out 2030-10 1000, out 2030-11 1200, back 2030-11 800', 'the weeks aren''t both directions by week: ' || coalesce(got, 'none');
  -- a route on the list no run read: no market
  assert private.fig_route_story(r3, greatest(t, now() + interval '1 hour')) -> 'market' = 'null'::jsonb, 'QM1–QM4, never read, has a market';
  raise notice 'route_story(): days_by_direction 14 days both ways (2 Mar out 89.3%%, back 71.4%%), rivals.history ours and each rival at both scans, market both directions of the run (service S2 out, S1 back; fares ours first; passenger shares with last week; the weeks both ways); a pair never read has none';
end
$test$;

-- 3e. competition(): the game's share and the contested pairs
do $test$
declare mp bigint := (select (v #>> '{}')::bigint from t_mp where k = 'mp'); run bigint := (select (v #>> '{}')::bigint from t_mp where k = 'run');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_mp where k = 't'); c jsonb; g jsonb; x jsonb; w bigint := (select (v #>> '{}')::bigint from t_mp where k = 'w');
begin
  c := private.fig_competition(mp, greatest(t, now() + interval '1 hour'), 0);
  assert (c #>> '{market_run,id}')::bigint = run, 'competition()''s market_run isn''t the run';
  g := c #> '{markets,0,game_share}';
  -- (30 × 1,200 + 50 × 800) ÷ 2,000 = 38; last week (32 × 1,200 + 50 × 800) ÷ 2,000 = 39.2; QM1–QM3 has no seats, so no weight
  assert (g ->> 'share')::numeric = 38 and (g ->> 'share_before')::numeric = 39.2 and (g ->> 'change')::numeric = -1.2
     and (g ->> 'pairs_read')::int = 2 and (g ->> 'pairs')::int = 3 and (g ->> 'seats')::int = 2000 and g ->> 'week' = '2030-11',
    'the game share isn''t 38% (39.2% last week), 2 of 3 pairs read, over 2,000 seats: ' || coalesce(g::text, 'none');
  -- the scan's share beside it, unchanged
  assert c #> '{markets,0}' ? 'share' and (c #>> '{markets,0,pairs}')::int = 3, 'the scan''s share went';
  -- contested: QM1–QM2 (Rival Alpha 14 against our 14); each way our fare against the cheapest rival's, and the share
  assert jsonb_array_length(c -> 'contested') = 1, 'contested isn''t QM1–QM2 alone: ' || (c -> 'contested')::text;
  x := c #> '{contested,0}';
  assert x ->> 'pair' = 'QM1-QM2' and x ->> 'hub' = 'QM1' and (x ->> 'ours')::int = 14 and x ->> 'rival' = 'Rival Alpha' and (x ->> 'rival_weekly')::int = 14,
    'the contested pair isn''t QM1–QM2, ours 14 against Rival Alpha 14: ' || x::text;
  assert (x #>> '{market,out,ours_eco}')::numeric = 100 and x #>> '{market,out,cheapest_rival,name}' = 'Rival Beta' and (x #>> '{market,out,cheapest_rival,eco}')::numeric = 90
     and (x #>> '{market,out,vs_cheapest_pct}')::numeric = 11.1 and (x #>> '{market,out,share}')::numeric = 30 and (x #>> '{market,out,share_before}')::numeric = 32
     and (x #>> '{market,back,ours_eco}')::numeric = 105 and x #>> '{market,back,cheapest_rival,name}' = 'Rival Alpha' and (x #>> '{market,back,vs_cheapest_pct}')::numeric = -8.7
     and (x #>> '{market,back,share}')::numeric = 50,
    'the contested pair''s fares and share each way aren''t out 100 against Beta''s 90 (+11.1%%), 30%% from 32%%; back 105 against Alpha''s 115 (−8.7%%), 50%%: ' || (x -> 'market')::text;
  -- the figures export carries them
  x := (select a from jsonb_array_elements(private.fig_export(w, greatest(t, now() + interval '1 hour')) -> 'airlines') a where (a ->> 'airline_id')::bigint = mp);
  assert x -> 'contested' = c -> 'contested' and x -> 'market_run' = c -> 'market_run', 'the figures export doesn''t carry contested and market_run as competition() gives them';
  raise notice 'competition(): game_share 38%% (39.2%% last week, −1.2 pts), 2 of 3 pairs read, weighted by 2,000 seats, beside the scan''s share; contested QM1–QM2 (Rival Alpha 14 against our 14): out 100 against Rival Beta''s 90 (+11.1%%), share 30%% from 32%%; back 105 against Rival Alpha''s 115 (−8.7%%), 50%%; the figures export carries contested and market_run';
end
$test$;

-- 3f. a later run that isn't finished changes nothing
set local role anon;
do $test$
declare r jsonb; run bigint;
begin
  -- the open run carried on within the hour would be the finished one's: a new start only after it is done, so start one
  r := public.capture_market('market-pages-planner-test-key', 'start', '{"version": "1.9", "total": 4}');
  run := (r ->> 'run_id')::bigint;
  r := public.capture_market('market-pages-planner-test-key', 'page', jsonb_build_object('run_id', run, 'airline', 990901, 'origin', 'QM1', 'dest', 'QM2', 'ok', true,
         'week', '2030-12', 'service', '{"code": "S3"}'::jsonb, 'fares', '[]'::jsonb, 'shares', '[]'::jsonb, 'weeks', '[]'::jsonb));
  assert r ->> 'ok' = 'true', 'the open run''s page was refused: ' || r::text;
end
$test$;
reset role;
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mp where k = 'w'); r1 bigint := (select (v #>> '{}')::bigint from t_mp where k = 'r1');
  t timestamptz := (select (v #>> '{}')::timestamptz from t_mp where k = 't');
begin
  assert private.fig_market_service_checks(w, null, now()) = (select v from t_mp where k = 'checks') - 'as_of' || jsonb_build_object('as_of', private.fig_ts(now())),
    'an open run changed the service check';
  assert private.fig_route_story(r1, greatest(t, now() + interval '1 hour')) #>> '{market,out,service_code}' = 'S2', 'an open run''s page reached route_story()';
  raise notice 'a later run that isn''t finished changes neither the service check nor the route story';
end
$test$;

-- ---------------------------------------------------------------- 4. who is refused; staff get what postgres gets
set local role anon;
do $test$
declare n int := 0;
begin
  begin perform public.market_service_checks(); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'signed out, market_service_checks() wasn''t refused';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "market-pages-planner-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare n int := 0;
begin
  begin perform public.market_service_checks((select (v #>> '{}')::bigint from t_mp where k = 'mp')); exception when insufficient_privilege then n := n + 1; end;
  assert n = 1, 'an account that isn''t staff wasn''t refused market_service_checks()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "market-pages-planner-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare mp bigint := (select (v #>> '{}')::bigint from t_mp where k = 'mp'); e jsonb;
begin
  e := public.market_service_checks(mp, now());
  assert e -> 'mismatches' = (select v -> 'mismatches' from t_mp where k = 'checks'), 'staff don''t get what postgres gets from market_service_checks()';
end
$test$;
reset role;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused market_service_checks(); staff get what postgres gets'; end $test$;

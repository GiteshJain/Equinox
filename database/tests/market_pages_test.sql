-- The market pages, part 1 (spec docs/specs/2026-10-30-market-pages.md; migration 20261030120000_market_pages.sql). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says which (codes, ids and counts of the hand-made world only, never rows
-- of the copy).
--   1. The objects: the five tables (RLS on, exactly one staff read rule, select for authenticated only, nothing for
--      anon, every column described, every foreign key indexed); capture_market() signed out and signed in, as owner with
--      an empty search path and a 30-second limit, described, not open to public; capture_airlines() and system_status()
--      called as before; the four internal functions closed, described; market_every_days 7 in every world, described.
--   2. On the copy: Gander's capture_airlines() with a key of its own, signed out: the market part as the copy's routes and
--      the setting say (counts only).
--   3. A world of its own with its own key: our Ryanair (game id 112, FR) flying DUB–AMS and DUB–BCN (with rotations),
--      a route without rotations and a removed one (not listed), our second airline on AMS–DUB too (listed once, under
--      the first); a finished world scan whose schedules give KL to one airline and EI to two. No finished run: due, the
--      four pages in order.
--   4. A run, signed out: start; a second start carried on; the saved page's figures (DUB→AMS, 30 Oct, as
--      tests/capture_market_test.mjs makes them) give the expected read (week 2026-44, service R 318), fares (KL by the
--      scan, FR by the share list's airline with that code, EI unmatched with its prefix kept), shares (KLM and Aer Lingus
--      added to airlines, logged as capture) and weeks; a failed page; the open run's pages left out of capture_airlines();
--      finish refused at 50% failed; the failed page sent again ok replaces it; finish. Refused, writing nothing: a wrong
--      key, a bad kind, a run of another world, an airline that isn't ours, figures that don't read, a page after the finish.
--   5. Due and not due by market_every_days (7, 1, 0 and none) as the run ages by capture days; a later read of a week wins
--      in market_weeks, an earlier one doesn't; a run left open over an hour stopped by the next start, with its note.
--   6. system_status()'s market line; staff read the tables, signed in without being staff sees nothing, signed out is
--      refused.
--   7. The archive: market_reads, market_fares and market_shares by their read's time, one month kept; the reads after
--      their fares and shares (archive_due's order, and archive_delete refuses reads still pointed at); manifests and
--      deletes; market_runs and market_weeks left alone.

create temporary table t_mk (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_mk to anon, authenticated;

-- the saved page's figures (tests/fixtures/market_DUBAMS_2026-10-30.html), as capture 1.9 sends them, without the run
insert into t_mk values ('page', '{"airline": 112, "origin": "DUB", "dest": "AMS", "ok": true, "week": "2026-44", "previous_week": "2026-43", "service": {"code": "R", "game_id": 318}, "fares": [{"code": "KL", "cls": "Y", "flights": 31, "low": 120, "avg": 120, "high": 120, "finished": 12, "sold_out": 12}, {"code": "KL", "cls": "C", "flights": 31, "low": 245, "avg": 245, "high": 245, "finished": 12, "sold_out": 12}, {"code": "KL", "cls": "Cargo", "flights": 31, "low": 91, "avg": 91, "high": 91, "finished": 12, "sold_out": 12}, {"code": "EI", "cls": "Y", "flights": 15, "low": 156, "avg": 156, "high": 156, "finished": 6, "sold_out": 1}, {"code": "EI", "cls": "C", "flights": 15, "low": 319, "avg": 319, "high": 319, "finished": 6, "sold_out": 6}, {"code": "EI", "cls": "F", "flights": 15, "low": 457, "avg": 457, "high": 457, "finished": 6, "sold_out": 6}, {"code": "EI", "cls": "Cargo", "flights": 15, "low": 100, "avg": 100, "high": 100, "finished": 6, "sold_out": 1}, {"code": "FR", "cls": "Y", "flights": 5, "low": 102, "avg": 102, "high": 102, "finished": 2, "sold_out": 2}, {"code": "FR", "cls": "Cargo", "flights": 5, "low": 91, "avg": 91, "high": 91, "finished": 2, "sold_out": 0}], "shares": [{"kind": "passengers", "enterprise_id": 157, "name": "KLM Royal Dutch Airlines", "share": 68.46, "change": -10.32}, {"kind": "passengers", "enterprise_id": 174, "name": "Aer Lingus", "share": 24.61, "change": 11.37}, {"kind": "passengers", "enterprise_id": 112, "name": "Ryanair", "share": 6.94, "change": -1.05}, {"kind": "cargo", "enterprise_id": 157, "name": "KLM Royal Dutch Airlines", "share": 58.27, "change": -11.81}, {"kind": "cargo", "enterprise_id": 174, "name": "Aer Lingus", "share": 31.65, "change": 13.85}, {"kind": "cargo", "enterprise_id": 112, "name": "Ryanair", "share": 10.07, "change": -2.04}], "weeks": [{"week": "2026-36", "seats": 546, "price": 120}, {"week": "2026-37", "seats": 7692, "price": 120}, {"week": "2026-38", "seats": 7956, "price": 120}, {"week": "2026-39", "seats": 7956, "price": 120}, {"week": "2026-40", "seats": 8576, "price": 119}, {"week": "2026-41", "seats": 9220, "price": 119}, {"week": "2026-42", "seats": 9616, "price": 120}, {"week": "2026-43", "seats": 9616, "price": 122}, {"week": "2026-44", "seats": 6268, "price": 125}]}'::jsonb);

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare t text; bad text; r text; p text; g text; f text := 'public.capture_market(text, text, jsonb)';
begin
  foreach t in array array['market_runs', 'market_reads', 'market_fares', 'market_shares', 'market_weeks'] loop
    assert (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass), t || ' has no RLS';
    assert (select count(*) from pg_policies where schemaname = 'public' and tablename = t) = 1
       and exists (select 1 from pg_policies where schemaname = 'public' and tablename = t and policyname = 'staff read'
                      and cmd = 'SELECT' and roles = '{authenticated}' and qual like '%is_planner_user%'),
      t || ' should have exactly one rule: staff read (select for authenticated, is_planner_user())';
    foreach r in array array['anon', 'authenticated'] loop
      foreach p in array array['insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        assert not has_table_privilege(r, 'public.' || t, p), r || ' has ' || p || ' on ' || t;
      end loop;
    end loop;
    assert not has_table_privilege('anon', 'public.' || t, 'select'), 'signed out can read ' || t;
    assert has_table_privilege('authenticated', 'public.' || t, 'select'), 'staff can''t read ' || t;
    assert length(coalesce(obj_description(('public.' || t)::regclass, 'pg_class'), '')) > 200, t || ' has no description';
    select string_agg(a.attname, ', ') into bad from pg_attribute a
     where a.attrelid = ('public.' || t)::regclass and a.attnum > 0 and not a.attisdropped
       and coalesce(col_description(a.attrelid, a.attnum), '') = '';
    assert bad is null, t || ' columns without a description: ' || bad;
    select string_agg(x.conname, ', ') into bad from pg_constraint x
     where x.conrelid = ('public.' || t)::regclass and x.contype = 'f'
       and not exists (select 1 from pg_index i where i.indrelid = x.conrelid and i.indkey[0] = x.conkey[1]);
    assert bad is null, t || ' foreign keys without an index: ' || bad;
  end loop;
  -- capture_market(): signed out (the capture) and signed in, as owner, empty search path, 30 seconds
  assert (select p2.prosecdef and p2.provolatile = 'v' and coalesce('search_path=""' = any (p2.proconfig), false)
                 and coalesce('statement_timeout=30s' = any (p2.proconfig), false) from pg_proc p2 where p2.oid = f::regprocedure),
    f || ' doesn''t run as owner with an empty search path and a 30-second limit';
  assert has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute'), f || ' can''t be called by the capture';
  assert not exists (select 1 from pg_proc p2 cross join aclexplode(coalesce(p2.proacl, acldefault('f', p2.proowner))) a
                      where p2.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  -- the two it changes for the capture and the board, called as before
  assert (select p2.prosecdef and p2.provolatile = 's' and has_function_privilege('anon', p2.oid, 'execute') from pg_proc p2
           where p2.oid = 'public.capture_airlines(text)'::regprocedure), 'capture_airlines() isn''t callable as before';
  assert (select p2.prosecdef and not has_function_privilege('anon', p2.oid, 'execute') and has_function_privilege('authenticated', p2.oid, 'execute')
            from pg_proc p2 where p2.oid = 'public.system_status(bigint, timestamptz)'::regprocedure), 'system_status() isn''t callable as before';
  -- the internal ones
  foreach g in array array['private.market_open(bigint, timestamptz)', 'private.market_stop_unfinished(bigint, timestamptz)',
                           'private.capture_market_plan(bigint, timestamptz)', 'private.market_ingest(bigint, text, jsonb)'] loop
    assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute'), g || ' can be called from outside';
    assert not exists (select 1 from pg_proc p2 cross join aclexplode(coalesce(p2.proacl, acldefault('f', p2.proowner))) a
                        where p2.oid = g::regprocedure and a.grantee = 0), g || ' is open to public';
    assert (select not p2.prosecdef and coalesce('search_path=""' = any (p2.proconfig), false) from pg_proc p2 where p2.oid = g::regprocedure),
      g || ' runs as owner or has no empty search path';
    assert obj_description(g::regprocedure, 'pg_proc') is not null, g || ' has no description';
  end loop;
  -- the setting
  assert not exists (select 1 from public.worlds w where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null
                       and s.key = 'market_every_days' and s.value = '7'::jsonb and s.unit = 'days' and length(coalesce(s.description, '')) > 100)),
    'a world has no described market_every_days setting of 7 days';
  raise notice 'market_runs, market_reads, market_fares, market_shares, market_weeks: RLS on, staff read only, columns described, foreign keys indexed; capture_market() signed out and in, as owner, 30 s; four internal functions closed; market_every_days 7 in every world';
end
$test$;

-- ---------------------------------------------------------------- 2. on the copy: Gander, as the capture calls it
insert into public.capture_keys (label, key_hash, world_id)
select 'market pages test, Gander', extensions.crypt('market-pages-gander-key', extensions.gen_salt('bf')), w.id
  from public.worlds w where w.is_default;
set local role anon;
do $test$
declare t0 timestamptz := clock_timestamp();
begin
  insert into t_mk values ('gander', public.capture_airlines('market-pages-gander-key')),
                          ('gander_ms', to_jsonb(round(extract(epoch from clock_timestamp() - t0) * 1000)));
end
$test$;
reset role;
do $test$
declare r jsonb := (select v from t_mk where k = 'gander'); dw bigint := (select id from public.worlds where is_default); n_pairs int; n_pages int; bad text;
begin
  assert r ->> 'ok' = 'true' and r ? 'scan_due' and r ? 'market_due', 'Gander''s capture_airlines() lacks its scan or market part: ' || left(r::text, 300);
  assert (r ->> 'market_every_days')::int = 7, 'Gander''s market_every_days isn''t 7';
  -- every pair our active airlines fly (routes with rotations, not removed), each once, both ways
  select count(*) into n_pairs from (
    select distinct least(rt.hub_code, rt.dest_code), greatest(rt.hub_code, rt.dest_code)
      from public.routes rt join public.airlines a on a.id = rt.airline_id join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where rt.world_id = dw and a.active and g.kind = 'ours' and not rt.removed and rt.hub_code <> rt.dest_code
       and exists (select 1 from public.rotations x where x.route_id = rt.id)) p;
  assert (r ->> 'market_total')::int = 2 * n_pairs, format('Gander: market_total %s, but our airlines fly %s pairs', r ->> 'market_total', n_pairs);
  select count(*) into n_pages from jsonb_array_elements(r -> 'market_pages') a cross join jsonb_array_elements(a -> 'pages') pg;
  assert n_pages = 2 * n_pairs, format('Gander: %s pages listed, %s pairs flown', n_pages, n_pairs);
  select string_agg(a ->> 'game_id', ', ') into bad from jsonb_array_elements(r -> 'market_pages') a
   where not exists (select 1 from jsonb_array_elements(r -> 'airlines') o where o ->> 'game_id' = a ->> 'game_id');
  assert bad is null, 'market pages listed under airlines the capture doesn''t capture: ' || bad;
  assert not exists (select 1 from jsonb_array_elements(r -> 'market_pages') a cross join jsonb_array_elements(a -> 'pages') pg
                      where pg ->> 0 !~ '^[A-Z0-9]{3}$' or pg ->> 1 !~ '^[A-Z0-9]{3}$' or pg ->> 0 = pg ->> 1), 'a page isn''t two airport codes';
  raise notice 'on the copy, Gander signed out: market pages due %, every % days, % pages (% pairs) under % airline(s), open run %; in % ms',
    r ->> 'market_due', r ->> 'market_every_days', n_pages, n_pairs, jsonb_array_length(r -> 'market_pages'), coalesce(r ->> 'market_open', 'none'),
    (select v from t_mk where k = 'gander_ms');
end
$test$;

-- ---------------------------------------------------------------- 3. a world of its own
do $setup$
declare dw bigint := (select id from public.worlds where is_default); w bigint; w2 bigint; g bigint; fr bigint; o2 bigint; kl bigint; e1 bigint; e2 bigint; s bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'market pages test', true);
  insert into public.airports (code, utc_offset) select c, 0 from unnest(array['DUB', 'AMS', 'BCN', 'ZM8', 'ZM9']) c on conflict (code) do nothing;
  insert into public.worlds (name, game_host, kind) values ('market pages test', 'market-pages.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s2.key, s2.value, s2.unit, s2.description from public.settings s2 where s2.world_id = dw and s2.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, game_name, iata_code, home_airport_code, active, position)
  values (w, g, 112, 'Market Test Ryanair', 'Ryanair', 'Ryanair', 'FR', 'DUB', true, 1) returning id into fr;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, game_name, iata_code, home_airport_code, active, position)
  values (w, g, 990812, 'Market Test Two', 'Two', 'Market Test Two', 'MT', 'AMS', true, 2) returning id into o2;
  -- Ryanair: DUB–AMS and DUB–BCN with rotations, DUB–ZM8 without, DUB–ZM9 removed; the second airline: AMS–DUB too
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, source, removed) values
    (w, fr, 'DUB', 'AMS', 750, 4, 'research', false), (w, fr, 'DUB', 'BCN', 1480, 4, 'research', false),
    (w, fr, 'DUB', 'ZM8', 500, 3, 'research', false), (w, fr, 'DUB', 'ZM9', 500, 3, 'research', true),
    (w, o2, 'AMS', 'DUB', 750, 4, 'research', false);
  insert into public.rotations (world_id, airline_id, route_id, launched_on)
  select w, x.airline_id, x.id, date '2026-10-01' from public.routes x where x.world_id = w and x.dest_code in ('AMS', 'BCN', 'ZM9', 'DUB');
  -- a finished world scan: KLM flies KL; two airlines fly EI (so EI tells no airline)
  insert into public.airlines (world_id, game_id, game_name) values (w, 990857, 'Scan KLM') returning id into kl;
  insert into public.airlines (world_id, game_id, game_name) values (w, 990874, 'Scan EI one') returning id into e1;
  insert into public.airlines (world_id, game_id, game_name) values (w, 990875, 'Scan EI two') returning id into e2;
  insert into public.game_scans (world_id, taken_at, week, status, note) values (w, now() - interval '2 days', '44', 'done', 'market pages test') returning id into s;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
    (s, w, kl, '[["KL", "8", "DUB", "AMS", "1234567", "04:35", "06:54", "32Q", ""]]'),
    (s, w, e1, '[["EI", "506", "DUB", "AMS", "1234567", "10:10", "12:29", "32Q", ""]]'),
    (s, w, e2, '[["EI", "603", "DUB", "AMS", "1234567", "13:10", "15:29", "32Q", ""]]');
  -- another world, with a run of its own
  insert into public.worlds (name, game_host, kind) values ('market pages test, other', 'market-pages-other.test', 'exclusive') returning id into w2;
  insert into public.market_runs (world_id, note) values (w2, 'market pages test, other world');
  insert into public.capture_keys (label, key_hash, world_id)
  values ('market pages test', extensions.crypt('market-pages-test-key', extensions.gen_salt('bf')), w);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  insert into t_mk values ('w', to_jsonb(w)), ('w2', to_jsonb(w2)), ('fr', to_jsonb(fr)), ('kl', to_jsonb(kl)),
                          ('other_run', to_jsonb((select id from public.market_runs where world_id = w2))),
                          ('log_from', to_jsonb(coalesce((select max(id) from public.change_log), 0)));
end
$setup$;

set local role anon;
do $test$
declare r jsonb;
begin
  r := public.capture_airlines('market-pages-test-key');
  assert r ->> 'ok' = 'true' and r ->> 'world' = 'market pages test', 'the hand-made world''s key didn''t answer: ' || left(r::text, 300);
  assert (r ->> 'market_due')::boolean and r -> 'market_open' = 'null'::jsonb and r -> 'market_latest' = 'null'::jsonb
         and (r ->> 'market_every_days')::int = 7 and (r ->> 'market_total')::int = 4 and (r ->> 'market_done')::int = 0,
    'with no finished run, the market pages aren''t due as expected: ' || (r - 'airlines' - 'scan_airports')::text;
  assert r -> 'market_pages' = '[{"game_id": 112, "code": "FR", "name": "Market Test Ryanair", "game_name": "Ryanair", "pages": [["DUB", "AMS"], ["AMS", "DUB"], ["DUB", "BCN"], ["BCN", "DUB"]]}]'::jsonb,
    'the pages to read aren''t both directions of the two pairs flown, under the first airline: ' || (r -> 'market_pages')::text;
end
$test$;
reset role;

-- ---------------------------------------------------------------- 4. a run, signed out
set local role anon;
do $test$
declare v_key text := 'market-pages-test-key'; r jsonb; run bigint; p jsonb := (select v from t_mk where k = 'page');
  other bigint := (select (v #>> '{}')::bigint from t_mk where k = 'other_run');
begin
  -- refused: a wrong key, a bad kind
  assert public.capture_market('not the key', 'start', '{}') = '{"ok": false, "error": "bad key"}'::jsonb, 'a wrong key wasn''t refused';
  assert public.capture_market(null, 'start', '{}') = '{"ok": false, "error": "bad key"}'::jsonb, 'a missing key wasn''t refused';
  assert public.capture_market(v_key, 'markets', '{}') = '{"ok": false, "error": "bad kind"}'::jsonb, 'a bad kind wasn''t refused';
  -- start, and a second start within the hour carried on
  r := public.capture_market(v_key, 'start', '{"version": "1.9", "total": 4, "note": "Capture all airlines 1.9"}');
  run := (r ->> 'run_id')::bigint;
  assert r = jsonb_build_object('ok', true, 'run_id', run, 'carried_on', false), 'start didn''t start a run: ' || r::text;
  assert public.capture_market(v_key, 'start', '{"version": "1.9"}') = jsonb_build_object('ok', true, 'run_id', run, 'carried_on', true),
    'a second start within the hour didn''t carry on with the same run';
  -- the saved page
  r := public.capture_market(v_key, 'page', p || jsonb_build_object('run_id', run));
  assert r ->> 'ok' = 'true' and (r ->> 'fares')::int = 9 and (r ->> 'shares')::int = 6 and (r ->> 'weeks')::int = 9
         and (r ->> 'pages_read')::int = 1 and (r ->> 'pages_failed')::int = 0 and (r ->> 'run_id')::bigint = run,
    'the saved page wasn''t stored as expected: ' || r::text;
  -- a page that didn't read
  r := public.capture_market(v_key, 'page', jsonb_build_object('run_id', run, 'airline', 112, 'origin', 'AMS', 'dest', 'DUB', 'ok', false,
                                                           'error', 'no Current Availability table on the page'));
  assert r ->> 'ok' = 'true' and (r ->> 'pages_failed')::int = 1 and (r ->> 'fares')::int = 0, 'a failed page wasn''t stored as failed: ' || r::text;
  -- refused, writing nothing: another world's run, an airline that isn't ours, figures that don't read
  r := public.capture_market(v_key, 'page', p || jsonb_build_object('run_id', other));
  assert r ->> 'ok' = 'false' and r ->> 'error' like 'no such market run in this capture key''s world%', 'another world''s run wasn''t refused: ' || r::text;
  r := public.capture_market(v_key, 'page', p || jsonb_build_object('run_id', run, 'airline', 990857, 'origin', 'DUB', 'dest', 'BCN'));
  assert r ->> 'ok' = 'false' and r ->> 'error' like 'airline 990857 isn''t one of ours%', 'a rival''s page wasn''t refused: ' || r::text;
  r := public.capture_market(v_key, 'page', p || jsonb_build_object('run_id', run, 'origin', 'DUB', 'dest', 'BCN',
                                                                'fares', '[{"code": "KL", "cls": "Q", "flights": 1}]'::jsonb));
  assert r ->> 'ok' = 'false' and r ->> 'error' like 'fares that don''t read: KL Q%', 'a fare that doesn''t read wasn''t refused: ' || r::text;
  r := public.capture_market(v_key, 'page', p || jsonb_build_object('run_id', run, 'origin', 'DUB', 'dest', 'BCN',
                                                                'shares', '[{"kind": "passengers", "enterprise_id": "x", "share": 1}]'::jsonb));
  assert r ->> 'ok' = 'false' and r ->> 'error' like 'shares that don''t read%', 'a share that doesn''t read wasn''t refused: ' || r::text;
  r := public.capture_market(v_key, 'page', '"just text"'::jsonb);
  assert r ->> 'ok' = 'false', 'a payload that isn''t an object wasn''t refused';
  -- the open run: its pages read are left out of capture_airlines()
  r := public.capture_airlines(v_key);
  assert (r ->> 'market_open')::bigint = run and (r ->> 'market_done')::int = 2 and (r ->> 'market_total')::int = 4
         and r -> 'market_pages' -> 0 -> 'pages' = '[["DUB", "BCN"], ["BCN", "DUB"]]'::jsonb,
    'the open run''s pages aren''t left out: ' || (r - 'airlines' - 'scan_airports')::text;
  -- finish refused at 50% failed; the failed page sent again ok replaces it; then finish
  r := public.capture_market(v_key, 'finish', jsonb_build_object('run_id', run));
  assert r ->> 'ok' = 'false' and r ->> 'error' like 'not finished: 1 of 2 pages failed%', 'a run with half its pages failed was finished: ' || r::text;
  r := public.capture_market(v_key, 'page', p || jsonb_build_object('run_id', run, 'origin', 'AMS', 'dest', 'DUB'));
  assert r ->> 'ok' = 'true' and (r ->> 'pages_read')::int = 2 and (r ->> 'pages_failed')::int = 0, 'the page sent again didn''t replace the failed one: ' || r::text;
  r := public.capture_market(v_key, 'finish', jsonb_build_object('run_id', run, 'note', '2 pages, 0 failed (Capture all airlines 1.9)'));
  assert r = jsonb_build_object('ok', true, 'run_id', run, 'pages_read', 2, 'pages_failed', 0), 'finish didn''t answer ok: ' || r::text;
  -- after the finish, nothing more for the run
  r := public.capture_market(v_key, 'page', p || jsonb_build_object('run_id', run, 'origin', 'DUB', 'dest', 'BCN'));
  assert r ->> 'ok' = 'false' and r ->> 'error' like '%is done, not open', 'a page for a finished run wasn''t refused: ' || r::text;
  insert into t_mk values ('run', to_jsonb(run));
end
$test$;
reset role;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mk where k = 'w'); run bigint := (select (v #>> '{}')::bigint from t_mk where k = 'run');
  fr bigint := (select (v #>> '{}')::bigint from t_mk where k = 'fr'); kl bigint := (select (v #>> '{}')::bigint from t_mk where k = 'kl');
  log_from bigint := (select (v #>> '{}')::bigint from t_mk where k = 'log_from'); rd bigint; got jsonb; x record;
begin
  select * into x from public.market_runs where id = run;
  assert x.world_id = w and x.status = 'done' and x.finished_at is not null and x.pages_read = 2 and x.pages_failed = 0 and x.pages_expected = 4
         and x.capture_version = '1.9' and x.note = '2 pages, 0 failed (Capture all airlines 1.9)',
    'the run isn''t done with its counts: ' || to_jsonb(x)::text;
  assert (select count(*) from public.market_runs where world_id = w) = 1, 'more than one run in the world';
  -- the reads: two, ok, the failed one replaced
  assert (select jsonb_agg(jsonb_build_array(m.origin, m.dest, m.ok, m.error, m.share_week, m.service_code, m.service_profile_game_id, m.airline_id = fr, m.world_id = w) order by m.origin)
            from public.market_reads m where m.run_id = run)
         = '[["AMS", "DUB", true, null, "2026-44", "R", 318, true, true], ["DUB", "AMS", true, null, "2026-44", "R", 318, true, true]]'::jsonb,
    'the reads aren''t as sent: ' || (select jsonb_agg(to_jsonb(m)) from public.market_reads m where m.run_id = run)::text;
  select m.id into rd from public.market_reads m where m.run_id = run and m.origin = 'DUB';
  -- the fares: KL by the scan, FR by the share list's airline with that code, EI unmatched (two airlines in the scan)
  select jsonb_agg(jsonb_build_array(f.airline_code, f.service_class, case when f.airline_id = kl then 'KLM' when f.airline_id = fr then 'ours' else f.airline_id::text end,
                                     f.flights, f.price_low, f.price_avg, f.price_high, f.finished, f.sold_out)
                   order by f.airline_code, array_position(array['Y', 'C', 'F', 'Cargo'], f.service_class)) into got
    from public.market_fares f where f.read_id = rd;
  assert got = '[["EI", "Y", null, 15, 156, 156, 156, 6, 1], ["EI", "C", null, 15, 319, 319, 319, 6, 6], ["EI", "F", null, 15, 457, 457, 457, 6, 6], ["EI", "Cargo", null, 15, 100, 100, 100, 6, 1],
                 ["FR", "Y", "ours", 5, 102, 102, 102, 2, 2], ["FR", "Cargo", "ours", 5, 91, 91, 91, 2, 0],
                 ["KL", "Y", "KLM", 31, 120, 120, 120, 12, 12], ["KL", "C", "KLM", 31, 245, 245, 245, 12, 12], ["KL", "Cargo", "KLM", 31, 91, 91, 91, 12, 12]]'::jsonb,
    'the fares aren''t as expected: ' || got::text;
  -- the shares, by the enterprises' game ids; KLM (157) and Aer Lingus (174) added to airlines, our Ryanair left as it is
  select jsonb_agg(jsonb_build_array(s.kind, a.game_id, s.week, s.share_pct, s.change_pts) order by s.kind desc, s.share_pct desc) into got
    from public.market_shares s join public.airlines a on a.id = s.airline_id where s.read_id = rd and a.world_id = w;
  assert got = '[["passengers", 157, "2026-44", 68.46, -10.32], ["passengers", 174, "2026-44", 24.61, 11.37], ["passengers", 112, "2026-44", 6.94, -1.05],
                 ["cargo", 157, "2026-44", 58.27, -11.81], ["cargo", 174, "2026-44", 31.65, 13.85], ["cargo", 112, "2026-44", 10.07, -2.04]]'::jsonb,
    'the shares aren''t as expected: ' || coalesce(got::text, 'none');
  assert (select jsonb_agg(jsonb_build_array(a.game_id, a.game_name, a.group_id is null) order by a.game_id) from public.airlines a where a.world_id = w and a.game_id in (157, 174))
         = '[[157, "KLM Royal Dutch Airlines", true], [174, "Aer Lingus", true]]'::jsonb, 'the unknown enterprises weren''t added to airlines';
  assert (select game_name from public.airlines where id = fr) = 'Ryanair', 'our airline''s name was changed';
  assert (select count(*) from public.change_log c where c.id > log_from and c.table_name = 'airlines' and c.op = 'insert' and c.actor = 'capture'
            and c.actor_detail = 'capture_market') = 2, 'the added airlines aren''t logged as the capture''s';
  -- the weeks: nine with figures, week 43 9,616 seats at 122, both directions
  assert (select count(*) from public.market_weeks k where k.world_id = w) = 18, 'the weeks aren''t nine each way';
  assert (select jsonb_build_array(k.seats, k.price_per_unit, k.run_id = run) from public.market_weeks k where k.world_id = w and k.origin = 'DUB' and k.dest = 'AMS' and k.week = '2026-43')
         = '[9616, 122, true]'::jsonb, 'week 43 isn''t 9,616 seats at 122 AS$';
  -- nothing written by the refused calls
  assert not exists (select 1 from public.market_reads m where m.run_id = run and m.dest = 'BCN'), 'a refused page was written';
  assert (select count(*) from public.market_runs r where r.world_id = (select (v #>> '{}')::bigint from t_mk where k = 'w2')) = 1
     and not exists (select 1 from public.market_reads m join public.market_runs r on r.id = m.run_id where r.world_id = (select (v #>> '{}')::bigint from t_mk where k = 'w2')),
    'the other world''s run was written to';
  raise notice 'a run signed out: start, carried on, the saved page (9 fares, 6 shares, 9 weeks), a failed page replaced, finish refused at 50%% failed then done; refusals wrote nothing';
end
$test$;

-- ---------------------------------------------------------------- 5. due and not due; the weeks; a run left open
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mk where k = 'w'); run bigint := (select (v #>> '{}')::bigint from t_mk where k = 'run');
  r jsonb; v_days int; t0 timestamptz; r2 bigint; x record;
begin
  -- just finished: not due, latest the run
  r := private.capture_market_plan(w, now());
  assert not (r ->> 'market_due')::boolean and (r #>> '{market_latest,id}')::bigint = run and r -> 'market_open' = 'null'::jsonb,
    'just after a finished run the market pages are due (or the run isn''t the latest): ' || (r - 'market_pages')::text;
  -- by capture days, as the run ages: 6 days not due, 7 due; market_every_days 1 due the next capture day; 0 and none never
  update public.market_runs set started_at = started_at - interval '6 days', finished_at = finished_at - interval '6 days' where id = run;
  v_days := private.capture_day(w, now()) - private.capture_day(w, (select finished_at from public.market_runs where id = run));
  assert (private.capture_market_plan(w, now()) ->> 'market_due')::boolean = (v_days >= 7), format('%s capture days old: due is wrong', v_days);
  update public.market_runs set started_at = started_at - interval '1 day', finished_at = finished_at - interval '1 day' where id = run;
  assert (private.capture_market_plan(w, now()) ->> 'market_due')::boolean, 'a run 7 days old isn''t due';
  update public.settings set value = '0'::jsonb where world_id = w and airline_id is null and key = 'market_every_days';
  assert not (private.capture_market_plan(w, now()) ->> 'market_due')::boolean, 'market_every_days 0 doesn''t switch it off';
  delete from public.settings where world_id = w and airline_id is null and key = 'market_every_days';
  r := private.capture_market_plan(w, now());
  assert not (r ->> 'market_due')::boolean and r -> 'market_every_days' = 'null'::jsonb, 'without the setting the market pages are due';
  insert into public.settings (world_id, airline_id, key, value, unit, description) values (w, null, 'market_every_days', '1', 'days', 'test');
  update public.market_runs set finished_at = now() - interval '1 day 1 hour', started_at = now() - interval '1 day 2 hours' where id = run;
  assert (private.capture_market_plan(w, now()) ->> 'market_due')::boolean = (private.capture_day(w, now()) > private.capture_day(w, now() - interval '1 day 1 hour')),
    'market_every_days 1 isn''t due the next capture day';
  update public.settings set value = '7'::jsonb where world_id = w and airline_id is null and key = 'market_every_days';

  -- a run left open: carried on within the hour, stopped by the next start after it, with its note
  insert into public.market_runs (world_id, started_at, pages_expected, note) values (w, now() - interval '30 minutes', 4, 'left open') returning id into r2;
  assert private.market_open(w, now()) = r2, 'a run started 30 minutes ago isn''t open';
  update public.market_runs set started_at = now() - interval '2 hours' where id = r2;
  assert private.market_open(w, now()) is null, 'a run started 2 hours ago is still open';
  t0 := now();
  insert into t_mk values ('stale', to_jsonb(r2));
end
$test$;

set local role anon;
do $test$
declare r jsonb; r2 bigint := (select (v #>> '{}')::bigint from t_mk where k = 'stale');
begin
  r := public.capture_market('market-pages-test-key', 'start', '{"version": "1.9", "total": 4}');
  assert r ->> 'ok' = 'true' and not (r ->> 'carried_on')::boolean and (r ->> 'run_id')::bigint <> r2, 'the start didn''t start a new run: ' || r::text;
  insert into t_mk values ('run2', r -> 'run_id');
end
$test$;
reset role;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mk where k = 'w'); r2 bigint := (select (v #>> '{}')::bigint from t_mk where k = 'stale');
  run2 bigint := (select (v #>> '{}')::bigint from t_mk where k = 'run2'); x record; p jsonb := (select v from t_mk where k = 'page'); res jsonb;
begin
  select * into x from public.market_runs where id = r2;
  assert x.status = 'stopped' and x.finished_at is null and x.note ~ '^stopped part-way after 0 of 4 pages, 0 failed \(marked \d\d \w{3} \d\d:\d\d UTC\) · left open$',
    'the run left open wasn''t stopped with its note: ' || to_jsonb(x)::text;
  -- the weeks: a later read wins, an earlier one doesn't
  res := private.market_ingest(w, 'page', p || jsonb_build_object('run_id', run2, 'weeks', '[{"week": "2026-43", "seats": 9700, "price": 123}, {"week": "2026-45", "seats": 0, "price": 0}]'::jsonb));
  assert (select jsonb_build_array(k.seats, k.price_per_unit, k.run_id = run2) from public.market_weeks k where k.world_id = w and k.origin = 'DUB' and k.dest = 'AMS' and k.week = '2026-43')
         = '[9700, 123, true]'::jsonb, 'a later read of week 43 didn''t win';
  assert not exists (select 1 from public.market_weeks k where k.world_id = w and k.week = '2026-45'), 'a week without figures was kept';
  update public.market_weeks set read_at = read_at + interval '1 hour' where world_id = w and origin = 'DUB' and dest = 'AMS' and week = '2026-43';
  res := private.market_ingest(w, 'page', p || jsonb_build_object('run_id', run2, 'weeks', '[{"week": "2026-43", "seats": 1, "price": 1}]'::jsonb));
  assert (select k.seats from public.market_weeks k where k.world_id = w and k.origin = 'DUB' and k.dest = 'AMS' and k.week = '2026-43') = 9700,
    'an earlier read of week 43 replaced a later one';
  raise notice 'due by capture days (7: not at 6, due at 7; 1 the next capture day; 0 and none never); a run left open over an hour stopped by the next start; market_weeks: the latest read wins';
end
$test$;

-- ---------------------------------------------------------------- 6. the Systems board; who reads the tables
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mk where k = 'w'); run bigint := (select (v #>> '{}')::bigint from t_mk where k = 'run'); d jsonb;
begin
  d := public.system_status(w);
  assert d ?& array['capture', 'snapshot', 'backup', 'archive', 'cleanup', 'scan', 'scan_stopped', 'usage', 'market'], 'system_status() lacks a part: ' || left(d::text, 300);
  assert (d #>> '{market,id}')::bigint = run and (d #>> '{market,pages_read}')::int = 2 and (d #>> '{market,pages_failed}')::int = 0
         and (d #>> '{market,age_days}')::numeric between 1 and 2 and d #>> '{market,finished_at}' ~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$',
    'system_status()''s market line isn''t the latest finished run: ' || (d -> 'market')::text;
  assert public.system_status(w, now() - interval '3 days') -> 'market' = 'null'::jsonb, 'before any finished run, system_status() has a market line';
  -- on the copy: Gander's line, whatever it is
  d := public.system_status();
  assert d ? 'market', 'Gander''s system_status() has no market part';
  raise notice 'system_status(): the market line, the latest finished run (Gander''s: %)', coalesce(d #>> '{market,id}', 'none yet');
end
$test$;

insert into public.planner_users (email) values ('market-staff@market-pages.test') on conflict do nothing;
do $$ begin perform set_config('request.jwt.claims', '{"email": "market-staff@market-pages.test", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare run bigint := (select (v #>> '{}')::bigint from t_mk where k = 'run');
begin
  assert public.is_planner_user(), 'the test account isn''t staff';
  assert exists (select 1 from public.market_runs where id = run) and (select count(*) from public.market_reads where run_id = run) = 2
     and exists (select 1 from public.market_fares f join public.market_reads m on m.id = f.read_id where m.run_id = run)
     and exists (select 1 from public.market_shares s join public.market_reads m on m.id = s.read_id where m.run_id = run)
     and exists (select 1 from public.market_weeks where run_id = run), 'staff don''t see the run''s rows';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '{"email": "not-staff@market-pages.test", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
begin
  assert (select count(*) from public.market_runs) = 0 and (select count(*) from public.market_reads) = 0 and (select count(*) from public.market_fares) = 0
     and (select count(*) from public.market_shares) = 0 and (select count(*) from public.market_weeks) = 0,
    'signed in without being staff, the market tables show rows';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
set local role anon;
do $test$
declare t text;
begin
  foreach t in array array['market_runs', 'market_reads', 'market_fares', 'market_shares', 'market_weeks'] loop
    begin
      execute format('select 1 from public.%I limit 1', t);
      raise exception 'signed out read %', t;
    exception when insufficient_privilege then null; end;
  end loop;
  raise notice 'staff read the market tables; signed in without being staff: no rows; signed out: refused';
end
$test$;
reset role;

-- ---------------------------------------------------------------- 7. the archive
set local timezone = 'UTC';
set local datestyle = 'ISO, YMD';
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_mk where k = 'w'); run bigint := (select (v #>> '{}')::bigint from t_mk where k = 'run');
  m date := (date_trunc('month', now() at time zone 'UTC') - interval '3 months')::date; rd_old bigint; mf jsonb; res jsonb; got text;
  n_weeks bigint; t text; n_now bigint;
begin
  assert (select string_agg(table_name || ':' || keep_months, ', ' order by table_name) from private.archive_tables() where table_name like 'market%')
         = 'market_fares:1, market_reads:1, market_shares:1', 'the archive doesn''t take the market detail after one month';
  assert not exists (select 1 from private.archive_tables() where table_name in ('market_runs', 'market_weeks')), 'the archive takes market_runs or market_weeks';
  -- the run's reads three months back (one read, its 9 fares and 6 shares; the other read stays this month)
  update public.market_reads set read_at = (m + 5)::timestamp at time zone 'UTC' where run_id = run and origin = 'DUB' returning id into rd_old;
  select count(*) into n_weeks from public.market_weeks where world_id = w;
  select string_agg(x.table_name || ':' || x.rows, ', ' order by x.ord) into got
    from (select d.*, row_number() over () as ord from private.archive_due() d) x
   where x.month = m and x.table_name like 'market%';
  assert got = 'market_fares:9, market_shares:6, market_reads:1', 'the market detail isn''t due as made, the reads last: ' || coalesce(got, 'none');
  -- the reads first: refused while their fares and shares point at them, deleting nothing
  mf := private.archive_manifest(m, 'market_reads');
  assert (mf ->> 'rows')::int = 1, 'the reads'' manifest doesn''t count one read';
  begin
    perform private.archive_delete(m, 'market_reads', (mf ->> 'rows')::bigint, mf ->> 'checksum');
    raise exception 'archive_delete took market_reads while its fares and shares point at it';
  exception when raise_exception then
    get stacked diagnostics got = message_text;
    assert got like 'archive_delete refused market_reads %: 15 market_fares or market_shares row(s) still point at these reads%', 'not the expected refusal: ' || got;
  end;
  assert exists (select 1 from public.market_reads where id = rd_old), 'the refused delete removed the read';
  -- then in archive_due's order: fares, shares, reads
  foreach t in array array['market_fares', 'market_shares', 'market_reads'] loop
    mf := private.archive_manifest(m, t);
    execute format('select count(*) from (%s) q', private.archive_select(m, t)) into n_now;
    assert n_now = (mf ->> 'rows')::bigint, t || ': the export query and the manifest disagree';
    res := private.archive_delete(m, t, (mf ->> 'rows')::bigint, mf ->> 'checksum');
    assert (res ->> 'deleted')::bigint = (mf ->> 'rows')::bigint, t || ': deleted another count than the manifest''s';
  end loop;
  assert not exists (select 1 from public.market_reads where id = rd_old) and not exists (select 1 from public.market_fares where read_id = rd_old)
     and not exists (select 1 from public.market_shares where read_id = rd_old), 'the old read''s detail is still there';
  assert (select count(*) from public.market_reads where run_id = run) = 1 and exists (select 1 from public.market_fares f join public.market_reads r on r.id = f.read_id where r.run_id = run),
    'the archive took the read of this month too';
  assert exists (select 1 from public.market_runs where id = run) and (select count(*) from public.market_weeks where world_id = w) = n_weeks,
    'the archive touched market_runs or market_weeks';
  raise notice 'the archive: % months back, market_fares 9, market_shares 6, then market_reads 1 (refused while pointed at); market_runs and market_weeks left alone', 3;
end
$test$;

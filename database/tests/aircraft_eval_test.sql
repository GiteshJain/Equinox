-- The aircraft evaluation script's run list and results (spec docs/specs/2026-10-27-aircraft-evaluation-script.md, the
-- Building chat's design; migration 20261027210000_aircraft_eval.sql). Run by database/rehearse.sh on the copy of last
-- night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an error
-- that says which (ids, codes and counts of the hand-made worlds only).
-- Two worlds of their own, made inside the test, each with its own capture key and the default world's
-- aircraft_eval_types: world 1 with four runs put on the list out of order (pass 2 seq 5, pass 1 seq 30, pass 1 seq 20,
-- pass 4 seq 1), world 2 with one.
--   1. The objects: both tables with RLS on and one staff read rule, nothing for anon, read only for authenticated,
--      described with every column, their foreign keys indexed; the setting in every world, the 17 types, described,
--      with since and reason; both functions as owner with an empty search path (the list stable), callable signed out
--      and signed in but not by everyone, described.
--   2. Signed out, as the userscript calls them: a bad key (wrong or missing) refused by both; world 1's list in pass,
--      seq order with the 17 types, total 4 and done 0; world 2's list only its own run.
--   3. A save: world 1's first run with the 17 types (the A350-900 as the tool showed it on 27 Oct, two that can't
--      operate) and one extra: ok, 18 rows, done 1 of 4, the run's names, settings and done_at written, the figures
--      as numbers and the cells as text; the list no longer has it.
--   4. A re-save: the same run with other figures and no extra type replaces its rows (17), done still 1, done_at moved.
--   5. Refused, nothing saved: a missing type, a figure that isn't a number, a figure for a type that can't operate, a
--      type twice, the wrong seat, no route names, no rows, world 2's run with world 1's key.
--   6. Signed in without being staff: no rows of either table; signed out: no table at all.
--   7. On the copy: the default world (Gander) has the 17 types, and its list answers with a key of its own.

create temporary table t_ae (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_ae to anon, authenticated;

-- one row of the result as the userscript sends it: a type that can operate with figures from a base (the A350-900's
-- of 27 Oct when base is 0, each figure plus base otherwise), or one that can't
create function pg_temp.ae_row(name text, can boolean, base numeric default 0) returns jsonb language sql as $f$
  select case when can then jsonb_build_object(
      'type_name', name, 'game_type_id', 3921, 'can_operate', true, 'message', null,
      'flights_week', 6.00 + base, 'seats', 377 + base, 'fuel', 64305 + base, 'handling', 631 + base, 'atc', 3014 + base,
      'landing', 1592 + base, 'maintenance', 11949 + base, 'capital', 116764 + base, 'crew', 5128 + base,
      'fixed_total', 203382 + base, 'per_seat', 539 + base,
      'profit_50', -30422 + base, 'profit_60', 4538 + base, 'profit_70', 38578 + base, 'profit_80', 73538 + base,
      'profit_90', 108498 + base, 'profit_100', 143458 + base,
      'margin_50', -17, 'margin_60', 2, 'margin_70', 16, 'margin_80', 26, 'margin_90', 34, 'margin_100', 41,
      'cells', jsonb_build_array(name, '6.00', '377', '64,305', '631', '3,014', '1,592', '11,949', '116,764', '5,128', '203,382',
                                 '539 AS$', '-30,422 (-17%)', '4,538 (2%)', '38,578 (16%)', '73,538 (26%)', '108,498 (34%)', '143,458 (41%)'))
    else jsonb_build_object('type_name', name, 'game_type_id', 3155, 'can_operate', false,
                            'message', 'This type cannot operate on the selected relation.',
                            'cells', jsonb_build_array(name, 'This type cannot operate on the selected relation.')) end
$f$;
-- a whole result: every type of the setting (the first two can't operate), plus any extra rows
create function pg_temp.ae_doc(types jsonb, seat text, base numeric default 0, extra jsonb default '[]'::jsonb) returns jsonb language sql as $f$
  select jsonb_build_object(
    'from_name', 'Test Field One', 'to_name', 'Test Field Two',
    'settings', jsonb_build_object('age', '0 year(s)', 'class', 'Economy', 'seat', seat, 'price_factor', '100%'),
    'rows', (select jsonb_agg(pg_temp.ae_row(t.n, t.i > 2, base) order by t.i)
               from jsonb_array_elements_text(types) with ordinality t(n, i)) || extra)
$f$;
grant execute on function pg_temp.ae_row(text, boolean, numeric), pg_temp.ae_doc(jsonb, text, numeric, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------- 1. the objects
do $test$
declare t text; bad text; r text; p text; f text; v jsonb;
begin
  foreach t in array array['aircraft_eval_runs', 'aircraft_eval_results'] loop
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
       and not exists (select 1 from pg_index i where i.indrelid = x.conrelid and i.indkey[0] = any (x.conkey));
    assert bad is null, t || ' foreign keys without an index: ' || bad;
  end loop;
  assert exists (select 1 from pg_constraint x where x.conrelid = 'public.aircraft_eval_runs'::regclass and x.contype = 'u'
                    and pg_get_constraintdef(x.oid) = 'UNIQUE (world_id, from_code, to_code, seat)'),
    'aircraft_eval_runs isn''t unique on world, from, to and seat';
  assert exists (select 1 from pg_constraint x where x.conrelid = 'public.aircraft_eval_runs'::regclass and x.contype = 'u'
                    and pg_get_constraintdef(x.oid) = 'UNIQUE (world_id, seq)'), 'aircraft_eval_runs'' seq isn''t unique in the world';
  assert exists (select 1 from pg_constraint x where x.conrelid = 'public.aircraft_eval_results'::regclass and x.contype = 'p'
                    and pg_get_constraintdef(x.oid) = 'PRIMARY KEY (run_id, type_name)'), 'aircraft_eval_results isn''t keyed on run and type';

  -- the setting: in every world, world-level, the 17 names, described with since and reason
  select string_agg(w.name, ', ') into bad from public.worlds w
   where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = 'aircraft_eval_types');
  assert bad is null, 'worlds without aircraft_eval_types: ' || bad;
  select s.value into v from public.settings s
   where s.world_id = (select id from public.worlds where is_default) and s.airline_id is null and s.key = 'aircraft_eval_types';
  assert v = '["Airbus A320NEO", "Airbus A320NEO Heavy", "Airbus A320NEO Light", "Airbus A320NEO SHARP", "Airbus A321LR",
               "Airbus A321NEO", "Airbus A321NEO Heavy", "Airbus A321NEO Light", "Airbus A321NEO Medium", "Airbus A321XLR",
               "Airbus A321XLR Heavy", "Airbus A321XLR Light", "Airbus A350-1000", "Airbus A350-900", "Airbus A350-900ULR",
               "Embraer 190 E2", "Embraer 195 E2"]'::jsonb, 'aircraft_eval_types isn''t the 17 types: ' || coalesce(v::text, 'none');
  assert not exists (select 1 from public.settings s where s.key = 'aircraft_eval_types'
                        and (length(coalesce(s.description, '')) < 100 or s.since is null or coalesce(s.reason, '') = '')),
    'aircraft_eval_types has no description, since or reason';

  foreach f in array array['public.capture_eval_runs(text)', 'public.capture_eval_result(text, bigint, jsonb)'] loop
    assert (select p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
      f || ' doesn''t run as owner with an empty search path';
    assert has_function_privilege('anon', f, 'execute'), 'signed out (the userscript), ' || f || ' can''t be called';
    assert has_function_privilege('authenticated', f, 'execute'), 'signed in, ' || f || ' can''t be called';
    assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                        where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
    assert length(coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 200, f || ' has no description';
  end loop;
  assert (select provolatile = 's' from pg_proc where oid = 'public.capture_eval_runs(text)'::regprocedure), 'capture_eval_runs() isn''t stable';
  raise notice 'aircraft_eval_runs and aircraft_eval_results: RLS with one staff read rule, staff read only, described; aircraft_eval_types in % worlds; both functions as owner, signed out and signed in',
    (select count(*) from public.worlds);
end
$test$;

-- ---------------------------------------------------------------- the hand-made worlds
do $setup$
declare dw bigint := (select id from public.worlds where is_default); w1 bigint; w2 bigint; r jsonb := '{}'::jsonb; x bigint;
begin
  insert into public.worlds (name, game_host, kind) values ('aircraft eval test', 'aircraft-eval.test', 'exclusive') returning id into w1;
  insert into public.worlds (name, game_host, kind) values ('aircraft eval other', 'aircraft-eval-other.test', 'exclusive') returning id into w2;
  insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
  select x.id, null, s.key, s.value, s.unit, s.description, s.since, s.reason from public.settings s cross join (values (w1), (w2)) x(id)
   where s.world_id = dw and s.airline_id is null and s.key = 'aircraft_eval_types'
  on conflict on constraint settings_world_airline_key_key do update set value = excluded.value;
  insert into public.capture_keys (label, key_hash, world_id) values
    ('aircraft eval test', extensions.crypt('aircraft-eval-test-key-1', extensions.gen_salt('bf')), w1),
    ('aircraft eval test, other world', extensions.crypt('aircraft-eval-test-key-2', extensions.gen_salt('bf')), w2);
  -- put on the list out of order, so pass and seq decide the order, not the id
  insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, distance_km, seat, note)
  values (w1, 2, 5, 'ZE3', 'ZE4', 4000, 'Leisure Plus', 'second region') returning id into x; r := r || jsonb_build_object('p2s5', x);
  insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, distance_km, seat)
  values (w1, 1, 30, 'ZE1', 'ZE5', 7000, 'Comfort') returning id into x; r := r || jsonb_build_object('p1s30', x);
  insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, distance_km, seat)
  values (w1, 1, 20, 'ZE1', 'ZE2', 1000, 'Leisure') returning id into x; r := r || jsonb_build_object('p1s20', x);
  insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, seat)
  values (w1, 4, 1, 'ZE6', 'ZE7', 'Standard') returning id into x; r := r || jsonb_build_object('p4s1', x);
  insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, seat)
  values (w2, 1, 1, 'ZE8', 'ZE9', 'Leisure') returning id into x; r := r || jsonb_build_object('w2', x);
  insert into t_ae values ('runs', r), ('types', (select value from public.settings where world_id = w1 and airline_id is null and key = 'aircraft_eval_types')),
                          ('w1', to_jsonb(w1));
  -- the list's checks refuse what the Scheduling chat mustn't write
  begin
    insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, seat) values (w1, 1, 99, 'ZE1', 'ZE2', 'Comfort Plus');
    raise exception 'a seat the list doesn''t know was taken';
  exception when check_violation then null; end;
  begin
    insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, seat) values (w1, 5, 99, 'ZE1', 'ZE2', 'Leisure');
    raise exception 'pass 5 was taken';
  exception when check_violation then null; end;
  begin
    insert into public.aircraft_eval_runs (world_id, pass, seq, from_code, to_code, seat) values (w1, 1, 98, 'ZE1', 'ZE2', 'Leisure');
    raise exception 'the same route and seat twice in a world was taken';
  exception when unique_violation then null; end;
end
$setup$;

-- ---------------------------------------------------------------- 2. the lists, signed out
set local role anon;
do $test$
declare r jsonb; ids jsonb := (select v from t_ae where k = 'runs'); types jsonb := (select v from t_ae where k = 'types');
begin
  foreach r in array array[public.capture_eval_runs('not the key'), public.capture_eval_runs(null),
                           public.capture_eval_result('not the key', (ids ->> 'p1s20')::bigint, '{}'::jsonb),
                           public.capture_eval_result(null, (ids ->> 'p1s20')::bigint, '{}'::jsonb)] loop
    assert r = '{"ok": false, "error": "bad key"}'::jsonb, 'a bad key wasn''t refused: ' || r::text;
  end loop;
  r := public.capture_eval_runs('aircraft-eval-test-key-1');
  assert r ->> 'ok' = 'true' and r ->> 'world' = 'aircraft eval test', 'world 1''s list didn''t answer: ' || r::text;
  assert r -> 'types' = types and jsonb_array_length(r -> 'types') = 17, 'world 1''s list doesn''t carry the 17 types';
  assert (r ->> 'total')::int = 4 and (r ->> 'done')::int = 0, 'world 1: total ' || (r ->> 'total') || ', done ' || (r ->> 'done');
  assert r -> 'runs' = jsonb_build_array(
      jsonb_build_object('id', (ids ->> 'p1s20')::bigint, 'pass', 1, 'seq', 20, 'from', 'ZE1', 'to', 'ZE2', 'seat', 'Leisure'),
      jsonb_build_object('id', (ids ->> 'p1s30')::bigint, 'pass', 1, 'seq', 30, 'from', 'ZE1', 'to', 'ZE5', 'seat', 'Comfort'),
      jsonb_build_object('id', (ids ->> 'p2s5')::bigint, 'pass', 2, 'seq', 5, 'from', 'ZE3', 'to', 'ZE4', 'seat', 'Leisure Plus'),
      jsonb_build_object('id', (ids ->> 'p4s1')::bigint, 'pass', 4, 'seq', 1, 'from', 'ZE6', 'to', 'ZE7', 'seat', 'Standard')),
    'world 1''s runs aren''t in pass, seq order: ' || (r -> 'runs')::text;
  r := public.capture_eval_runs('aircraft-eval-test-key-2');
  assert jsonb_array_length(r -> 'runs') = 1 and (r -> 'runs' -> 0 ->> 'id')::bigint = (ids ->> 'w2')::bigint and (r ->> 'total')::int = 1,
    'world 2''s list isn''t only its own run: ' || r::text;
  raise notice 'signed out: a bad key refused by both; world 1''s 4 runs in pass, seq order with the 17 types; world 2 only its own';
end
$test$;

-- ---------------------------------------------------------------- 3. a save
do $test$
declare r jsonb; ids jsonb := (select v from t_ae where k = 'runs'); types jsonb := (select v from t_ae where k = 'types');
  run bigint := (ids ->> 'p1s20')::bigint;
begin
  r := public.capture_eval_result('aircraft-eval-test-key-1', run,
         pg_temp.ae_doc(types, 'Leisure', 0, jsonb_build_array(pg_temp.ae_row('Boeing 737-8', true, 1))));
  assert r = jsonb_build_object('ok', true, 'run', run, 'saved', 18, 'done', 1, 'total', 4), 'the save didn''t answer as it should: ' || r::text;
  r := public.capture_eval_runs('aircraft-eval-test-key-1');
  assert (r ->> 'done')::int = 1 and jsonb_array_length(r -> 'runs') = 3 and not (r -> 'runs') @> jsonb_build_array(jsonb_build_object('id', run)),
    'the saved run is still on the list: ' || r::text;
  insert into t_ae values ('saved', r);
end
$test$;
reset role;

do $test$
declare ids jsonb := (select v from t_ae where k = 'runs'); run bigint := (ids ->> 'p1s20')::bigint; x record; n int;
begin
  select * into x from public.aircraft_eval_runs where id = run;
  assert x.from_name = 'Test Field One' and x.to_name = 'Test Field Two' and x.done_at is not null
     and x.settings = '{"age": "0 year(s)", "class": "Economy", "seat": "Leisure", "price_factor": "100%"}'::jsonb,
    'the run''s header wasn''t written';
  insert into t_ae values ('done_at', to_jsonb(x.done_at));
  select count(*) into n from public.aircraft_eval_results where run_id = run;
  assert n = 18, n || ' rows saved, not 18';
  select * into x from public.aircraft_eval_results where run_id = run and type_name = 'Airbus A320NEO SHARP';
  assert x.can_operate and x.game_type_id = 3921 and x.flights_week = 6.00 and x.seats = 377 and x.fuel = 64305 and x.handling = 631
     and x.atc = 3014 and x.landing = 1592 and x.maintenance = 11949 and x.capital = 116764 and x.crew = 5128
     and x.fixed_total = 203382 and x.per_seat = 539 and x.profit_50 = -30422 and x.profit_100 = 143458
     and x.margin_50 = -17 and x.margin_100 = 41 and x.message is null and x.cells ->> 11 = '539 AS$',
    'the figures weren''t saved as numbers, or the cells as text';
  select * into x from public.aircraft_eval_results where run_id = run and type_name = 'Airbus A320NEO';
  assert not x.can_operate and x.message = 'This type cannot operate on the selected relation.' and x.seats is null and x.profit_50 is null,
    'a type that can''t operate wasn''t saved as such';
  assert exists (select 1 from public.aircraft_eval_results where run_id = run and type_name = 'Boeing 737-8' and seats = 378),
    'the extra type wasn''t saved';
  raise notice 'a save: 18 rows (the 17 and one extra), figures as numbers, cells as text, the run''s names, settings and done_at';
end
$test$;

-- ---------------------------------------------------------------- 4. a re-save, and 5. what's refused
set local role anon;
do $test$
declare r jsonb; ids jsonb := (select v from t_ae where k = 'runs'); types jsonb := (select v from t_ae where k = 'types');
  run bigint := (ids ->> 'p1s20')::bigint; good jsonb; bad jsonb; why text;
begin
  r := public.capture_eval_result('aircraft-eval-test-key-1', run, pg_temp.ae_doc(types, 'Leisure', 10));
  assert r = jsonb_build_object('ok', true, 'run', run, 'saved', 17, 'done', 1, 'total', 4), 'the re-save didn''t answer as it should: ' || r::text;

  good := pg_temp.ae_doc(types, 'Comfort');
  run := (ids ->> 'p1s30')::bigint;
  foreach why in array array['missing', 'string', 'figure for cannot', 'twice', 'seat', 'names', 'no rows', 'other world'] loop
    bad := case why
      when 'missing' then jsonb_set(good, '{rows}', (good -> 'rows') - 13)   -- Airbus A350-900
      when 'string' then jsonb_set(good, '{rows,3,fuel}', '"64,305"')
      when 'figure for cannot' then jsonb_set(good, '{rows,0,seats}', '377')
      when 'twice' then jsonb_set(good, '{rows}', (good -> 'rows') || jsonb_build_array(good -> 'rows' -> 4))
      when 'seat' then jsonb_set(good, '{settings,seat}', '"Leisure"')
      when 'names' then good - 'to_name'
      when 'no rows' then good - 'rows'
      else good end;
    r := public.capture_eval_result('aircraft-eval-test-key-1', case when why = 'other world' then (ids ->> 'w2')::bigint else run end, bad);
    assert r ->> 'ok' = 'false', why || ' wasn''t refused: ' || r::text;
    assert r ->> 'error' ~ case why
      when 'missing' then '^the result has no row for Airbus A350-900$'
      when 'string' then '^not a number: Airbus A320NEO SHARP: fuel$'
      when 'figure for cannot' then '^a figure for a type that cannot operate: Airbus A320NEO: seats$'
      when 'twice' then '^a type twice in the result: Airbus A321LR$'
      when 'seat' then '^the result''s seat is Leisure, the run''s Comfort$'
      when 'names' then 'doesn''t name the route'
      when 'no rows' then '^the result has no rows$'
      else 'isn''t on this world''s run list$' end, why || ': ' || (r ->> 'error');
  end loop;
  r := public.capture_eval_runs('aircraft-eval-test-key-1');
  assert (r ->> 'done')::int = 1, 'a refused result was counted as done';
  raise notice 'a re-save replaced the run''s rows; 8 kinds of bad result refused, each saying why';
end
$test$;
reset role;

do $test$
declare ids jsonb := (select v from t_ae where k = 'runs'); x record;
begin
  assert (select count(*) from public.aircraft_eval_results where run_id = (ids ->> 'p1s20')::bigint) = 17
     and not exists (select 1 from public.aircraft_eval_results where run_id = (ids ->> 'p1s20')::bigint and type_name = 'Boeing 737-8')
     and (select seats from public.aircraft_eval_results where run_id = (ids ->> 'p1s20')::bigint and type_name = 'Airbus A350-900') = 387,
    'the re-save didn''t replace the earlier rows';
  select * into x from public.aircraft_eval_runs where id = (ids ->> 'p1s20')::bigint;
  assert x.done_at > (select (v #>> '{}')::timestamptz from t_ae where k = 'done_at'), 'the re-save didn''t move done_at';
  assert not exists (select 1 from public.aircraft_eval_results where run_id in ((ids ->> 'p1s30')::bigint, (ids ->> 'w2')::bigint))
     and (select done_at from public.aircraft_eval_runs where id = (ids ->> 'p1s30')::bigint) is null
     and (select done_at from public.aircraft_eval_runs where id = (ids ->> 'w2')::bigint) is null,
    'a refused result saved something';
end
$test$;

-- ---------------------------------------------------------------- 6. who reads the tables
do $$ begin perform set_config('request.jwt.claims', '{"email": "not-staff@aircraft-eval.test", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
begin
  assert (select count(*) from public.aircraft_eval_runs) = 0 and (select count(*) from public.aircraft_eval_results) = 0,
    'signed in without being staff, the evaluation tables show rows';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
set local role anon;
do $test$
begin
  begin
    perform 1 from public.aircraft_eval_runs limit 1;
    raise exception 'signed out read aircraft_eval_runs';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.aircraft_eval_results limit 1;
    raise exception 'signed out read aircraft_eval_results';
  exception when insufficient_privilege then null; end;
  raise notice 'signed in without being staff: no rows; signed out: refused';
end
$test$;
reset role;

-- ---------------------------------------------------------------- 7. on the copy
insert into public.capture_keys (label, key_hash, world_id)
select 'aircraft eval test, Gander', extensions.crypt('aircraft-eval-test-key-gander', extensions.gen_salt('bf')), id
  from public.worlds where is_default;
set local role anon;
do $test$
declare r jsonb := public.capture_eval_runs('aircraft-eval-test-key-gander');
begin
  assert r ->> 'ok' = 'true' and jsonb_array_length(r -> 'types') = 17, 'the default world''s list didn''t answer with the 17 types: ' || r::text;
  raise notice 'on the copy, signed out: % (the default world) answers with 17 types, % runs on its list, % done',
    r ->> 'world', r ->> 'total', r ->> 'done';
end
$test$;
reset role;

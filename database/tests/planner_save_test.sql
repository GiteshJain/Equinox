-- planner_save(): the new planner's one way to write (decision #18, build pull request 1; design §6, §14 choice 4).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says where (ids and counts, never values).
--   1. Who may call it: authenticated only (signed out, nobody); runs as owner with an empty search path. Signed out
--      and as an account that isn't staff, a call is refused and writes nothing.
--   2. As staff: one insert, one update and one delete, each read back, each answer giving the row's key and its new
--      updated_at, and each logged as actor planner with the client (the tab's ID) as the detail, role authenticated.
--      updated_at moves on each change. A table keyed by its own columns (dismissals) too.
--   3. All or nothing: a clash on one of two rows writes neither and answers with the clashing row as it is now; a row
--      deleted since it was loaded is a clash (current null); an error from a table's own check writes nothing.
--   4. Refused, writing nothing: a table not on the list, an unknown column, a missing base (update and delete), an
--      unknown op, a key that isn't the primary key, updated_at in the values, and changes that aren't a list.
-- Within this one transaction now() doesn't move, so the rows a change must visibly move are made first with an
-- updated_at an hour back, as if they had been loaded in an earlier transaction.

create temporary table t_ps (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_ps to authenticated, anon;
insert into public.planner_users (email) values ('planner-save-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. who may call it
do $test$
begin
  assert (select p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'public.planner_save(jsonb, text)'::regprocedure),
    'planner_save() doesn''t run as owner with an empty search path';
  assert not has_function_privilege('anon', 'public.planner_save(jsonb, text)', 'execute'), 'signed out, planner_save() can be called';
  assert has_function_privilege('authenticated', 'public.planner_save(jsonb, text)', 'execute'), 'signed in, planner_save() can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = 'public.planner_save(jsonb, text)'::regprocedure and a.grantee = 0),
    'everyone (PUBLIC) can call planner_save()';
  assert obj_description('public.planner_save(jsonb, text)'::regprocedure, 'pg_proc') is not null, 'planner_save() has no description';
end
$test$;

-- the rows this test changes: to-dos made as Claude would make them, each set an hour back (the trigger that keeps
-- updated_at is switched off for that one update, and the change log ignores a change to updated_at alone)
do $test$
declare w bigint := (select x.id from public.worlds x where x.is_default); v_name text; v_id bigint;
begin
  assert w is not null, 'the copy has no default world';
  insert into t_ps values ('world', to_jsonb(w));
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'planner_save test', true);
  foreach v_name in array array['a', 'x', 'y', 'n'] loop
    insert into public.todos (world_id, title, legacy_key)
    values (w, 'planner_save test: ' || v_name, 'planner-save-test-' || v_name || '-' || gen_random_uuid())
    returning id into v_id;
    insert into t_ps values (v_name, to_jsonb(v_id));
  end loop;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  execute 'alter table public.todos disable trigger set_updated_at';
  update public.todos set updated_at = now() - interval '1 hour'
   where id in (select (p.v #>> '{}')::bigint from t_ps p where p.k in ('a', 'x', 'y', 'n'));
  execute 'alter table public.todos enable trigger set_updated_at';
  assert (select count(*) from public.todos where updated_at < now()
             and id in (select (p.v #>> '{}')::bigint from t_ps p where p.k in ('a', 'x', 'y', 'n'))) = 4,
    'the test''s to-dos weren''t set back';
  insert into t_ps values ('mark', to_jsonb((select coalesce(max(id), 0) from public.change_log)));
end
$test$;

-- signed out: refused
set local role anon;
do $test$
declare refused boolean := false;
begin
  begin perform public.planner_save('[]'::jsonb, 'signed-out'); exception when insufficient_privilege then refused := true; end;
  assert refused, 'signed out, planner_save() could be called';
end
$test$;
reset role;

-- an account that isn't staff: refused, even with a change that would otherwise be fine
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e1", "email": "planner-save-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false; a bigint := (select (v #>> '{}')::bigint from t_ps where k = 'a');
begin
  begin
    perform public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', a),
                                                                     'base', now() - interval '1 hour', 'values', '{"title": "not staff"}'::jsonb)),
                                'not-staff');
  exception when insufficient_privilege then refused := true;
  end;
  assert refused, 'an account that isn''t staff could call planner_save()';
end
$test$;
reset role;
do $test$
begin
  assert not exists (select 1 from public.change_log where id > (select (v #>> '{}')::bigint from t_ps where k = 'mark')),
    'a refused caller wrote something';
  raise notice 'who may call it: signed in only, runs as owner with an empty search path; signed out and an account that isn''t staff are refused and write nothing';
end
$test$;

-- ---------------------------------------------------------------- 2. as staff: insert, update, delete
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e2", "email": "planner-save-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r jsonb; w bigint := (select (v #>> '{}')::bigint from t_ps where k = 'world');
  a bigint := (select (v #>> '{}')::bigint from t_ps where k = 'a'); v_new bigint; v_base jsonb; v_at timestamptz;
  v_key text := 'planner-save-test-new-' || gen_random_uuid(); v_alert text := 'planner-save-test|' || gen_random_uuid();
begin
  -- insert: the answer gives the new row's key and updated_at
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'insert',
         'values', jsonb_build_object('world_id', w, 'title', 'planner_save test: inserted', 'legacy_key', v_key))), 'save-test-tab');
  assert (r ->> 'ok')::boolean and jsonb_array_length(r -> 'rows') = 1, 'the insert wasn''t saved: ' || coalesce(r::text, 'no answer');
  v_new := (r #>> '{rows,0,key,id}')::bigint;
  select t.updated_at into v_at from public.todos t where t.id = v_new and t.legacy_key = v_key and t.title = 'planner_save test: inserted';
  assert found, 'the inserted to-do doesn''t read back';
  assert r #>> '{rows,0,table}' = 'todos' and (r #>> '{rows,0,updated_at}')::timestamptz = v_at, 'the insert''s answer doesn''t give the row''s updated_at';

  -- update: a row loaded an hour ago; its updated_at moves, and the answer says to what
  v_base := (select to_jsonb(t.updated_at) from public.todos t where t.id = a);
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', a),
         'base', v_base, 'values', jsonb_build_object('title', 'planner_save test: updated', 'done', true, 'done_at', now()))), 'save-test-tab');
  assert (r ->> 'ok')::boolean, 'the update wasn''t saved: ' || r::text;
  select t.updated_at into v_at from public.todos t where t.id = a and t.title = 'planner_save test: updated' and t.done and t.done_at is not null;
  assert found, 'the update doesn''t read back';
  assert v_at > (v_base #>> '{}')::timestamptz and (r #>> '{rows,0,updated_at}')::timestamptz = v_at and (r #>> '{rows,0,key,id}')::bigint = a,
    'the update didn''t move updated_at, or the answer doesn''t say where it is now';

  -- delete: the inserted row, with the updated_at its insert answered
  v_base := (select to_jsonb(t.updated_at) from public.todos t where t.id = v_new);
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'delete', 'key', jsonb_build_object('id', v_new),
         'base', v_base)), 'save-test-tab');
  assert (r ->> 'ok')::boolean and r #> '{rows,0,updated_at}' = 'null'::jsonb, 'the delete wasn''t saved: ' || r::text;
  assert not exists (select 1 from public.todos t where t.id = v_new), 'the deleted to-do is still there';

  -- a table keyed by its own columns: the key goes with the insert's values; then update and delete by it
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'dismissals', 'op', 'insert',
         'key', jsonb_build_object('world_id', w, 'alert_key', v_alert), 'values', jsonb_build_object('dismissed_on', '2026-10-12'))), 'save-test-tab');
  assert (r ->> 'ok')::boolean and r #> '{rows,0,key}' = jsonb_build_object('alert_key', v_alert, 'world_id', w),
    'the dismissal wasn''t saved with its key: ' || r::text;
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'dismissals', 'op', 'update',
         'key', jsonb_build_object('world_id', w, 'alert_key', v_alert), 'base', r #> '{rows,0,updated_at}',
         'values', jsonb_build_object('dismissed_on', '2026-10-13'))), 'save-test-tab');
  assert (r ->> 'ok')::boolean and (select d.dismissed_on from public.dismissals d where d.world_id = w and d.alert_key = v_alert) = date '2026-10-13',
    'the dismissal''s update doesn''t read back: ' || r::text;
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'dismissals', 'op', 'delete',
         'key', jsonb_build_object('world_id', w, 'alert_key', v_alert), 'base', r #> '{rows,0,updated_at}')), 'save-test-tab');
  assert (r ->> 'ok')::boolean and not exists (select 1 from public.dismissals d where d.world_id = w and d.alert_key = v_alert),
    'the dismissal wasn''t removed: ' || r::text;
  insert into t_ps values ('new', to_jsonb(v_new)), ('alert', to_jsonb(v_alert));
end
$test$;
reset role;
do $test$
declare v_mark bigint := (select (v #>> '{}')::bigint from t_ps where k = 'mark'); a bigint := (select (v #>> '{}')::bigint from t_ps where k = 'a');
  v_new bigint := (select (v #>> '{}')::bigint from t_ps where k = 'new'); v_alert text := (select v #>> '{}' from t_ps where k = 'alert');
  n int; bad int;
begin
  select count(*), count(*) filter (where l.actor is distinct from 'planner' or l.actor_detail is distinct from 'save-test-tab'
                                       or l.db_role is distinct from 'authenticated')
    into n, bad from public.change_log l where l.id > v_mark;
  assert bad = 0, format('%s of %s change-log row(s) aren''t actor planner, detail save-test-tab, role authenticated', bad, n);
  assert n = 6, format('%s change-log row(s), expected 6 (three to-do changes, three dismissal changes)', n);
  assert (select array_agg(l.op order by l.id) from public.change_log l where l.id > v_mark and l.table_name = 'todos')
         = array['insert', 'update', 'delete']
     and (select array_agg(l.row_key ->> 'id' order by l.id) from public.change_log l where l.id > v_mark and l.table_name = 'todos')
         = array[v_new::text, a::text, v_new::text],
    'the to-dos'' change log isn''t the insert, the update and the delete, in that order, of the right rows';
  assert (select array_agg(l.op order by l.id) from public.change_log l
           where l.id > v_mark and l.table_name = 'dismissals' and l.row_key ->> 'alert_key' = v_alert) = array['insert', 'update', 'delete'],
    'the dismissal''s change log isn''t its insert, update and delete';
  assert (select array_agg(k order by k) from public.change_log l cross join jsonb_object_keys(l.new_values) k
           where l.id > v_mark and l.table_name = 'todos' and l.op = 'update') = array['done', 'done_at', 'title'],
    'the update logged other columns than the ones it set';
  update t_ps set v = to_jsonb((select max(id) from public.change_log)) where k = 'mark';
  raise notice 'as staff: one insert, update and delete of a to-do, and of a dismissal keyed by its own columns, each read back with its key and new updated_at (moved by the update), and logged as planner with the tab''s ID (6 change-log rows)';
end
$test$;

-- ---------------------------------------------------------------- 3. all or nothing
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e2", "email": "planner-save-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r jsonb; r2 jsonb; w bigint := (select (v #>> '{}')::bigint from t_ps where k = 'world');
  x bigint := (select (v #>> '{}')::bigint from t_ps where k = 'x'); y bigint := (select (v #>> '{}')::bigint from t_ps where k = 'y');
  n bigint := (select (v #>> '{}')::bigint from t_ps where k = 'n');
  x0 jsonb := (select to_jsonb(t.updated_at) from public.todos t where t.id = x);
  y0 jsonb := (select to_jsonb(t.updated_at) from public.todos t where t.id = y);
  n0 jsonb := (select to_jsonb(t.updated_at) from public.todos t where t.id = n);
  y_title text := (select t.title from public.todos t where t.id = y);
  v_key text := 'planner-save-test-check-' || gen_random_uuid(); failed boolean;
begin
  -- two tabs loaded X and Y at the same time; the first changes X's title
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', x),
         'base', x0, 'values', '{"title": "planner_save test: tab 1"}'::jsonb)), 'save-test-tab-1');
  assert (r ->> 'ok')::boolean, 'the first tab''s change wasn''t saved: ' || r::text;
  -- the second, from what it loaded, changes X (a clash) and Y (no clash) in one action: neither is written
  r := public.planner_save(jsonb_build_array(
         jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', x), 'base', x0, 'values', '{"title": "planner_save test: tab 2"}'::jsonb),
         jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', y), 'base', y0, 'values', '{"title": "planner_save test: tab 2"}'::jsonb)),
       'save-test-tab-2');
  assert r ->> 'ok' = 'false' and not r ? 'rows', 'a clashing action was saved: ' || r::text;
  assert jsonb_array_length(r -> 'clashes') = 1 and r #>> '{clashes,0,table}' = 'todos' and r #> '{clashes,0,key}' = jsonb_build_object('id', x),
    'the answer doesn''t name exactly the clashing row: ' || (r -> 'clashes')::text;
  assert r #>> '{clashes,0,current,title}' = 'planner_save test: tab 1'
     and (r #>> '{clashes,0,current,updated_at}')::timestamptz = (select t.updated_at from public.todos t where t.id = x),
    'the clash doesn''t give the row as it is now';
  assert (select t.title from public.todos t where t.id = x) = 'planner_save test: tab 1', 'the clashing row was overwritten';
  assert (select t.title = y_title and to_jsonb(t.updated_at) = y0 from public.todos t where t.id = y),
    'the other row of the clashing action was written';

  -- a row deleted since it was loaded is a clash, with current null
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'delete', 'key', jsonb_build_object('id', n),
         'base', n0)), 'save-test-tab-1');
  assert (r ->> 'ok')::boolean, 'the delete wasn''t saved: ' || r::text;
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', n),
         'base', n0, 'values', '{"title": "planner_save test: gone"}'::jsonb)), 'save-test-tab-2');
  r2 := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'delete', 'key', jsonb_build_object('id', n),
         'base', n0)), 'save-test-tab-2');
  assert r ->> 'ok' = 'false' and r #> '{clashes,0,key}' = jsonb_build_object('id', n) and r #> '{clashes,0,current}' = 'null'::jsonb
     and r2 ->> 'ok' = 'false' and r2 #> '{clashes,0,current}' = 'null'::jsonb,
    'changing or removing a row deleted since it was loaded isn''t a clash with current null: ' || r::text || ' ' || r2::text;

  -- an error from a table's own check (a to-do needs a title) writes nothing, not even the action's other insert
  failed := false;
  begin
    perform public.planner_save(jsonb_build_array(
      jsonb_build_object('table', 'todos', 'op', 'insert', 'values', jsonb_build_object('world_id', w, 'title', 'planner_save test: half', 'legacy_key', v_key)),
      jsonb_build_object('table', 'todos', 'op', 'insert', 'values', jsonb_build_object('world_id', w, 'title', null))), 'save-test-tab-1');
  exception when not_null_violation then failed := true;
  end;
  assert failed, 'a to-do with no title was accepted';
  assert not exists (select 1 from public.todos t where t.legacy_key = v_key), 'half of a refused action was written';
end
$test$;
reset role;
do $test$
declare v_mark bigint := (select (v #>> '{}')::bigint from t_ps where k = 'mark'); n int; n2 int;
begin
  select count(*) filter (where l.actor_detail = 'save-test-tab-1'), count(*) filter (where l.actor_detail is distinct from 'save-test-tab-1')
    into n, n2 from public.change_log l where l.id > v_mark;
  assert n = 2 and n2 = 0, format('the first tab logged %s change(s) (expected 2: its title, its delete) and anything else %s (expected 0)', n, n2);
  update t_ps set v = to_jsonb((select max(id) from public.change_log)) where k = 'mark';
  raise notice 'all or nothing: a clash on one of two rows wrote neither and answered with the clashing row as it is now; a row deleted since it was loaded is a clash (current null); a table''s own check refusing one insert wrote nothing';
end
$test$;

-- ---------------------------------------------------------------- 4. refused, writing nothing
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e2", "email": "planner-save-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare y bigint := (select (v #>> '{}')::bigint from t_ps where k = 'y');
  y0 jsonb := (select to_jsonb(t.updated_at) from public.todos t where t.id = y);
  c record; got text; n int := 0;
begin
  for c in select * from (values
      ('a table not on the list (planner_users)', '[{"table": "planner_users", "op": "insert", "values": {"email": "x@example.com"}}]'::jsonb, 'isn''t one of the planner''s tables'),
      ('a table not on the list (change_log)', '[{"table": "change_log", "op": "delete", "key": {"id": 1}, "base": "2026-10-12T00:00:00Z"}]'::jsonb, 'isn''t one of the planner''s tables'),
      ('a table not on the list (game_flights)', '[{"table": "game_flights", "op": "delete", "key": {"id": 1}, "base": "2026-10-12T00:00:00Z"}]'::jsonb, 'isn''t one of the planner''s tables'),
      ('a table not on the list (planner_state)', '[{"table": "planner_state", "op": "insert", "values": {"id": "x"}}]'::jsonb, 'isn''t one of the planner''s tables'),
      ('an unknown column', jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', y), 'base', y0, 'values', '{"title": "x", "colour": "red"}'::jsonb)), 'has no column colour'),
      ('an update with no base', jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', y), 'values', '{"title": "x"}'::jsonb)), 'needs base'),
      ('a delete with no base', jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'delete', 'key', jsonb_build_object('id', y))), 'needs base'),
      ('an unknown op', jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'upsert', 'key', jsonb_build_object('id', y), 'base', y0, 'values', '{"title": "x"}'::jsonb)), 'op must be insert, update or delete'),
      ('a key that isn''t the primary key', jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', '{"legacy_key": "x"}'::jsonb, 'base', y0, 'values', '{"title": "x"}'::jsonb)), 'must name exactly the primary key'),
      ('updated_at in the values', jsonb_build_array(jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', y), 'base', y0, 'values', jsonb_build_object('updated_at', now()))), 'updated_at is set by the database'),
      ('changes that aren''t a list', '{"table": "todos"}'::jsonb, 'must be a JSON list'),
      -- a good change first, then a bad one: the good one isn't written either
      ('a good change with a bad one', jsonb_build_array(
         jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', y), 'base', y0, 'values', '{"title": "planner_save test: refused"}'::jsonb),
         jsonb_build_object('table', 'todos', 'op', 'update', 'key', jsonb_build_object('id', y), 'values', '{"title": "x"}'::jsonb)), 'needs base')
    ) as t(name, changes, msg) loop
    got := null;
    begin
      perform public.planner_save(c.changes, 'save-test-refused');
    exception when invalid_parameter_value then got := sqlerrm;
    end;
    assert got is not null, c.name || ' was accepted';
    assert position(c.msg in got) > 0, format('%s was refused, but not as expected: %s', c.name, got);
    n := n + 1;
  end loop;
  assert (select t.title from public.todos t where t.id = y) <> 'planner_save test: refused', 'a refused action was written';
  insert into t_ps values ('refused', to_jsonb(n));
end
$test$;
reset role;
do $test$
begin
  assert not exists (select 1 from public.change_log l where l.id > (select (v #>> '{}')::bigint from t_ps where k = 'mark')),
    'a refused action wrote something';
  raise notice 'refused, writing nothing: % cases (tables not on the list, an unknown column, a missing base for an update and a delete, an unknown op, a key that isn''t the primary key, updated_at in the values, changes that aren''t a list, a good change with a bad one)',
    (select v #>> '{}' from t_ps where k = 'refused');
end
$test$;

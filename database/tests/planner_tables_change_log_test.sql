-- The change log (#13 build pull request 2; design §6, decision #15).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says which.
--   1. As staff with the actor set: an insert, an update and a delete each write the right row; an update that changes
--      nothing writes none (and leaves updated_at alone); an actor the log doesn't know is kept as unset.
--   2. With no actor set: staff log planner, postgres logs unset.
--   3. equinox.change_log = off skips logging for postgres and is ignored for authenticated.
--   4. private.restore_row() puts a row back: changed, removed, and added since; also a table keyed by two columns.

insert into public.planner_users (email) values ('change-log-staff@example.com') on conflict do nothing;
create temporary table t_log_ids (k text primary key, v bigint) on commit drop;
grant select, insert, update on t_log_ids to authenticated;
insert into t_log_ids select 'world', id from public.worlds where name = 'Gander';

-- ---------------------------------------------------------------- 1. staff, actor set
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub": "00000000-0000-4000-8000-0000000000c1", "email": "change-log-staff@example.com", "role": "authenticated"}', true);
  perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', 'tab-test-1', true);
end $$;
set local role authenticated;
do $test$
declare w bigint := (select v from t_log_ids where k = 'world'); t bigint; l record; n bigint; before_at timestamptz;
begin
  -- insert: the whole new row
  insert into public.todos (world_id, title, note) values (w, 'Change-log test', 'first') returning id into t;
  insert into t_log_ids values ('todo', t);
  select * into l from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t) order by id desc limit 1;
  assert l.op = 'insert', 'an insert wasn''t logged as insert';
  assert l.old_values is null and l.new_values ->> 'title' = 'Change-log test' and l.new_values ->> 'note' = 'first',
    'an insert didn''t log the new row';
  assert l.actor = 'planner' and l.actor_detail = 'tab-test-1', format('an insert logged actor %s / %s', l.actor, l.actor_detail);
  assert l.db_role = 'authenticated', 'an insert logged role ' || l.db_role;
  assert l.world_id = w, 'an insert logged the wrong world';
  assert l.txid = txid_current(), 'an insert logged the wrong transaction';

  -- update: only the columns that changed, before and after
  select updated_at into before_at from public.todos where id = t;
  update public.todos set note = 'second', title = title where id = t;
  select * into l from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t) order by id desc limit 1;
  assert l.op = 'update', 'an update wasn''t logged as update';
  assert l.old_values = '{"note": "first"}'::jsonb and l.new_values = '{"note": "second"}'::jsonb,
    format('an update logged %s -> %s, expected only the note', l.old_values, l.new_values);

  -- an update that changes nothing: no row, and updated_at stays
  select count(*) into n from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t);
  select updated_at into before_at from public.todos where id = t;
  update public.todos set note = 'second', title = title where id = t;
  assert (select count(*) from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t)) = n,
    'an update that changed nothing was logged';
  assert (select updated_at from public.todos where id = t) = before_at, 'an update that changed nothing moved updated_at';

  -- an actor the log doesn't know: kept as unset, with what it said
  perform set_config('equinox.actor', 'someone', true);
  update public.todos set note = 'third' where id = t;
  select * into l from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t) order by id desc limit 1;
  assert l.actor = 'unset' and l.actor_detail like '%someone%', format('an unknown actor was logged as %s / %s', l.actor, l.actor_detail);
  perform set_config('equinox.actor', 'planner', true);

  -- delete: the whole old row
  delete from public.todos where id = t;
  select * into l from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t) order by id desc limit 1;
  assert l.op = 'delete', 'a delete wasn''t logged as delete';
  assert l.new_values is null and l.old_values ->> 'title' = 'Change-log test' and l.old_values ->> 'note' = 'third',
    'a delete didn''t log the old row';
  assert l.actor = 'planner' and l.actor_detail = 'tab-test-1', 'a delete logged the wrong actor';
end
$test$;

-- ---------------------------------------------------------------- 2. no actor set
do $$ begin perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true); end $$;
do $test$
declare w bigint := (select v from t_log_ids where k = 'world'); t bigint; l record;
begin
  insert into public.todos (world_id, title) values (w, 'No actor, staff') returning id into t;
  select * into l from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t);
  assert l.actor = 'planner' and l.actor_detail is null, 'a staff write with no actor wasn''t logged as planner: ' || l.actor;
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;
do $test$
declare w bigint := (select v from t_log_ids where k = 'world'); t bigint; l record;
begin
  assert auth.uid() is null, 'a signed-in user is still set';
  insert into public.todos (world_id, title) values (w, 'No actor, postgres') returning id into t;
  select * into l from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t);
  assert l.actor = 'unset' and l.db_role = 'postgres', format('a postgres write with no actor was logged as %s (%s)', l.actor, l.db_role);
end
$test$;

-- ---------------------------------------------------------------- 3. logging off
do $test$
declare w bigint := (select v from t_log_ids where k = 'world'); t bigint;
begin
  perform set_config('equinox.change_log', 'off', true);
  insert into public.todos (world_id, title) values (w, 'Logging off, postgres') returning id into t;
  assert not exists (select 1 from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t)),
    'equinox.change_log = off didn''t stop logging for postgres';
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c1", "email": "change-log-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare w bigint := (select v from t_log_ids where k = 'world'); t bigint;
begin
  assert current_setting('equinox.change_log', true) = 'off', 'the test lost its setting';
  insert into public.todos (world_id, title) values (w, 'Logging off, authenticated') returning id into t;
  insert into t_log_ids values ('off_auth', t);
end
$test$;
reset role;
do $test$
begin
  assert exists (select 1 from public.change_log where table_name = 'todos'
                  and row_key = jsonb_build_object('id', (select v from t_log_ids where k = 'off_auth'))),
    'equinox.change_log = off was honoured for authenticated';
  perform set_config('equinox.change_log', '', true);
end
$test$;

-- ---------------------------------------------------------------- 4. undo with private.restore_row()
do $test$
declare w bigint := (select v from t_log_ids where k = 'world'); t bigint; t0 timestamptz; t1 timestamptz; t2 timestamptz;
  r jsonb; n bigint; created timestamptz;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'restore test', true);
  t0 := clock_timestamp();
  insert into public.todos (world_id, title, note) values (w, 'Restore me', 'one') returning id, created_at into t, created;
  t1 := clock_timestamp();
  update public.todos set note = 'two', done = true where id = t;
  t2 := clock_timestamp();
  delete from public.todos where id = t;

  -- back to just before the delete: the row returns with its own id and values
  r := private.restore_row('todos', jsonb_build_object('id', t), t2);
  assert (select note from public.todos where id = t) = 'two' and (select done from public.todos where id = t),
    'restore_row didn''t bring back a removed row as it was';
  assert (select created_at from public.todos where id = t) = created, 'restore_row didn''t keep the row''s created_at';
  -- back to before the update: the changed columns are undone
  r := private.restore_row('todos', jsonb_build_object('id', t), t1);
  assert (select note from public.todos where id = t) = 'one' and not (select done from public.todos where id = t),
    'restore_row didn''t undo a change';
  -- back to before it existed: it goes
  r := private.restore_row('todos', jsonb_build_object('id', t), t0);
  assert r is null and not exists (select 1 from public.todos where id = t), 'restore_row didn''t remove a row added since';
  -- each restore is logged like any change, with the actor named
  select count(*) into n from public.change_log where table_name = 'todos' and row_key = jsonb_build_object('id', t)
     and changed_at > t2 and actor = 'claude' and actor_detail = 'restore test';
  assert n = 4, format('the restores wrote %s log rows (the delete plus three restores expected 4)', n);

  -- a table keyed by two columns
  t0 := clock_timestamp();
  insert into public.dismissals (world_id, alert_key, dismissed_on) values (w, 'test|restore', date '2026-10-09');
  t1 := clock_timestamp();
  delete from public.dismissals where world_id = w and alert_key = 'test|restore';
  r := private.restore_row('dismissals', jsonb_build_object('world_id', w, 'alert_key', 'test|restore'), t1);
  assert (select dismissed_on from public.dismissals where world_id = w and alert_key = 'test|restore') = date '2026-10-09',
    'restore_row didn''t bring back a row keyed by two columns';

  -- wrong use is refused
  begin r := private.restore_row('planner_state', '{"id": "main"}', t0); assert false, 'restore_row took a table the log doesn''t cover';
  exception when raise_exception then null; end;
  begin r := private.restore_row('todos', '{"title": "x"}', t0); assert false, 'restore_row took a key that isn''t the primary key';
  exception when raise_exception then null; end;
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
end
$test$;

do $$ begin raise notice 'change log: all checks passed'; end $$;

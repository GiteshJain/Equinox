-- The adapter's write side: a save meeting a newer change (design §8, §11 choice 4), and one item at a time (#13 build,
-- pull request 5). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a
-- transaction that is rolled back. A failed check stops with an error that says where (ids and counts, never values).
--   1. Two tabs save with the same base: the second keeps its items that don't clash, skips the one the first changed,
--      and answers reload: true. A tab's own earlier change is no clash; another tab's is, and so is Claude's. With no
--      base, the save's own time is the base.
--   2. planner_item_put() and planner_item_delete(): a plan card and a to-do added, changed and removed, each logged
--      with the caller's name; the planner's own document read back with them.
--   3. Who may call them: staff and postgres; an account that isn't staff is refused; signed out, nobody.

create function pg_temp.doc() returns jsonb language sql as $$ select (public.planner_state_get() ->> 'json')::jsonb $$;
create function pg_temp.ms() returns bigint language sql as $$ select floor(extract(epoch from clock_timestamp()) * 1000)::bigint $$;
create function pg_temp.todo(p_doc jsonb, p_id text) returns jsonb language sql as $$
  select e from jsonb_array_elements(p_doc -> 'todos') e where e ->> 'id' = p_id
$$;
create function pg_temp.with_todo(p_doc jsonb, p_id text, p_set jsonb) returns jsonb language sql as $$
  select jsonb_set(p_doc, '{todos}', (select jsonb_agg(case when e ->> 'id' = p_id then e || p_set else e end order by o)
                                         from jsonb_array_elements(p_doc -> 'todos') with ordinality as x(e, o)))
$$;

-- ---------------------------------------------------------------- 1. a save meeting a newer change
do $test$
declare d0 jsonb := pg_temp.doc(); base bigint; x text; y text; z text; ra jsonb; rb jsonb; ra2 jsonb; rc jsonb; rn jsonb; g jsonb;
  v_log bigint; xdone boolean;
begin
  select (array_agg(e ->> 'id' order by o))[1], (array_agg(e ->> 'id' order by o))[2], (array_agg(e ->> 'id' order by o))[3]
    into x, y, z from jsonb_array_elements(d0 -> 'todos') with ordinality as t(e, o);
  assert z is not null, 'the copy has fewer than three to-dos';
  xdone := coalesce((pg_temp.todo(d0, x) ->> 'done')::boolean, false);
  base := pg_temp.ms();

  -- tab A changes to-do X's title
  ra := public.planner_state_put(pg_temp.with_todo(d0, x, '{"title": "clash test: tab A"}')::text, pg_temp.ms(), base, 'clash-tab-a');
  assert (ra ->> 'applied')::int = 1 and (ra ->> 'skipped')::int = 0 and not (ra ->> 'reload')::boolean,
    format('tab A''s save: applied %s, skipped %s', ra ->> 'applied', ra ->> 'skipped');

  -- tab B, from the same base, ticks X and retitles Y: Y is kept, X (changed by A since) is skipped, and B is told to reload
  v_log := (select max(id) from public.change_log);
  rb := public.planner_state_put(pg_temp.with_todo(pg_temp.with_todo(d0, x, jsonb_build_object('done', not xdone)), y,
                                                   '{"title": "clash test: tab B"}')::text, pg_temp.ms(), base, 'clash-tab-b');
  assert (rb ->> 'applied')::int = 1 and (rb ->> 'skipped')::int = 1 and (rb ->> 'reload')::boolean
     and rb -> 'skipped_items' = jsonb_build_array('todos ' || x),
    format('tab B''s save: applied %s, skipped %s (%s), reload %s; expected 1, 1 (todos %s), true',
           rb ->> 'applied', rb ->> 'skipped', rb -> 'skipped_items', rb ->> 'reload', x);
  assert (rb ->> 'saved_at')::bigint >= (ra ->> 'saved_at')::bigint, 'saved_at went back';
  g := pg_temp.doc();
  assert pg_temp.todo(g, x) ->> 'title' = 'clash test: tab A' and coalesce((pg_temp.todo(g, x) ->> 'done')::boolean, false) = xdone,
    'to-do X isn''t as tab A left it';
  assert pg_temp.todo(g, y) ->> 'title' = 'clash test: tab B', 'tab B''s change to to-do Y wasn''t kept';
  assert not exists (select 1 from public.change_log l join public.todos t on l.row_key = jsonb_build_object('id', t.id)
                      where l.id > v_log and l.table_name = 'todos' and t.legacy_key = x),
    'tab B wrote to to-do X';

  -- tab A again, still from its first base and not knowing B's save: its own earlier change to X is no clash, B's to Y is
  ra2 := public.planner_state_put(pg_temp.with_todo(d0, x, '{"title": "clash test: tab A", "note": "clash test: tab A again"}')::text,
                                  pg_temp.ms(), base, 'clash-tab-a');
  assert (ra2 ->> 'applied')::int = 1 and ra2 -> 'skipped_items' = jsonb_build_array('todos ' || y) and (ra2 ->> 'reload')::boolean,
    format('tab A''s second save: applied %s, skipped %s; expected its own to-do kept and todos %s skipped', ra2 ->> 'applied', ra2 -> 'skipped_items', y);
  g := pg_temp.doc();
  assert pg_temp.todo(g, x) ->> 'note' = 'clash test: tab A again' and pg_temp.todo(g, y) ->> 'title' = 'clash test: tab B',
    'tab A''s second save didn''t keep its own change, or overwrote tab B''s';

  -- Claude changes to-do Z in a chat (plain SQL, naming itself): a tab saving from before that skips Z
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'clash test', true);
  update public.todos set title = 'clash test: Claude' where legacy_key = z and world_id = (select id from public.worlds where is_default);
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  rc := public.planner_state_put(pg_temp.with_todo(g, z, '{"done": true}')::text, pg_temp.ms(), base, 'clash-tab-a');
  assert rc -> 'skipped_items' ? ('todos ' || z) and (rc ->> 'reload')::boolean, 'a tab overwrote Claude''s newer change';
  assert pg_temp.todo(pg_temp.doc(), z) ->> 'title' = 'clash test: Claude', 'Claude''s change was lost';

  -- no base: the save's own time is the base, so changes made after it are kept and earlier ones aren't in the way
  rn := public.planner_state_put(pg_temp.with_todo(pg_temp.doc(), z, '{"note": "clash test: no base"}')::text, pg_temp.ms(), null, 'clash-tab-c');
  assert (rn ->> 'applied')::int = 1 and (rn ->> 'skipped')::int = 0, 'a save with no base skipped what it shouldn''t';

  raise notice 'a save meeting a newer change: tab B kept its own to-do, skipped the one tab A had changed and was told to reload; a tab''s own earlier change is no clash; Claude''s newer change was kept; with no base the save''s own time counts';
end
$test$;

-- ---------------------------------------------------------------- 2. one item at a time
do $test$
declare d jsonb := pg_temp.doc(); reg text; src text; card jsonb; r jsonb; v_log bigint; n_ins int; n_upd int; n_del int;
  todo jsonb := '{"title": "item test", "date": "2026-10-11", "done": false, "items": ["first", "second"], "created": "2026-10-10T18:30:00.123Z"}';
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'adapter item test', true);
  v_log := coalesce((select max(id) from public.change_log), 0);

  -- a plan card for an aircraft that has none, with another card's legs
  reg := (select t ->> 'id' from jsonb_array_elements(d -> 'tails') t where not (d -> 'plans') ? (t ->> 'id') limit 1);
  src := (select min(x) from jsonb_object_keys(d -> 'plans') x where jsonb_array_length(coalesce(d #> array['plans', x, 'legs'], '[]')) > 0);
  assert reg is not null and src is not null, 'the copy has no tail without a plan card, or no plan card with legs';
  card := jsonb_build_object('base', d #> array['plans', src, 'base'], 'title', 'item test card', 'legs', d #> array['plans', src, 'legs']);
  r := public.planner_item_put('plans', reg, card);
  assert (r ->> 'applied')::int = 1 and pg_temp.doc() #> array['plans', reg] is not null
     and not exists (select 1 from private.planner_json_diff(card, pg_temp.doc() #> array['plans', reg]) x where x.kind = 'differs'),
    'the plan card put doesn''t read back as given';
  r := public.planner_item_put('plans', reg, card || '{"title": "item test card, changed"}');
  assert pg_temp.doc() #>> array['plans', reg, 'title'] = 'item test card, changed', 'the plan card''s change didn''t read back';
  r := public.planner_item_delete('plans', reg);
  assert not (pg_temp.doc() -> 'plans') ? reg, 'the plan card wasn''t removed';
  select count(*) filter (where op = 'insert'), count(*) filter (where op = 'update'), count(*) filter (where op = 'delete')
    into n_ins, n_upd, n_del from public.change_log where id > v_log and table_name = 'plan_cards';
  assert n_ins = 1 and n_upd = 1 and n_del = 1, format('the plan card''s log: %s added, %s changed, %s removed; expected 1 each', n_ins, n_upd, n_del);
  assert (select count(*) from public.change_log where id > v_log and table_name = 'plan_card_legs' and op = 'insert')
         = jsonb_array_length(card -> 'legs'), 'the plan card''s legs weren''t each logged when added';

  -- a to-do
  v_log := (select max(id) from public.change_log);
  r := public.planner_item_put('todos', 't-adapter-item-test', todo);
  assert pg_temp.todo(pg_temp.doc(), 't-adapter-item-test') - 'id' = todo, 'the to-do put doesn''t read back as given';
  r := public.planner_item_put('todos', 't-adapter-item-test', todo || '{"done": true, "doneAt": "2026-10-10T19:00:00.456Z", "items": ["first"]}');
  assert (pg_temp.todo(pg_temp.doc(), 't-adapter-item-test') ->> 'done')::boolean
     and pg_temp.todo(pg_temp.doc(), 't-adapter-item-test') -> 'items' = '["first"]', 'the to-do''s change didn''t read back';
  r := public.planner_item_delete('todos', 't-adapter-item-test');
  assert pg_temp.todo(pg_temp.doc(), 't-adapter-item-test') is null, 'the to-do wasn''t removed';
  select count(*) filter (where op = 'insert'), count(*) filter (where op = 'update'), count(*) filter (where op = 'delete')
    into n_ins, n_upd, n_del from public.change_log where id > v_log and table_name = 'todos';
  assert n_ins = 1 and n_upd = 1 and n_del = 1, format('the to-do''s log: %s added, %s changed, %s removed; expected 1 each', n_ins, n_upd, n_del);
  assert exists (select 1 from public.change_log where id > v_log and table_name = 'todo_items' and op = 'delete'),
    'the to-do''s removed step wasn''t logged';
  assert not exists (select 1 from public.change_log where id > v_log and (actor <> 'claude' or actor_detail is distinct from 'adapter item test')),
    'a change-log row doesn''t name the caller (claude, adapter item test)';
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

  -- bad input is refused
  begin perform public.planner_item_put('nonsense', 'x', '{}'); assert false, 'an unknown section was accepted';
  exception when others then if sqlerrm like '%was accepted' then raise; end if; end;
  begin perform public.planner_item_put('todos', 'x', null); assert false, 'a put with no value was accepted';
  exception when others then if sqlerrm like '%was accepted' then raise; end if; end;
  raise notice 'one item at a time: a plan card and a to-do added, changed and removed through planner_item_put() and planner_item_delete(), each logged with the caller''s name';
end
$test$;

-- ---------------------------------------------------------------- 3. who may call them
insert into public.planner_users (email) values ('adapter-write-staff@example.com') on conflict do nothing;
do $test$
begin
  assert not has_function_privilege('anon', 'public.planner_state_put(text, bigint, bigint, text)', 'execute')
     and not has_function_privilege('anon', 'public.planner_item_put(text, text, jsonb)', 'execute')
     and not has_function_privilege('anon', 'public.planner_item_delete(text, text)', 'execute'), 'signed out, the write functions can be called';
  assert has_function_privilege('authenticated', 'public.planner_state_put(text, bigint, bigint, text)', 'execute'),
    'signed in, planner_state_put() can''t be called';
  assert (select bool_and(p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false)) from pg_proc p
           where p.oid in ('public.planner_state_put(text, bigint, bigint, text)'::regprocedure, 'public.planner_item_put(text, text, jsonb)'::regprocedure,
                           'public.planner_item_delete(text, text)'::regprocedure, 'public.save_loads(text, jsonb)'::regprocedure)),
    'a write function doesn''t run as owner with an empty search path';
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d1", "email": "adapter-write-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean;
begin
  refused := false;
  begin perform public.planner_state_put((select '{}'), null, null, 'x'); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could call planner_state_put()';
  refused := false;
  begin perform public.planner_item_put('dismissed', 'x', '"2026-10-10"'); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could call planner_item_put()';
  refused := false;
  begin perform public.planner_item_delete('dismissed', 'x'); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could call planner_item_delete()';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d2", "email": "adapter-write-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r jsonb; v_log bigint;
begin
  r := public.planner_item_put('dismissed', 'adapter|staff-test', '"2026-10-10"');
  assert (r ->> 'applied')::int = 1, 'staff couldn''t put an item';
  r := public.planner_item_delete('dismissed', 'adapter|staff-test');
  assert (r ->> 'applied')::int = 1, 'staff couldn''t remove an item';
end
$test$;
reset role;
do $test$
begin
  assert (select count(*) from public.change_log where table_name = 'dismissals' and row_key ->> 'alert_key' = 'adapter|staff-test'
             and actor = 'planner' and db_role = 'authenticated') = 2, 'staff''s item saves aren''t logged as planner, role authenticated';
  raise notice 'who may call them: signed out nobody; an account that isn''t staff is refused; staff can, logged as planner';
end
$test$;

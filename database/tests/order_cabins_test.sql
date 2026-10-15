-- The cabin an order comes with, as data (spec docs/specs/2026-10-15-last-leftovers.md §1; migration
-- 20261015220000_last_leftovers.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says where (codes, ids
-- and counts only). Nothing on the copy changes:
--   1. The data and its reader: aircraft_types.order_config_id and airline_order_cabins (an airline's own, keyed by
--      airline and type) are there and described; private.fig_order_cabin() is stable, internal, with an empty search
--      path, and described.
--   2. The same as before: for every airline and every type of its world, private.fig_order_cabin() gives the layout it
--      gave before the changes (rehearsal_before.order_cabins, saved by database/tests/before/order_cabins_before.sql),
--      so order_cabin(), cash_forecast() and the briefing's figures don't move. The type's and the airlines' own are
--      layouts of that type.
--   3. The data decides it: the type's order cabin changed moves every airline without its own and no other; an
--      airline's own row moves that airline only, an empty one gives it none, and removing it gives it the type's again.
--      An airline or type that isn't there gives none.
--   4. Reference saves it through planner_save() as staff: the type's order cabin (aircraft_types) and an airline's own
--      (airline_order_cabins: added, changed and removed), each logged as planner with the tab's ID.

create temporary table t_oc (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_oc to authenticated, anon;
insert into public.planner_users (email) values ('order-cabins-test-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. the data and its reader
do $test$
begin
  assert (select a.atttypid = 'bigint'::regtype from pg_attribute a
           where a.attrelid = 'public.aircraft_types'::regclass and a.attname = 'order_config_id' and not a.attisdropped),
    'aircraft_types has no order_config_id';
  assert col_description('public.aircraft_types'::regclass,
           (select a.attnum from pg_attribute a where a.attrelid = 'public.aircraft_types'::regclass and a.attname = 'order_config_id')::int) is not null,
    'aircraft_types.order_config_id has no description';
  assert to_regclass('public.airline_order_cabins') is not null, 'airline_order_cabins isn''t there';
  assert obj_description('public.airline_order_cabins'::regclass, 'pg_class') is not null, 'airline_order_cabins has no description';
  assert (select array_agg(a.attname::text order by k.n) from pg_index x
            cross join lateral unnest(x.indkey::smallint[]) with ordinality as k(attnum, n)
            join pg_attribute a on a.attrelid = x.indrelid and a.attnum = k.attnum
           where x.indrelid = 'public.airline_order_cabins'::regclass and x.indisprimary) = array['airline_id', 'aircraft_type_id'],
    'airline_order_cabins isn''t keyed by airline and type';
  assert (select p.provolatile = 's' and not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'private.fig_order_cabin(bigint, bigint)'::regprocedure),
    'fig_order_cabin() isn''t stable with an empty search path';
  assert not has_function_privilege('authenticated', 'private.fig_order_cabin(bigint, bigint)', 'execute'), 'fig_order_cabin() can be called from outside';
  assert obj_description('private.fig_order_cabin(bigint, bigint)'::regprocedure, 'pg_proc') like '%airline_order_cabins%',
    'fig_order_cabin()''s description doesn''t say it reads the data';
  raise notice 'the data: aircraft_types.order_config_id and airline_order_cabins (by airline and type), described; fig_order_cabin() stable, internal, empty search path';
end
$test$;

-- ---------------------------------------------------------------- 2. the same as before
do $test$
declare n_pairs int; n_with int; n_moved int; n_own int; n_types int; n_typed int; bad text;
begin
  assert to_regclass('rehearsal_before.order_cabins') is not null,
    'the order cabins from before the changes weren''t saved (database/tests/before/order_cabins_before.sql)';
  select count(*), count(b.config_id), count(*) filter (where private.fig_order_cabin(b.airline_id, b.aircraft_type_id) is distinct from b.config_id)
    into n_pairs, n_with, n_moved
    from rehearsal_before.order_cabins b;
  assert n_pairs > 0, 'no airline and type on the copy';
  select string_agg(format('%s/%s', a.iata_code, t.name), ', ') into bad
    from rehearsal_before.order_cabins b
    join public.airlines a on a.id = b.airline_id join public.aircraft_types t on t.id = b.aircraft_type_id
   where private.fig_order_cabin(b.airline_id, b.aircraft_type_id) is distinct from b.config_id;
  assert n_moved = 0, format('%s of %s airline-and-type pairs get another order cabin than before: %s', n_moved, n_pairs, left(bad, 400));
  -- every pair there is now was there before (no airline or type came or went with the changes)
  assert (select count(*) from public.airlines a join public.aircraft_types t on t.world_id = a.world_id) = n_pairs,
    'the airlines and types aren''t the ones there were before the changes';
  -- each order cabin is a layout of its own type
  assert not exists (select 1 from public.aircraft_types t join public.cabin_configs c on c.id = t.order_config_id
                      where c.aircraft_type_id is distinct from t.id), 'a type''s order cabin is a layout of another type';
  assert not exists (select 1 from public.airline_order_cabins x join public.cabin_configs c on c.id = x.order_config_id
                      where c.aircraft_type_id is distinct from x.aircraft_type_id), 'an airline''s own order cabin is a layout of another type';
  select count(*), count(t.order_config_id) into n_types, n_typed from public.aircraft_types t;
  select count(*) into n_own from public.airline_order_cabins;
  raise notice 'the same as before for all % airline-and-type pairs (% with a layout): % types, % with an order cabin; % airline''s own',
    n_pairs, n_with, n_types, n_typed, n_own;
end
$test$;

-- ---------------------------------------------------------------- 3. the data decides it
do $test$
declare
  t record; a_free bigint; a_other bigint; before_other bigint; was_type bigint; alt bigint; n_moved int; n_others int;
begin
  -- a type with an order cabin and another layout, and two airlines of its world without their own row for it
  select ty.id, ty.world_id, ty.order_config_id into t
    from public.aircraft_types ty
   where ty.order_config_id is not null
     and exists (select 1 from public.cabin_configs c where c.aircraft_type_id = ty.id and c.id <> ty.order_config_id)
   order by ty.id limit 1;
  if t.id is null then
    raise notice 'the data decides it: not tried (no type with an order cabin and another layout on the copy)';
    return;
  end if;
  select a.id into a_free from public.airlines a
   where a.world_id = t.world_id and not exists (select 1 from public.airline_order_cabins x where x.airline_id = a.id and x.aircraft_type_id = t.id)
   order by a.id limit 1;
  select a.id into a_other from public.airlines a
   where a.world_id = t.world_id and a.id <> a_free
     and not exists (select 1 from public.airline_order_cabins x where x.airline_id = a.id and x.aircraft_type_id = t.id)
   order by a.id limit 1;
  select c.id into alt from public.cabin_configs c where c.aircraft_type_id = t.id and c.id <> t.order_config_id order by c.id limit 1;
  was_type := t.order_config_id;
  create temporary table t_was_oc on commit drop as
    select a.id as airline_id, private.fig_order_cabin(a.id, t.id) as config_id from public.airlines a where a.world_id = t.world_id;

  -- the type's order cabin moves every airline without its own, and only those
  update public.aircraft_types set order_config_id = alt where id = t.id;
  select count(*) filter (where private.fig_order_cabin(w.airline_id, t.id) is distinct from w.config_id),
         count(*) filter (where exists (select 1 from public.airline_order_cabins x where x.airline_id = w.airline_id and x.aircraft_type_id = t.id)
                            and private.fig_order_cabin(w.airline_id, t.id) is distinct from w.config_id)
    into n_moved, n_others from t_was_oc w;
  assert private.fig_order_cabin(a_free, t.id) = alt, 'the type''s order cabin changed, an airline without its own didn''t follow';
  assert n_others = 0, 'the type''s order cabin changed, an airline with its own moved';
  assert n_moved = (select count(*) from t_was_oc w where not exists (select 1 from public.airline_order_cabins x
                      where x.airline_id = w.airline_id and x.aircraft_type_id = t.id) and w.config_id is distinct from alt),
    'the type''s order cabin changed, and not exactly the airlines without their own moved';
  update public.aircraft_types set order_config_id = was_type where id = t.id;

  -- an airline's own row moves that airline only; an empty one gives it none; removing it gives it the type's again
  before_other := private.fig_order_cabin(a_other, t.id);
  insert into public.airline_order_cabins (world_id, airline_id, aircraft_type_id, order_config_id) values (t.world_id, a_free, t.id, alt);
  assert private.fig_order_cabin(a_free, t.id) = alt, 'an airline''s own order cabin isn''t what it gets';
  assert private.fig_order_cabin(a_other, t.id) is not distinct from before_other, 'an airline''s own order cabin moved another airline';
  update public.airline_order_cabins set order_config_id = null where airline_id = a_free and aircraft_type_id = t.id;
  assert private.fig_order_cabin(a_free, t.id) is null, 'an airline''s own empty order cabin doesn''t give it none';
  delete from public.airline_order_cabins where airline_id = a_free and aircraft_type_id = t.id;
  assert private.fig_order_cabin(a_free, t.id) is not distinct from was_type, 'with its own row removed, an airline doesn''t get the type''s again';

  -- none for an airline or a type that isn't there
  assert private.fig_order_cabin(-1, t.id) is null and private.fig_order_cabin(a_free, -1) is null,
    'an airline or type that isn''t there gets an order cabin';
  insert into t_oc values ('type', to_jsonb(t.id)), ('world', to_jsonb(t.world_id)), ('airline', to_jsonb(a_free)), ('alt', to_jsonb(alt)),
                          ('was', coalesce(to_jsonb(was_type), 'null'::jsonb)), ('mark', to_jsonb((select coalesce(max(id), 0) from public.change_log)));
  raise notice 'the data decides it: the type''s order cabin moved % airline(s) without their own and none with; an airline''s own row moves it alone, empty gives none, removed gives the type''s',
    n_moved;
end
$test$;

-- ---------------------------------------------------------------- 4. saved through planner_save() as staff
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000e7", "email": "order-cabins-test-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare
  tid bigint; w bigint; al bigint; alt bigint; was jsonb; r jsonb; v_base timestamptz;
begin
  select (v #>> '{}')::bigint into tid from t_oc where k = 'type';
  if tid is null then
    raise notice 'saved through planner_save(): not tried (no type to try it on)';
    return;
  end if;
  select (v #>> '{}')::bigint into w from t_oc where k = 'world';
  select (v #>> '{}')::bigint into al from t_oc where k = 'airline';
  select (v #>> '{}')::bigint into alt from t_oc where k = 'alt';
  select v into was from t_oc where k = 'was';
  -- the type's order cabin, as Reference's Aircraft table saves it
  select t.updated_at into v_base from public.aircraft_types t where t.id = tid;
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'aircraft_types', 'op', 'update', 'key', jsonb_build_object('id', tid),
         'base', v_base, 'values', jsonb_build_object('order_config_id', alt))), 'order-cabins-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t save a type''s order cabin: ' || r::text;
  assert (select t.order_config_id from public.aircraft_types t where t.id = tid) = alt, 'the type''s order cabin wasn''t saved';
  -- an airline's own: added, changed, removed
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'airline_order_cabins', 'op', 'insert',
         'values', jsonb_build_object('world_id', w, 'airline_id', al, 'aircraft_type_id', tid, 'order_config_id', was))), 'order-cabins-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t add an airline''s own order cabin: ' || r::text;
  assert r -> 'rows' -> 0 -> 'key' = jsonb_build_object('airline_id', al, 'aircraft_type_id', tid), 'the answer doesn''t give the new row''s key';
  select x.updated_at into v_base from public.airline_order_cabins x where x.airline_id = al and x.aircraft_type_id = tid;
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'airline_order_cabins', 'op', 'update',
         'key', jsonb_build_object('airline_id', al, 'aircraft_type_id', tid), 'base', v_base, 'values', jsonb_build_object('order_config_id', alt))),
         'order-cabins-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t change an airline''s own order cabin: ' || r::text;
  select x.updated_at into v_base from public.airline_order_cabins x where x.airline_id = al and x.aircraft_type_id = tid;
  r := public.planner_save(jsonb_build_array(jsonb_build_object('table', 'airline_order_cabins', 'op', 'delete',
         'key', jsonb_build_object('airline_id', al, 'aircraft_type_id', tid), 'base', v_base)), 'order-cabins-test');
  assert (r ->> 'ok')::boolean, 'planner_save() didn''t remove an airline''s own order cabin: ' || r::text;
end
$test$;
reset role;
do $test$
declare mark bigint := (select (v #>> '{}')::bigint from t_oc where k = 'mark'); got text;
begin
  if mark is null then return; end if;
  select string_agg(c.table_name || ' ' || c.op, ', ' order by c.id) into got
    from public.change_log c where c.id > mark and c.actor = 'planner' and c.actor_detail = 'order-cabins-test';
  assert got = 'aircraft_types update, airline_order_cabins insert, airline_order_cabins update, airline_order_cabins delete',
    'planner_save()''s writes weren''t logged as planner with the tab: ' || coalesce(got, 'nothing');
  assert not exists (select 1 from public.change_log c where c.id > mark and c.actor_detail = 'order-cabins-test' and c.db_role <> 'authenticated'),
    'planner_save()''s writes weren''t made as the signed-in staff';
  raise notice 'saved through planner_save() as staff: the type''s order cabin, and an airline''s own added, changed and removed, each logged as planner with the tab';
end
$test$;

do $$ begin raise notice 'order cabins: all checks passed'; end $$;

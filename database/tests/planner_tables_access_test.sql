-- The planner tables (#13, build pull request 2): who can reach them (design §5).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says which.
--   1. From the catalogue: anon can read no table or view in public; every new table has RLS on and one staff rule per
--      action; every new view is security_invoker; anon gets nothing new; authenticated reads every new table and view
--      and writes only the planner tables; the new functions are closed; new objects aren't given away by default.
--   2. Signed in with an email that isn't on planner_users: every new table and view reads no rows, and every write is
--      refused or touches nothing.
--   3. Signed in as staff: reads and writes work, and change_log stays read-only.

create temporary table t_new (name text primary key, planner boolean not null) on commit drop;
insert into t_new values
  ('worlds', true), ('groups', true), ('airlines', true), ('airline_bases', true), ('airline_aircraft_types', true),
  ('countries', true), ('airports', true), ('world_airports', true),
  ('aircraft_types', true), ('cabin_configs', true), ('aircraft', true), ('aircraft_cabin_keeps', true),
  ('markets', true), ('service_profiles', true), ('routes', true), ('rotations', true), ('flight_legs', true),
  ('plan_cards', true), ('plan_card_legs', true),
  ('todos', true), ('todo_items', true), ('growth_log', true), ('spending_log', true), ('fare_plan', true),
  ('interline_agreements', true), ('monthly_checks', true), ('dismissals', true), ('cash_entries', true),
  ('load_entries', true), ('load_days', true), ('settings', true), ('world_rules', true),
  ('airline_order_cabins', true),   -- the 33rd, 15 Oct (20261015220000_last_leftovers.sql)
  ('change_log', false);
create temporary table t_views (name text primary key) on commit drop;
insert into t_views values ('flight_legs_local'), ('flight_no_clashes');
grant select on t_new, t_views to authenticated;

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare bad text;
begin
  select string_agg(n.name, ', ') into bad from t_new n where to_regclass('public.' || n.name) is null;
  assert bad is null, 'missing tables: ' || bad;
  select string_agg(v.name, ', ') into bad from t_views v where to_regclass('public.' || v.name) is null;
  assert bad is null, 'missing views: ' || bad;

  -- a signed-out visitor reads nothing: no table or view in public is readable by anon. Since #13's pull request 3
  -- (20261009230100_capture_data_removals.sql) that holds for the 22 tables from before #13 too, with no exception.
  select string_agg(c.relname, ', ' order by c.relname) into bad
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') and has_table_privilege('anon', c.oid, 'select');
  assert bad is null, 'anon can read these tables and views in public: ' || bad;
  select string_agg(c.relname, ', ' order by c.relname) into bad
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
   where s.nspname = 'public' and c.relkind in ('r', 'p') and has_table_privilege('anon', c.oid, 'select')
     and (not c.relrowsecurity
          or exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname
                        and p.cmd in ('SELECT', 'ALL') and p.roles && array['anon', 'public']::name[]));
  assert bad is null, 'anon can read rows of these tables in public: ' || bad;

  -- RLS on every new table, with exactly one staff rule per action, each using the staff check once per query
  select string_agg(n.name, ', ') into bad from t_new n join pg_class c on c.oid = ('public.' || n.name)::regclass
   where not c.relrowsecurity;
  assert bad is null, 'RLS is off on: ' || bad;
  select string_agg(n.name || ' (' || coalesce(p.cmds, 'none') || ')', ', ') into bad
    from t_new n left join lateral (
      select string_agg(lower(cmd), ',' order by cmd) as cmds from pg_policies
       where schemaname = 'public' and tablename = n.name) p on true
   where p.cmds is distinct from (case when n.planner then 'delete,insert,select,update' else 'select' end);
  assert bad is null, 'not one staff rule per action on: ' || bad;
  select string_agg(tablename || '.' || policyname, ', ') into bad from pg_policies p join t_new n on n.name = p.tablename
   where p.schemaname = 'public'
     and (p.roles <> '{authenticated}'
          or (p.cmd <> 'INSERT' and p.qual is distinct from '( SELECT is_planner_user() AS is_planner_user)')
          or (p.cmd in ('INSERT', 'UPDATE') and p.with_check is distinct from '( SELECT is_planner_user() AS is_planner_user)'));
  assert bad is null, 'rules that aren''t the staff check, for authenticated: ' || bad;

  -- every new view shows the caller only what the caller may read
  select string_agg(v.name, ', ') into bad from t_views v join pg_class c on c.oid = ('public.' || v.name)::regclass
   where not coalesce('security_invoker=true' = any (c.reloptions), false);
  assert bad is null, 'views that aren''t security_invoker: ' || bad;

  -- anon: nothing at all on the new tables and views
  select string_agg(x.name || ' ' || x.priv, ', ') into bad
    from (select name from t_new union all select name from t_views) x0(name)
    cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) as p(priv)
    cross join lateral (select x0.name, p.priv) x
   where has_table_privilege('anon', 'public.' || x.name, x.priv);
  assert bad is null, 'anon has: ' || bad;

  -- authenticated: reads every new table and view; writes only the planner tables; never truncate
  select string_agg(x.name, ', ') into bad
    from (select name from t_new union all select name from t_views) x
   where not has_table_privilege('authenticated', 'public.' || x.name, 'select');
  assert bad is null, 'authenticated can''t read: ' || bad;
  select string_agg(n.name || ' ' || p.priv, ', ') into bad
    from t_new n cross join unnest(array['insert', 'update', 'delete']) as p(priv)
   where has_table_privilege('authenticated', 'public.' || n.name, p.priv) is distinct from n.planner;
  assert bad is null, 'authenticated writes differ from the planner tables (expected on all of them, never on change_log): ' || bad;
  select string_agg(x.name || ' ' || p.priv, ', ') into bad
    from (select name from t_new union all select name from t_views) x
    cross join unnest(array['truncate', 'references', 'trigger']) as p(priv)
   where has_table_privilege('authenticated', 'public.' || x.name, p.priv);
  assert bad is null, 'authenticated has: ' || bad;
  select string_agg(v.name || ' ' || p.priv, ', ') into bad
    from t_views v cross join unnest(array['insert', 'update', 'delete']) as p(priv)
   where has_table_privilege('authenticated', 'public.' || v.name, p.priv);
  assert bad is null, 'authenticated can write views: ' || bad;

  -- the private schema: closed to the data API's roles; its functions closed to public and anon; only the change-log
  -- trigger and the side-by-side triggers (#13 pull request 5: they write job_runs, which stays read-only to everyone
  -- else) run as owner; each has a fixed, empty search path
  assert not has_schema_privilege('anon', 'private', 'usage'), 'anon can use the private schema';
  assert not has_schema_privilege('authenticated', 'private', 'usage'), 'authenticated can use the private schema';
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p where p.pronamespace = 'private'::regnamespace
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0));
  assert bad is null, 'functions anyone or anon can run: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p where p.pronamespace = 'private'::regnamespace
     and has_function_privilege('authenticated', p.oid, 'execute') and p.proname <> 'is_weekday_set';
  assert bad is null, 'functions authenticated can run: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p where p.pronamespace = 'private'::regnamespace
     and p.prosecdef <> (p.proname = 'log_change');
  assert bad is null, 'runs as owner when it shouldn''t, or the other way round: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p where p.pronamespace = 'private'::regnamespace
     and not coalesce('search_path=""' = any (p.proconfig), false);
  assert bad is null, 'functions without an empty search path: ' || bad;

  -- new tables, sequences and functions in public aren't given to anon or authenticated by default
  select string_agg(d.defaclobjtype::text || ' to ' || r.rolname, ', ') into bad
    from pg_default_acl d cross join aclexplode(d.defaclacl) a join pg_roles r on r.oid = a.grantee
   where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace
     and r.rolname in ('anon', 'authenticated');
  assert bad is null, 'postgres still gives new objects in public away by default (r = tables, S = sequences, f = functions): ' || bad;
end
$test$;

-- ---------------------------------------------------------------- 2. signed in, but not staff
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000a2", "email": "planner-tables-not-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r record; n bigint; refused boolean;
begin
  assert not public.is_planner_user(), 'the test account is staff';
  for r in select name, planner from t_new union all select name, false from t_views loop
    execute format('select count(*) from public.%I', r.name) into n;
    assert n = 0, format('an account that isn''t staff reads %s row(s) of %s', n, r.name);
  end loop;
  for r in select name, planner from t_new loop
    refused := false;
    begin
      execute format('insert into public.%I default values', r.name);
    exception when insufficient_privilege then refused := true;
    end;
    assert refused, format('an account that isn''t staff could add a row to %s', r.name);
    if r.planner then
      execute format('update public.%I set created_at = created_at', r.name);
      get diagnostics n = row_count;
      assert n = 0, format('an account that isn''t staff changed %s row(s) of %s', n, r.name);
      execute format('delete from public.%I', r.name);
      get diagnostics n = row_count;
      assert n = 0, format('an account that isn''t staff removed %s row(s) of %s', n, r.name);
    end if;
  end loop;
end
$test$;
reset role;

-- ---------------------------------------------------------------- 3. staff
insert into public.planner_users (email) values ('planner-tables-staff@example.com') on conflict do nothing;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000a1", "email": "planner-tables-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r record; n bigint; w bigint; t bigint; refused boolean;
begin
  assert public.is_planner_user(), 'the test account isn''t staff';
  for r in select name from t_new union all select name from t_views loop
    execute format('select count(*) from public.%I', r.name) into n;   -- every new table and view can be read
  end loop;
  select count(*) into n from public.airlines;
  assert n >= 6, 'staff don''t see the reference airlines';
  select id into w from public.worlds where name = 'Gander';
  assert w is not null, 'staff don''t see the world Gander';

  -- a write: add, change and remove a to-do and a step
  insert into public.todos (world_id, title) values (w, 'Access test to-do') returning id into t;
  insert into public.todo_items (world_id, todo_id, position, body) values (w, t, 1, 'a step');
  update public.todos set done = true, done_at = now() where id = t;
  get diagnostics n = row_count;
  assert n = 1, 'staff couldn''t change a to-do';
  assert (select done from public.todos where id = t), 'the change wasn''t saved';
  delete from public.todos where id = t;
  get diagnostics n = row_count;
  assert n = 1, 'staff couldn''t remove a to-do';
  assert not exists (select 1 from public.todo_items where todo_id = t), 'removing a to-do left its steps';

  -- staff read the log of what they just did, and can't edit it
  select count(*) into n from public.change_log where table_name in ('todos', 'todo_items') and (row_key ->> 'id')::bigint is not null
     and (new_values ->> 'todo_id' = t::text or row_key = jsonb_build_object('id', t));
  assert n >= 4, format('staff see %s log rows for their to-do, expected at least 4', n);
  refused := false;
  begin insert into public.change_log (table_name, row_key, op, actor) values ('todos', '{}', 'insert', 'planner');
  exception when insufficient_privilege then refused := true; end;
  assert refused, 'staff could add to change_log';
  refused := false;
  begin update public.change_log set actor = 'claude';
  exception when insufficient_privilege then refused := true; end;
  assert refused, 'staff could change change_log';
  refused := false;
  begin delete from public.change_log;
  exception when insufficient_privilege then refused := true; end;
  assert refused, 'staff could remove change_log rows';
end
$test$;
reset role;

do $$ begin raise notice 'planner tables access: all checks passed'; end $$;

-- The capture data (#13 build, pull request 3): who can reach it (design §5).
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations (both files: the adding one
-- and the removal Gitesh runs), inside a transaction that is rolled back. A failed check stops with an error that says
-- which.
--   1. From the catalogue: anon holds nothing at all on any table or view in public; game_flights and game_payments
--      have RLS on with one staff read rule, and authenticated may only read them; the three compatibility views are
--      security_invoker and read-only to authenticated; the capture's functions are closed except capture_ingest() and
--      capture_airlines(); parse_capture() is retired (apply_loads_from_capture() went with the clean-up); the capture tables carry their
--      world and airline, and every foreign key on them has an index.
--   2. Signed in with an email that isn't on planner_users: the new tables and views read no rows.
--   3. Signed in as staff: they read what the copy holds.

create temporary table t_capture (name text primary key, kind text not null) on commit drop;
insert into t_capture values
  ('game_flights', 'table'), ('game_payments', 'table'),
  ('game_loads', 'view'), ('game_flight_pnl', 'view'), ('game_ops_recent', 'view');
grant select on t_capture to authenticated;

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare bad text;
begin
  -- anon: nothing on any table or view in public, old or new, any privilege
  select string_agg(c.relname || ' ' || p.priv, ', ' order by c.relname) into bad
    from pg_class c join pg_namespace s on s.oid = c.relnamespace
    cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) as p(priv)
   where s.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f') and has_table_privilege('anon', c.oid, p.priv);
  assert bad is null, 'anon still holds on tables and views in public: ' || bad;

  -- the new tables: RLS on, one rule (staff read, checked once per query), read-only to authenticated
  select string_agg(t.name, ', ') into bad from t_capture t join pg_class c on c.oid = ('public.' || t.name)::regclass
   where t.kind = 'table' and not c.relrowsecurity;
  assert bad is null, 'RLS is off on: ' || bad;
  select string_agg(t.name || ' (' || coalesce(p.rules, 'none') || ')', ', ') into bad
    from t_capture t left join lateral (
      select string_agg(lower(cmd) || ' ' || array_to_string(roles, '+') || ' ' || coalesce(qual, ''), '; ') as rules
        from pg_policies where schemaname = 'public' and tablename = t.name) p on true
   where t.kind = 'table' and p.rules is distinct from 'select authenticated ( SELECT is_planner_user() AS is_planner_user)';
  assert bad is null, 'not exactly one staff read rule on: ' || bad;
  select string_agg(t.name || ' ' || p.priv, ', ') into bad
    from t_capture t cross join unnest(array['insert', 'update', 'delete', 'truncate', 'references', 'trigger']) as p(priv)
   where has_table_privilege('authenticated', 'public.' || t.name, p.priv);
  assert bad is null, 'authenticated can write: ' || bad;
  select string_agg(t.name, ', ') into bad from t_capture t
   where not has_table_privilege('authenticated', 'public.' || t.name, 'select');
  assert bad is null, 'staff can''t read: ' || bad;

  -- the views show the caller only what the caller may read
  select string_agg(t.name, ', ') into bad from t_capture t join pg_class c on c.oid = ('public.' || t.name)::regclass
   where t.kind = 'view' and (c.relkind <> 'v' or not coalesce('security_invoker=true' = any (c.reloptions), false));
  assert bad is null, 'not a security_invoker view: ' || bad;

  -- functions: the capture's entry points are open to the capture (anon with the key); the internal steps aren't; the
  -- retired ones are closed to signed-in accounts
  assert has_function_privilege('anon', 'public.capture_ingest(text, text, text, text, jsonb)', 'execute'), 'the capture can''t call capture_ingest()';
  assert has_function_privilege('anon', 'public.capture_airlines(text)', 'execute'), 'the capture can''t call capture_airlines()';
  assert not has_function_privilege('authenticated', 'public.parse_capture(bigint)', 'execute'), 'signed-in accounts can still call parse_capture()';
  assert to_regprocedure('public.apply_loads_from_capture(text)') is null
      or not has_function_privilege('authenticated', 'public.apply_loads_from_capture(text)', 'execute'), 'signed-in accounts can still call apply_loads_from_capture()';
  assert not has_function_privilege('anon', 'public.parse_capture(bigint)', 'execute'), 'anon can call parse_capture()';
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.pronamespace = 'private'::regnamespace
     and (has_function_privilege('anon', p.oid, 'execute')
          or (has_function_privilege('authenticated', p.oid, 'execute') and p.proname <> 'is_weekday_set'));
  assert bad is null, 'internal functions the data API''s roles can run: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid in ('public.capture_ingest(text, text, text, text, jsonb)'::regprocedure, 'public.capture_airlines(text)'::regprocedure,
                   'public.export_capture(text, integer)'::regprocedure)
     and not (p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false));
  assert bad is null, 'runs as owner without an empty search path, or doesn''t run as owner: ' || bad;

  -- every capture row carries its world and airline (#14)
  select string_agg(c.table_name || '.' || c.column_name, ', ') into bad from information_schema.columns c
   where c.table_schema = 'public' and c.is_nullable = 'YES'
     and (c.table_name, c.column_name) in (('game_capture_raw', 'world_id'), ('game_capture_raw', 'airline_id'),
         ('game_statement', 'world_id'), ('game_statement', 'airline_id'), ('game_events', 'world_id'), ('game_events', 'airline_id'),
         ('game_balance', 'world_id'), ('game_balance', 'airline_id'), ('game_balance', 'capture_day'),
         ('game_pnl', 'world_id'), ('game_pnl', 'airline_id'), ('game_pnl', 'capture_day'), ('capture_keys', 'world_id'),
         ('game_flights', 'world_id'), ('game_flights', 'airline_id'), ('game_payments', 'world_id'), ('game_payments', 'airline_id'));
  assert bad is null, 'capture columns that can be empty: ' || bad;
  select string_agg(c.conrelid::regclass::text || ' (' || c.conname || ')', ', ') into bad
    from pg_constraint c
   where c.contype = 'f'
     and c.conrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace and relname = any (array[
       'game_flights', 'game_payments', 'game_statement', 'game_events', 'game_balance', 'game_pnl', 'game_capture_raw', 'capture_keys']))
     and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = any (c.conkey));
  assert bad is null, 'foreign keys without an index: ' || bad;
end
$test$;

-- ---------------------------------------------------------------- 2. signed in, but not staff
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000b2", "email": "capture-not-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare r record; n bigint;
begin
  assert not public.is_planner_user(), 'the test account is staff';
  for r in select name from t_capture loop
    execute format('select count(*) from public.%I', r.name) into n;
    assert n = 0, format('an account that isn''t staff reads %s row(s) of %s', n, r.name);
  end loop;
end
$test$;
reset role;

-- ---------------------------------------------------------------- 3. staff
insert into public.planner_users (email) values ('capture-staff@example.com') on conflict do nothing;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000b1", "email": "capture-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare n bigint;
begin
  assert public.is_planner_user(), 'the test account isn''t staff';
  select count(*) into n from public.game_loads;
  assert n = (select count(*) from public.game_flights where flight_no is not null), 'staff don''t see every loads row';
  select count(*) into n from public.game_flight_pnl;
  assert n >= (select count(*) from public.game_flights where posted_at is not null), 'staff don''t see every flight''s money';
end
$test$;
reset role;

do $$ begin raise notice 'capture data access: all checks passed'; end $$;

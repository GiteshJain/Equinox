-- Nothing outside the planner's own path reads the old rows any more (#13 build, pull request 8): before the switch-over
-- (pull request 9) freezes planner_state and planner_loads, every function and view that names them must be one that
-- the switch-over deals with. Run by database/rehearse.sh on the copy of last night's backup, after the new migrations,
-- inside a transaction that is rolled back.
--   1. No function (pg_proc, every schema but Postgres' own) and no view names planner_state or planner_loads, except:
--      - the adapter: planner_state_version() (never earlier than the old row's last save), save_loads() (still writes
--        the old month documents), the loader (private.load_planner, private.load_planner_loads) and the side by side's
--        comparison (private.planner_state_check, in a message);
--      - the side by side's triggers (private.adapter_mirror_state, private.adapter_mirror_loads);
--      - the capture's loads step (private.apply_loads_from_capture), which keeps the old planner's month documents
--        current until the switch-over.
--      Anything else is listed and fails.
--   2. Who may call the functions this pull request changed is as before: the website's and the investor page's signed
--      out, the scripts' signed out with the ingest secret, the Photos screen's signed in; each runs as owner with an
--      empty search path. The two new internal functions are closed to the data API's roles and run as the caller.
--   3. Signed out, site_public() and export_for_report('planner') (with the ingest secret) answer: the getters they
--      call check their caller, so this proves they run as the functions' owner.

do $test$
declare bad text; v_allowed text[] := array[
    'public.planner_state_version', 'public.save_loads', 'private.load_planner', 'private.load_planner_loads',
    'private.planner_state_check', 'private.adapter_mirror_state', 'private.adapter_mirror_loads',
    'private.apply_loads_from_capture'];
  v_named text;
begin
  -- ---------------------------------------------------------------- 1. no reader left
  select string_agg(x.name, ', ' order by x.name) into bad
    from (select format('%s.%s(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) as name
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
             and p.prosrc ~ '\m(planner_state|planner_loads)\M'
             and (n.nspname || '.' || p.proname) <> all (v_allowed)) x;
  assert bad is null, 'these functions still name planner_state or planner_loads: ' || bad;
  select string_agg(c.relnamespace::regnamespace || '.' || c.relname, ', ') into bad
    from pg_class c
   where c.relkind in ('v', 'm') and c.relnamespace::regnamespace::text not in ('pg_catalog', 'information_schema')
     and pg_get_viewdef(c.oid) ~ '\m(planner_state|planner_loads)\M';
  assert bad is null, 'these views still name planner_state or planner_loads: ' || bad;
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname) into v_named
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\_%'
     and p.prosrc ~ '\m(planner_state|planner_loads)\M';
  raise notice 'no function or view outside the adapter, the side by side and the capture''s loads step names planner_state or planner_loads (those that do: %)',
    coalesce(v_named, 'none');

  -- ---------------------------------------------------------------- 2. who may call them
  select string_agg(x.f, ', ') into bad from (values
      ('public.site_public()', true, true), ('public.site_investor(text)', true, true), ('public.site_report(bigint, text)', true, true),
      ('public.export_for_report(text, text, text)', true, true), ('public.planner_data_set(text, text, jsonb)', true, true),
      ('public.site_admin(text, text, jsonb)', true, true), ('public.site_set_airline_logo(text, text, text)', false, true)) as x(f, anon, authed)
   where has_function_privilege('anon', x.f::regprocedure, 'execute') <> x.anon
      or has_function_privilege('authenticated', x.f::regprocedure, 'execute') <> x.authed;
  assert bad is null, 'who may call these changed: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid in ('public.site_public()'::regprocedure, 'public.site_investor(text)'::regprocedure,
                   'public.export_for_report(text, text, text)'::regprocedure, 'public.planner_data_set(text, text, jsonb)'::regprocedure,
                   'public.site_admin(text, text, jsonb)'::regprocedure, 'public.site_set_airline_logo(text, text, text)'::regprocedure)
     and not (p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false));
  assert bad is null, 'runs as owner without an empty search path, or doesn''t run as owner: ' || bad;
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid in ('private.research_apply(bigint, jsonb)'::regprocedure, 'private.world_mct_set(bigint, jsonb)'::regprocedure)
     and (p.prosecdef or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
          or not coalesce('search_path=""' = any (p.proconfig), false));
  assert bad is null, 'the new internal functions are open or run as owner: ' || bad;
  raise notice 'the changed functions are called by the same roles as before, each runs as owner with an empty search path; the two new internal ones are closed';
end
$test$;

-- ---------------------------------------------------------------- 3. called as the website and the scripts call them
-- Signed out (anon), as the data API runs them: the getters these functions call check their caller, so this proves
-- they run as the functions' owner and not as the visitor.
create temporary table t_secret on commit drop as select 'website-test-' || gen_random_uuid() as s;
insert into public.ingest_secret (secret) select s from t_secret;
grant select on t_secret to anon;
set local role anon;
do $test$
declare a jsonb; s text := (select s from t_secret);
begin
  a := public.site_public();
  assert jsonb_array_length(a -> 'airlines') > 0 and jsonb_typeof(a -> 'freqs') = 'array' and jsonb_typeof(a -> 'content') = 'object',
    'signed out, site_public() doesn''t give the airlines, frequencies and content';
  assert public.site_investor('not the password') = '{"ok": false}'::jsonb, 'signed out, site_investor() answers a wrong password';
  a := public.export_for_report(s, 'planner');
  assert jsonb_typeof(a -> 'state' -> 'freqs') = 'array' and jsonb_typeof(a -> 'loads') = 'object',
    'signed out with the ingest secret, export_for_report(''planner'') doesn''t give the two documents';
  raise notice 'signed out: site_public() and export_for_report(''planner'') (with the ingest secret) answer as the website and the scripts need';
end
$test$;
reset role;

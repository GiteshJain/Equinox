-- The planner's data in the tables, and the adapter's read side (#13 build, pull request 4; design §8, §9). Run by
-- database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that is rolled
-- back. A failed check stops with an error that says where (paths and counts, never values).
--   1. planner_loads_get() equals every month of planner_loads, with only the differences design §9 allows; each
--      allowed difference used is printed with how often. (planner_state_get() against planner_state is
--      planner_load_state_test.sql.)
--   2. The keys kept in extra (expected: none, beyond each aircraft's place in the old planner's two lists).
--   3. Running the loader a second time changes no rows, and the documents stay the same.
--   4. Speed: how long each getter takes on the copy.
--   5. Who may call them: signed out nobody; signed in but not staff, refused; staff get the same documents as postgres.

-- Since the switch-over (#13, pull request 9) the old rows are frozen. The night they freeze (during this rehearsal,
-- database/tests/before/switch_over_before.sql) they still equal the getters, and are compared as before; on any night
-- after, the old rows are older than the tables by design, so they aren't (switch_over_test.sql checks the rollback's
-- copy instead).
create function pg_temp.old_rows_current() returns boolean language plpgsql as $$
declare v boolean;
begin
  if private.planner_frozen_since('public.planner_state'::regclass) is null then return true; end if;
  if to_regclass('rehearsal_before.planner_frozen') is null then return false; end if;
  execute 'select not frozen from rehearsal_before.planner_frozen' into v;
  return coalesce(v, false);
end
$$;

-- the differences between two documents, by where they are: list positions as [], keys of keyed sections as {}
create function pg_temp.places(p_old jsonb, p_new jsonb) returns table (kind text, place text, n bigint) language sql as $$
  select d.kind,
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(d.path, '\[\d+\]', '[]', 'g'),
           '^(\$\.(plans|cash|fixed7|interline|routeEdits|routeCabin|monthly|dismissed|cabinKeep|ref\.markets|ref\.curfews|ref\.gameLinks|ref\.utcOverrides))\.[^.\[]+', '\1.{}'),
           '^\$\.\d{4}-\d{2}-\d{2}', '$.{day}'), '\.f\..+$', '.f.{flight}'),
         count(*)
    from private.planner_json_differences(p_old, p_new) d
   group by 1, 2
$$;
create temporary table t_pl (k text primary key, v jsonb) on commit drop;

-- ---------------------------------------------------------------- 1. the loads documents equal today's
do $test$
declare bad text; used text; n_months int; n_days int;
begin
  insert into t_pl values ('state', (public.planner_state_get() ->> 'json')::jsonb),
    ('loads', (select jsonb_object_agg(g.month, g.json::jsonb) from public.planner_loads_get() g));
  if not pg_temp.old_rows_current() then
    raise notice 'planner_loads frozen since % (before last night''s backup): older than the tables by design, not compared; switch_over_test.sql compares the rollback''s copy',
      private.planner_frozen_since('public.planner_loads'::regclass);
    return;
  end if;

  -- loads: every month, day and flight
  select string_agg(coalesce(o.month, n.month), ', ') into bad
    from public.planner_loads o full join public.planner_loads_get() n on n.month = o.month
   where o.month is null or n.month is null;
  assert bad is null, 'planner_loads_get() and planner_loads don''t have the same months: ' || bad;
  select string_agg(x.month || ' ' || x.place || ' ×' || x.n, ', ' order by x.month, x.place) into bad
    from (select o.month, p.place, p.n from public.planner_loads o join public.planner_loads_get() g on g.month = o.month
            cross join lateral pg_temp.places(o.json::jsonb, g.json::jsonb) p where p.kind = 'differs') x;
  assert bad is null, 'planner_loads_get() differs from planner_loads at: ' || bad;
  select string_agg(kind || ' ×' || n || ' (' || places || ')', '; ' order by kind) into used
    from (select y.kind, sum(y.n) as n, string_agg(distinct y.place, ', ') as places
            from (select p.kind, p.place, p.n from public.planner_loads o join public.planner_loads_get() g on g.month = o.month
                    cross join lateral pg_temp.places(o.json::jsonb, g.json::jsonb) p
                  union all
                  select 'savedAt and version', 'each month''s saved_at', count(*) from public.planner_loads o
                    join public.planner_loads_get() g on g.month = o.month where g.saved_at <> o.saved_at) y
           where y.n > 0 group by y.kind) x;
  select count(*), sum((select count(*) from jsonb_object_keys(o.json::jsonb))) into n_months, n_days from public.planner_loads o;
  raise notice 'planner_loads_get() equals planner_loads (% months, % days); allowed differences used: %', n_months, n_days, coalesce(used, 'none');
end
$test$;

-- ---------------------------------------------------------------- 2. what went to extra
do $test$
declare v_keys text;
begin
  select string_agg(t || '.' || k || ' ×' || n, ', ' order by t, k) into v_keys from (
    select 'tails' as t, e.key as k, count(*) as n from public.aircraft a, jsonb_each(coalesce(a.extra -> 'tail', '{}'::jsonb)) e group by 1, 2
    union all select 'deliveries', e.key, count(*) from public.aircraft a, jsonb_each(coalesce(a.extra -> 'delivery', '{}'::jsonb)) e group by 1, 2
    union all select 'freqs', e.key, count(*) from public.rotations r, jsonb_each(r.extra) e group by 1, 2
    union all select 'plans', e.key, count(*) from public.plan_cards p, jsonb_each(p.extra) e group by 1, 2
    union all select 'todos', e.key, count(*) from public.todos t, jsonb_each(t.extra) e group by 1, 2
    union all select 'farePlan', e.key, count(*) from public.fare_plan f, jsonb_each(f.extra) e group by 1, 2) x;
  raise notice 'kept in extra: % (and every aircraft''s place in the old planner''s lists: % tails, % deliveries)', coalesce(v_keys, 'nothing'),
    (select count(*) from public.aircraft where extra ? 'tails_index'), (select count(*) from public.aircraft where extra ? 'deliveries_index');
end
$test$;

-- ---------------------------------------------------------------- 3. the loader a second time, and 4. speed
do $test$
declare w bigint := (select id from public.worlds where is_default); v_res jsonb; bad text; n bigint; t text;
  t0 timestamptz; v_state numeric[] := '{}'; v_loads numeric[] := '{}'; v_ver numeric[] := '{}'; i int;
begin
  -- (a second run reads the old rows: on a night after the switch-over they are older than the tables, so it would
  -- write them back; it runs only while they are current)
  if pg_temp.old_rows_current() then
  v_res := private.load_planner(w);
  -- no row of any planner table, nor of the events whose due times it fills, was written by the second run
  for t in select unnest(array['worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types', 'countries', 'airports',
                               'world_airports', 'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps', 'markets',
                               'service_profiles', 'routes', 'rotations', 'flight_legs', 'plan_cards', 'plan_card_legs', 'todos',
                               'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements', 'monthly_checks',
                               'dismissals', 'cash_entries', 'load_entries', 'load_days', 'settings', 'world_rules', 'game_events']) loop
    execute format('select count(*) from public.%I where xmin = pg_current_xact_id()::xid', t) into n;
    if n > 0 then bad := concat_ws(', ', bad, t || ' ' || n); end if;
  end loop;
  assert bad is null, 'running the loader a second time changed rows: ' || bad;
  assert (public.planner_state_get() ->> 'json')::jsonb = (select v from t_pl where k = 'state'),
    'planner_state_get() changed after the loader ran a second time';
  assert (select jsonb_object_agg(g.month, g.json::jsonb) from public.planner_loads_get() g) = (select v from t_pl where k = 'loads'),
    'planner_loads_get() changed after the loader ran a second time';
  -- (rows removed would show as a difference in the documents; rows added would carry this transaction's xmin)
  end if;
  for i in 1 .. 3 loop
    t0 := clock_timestamp(); perform public.planner_state_get(); v_state := v_state || extract(epoch from clock_timestamp() - t0) * 1000;
    t0 := clock_timestamp(); perform count(*) from public.planner_loads_get(); v_loads := v_loads || extract(epoch from clock_timestamp() - t0) * 1000;
    t0 := clock_timestamp(); perform public.planner_state_version(); v_ver := v_ver || extract(epoch from clock_timestamp() - t0) * 1000;
  end loop;
  raise notice '%speed on the copy (best of 3): planner_state_get() % ms, planner_loads_get() % ms, planner_state_version() % ms',
    case when pg_temp.old_rows_current() then 'the loader a second time changed no rows; ' else '' end, round((select min(x) from unnest(v_state) x)), round((select min(x) from unnest(v_loads) x), 1), round((select min(x) from unnest(v_ver) x), 2);
end
$test$;

-- ---------------------------------------------------------------- 5. who may call them
insert into public.planner_users (email) values ('load-test-staff@example.com') on conflict do nothing;
grant select on t_pl to authenticated;
do $test$
begin
  assert not has_function_privilege('anon', 'public.planner_state_get(bigint)', 'execute')
     and not has_function_privilege('anon', 'public.planner_state_version(bigint)', 'execute')
     and not has_function_privilege('anon', 'public.planner_loads_get(bigint)', 'execute'), 'signed out, the getters can be called';
  assert has_function_privilege('authenticated', 'public.planner_state_get(bigint)', 'execute'), 'signed in, planner_state_get() can''t be called';
  assert not has_table_privilege('anon', 'public.capture_cash', 'select'), 'signed out, capture_cash can be read';
  assert (select not p.prosecdef from pg_proc p where p.oid = 'public.planner_state_get(bigint)'::regprocedure)
     and (select not p.prosecdef from pg_proc p where p.oid = 'public.planner_loads_get(bigint)'::regprocedure)
     and (select not p.prosecdef from pg_proc p where p.oid = 'public.planner_state_version(bigint)'::regprocedure),
    'a getter runs as its owner';
  assert (select coalesce('security_invoker=true' = any (c.reloptions), false) from pg_class c where c.oid = 'public.capture_cash'::regclass),
    'capture_cash isn''t security_invoker';
end
$test$;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c4", "email": "load-test-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  begin perform public.planner_state_get(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff read planner_state_get()';
  refused := false;
  begin perform public.planner_loads_get(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff read planner_loads_get()';
  assert (select count(*) from public.capture_cash) = 0, 'an account that isn''t staff reads capture_cash';
end
$test$;
reset role;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000c5", "email": "load-test-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
begin
  assert (public.planner_state_get() ->> 'json')::jsonb = (select v from t_pl where k = 'state'),
    'staff get a different planner_state_get() from postgres';
  assert (select jsonb_object_agg(g.month, g.json::jsonb) from public.planner_loads_get() g) = (select v from t_pl where k = 'loads'),
    'staff get a different planner_loads_get() from postgres';
end
$test$;
reset role;

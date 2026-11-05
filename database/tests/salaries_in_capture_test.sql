-- Salaries inside the evening capture (manual §7; migration 20261105020000; brief
-- docs/briefs/2026-11-04-salaries-in-capture.md, option A). Run by database/rehearse.sh on the copy of last night's
-- backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an error that
-- says which.
--   1. settings.salary_above_average_pct: world level in every world, in percent, described, with since and reason; 5 in
--      the default world; no airline's own.
--   2. capture_airlines(): called as before (as owner with an empty search path, stable, anon and authenticated may call
--      it, not public), described with the new key; with a key of the default world, signed out as the capture calls it,
--      it answers the setting as salary_above_average_pct beside the airlines, the scan and the market plan; a world
--      without the setting answers null; a wrong key is refused as before.
--      world_rules.capture_salary_step kept, true, its description no longer the separate script's.
--   3. Nothing about salaries is stored: no table or column named for salaries came with the migration.

create temporary table t_sal (k text primary key, v jsonb) on commit drop;
grant select, insert on t_sal to anon;

-- ---------------------------------------------------------------- 1. the setting
do $test$
declare dw bigint := (select id from public.worlds where is_default);
begin
  assert not exists (select 1 from public.worlds w where not exists (
           select 1 from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = 'salary_above_average_pct'
              and s.unit = 'percent' and length(coalesce(s.description, '')) > 100 and s.since is not null and coalesce(s.reason, '') <> '')),
    'a world has no described salary_above_average_pct setting in percent with since and reason';
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'salary_above_average_pct') = '5'::jsonb,
    'the default world''s salary_above_average_pct isn''t 5';
  assert not exists (select 1 from public.settings s where s.key = 'salary_above_average_pct' and s.airline_id is not null),
    'an airline has its own salary_above_average_pct';
  assert position('never lowered' in (select s.description from public.settings s where s.world_id = dw and s.airline_id is null
                                        and s.key = 'salary_above_average_pct')) > 0,
    'salary_above_average_pct''s description doesn''t say salaries are never lowered';
  -- the permission row is kept (manual §9), still true, its description naming the capture
  assert (select r.value = 'true'::jsonb
                 and coalesce(r.description, '') <> 'Setting salaries by script is allowed in Gander (since 10 Oct a separate script, run by hand on one airline)'
            from public.world_rules r where r.world_id = dw and r.key = 'capture_salary_step' and r.kind = 'permission'),
    'the default world''s capture_salary_step permission row is gone, not true, or still says the separate script is how salaries are set';
  raise notice 'salary_above_average_pct: 5 percent in the default world, described, in every world, no airline''s own';
end
$test$;

-- ---------------------------------------------------------------- 2. capture_airlines()
do $test$
declare f text := 'public.capture_airlines(text)';
begin
  assert (select p.prosecdef and p.provolatile = 's' and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = f::regprocedure),
    f || ' doesn''t run as owner with an empty search path, or isn''t stable';
  assert has_function_privilege('anon', f, 'execute') and has_function_privilege('authenticated', f, 'execute'), f || ' can''t be called as before';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid = f::regprocedure and a.grantee = 0), f || ' is open to public';
  assert position('salary_above_average_pct' in coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 0, f || '''s description doesn''t name salary_above_average_pct';
  assert position('market_every_days, market_due' in coalesce(obj_description(f::regprocedure, 'pg_proc'), '')) > 0, f || '''s description lost its market part';
end
$test$;

do $setup$
declare w2 bigint;
begin
  insert into public.capture_keys (label, key_hash, world_id)
  select 'salaries in capture test, default world', extensions.crypt('salaries-test-default-key', extensions.gen_salt('bf')), w.id
    from public.worlds w where w.is_default;
  -- a world of its own with no salary setting
  insert into public.worlds (name, game_host, kind) values ('salaries test', 'salaries.test', 'exclusive') returning id into w2;
  insert into public.capture_keys (label, key_hash, world_id)
  values ('salaries in capture test, world without the setting', extensions.crypt('salaries-test-bare-key', extensions.gen_salt('bf')), w2);
end
$setup$;

set local role anon;
do $test$
begin
  insert into t_sal values ('default', public.capture_airlines('salaries-test-default-key')),
                           ('bare', public.capture_airlines('salaries-test-bare-key')),
                           ('bad', public.capture_airlines('not the key'));
end
$test$;
reset role;

do $test$
declare r jsonb := (select v from t_sal where k = 'default'); b jsonb := (select v from t_sal where k = 'bare');
begin
  assert r ->> 'ok' = 'true' and jsonb_typeof(r -> 'airlines') = 'array' and jsonb_array_length(r -> 'airlines') > 0,
    'the default world''s key didn''t answer with its airlines: ' || coalesce(r ->> 'error', 'no error');
  assert r -> 'salary_above_average_pct' = '5'::jsonb, 'capture_airlines() answers salary_above_average_pct ' || coalesce(r ->> 'salary_above_average_pct', 'null') || ', not 5';
  assert r ? 'scan_due' and r ? 'market_due' and r ? 'world', 'capture_airlines() lost the scan, the market plan or the world';
  assert b ->> 'ok' = 'true' and b ? 'salary_above_average_pct' and b -> 'salary_above_average_pct' = 'null'::jsonb,
    'a world without the setting doesn''t answer salary_above_average_pct null: ' || b::text;
  assert (select v from t_sal where k = 'bad') = '{"ok": false, "error": "bad key"}'::jsonb, 'capture_airlines() doesn''t refuse a wrong key as before';
  raise notice 'capture_airlines(): salary_above_average_pct 5 with the default world''s key, null in a world without the setting; wrong key refused';
end
$test$;

-- ---------------------------------------------------------------- 3. nothing about salaries stored
do $test$
declare bad text;
begin
  select string_agg(c.relname, ', ') into bad from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'private') and c.relkind in ('r', 'p', 'v', 'm') and c.relname ~* 'salar';
  assert bad is null, 'a table or view named for salaries exists: ' || bad;
  raise notice 'no table or view about salaries';
end
$test$;

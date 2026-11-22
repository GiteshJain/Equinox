-- The unused functions and table removed (to-do 248, Gitesh 15 Nov 2026; migration
-- 20261122100000_remove_unused_functions.sql, which Gitesh runs in the SQL editor). Run by database/rehearse.sh on the
-- copy of last night's backup, after the new migrations, inside a transaction that is rolled back. Needs nothing from
-- before the changes, so it passes the same on the night the file is pending and on every night after it is live.
--   1. Gone: save_script(), export_repo_bootstrap() and export_capture() (any arguments, in any schema), and the table
--      planner_scripts.
--   2. Nothing that stays names them: no function's code (comments left out), view, row rule or scheduled job.
--   3. The capture's own entry points are still there and open to the capture as before.

do $test$
declare bad text; v_pat constant text := '\m(save_script|export_repo_bootstrap|export_capture|planner_scripts)\M';
begin
  -- 1. gone
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.proname in ('save_script', 'export_repo_bootstrap', 'export_capture');
  assert bad is null, 'still there: ' || bad;
  select string_agg(c.oid::regclass::text, ', ') into bad from pg_class c where c.relname = 'planner_scripts';
  assert bad is null, 'still there: ' || bad;

  -- 2. nothing that stays names them
  select string_agg(n.nspname || '.' || p.proname, ', ') into bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private')
     and regexp_replace(regexp_replace(coalesce(p.prosrc, ''), '/\*.*?\*/', ' ', 'g'), '--[^' || chr(10) || ']*', ' ', 'g') ~ v_pat;
  assert bad is null, 'functions whose code still names them: ' || bad;
  select string_agg(v.schemaname || '.' || v.viewname, ', ') into bad from pg_views v
   where v.schemaname in ('public', 'private') and v.definition ~ v_pat;
  assert bad is null, 'views that still name them: ' || bad;
  select string_agg(pl.schemaname || '.' || pl.tablename || ' ' || pl.policyname, ', ') into bad from pg_policies pl
   where (coalesce(pl.qual, '') || ' ' || coalesce(pl.with_check, '')) ~ v_pat;
  assert bad is null, 'row rules that still name them: ' || bad;
  if to_regclass('cron.job') is not null then
    execute 'select string_agg(jobname, '', '') from cron.job where command ~ $1' into bad using v_pat;
    assert bad is null, 'scheduled jobs that still name them: ' || bad;
  end if;

  -- 3. the capture's entry points are untouched
  assert has_function_privilege('anon', 'public.capture_ingest(text, text, text, text, jsonb)', 'execute')
     and has_function_privilege('anon', 'public.capture_airlines(text)', 'execute'),
    'the capture can''t call capture_ingest() or capture_airlines() any more';

  raise notice 'unused functions removed: save_script(), export_repo_bootstrap(), export_capture() and planner_scripts are gone, nothing that stays names them, the capture''s entry points are as before';
end
$test$;

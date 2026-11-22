-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), after the merge: it drops functions and
-- a table, so it isn't applied from a chat. Paste the whole file and press Run, once.
--
-- Removes three unused functions, save_script(), export_repo_bootstrap() and export_capture(), and the old table
-- planner_scripts (to-do 248, Gitesh 15 Nov 2026, from to-do 218 step 1).
--
-- Why: they are leftovers from before the repository existed (decision #1) and nothing calls them any more. All three
-- run as owner and anon may call them (each asks for the ingest secret first), so they were an unneeded way in.
-- planner_scripts held copies of Claude's old scripts (the repository is the source); only save_script() wrote it and
-- only export_repo_bootstrap() read it.
--
-- The check at the top stops the file, changing nothing, if anything that stays still names what it drops: a
-- function's code (comments left out), a view, a row rule, a trigger or a scheduled job. Nothing below cascades, so
-- Postgres itself also refuses a drop that something still depends on, and the file runs as one transaction: all of it
-- happens or none of it does. Run twice, the second run finds nothing to drop and changes nothing.
-- To undo it: restore the three functions and the table from last night's copy (the README in equinox-backups); their
-- last definitions are in database/migrations/20261005050600_planner_scripts.sql, 20261005051903_ingest_scripts.sql,
-- 20261008151450_export_repo_bootstrap_rpc.sql and 20261009230000_capture_data.sql.

do $guard$
declare
  v_fns constant text[] := array['public.save_script(text, text, text)', 'public.export_repo_bootstrap(text)',
                                 'public.export_capture(text, integer)'];
  v_rels constant text[] := array['public.planner_scripts'];
  v_fn_oids oid[]; v_rel_oids oid[]; v_users text[]; v_jobs text[];
  v_pat constant text := '\m(save_script|export_repo_bootstrap|export_capture|planner_scripts)\M';
  nl constant text := chr(10);
begin
  v_fn_oids := array(select to_regprocedure(f)::oid from unnest(v_fns) f where to_regprocedure(f) is not null);
  v_rel_oids := array(select to_regclass(r)::oid from unnest(v_rels) r where to_regclass(r) is not null);
  v_users := array(
    -- functions that stay, in our two schemas: their code, without comments
    select 'function ' || n.nspname || '.' || p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
      from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.prokind in ('f', 'p') and not (p.oid = any (v_fn_oids))
       and regexp_replace(regexp_replace(coalesce(p.prosrc, ''), '/\*.*?\*/', ' ', 'g'), '--[^' || nl || ']*', ' ', 'g') ~ v_pat
    union all
    select 'view ' || v.schemaname || '.' || v.viewname from pg_catalog.pg_views v
     where v.schemaname in ('public', 'private') and v.definition ~ v_pat
    union all
    select 'row rule "' || pl.policyname || '" on ' || pl.schemaname || '.' || pl.tablename from pg_catalog.pg_policies pl
     where to_regclass(quote_ident(pl.schemaname) || '.' || quote_ident(pl.tablename))::oid <> all (v_rel_oids)
       and (coalesce(pl.qual, '') || ' ' || coalesce(pl.with_check, '')) ~ v_pat
    union all
    select 'trigger ' || t.tgname || ' on ' || t.tgrelid::regclass::text from pg_catalog.pg_trigger t
     where not t.tgisinternal and t.tgfoid = any (v_fn_oids) and t.tgrelid <> all (v_rel_oids)
     order by 1);
  if to_regclass('cron.job') is not null then
    execute 'select array(select ''scheduled job '' || j.jobname from cron.job j where j.command ~ $1 order by 1)' into v_jobs using v_pat;
    v_users := v_users || v_jobs;
  end if;
  if cardinality(v_users) > 0 then
    raise exception 'stopped, nothing changed: % still name what this file drops: %', cardinality(v_users), array_to_string(v_users, '; ');
  end if;
  raise notice 'checked: nothing that stays names what this file drops (% of 3 functions and % of 1 table still there)',
    cardinality(v_fn_oids), cardinality(v_rel_oids);
end
$guard$;

-- the functions first (two of them use the table), then the table; nothing cascades
drop function if exists public.save_script(text, text, text);
drop function if exists public.export_repo_bootstrap(text);
drop function if exists public.export_capture(text, integer);
drop table if exists public.planner_scripts;

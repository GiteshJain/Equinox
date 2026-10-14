-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), AFTER the Building chat has applied
-- 20261014200000_clean_up.sql: it drops tables and functions, so it isn't applied from a chat. Paste the whole file and
-- press Run; the Building chat then records it and checks it.
--
-- The clean-up, part 2 of 2 (decision #18, build pull request 14; spec docs/specs/2026-10-14-clean-up.md): the old
-- planner's adapter goes, with the tables only it used.
--   Tables: planner_state and planner_loads (the old planner's two documents, frozen since the switch-over), planner_meta
--     and planner_data (its growth rules and route research documents; the tables have both), and the tables #13 renamed
--     and kept (game_loads_before_13, backup_runs_before_13). Their triggers go with them.
--   The view adapter_check_days (the side by side's days).
--   Functions: the getters and savers (planner_state_get, planner_state_put, planner_state_version, planner_loads_get,
--     save_loads, planner_item_put, planner_item_delete), export_planner_data, the freeze, the side by side and its
--     counts, the loader and the save steps (load_planner*, planner_apply*), the capture's old loads step
--     (apply_loads_from_capture, both), loads_day_captured (now only the captured figures' own rule,
--     private.fig_day_captured, is used) and the helpers only they used.
-- The backups and the monthly archive name none of these (they copy whatever tables there are; the archived tables stay
-- as they are), so they run as before.
--
-- The check at the top stops the file, changing nothing, if 20261014200000_clean_up.sql isn't applied yet, or if anything
-- that stays still names something it drops: a function's code (comments left out), a view, a row rule, a trigger or a
-- scheduled job. Postgres itself refuses any drop that something it tracks still depends on (nothing below cascades),
-- and the file runs as one transaction, so either all of it happens or none of it does.
-- To undo it: restore the dropped tables and functions from last night's copy (the README in equinox-backups), or ask
-- the Building chat; nothing the planner or the website reads is here.

do $guard$
declare
  v_fns constant text[] := array[
    'public.adapter_clean_days(bigint, timestamp with time zone)', 'public.apply_loads_from_capture(text)',
    'public.export_planner_data(text)', 'public.loads_day_captured(bigint, date)', 'public.planner_item_delete(text, text)',
    'public.planner_item_put(text, text, jsonb)', 'public.planner_loads_get(bigint)', 'public.planner_state_get(bigint)',
    'public.planner_state_put(text, bigint, bigint, text)', 'public.planner_state_version(bigint)',
    'public.save_loads(text, jsonb)', 'public.touch_updated_at()',
    'private.adapter_mirror_loads()', 'private.adapter_mirror_state()', 'private.adapter_seen(text)',
    'private.apply_loads_from_capture(bigint)', 'private.capex_key(text, date, text, numeric, text)',
    'private.clock_min(text)', 'private.fig_eq_off(text)', 'private.freeze_planner_state()',
    'private.growth_key(text, date, text, text)', 'private.json_date(jsonb)', 'private.json_object_or_empty(text)',
    'private.json_ts(jsonb)', 'private.load_planner(bigint)', 'private.load_planner_extra(bigint, jsonb)',
    'private.load_planner_fleet(bigint, jsonb)', 'private.load_planner_loads(bigint)',
    'private.load_planner_money(bigint, jsonb, timestamp with time zone)', 'private.load_planner_network(bigint, jsonb, jsonb)',
    'private.load_planner_places(bigint, jsonb, jsonb, jsonb)', 'private.load_planner_reference(bigint, jsonb, jsonb)',
    'private.load_planner_tidy(bigint, jsonb, jsonb, jsonb)', 'private.load_planner_work(bigint, jsonb)',
    'private.loads_mirror_days(bigint, jsonb, timestamp with time zone)',
    'private.planner_apply(bigint, jsonb, text, timestamp with time zone, text, text, text)',
    'private.planner_apply_extra(bigint)', 'private.planner_apply_fleet(bigint)', 'private.planner_apply_flights(bigint)',
    'private.planner_apply_money(bigint)', 'private.planner_apply_places(bigint)', 'private.planner_apply_reference(bigint)',
    'private.planner_apply_routes(bigint)', 'private.planner_apply_tidy(bigint)', 'private.planner_apply_work(bigint, boolean)',
    'private.planner_doc_with_item(jsonb, text, text, jsonb)', 'private.planner_duplicates(jsonb)',
    'private.planner_extra(jsonb, text[], jsonb)', 'private.planner_frozen()', 'private.planner_frozen_since(regclass)',
    'private.planner_items(jsonb)', 'private.planner_json_diff(jsonb, jsonb, text, text, boolean)',
    'private.planner_json_differences(jsonb, jsonb, text, text, boolean)', 'private.planner_place(text)',
    'private.planner_ref_blank(text, text)', 'private.planner_state_check(bigint, jsonb, bigint, jsonb)',
    'private.planner_touched(bigint, timestamp with time zone, text)', 'private.unfreeze_planner_state()',
    'private.weekday_set(text)'];
  v_rels constant text[] := array['public.planner_state', 'public.planner_loads', 'public.planner_meta', 'public.planner_data',
    'public.game_loads_before_13', 'public.backup_runs_before_13', 'public.adapter_check_days'];
  v_fn_oids oid[]; v_rel_oids oid[]; v_pat text; v_users text[]; v_jobs text[];
  nl constant text := chr(10);
begin
  if to_regprocedure('public.loads_by_day(bigint, date, date)') is null then
    raise exception 'stopped, nothing changed: apply 20261014200000_clean_up.sql first (loads_by_day() isn''t there yet)';
  end if;
  v_fn_oids := array(select to_regprocedure(f)::oid from unnest(v_fns) f where to_regprocedure(f) is not null);
  v_rel_oids := array(select to_regclass(r)::oid from unnest(v_rels) r where to_regclass(r) is not null);
  -- every name dropped, as a whole word
  v_pat := '\m(' || array_to_string(array(
             select distinct regexp_replace(x, '^[a-z]+\.([a-z_0-9]+).*$', '\1') from unnest(v_fns || v_rels) x), '|') || ')\M';
  v_users := array(
    -- functions that stay, in our two schemas: their code, without comments
    select 'function ' || n.nspname || '.' || p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
      from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.prokind in ('f', 'p') and not (p.oid = any (v_fn_oids))
       and regexp_replace(regexp_replace(coalesce(p.prosrc, ''), '/\*.*?\*/', ' ', 'g'), '--[^' || nl || ']*', ' ', 'g') ~ v_pat
    union all
    select 'view ' || v.schemaname || '.' || v.viewname from pg_catalog.pg_views v
     where v.schemaname in ('public', 'private') and to_regclass(quote_ident(v.schemaname) || '.' || quote_ident(v.viewname))::oid <> all (v_rel_oids)
       and v.definition ~ v_pat
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
  raise notice 'checked: nothing that stays names what this file drops (% functions, % tables and views)', cardinality(v_fn_oids), cardinality(v_rel_oids);
end
$guard$;

-- the tables first (their triggers go with them), then the view, then the functions; nothing cascades
drop table if exists public.planner_state;
drop table if exists public.planner_loads;
drop table if exists public.planner_meta;
drop table if exists public.planner_data;
drop table if exists public.game_loads_before_13;
drop table if exists public.backup_runs_before_13;
drop view if exists public.adapter_check_days;

drop function if exists public.adapter_clean_days(bigint, timestamp with time zone);
drop function if exists public.apply_loads_from_capture(text);
drop function if exists public.export_planner_data(text);
drop function if exists public.loads_day_captured(bigint, date);
drop function if exists public.planner_item_delete(text, text);
drop function if exists public.planner_item_put(text, text, jsonb);
drop function if exists public.planner_loads_get(bigint);
drop function if exists public.planner_state_get(bigint);
drop function if exists public.planner_state_put(text, bigint, bigint, text);
drop function if exists public.planner_state_version(bigint);
drop function if exists public.save_loads(text, jsonb);
drop function if exists public.touch_updated_at();
drop function if exists private.adapter_mirror_loads();
drop function if exists private.adapter_mirror_state();
drop function if exists private.adapter_seen(text);
drop function if exists private.apply_loads_from_capture(bigint);
drop function if exists private.capex_key(text, date, text, numeric, text);
drop function if exists private.clock_min(text);
drop function if exists private.fig_eq_off(text);
drop function if exists private.freeze_planner_state();
drop function if exists private.growth_key(text, date, text, text);
drop function if exists private.json_date(jsonb);
drop function if exists private.json_object_or_empty(text);
drop function if exists private.json_ts(jsonb);
drop function if exists private.load_planner(bigint);
drop function if exists private.load_planner_extra(bigint, jsonb);
drop function if exists private.load_planner_fleet(bigint, jsonb);
drop function if exists private.load_planner_loads(bigint);
drop function if exists private.load_planner_money(bigint, jsonb, timestamp with time zone);
drop function if exists private.load_planner_network(bigint, jsonb, jsonb);
drop function if exists private.load_planner_places(bigint, jsonb, jsonb, jsonb);
drop function if exists private.load_planner_reference(bigint, jsonb, jsonb);
drop function if exists private.load_planner_tidy(bigint, jsonb, jsonb, jsonb);
drop function if exists private.load_planner_work(bigint, jsonb);
drop function if exists private.loads_mirror_days(bigint, jsonb, timestamp with time zone);
drop function if exists private.planner_apply(bigint, jsonb, text, timestamp with time zone, text, text, text);
drop function if exists private.planner_apply_extra(bigint);
drop function if exists private.planner_apply_fleet(bigint);
drop function if exists private.planner_apply_flights(bigint);
drop function if exists private.planner_apply_money(bigint);
drop function if exists private.planner_apply_places(bigint);
drop function if exists private.planner_apply_reference(bigint);
drop function if exists private.planner_apply_routes(bigint);
drop function if exists private.planner_apply_tidy(bigint);
drop function if exists private.planner_apply_work(bigint, boolean);
drop function if exists private.planner_doc_with_item(jsonb, text, text, jsonb);
drop function if exists private.planner_duplicates(jsonb);
drop function if exists private.planner_extra(jsonb, text[], jsonb);
drop function if exists private.planner_frozen();
drop function if exists private.planner_frozen_since(regclass);
drop function if exists private.planner_items(jsonb);
drop function if exists private.planner_json_diff(jsonb, jsonb, text, text, boolean);
drop function if exists private.planner_json_differences(jsonb, jsonb, text, text, boolean);
drop function if exists private.planner_place(text);
drop function if exists private.planner_ref_blank(text, text);
drop function if exists private.planner_state_check(bigint, jsonb, bigint, jsonb);
drop function if exists private.planner_touched(bigint, timestamp with time zone, text);
drop function if exists private.unfreeze_planner_state();
drop function if exists private.weekday_set(text);

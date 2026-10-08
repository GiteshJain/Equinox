create or replace function public.export_repo_bootstrap(p_secret text) returns jsonb
language plpgsql security definer set search_path = public, supabase_migrations as $$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'scripts', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'content', content) order by name), '[]'::jsonb) from public.planner_scripts),
    'migrations', (select coalesce(jsonb_agg(jsonb_build_object('version', version, 'name', name, 'statements', statements) order by version), '[]'::jsonb) from supabase_migrations.schema_migrations),
    'functions', (select coalesce(jsonb_agg(jsonb_build_object('name', p.proname, 'args', pg_get_function_identity_arguments(p.oid), 'def', pg_get_functiondef(p.oid)) order by p.proname), '[]'::jsonb)
                  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f'),
    'views', (select coalesce(jsonb_agg(jsonb_build_object('name', viewname, 'def', definition) order by viewname), '[]'::jsonb) from pg_views where schemaname = 'public'));
end $$;
revoke all on function public.export_repo_bootstrap(text) from public;
grant execute on function public.export_repo_bootstrap(text) to anon;;

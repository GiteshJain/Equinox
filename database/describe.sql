-- Everything the table guide (docs/data.md) is made from, as one JSON document: every table, view and function in the
-- public schema with its description, columns, access rules and triggers, and the internal functions in the private
-- schema (#13), which the data API doesn't expose. Used by database/describe.py (decision #10).
select json_build_object(
  'relations', (
    select coalesce(json_agg(r order by r.name collate "C"), '[]') from (
      select c.relname as name, case c.relkind when 'v' then 'view' when 'm' then 'view' else 'table' end as kind,
             obj_description(c.oid, 'pg_class') as description,
             (select json_agg(json_build_object('name', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
                       'description', col_description(c.oid, a.attnum)) order by a.attnum)
                from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as columns,
             (select json_agg(p.policyname || ': ' || lower(p.cmd) || ' for ' || array_to_string(p.roles, ', ') order by p.policyname collate "C")
                from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as policies,
             (select json_agg(distinct t.tgname::text) from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal) as triggers
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')) r),
  'functions', (
    select coalesce(json_agg(f order by f.schema collate "C" desc, f.name collate "C", f.args collate "C"), '[]') from (
      select n.nspname as schema, p.proname as name, pg_get_function_identity_arguments(p.oid) as args, pg_get_function_result(p.oid) as returns,
             obj_description(p.oid, 'pg_proc') as description, p.prosecdef as definer,
             (select json_agg(distinct r.rolname::text) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x
                join pg_roles r on r.oid = x.grantee where x.privilege_type = 'EXECUTE' and r.rolname in ('anon', 'authenticated')) as callable_by
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private')) f)
);

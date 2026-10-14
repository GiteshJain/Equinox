-- Who may use what in the public schema: for every function, which roles may call it, and for every table and view,
-- whether row-level security is on and what anon, authenticated and service_role may do. One line each, sorted.
-- Copied on 14 Oct 2026 from scripts/permissions.sql in GiteshJain/equinox-backups, which keeps its own copy for the
-- nightly backup (db/permissions.txt) and its restore check. Used here by database/rehearse.sh, whose backup and restore
-- after the changes makes sure the restored copy gives exactly the same answers. Keep the two the same.
with fn as (
  select 'function ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || '): ' ||
         coalesce((select string_agg(g, ',' order by g) from (
            select distinct case when x.grantee = 0 then 'PUBLIC' else r.rolname end as g
            from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x left join pg_roles r on r.oid = x.grantee
            where x.privilege_type = 'EXECUTE') s
          where g in ('PUBLIC', 'anon', 'authenticated', 'service_role')), 'nobody') as line
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
rel as (
  select case c.relkind when 'v' then 'view ' when 'm' then 'view ' else 'table ' end || c.relname || ': rls ' ||
         case when c.relrowsecurity then 'on' else 'off' end || coalesce('; ' || (
           select string_agg(g || ' ' || privs, '; ' order by g) from (
             select r.rolname as g, string_agg(distinct x.privilege_type, ',' order by x.privilege_type) as privs
             from aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) x join pg_roles r on r.oid = x.grantee
             where r.rolname in ('anon', 'authenticated', 'service_role') group by r.rolname) s), '') as line
  from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm'))
select line from (select line from fn union all select line from rel) a order by line collate "C";

-- Row count of every table that is backed up, one line each ("schema.table count").
-- Copied on 9 Oct 2026 from scripts/counts.sql in GiteshJain/equinox-backups, which keeps its own copy for the nightly
-- job's restore check. Used here by database/rehearse.sh. Keep the two the same.
-- The restore check compares these counts before and after. Run with -v skip=<comma-separated tables to leave out>.
select format('select %L || '' '' || count(*) from %I.%I', n.nspname || '.' || c.relname, n.nspname, c.relname)
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'p')
  and (n.nspname = 'public' or (n.nspname = 'storage' and c.relname in ('buckets', 'objects')))
  and not (n.nspname || '.' || c.relname = any (string_to_array(:'skip', ',')))
order by 1
\gexec

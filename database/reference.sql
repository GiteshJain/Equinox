-- Every function in public and private, as database/reference.py compares them with database/current/functions.sql (run
-- by database/rehearse.sh on the copy after the changes): its schema, name and arguments as the file's entry lines give
-- them, and its definition. The same functions as the table guide counts (database/describe.sql). One JSON document.
select coalesce(jsonb_agg(jsonb_build_object(
         'schema', n.nspname, 'name', p.proname, 'args', pg_get_function_identity_arguments(p.oid),
         'definition', case when p.prokind in ('f', 'p') then pg_get_functiondef(p.oid) end)
       order by n.nspname <> 'public', p.proname collate "C", pg_get_function_identity_arguments(p.oid) collate "C"), '[]'::jsonb)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('public', 'private');

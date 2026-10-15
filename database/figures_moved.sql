-- The captured figures before and after a pull request's database changes, for database/figures_moved.py (run by
-- database/rehearse.sh after the database tests): what database/tests/before/figures_before.sql saved, and
-- private.fig_export() worked out again at the same moment on the copy as the changes left it. One JSON document.
select jsonb_build_object(
  'as_of', (select value from rehearsal_before.figures where name = 'as_of'),
  'before', (select value from rehearsal_before.figures where name = 'figures'),
  'after', private.fig_export((select (value #>> '{}')::bigint from rehearsal_before.figures where name = 'world_id'),
                              (select (value #>> '{}')::timestamptz from rehearsal_before.figures where name = 'as_of')));

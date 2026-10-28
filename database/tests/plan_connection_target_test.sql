-- The planning target for connections (manual §4; migration 20261027230000; spec
-- docs/specs/2026-10-27-planning-connection-target.md §1). Run by database/rehearse.sh on the copy of last night's backup,
-- after the new migrations, inside a transaction that is rolled back. Read only.
--   1. plan_connection_target_h is a world-level setting in every world, in hours, described, with since and reason;
--      4 in the default world, and no airline has its own.
--   2. connection_max_wait_h stays 8 in the default world (the target changes no other reader).
--   3. rules_input() carries it to the planning library, as 4, in the world's settings and every airline's.

do $test$
declare
  dw bigint := (select id from public.worlds where is_default);
  d jsonb;
  bad text;
begin
  -- ---------------------------------------------------------------- 1. the setting
  assert not exists (select 1 from public.worlds x
                      where not exists (select 1 from public.settings s where s.world_id = x.id and s.airline_id is null
                                           and s.key = 'plan_connection_target_h' and s.description is not null and s.unit = 'hours'
                                           and s.since is not null and s.reason is not null)),
    'a world has no described plan_connection_target_h setting in hours (with since and reason)';
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'plan_connection_target_h') = '4'::jsonb,
    'plan_connection_target_h isn''t 4 in the default world';
  assert not exists (select 1 from public.settings s where s.key = 'plan_connection_target_h' and s.airline_id is not null),
    'an airline has its own plan_connection_target_h (the spec says world-wide, no overrides)';

  -- ---------------------------------------------------------------- 2. the longest wait is unchanged
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'connection_max_wait_h') = '8'::jsonb,
    'connection_max_wait_h isn''t 8 in the default world';

  -- ---------------------------------------------------------------- 3. through rules_input()
  d := public.rules_input(dw, 'all');
  assert d #> '{settings,plan_connection_target_h}' = '4'::jsonb, 'rules_input() doesn''t carry plan_connection_target_h as 4';
  select string_agg(a ->> 'id', ', ') into bad from jsonb_array_elements(d -> 'airlines') a
   where a ? 'settings' and (a #> '{settings,plan_connection_target_h}') is distinct from '4'::jsonb;
  assert bad is null, 'these airlines'' settings in rules_input() don''t have plan_connection_target_h 4: ' || bad;
  raise notice 'plan_connection_target_h: 4 hours in every world, described, no airline''s own; connection_max_wait_h still 8; rules_input() carries it';
end
$test$;

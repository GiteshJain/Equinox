-- Long haul in 7-day lines: the settings (migration 20261028120000; spec docs/specs/2026-10-27-long-haul-lines.md,
-- "Settings"). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a
-- transaction that is rolled back. Read only.
--   1. line_min_km, maintenance_max_gap_h and line_aircraft are world-level settings in every world, described, with
--      a unit, since and reason; 7,750, 40 and 7 in the default world, and no airline has its own.
--   2. rules_input() carries them to the planning library, in the world's settings and every airline's.
--   3. maintenance_min_pct stays 100 (the spacing is beside it, not in place of it).

do $test$
declare
  dw bigint := (select id from public.worlds where is_default);
  d jsonb;
  k text;
  want jsonb;
  bad text;
begin
  -- ---------------------------------------------------------------- 1. the settings
  for k, want in select * from (values ('line_min_km', '7750'::jsonb), ('maintenance_max_gap_h', '40'::jsonb), ('line_aircraft', '7'::jsonb)) v(key, value) loop
    assert not exists (select 1 from public.worlds x
                        where not exists (select 1 from public.settings s where s.world_id = x.id and s.airline_id is null
                                             and s.key = k and s.description is not null and s.unit is not null
                                             and s.since is not null and s.reason is not null)),
      format('a world has no described %s setting (with a unit, since and reason)', k);
    assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = k) = want,
      format('%s isn''t %s in the default world', k, want);
    assert not exists (select 1 from public.settings s where s.key = k and s.airline_id is not null),
      format('an airline has its own %s (the spec gives none)', k);
  end loop;

  -- ---------------------------------------------------------------- 2. through rules_input() (the document in a variable first)
  d := public.rules_input(dw, 'all');
  for k, want in select * from (values ('line_min_km', '7750'::jsonb), ('maintenance_max_gap_h', '40'::jsonb), ('line_aircraft', '7'::jsonb)) v(key, value) loop
    assert d -> 'settings' -> k = want, format('rules_input() doesn''t carry %s as %s', k, want);
    select string_agg(a ->> 'id', ', ') into bad from jsonb_array_elements(d -> 'airlines') a
     where a ? 'settings' and (a -> 'settings' -> k) is distinct from want;
    assert bad is null, format('these airlines'' settings in rules_input() don''t have %s %s: %s', k, want, bad);
  end loop;

  -- ---------------------------------------------------------------- 3. the week's total is still judged
  assert (select s.value from public.settings s where s.world_id = dw and s.airline_id is null and s.key = 'maintenance_min_pct') = '100'::jsonb,
    'maintenance_min_pct isn''t 100 in the default world';
  raise notice 'long haul in lines: line_min_km 7,750, maintenance_max_gap_h 40 and line_aircraft 7 in every world, described, no airline''s own; rules_input() carries them; maintenance_min_pct still 100';
end
$test$;

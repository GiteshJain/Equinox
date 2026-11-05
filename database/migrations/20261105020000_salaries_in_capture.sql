-- Salaries inside the evening capture (5 Nov 2026; brief docs/briefs/2026-11-04-salaries-in-capture.md, option A,
-- decided by Gitesh 4 Nov; manual §7).
--
-- Why: the separate "Salaries: this airline" script set every position to exactly 10% above its country average, one
-- airline at a time, only when Gitesh pressed it, so a position could sit below the average unseen between presses. From
-- capture 1.12 the evening capture checks every position of each of our airlines on the game's Employee overview page:
-- at or above the country average it is left alone; below it, it is set to this setting's percentage above the average.
-- It never lowers a salary. Nothing about salaries is stored in the database.
--
-- Adds one setting, replaces one function with the same arguments and rewords one row's description; changes, drops and
-- renames nothing else, so it can be applied from the chat:
--   - settings.salary_above_average_pct: 5 (per cent), world level in every world (airline null), described. Shown under
--     Reference -> constants.
--   - public.capture_airlines(p_key): as before (about 25 lines), plus salary_above_average_pct: the setting's value in
--     the key's world, or null when the world has none (the capture then leaves salaries alone and says so). Its
--     grants are kept by create or replace (anon may execute, as the capture calls it signed out).
--   - world_rules.capture_salary_step (the permission row, kept, manual §9): its description said "since 10 Oct a separate
--     script, run by hand on one airline"; it now says the evening capture sets salaries again. Value unchanged (true).

select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building salaries in capture', true);

-- ============================================================ 1. the setting
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'salary_above_average_pct', '5'::jsonb, 'percent',
       'How far above the country average the evening capture sets a salary that is below it (manual §7; capture/capture_all.user.js 1.12): '
       'for each of our airlines, after its fleet pages, the capture reads the game''s Employee overview page; a position at or above its '
       'country average is left alone, one below it is set to the average plus this many per cent (rounded to a whole AS$), using the '
       'page''s own adjust control. Salaries are never lowered. Without this setting the capture leaves salaries alone. Shown under '
       'Reference -> constants.',
       date '2026-11-05',
       'Gitesh, 4 Nov: option A of docs/briefs/2026-11-04-salaries-in-capture.md (below the average to 5% above it, in the capture; the "Salaries: this airline" script retired)'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- the permission row stays (manual §9); only its description follows the build
update public.world_rules r
   set description = 'Setting salaries by script is allowed in Gander: since 5 Nov the evening capture (capture/capture_all.user.js 1.12) raises each salary below its country average to settings.salary_above_average_pct above it, never lowering one (manual §7); from 10 Oct to 5 Nov a separate script, run by hand on one airline'
 where r.key = 'capture_salary_step' and r.kind = 'permission'
   and r.description = 'Setting salaries by script is allowed in Gander (since 10 Oct a separate script, run by hand on one airline)';

-- ============================================================ 2. capture_airlines(): the setting too
create or replace function public.capture_airlines(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  return jsonb_build_object(
    'ok', true,
    'world', (select w.name from public.worlds w where w.id = v_world),
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object('game_id', a.game_id, 'name', a.planner_name,
                                                               'game_name', a.game_name, 'code', a.iata_code)
                                           order by a.position nulls last, a.id), '[]'::jsonb)
                   from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = v_world and a.active and g.kind = 'ours'),
    -- salaries (since 5 Nov, manual §7): how far above the country average a salary below it is set; null: left alone
    'salary_above_average_pct', (select s.value from public.settings s
                                  where s.world_id = v_world and s.airline_id is null and s.key = 'salary_above_average_pct'))
    -- the world scan (spec docs/specs/2026-10-21-scan-in-capture.md): whether one is due, the open one and the airports
    || private.capture_scan_plan(v_world, now())
    -- the market pages (spec docs/specs/2026-10-30-market-pages.md): whether they're due, the open run and the pages
    || private.capture_market_plan(v_world, now());
end
$function$;

-- its description keeps every word as it stands (later tests read it); the salary part is added at the end, once
do $describe$
declare d text := obj_description('public.capture_airlines(text)'::regprocedure, 'pg_proc');
begin
  if position('salary_above_average_pct' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_airlines(text) is %L', coalesce(d, '')
      || ' Since 5 Nov (manual §7, brief docs/briefs/2026-11-04-salaries-in-capture.md) also salary_above_average_pct: the world''s setting (5), or null when it has none, so the capture sets each salary below its country average to that many per cent above it (and leaves salaries alone without it).');
  end if;
end
$describe$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

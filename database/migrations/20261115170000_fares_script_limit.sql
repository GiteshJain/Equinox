-- The fares userscript's own limit (15 Nov 2026; to-do 247 with to-do 218 step 3, option B; Gitesh 15 Nov in the Main
-- chat, choice 5a option A; spec docs/specs/2026-11-15-self-updating-scripts.md §8).
--
-- Why: the fares userscript (capture/fares_apply.user.js) makes whatever changes the database lists. Its own limit is a
-- last check that doesn't trust the fare ladder: it refuses any change whose level is under 55% or over 135% of the
-- default price, stops before making anything and says which change and why. That is just outside what the ladder can
-- produce today (manual §5: the 60% floor and the last under-launch level, 60%; the highest cap, Pan Am and China
-- Eastern, 128%). The two numbers are settings (manual §1: the one source for rule numbers); a cap lifted to or past
-- them turns database/tests/fares_script_limit_test.sql red, so the limit is moved in the same rule change.
--
-- Adds two settings in every world and replaces one function with the same arguments (create or replace keeps its
-- grants). Drops, renames and deletes nothing, so it can be applied from the chat:
--   1. settings.fares_script_min_pct (55) and fares_script_max_pct (135), % of the default price, world rows.
--   2. capture_fare_actions_by_airline(): its list (no game ID) also answers limits {min_pct, max_pct}, read from the
--      key's world's two rows; either row missing or not a number answers limits null, and the userscript (1.5 and later)
--      then refuses the whole plan. Each airline's answer is unchanged.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261115170000_fares_script_limit', true);

-- ============================================================ 1. the settings
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, '% of default price', x.description, date '2026-11-15', x.reason
  from public.worlds w
 cross join (values
   ('fares_script_min_pct', '55'::jsonb,
    'The fares userscript''s own lower limit (manual §5; spec docs/specs/2026-11-15-self-updating-scripts.md §8): it refuses any '
    'change whose level is under this % of the default price, before making anything, and says which change and why. Kept just '
    'under the lowest level the fare ladder can produce (world_rules.fare_floor_pct and the last of fare_under_launch_levels, 60); '
    'database/tests/fares_script_limit_test.sql fails when the ladder can reach it, so a floor change moves this row too. '
    'capture_fare_actions_by_airline() gives it to the userscript.',
    'Gitesh, 15 Nov: to-do 218 step 3, option B (a limit of the script''s own), and choice 5a, option A (two fixed rows)'),
   ('fares_script_max_pct', '135'::jsonb,
    'The fares userscript''s own upper limit (manual §5; spec docs/specs/2026-11-15-self-updating-scripts.md §8): it refuses any '
    'change whose level is over this % of the default price, before making anything, and says which change and why. Kept just '
    'over the highest level the fare ladder can produce (fare_launch_pct plus fare_ladder_cap_pts, 128% for Pan Am and China '
    'Eastern on 15 Nov); database/tests/fares_script_limit_test.sql fails when a cap reaches it, so lifting a cap moves this '
    'row too. capture_fare_actions_by_airline() gives it to the userscript.',
    'Gitesh, 15 Nov: to-do 218 step 3, option B (a limit of the script''s own), and choice 5a, option A (two fixed rows)')
 ) as x(key, value, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2. the list answers the limits
create or replace function public.capture_fare_actions_by_airline(p_key text, p_game_id integer default null)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
set statement_timeout to '30s'
set plan_cache_mode to 'force_custom_plan'
as $function$
declare v_world bigint; v_doc jsonb; v_min jsonb; v_max jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  -- the unattended capture's key reads only (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): fares are
  -- never changed on a schedule (manual §5), so it is refused as a wrong key is
  if private.capture_key_unattended(p_key) then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_game_id is null then
    -- the fares script's own limit (since 15 Nov, spec docs/specs/2026-11-15-self-updating-scripts.md §8): the world's two
    -- rows, or null when either is missing or not a number (the script then refuses the plan)
    select s.value into v_min from public.settings s where s.world_id = v_world and s.airline_id is null and s.key = 'fares_script_min_pct';
    select s.value into v_max from public.settings s where s.world_id = v_world and s.airline_id is null and s.key = 'fares_script_max_pct';
    -- the list: our active airlines of the world in display order, with no fare ladder worked out (it answers at once)
    return jsonb_build_object('ok', true, 'world', (select w.name from public.worlds w where w.id = v_world),
             'as_of', private.fig_ts(now()),
             'limits', case when jsonb_typeof(v_min) = 'number' and jsonb_typeof(v_max) = 'number'
                            then jsonb_build_object('min_pct', v_min, 'max_pct', v_max) end,
             'airlines', coalesce((select jsonb_agg(jsonb_build_object('game_id', a.game_id, 'name', coalesce(a.public_name, a.planner_name, a.game_name),
                                                                       'game_name', a.game_name, 'code', a.iata_code)
                                                    order by a.position nulls last, a.id)
                                     from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                                    where a.world_id = v_world and a.active and g.kind = 'ours'), '[]'::jsonb));
  end if;
  v_doc := private.capture_fare_actions_doc(v_world, now(), p_game_id);
  if jsonb_array_length(v_doc -> 'airlines') = 0 then return jsonb_build_object('ok', false, 'error', 'no such airline of ours: ' || p_game_id); end if;
  return jsonb_build_object('ok', true, 'world', (select w.name from public.worlds w where w.id = v_world)) || v_doc;
end
$function$;

do $describe$
declare d text := obj_description('public.capture_fare_actions_by_airline(text, integer)'::regprocedure, 'pg_proc');
begin
  if position('fares_script_min_pct' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_fare_actions_by_airline(text, integer) is %L', coalesce(d, '')
      || ' Since 15 Nov (spec docs/specs/2026-11-15-self-updating-scripts.md §8) the list (no p_game_id) also answers limits {min_pct, max_pct}: the key''s world''s settings fares_script_min_pct and fares_script_max_pct, the fares userscript''s own limit, or null when either is missing or not a number (the userscript, 1.5 and later, then refuses the plan).');
  end if;
end
$describe$;

-- The fares userscript's list (21 Oct 2026; spec docs/specs/2026-10-21-fares-userscript.md §1; manual §5).
--
-- Why (Gitesh, 21 Oct): the fare ladder's changes go route by route, in both directions, which is a few hundred game
-- changes on a Saturday. A userscript in the game (capture/fares_apply.user.js) makes them for him, one at a time, while
-- he watches. It reads what to change from here with the capture key, as the capture reads its airlines.
--
-- Adds two functions and nothing else; changes, drops and renames nothing, so it can be applied from the chat:
--   - public.capture_fare_actions(p_key): with a valid capture key, for each active airline of ours in the key's world
--     (as capture_airlines() lists them, in their order), that airline's fare_ladder() actions for routes that are on the
--     fare plan this week and not yet seen in the game (planned and not applied, in every cabin the action names). Each
--     action gives the airline's game ID and name, n, the route, from and to (IATA), level, sign, pct, the classes, the
--     route's plan row id(s) (one per class, in the action's order) and the action's words. With no valid key it refuses
--     as capture_airlines() does ({"ok": false, "error": "bad key"}). Runs as owner with an empty search path, granted
--     to anon and authenticated like capture_airlines(). It works out six fare ladders in one call, signed out, so it
--     carries its own statement limit of 30 seconds, as export_for_report() does (the role's is 3 seconds).
--   - private.capture_fare_actions_doc(p_world_id, p_as_of): its builder, internal, with no check of its own, so the
--     database test can ask it at a fixed moment. It reads private.fig_fare_ladder() for each airline, unchanged.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261021210000_capture_fare_actions', true);

create or replace function private.capture_fare_actions_doc(p_world_id bigint, p_as_of timestamp with time zone)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  v_al record; d jsonb; v_week text; v_keep jsonb;
  v_airlines jsonb := '[]'::jsonb; v_actions jsonb := '[]'::jsonb;
begin
  -- our active airlines of the world, as capture_airlines() lists them, in display order
  for v_al in select a.id, a.game_id, coalesce(a.public_name, a.planner_name, a.game_name) as name, a.game_name, a.iata_code
                from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
               where a.world_id = p_world_id and a.active and g.kind = 'ours'
               order by a.position nulls last, a.id loop
    d := private.fig_fare_ladder(v_al.id, p_as_of);
    v_week := coalesce(v_week, d ->> 'week_of');
    -- an action is kept when every class it names is a route row (matched by its route, "HUB–DEST", and cabin) that is
    -- on the fare plan this week (planned) and not yet seen in the captures (applied false)
    with acts as (select t.x, t.i from jsonb_array_elements(d -> 'actions') with ordinality as t(x, i)),
         cls as (select acts.i, c.k, m.rt
                   from acts
                   cross join lateral jsonb_array_elements_text(acts.x -> 'classes') with ordinality as c(cabin, k)
                   left join lateral (select e as rt from jsonb_array_elements(d -> 'routes') e
                                       where (e ->> 'hub') || '–' || (e ->> 'dest') = acts.x ->> 'route' and e ->> 'cabin' = c.cabin
                                       limit 1) m on true),
         ok as (select cls.i, jsonb_agg((cls.rt ->> 'plan_id')::bigint order by cls.k) as plan_ids
                  from cls
                 group by cls.i
                having bool_and(coalesce((cls.rt ->> 'planned')::boolean, false) and not coalesce((cls.rt ->> 'applied')::boolean, true)))
    select coalesce(jsonb_agg(jsonb_build_object(
             'game_id', v_al.game_id, 'airline', v_al.name, 'n', acts.x -> 'n', 'route', acts.x -> 'route',
             'from', acts.x -> 'from', 'to', acts.x -> 'to', 'level', acts.x -> 'level', 'sign', acts.x -> 'sign',
             'pct', acts.x -> 'pct', 'classes', acts.x -> 'classes', 'plan_ids', ok.plan_ids, 'text', acts.x -> 'text')
             order by acts.i), '[]'::jsonb)
      into v_keep
      from acts join ok on ok.i = acts.i;
    v_actions := v_actions || v_keep;
    v_airlines := v_airlines || jsonb_build_object('game_id', v_al.game_id, 'name', v_al.name, 'game_name', v_al.game_name,
                                                   'code', v_al.iata_code, 'count', jsonb_array_length(v_keep));
  end loop;
  return jsonb_build_object('as_of', private.fig_ts(p_as_of), 'week_of', v_week, 'airlines', v_airlines, 'actions', v_actions);
end
$function$;

create or replace function public.capture_fare_actions(p_key text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
 set statement_timeout to '30s'
as $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  return jsonb_build_object('ok', true, 'world', (select w.name from public.worlds w where w.id = v_world))
         || private.capture_fare_actions_doc(v_world, now());
end
$function$;

revoke all on function private.capture_fare_actions_doc(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.capture_fare_actions(text) from public, anon, authenticated;
grant execute on function public.capture_fare_actions(text) to anon, authenticated;

comment on function private.capture_fare_actions_doc(bigint, timestamptz) is 'The fares userscript''s list (spec docs/specs/2026-10-21-fares-userscript.md): builds capture_fare_actions()''s document for one world at a moment, with no check of its own. See capture_fare_actions().';
comment on function public.capture_fare_actions(text) is 'For the fares userscript (capture/fares_apply.user.js; manual §5, since 21 Oct; spec docs/specs/2026-10-21-fares-userscript.md), with the capture key: the game''s Ticket price adjustments still to make this week. For each active airline of our groups in the key''s world, in display order (as capture_airlines()), its fare_ladder() actions whose route is on the fare plan this week and not yet seen in the captures: every class the action names is a route row with planned true and applied false. airlines: each airline''s game_id, name (the website''s, else the planner''s), game_name, code and count of actions; actions: each with game_id and airline (its name), n (the action''s number in fare_ladder()), route (HUB–DEST), from and to (IATA), level (% of the default price), sign (+ or -) and pct (the game''s percent, a whole number), classes (economy and/or business), plan_ids (the fare plan rows, one per class in the same order) and text (the action in words); week_of (this Saturday) and as_of. A wrong or missing key gets {"ok": false, "error": "bad key"} and nothing else. Runs as owner with an empty search path and its own statement limit of 30 seconds (it works out every airline''s fare ladder in one call, signed out).';

-- Apply fare plan asks one airline at a time (2 Nov 2026; to-do 194, brief docs/briefs/2026-11-02-fare-actions-by-airline.md,
-- option B).
--
-- Why: capture_fare_actions() works out every airline's fare ladder in one call under its own 30-second limit, and on
-- 2 Nov it took about 70 s (Pan Am 11.4 s, Kingfisher 9.4, Ryanair 9.8, Virgin 12.5, China Eastern 14.8, Malaysia
-- 12.1), so the fares userscript's "Apply fare plan" stopped with "canceling statement due to statement timeout".
-- Raising the limit (option A) can't work: calls through Supabase's API are cut off at 60 seconds whatever the function
-- sets. The userscript (1.3) now reads the list, then each airline's changes in a call of its own, each well under 30 s.
--
-- Adds two functions and replaces one with the same arguments; changes, drops and renames nothing else, so it can be
-- applied from the chat. capture_fare_actions() stays as it was (the one-call answer, for a small world or an older
-- userscript).
--   - public.capture_fare_actions_by_airline(p_key text, p_game_id integer default null): with the capture key; no
--     game ID: the list of our active airlines (no fare ladder worked out); a game ID: that airline's answer, as
--     capture_fare_actions() gives it for that airline. Signed out and signed in, its own 30 s limit.
--   - private.capture_fare_actions_doc(p_world_id, p_as_of, p_game_id): the builder for one airline (or all, null).
--   - private.capture_fare_actions_doc(p_world_id, p_as_of): now calls it with null; same answer as before.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261102230000_fare_actions_by_airline', true);

CREATE OR REPLACE FUNCTION private.capture_fare_actions_doc(p_world_id bigint, p_as_of timestamp with time zone, p_game_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_al record; d jsonb; v_week text; v_keep jsonb;
  v_airlines jsonb := '[]'::jsonb; v_actions jsonb := '[]'::jsonb;
begin
  -- our active airlines of the world, as capture_airlines() lists them, in display order (one, by its game ID, when
  -- p_game_id is given: since 2 Nov the userscript asks one airline at a time)
  for v_al in select a.id, a.game_id, coalesce(a.public_name, a.planner_name, a.game_name) as name, a.game_name, a.iata_code
                from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
               where a.world_id = p_world_id and a.active and g.kind = 'ours' and (p_game_id is null or a.game_id = p_game_id)
               order by a.position nulls last, a.id loop
    d := private.fig_fare_ladder(v_al.id, p_as_of);
    v_week := coalesce(v_week, d ->> 'week_of');
    -- an action is kept when it sets a route back to its level (fix: no fare plan row; the index matching again is the
    -- proof), or when every class it names is a route row (matched by its route, "HUB–DEST", its direction, From and To,
    -- since 26 Oct, and cabin) that is on the fare plan this week (planned) and not yet seen in the captures (applied
    -- false, by its own direction's fares when the row has one)
    with acts as (select t.x, t.i from jsonb_array_elements(d -> 'actions') with ordinality as t(x, i)),
         cls as (select acts.i, c.k, m.rt
                   from acts
                   cross join lateral jsonb_array_elements_text(acts.x -> 'classes') with ordinality as c(cabin, k)
                   left join lateral (select e as rt from jsonb_array_elements(d -> 'routes') e
                                       where (e ->> 'hub') || '–' || (e ->> 'dest') = acts.x ->> 'route' and e ->> 'cabin' = c.cabin
                                         and e ->> 'from' = acts.x ->> 'from' and e ->> 'to' = acts.x ->> 'to'
                                       limit 1) m on true),
         ok as (select cls.i, jsonb_agg((cls.rt ->> 'plan_id')::bigint order by cls.k) as plan_ids
                  from cls
                 group by cls.i
                having bool_and(coalesce((cls.rt ->> 'planned')::boolean, false) and not coalesce((cls.rt ->> 'applied')::boolean, true))),
         keep as (select acts.i, acts.x, case when coalesce((acts.x ->> 'fix')::boolean, false) then '[]'::jsonb else ok.plan_ids end as plan_ids
                    from acts left join ok on ok.i = acts.i
                   where coalesce((acts.x ->> 'fix')::boolean, false) or ok.i is not null)
    select coalesce(jsonb_agg(jsonb_build_object(
             'game_id', v_al.game_id, 'airline', v_al.name, 'n', keep.x -> 'n', 'route', keep.x -> 'route',
             'from', keep.x -> 'from', 'to', keep.x -> 'to', 'level', keep.x -> 'level', 'sign', keep.x -> 'sign',
             'pct', keep.x -> 'pct', 'classes', keep.x -> 'classes', 'plan_ids', keep.plan_ids,
             'fix', coalesce((keep.x ->> 'fix')::boolean, false), 'reason', keep.x -> 'reason', 'text', keep.x -> 'text')
             order by keep.i), '[]'::jsonb)
      into v_keep
      from keep;
    v_actions := v_actions || v_keep;
    v_airlines := v_airlines || jsonb_build_object('game_id', v_al.game_id, 'name', v_al.name, 'game_name', v_al.game_name,
                                                   'code', v_al.iata_code, 'count', jsonb_array_length(v_keep),
                                                   'fixes', (select count(*) from jsonb_array_elements(v_keep) x where (x ->> 'fix')::boolean));
  end loop;
  return jsonb_build_object('as_of', private.fig_ts(p_as_of), 'week_of', v_week, 'airlines', v_airlines, 'actions', v_actions);
end
$function$

;

CREATE OR REPLACE FUNCTION private.capture_fare_actions_doc(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select private.capture_fare_actions_doc(p_world_id, p_as_of, null::integer)
$function$

;

CREATE OR REPLACE FUNCTION public.capture_fare_actions_by_airline(p_key text, p_game_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare v_world bigint; v_doc jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_game_id is null then
    -- the list: our active airlines of the world in display order, with no fare ladder worked out (it answers at once)
    return jsonb_build_object('ok', true, 'world', (select w.name from public.worlds w where w.id = v_world),
             'as_of', private.fig_ts(now()),
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
$function$

;

revoke all on function private.capture_fare_actions_doc(bigint, timestamptz, integer) from public, anon, authenticated, service_role;
revoke all on function public.capture_fare_actions_by_airline(text, integer) from public;
grant execute on function public.capture_fare_actions_by_airline(text, integer) to anon, authenticated;

comment on function private.capture_fare_actions_doc(bigint, timestamptz, integer) is 'capture_fare_actions()''s builder (since 2 Nov, for one airline): for our active airlines of p_world_id in display order, or only the one whose game ID is p_game_id (none when it isn''t one of ours and active), each one''s fare_ladder() actions still to make this week: the set-back changes (fix) and those whose every class is on the fare plan this week and not yet seen in the captures, with their plan rows. Answers as_of, week_of, airlines (game_id, name, game_name, code, count, fixes) and actions. The two-argument form is this with p_game_id null. Internal, as the caller.';
comment on function public.capture_fare_actions_by_airline(text, integer) is 'For the fares userscript (capture/fares_apply.user.js 1.3 and later; manual §5; since 2 Nov, brief docs/briefs/2026-11-02-fare-actions-by-airline.md), with the capture key, one airline at a time so no call runs past its limit: with no p_game_id, the list of our active airlines of the key''s world in display order (game_id, name, game_name, code; no fare ladder worked out, so it answers at once); with an airline''s game ID, that airline''s Ticket price adjustments still to make, exactly as capture_fare_actions() gives them for it (ok, world, as_of, week_of, airlines: that one with its count and fixes, actions), from private.capture_fare_actions_doc(). A wrong or missing key gets {"ok": false, "error": "bad key"}, a game ID that isn''t an active airline of ours in the key''s world {"ok": false, "error": "no such airline of ours: <id>"}. Runs as owner with an empty search path and its own statement limit of 30 seconds (one airline''s fare ladder, about 10 to 15 s on 2 Nov; calls through the API are cut off at 60 s whatever the limit).';

do $describe$
declare d text;
begin
  d := obj_description('private.capture_fare_actions_doc(bigint, timestamptz)'::regprocedure, 'pg_proc');
  if position('(since 2 Nov' in coalesce(d, '')) = 0 then
    execute format('comment on function private.capture_fare_actions_doc(bigint, timestamptz) is %L',
                   coalesce(d, '') || ' Since 2 Nov the three-argument form with p_game_id null (one airline at a time for capture_fare_actions_by_airline()).');
  end if;
  d := obj_description('public.capture_fare_actions(text)'::regprocedure, 'pg_proc');
  if position('(since 2 Nov' in coalesce(d, '')) = 0 then
    execute format('comment on function public.capture_fare_actions(text) is %L',
                   coalesce(d, '') || ' The fares userscript asks capture_fare_actions_by_airline() one airline at a time instead (since 2 Nov): every airline in one call took about 70 s, past the 30 s limit and the API''s 60 s.');
  end if;
end
$describe$;

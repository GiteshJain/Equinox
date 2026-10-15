-- The airline briefing (decision #24, option B; spec docs/specs/2026-10-15-airline-briefing.md): one new export kind,
-- briefing, for scripts/briefing/brief.py. It gives, for one airline, what no other export kind gave: the aircraft on
-- order or arrived and not yet filed (deliveries) with their plan cards and the cards' legs, the open to-dos (the
-- airline's and the group's), its fare plan (fare_plan_status()) and its loads by route and flight over 7 days
-- (route_loads()). Read only. Each figure keeps its one home (#19): the fare plan and the loads come from their own
-- builders, private.fig_fare_plan() and private.fig_route_loads(), unchanged.
--
-- Adds one function and replaces one with the same arguments; takes nothing away, so it can be applied from the chat:
--   private.briefing_doc(bigint, timestamptz): new, the kind's document for one airline (stable, internal only);
--   public.export_for_report(text, text, text): the new kind briefing, p_arg {"airline": id, code or name, "as_of",
--     "world"}; every other kind exactly as before.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261015180000_briefing', true);

-- ---------------------------------------------------------------- 1. the document for one airline
create or replace function private.briefing_doc(p_airline_id bigint, p_as_of timestamptz)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  with al as (select a.id, a.world_id, a.iata_code, a.planner_name, a.public_name, a.game_name, a.game_id
                from public.airlines a where a.id = p_airline_id),
  -- loads by route and flight number over the 7 days to the moment, as route_loads() gives them, this airline's only
  rl as (select private.fig_route_loads(al.world_id, p_as_of) as d from al)
  select jsonb_build_object(
    'airline', (select jsonb_build_object('id', al.id, 'world_id', al.world_id, 'code', al.iata_code, 'planner_name', al.planner_name,
                                          'public_name', al.public_name, 'game_name', al.game_name, 'game_id', al.game_id) from al),
    'as_of', private.fig_ts(p_as_of),
    -- the aircraft not yet filed: on order, or arrived and not yet flying (status delivered), each with its plan cards
    'deliveries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'aircraft_id', a.id, 'registration', a.registration, 'status', a.status,
               'type_id', a.aircraft_type_id, 'type', t.name, 'ordered_on', a.ordered_on,
               'delivery_at', private.fig_ts(a.delivery_at), 'arrived', a.delivery_at is not null and a.delivery_at <= p_as_of,
               'base_code', a.base_code, 'order_base_code', a.order_base_code,
               'cabin', c.code, 'order_cabin', oc.code, 'order_note', a.order_note,
               'plan_cards', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', pc.id, 'airline_id', pc.airline_id, 'title', pc.title, 'base_code', pc.base_code, 'note', pc.note,
                          'updated_at', private.fig_ts(pc.updated_at),
                          'legs', coalesce((
                            select jsonb_agg(jsonb_build_object(
                                     'position', l.position, 'flight_no', l.flight_no, 'origin_code', l.origin_code, 'dest_code', l.dest_code,
                                     'days_utc', to_jsonb(l.days_utc), 'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min,
                                     'service_code', l.service_code)
                                   order by l.position, l.id)
                              from public.plan_card_legs l where l.plan_card_id = pc.id), '[]'::jsonb))
                        order by pc.id)
                   from public.plan_cards pc where pc.aircraft_id = a.id), '[]'::jsonb))
             order by a.delivery_at nulls last, a.id)
        from public.aircraft a
        left join public.aircraft_types t on t.id = a.aircraft_type_id
        left join public.cabin_configs c on c.id = a.cabin_config_id
        left join public.cabin_configs oc on oc.id = a.order_config_id
       where a.airline_id = p_airline_id and a.status in ('on_order', 'delivered')), '[]'::jsonb),
    -- the open to-dos: the airline's own, and the group's (no airline)
    'todos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'legacy_key', t.legacy_key, 'airline_id', t.airline_id, 'group', t.airline_id is null,
               'title', t.title, 'due_on', t.due_on, 'note', t.note, 'created_at', private.fig_ts(t.created_at),
               'steps', (select coalesce(jsonb_agg(i.body order by i.position, i.id), '[]'::jsonb)
                           from public.todo_items i where i.todo_id = t.id))
             order by t.due_on nulls last, t.created_at, t.id)
        from public.todos t, al
       where t.world_id = al.world_id and t.done is not true and (t.airline_id = p_airline_id or t.airline_id is null)), '[]'::jsonb),
    -- the fare plan and whether the captures show each change (fare_plan_status()'s document)
    'fare_plan', private.fig_fare_plan(p_airline_id, p_as_of),
    'route_loads', (select jsonb_build_object(
        'from', rl.d -> 'from', 'to', rl.d -> 'to',
        'routes', coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(rl.d -> 'routes') with ordinality x(v, o)
                             where (x.v ->> 'airline_id')::bigint = p_airline_id), '[]'::jsonb),
        'flights', coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(rl.d -> 'flights') with ordinality x(v, o)
                              where (x.v ->> 'airline_id')::bigint = p_airline_id), '[]'::jsonb))
      from rl))
  from al
$function$;

-- ---------------------------------------------------------------- 2. export_for_report(): kind briefing
-- As 20261014200000_clean_up.sql left it, with the one new kind.
create or replace function public.export_for_report(p_secret text, p_kind text, p_arg text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_arg jsonb; v_world bigint; v_airline bigint;
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'snapshots' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', s.taken_at, 'week', s.week, 'status', s.status) order by s.id), '[]'::jsonb)
              from public.game_scans s);
  elsif p_kind = 'airlines' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', a.enterprise_id, 'name', a.name, 'flights', sc.flights, 'n_weekly', a.n_weekly)
                                      order by a.position, a.enterprise_id), '[]'::jsonb)
              from public.game_scan_airlines a
              left join public.game_scan_schedules sc on sc.scan_id = a.scan_id and sc.airline_id = a.airline_id
             where a.scan_id = p_arg::bigint);
  elsif p_kind = 'airports' then
    return (select coalesce(jsonb_agg(jsonb_build_object('code', a.airport_code, 'info', a.info, 'stations', a.stations, 'news', a.news)
                                      order by a.position, a.airport_code), '[]'::jsonb)
              from public.game_scan_airports a where a.scan_id = p_arg::bigint);
  elsif p_kind = 'planner' then
    -- the old planner's two documents went with it (the clean-up, build pull request 14)
    raise exception 'kind planner is gone since the clean-up (build pull request 14): use rules or figures' using errcode = '22023';
  elsif p_kind = 'rules' then
    -- the planning library's input, exactly as rules_input() gives it (design §7); p_arg: the world, or empty for the default
    return private.rules_input_doc(nullif(p_arg, '')::bigint);
  elsif p_kind = 'figures' then
    -- the captured figures (design §8) for every airline; p_arg: {"as_of": ..., "world": ...}, both optional
    v_arg := coalesce(nullif(btrim(coalesce(p_arg, '')), '')::jsonb, '{}'::jsonb);
    if jsonb_typeof(v_arg) <> 'object' then raise exception 'figures: p_arg is a JSON object, {"as_of": ..., "world": ...}' using errcode = '22023'; end if;
    return private.fig_export(private.fig_world((v_arg ->> 'world')::bigint), coalesce((v_arg ->> 'as_of')::timestamptz, now()));
  elsif p_kind = 'briefing' then
    -- one airline's deliveries, plan cards, open to-dos, fare plan and loads by route (#24); p_arg: {"airline": its id,
    -- code or name (one of our active airlines), "as_of": ..., "world": ...}, the airline required
    v_arg := coalesce(nullif(btrim(coalesce(p_arg, '')), '')::jsonb, '{}'::jsonb);
    if jsonb_typeof(v_arg) <> 'object' or nullif(btrim(coalesce(v_arg ->> 'airline', '')), '') is null then
      raise exception 'briefing: p_arg is a JSON object naming the airline, {"airline": ..., "as_of": ..., "world": ...}' using errcode = '22023';
    end if;
    v_world := private.fig_world((v_arg ->> 'world')::bigint);
    select al.airline_id into v_airline
      from private.fig_airlines(v_world) al join public.airlines a on a.id = al.airline_id
     where al.airline_id::text = btrim(v_arg ->> 'airline')
        or lower(btrim(v_arg ->> 'airline')) in (lower(a.iata_code), lower(a.planner_name), lower(a.public_name), lower(a.game_name))
     order by al.ord
     limit 1;
    if v_airline is null then
      raise exception 'briefing: % isn''t one of our active airlines in world %', v_arg ->> 'airline', v_world using errcode = '22023';
    end if;
    return private.briefing_doc(v_airline, coalesce((v_arg ->> 'as_of')::timestamptz, now()));
  end if;
  raise exception 'unknown kind';
end
$function$;

-- ---------------------------------------------------------------- 3. access: the builder is nobody's to call from outside
revoke all on function private.briefing_doc(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.export_for_report(text, text, text) from public, anon, authenticated;
grant execute on function public.export_for_report(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------- 4. descriptions (decision #10)
comment on function private.briefing_doc(bigint, timestamptz) is 'The airline briefing (#24): one airline''s document for export_for_report(''briefing''), read only, with no check of its own: the airline (id, world, code, names, game ID); deliveries, its aircraft not yet filed (status on_order or delivered) with type, cabin as ordered and now, bases, order date and note, delivery time and whether it has arrived by p_as_of, and each one''s plan cards with their legs in order (UTC weekdays and minute, block, service code); todos, the open to-dos (not done) of the airline and of the group (no airline), with their steps; fare_plan, fare_plan_status()''s document (private.fig_fare_plan()); route_loads, route_loads()''s routes and flights for this airline only (private.fig_route_loads()). Deliveries, plan cards and to-dos are the tables as they are now; the fare plan and the loads are as of p_as_of.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report, gander monthly, the airline briefing and the planning library: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19); and one airline''s briefing rows (kind briefing, p_arg {"airline": its id, code or name, "as_of", "world"}, the airline required: its deliveries with their plan cards and legs, open to-dos of the airline and the group, fare_plan_status() and route_loads() for it, private.briefing_doc(), #24; read only). Kind planner (the old planner''s documents) is refused since the clean-up (build pull request 14). Needs the ingest secret.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

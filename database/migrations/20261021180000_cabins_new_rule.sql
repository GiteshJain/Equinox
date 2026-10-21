-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1): it drops two settings and four columns,
-- so it isn't applied from a chat. Paste the whole file and press Run; the Building chat then records it and checks it.
--
-- Cabins follow the new rule (21 Oct 2026; manual §5; spec docs/specs/2026-10-21-cabins-new-rule.md, Gitesh). Since
-- 20 Oct the cabin is chosen with each order: if one route takes more than 65% of the aircraft's block time, the layout
-- that route's market calls for (Standard, Leisure, Leisure Plus or Comfort); otherwise the layout with the most seats;
-- Ryanair flies Standard only. We no longer refit, so the Cabins board goes, and each market keeps only its layout.
--   1. Settings: cabin_refit_cost and cabin_refit_share_pct go (every world, and any airline's own); cabin_route_share_pct
--      (65, percent of block time) is added in every world, described. Past refits stay in spending_log.
--   2. aircraft_cabin_keeps is kept with its rows, as history, and described as retired: nothing writes to it.
--   3. markets: layout is added (text, one of Standard, Leisure, Leisure Plus or Comfort, a check, described), filled from
--      the cabin of each market's default layout (default_config_id: every -LP cabin Leisure Plus, -CMF Comfort, -LEI
--      Leisure, -STD Standard; a low-cost airline's market Standard if it has none), made not null; then
--      default_type_id, default_config_id, fare_y_pct and fare_j_pct are dropped (their foreign keys and indexes go with
--      them).
--   4. Replaced, same arguments: private.rules_input_doc() (so rules_input() and export_for_report('rules')) carries each
--      layout's name (cabin_configs.cabin), each airline's is_lcc, and each route's own cabin_choice and its market's
--      layout (market_layout), for the plan card's cabin (the library's card.cabinFor); private.briefing_doc() gives each
--      plan card its config_id, so the briefing's card check sees the card's cabin.
-- Nothing else in the database reads the dropped columns: checked in every function and view of database/current/, and
-- the guard below checks the database's own function code (comments included) before anything changes. Postgres itself
-- refuses to drop a column a view uses (nothing here cascades), and the file runs as one transaction, so either all of it
-- happens or none of it does.
-- To undo it: the columns' values are in last night's copy (the README in equinox-backups), or ask the Building chat.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261021180000_cabins_new_rule', true);

do $guard$
declare v_bad text;
begin
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private')
     and p.prosrc ~ '\m(default_type_id|default_config_id|fare_y_pct|fare_j_pct)\M';
  if v_bad is not null then
    raise exception 'these functions still name a column of markets this file drops, so nothing was changed: %', v_bad;
  end if;
end
$guard$;

-- ============================================================ 1. the settings
delete from public.settings where key in ('cabin_refit_cost', 'cabin_refit_share_pct');

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'cabin_route_share_pct', '65'::jsonb, 'percent of block time',
       'The cabin is chosen with each order (manual §5): if one route takes more than this share of the aircraft''s block time, the layout that route calls for (its own choice, else its market''s layout); otherwise the layout with the most seats. Ryanair flies Standard only. The plan card suggests its cabin by it (the planning library''s card.cabinFor)',
       date '2026-10-20',
       'Gitesh, 20 Oct: the cabin follows the route the aircraft mostly flies, else the most seats; the markets'' old default cabins don''t capture the new layouts'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2. the cabins kept as they are: history only
comment on table public.aircraft_cabin_keeps is 'Retired 21 Oct (manual §5; spec docs/specs/2026-10-21-cabins-new-rule.md): the Cabins board''s "Keep as is" decisions, kept as history; nothing writes to it since the board went (we no longer refit; the cabin is chosen with each order). Each row: the aircraft kept its cabin although its routes called for this one. Replaced the planner''s cabinKeep.';

-- ============================================================ 3. each market keeps only its layout
alter table public.markets add column layout text;

-- the cabin of its default layout; a low-cost airline's market without one, Standard
update public.markets m
   set layout = coalesce((select c.cabin from public.cabin_configs c where c.id = m.default_config_id and c.world_id = m.world_id),
                         (select 'Standard' from public.airlines al where al.id = m.airline_id and al.is_lcc));

do $fill$
declare v_bad text;
begin
  select string_agg(m.id || ' (' || m.name || ')', ', ' order by m.id) into v_bad from public.markets m where m.layout is null;
  if v_bad is not null then
    raise exception 'these markets have no layout to take (no default cabin layout with a cabin, and not a low-cost airline''s), so nothing was changed: %', v_bad;
  end if;
end
$fill$;

alter table public.markets alter column layout set not null;
alter table public.markets add constraint markets_layout_check check (layout in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort'));

alter table public.markets
  drop column default_type_id,
  drop column default_config_id,
  drop column fare_y_pct,
  drop column fare_j_pct;

comment on table public.markets is 'Each airline''s markets, with the cabin layout each calls for (layout; manual §5). Since 21 Oct a market keeps only its layout: its default aircraft, default cabin and fares went (spec docs/specs/2026-10-21-cabins-new-rule.md). Replaces the planner''s ref.markets.';
comment on column public.markets.layout is 'The cabin layout the market calls for: Standard, Leisure, Leisure Plus or Comfort (manual §5). A plan card''s cabin takes it where one route of the market flies more than cabin_route_share_pct of the aircraft''s block time, unless the route has its own choice (routes.cabin_choice). Filled on 21 Oct from the cabin of the market''s old default layout; changed in Reference → Markets';

-- ============================================================ 4. the planning library's input and the briefing
CREATE OR REPLACE FUNCTION private.rules_input_doc(p_world_id bigint, p_routes text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint;
  v_name text;
begin
  if p_routes is null or p_routes not in ('all', 'flown') then
    raise exception 'rules_input: p_routes must be all or flown, not %', coalesce(p_routes, 'null') using errcode = '22023';
  end if;
  select x.id, x.name into w, v_name from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', coalesce(p_world_id::text, 'no default world') using errcode = '22023'; end if;
  return (
    with
    -- the routes the document holds: every route that isn't removed, or with 'flown' only those that have rotations
    rts as (
      select r.* from public.routes r
       where r.world_id = w and not r.removed
         and (p_routes = 'all' or exists (select 1 from public.rotations ro where ro.route_id = r.id))),
    -- the airlines the planning rows name, and every airline of our groups (the same with 'all' and 'flown')
    named(id) as (
      select b.airline_id from public.airline_bases b where b.world_id = w
      union select a.airline_id from public.aircraft a where a.world_id = w
      union select r.airline_id from public.routes r where r.world_id = w and not r.removed
      union select r.airline_id from public.rotations r where r.world_id = w
      union select l.airline_id from public.flight_legs l where l.world_id = w
      union select al.id from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
             where al.world_id = w and g.kind = 'ours'),
    -- every airport the document's routes, a leg, a base or an aircraft's base uses
    codes(code) as (
      select r.hub_code from rts r
      union select r.dest_code from rts r
      union select l.origin_code from public.flight_legs l where l.world_id = w
      union select l.dest_code from public.flight_legs l where l.world_id = w
      union select b.airport_code from public.airline_bases b where b.world_id = w
      union select a.base_code from public.aircraft a where a.world_id = w and a.base_code is not null)
    select jsonb_build_object(
      'world', jsonb_build_object('id', w, 'name', v_name),
      'settings', (select coalesce(jsonb_object_agg(s.key, s.value order by s.key), '{}'::jsonb)
                     from public.settings s where s.world_id = w and s.airline_id is null),
      'world_rules', (select coalesce(jsonb_object_agg(r.key, r.value order by r.key), '{}'::jsonb)
                        from public.world_rules r where r.world_id = w),
      'aircraft_types', (select coalesce(jsonb_agg(jsonb_build_object(
                            'id', t.id, 'name', t.name, 'family_no', t.family_no, 'seats_max', t.seats_max, 'cruise_kmh', t.cruise_kmh,
                            'min_turn_min', t.min_turn_min, 'gap_target_h', t.gap_target_h, 'maint_per_cycle', t.maint_per_cycle,
                            'maint_per_hour', t.maint_per_hour, 'ground_keep_min', t.ground_keep_min) order by t.id), '[]'::jsonb)
                           from public.aircraft_types t where t.world_id = w),
      -- each layout with its name (cabin: Standard, Leisure, Leisure Plus or Comfort; since 21 Oct, for the plan card's cabin)
      'cabin_configs', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', c.id, 'code', c.code, 'aircraft_type_id', c.aircraft_type_id, 'seats', c.seats, 'cabin', c.cabin) order by c.id), '[]'::jsonb)
                          from public.cabin_configs c where c.world_id = w),
      -- each airport with its country's region (countries.region, #18 build pull request 12); none without a country
      'airports', (select coalesce(jsonb_agg(jsonb_build_object(
                      'code', k.code, 'city', a.city, 'country_code', a.country_code, 'region', co.region, 'lat', a.lat, 'lon', a.lon,
                      'utc_offset', coalesce(wa.utc_offset_override, a.utc_offset), 'utc_offset_override', wa.utc_offset_override,
                      'mct_min', wa.mct_min, 'night_ban_from', to_char(wa.night_ban_from, 'HH24:MI'), 'night_ban_to', to_char(wa.night_ban_to, 'HH24:MI'),
                      'closed', coalesce(wa.closed, false)) order by k.code collate "C"), '[]'::jsonb)
                     from codes k
                     left join public.airports a on a.code = k.code
                     left join public.countries co on co.code = a.country_code
                     left join public.world_airports wa on wa.world_id = w and wa.airport_code = k.code),
      -- is_lcc since 21 Oct: a low-cost airline flies Standard layouts only (manual §5)
      'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', al.id, 'iata_code', al.iata_code, 'game_id', al.game_id, 'game_name', al.game_name, 'planner_name', al.planner_name,
                      'public_name', al.public_name, 'position', al.position, 'active', al.active, 'ours', coalesce(g.kind = 'ours', false),
                      'is_lcc', coalesce(al.is_lcc, false),
                      -- the settings as they apply to this airline: its own override of a key in place of the world's value
                      'settings', (select coalesce(jsonb_object_agg(s.key, s.value order by s.key), '{}'::jsonb)
                                     from (select distinct on (st.key) st.key, st.value from public.settings st
                                            where st.world_id = w and (st.airline_id is null or st.airline_id = al.id)
                                            order by st.key, st.airline_id nulls last) s))
                      order by al.position nulls last, al.id), '[]'::jsonb)
                     from public.airlines al
                     left join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                    where al.world_id = w and al.id in (select n.id from named n)),
      'airline_bases', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', b.id, 'airline_id', b.airline_id, 'airport_code', b.airport_code, 'role', b.role, 'is_main', b.is_main,
                           'parent_base_id', b.parent_base_id, 'parent_code', pb.airport_code,
                           'bank_times', (select jsonb_agg(to_char(t, 'HH24:MI') order by o) from unnest(b.bank_times) with ordinality as u(t, o)),
                           'flight_no_from', b.flight_no_from, 'last_flight_no', b.last_flight_no, 'position', b.position)
                           order by b.position nulls last, b.id), '[]'::jsonb)
                          from public.airline_bases b left join public.airline_bases pb on pb.id = b.parent_base_id
                         where b.world_id = w),
      'aircraft', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', a.id, 'registration', a.registration, 'airline_id', a.airline_id, 'aircraft_type_id', a.aircraft_type_id,
                      'cabin_config_id', a.cabin_config_id, 'base_code', a.base_code, 'status', a.status) order by a.id), '[]'::jsonb)
                     from public.aircraft a where a.world_id = w),
      -- each route with its market (any override applied) and, since 21 Oct, the layout it calls for: its own cabin_choice
      -- and its market's layout
      'routes', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', r.id, 'airline_id', r.airline_id, 'hub_code', r.hub_code, 'dest_code', r.dest_code,
                    'distance_km', coalesce(r.distance_override_km, r.distance_km),
                    'market_id', m.id, 'market', m.name, 'market_layout', m.layout, 'cabin_choice', r.cabin_choice) order by r.id), '[]'::jsonb)
                   from rts r
                   left join public.markets m on m.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end),
      'rotations', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', r.id, 'airline_id', r.airline_id, 'route_id', r.route_id, 'legacy_key', r.legacy_key) order by r.id), '[]'::jsonb)
                      from public.rotations r where r.world_id = w),
      'flight_legs', (select coalesce(jsonb_agg(jsonb_build_object(
                         'id', l.id, 'airline_id', l.airline_id, 'rotation_id', l.rotation_id, 'leg_no', l.leg_no, 'flight_no', l.flight_no,
                         'origin_code', l.origin_code, 'dest_code', l.dest_code, 'aircraft_id', l.aircraft_id, 'days_utc', to_jsonb(l.days_utc),
                         'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min) order by l.rotation_id, l.leg_no, l.id), '[]'::jsonb)
                        from public.flight_legs l where l.world_id = w),
      -- the service profiles (service_profiles), for the plan card's service check (#18 build pull request 10)
      'service_profiles', (select coalesce(jsonb_agg(jsonb_build_object(
                              'id', s.id, 'code', s.code, 'airline_id', s.airline_id, 'up_to_km', s.up_to_km) order by s.id), '[]'::jsonb)
                             from public.service_profiles s where s.world_id = w))
  );
end
$function$;

comment on function public.rules_input(bigint, text) is 'Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world''s values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats); cabin_configs (code, type, seats and, since 21 Oct, the layout''s name, cabin); every airport any route, leg or base uses (position, country and its region, UTC offset with the world''s correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name, whether low cost: is_lcc), each with its settings as they apply to it (its own overrides in place of the world''s values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren''t removed (distance and market with any override applied, and since 21 Oct the market''s layout, market_layout, and the route''s own cabin_choice, for the plan card''s cabin); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg; and service_profiles (code, airline or none for the shared ones, up to km), for the plan card''s service check (#18 build pull request 10). p_routes: all (the default) or flown, the new planner''s lighter start (#18, design §5): only the routes that have rotations, and only the airports they, the legs, the bases and the aircraft use; the rest of the document is the same. The new planner (flown), the scripts (export_for_report(''rules''), all) and Claude''s command (node lib/rules/dist/cli.js) build the library''s Rules object from it. Staff only; runs as owner and checks the caller itself.';

CREATE OR REPLACE FUNCTION private.briefing_doc(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with al as (select a.id, a.world_id, a.iata_code, a.planner_name, a.public_name, a.game_name, a.game_id
                from public.airlines a where a.id = p_airline_id),
  -- loads by route and flight number over the 7 days to the moment, as route_loads() gives them, this airline's only
  rl as (select private.fig_route_loads(al.world_id, p_as_of) as d from al)
  select jsonb_build_object(
    'airline', (select jsonb_build_object('id', al.id, 'world_id', al.world_id, 'code', al.iata_code, 'planner_name', al.planner_name,
                                          'public_name', al.public_name, 'game_name', al.game_name, 'game_id', al.game_id) from al),
    'as_of', private.fig_ts(p_as_of),
    -- the aircraft not yet filed: on order, or arrived and not yet flying (status delivered), each with its plan cards
    -- (each with its cabin, config_id, since 21 Oct, for the card check's cabin)
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
                          'config_id', pc.config_id, 'updated_at', private.fig_ts(pc.updated_at),
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

comment on function private.briefing_doc(bigint, timestamptz) is 'The airline briefing (#24): one airline''s document for export_for_report(''briefing''), read only, with no check of its own: the airline (id, world, code, names, game ID); deliveries, its aircraft not yet filed (status on_order or delivered) with type, cabin as ordered and now, bases, order date and note, delivery time and whether it has arrived by p_as_of, and each one''s plan cards (with the card''s cabin, config_id, since 21 Oct) with their legs in order (UTC weekdays and minute, block, service code); todos, the open to-dos (not done) of the airline and of the group (no airline), with their steps; fare_plan, fare_plan_status()''s document (private.fig_fare_plan()); route_loads, route_loads()''s routes and flights for this airline only (private.fig_route_loads()). Deliveries, plan cards and to-dos are the tables as they are now; the fare plan and the loads are as of p_as_of.';

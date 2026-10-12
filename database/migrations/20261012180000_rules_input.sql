-- rules_input(): everything the planning library needs, in one call (decision #19, build pull request 2, "the planning
-- library"). Design: docs/design/2026-10-12-planner-app.md §5 ("Rules at start") and §7. Spec:
-- docs/specs/2026-10-12-rules-library.md §2.
--
-- Adds two functions and changes one; removes nothing:
--   public.rules_input(p_world_id bigint default null): one JSON document for the world (the default world when null):
--     settings (the world's values) and world_rules, as key → value; aircraft_types; cabin_configs; every airport any
--     route, leg or base uses, with the world's correction to its UTC offset applied, its minimum connection time and
--     night ban; airlines (ours, and any the planning rows name), each with its settings as they apply to it (its
--     overrides in place of the world's values); airline_bases; aircraft; routes that aren't removed (distance and
--     market with any override applied); rotations; flight_legs. The library builds its Rules object from it
--     (lib/rules/src/input.ts). Staff only; runs as owner with an empty search path and checks the caller itself.
--   private.rules_input_doc(p_world_id bigint): builds that document, with no check of its own. Only the two functions
--     here call it: rules_input() for staff, and export_for_report() with the ingest secret.
--   public.export_for_report(): gains kind 'rules' for the scripts (p_arg: the world id, or empty for the default
--     world), answering exactly what rules_input() answers. Every other kind is unchanged.
-- Nothing calls rules_input() yet: the new planner's screens start using it from build pull request 5, and the scripts
-- move onto it in pull request 4.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261012180000_rules_input', true);

-- ============================================================ 1. the document
create or replace function private.rules_input_doc(p_world_id bigint)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint;
  v_name text;
begin
  select x.id, x.name into w, v_name from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', coalesce(p_world_id::text, 'no default world') using errcode = '22023'; end if;
  return (
    with
    -- the airlines the planning rows name, and every airline of our groups
    named(id) as (
      select b.airline_id from public.airline_bases b where b.world_id = w
      union select a.airline_id from public.aircraft a where a.world_id = w
      union select r.airline_id from public.routes r where r.world_id = w and not r.removed
      union select r.airline_id from public.rotations r where r.world_id = w
      union select l.airline_id from public.flight_legs l where l.world_id = w
      union select al.id from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
             where al.world_id = w and g.kind = 'ours'),
    -- every airport a route that isn't removed, a leg, a base or an aircraft's base uses
    codes(code) as (
      select r.hub_code from public.routes r where r.world_id = w and not r.removed
      union select r.dest_code from public.routes r where r.world_id = w and not r.removed
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
      'cabin_configs', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', c.id, 'code', c.code, 'aircraft_type_id', c.aircraft_type_id, 'seats', c.seats) order by c.id), '[]'::jsonb)
                          from public.cabin_configs c where c.world_id = w),
      'airports', (select coalesce(jsonb_agg(jsonb_build_object(
                      'code', k.code, 'city', a.city, 'country_code', a.country_code, 'lat', a.lat, 'lon', a.lon,
                      'utc_offset', coalesce(wa.utc_offset_override, a.utc_offset), 'utc_offset_override', wa.utc_offset_override,
                      'mct_min', wa.mct_min, 'night_ban_from', to_char(wa.night_ban_from, 'HH24:MI'), 'night_ban_to', to_char(wa.night_ban_to, 'HH24:MI'),
                      'closed', coalesce(wa.closed, false)) order by k.code collate "C"), '[]'::jsonb)
                     from codes k
                     left join public.airports a on a.code = k.code
                     left join public.world_airports wa on wa.world_id = w and wa.airport_code = k.code),
      'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', al.id, 'iata_code', al.iata_code, 'game_id', al.game_id, 'game_name', al.game_name, 'planner_name', al.planner_name,
                      'public_name', al.public_name, 'position', al.position, 'active', al.active, 'ours', coalesce(g.kind = 'ours', false),
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
      'routes', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', r.id, 'airline_id', r.airline_id, 'hub_code', r.hub_code, 'dest_code', r.dest_code,
                    'distance_km', coalesce(r.distance_override_km, r.distance_km),
                    'market_id', m.id, 'market', m.name) order by r.id), '[]'::jsonb)
                   from public.routes r
                   left join public.markets m on m.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end
                  where r.world_id = w and not r.removed),
      'rotations', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', r.id, 'airline_id', r.airline_id, 'route_id', r.route_id, 'legacy_key', r.legacy_key) order by r.id), '[]'::jsonb)
                      from public.rotations r where r.world_id = w),
      'flight_legs', (select coalesce(jsonb_agg(jsonb_build_object(
                         'id', l.id, 'airline_id', l.airline_id, 'rotation_id', l.rotation_id, 'leg_no', l.leg_no, 'flight_no', l.flight_no,
                         'origin_code', l.origin_code, 'dest_code', l.dest_code, 'aircraft_id', l.aircraft_id, 'days_utc', to_jsonb(l.days_utc),
                         'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min) order by l.rotation_id, l.leg_no, l.id), '[]'::jsonb)
                        from public.flight_legs l where l.world_id = w))
  );
end
$function$;

create or replace function public.rules_input(p_world_id bigint default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then
    raise exception 'only planner staff can read the planning rules' using errcode = '42501';
  end if;
  return private.rules_input_doc(p_world_id);
end
$function$;

-- ============================================================ 2. export_for_report(): kind 'rules' for the scripts
-- As 20261011120000_history.sql left it, with the one new kind.
create or replace function public.export_for_report(p_secret text, p_kind text, p_arg text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    -- today's two documents, built from the tables by the adapter's getters (design §8)
    return jsonb_build_object('state', (public.planner_state_get() ->> 'json')::jsonb,
                              'loads', (select coalesce(jsonb_object_agg(g.month, g.json::jsonb), '{}'::jsonb) from public.planner_loads_get() g));
  elsif p_kind = 'rules' then
    -- the planning library's input, exactly as rules_input() gives it (design §7); p_arg: the world, or empty for the default
    return private.rules_input_doc(nullif(p_arg, '')::bigint);
  end if;
  raise exception 'unknown kind';
end
$function$;

-- ============================================================ 3. access (design §5)
revoke all on function private.rules_input_doc(bigint) from public, anon, authenticated, service_role;
revoke all on function public.rules_input(bigint) from public, anon, authenticated, service_role;
grant execute on function public.rules_input(bigint) to authenticated;
revoke all on function public.export_for_report(text, text, text) from public, anon, authenticated;
grant execute on function public.export_for_report(text, text, text) to anon, authenticated;

-- ============================================================ 4. descriptions (decision #10)
comment on function private.rules_input_doc(bigint) is 'The planning library''s input for a world (decision #19, design §7), with no check of its own: what rules_input() gives staff and export_for_report(''rules'') gives the scripts. See rules_input(). p_world_id: the world, or null for the default world.';
comment on function public.rules_input(bigint) is 'Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world''s values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats); cabin_configs; every airport any route, leg or base uses (position, UTC offset with the world''s correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name), each with its settings as they apply to it (its own overrides in place of the world''s values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren''t removed (distance and market with any override applied); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg. The new planner, the scripts (export_for_report(''rules'')) and Claude''s command (node lib/rules/dist/cli.js) build the library''s Rules object from it. Staff only; runs as owner and checks the caller itself.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report, gander monthly and the planning library: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planner ({state, loads}: today''s planner_state and planner_loads documents, built from the tables by planner_state_get() and planner_loads_get()); and the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19). Needs the ingest secret.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

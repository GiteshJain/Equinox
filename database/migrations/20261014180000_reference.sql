-- The new planner's last screens and what design §16 keeps for before the switch (decision #18, build pull request 12).
-- Spec: docs/specs/2026-10-14-interline-photos-reference.md, part 2 ("regions: add region to countries, filled from the
-- old planner's REGION_OF list ... the suggested aircraft size ... as settings, a world value with Ryanair's override,
-- read through rules_input() ... airline card photos: airlines.photo_city ... migrations add only").
--
-- Adds one column with its values, two settings (one with Ryanair's override) and the airports' region in the
-- planning library's input (same arguments), and fills airlines.photo_city where it's empty. Changes no function's
-- arguments and takes nothing away, so it can be applied from the chat:
--   countries.region: the region the old planner named for a country (its REGION_OF list, used by Hubs' connections table
--     and Check's hub readiness), and its fallback: Europe for a country not on the list (the column's default, so a
--     country the research adds later takes it too), Other for the unknown country (--). An airport with no country has
--     no region; the library calls that Other, as the old planner did.
--   private.rules_input_doc(p_world_id bigint, p_routes text): each airport gains its country's region. Everything else
--     is as before, so rules_input() and export_for_report('rules') answer as they did plus that one key per airport.
--   settings.suggested_size (every world) and Ryanair's own: the aircraft size Check suggests after a route for each move
--     of the order rotation (the old suggestSize for a frequency and the routes ready for another flight, bigSize for a
--     big market, feedSize for a smaller feeder), as a list per move whose first match wins: at least min_stars stars and
--     longer than over_km, when given. The planning library reads it through rules_input() (growth.suggestedSize).
--   settings.interline_rules (every world): the group's interline rules (manual §6) the old Interline screen kept in its
--     code (the interline countries and why, the partners in the game, the Europe zone, the hub rivals, the countries each
--     of our airlines covers, Ryanair with no one outside the group), which the new Interline screen reads.
--   airlines.photo_city: already there (the website's city photo for each airline, since 20261009210000) with the same
--     six cities Home's airline cards kept in their code; any of ours still empty takes its city from that list. Home's
--     cards read it now. Its description says so.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261014180000_reference', true);

-- ============================================================ 1. regions
alter table public.countries add column if not exists region text not null default 'Europe';

update public.countries c set region = v.region
  from (select r.region, unnest(string_to_array(r.codes, ' ')) as code
          from (values
            ('South Asia', 'IN PK BD LK NP MV BT AF'),
            ('China & North-East Asia', 'CN HK MO TW JP KR MN'),
            ('South-East Asia', 'MY SG TH VN KH LA MM BN ID PH TL'),
            ('Oceania', 'AU NZ FJ PG PF NC VU SB WS TO CK'),
            ('Middle East', 'AE QA OM BH KW SA TR IL JO LB IR IQ YE'),
            ('Russia & Central Asia', 'RU KZ UZ KG TJ TM AZ GE AM BY UA MD'),
            ('North America', 'US CA MX PM GL BM AG AI AW BB BQ BS CU CW DM DO GD GP HT JM KN KY LC MQ PR SX TC TT VC VI BZ CR GT HN NI PA SV'),
            ('South America', 'AR BO BR CL CO EC GF GY PE PY SR UY VE'),
            ('Africa', 'DZ EG LY MA TN AO BJ CD CG CI CM CV DJ ET GA GH GM GN GQ KE MG MR MU NA NG RE RW SC SN TD TG TZ UG YT ZA ZM ZW MZ BW SS SD SO'),
            ('Other', '--')) as r(region, codes)) v
 where c.code = v.code and c.region is distinct from v.region;

comment on column public.countries.region is 'The region the planner names for the country (Hubs'' connections table, Check''s hub readiness): South Asia, China & North-East Asia, South-East Asia, Oceania, Middle East, Russia & Central Asia, North America, South America or Africa as the old planner''s list had them; Europe for any other country (the default, so a country the research adds takes it); Other for the unknown country (--)';
comment on table public.countries is 'Country names by ISO code (-- for unknown), with the region the planner names for each. The same in every world. Replaces planner_data.countries; kept in step with the research by planner_data_set().';

-- ============================================================ 2. rules_input(): each airport's region
create or replace function private.rules_input_doc(p_world_id bigint, p_routes text default 'all')
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
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
      'cabin_configs', (select coalesce(jsonb_agg(jsonb_build_object(
                           'id', c.id, 'code', c.code, 'aircraft_type_id', c.aircraft_type_id, 'seats', c.seats) order by c.id), '[]'::jsonb)
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

comment on function private.rules_input_doc(bigint, text) is 'The planning library''s input for a world (decision #19, design §7), with no check of its own: what rules_input() gives staff and export_for_report(''rules'') gives the scripts (always ''all''). See rules_input(). p_world_id: the world, or null for the default world; p_routes: all (every route that isn''t removed) or flown (only routes with rotations, and only the airports they, the legs, the bases and the aircraft use).';
comment on function public.rules_input(bigint, text) is 'Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world''s values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats); cabin_configs; every airport any route, leg or base uses (position, country and its region, UTC offset with the world''s correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name), each with its settings as they apply to it (its own overrides in place of the world''s values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren''t removed (distance and market with any override applied); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg; and service_profiles (code, airline or none for the shared ones, up to km), for the plan card''s service check (#18 build pull request 10). p_routes: all (the default) or flown, the new planner''s lighter start (#18, design §5): only the routes that have rotations, and only the airports they, the legs, the bases and the aircraft use; the rest of the document is the same. The new planner (flown), the scripts (export_for_report(''rules''), all) and Claude''s command (node lib/rules/dist/cli.js) build the library''s Rules object from it. Staff only; runs as owner and checks the caller itself.';

-- ============================================================ 3. the suggested aircraft size
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'suggested_size',
       '{"big": [{"min_stars": 5, "type": "A321neo"}, {"type": "A320neo"}],
         "freq": [{"min_stars": 5, "type": "A321neo"}, {"min_stars": 3, "type": "A320neo"}, {"type": "E195"}],
         "feeder": [{"min_stars": 3, "over_km": 2500, "type": "A320neo"}, {"type": "E195"}]}'::jsonb,
       'aircraft type by move',
       'Check → Growth: the aircraft size suggested after a route, for each move of the order rotation (big market, frequency, smaller feeder; frequency also for the routes ready for another flight): the first entry the route meets (at least min_stars stars, longer than over_km km when given) names the type (the old planner''s bigSize, suggestSize and feedSize)',
       date '2026-10-14', 'The old planner''s sizes by stars and distance, given a home of their own (#19, design §16)'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select a.world_id, a.id, 'suggested_size',
       '{"big": [{"type": "A321neo"}],
         "freq": [{"min_stars": 4, "type": "A321neo"}, {"type": "E195"}],
         "feeder": [{"type": "E195"}]}'::jsonb,
       'aircraft type by move',
       'Ryanair''s own suggested sizes (two types: A321neo and E195): an A321neo for a big market, for a frequency on a route of 4 stars or more, else an E195',
       date '2026-10-14', 'The old planner''s Ryanair sizes, given a home of their own (#19, design §16)'
  from public.airlines a
  join public.groups g on g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
 where a.planner_name = 'Ryanair'
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 4. the interline rules
-- The group's interline rules (manual §6) as the old Interline screen kept them in its code (IL_YES, EUROPE_ZONE, IL_RIVAL,
-- IL_COVER, IL_PARTNERS, and Ryanair signing with no one outside the group), so the new Interline screen reads them as data
-- (design §2: nothing typed into code). Airlines by their code.
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'interline_rules',
       '{"countries": {"BR": "domestic", "AR": "domestic", "CO": "domestic", "CL": "domestic", "PE": "domestic", "RU": "domestic",
                       "JP": "domestic", "ID": "domestic", "PH": "domestic", "AU": "domestic", "NZ": "domestic", "ZA": "domestic",
                       "NG": "domestic", "IR": "domestic", "ET": "gateway", "KE": "gateway", "FJ": "gateway"},
         "europe_zone": ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT",
                         "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "GB", "NO", "CH", "IS"],
         "rivals": ["AE", "QA", "OM", "BH", "KW", "SA", "TR", "SG", "HK", "KR"],
         "covered": {"AW": ["CA", "MX", "AG", "AI", "AW", "BB", "BL", "BM", "BQ", "BS", "CU", "CW", "DM", "DO", "GD", "GP", "HT", "JM", "KN",
                            "KY", "LC", "MF", "MQ", "MS", "PR", "SX", "TC", "TT", "VC", "VG", "VI", "BZ", "CR", "GT", "HN", "NI", "PA", "SV"],
                     "MH": ["TH", "VN", "KH", "LA", "MM", "BN"],
                     "MU": ["MO", "TW", "MN", "KZ", "UZ", "KG", "TJ", "TM"],
                     "KF": ["NP", "LK", "BD", "MV", "BT"],
                     "VS": ["MA", "DZ", "TN", "LY", "EG"]},
         "group_only": ["FR"],
         "partners": {"AR": [{"name": "Aerolíneas Argentinas", "game_id": 159}],
                      "AU": [{"name": "Qantas", "game_id": 49}, {"name": "Virgin Australia", "game_id": 35}],
                      "BR": [{"name": "Azul", "game_id": 68}], "CL": [{"name": "LATAM Airlines Chile", "game_id": 76}],
                      "CO": [{"name": "Avianca", "game_id": 195}], "ET": [{"name": "Ethiopian Airlines", "game_id": 187}],
                      "FJ": [{"name": "Fiji Airways", "game_id": 139}], "ID": [{"name": "Garuda Indonesia", "game_id": 161}],
                      "JP": [{"name": "ANA", "game_id": 45}, {"name": "Japan Airlines", "game_id": 52}],
                      "NZ": [{"name": "Air New Zealand", "game_id": 160}], "NG": [{"name": "Ibom Air", "game_id": 117}],
                      "RU": [{"name": "Aeroflot", "game_id": 124}],
                      "ZA": [{"name": "South African Airways", "game_id": 103}, {"name": "Airlink", "game_id": 141}]}}'::jsonb,
       'countries and airlines',
       'Interline (manual §6): the countries with a real domestic network or a regional gateway (countries: domestic or gateway), and the partners in the game there (partners, by the game''s enterprise id); where not to sign: the Europe zone (europe_zone), the hub rivals (rivals), the countries one of our airlines covers (covered, by airline code), and airlines that sign with no one outside the group (group_only). A country with a group base is never an interline country. The Interline screen''s rows and its list of interline countries come from it (the old planner''s IL_YES, EUROPE_ZONE, IL_RIVAL, IL_COVER and IL_PARTNERS)',
       date '2026-10-14', 'The old Interline screen''s lists, given a home of their own (#19, design §2); the rules themselves since 25, 26 and 28 Sep and 5 Oct (manual §6)'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 5. the airline cards' photos
update public.airlines a set photo_city = v.city
  from (values ('Pan American', 'New York'), ('Virgin Atlantic', 'London'), ('Ryanair', 'Paris'), ('Kingfisher', 'Delhi'),
               ('China Eastern', 'Shanghai'), ('Malaysia Airlines', 'Kuala Lumpur')) as v(name, city),
       public.groups g
 where a.planner_name = v.name and g.id = a.group_id and g.world_id = a.world_id and g.kind = 'ours'
   and (a.photo_city is null or a.photo_city = '');

comment on column public.airlines.photo_city is 'The city whose photo stands for the airline (site_content media photos, by city): on the website, and behind the airline''s card on the planner''s Home';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

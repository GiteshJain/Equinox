-- rules_input(): the planning library's input in one call (decision #19, build pull request 2; spec
-- docs/specs/2026-10-12-rules-library.md §2). Run by database/rehearse.sh on the copy of last night's backup, after the
-- new migrations, inside a transaction that is rolled back. A failed check stops with an error that says where (ids,
-- keys and counts, never rows).
--   1. Who may call it: authenticated only (signed out, nobody); runs as owner with an empty search path; described.
--      The internal builder, private.rules_input_doc(), is nobody's to call but postgres's, and described.
--   2. As postgres: the document's counts equal the tables' (settings, world rules, types, cabins, airports used,
--      airlines, bases, aircraft, routes not removed, rotations, legs).
--   3. One leg, one airport and one setting read back exactly.
--   4. An airline's override wins over the world value: in that airline's settings, while the world's stay as they are
--      for the document and for every other airline. Every override the copy already has reads back the same way.
--   5. Signed out, refused; an account that isn't staff, refused; staff get what postgres gets.
--   6. export_for_report(secret, 'rules'), signed out as the scripts call it, gives the same document (with and without
--      the world's id); a wrong secret is refused.
--   7. p_routes (#18 build pull request 5, spec docs/specs/2026-10-13-home.md §1): 'all' (the default) is unchanged, the
--      document exactly as rules_input() gave it before this rehearsal's changes (database/tests/before/
--      rules_input_before.sql; a copy older than rules_input() has none, and section 2's counts are the check), but for
--      the two settings Home adds (airport_cap_warning_pct, aircraft_check_after_days), the one Tails adds
--      (aircraft_block_target_h) and the five Check adds that stay (growth_big_min_stars,
--      growth_ready_min_days, growth_ready_full_share, order_queue_grace_h, order_queue_warn_h), and Review's setting
--      (fare_plan_raise_pct) and service profiles (service_profiles, #18 build pull request 10, every row of the
--      world's), and build pull request 12's settings (suggested_size, interline_rules) and each airport's region (its
--      country's), and the cabins' new rule's (21 Oct, 20261021180000) setting (cabin_route_share_pct), each layout's
--      name (cabin_configs' cabin), each airline's is_lcc and each route's market_layout and cabin_choice, and each
--      aircraft type's reach (range_km, 28 Oct, lines in the planner):
--      in the document, then taken out before comparing, when the copy didn't have them; the two refit settings that
--      rule removes (cabin_refit_cost, cabin_refit_share_pct) must be gone, and are taken out of the before; 'flown' holds every route with a rotation and no other, and exactly the airports a flown
--      route, a leg, a base or an aircraft uses, each read back as 'all' has it; everything else in the document is the
--      same; any other value is refused. Prints both documents' sizes (the new planner's start).

create temporary table t_ri (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_ri to authenticated, anon;
insert into public.planner_users (email) values ('rules-input-staff@example.com') on conflict do nothing;

-- ---------------------------------------------------------------- 1. who may call it
do $test$
begin
  assert (select p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p
           where p.oid = 'public.rules_input(bigint, text)'::regprocedure),
    'rules_input() doesn''t run as owner with an empty search path';
  assert not has_function_privilege('anon', 'public.rules_input(bigint, text)', 'execute'), 'signed out, rules_input() can be called';
  assert has_function_privilege('authenticated', 'public.rules_input(bigint, text)', 'execute'), 'signed in, rules_input() can''t be called';
  assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                      where p.oid in ('public.rules_input(bigint, text)'::regprocedure, 'private.rules_input_doc(bigint, text)'::regprocedure) and a.grantee = 0),
    'everyone (PUBLIC) can call rules_input() or private.rules_input_doc()';
  assert not has_function_privilege('anon', 'private.rules_input_doc(bigint, text)', 'execute')
     and not has_function_privilege('authenticated', 'private.rules_input_doc(bigint, text)', 'execute'),
    'private.rules_input_doc() can be called from outside the database';
  assert (select coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = 'private.rules_input_doc(bigint, text)'::regprocedure),
    'private.rules_input_doc() doesn''t have an empty search path';
  assert obj_description('public.rules_input(bigint, text)'::regprocedure, 'pg_proc') is not null, 'rules_input() has no description';
  assert obj_description('private.rules_input_doc(bigint, text)'::regprocedure, 'pg_proc') is not null, 'private.rules_input_doc() has no description';
  assert obj_description('public.export_for_report(text, text, text)'::regprocedure, 'pg_proc') like '%rules_input()%',
    'export_for_report()''s description doesn''t mention kind rules';
  raise notice 'who may call it: signed in only, runs as owner with an empty search path; its builder is internal; both described';
end
$test$;

-- ---------------------------------------------------------------- 7. p_routes: 'all' unchanged, 'flown' the lighter start
-- (run second, so that its sizes are among the four notices the rehearsal's log shows for a test)
do $test$
declare
  w bigint := (select x.id from public.worlds x where x.is_default);
  d_all jsonb; d_flown jsonb; d_before jsonb; d_cmp jsonb; n_new int := 0; bad text; refused int := 0; v text;
  n_routes int; n_codes int; n_removed int;
begin
  assert w is not null, 'the copy has no default world';
  d_all := public.rules_input();
  d_flown := public.rules_input(w, 'flown');
  assert public.rules_input(w, 'all') = d_all and public.rules_input(null, 'all') = d_all, 'rules_input(world, all) differs from rules_input()';
  -- 'all' is the document exactly as rules_input() gave it before this rehearsal's changes (when the copy had it: a backup
  -- taken before 20261012180000 went live has none, and then section 2's counts against the tables are the check), but
  -- for the two settings 20261013200000 adds, the one 20261013230000 (Tails) adds, the seven 20261013235900 (Check)
  -- adds, the two 20261014220000 (the capture checks, #21) adds, the one 20261016120000 (new routes' age) adds, the
  -- six 20261021120000 (the fare ladder) adds, the one 20261021230000 (a new frequency's hold) adds, the one
  -- 20261021233000 (the world scan in the capture, scan_every_days) adds, the three 20261021235000 (competition
  -- analysis: competition_threat_min_weekly, trunk_month_from, trunk_month_to) adds and the one 20261022010000 (the
  -- cabin charge check, cabin_charge_check_from) adds, the two 20261022060000 (stations) adds and the three
  -- 20261022090000 (the aircraft age check: replace_new_years, replace_used_years, replace_warn_days) adds, the five
  -- 20261023100000 (the fare ladder under launch: fare_under_launch_load_pct, _levels, _days, _min_flights and
  -- _decide_load_pct, with Ryanair's own _levels) adds, the two 20261023120000 (rivals' fleets: rival_orders_flag_pct,
  -- rival_orders_flag_min) adds, the one 20261023140000 (rivals' connections: rival_connection_detour_max) adds and
  -- the two 20261026180000 (the cabin by distance: cabin_leisure_max_km, cabin_leisure_plus_max_km) adds and the one
  -- 20261027000000 (the fare ladder's hold after a step up: fare_ladder_up_hold_weeks) adds, the one 20261027210000
  -- (the aircraft evaluation script: aircraft_eval_types) adds and the one 20261027230000 (the planning target for
  -- connections: plan_connection_target_h) adds and the one 20261027220000 (the openings' A350 cut-over:
  -- a350_1000_from_km) adds and the three 20261028120000 (long haul in lines: line_min_km, maintenance_max_gap_h,
  -- line_aircraft) adds, which
  -- are new in it: they're checked, then taken out (from the
  -- world's settings and each airline's) before comparing
  select b.doc into d_before from rehearsal_before.rules_input b;
  d_cmp := d_all;
  if d_before is not null then
    -- (Check's two refit settings, cabin_refit_cost and cabin_refit_share_pct, are no longer in this list: the cabins'
    -- new rule removed them, so a copy without them is one where they're gone, not one from before they came; below)
    foreach v in array array['airport_cap_warning_pct', 'aircraft_check_after_days', 'aircraft_block_target_h',
                             'growth_big_min_stars', 'growth_ready_min_days', 'growth_ready_full_share',
                             'order_queue_grace_h', 'order_queue_warn_h', 'fare_plan_raise_pct', 'suggested_size', 'interline_rules',
                             'capture_loads_min_share', 'capture_statement_min_share', 'growth_new_route_days',
                             'fare_ladder_step_pts', 'fare_ladder_up_share', 'fare_ladder_down_share', 'fare_ladder_min_departures',
                             'fare_ladder_hold_weeks', 'fare_ladder_cap_pts', 'cabin_route_share_pct', 'fare_ladder_capacity_hold_days',
                             'scan_every_days', 'competition_threat_min_weekly', 'trunk_month_from', 'trunk_month_to',
                             'cabin_charge_check_from', 'station_flight_no_from', 'station_flight_no_to',
                             'replace_new_years', 'replace_used_years', 'replace_warn_days',
                             'fare_under_launch_load_pct', 'fare_under_launch_levels', 'fare_under_launch_days',
                             'fare_under_launch_min_flights', 'fare_under_launch_decide_load_pct',
                             'rival_orders_flag_pct', 'rival_orders_flag_min', 'rival_connection_detour_max',
                             'cabin_leisure_max_km', 'cabin_leisure_plus_max_km', 'fare_ladder_up_hold_weeks',
                             'aircraft_eval_types', 'plan_connection_target_h', 'a350_1000_from_km',
                             'line_min_km', 'maintenance_max_gap_h', 'line_aircraft'] loop
      continue when d_before -> 'settings' ? v;
      assert d_all -> 'settings' ? v, 'all: the new setting ' || v || ' isn''t in the document';
      d_cmp := jsonb_set(d_cmp, '{settings}', (d_cmp -> 'settings') - v);
      d_cmp := jsonb_set(d_cmp, '{airlines}', (select coalesce(jsonb_agg(case when a ? 'settings' then jsonb_set(a, '{settings}', (a -> 'settings') - v) else a end order by i), '[]'::jsonb)
                                                 from jsonb_array_elements(d_cmp -> 'airlines') with ordinality as e(a, i)));
      n_new := n_new + 1;
    end loop;
    -- the service profiles (build pull request 10): every row of the world's, then taken out when the copy didn't have them
    if not d_before ? 'service_profiles' then
      assert jsonb_array_length(d_all -> 'service_profiles') = (select count(*) from public.service_profiles s where s.world_id = w),
        'all: the service profiles aren''t every row of the world''s';
      d_cmp := d_cmp - 'service_profiles';
      n_new := n_new + 1;
    end if;
    -- each airport's region (build pull request 12): its country's, none without one; then taken out when the copy's
    -- airports didn't carry it
    if not exists (select 1 from jsonb_array_elements(d_before -> 'airports') e where e ? 'region') then
      select string_agg(e ->> 'code', ', ') into bad from jsonb_array_elements(d_all -> 'airports') e
       where not e ? 'region'
          or (e ->> 'region') is distinct from (select c.region from public.airports a join public.countries c on c.code = a.country_code
                                                  where a.code = e ->> 'code');
      assert bad is null, 'all: these airports don''t carry their country''s region: ' || bad;
      d_cmp := jsonb_set(d_cmp, '{airports}', (select coalesce(jsonb_agg(e - 'region' order by i), '[]'::jsonb)
                                                 from jsonb_array_elements(d_cmp -> 'airports') with ordinality as x(e, i)));
      n_new := n_new + 1;
    end if;
    -- the default line's variants (20261019180000): 8 more aircraft types and 28 more cabin layouts, and the sheet's
    -- figures on the types we had (cruise speeds, the A350-900ULR's seats); while pending, the types and layouts are
    -- checked here (every one from before still there, the new ones added) and taken out of the comparison
    if jsonb_array_length(d_all -> 'aircraft_types') > jsonb_array_length(d_before -> 'aircraft_types') then
      assert jsonb_array_length(d_all -> 'aircraft_types') = jsonb_array_length(d_before -> 'aircraft_types') + 8, 'all: the default line should add 8 aircraft types';
      assert jsonb_array_length(d_all -> 'cabin_configs') = jsonb_array_length(d_before -> 'cabin_configs') + 28, 'all: the default line should add 28 cabin layouts';
      assert not exists (select 1 from jsonb_array_elements(d_before -> 'aircraft_types') e
                          where not exists (select 1 from jsonb_array_elements(d_all -> 'aircraft_types') x where x -> 'id' = e -> 'id')),
        'all: an aircraft type from before is gone';
      d_cmp := d_cmp - 'aircraft_types' - 'cabin_configs';
      d_before := d_before - 'aircraft_types' - 'cabin_configs';
      n_new := n_new + 1;
    end if;
    -- the cabins' new rule (20261021180000): the two refit settings go (from the world's settings and each airline's),
    -- so they're checked gone and taken out of the before; each layout's name, each airline's is_lcc and each route's
    -- market_layout and cabin_choice are new: checked against the tables in cabins_new_rule_test.sql, taken out here
    foreach v in array array['cabin_refit_cost', 'cabin_refit_share_pct'] loop
      continue when not (d_before -> 'settings' ? v);
      assert not (d_all -> 'settings' ? v), 'all: the removed setting ' || v || ' is still in the document';
      d_before := jsonb_set(d_before, '{settings}', (d_before -> 'settings') - v);
      d_before := jsonb_set(d_before, '{airlines}', (select coalesce(jsonb_agg(case when a ? 'settings' then jsonb_set(a, '{settings}', (a -> 'settings') - v) else a end order by i), '[]'::jsonb)
                                                       from jsonb_array_elements(d_before -> 'airlines') with ordinality as e(a, i)));
      n_new := n_new + 1;
    end loop;
    if d_before ? 'cabin_configs' and not exists (select 1 from jsonb_array_elements(d_before -> 'cabin_configs') e where e ? 'cabin') then
      assert not exists (select 1 from jsonb_array_elements(d_all -> 'cabin_configs') e where not e ? 'cabin'), 'all: a cabin layout has no name (cabin)';
      d_cmp := jsonb_set(d_cmp, '{cabin_configs}', (select coalesce(jsonb_agg(e - 'cabin' order by i), '[]'::jsonb)
                                                      from jsonb_array_elements(d_cmp -> 'cabin_configs') with ordinality as x(e, i)));
      n_new := n_new + 1;
    end if;
    if not exists (select 1 from jsonb_array_elements(d_before -> 'airlines') e where e ? 'is_lcc') then
      assert not exists (select 1 from jsonb_array_elements(d_all -> 'airlines') e where not e ? 'is_lcc'), 'all: an airline has no is_lcc';
      d_cmp := jsonb_set(d_cmp, '{airlines}', (select coalesce(jsonb_agg(e - 'is_lcc' order by i), '[]'::jsonb)
                                                 from jsonb_array_elements(d_cmp -> 'airlines') with ordinality as x(e, i)));
      n_new := n_new + 1;
    end if;
    if not exists (select 1 from jsonb_array_elements(d_before -> 'routes') e where e ? 'market_layout') then
      assert not exists (select 1 from jsonb_array_elements(d_all -> 'routes') e where not (e ? 'market_layout' and e ? 'cabin_choice')),
        'all: a route has no market_layout or cabin_choice';
      d_cmp := jsonb_set(d_cmp, '{routes}', (select coalesce(jsonb_agg(e - 'market_layout' - 'cabin_choice' order by i), '[]'::jsonb)
                                               from jsonb_array_elements(d_cmp -> 'routes') with ordinality as x(e, i)));
      n_new := n_new + 1;
    end if;
    -- each type's reach (20261028180000, lines in the planner): range_km as the table has it, then taken out when the
    -- copy's types didn't carry it
    if d_cmp ? 'aircraft_types' and not exists (select 1 from jsonb_array_elements(d_before -> 'aircraft_types') e where e ? 'range_km') then
      select string_agg(e ->> 'id', ', ') into bad from jsonb_array_elements(d_all -> 'aircraft_types') e
       where not e ? 'range_km'
          or (e ->> 'range_km')::int is distinct from (select t.range_km from public.aircraft_types t where t.id = (e ->> 'id')::bigint);
      assert bad is null, 'all: these types don''t carry their range_km: ' || bad;
      d_cmp := jsonb_set(d_cmp, '{aircraft_types}', (select coalesce(jsonb_agg(e - 'range_km' order by i), '[]'::jsonb)
                                                       from jsonb_array_elements(d_cmp -> 'aircraft_types') with ordinality as x(e, i)));
      n_new := n_new + 1;
    end if;
  end if;
  assert d_before is null or d_cmp = d_before, 'all: the document isn''t exactly what rules_input() gave before this rehearsal''s changes (the new settings aside)';
  assert (d_flown #>> '{world,id}')::bigint = w, 'flown: the document isn''t the default world''s';

  -- 'flown': every route that isn't removed and has a rotation, and no other, each as 'all' has it
  select count(*) into n_routes from public.routes r
   where r.world_id = w and not r.removed and exists (select 1 from public.rotations ro where ro.route_id = r.id);
  select string_agg(x.id::text, ', ') into bad from (
    (select (e ->> 'id')::bigint as id from jsonb_array_elements(d_flown -> 'routes') e
     except select r.id from public.routes r
             where r.world_id = w and not r.removed and exists (select 1 from public.rotations ro where ro.route_id = r.id))
    union all
    (select r.id from public.routes r
      where r.world_id = w and not r.removed and exists (select 1 from public.rotations ro where ro.route_id = r.id)
     except select (e ->> 'id')::bigint from jsonb_array_elements(d_flown -> 'routes') e)) x;
  assert bad is null, 'flown: the routes aren''t exactly those with rotations; these differ: ' || bad;
  assert jsonb_array_length(d_flown -> 'routes') = n_routes, 'flown: a route is listed twice';
  assert not exists (select 1 from public.rotations ro join public.routes r on r.id = ro.route_id
                      where ro.world_id = w and not r.removed
                        and not exists (select 1 from jsonb_array_elements(d_flown -> 'routes') e where (e ->> 'id')::bigint = r.id)),
    'flown: a rotation''s route is missing';
  select string_agg(e ->> 'id', ', ') into bad from jsonb_array_elements(d_flown -> 'routes') e
   where not exists (select 1 from jsonb_array_elements(d_all -> 'routes') a where a = e);
  assert bad is null, 'flown: these routes don''t read as all has them: ' || bad;
  select count(distinct r.id) into n_removed from public.routes r
   where r.world_id = w and r.removed and exists (select 1 from public.rotations ro where ro.route_id = r.id);

  -- 'flown': exactly the airports a flown route, a leg, a base or an aircraft's base uses, each as 'all' has it
  create temporary table t_ri_codes on commit drop as
    select r.hub_code as code from public.routes r
     where r.world_id = w and not r.removed and exists (select 1 from public.rotations ro where ro.route_id = r.id)
    union select r.dest_code from public.routes r
     where r.world_id = w and not r.removed and exists (select 1 from public.rotations ro where ro.route_id = r.id)
    union select l.origin_code from public.flight_legs l where l.world_id = w
    union select l.dest_code from public.flight_legs l where l.world_id = w
    union select b.airport_code from public.airline_bases b where b.world_id = w
    union select a.base_code from public.aircraft a where a.world_id = w and a.base_code is not null;
  select count(*) into n_codes from t_ri_codes;
  select string_agg(x.code, ', ') into bad from (
    (select e ->> 'code' as code from jsonb_array_elements(d_flown -> 'airports') e except select c.code from t_ri_codes c)
    union all
    (select c.code from t_ri_codes c except select e ->> 'code' from jsonb_array_elements(d_flown -> 'airports') e)) x;
  assert bad is null, 'flown: the airports aren''t exactly those the flown routes, legs, bases and aircraft use; these differ: ' || bad;
  assert jsonb_array_length(d_flown -> 'airports') = n_codes, 'flown: an airport is listed twice';
  select string_agg(e ->> 'code', ', ') into bad from jsonb_array_elements(d_flown -> 'airports') e
   where not exists (select 1 from jsonb_array_elements(d_all -> 'airports') a where a = e);
  assert bad is null, 'flown: these airports don''t read as all has them: ' || bad;

  -- everything else is the same
  select string_agg(k, ', ') into bad from (select jsonb_object_keys(d_all) as k union select jsonb_object_keys(d_flown)) x
   where k not in ('routes', 'airports') and d_all -> k is distinct from d_flown -> k;
  assert bad is null, 'flown: these parts differ from all, which they shouldn''t: ' || bad;

  -- any other value is refused
  foreach v in array array['some', 'FLOWN', ''] loop
    begin perform public.rules_input(w, v); exception when invalid_parameter_value then refused := refused + 1; end;
  end loop;
  begin perform public.rules_input(w, null); exception when invalid_parameter_value then refused := refused + 1; end;
  assert refused = 4, format('%s of 4 bad p_routes values were refused', refused);

  raise notice 'p_routes: all is % (% KB, % routes, % airports); flown is % KB: the % routes with rotations and the % airports they, the legs, the bases and the aircraft use, the rest the same (% removed routes have rotations; like all, flown leaves removed routes out); other values refused',
    case when d_before is null then 'as the tables have it (the copy had no rules_input() before its changes)'
         when n_new > 0 then format('unchanged but for %s new part(s): settings, at the world and in each airline''s, and the service profiles', n_new) else 'unchanged' end,
    round(octet_length(d_all::text) / 1024.0), jsonb_array_length(d_all -> 'routes'), jsonb_array_length(d_all -> 'airports'),
    round(octet_length(d_flown::text) / 1024.0), n_routes, n_codes, n_removed;
end
$test$;

-- ---------------------------------------------------------------- 2. the document's counts equal the tables'
do $test$
declare
  w bigint := (select x.id from public.worlds x where x.is_default);
  d jsonb;
  n_air int; n_ap int;
begin
  assert w is not null, 'the copy has no default world';
  d := public.rules_input();
  insert into t_ri values ('world', to_jsonb(w)), ('doc', d);
  assert (d #>> '{world,id}')::bigint = w, 'the document isn''t the default world''s';
  assert public.rules_input(w) = d, 'rules_input(the default world''s id) differs from rules_input()';
  assert (select count(*) from jsonb_object_keys(d -> 'settings')) = (select count(*) from public.settings s where s.world_id = w and s.airline_id is null),
    'settings: the document''s count differs from the table''s';
  assert (select count(*) from jsonb_object_keys(d -> 'world_rules')) = (select count(*) from public.world_rules r where r.world_id = w),
    'world_rules: the document''s count differs from the table''s';
  assert jsonb_array_length(d -> 'aircraft_types') = (select count(*) from public.aircraft_types t where t.world_id = w), 'aircraft_types: counts differ';
  assert jsonb_array_length(d -> 'cabin_configs') = (select count(*) from public.cabin_configs c where c.world_id = w), 'cabin_configs: counts differ';
  assert jsonb_array_length(d -> 'airline_bases') = (select count(*) from public.airline_bases b where b.world_id = w), 'airline_bases: counts differ';
  assert jsonb_array_length(d -> 'aircraft') = (select count(*) from public.aircraft a where a.world_id = w), 'aircraft: counts differ';
  assert jsonb_array_length(d -> 'routes') = (select count(*) from public.routes r where r.world_id = w and not r.removed), 'routes (not removed): counts differ';
  assert jsonb_array_length(d -> 'rotations') = (select count(*) from public.rotations r where r.world_id = w), 'rotations: counts differ';
  assert jsonb_array_length(d -> 'flight_legs') = (select count(*) from public.flight_legs l where l.world_id = w), 'flight_legs: counts differ';
  select count(*) into n_ap from (
    select r.hub_code as c from public.routes r where r.world_id = w and not r.removed
    union select r.dest_code from public.routes r where r.world_id = w and not r.removed
    union select l.origin_code from public.flight_legs l where l.world_id = w
    union select l.dest_code from public.flight_legs l where l.world_id = w
    union select b.airport_code from public.airline_bases b where b.world_id = w
    union select a.base_code from public.aircraft a where a.world_id = w and a.base_code is not null) x;
  assert jsonb_array_length(d -> 'airports') = n_ap, format('airports: the document has %s, the routes, legs and bases use %s', jsonb_array_length(d -> 'airports'), n_ap);
  select count(*) into n_air from public.airlines al
   where al.world_id = w
     and (exists (select 1 from public.groups g where g.id = al.group_id and g.kind = 'ours')
          or exists (select 1 from public.airline_bases b where b.airline_id = al.id)
          or exists (select 1 from public.aircraft a where a.airline_id = al.id)
          or exists (select 1 from public.routes r where r.airline_id = al.id and not r.removed)
          or exists (select 1 from public.rotations r where r.airline_id = al.id)
          or exists (select 1 from public.flight_legs l where l.airline_id = al.id));
  assert jsonb_array_length(d -> 'airlines') = n_air, format('airlines: the document has %s, ours and the ones the planning rows name are %s', jsonb_array_length(d -> 'airlines'), n_air);
  assert not exists (select 1 from jsonb_array_elements(d -> 'flight_legs') e(l)
                      where not exists (select 1 from jsonb_array_elements(d -> 'airports') a where a ->> 'code' = e.l ->> 'origin_code')
                         or not exists (select 1 from jsonb_array_elements(d -> 'airports') a where a ->> 'code' = e.l ->> 'dest_code')),
    'a leg names an airport the document leaves out';
  raise notice 'counts equal the tables'': % settings, % world rules, % types, % airports, % airlines, % bases, % aircraft, % routes, % rotations, % legs',
    (select count(*) from jsonb_object_keys(d -> 'settings')), (select count(*) from jsonb_object_keys(d -> 'world_rules')),
    jsonb_array_length(d -> 'aircraft_types'), n_ap, n_air, jsonb_array_length(d -> 'airline_bases'), jsonb_array_length(d -> 'aircraft'),
    jsonb_array_length(d -> 'routes'), jsonb_array_length(d -> 'rotations'), jsonb_array_length(d -> 'flight_legs');
end
$test$;

-- ---------------------------------------------------------------- 3. one leg, one airport and one setting read back exactly
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_ri where k = 'world');
  d jsonb := (select v from t_ri where k = 'doc');
  l public.flight_legs; dl jsonb;
  v_code text; da jsonb; a public.airports; wa public.world_airports;
  s public.settings;
begin
  select * into l from public.flight_legs x where x.world_id = w order by x.id limit 1;
  if found then
    select e into dl from jsonb_array_elements(d -> 'flight_legs') e where (e ->> 'id')::bigint = l.id;
    assert dl is not null, format('leg %s isn''t in the document', l.id);
    assert (dl ->> 'airline_id')::bigint = l.airline_id and (dl ->> 'rotation_id')::bigint = l.rotation_id
       and (dl ->> 'leg_no')::smallint = l.leg_no and (dl ->> 'flight_no')::int is not distinct from l.flight_no
       and dl ->> 'origin_code' = l.origin_code and dl ->> 'dest_code' = l.dest_code
       and (dl ->> 'aircraft_id')::bigint is not distinct from l.aircraft_id
       and (select array_agg(x::smallint order by o) from jsonb_array_elements_text(dl -> 'days_utc') with ordinality as t(x, o)) = l.days_utc
       and (dl ->> 'dep_utc_min')::smallint is not distinct from l.dep_utc_min and (dl ->> 'block_min')::smallint is not distinct from l.block_min,
      format('leg %s doesn''t read back exactly', l.id);
  end if;
  -- an airport with the most the world says about it: a night ban if any has one, else a minimum connection time
  select x.airport_code into v_code from public.world_airports x
   where x.world_id = w and x.airport_code in (select e ->> 'code' from jsonb_array_elements(d -> 'airports') e)
   order by (x.night_ban_from is not null) desc, (x.mct_min is not null) desc, (x.utc_offset_override is not null) desc, x.airport_code limit 1;
  assert v_code is not null, 'no airport in the document has a world_airports row';
  select e into da from jsonb_array_elements(d -> 'airports') e where e ->> 'code' = v_code;
  select * into a from public.airports x where x.code = v_code;
  select * into wa from public.world_airports x where x.world_id = w and x.airport_code = v_code;
  assert da ->> 'city' is not distinct from a.city and da ->> 'country_code' is not distinct from a.country_code
     and (da ->> 'lat')::numeric is not distinct from a.lat and (da ->> 'lon')::numeric is not distinct from a.lon
     and (da ->> 'utc_offset')::numeric is not distinct from coalesce(wa.utc_offset_override, a.utc_offset)
     and (da ->> 'utc_offset_override')::numeric is not distinct from wa.utc_offset_override
     and (da ->> 'mct_min')::smallint is not distinct from wa.mct_min
     and da ->> 'night_ban_from' is not distinct from to_char(wa.night_ban_from, 'HH24:MI')
     and da ->> 'night_ban_to' is not distinct from to_char(wa.night_ban_to, 'HH24:MI'),
    format('airport %s doesn''t read back exactly', v_code);
  -- a setting: the connection wait if there is one, else the first
  select * into s from public.settings x where x.world_id = w and x.airline_id is null order by (x.key = 'connection_max_wait_h') desc, x.key limit 1;
  assert d -> 'settings' -> s.key = s.value, format('setting %s doesn''t read back exactly', s.key);
  raise notice 'leg %, airport % and setting % read back exactly', coalesce(l.id::text, '(no legs)'), v_code, s.key;
end
$test$;

-- ---------------------------------------------------------------- 4. an airline's override wins over the world value
do $test$
declare
  w bigint := (select (v #>> '{}')::bigint from t_ri where k = 'world');
  d jsonb; al1 bigint; al2 bigint; o record; n int := 0;
begin
  select (e ->> 'id')::bigint into al1 from jsonb_array_elements((select v from t_ri where k = 'doc') -> 'airlines') e order by (e ->> 'id')::bigint limit 1;
  select (e ->> 'id')::bigint into al2 from jsonb_array_elements((select v from t_ri where k = 'doc') -> 'airlines') e
   where (e ->> 'id')::bigint <> al1 order by (e ->> 'id')::bigint limit 1;
  assert al1 is not null, 'the document has no airlines';
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'rules_input test', true);
  insert into public.settings (world_id, airline_id, key, value, description)
  values (w, null, 'rules_input_test_key', '1', 'rules_input test: the world''s value'),
         (w, al1, 'rules_input_test_key', '2', 'rules_input test: one airline''s override');
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
  d := public.rules_input();
  insert into t_ri values ('doc2', d);
  assert d #> '{settings,rules_input_test_key}' = '1'::jsonb, 'the world''s value isn''t the document''s setting';
  assert (select e #> '{settings,rules_input_test_key}' from jsonb_array_elements(d -> 'airlines') e where (e ->> 'id')::bigint = al1) = '2'::jsonb,
    'the airline''s override doesn''t win in its own settings';
  if al2 is not null then
    assert (select e #> '{settings,rules_input_test_key}' from jsonb_array_elements(d -> 'airlines') e where (e ->> 'id')::bigint = al2) = '1'::jsonb,
      'another airline doesn''t keep the world''s value';
  end if;
  -- the overrides the copy already has (Ryanair's fare and hubs-first exemption, say) read back the same way
  for o in select s.airline_id, s.key, s.value from public.settings s where s.world_id = w and s.airline_id is not null and s.key <> 'rules_input_test_key' loop
    assert (select e -> 'settings' -> o.key from jsonb_array_elements(d -> 'airlines') e where (e ->> 'id')::bigint = o.airline_id) = o.value,
      format('airline %s''s override of %s doesn''t win in its settings', o.airline_id, o.key);
    n := n + 1;
  end loop;
  raise notice 'an airline''s override wins in its own settings (and % override(s) already in the copy read back the same); the world''s value stays for the document and the others', n;
end
$test$;

-- ---------------------------------------------------------------- 5. who is refused, and what staff get
set local role anon;
do $test$
declare refused boolean := false;
begin
  begin perform public.rules_input(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'signed out, rules_input() could be called';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f1", "email": "rules-input-other@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
declare refused boolean := false;
begin
  begin perform public.rules_input(); exception when insufficient_privilege then refused := true; end;
  assert refused, 'an account that isn''t staff could read rules_input()';
end
$test$;
reset role;

do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000f2", "email": "rules-input-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
do $test$
begin
  assert public.rules_input() = (select v from t_ri where k = 'doc2'), 'staff don''t get what postgres gets';
end
$test$;
reset role;
do $test$ begin raise notice 'signed out and an account that isn''t staff are refused; staff get what postgres gets'; end $test$;

-- ---------------------------------------------------------------- 6. export_for_report(secret, 'rules')
insert into t_ri values ('secret', to_jsonb('rules-input-test-' || gen_random_uuid()::text));
insert into public.ingest_secret (secret) select v #>> '{}' from t_ri where k = 'secret';
set local role anon;
do $test$
declare s text := (select v #>> '{}' from t_ri where k = 'secret'); w text := (select v #>> '{}' from t_ri where k = 'world');
  want jsonb := (select v from t_ri where k = 'doc2'); refused boolean := false;
begin
  assert public.export_for_report(s, 'rules') = want, 'export_for_report(secret, rules) differs from rules_input()';
  assert public.export_for_report(s, 'rules', w) = want, 'export_for_report(secret, rules, the world''s id) differs from rules_input()';
  assert public.export_for_report(s, 'rules', '') = want, 'export_for_report(secret, rules, empty) differs from rules_input()';
  begin perform public.export_for_report(s || '-wrong', 'rules'); exception when others then refused := sqlerrm = 'not allowed'; end;
  assert refused, 'export_for_report(rules) with a wrong secret wasn''t refused';
end
$test$;
reset role;
do $test$ begin raise notice 'export_for_report(secret, rules), signed out as the scripts call it, gives rules_input()''s document; a wrong secret is refused'; end $test$;

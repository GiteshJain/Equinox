-- The new planner's Home (decision #18, build pull request 5). Spec: docs/specs/2026-10-13-home.md §1 and §2; design
-- docs/design/2026-10-12-planner-app.md §5 ("Rules at start", the 12 Oct note), §6 and §14 choice 4.
--
-- Changes five functions, adds one with its builder and two settings; takes nothing away from anyone:
--   public.rules_input(p_world_id bigint default null, p_routes text default 'all') and its builder
--     private.rules_input_doc(p_world_id bigint, p_routes text default 'all'): with p_routes 'flown' the document holds
--     only the routes that have rotations, and only the airports those routes, the legs, the bases and the aircraft
--     use: the new planner's lighter start (design §5: about 1 MB on live, because it carried all 4,522 researched
--     routes and their 1,219 airports). Everything else in the document is as with 'all'. 'all', the default, is the
--     document exactly as before, so rules_input(), rules_input(world) and export_for_report('rules') answer as they
--     did. Any other value is refused. A function's arguments can't be added in place, so the one-argument versions
--     are dropped and made again with the new one, in this one transaction; the grants are set again as they were.
--   public.planner_save(): an insert may name the row it makes ("as": a name), and a later change in the same call
--     may take a column's value from that row's key ("from": {column: name}). So a new to-do and its steps are one
--     action, all or nothing (and, for later screens, a plan card and its legs, a rotation and its two legs: design §6
--     and §14 choice 4). Without "as" and "from" it answers and writes exactly as before.
-- And, from the Building chat's review of the pull request (Home as the old Home shows it, each figure from one home):
--   settings airport_cap_warning_pct (80) and aircraft_check_after_days (7), two numbers the old planner kept in its
--     code, for every world (the library reads them through rules_input());
--   public.route_loads(p_world_id, p_as_of) and its builder private.fig_route_loads(): each route's economy loads over
--     the last 7 days (the old planner's loadStats), for Home's map with one airline picked;
--   public.airline_cards(): gains the group's average economy load over 7 days (load_7_days, with how many flights it
--     covers and whether from captures or reports), the old Home's figure, worked out here rather than on the screen;
--   public.growth_signals(): gains profit_captured, whether any profit was captured in the old Home's 8 days, so Home
--     falls back on the load patterns as the old Home did. Both answer everything else as before.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261013200000_home', true);

-- ============================================================ 1. rules_input(): 'all' or 'flown'
drop function if exists public.rules_input(bigint);
drop function if exists private.rules_input_doc(bigint);

create function private.rules_input_doc(p_world_id bigint, p_routes text default 'all')
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
                   from rts r
                   left join public.markets m on m.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end),
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

create function public.rules_input(p_world_id bigint default null, p_routes text default 'all')
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
  return private.rules_input_doc(p_world_id, p_routes);
end
$function$;

revoke all on function private.rules_input_doc(bigint, text) from public, anon, authenticated, service_role;
revoke all on function public.rules_input(bigint, text) from public, anon, authenticated, service_role;
grant execute on function public.rules_input(bigint, text) to authenticated;

-- ============================================================ 2. planner_save(): a new row's key for a later change
-- As 20261012120000_planner_save.sql left it, with "as" and "from".
create or replace function public.planner_save(p_changes jsonb, p_client text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- the 32 planner tables, each with the change-log trigger (migration 20261009210000_planner_tables.sql, §4)
  v_tables constant text[] := array[
    'worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types',
    'countries', 'airports', 'world_airports',
    'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps',
    'markets', 'service_profiles', 'routes', 'rotations', 'flight_legs',
    'plan_cards', 'plan_card_legs',
    'todos', 'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements', 'monthly_checks',
    'dismissals', 'cash_entries', 'load_entries', 'load_days',
    'settings', 'world_rules'];
  v_actor text := current_setting('equinox.actor', true);
  v_detail text := current_setting('equinox.actor_detail', true);
  w bigint;
  c jsonb;
  i bigint;
  v_list jsonb := '[]'::jsonb;
  v_table text;
  v_op text;
  v_key jsonb;
  v_vals jsonb;
  v_pk text[];
  v_cols text[];
  v_bad text;
  v_base timestamptz;
  v_where text;
  v_names text;
  v_from text;
  v_row jsonb;
  v_at timestamptz;
  v_clashes jsonb := '[]'::jsonb;
  v_rows jsonb := '[]'::jsonb;
  -- "as" and "from": the names given to inserts so far (name -> its primary key column), and, while writing, the key
  -- each named insert made (name -> value)
  v_as text;
  v_take jsonb;
  v_named jsonb := '{}'::jsonb;
  v_made jsonb := '{}'::jsonb;
  f record;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  if jsonb_typeof(p_changes) is distinct from 'array' then
    raise exception 'planner_save: the changes must be a JSON list' using errcode = '22023';
  end if;

  -- 1. every change is checked before any row is read or written
  for c, i in select e.value, e.ordinality from jsonb_array_elements(p_changes) with ordinality as e loop
    if jsonb_typeof(c) is distinct from 'object' then
      raise exception 'planner_save: change % isn''t an object', i using errcode = '22023';
    end if;
    v_table := c ->> 'table';
    v_op := c ->> 'op';
    if v_table is null or not (v_table = any (v_tables)) then
      raise exception 'planner_save: change %: % isn''t one of the planner''s tables (only the 32 the change log covers)',
        i, coalesce(v_table, 'no table') using errcode = '22023';
    end if;
    if v_op is null or v_op not in ('insert', 'update', 'delete') then
      raise exception 'planner_save: change %: op must be insert, update or delete, not %', i, coalesce(v_op, 'nothing')
        using errcode = '22023';
    end if;
    v_key := c -> 'key';
    v_vals := c -> 'values';
    v_take := c -> 'from';
    if v_key = 'null'::jsonb then v_key := null; end if;
    if v_vals = 'null'::jsonb then v_vals := null; end if;
    if v_take = 'null'::jsonb then v_take := null; end if;
    if v_key is not null and jsonb_typeof(v_key) <> 'object' then
      raise exception 'planner_save: change %: key must be an object, e.g. {"id": 812}', i using errcode = '22023';
    end if;
    if v_vals is not null and jsonb_typeof(v_vals) <> 'object' then
      raise exception 'planner_save: change %: values must be an object of columns', i using errcode = '22023';
    end if;
    select array_agg(a.attname::text order by k.n) into v_pk
      from pg_catalog.pg_index x
      cross join lateral unnest(x.indkey::smallint[]) with ordinality as k(attnum, n)
      join pg_catalog.pg_attribute a on a.attrelid = x.indrelid and a.attnum = k.attnum
     where x.indrelid = format('public.%I', v_table)::regclass and x.indisprimary;
    select array_agg(a.attname::text) into v_cols
      from pg_catalog.pg_attribute a
     where a.attrelid = format('public.%I', v_table)::regclass and a.attnum > 0 and not a.attisdropped;

    -- "from": columns whose value is the key of a row an earlier insert in this call makes (it names that row with "as")
    if v_take is not null then
      if jsonb_typeof(v_take) <> 'object' or v_take = '{}'::jsonb then
        raise exception 'planner_save: change %: from must be an object of columns, e.g. {"todo_id": "new-todo"}', i using errcode = '22023';
      end if;
      if v_op = 'delete' then
        raise exception 'planner_save: change %: a delete takes no from', i using errcode = '22023';
      end if;
      for f in select e.key, e.value from jsonb_each(v_take) as e loop
        if jsonb_typeof(f.value) <> 'string' or not (v_named ? (f.value #>> '{}')) then
          raise exception 'planner_save: change %: from names %, which no earlier insert in this call is called (as)', i, f.value
            using errcode = '22023';
        end if;
        if not (f.key = any (v_cols)) then
          raise exception 'planner_save: change %: % has no column %', i, v_table, f.key using errcode = '22023';
        end if;
        if f.key = 'updated_at' or coalesce(v_vals, '{}'::jsonb) ? f.key then
          raise exception 'planner_save: change %: % is given both in values and in from', i, f.key using errcode = '22023';
        end if;
      end loop;
    end if;

    if v_op in ('update', 'delete') then
      if v_key is null
         or (select array_agg(k order by k) from jsonb_object_keys(v_key) as k) is distinct from
            (select array_agg(p order by p) from unnest(v_pk) as p) then
        raise exception 'planner_save: change %: the key must name exactly the primary key of % (%)',
          i, v_table, array_to_string(v_pk, ', ') using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each(v_key) as e where e.value = 'null'::jsonb) then
        raise exception 'planner_save: change %: a key value is empty', i using errcode = '22023';
      end if;
      if c ->> 'base' is null then
        raise exception 'planner_save: change %: an % needs base, the row''s updated_at as it was loaded', i, v_op
          using errcode = '22023';
      end if;
      begin
        v_base := (c ->> 'base')::timestamptz;
      exception when others then
        raise exception 'planner_save: change %: base isn''t a time: %', i, c ->> 'base' using errcode = '22023';
      end;
    end if;
    if v_op = 'insert' then
      -- a key given with an insert (a table keyed by its own columns, like dismissals) is part of its values
      if v_key is not null then
        if exists (select 1 from jsonb_each(v_key) as k where coalesce(v_vals, '{}'::jsonb) ? k.key and v_vals -> k.key <> k.value) then
          raise exception 'planner_save: change %: the key and the values disagree', i using errcode = '22023';
        end if;
        v_vals := coalesce(v_vals, '{}'::jsonb) || v_key;
      end if;
      if coalesce(v_vals, '{}'::jsonb) = '{}'::jsonb then
        raise exception 'planner_save: change %: an insert needs values', i using errcode = '22023';
      end if;
    elsif v_op = 'update' then
      if coalesce(v_vals, '{}'::jsonb) = '{}'::jsonb and v_take is null then
        raise exception 'planner_save: change %: an update needs values', i using errcode = '22023';
      end if;
    elsif coalesce(v_vals, '{}'::jsonb) <> '{}'::jsonb then
      raise exception 'planner_save: change %: a delete takes no values', i using errcode = '22023';
    end if;
    select string_agg(k, ', ' order by k) into v_bad
      from jsonb_object_keys(coalesce(v_vals, '{}'::jsonb)) as k
     where not (k = any (v_cols));
    if v_bad is not null then
      raise exception 'planner_save: change %: % has no column %', i, v_table, v_bad using errcode = '22023';
    end if;
    if coalesce(v_vals, '{}'::jsonb) ? 'updated_at' then
      raise exception 'planner_save: change %: updated_at is set by the database', i using errcode = '22023';
    end if;

    -- "as": an insert names the row it makes, for a later change's "from"; its table needs a one-column key
    if c ? 'as' and c -> 'as' <> 'null'::jsonb then
      v_as := c ->> 'as';
      if jsonb_typeof(c -> 'as') <> 'string' or v_as = '' then
        raise exception 'planner_save: change %: as must be a name, e.g. "new-todo"', i using errcode = '22023';
      end if;
      if v_op <> 'insert' then
        raise exception 'planner_save: change %: only an insert can be named (as)', i using errcode = '22023';
      end if;
      if v_named ? v_as then
        raise exception 'planner_save: change %: the name % is used twice', i, v_as using errcode = '22023';
      end if;
      if coalesce(array_length(v_pk, 1), 0) <> 1 then
        raise exception 'planner_save: change %: % is keyed by more than one column, so no other change can take its key', i, v_table
          using errcode = '22023';
      end if;
      v_named := v_named || jsonb_build_object(v_as, v_pk[1]);
    else
      v_as := null;
    end if;
    v_list := v_list || jsonb_build_array(jsonb_build_object('n', i, 'table', v_table, 'op', v_op, 'key', v_key,
                                                             'values', v_vals, 'base', c ->> 'base', 'pk', to_jsonb(v_pk),
                                                             'as', v_as, 'from', v_take));
  end loop;

  -- 2. the rows to change or remove, locked in one order (table, then key) so two saves can't deadlock, each checked
  --    against its base. Saves of the old planner and other chats' items take the same lock, so they queue too.
  select x.id into w from public.worlds x where x.is_default;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  for c in select e.value from jsonb_array_elements(v_list) as e
            where e.value ->> 'op' <> 'insert' order by e.value ->> 'table', (e.value -> 'key')::text loop
    select string_agg(format('t.%1$I = k.%1$I', p), ' and ') into v_where from jsonb_array_elements_text(c -> 'pk') as p;
    execute format('select to_jsonb(t), t.updated_at from public.%1$I t, pg_catalog.jsonb_populate_record(null::public.%1$I, $1) k '
                   'where %2$s for update of t', c ->> 'table', v_where)
       into v_row, v_at using c -> 'key';
    if v_row is null or v_at is distinct from (c ->> 'base')::timestamptz then
      v_clashes := v_clashes || jsonb_build_array(jsonb_build_object('table', c ->> 'table', 'key', c -> 'key', 'current', v_row));
    end if;
  end loop;
  if jsonb_array_length(v_clashes) > 0 then
    return jsonb_build_object('ok', false, 'clashes', v_clashes);
  end if;

  -- 3. the writes, in the order given, as actor planner with the tab's ID
  perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', coalesce(p_client, ''), true);
  for c in select e.value from jsonb_array_elements(v_list) as e order by (e.value ->> 'n')::bigint loop
    v_table := c ->> 'table';
    -- the values, with each "from" column given the key its named insert made
    v_vals := coalesce(c -> 'values', '{}'::jsonb);
    if jsonb_typeof(c -> 'from') = 'object' then
      v_vals := v_vals || (select jsonb_object_agg(e.key, v_made -> (e.value #>> '{}')) from jsonb_each(c -> 'from') as e);
    end if;
    select string_agg(format('t.%1$I = k.%1$I', p), ' and ') into v_where from jsonb_array_elements_text(c -> 'pk') as p;
    if c ->> 'op' = 'insert' then
      select string_agg(format('%I', k), ', ' order by k), string_agg(format('r.%I', k), ', ' order by k)
        into v_names, v_from from jsonb_object_keys(v_vals) as k;
      execute format('insert into public.%1$I as t (%2$s) select %3$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r '
                     'returning to_jsonb(t), t.updated_at', v_table, v_names, v_from)
         into v_row, v_at using v_vals;
    elsif c ->> 'op' = 'update' then
      select string_agg(format('%1$I = r.%1$I', k), ', ' order by k) into v_names from jsonb_object_keys(v_vals) as k;
      execute format('update public.%1$I t set %2$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r, '
                     'pg_catalog.jsonb_populate_record(null::public.%1$I, $2) k where %3$s returning to_jsonb(t), t.updated_at',
                     v_table, v_names, v_where)
         into v_row, v_at using v_vals, c -> 'key';
    else
      execute format('delete from public.%1$I t using pg_catalog.jsonb_populate_record(null::public.%1$I, $1) k where %2$s '
                     'returning to_jsonb(t)', v_table, v_where)
         into v_row using c -> 'key';
      v_at := null;
    end if;
    if v_row is null then
      raise exception 'planner_save: change %: the row wasn''t there to %', c ->> 'n', c ->> 'op';
    end if;
    if c ->> 'as' is not null then
      v_made := v_made || jsonb_build_object(c ->> 'as', v_row -> (c -> 'pk' ->> 0));
    end if;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'table', v_table, 'op', c ->> 'op',
      'key', (select jsonb_object_agg(p, v_row -> p) from jsonb_array_elements_text(c -> 'pk') as p),
      'updated_at', to_jsonb(v_at)));
  end loop;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return jsonb_build_object('ok', true, 'rows', v_rows);
end
$function$;

-- ============================================================ 3. Home's figures (the Building chat's review of pull request 5)
-- Two numbers the old planner kept in its code get a home of their own (decision #19): Home's airport-cap warning (the
-- old planner's 4,000 of the 5,000 cap) and the one-week check's week (its tailChecks()). The planning library reads
-- both through rules_input().
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, x.unit, x.description, date '2026-10-13', x.reason
  from public.worlds w
 cross join (values
   ('airport_cap_warning_pct', '80'::jsonb, '% of the cap',
    'Home warns about an airport''s departures a week from this share of the game''s cap (world_rules.departures_per_airport_week), and marks it bad at the cap',
    'The old planner''s 4,000 of the 5,000 cap, given a home of its own (#19)'),
   ('aircraft_check_after_days', '7'::jsonb, 'days',
    'An aircraft''s one-week check falls due this many days after its latest launch or schedule change (manual §1; the old planner''s tailChecks)',
    'The old planner''s week, given a home of its own (#19)')) as x(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- the loads per route over the last 7 days: Home's map, coloured by load with one airline picked
-- loadStats(): each route's economy loads over the 7 days to today (p_as_of's UTC date and the 6 before): every flight
-- each day's load report covers (done days only; on a captured day only the flights the capture has a load for; none
-- before its rotation's launch), a flight without a load counting as 97.5% (lfVal); departures, their sum and average,
-- how many at 95% or more (or not reported), under 95, under 85 and under 70 (lfBucket), and the days seen
create or replace function private.fig_route_loads(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  with d as (select (p_as_of at time zone 'UTC')::date as d0),
  ld as (select x.* from d cross join lateral private.fig_load_days(p_world_id, p_as_of, d.d0 - 6, d.d0) x where x.done),
  lv as (select x.* from d cross join lateral private.fig_load_values(p_world_id, p_as_of, d.d0 - 6, d.d0) x where x.v is not null),
  fl as (select x.day, x.airline_id, x.flight_no, x.route_id, lv.v
           from d cross join lateral private.fig_flights_on(p_world_id, d.d0 - 6, d.d0) x
           join ld on ld.day = x.day
           left join lv on lv.day = x.day and lv.airline_id = x.airline_id and lv.flight_no = x.flight_no
          where not (x.launched_on is not null and x.day < x.launched_on)
            and not (ld.captured and lv.v is null)),
  r as (select fl.route_id, fl.airline_id, count(*)::int as n,
               sum(case when coalesce(fl.v, 0) = 0 then 97.5 else fl.v end) as s,
               count(*) filter (where coalesce(fl.v, 0) = 0 or fl.v >= 95)::int as full_n,
               count(*) filter (where fl.v > 0 and fl.v >= 85 and fl.v < 95)::int as b95,
               count(*) filter (where fl.v > 0 and fl.v >= 70 and fl.v < 85)::int as b85,
               count(*) filter (where fl.v > 0 and fl.v < 70)::int as b70,
               count(distinct fl.day)::int as days
          from fl group by fl.route_id, fl.airline_id)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'from', (select d0 - 6 from d), 'to', (select d0 from d),
    'routes', coalesce((select jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'route_id', r.route_id, 'hub', ro.hub_code, 'dest', ro.dest_code,
        'departures', r.n, 'sum', r.s, 'average', r.s / r.n, 'full', r.full_n, 'under_95', r.b95, 'under_85', r.b85,
        'under_70', r.b70, 'days', r.days)
        order by a.position nulls last, r.airline_id, ro.hub_code, ro.dest_code)
      from r join public.routes ro on ro.id = r.route_id join public.airlines a on a.id = r.airline_id), '[]'::jsonb))
$function$;

create or replace function public.route_loads(p_world_id bigint default null, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_route_loads(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

revoke all on function private.fig_route_loads(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.route_loads(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.route_loads(bigint, timestamptz) to authenticated;

-- airline_cards(): the group's average economy load, worked out here rather than averaged on the screen
create or replace function private.fig_airline_cards(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_today date := (p_as_of at time zone 'UTC')::date; v_from date; v_ops jsonb;
        v_leases jsonb := private.fig_lease_map(p_world_id, p_as_of); v_load numeric; v_load_n int; v_load_from text;
begin
  -- the group's average economy load, the old Home's key figure (avgLF): every flight the loads pages captured by
  -- p_as_of departing from 7 days before today on (CAP.loads: one per airline, date and flight number, the latest row),
  -- averaged as they are, one flight one vote; with none captured, every flight the last 7 days' load reports cover
  -- (loadStats, as route_loads() counts them: a flight without a load as 97.5%)
  select avg(x.eco_pct), count(*)::int into v_load, v_load_n
    from (select distinct on (f.airline_id, f.game_date, f.flight_no) f.eco_pct
            from public.game_flights f join public.airlines a on a.id = f.airline_id
           where a.world_id = p_world_id and f.flight_no is not null and f.game_date >= v_today - 7 and f.loads_captured_at <= p_as_of
           order by f.airline_id, f.game_date, f.flight_no, f.id desc) x
   where x.eco_pct is not null;
  if v_load_n > 0 then
    v_load_from := 'captures';
  else
    select sum((r ->> 'sum')::numeric) / nullif(sum((r ->> 'departures')::int), 0), coalesce(sum((r ->> 'departures')::int), 0)::int
      into v_load, v_load_n
      from jsonb_array_elements(private.fig_route_loads(p_world_id, p_as_of) -> 'routes') r;
    v_load_from := case when v_load_n > 0 then 'reports' end;
  end if;
  -- dayOps for every airline at once, from the first reported cash date (or a week back) to today
  select least(coalesce(min(c.day), v_today), v_today - 7) into v_from
    from private.fig_airlines(p_world_id) al cross join lateral private.fig_cash_days(al.airline_id, p_as_of) c;
  select coalesce(jsonb_object_agg(x.airline_id::text, x.days), '{}'::jsonb) into v_ops
    from (select o.airline_id, jsonb_object_agg(o.day::text, jsonb_build_object('flights', o.flights, 'aircraft', o.aircraft, 'load', o.load)) as days
            from private.fig_day_ops(p_world_id, p_as_of, v_from, v_today) o group by o.airline_id) x;
  return (
    -- materialized: each airline's card, forecast and row worked out once (folded in, each use would work them out again)
    with c as materialized (
      select al.*, private.fig_fin_stats(al.airline_id, p_as_of, v_ops) as card,
             case when al.home_code is not null then private.fig_cash_forecast(al.airline_id, '[]'::jsonb, p_as_of, v_leases) end as fc,
             case when al.home_code is not null then private.fig_group_today(al.airline_id, p_as_of) end as today
        from private.fig_airlines(p_world_id) al)
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of),
      -- the group's average economy load over 7 days, how many flights it covers, and from captures or from reports
      'load_7_days', v_load, 'load_7_days_flights', v_load_n, 'load_7_days_from', v_load_from,
      'airlines', coalesce(jsonb_agg((c.card - 'days') || jsonb_build_object(
          'code', c.iata_code, 'name', c.name,
          -- fcNext(): needs a capture, needs a bank statement capture, can order now, safe from a day, or not within 14 days
          'next_order', case when c.fc is null or c.fc ->> 'status' = 'no capture' then jsonb_build_object('when', 'needs', 'missing', 'a capture')
                             when c.fc ->> 'status' <> 'ok' then jsonb_build_object('when', 'needs', 'missing', c.fc ->> 'missing')
                             else c.fc -> 'next_order' end,
          'can_order_now', coalesce(c.fc -> 'can_order_now', '[]'::jsonb))
          order by c.ord), '[]'::jsonb),
      -- the group today: shown once any airline has flight profit
      'group_today', coalesce(jsonb_agg(c.today || jsonb_build_object('code', c.iata_code, 'name', c.name) order by c.ord)
                                filter (where c.today is not null), '[]'::jsonb),
      'group_today_shown', coalesce(bool_or(c.today ->> 'flight_profit_day' is not null), false))
      from c);
end
$function$;

-- growth_signals(): whether any profit was captured, so Home knows when to fall back on the load patterns
create or replace function private.fig_growth_signals(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_days int := private.fig_num(p_world_id, null, 'growth_window_days')::int; v_docs jsonb;
        v_today date := (p_as_of at time zone 'UTC')::date; v_profit boolean;
begin
  -- each airline's route and aircraft profit over the growth window, for those with flights captured
  select coalesce(jsonb_agg(jsonb_build_object('airline_id', al.airline_id, 'ord', al.ord, 'doc', x.doc) order by al.ord), '[]'::jsonb) into v_docs
    from private.fig_airlines(p_world_id) al
    cross join lateral (select private.fig_route_profit(al.airline_id, v_days, p_as_of) as doc offset 0) x   -- once each
   where al.home_code is not null and (x.doc ->> 'flights')::int > 0;
  -- any profit captured: a bank-statement line posted since midnight UTC 8 days ago (the old Home's CAP.pnl,
  -- game_flight_pnl since utcDay(-8)); with none, Home lists the routes the load patterns say to reduce instead
  v_profit := exists (select 1 from public.game_flights f join public.airlines a on a.id = f.airline_id
                       where a.world_id = p_world_id and f.posted_at >= (v_today - 8)::timestamp at time zone 'UTC'
                         and coalesce(f.money_captured_at, f.posted_at) <= p_as_of)
           or exists (select 1 from public.game_payments p join public.airlines a on a.id = p.airline_id
                       where a.world_id = p_world_id and p.paid_at >= (v_today - 8)::timestamp at time zone 'UTC' and p.created_at <= p_as_of
                         and coalesce(p.statement_blk::int, 1) > 0 and p.kind = 'other');
  return (
    with r as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
                 from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'routes') with ordinality as e(x, i)),
    t as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
            from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'aircraft') with ordinality as e(x, i))
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'days', v_days, 'profit_captured', v_profit,
      'ready_for_another_flight', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                                     order by (r.x ->> 'profit_week')::numeric desc, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' = 'add'),
      'raise_fares', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                        order by (r.x ->> 'flights')::int desc, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' = 'raise'),
      'fix_or_reduce', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                          order by (r.x ->> 'profit_per_flight')::numeric, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' in ('losing', 'fix')),
      'aircraft_losing_after_lease', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', t.airline_id) || t.x
                                        order by (t.x ->> 'net_day')::numeric, t.ord, t.i), '[]'::jsonb)
                                        from t where (t.x ->> 'net_day')::numeric < 0),
      'load_patterns', private.fig_patterns(p_world_id, p_as_of)));
end
$function$;

-- ============================================================ 4. descriptions (decision #10)
comment on function private.rules_input_doc(bigint, text) is 'The planning library''s input for a world (decision #19, design §7), with no check of its own: what rules_input() gives staff and export_for_report(''rules'') gives the scripts (always ''all''). See rules_input(). p_world_id: the world, or null for the default world; p_routes: all (every route that isn''t removed) or flown (only routes with rotations, and only the airports they, the legs, the bases and the aircraft use).';
comment on function public.rules_input(bigint, text) is 'Everything the planning library (lib/rules/, decision #19, design §7) needs, in one JSON document for the world (the default world when null): settings (the world''s values) and world_rules, as key → value; aircraft_types (cruise, turn, maintenance per cycle and hour, ground keep, seats); cabin_configs; every airport any route, leg or base uses (position, UTC offset with the world''s correction applied, minimum connection time, night ban as local HH:MM); airlines (ours and any the planning rows name), each with its settings as they apply to it (its own overrides in place of the world''s values); airline_bases (role, bank times as HH:MM, flight-number block, last number used); aircraft; routes that aren''t removed (distance and market with any override applied); rotations; flight_legs (UTC weekdays, departure minute and block time), by rotation and leg. p_routes: all (the default) or flown, the new planner''s lighter start (#18, design §5): only the routes that have rotations, and only the airports they, the legs, the bases and the aircraft use; the rest of the document is the same. The new planner (flown), the scripts (export_for_report(''rules''), all) and Claude''s command (node lib/rules/dist/cli.js) build the library''s Rules object from it. Staff only; runs as owner and checks the caller itself.';
comment on function private.fig_route_loads(bigint, timestamptz) is 'The captured figures (#19): the old planner''s loadStats() for each route over the last 7 days, with no check of its own. See route_loads().';
comment on function public.route_loads(bigint, timestamptz) is 'Each route''s economy loads over the last 7 days for our airlines in a world (the default world when null; decision #19, design §9: Home''s map and Routes'' loads per route; the old planner''s loadStats): every flight each day''s load report covers on the 7 days to p_as_of''s UTC date (from and to), done days only, on a captured day only the flights the capture has a load for, none before its rotation''s launch, a flight without a load counting as 97.5%: departures, their sum and average, how many at 95% or more (or not reported), under 95, under 85 and under 70, and the days seen, by airline position, hub and destination. Staff only; runs as owner and checks the caller itself.';
comment on function public.airline_cards(bigint, timestamptz) is 'Review''s card for each of our active airlines in a world (the default world when null), in display order (decision #19, design §8; the old planner''s finStats, renderFinance and fcNext): profit a day over the last 7 days of reported cash (an early read over fewer, early true), per aircraft, return on fleet a week, an aircraft pays back in and funds a new aircraft every (days), fleet, on order, flights a day and how many more than a week ago, average load over 7 days, next_order and can_order_now (cash_forecast()); and group_today (groupOverviewHtml): per airline cash, flight profit a day, this week''s leases and week-end closing per day, net, and aircraft arrived but not yet flying with their leases a day (group_today_shown once any airline has flight profit). No group totals (manual §1). Money in millions of AS$. And the group''s average economy load over 7 days, the old Home''s key figure (avgLF): load_7_days, the average of every flight the loads pages captured departing from 7 days before p_as_of''s UTC date on (one per airline, date and flight number), with load_7_days_flights and load_7_days_from captures; with none captured, every flight the last 7 days'' load reports cover (route_loads()), from reports; with neither, null. Staff only; runs as owner and checks the caller itself.';
comment on function public.growth_signals(bigint, timestamptz) is 'The Check screen''s growth lists across our airlines in a world (the default world when null; decision #19, design §8; the old planner''s capSignalsHtml and patterns): from route_profit() and aircraft_profit() over growth_window_days, ready for another flight (mark add, by profit a week), raise fares (by flights), fix or reduce (losing or fix, by profit a flight) and aircraft losing money after their lease (by net); and the load patterns: each route''s departures over the load window (load_window_days, ending two days ahead, leaving out each rotation''s first load_leeway_days) by load band, marked cut, watch, add or hold from the pattern_* settings. profit_captured: whether any bank-statement line was posted since midnight UTC 8 days before p_as_of (the old Home lists the routes the load patterns mark cut when none was). Staff only; runs as owner and checks the caller itself.';
comment on function public.planner_save(jsonb, text) is 'The new planner''s one way to write (decision #18, design §6): one call per action, with every row it changes, as a list of {table, op (insert, update or delete), key (the primary key, e.g. {"id": 812}), base (the row''s updated_at as loaded; needed for an update or delete), values (the columns to set)}. An insert may name the row it makes (as: a name), and a later change in the same call may take a column''s value from that row''s key (from: {column: name}), so a to-do and its steps are one action. All or nothing: if any row to update or delete was changed or removed since it was loaded, nothing is written and the answer is {ok: false, clashes: [{table, key, current (the row now, or null if it''s gone)}]}; otherwise {ok: true, rows: [{table, op, key, updated_at}]}, inserts included. Only the 32 planner tables the change log covers, and only their own columns; their checks still apply. Written as actor planner with p_client (the tab''s ID) as the detail. Staff only; runs as owner and checks the caller itself.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

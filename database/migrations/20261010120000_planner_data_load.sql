-- The planner's data in the tables, and the adapter's read side (decision #13, build pull request 4).
-- Design: docs/design/2026-10-09-data-model.md (§2, §3.2 to §3.7, §4, §8, §9 step 3, §10 row 4). Spec:
-- docs/specs/2026-10-10-data-load.md.
--
-- Adds, and changes nothing that exists (no removals, so there is no file for Gitesh to run):
--   1. helpers in private: reading numbers, dates, times and weekdays from the old JSON, and comparing two planner
--      documents with only the differences design §9 allows (private.planner_json_differences);
--   2. the view capture_cash: cash and the next 7 days' payments per airline and capture date, from the capture, worked
--      out exactly as the planner does today (applyCaptureCash);
--   3. the getters planner_state_get(), planner_state_version() and planner_loads_get(): today's planner_state JSON and
--      planner_loads documents, built from the tables. Staff only (and postgres); nothing calls them yet;
--   4. the loader private.load_planner(world_id): fills the tables from planner_state, planner_loads, planner_data,
--      site_content.mct, planner_meta.growthRules and the planner's code constants. It can be run again: a second
--      run brings the tables in line with today's planner_state without changing ids that already exist;
--   5. private.fill_flight_links(world_id): the route and aircraft of each captured flight;
--   6. the load itself, then the capture's matching (private.capture_refresh) now that airports have time zones, and
--      the flights' routes and aircraft. Logged as migration, the change log off (design §6, §9);
--   7. grants and descriptions.
-- Apply it when no capture is running.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261010120000_planner_data_load', true),
       set_config('equinox.change_log', 'off', true);

-- ============================================================ 1. helpers
-- A number from the old JSON: a JSON number, or text that is plainly a number ("90"); null for anything else
create or replace function private.json_num(p jsonb)
 returns numeric
 language sql
 immutable
 set search_path to ''
as $function$
  select case jsonb_typeof(p)
           when 'number' then (p #>> '{}')::numeric
           when 'string' then case when (p #>> '{}') ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(p #>> '{}')::numeric end
         end
$function$;

-- A whole number from the old JSON (a flight number, seats, minutes); null when it isn't a whole number
create or replace function private.json_int(p jsonb)
 returns bigint
 language sql
 immutable
 set search_path to ''
as $function$
  select case when n = trunc(n) and abs(n) < 1e15 then n::bigint end from (select private.json_num(p) as n) x
$function$;

-- A date written YYYY-MM-DD; null for anything else, or a day that doesn't exist
create or replace function private.json_date(p jsonb)
 returns date
 language plpgsql
 immutable
 set search_path to ''
as $function$
begin
  if jsonb_typeof(p) is distinct from 'string' or (p #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return (p #>> '{}')::date;
exception when others then
  return null;
end
$function$;

-- A moment written the ISO way ("2026-09-29T17:53:16.155Z", "2026-09-29T05:53Z"); null for anything else
create or replace function private.json_ts(p jsonb)
 returns timestamptz
 language plpgsql
 immutable
 set search_path to ''
as $function$
begin
  if jsonb_typeof(p) is distinct from 'string'
     or (p #>> '{}') !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$' then
    return null;
  end if;
  return (p #>> '{}')::timestamptz;
exception when others then
  return null;
end
$function$;

-- A local clock time as the planner reads it (toMin): "07:30" or "7:30", up to 23:59, as minutes after midnight
create or replace function private.clock_min(p text)
 returns int
 language sql
 immutable
 set search_path to ''
as $function$
  select case when m[1]::int <= 23 and m[2]::int <= 59 then m[1]::int * 60 + m[2]::int end
    from (select regexp_match(btrim(p), '^(\d{1,2}):(\d{2})$') as m) x
$function$;

-- The weekdays in an old frequency's days ("135"), as the planner reads them: the digits 1 to 7, each once, sorted.
-- Null when there are none.
create or replace function private.weekday_set(p text)
 returns smallint[]
 language sql
 immutable
 set search_path to ''
as $function$
  select nullif(array(select distinct d::smallint from regexp_split_to_table(coalesce(p, ''), '') as d
                       where d ~ '^[1-7]$' order by 1), '{}')
$function$;

-- Weekdays moved by whole days (−1 = each a day earlier, Monday to Sunday), sorted
create or replace function private.shift_weekdays(p smallint[], p_days int)
 returns smallint[]
 language sql
 immutable
 set search_path to ''
as $function$
  select array(select distinct ((((d - 1 + p_days) % 7) + 7) % 7 + 1)::smallint from unnest(p) as d order by 1)
$function$;

-- Compares two planner documents (design §9, "Proving old and new are the same"): one row per difference, with its
-- path and kind. The kinds design §9 allows: 'a missing key equals null', 'numbers by value' (2.15 = 2.150000),
-- 'flight numbers as text' (noOut, noBack and a plan leg's no), 'a tail with no status equals "Active"', and
-- 'savedAt and version'. Key order never shows: jsonb keeps none. Anything else is 'differs'. p_old is the old
-- document; p_key is the key the values sit under, p_in_list whether they are list items.
create or replace function private.planner_json_differences(p_old jsonb, p_new jsonb, p_path text default '$',
                                                            p_key text default null, p_in_list boolean default false)
 returns table (path text, kind text)
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare k text; i int; n_old int; n_new int;
begin
  -- a list item that one side doesn't have
  if p_in_list and (p_old is null or p_new is null) then
    if p_old is not null or p_new is not null then return query select p_path, 'differs'; end if;
    return;
  end if;
  if p_key in ('savedAt', 'version') then
    if p_old is distinct from p_new then return query select p_path, 'savedAt and version'; end if;
    return;
  end if;
  -- missing, or null
  if coalesce(p_old, 'null'::jsonb) = 'null'::jsonb and coalesce(p_new, 'null'::jsonb) = 'null'::jsonb then
    if (p_old is null) <> (p_new is null) then return query select p_path, 'a missing key equals null'; end if;
    return;
  end if;
  if p_old is null and p_new = '"Active"'::jsonb and p_path ~ '^\$\.tails\[\d+\]\.status$' then
    return query select p_path, 'a tail with no status equals "Active"';
    return;
  end if;
  if coalesce(p_old, 'null'::jsonb) = 'null'::jsonb or coalesce(p_new, 'null'::jsonb) = 'null'::jsonb then
    return query select p_path, 'differs';
    return;
  end if;
  if p_key in ('noOut', 'noBack', 'no') and jsonb_typeof(p_old) <> jsonb_typeof(p_new)
     and jsonb_typeof(p_old) in ('string', 'number') and jsonb_typeof(p_new) in ('string', 'number') then
    return query select p_path, case when (p_old #>> '{}') = (p_new #>> '{}') then 'flight numbers as text' else 'differs' end;
    return;
  end if;
  if jsonb_typeof(p_old) <> jsonb_typeof(p_new) then
    return query select p_path, 'differs';
    return;
  end if;
  case jsonb_typeof(p_old)
    when 'object' then
      for k in select x from jsonb_object_keys(p_old) as x union select x from jsonb_object_keys(p_new) as x loop
        return query select * from private.planner_json_differences(p_old -> k, p_new -> k, p_path || '.' || k, k, false);
      end loop;
    when 'array' then
      n_old := jsonb_array_length(p_old); n_new := jsonb_array_length(p_new);
      for i in 0 .. greatest(n_old, n_new) - 1 loop
        return query select * from private.planner_json_differences(p_old -> i, p_new -> i, p_path || '[' || i || ']', p_key, true);
      end loop;
    when 'number' then
      if p_old <> p_new then return query select p_path, 'differs';
      elsif p_old::text <> p_new::text then return query select p_path, 'numbers by value';
      end if;
    else
      if p_old <> p_new then return query select p_path, 'differs'; end if;
  end case;
end
$function$;

-- ============================================================ 2. capture_cash (design §3.12, §8)
-- The planner's applyCaptureCash: per airline and capture date (game_balance.captured_on, the planner's date key) the
-- latest balance of account 2800, and the debits the events page lists in the 7 days after that balance was captured.
create view public.capture_cash with (security_invoker = true) as
with bal as (
  select distinct on (b.airline_id, b.captured_on) b.world_id, b.airline_id, b.captured_on, b.amount, b.captured_at
    from public.game_balance b
   where b.account like '2800%'
   order by b.airline_id, b.captured_on, b.captured_at desc)
select bal.world_id, bal.airline_id, bal.captured_on as day, bal.amount as cash,
       (select sum(e.debit) from public.game_events e
         where e.airline_id = bal.airline_id and e.debit > 0
           and e.due_at > bal.captured_at and e.due_at <= bal.captured_at + interval '7 days') as fixed_next7,
       bal.captured_at as cash_at
  from bal
 where bal.amount is not null;

-- ============================================================ 3. the getters (design §8)
-- The time of the latest logged change to a world's planner tables, in milliseconds, never earlier than the old
-- planner_state row's last save (for the default world). Cheap: no document is built.
create or replace function public.planner_state_version(p_world_id bigint default null)
 returns bigint
 language plpgsql
 stable
 security invoker
 set search_path to ''
as $function$
declare w bigint;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  select x.id into w from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', p_world_id; end if;
  return greatest(
    coalesce((select floor(extract(epoch from max(c.changed_at)) * 1000)::bigint from public.change_log c where c.world_id = w), 0),
    -- countries and airports carry no world, and their changes move every world's times
    coalesce((select floor(extract(epoch from max(c.changed_at)) * 1000)::bigint from public.change_log c where c.world_id is null), 0),
    coalesce((select p.saved_at from public.planner_state p join public.worlds x on x.id = w and x.is_default where p.id = 'main'), 0));
end
$function$;

-- Today's planner_state document, built from the tables: {json: the document as text, saved_at}. Its savedAt is
-- planner_state_version(). Every list keeps the old planner's order; anything the tables have no column for comes back
-- from the row's extra.
create or replace function public.planner_state_get(p_world_id bigint default null)
 returns jsonb
 language plpgsql
 stable
 security invoker
 set search_path to ''
as $function$
declare
  w bigint; v_host text; v_ver bigint;
  v_ref jsonb; v_tails jsonb; v_deliveries jsonb; v_freqs jsonb; v_plans jsonb; v_todos jsonb; v_fare jsonb;
  v_added jsonb; v_edits jsonb; v_cabin jsonb; v_monthly jsonb; v_interline jsonb; v_dismissed jsonb; v_keep jsonb;
  v_cash jsonb; v_fixed jsonb; v_capex jsonb; v_growth jsonb; v_doc jsonb;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  select x.id, x.game_host into w, v_host from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', p_world_id; end if;
  v_ver := public.planner_state_version(w);

  -- ---------- ref: hubs, consts, types, configs, services, markets, curfews, utcOverrides, timeMode, gameLinks
  v_ref := jsonb_build_object(
    'hubs', (select coalesce(jsonb_agg(
               jsonb_build_object('code', b.airport_code, 'airline', al.planner_name, 'role', b.role,
                                  'block', b.flight_no_from, 'lastUsed', b.last_flight_no)
               || jsonb_strip_nulls(jsonb_build_object(
                    'banks', (select jsonb_agg(coalesce(to_char(t, 'HH24:MI'), '') order by o) from unnest(b.bank_times) with ordinality as u(t, o)),
                    'mct', trim_scale(wa.mct_min / 60.0),
                    'hold', b.hold_note,
                    'parent', pb.airport_code))
               order by b.position, b.id), '[]'::jsonb)
               from public.airline_bases b
               join public.airlines al on al.id = b.airline_id
               left join public.airline_bases pb on pb.id = b.parent_base_id
               left join public.world_airports wa on wa.world_id = w and wa.airport_code = b.airport_code
              where b.world_id = w),
    'consts', (select coalesce(jsonb_object_agg(m.k, s.value order by m.k), '{}'::jsonb)
                 from (values ('buf', 'bank_buffer_min'), ('ovh', 'block_allowance_min'), ('arrwin', 'bank_arrival_window_min'),
                              ('depwin', 'bank_departure_window_min'), ('maxWait', 'connection_max_wait_h'),
                              ('legalGap', 'legal_gap_h'), ('turnMargin', 'turn_margin_min'),
                              ('maintMinGround', 'maint_min_ground_min'), ('leeway', 'load_leeway_days'),
                              ('lfWindow', 'load_window_days')) as m(k, setting)
                 join public.settings s on s.world_id = w and s.airline_id is null and s.key = m.setting
                -- the old planner stores these two only once they are typed; at its own defaults it leaves them out
                where not (m.k = 'leeway' and s.value = '7'::jsonb) and not (m.k = 'lfWindow' and s.value = '14'::jsonb))
              || coalesce((select jsonb_build_object('depCap', r.value -> 'value') from public.world_rules r
                            where r.world_id = w and r.key = 'departures_per_airport_week' and r.value ? 'value'), '{}'::jsonb),
    'types', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                'name', t.name, 'family', t.family_no, 'seats', t.seats_max, 'cruise', t.cruise_kmh, 'minTurn', t.min_turn_min,
                'gap', trim_scale(t.gap_target_h), 'mHour', trim_scale(t.maint_per_hour), 'mCycle', trim_scale(t.maint_per_cycle),
                'greens', t.ground_keep_min, 'priceM', trim_scale(t.price / 1000000))) order by t.id), '[]'::jsonb)
                from public.aircraft_types t where t.world_id = w),
    'configs', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                  'code', c.code, 'type', t.name, 'cabin', c.cabin, 'seats', c.seats, 'c', c.business_seats,
                  'y', c.economy_seats, 'costM', trim_scale(c.cost / 1000000), 'note', c.note)) order by c.id), '[]'::jsonb)
                  from public.cabin_configs c left join public.aircraft_types t on t.id = c.aircraft_type_id
                 where c.world_id = w),
    'services', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                   'code', p.code, 'airline', coalesce(al.planner_name, 'Legacy'), 'upTo', p.up_to_km, 'note', p.note))
                   order by p.id), '[]'::jsonb)
                   from public.service_profiles p left join public.airlines al on al.id = p.airline_id
                  where p.world_id = w),
    'markets', (select coalesce(jsonb_object_agg(al.planner_name || '|' || m.name,
                  jsonb_build_object('config', c.code, 'aircraft', t.name, 'priceY', trim_scale(m.fare_y_pct),
                                     'priceJ', trim_scale(m.fare_j_pct))), '{}'::jsonb)
                  from public.markets m
                  join public.airlines al on al.id = m.airline_id
                  left join public.cabin_configs c on c.id = m.default_config_id
                  left join public.aircraft_types t on t.id = m.default_type_id
                 where m.world_id = w),
    'curfews', (select coalesce(jsonb_object_agg(wa.airport_code,
                  to_char(wa.night_ban_from, 'HH24:MI') || '-' || to_char(wa.night_ban_to, 'HH24:MI')), '{}'::jsonb)
                  from public.world_airports wa
                 where wa.world_id = w and wa.night_ban_from is not null and wa.night_ban_to is not null),
    'utcOverrides', (select coalesce(jsonb_object_agg(wa.airport_code, trim_scale(wa.utc_offset_override)), '{}'::jsonb)
                       from public.world_airports wa where wa.world_id = w and wa.utc_offset_override is not null),
    'timeMode', (select s.value from public.settings s where s.world_id = w and s.airline_id is null and s.key = 'planner_time_mode'),
    'gameLinks', (select coalesce(jsonb_object_agg(al.planner_name,
                    'https://' || v_host || '/app/info/enterprises/' || al.game_id || '?tab=3'), '{}'::jsonb)
                    from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                   where al.world_id = w and g.kind = 'ours' and al.planner_name is not null));

  -- ---------- tails and deliveries: one aircraft row each, in each list's own order (kept in extra)
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', a.registration, 'airline', al.planner_name, 'base', coalesce(a.base_code, ''),
           'type', coalesce(t.name, ''), 'config', coalesce(c.code, ''), 'status', 'Active',
           'maint', a.maintenance_note, 'checkedOn', a.checked_on::text, 'schedChangedOn', a.schedule_changed_on::text))
           || coalesce(a.extra -> 'tail', '{}'::jsonb)
           order by (a.extra ->> 'tails_index')::int, a.id), '[]'::jsonb)
    into v_tails
    from public.aircraft a
    join public.airlines al on al.id = a.airline_id
    left join public.aircraft_types t on t.id = a.aircraft_type_id
    left join public.cabin_configs c on c.id = a.cabin_config_id
   where a.world_id = w and a.extra ? 'tails_index';
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'reg', a.registration, 'airline', al.planner_name,
           'utc', to_char(a.delivery_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'),
           'date', a.ordered_on::text, 'base', a.order_base_code, 'type', t.name, 'config', c.code, 'plan', a.order_note))
           || coalesce(a.extra -> 'delivery', '{}'::jsonb)
           order by (a.extra ->> 'deliveries_index')::int, a.id), '[]'::jsonb)
    into v_deliveries
    from public.aircraft a
    join public.airlines al on al.id = a.airline_id
    left join public.aircraft_types t on t.id = a.aircraft_type_id
    left join public.cabin_configs c on c.id = a.order_config_id
   where a.world_id = w and a.extra ? 'deliveries_index';

  -- ---------- freqs: a rotation and its two legs back in local time (design §4)
  select coalesce(jsonb_agg(f.j order by f.id), '[]'::jsonb) into v_freqs
    from (
      select r.id,
             jsonb_strip_nulls(jsonb_build_object(
               'id', r.legacy_key,
               'routeKey', al.planner_name || '|' || ro.hub_code || '|' || ro.dest_code,
               'days', (select string_agg(d::text, '' order by d) from unnest(x.days_local) as d),
               'tail', coalesce(ac.registration, ''),
               'noOut', coalesce(l1.flight_no::text, ''),
               'noBack', coalesce(l2.flight_no::text, ''),
               'depHub', coalesce(to_char(make_time(x.dep_hub / 60, x.dep_hub % 60, 0), 'HH24:MI'), ''),
               'arrDest', coalesce(to_char(make_time(x.arr_dest / 60, x.arr_dest % 60, 0), 'HH24:MI'), ''),
               'depDest', coalesce(to_char(make_time(x.dep_dest / 60, x.dep_dest % 60, 0), 'HH24:MI'), ''),
               'arrHub', coalesce(to_char(make_time(x.arr_hub / 60, x.arr_hub % 60, 0), 'HH24:MI'), ''),
               'service', r.service_code,
               'price', trim_scale(r.fare_pct),
               'launched', r.launched_on::text,
               'notes', r.note))
             || r.extra as j
        from public.rotations r
        join public.routes ro on ro.id = r.route_id
        join public.airlines al on al.id = r.airline_id
        left join public.flight_legs l1 on l1.rotation_id = r.id and l1.leg_no = 1
        left join public.flight_legs l2 on l2.rotation_id = r.id and l2.leg_no = 2
        left join public.aircraft ac on ac.id = coalesce(l1.aircraft_id, l2.aircraft_id)
        left join public.airports ah on ah.code = ro.hub_code
        left join public.world_airports wh on wh.world_id = w and wh.airport_code = ro.hub_code
        left join public.airports ad on ad.code = ro.dest_code
        left join public.world_airports wd on wd.world_id = w and wd.airport_code = ro.dest_code
        -- each end's offset in minutes; an airport whose offset isn't known counts as UTC, as the planner counts it
        cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                                   round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
        cross join lateral (
          select (((l1.dep_utc_min + o.oh) % 1440) + 1440) % 1440 as dep_hub,
                 (((l1.dep_utc_min + l1.block_min + o.od) % 1440) + 1440) % 1440 as arr_dest,
                 (((l2.dep_utc_min + o.od) % 1440) + 1440) % 1440 as dep_dest,
                 (((l2.dep_utc_min + l2.block_min + o.oh) % 1440) + 1440) % 1440 as arr_hub,
                 -- the old planner keeps the outbound's local weekdays at the hub
                 dl.days_local
            from (select case when l1.dep_utc_min is null then l1.days_utc
                              else array(select distinct ((((d - 1 + floor((l1.dep_utc_min + o.oh) / 1440.0)::int) % 7) + 7) % 7 + 1)::smallint
                                           from unnest(l1.days_utc) as d order by 1) end as days_local) dl) x
       where r.world_id = w) f;

  -- ---------- plans: one card per aircraft, its legs back in local time
  select coalesce(jsonb_object_agg(a.registration,
           jsonb_strip_nulls(jsonb_build_object('base', p.base_code, 'title', p.title, 'note', p.note))
           || jsonb_build_object('legs', (
                select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                         'no', coalesce(l.flight_no::text, ''),
                         'from', l.origin_code, 'to', l.dest_code,
                         'dep', coalesce(to_char(make_time(y.dep / 60, y.dep % 60, 0), 'HH24:MI'), ''),
                         'arr', coalesce(to_char(make_time(y.arr / 60, y.arr % 60, 0), 'HH24:MI'), ''),
                         'block', coalesce((l.block_min / 60)::text || ':' || lpad((l.block_min % 60)::text, 2, '0'), ''),
                         'svc', l.service_code)) order by l.position), '[]'::jsonb)
                  from public.plan_card_legs l
                  left join public.airports ao on ao.code = l.origin_code
                  left join public.world_airports wo on wo.world_id = w and wo.airport_code = l.origin_code
                  left join public.airports ad on ad.code = l.dest_code
                  left join public.world_airports wd on wd.world_id = w and wd.airport_code = l.dest_code
                  cross join lateral (select round(coalesce(wo.utc_offset_override, ao.utc_offset, 0) * 60)::int as oo,
                                             round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
                  cross join lateral (select (((l.dep_utc_min + o.oo) % 1440) + 1440) % 1440 as dep,
                                             (((l.dep_utc_min + l.block_min + o.od) % 1440) + 1440) % 1440 as arr) y
                 where l.plan_card_id = p.id))
           || p.extra), '{}'::jsonb)
    into v_plans
    from public.plan_cards p join public.aircraft a on a.id = p.aircraft_id
   where p.world_id = w;

  -- ---------- todos
  select coalesce(jsonb_agg(
           jsonb_strip_nulls(jsonb_build_object(
             'id', t.legacy_key, 'title', t.title, 'date', t.due_on::text, 'done', t.done, 'note', t.note,
             'doneAt', to_char(t.done_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
                       || case when to_char(t.done_at at time zone 'UTC', 'MS') = '000' then '' else '.' || to_char(t.done_at at time zone 'UTC', 'MS') end || 'Z',
             'created', to_char(t.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS')
                       || case when to_char(t.created_at at time zone 'UTC', 'MS') = '000' then '' else '.' || to_char(t.created_at at time zone 'UTC', 'MS') end || 'Z'))
           || jsonb_build_object('items', (select coalesce(jsonb_agg(to_jsonb(i.body) order by i.position), '[]'::jsonb)
                                             from public.todo_items i where i.todo_id = t.id))
           || t.extra
           order by t.id), '[]'::jsonb)
    into v_todos
    from public.todos t where t.world_id = w;

  -- ---------- fare plan
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', f.legacy_key, 'airline', al.planner_name,
           'routeKey', ral.planner_name || '|' || ro.hub_code || '|' || ro.dest_code,
           'cls', f.cabin_class, 'pct', trim_scale(f.change_pct), 'from', trim_scale(f.fare_from),
           'proposed', f.proposed_on::text, 'status', f.status, 'why', f.reason)) || f.extra order by f.id), '[]'::jsonb)
    into v_fare
    from public.fare_plan f
    join public.airlines al on al.id = f.airline_id
    left join public.routes ro on ro.id = f.route_id
    left join public.airlines ral on ral.id = ro.airline_id
   where f.world_id = w;

  -- ---------- routes added, route edits, route cabins
  select coalesce(jsonb_agg(jsonb_build_array(al.planner_name, r.hub_code, r.dest_code, r.city, r.country_label, r.distance_km,
                                              m.name, r.stars) order by r.id), '[]'::jsonb)
    into v_added
    from public.routes r join public.airlines al on al.id = r.airline_id left join public.markets m on m.id = r.market_id
   where r.world_id = w and r.source = 'added';
  select coalesce(jsonb_object_agg(al.planner_name || '|' || r.hub_code || '|' || r.dest_code,
           jsonb_strip_nulls(jsonb_build_object('removed', case when r.removed then true end, 'note', r.removed_note,
             'city', r.city_override, 'dist', r.distance_override_km, 'market', mo.name, 'stars', r.stars_override))), '{}'::jsonb)
    into v_edits
    from public.routes r join public.airlines al on al.id = r.airline_id left join public.markets mo on mo.id = r.market_override_id
   where r.world_id = w
     and (r.removed or r.removed_note is not null or r.city_override is not null or r.distance_override_km is not null
          or r.market_override_id is not null or r.stars_override is not null);
  select coalesce(jsonb_object_agg(al.planner_name || '|' || r.hub_code || '|' || r.dest_code, r.cabin_choice), '{}'::jsonb)
    into v_cabin
    from public.routes r join public.airlines al on al.id = r.airline_id
   where r.world_id = w and r.cabin_choice is not null;

  -- ---------- monthly checks, interline, dismissed alerts, kept cabins
  select coalesce(jsonb_object_agg(x.name, x.tasks), '{}'::jsonb) into v_monthly
    from (select coalesce(al.planner_name, 'Equinox') as name, jsonb_object_agg(m.task, m.last_done_on) as tasks
            from public.monthly_checks m left join public.airlines al on al.id = m.airline_id
           where m.world_id = w group by 1) x;
  select coalesce(jsonb_object_agg(al.planner_name || '|' || i.country_code, jsonb_strip_nulls(jsonb_build_object(
           'status', case i.status when 'to_sign' then 'requested' else i.status end,
           'partner', i.partner, 'date', i.decided_on::text, 'notes', i.note))), '{}'::jsonb)
    into v_interline
    from public.interline_agreements i join public.airlines al on al.id = i.airline_id
   where i.world_id = w;
  select coalesce(jsonb_object_agg(d.alert_key, d.dismissed_on), '{}'::jsonb) into v_dismissed
    from public.dismissals d where d.world_id = w;
  select coalesce(jsonb_object_agg(a.registration || '|' || k.cabin, jsonb_strip_nulls(jsonb_build_object('date', k.decided_on))), '{}'::jsonb)
    into v_keep
    from public.aircraft_cabin_keeps k join public.aircraft a on a.id = k.aircraft_id
   where k.world_id = w;

  -- ---------- cash and next-7-day costs, in millions: the capture's figure unless a cash_entries row says otherwise
  -- (design §8); rounded as the planner rounds (Math.round to 0.01M); next-7-day costs only when above zero
  with pairs as (
    select coalesce(e.airline_id, cc.airline_id) as airline_id, coalesce(e.day, cc.day) as day,
           coalesce(e.cash / 1000000, floor(cc.cash / 10000 + 0.5) / 100) as cash_m,
           coalesce(e.fixed_next7, cc.fixed_next7) as fixed_raw,
           e.fixed_next7 is not null as fixed_typed
      from (select * from public.cash_entries where world_id = w) e
      full join (select * from public.capture_cash where world_id = w) cc on cc.airline_id = e.airline_id and cc.day = e.day),
  named as (
    select al.planner_name, p.day::text as day, trim_scale(p.cash_m) as cash_m,
           case when p.fixed_raw > 0 then trim_scale(case when p.fixed_typed then p.fixed_raw / 1000000
                                                          else floor(p.fixed_raw / 10000 + 0.5) / 100 end) end as fixed_m
      from pairs p join public.airlines al on al.id = p.airline_id)
  select (select coalesce(jsonb_object_agg(x.day, x.v), '{}'::jsonb)
            from (select day, jsonb_object_agg(planner_name, cash_m) as v from named where cash_m is not null group by day) x),
         (select coalesce(jsonb_object_agg(x.day, x.v), '{}'::jsonb)
            from (select day, jsonb_object_agg(planner_name, fixed_m) as v from named where fixed_m is not null group by day) x)
    into v_cash, v_fixed;

  -- ---------- money spent and growth moves, in the old order
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'date', s.spent_on::text, 'note', s.note, 'airline', al.planner_name, 'amountM', trim_scale(s.amount / 1000000),
           -- orders were logged without a kind
           'kind', case when s.kind <> 'order' then s.kind end)) order by s.id), '[]'::jsonb)
    into v_capex
    from public.spending_log s join public.airlines al on al.id = s.airline_id where s.world_id = w;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'date', g.logged_on::text, 'move', g.move, 'note', g.note, 'airline', al.planner_name)) order by g.id), '[]'::jsonb)
    into v_growth
    from public.growth_log g join public.airlines al on al.id = g.airline_id where g.world_id = w;

  v_doc := jsonb_build_object(
    'version', 2, 'savedAt', v_ver, 'ref', v_ref, 'tails', v_tails, 'deliveries', v_deliveries, 'freqs', v_freqs,
    'plans', v_plans, 'todos', v_todos, 'farePlan', v_fare, 'routesAdded', v_added, 'routeEdits', v_edits,
    'routeCabin', v_cabin, 'monthly', v_monthly, 'interline', v_interline, 'dismissed', v_dismissed,
    'cabinKeep', v_keep, 'cash', v_cash, 'fixed7', v_fixed, 'capex', v_capex, 'growthLog', v_growth);
  return jsonb_build_object('json', v_doc::text, 'saved_at', v_ver);
end
$function$;

-- Today's planner_loads documents, one row per month like planner_loads, built from game_flights, load_entries and
-- load_days (design §8). A day holds:
--   f: each flight's economy load, keyed "Airline|number". The capture's figure, or a typed one (load_entries; null
--      means cleared) when it was written after the capture's loads step last ran over that day for that airline, or
--      the capture has no figure. The latest write wins, as the capture's loads step and save_loads() behave together.
--   done: as typed (load_days), unless a capture came later: then true once every active airline of the world has that
--      date's loads, as the loads step sets it;
--   source and captured: when the capture wrote the day. The loads step stamps every day of an airline's flights up to
--      3 days before the capture, so captured is the latest loads capture, of an airline flying that day, made no more
--      than 3 days after it;
--   savedAt: when the planner saved the day.
create or replace function public.planner_loads_get(p_world_id bigint default null)
 returns table (month text, "json" text, saved_at bigint)
 language plpgsql
 stable
 security invoker
 set search_path to ''
as $function$
#variable_conflict use_column
declare w bigint;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  select x.id into w from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', p_world_id; end if;
  return query
  with ours as (
    select a.id, a.planner_name, a.active from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  flown as (
    select f.airline_id, f.game_date, f.flight_no, f.eco_pct, f.loads_captured_at
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.game_date is not null),
  -- each airline's loads captures: its kept pages, and the times its flights were last written
  captures as (
    select r.airline_id, r.captured_at from public.game_capture_raw r join ours on ours.id = r.airline_id where r.kind = 'loads'
    union
    select f.airline_id, f.loads_captured_at from flown f where f.loads_captured_at is not null),
  -- when the loads step last ran over a day for an airline flying it
  stamped as (
    select x.airline_id, x.day, max(c.captured_at) as at
      from (select distinct f.airline_id, f.game_date as day from flown f) x
      join captures c on c.airline_id = x.airline_id and (c.captured_at at time zone 'UTC')::date - 3 <= x.day
     group by x.airline_id, x.day),
  caught as (
    select f.airline_id, f.game_date as day, f.flight_no, max(f.eco_pct) as eco_pct
      from flown f where f.eco_pct is not null group by f.airline_id, f.game_date, f.flight_no),
  typed as (select * from public.load_entries e where e.world_id = w),
  loads as (
    select coalesce(c.airline_id, e.airline_id) as airline_id, coalesce(c.day, e.game_date) as day,
           coalesce(c.flight_no, e.flight_no) as flight_no,
           case when e.airline_id is not null and (c.eco_pct is null or s.at is null or e.entered_at is null or e.entered_at >= s.at)
                then trim_scale(e.eco_pct) else c.eco_pct end as v
      from caught c
      full join typed e on e.airline_id = c.airline_id and e.game_date = c.day and e.flight_no = c.flight_no
      left join stamped s on s.airline_id = coalesce(c.airline_id, e.airline_id) and s.day = coalesce(c.day, e.game_date)),
  days as (
    select f.game_date as day from flown f
    union select ld.game_date from public.load_days ld where ld.world_id = w
    union select e.game_date from typed e),
  day_stamp as (select s.day, max(s.at) as at from stamped s group by s.day),
  doc_days as (
    select d.day,
           jsonb_build_object(
             'f', coalesce((select jsonb_object_agg(o.planner_name || '|' || l.flight_no, l.v)
                              from loads l join ours o on o.id = l.airline_id
                             where l.day = d.day and l.v is not null), '{}'::jsonb),
             'done', case when ld.game_date is null then c.complete
                          when ds.at is not null and (ld.entered_at is null or ds.at > ld.entered_at) then ld.done or c.complete
                          else ld.done end)
           || case when ds.day is null then '{}'::jsonb
                   else jsonb_build_object('source', 'capture',
                                           'captured', (to_jsonb(ds.at at time zone 'UTC') #>> '{}') || '+00:00') end
           || case when ld.saved_at_ms is null then '{}'::jsonb else jsonb_build_object('savedAt', ld.saved_at_ms) end as j,
           greatest(ds.at, ld.entered_at, (select max(e.entered_at) from typed e where e.game_date = d.day),
                    to_timestamp(ld.saved_at_ms / 1000.0)) as at
      from days d
      left join public.load_days ld on ld.world_id = w and ld.game_date = d.day
      left join day_stamp ds on ds.day = d.day
      -- every active airline of the world has loads for the date
      cross join lateral (select not exists (select 1 from ours o
                                              where o.active and not exists (select 1 from flown f
                                                                              where f.airline_id = o.id and f.game_date = d.day)) as complete) c)
  select to_char(dd.day, 'YYYY-MM'),
         jsonb_object_agg(dd.day::text, dd.j)::text,
         coalesce(floor(extract(epoch from max(dd.at)) * 1000)::bigint, 0)
    from doc_days dd
   group by to_char(dd.day, 'YYYY-MM')
   order by 1;
end
$function$;

-- ============================================================ 4. the loader (design §9 step 3)
-- Each step reads the old storage and writes its tables with upserts that leave a row untouched when nothing about it
-- changed, so running the loader again on the same data changes no rows, and ids that exist are kept.

-- A planner_loads month or any stored JSON text, read safely: '{}' when it isn't a JSON object
create or replace function private.json_object_or_empty(p text)
 returns jsonb
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare j jsonb;
begin
  j := p::jsonb;
  return case when jsonb_typeof(j) = 'object' then j else '{}'::jsonb end;
exception when others then
  return '{}'::jsonb;
end
$function$;

-- The keys of an old item the table has no column for, plus the earlier load's stand-ins that still hold: a value the
-- columns couldn't give back exactly (kept as the old JSON had it), or null for a key the old item didn't have. Used for
-- the extra column of aircraft (tail and delivery), rotations, plan_cards, todos and fare_plan.
create or replace function private.planner_extra(p_item jsonb, p_known text[], p_old_extra jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(p_item) e where e.key <> all (p_known)), '{}'::jsonb)
         || coalesce((select jsonb_object_agg(o.key, o.value) from jsonb_each(coalesce(p_old_extra, '{}'::jsonb)) o
                       where o.key = any (p_known)
                         and ((p_item ? o.key and p_item -> o.key = o.value) or (not p_item ? o.key and o.value = 'null'::jsonb))),
                     '{}'::jsonb)
$function$;

-- ---------- 4a. countries, airports and the world's airports (design §3.2)
create or replace function private.load_planner_places(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; v_countries int; v_airports int; v_codes int; v_world int; r jsonb := coalesce(s -> 'ref', '{}'::jsonb);
begin
  -- countries, from the route research; and any country an interline names that the research hasn't
  insert into public.countries as c (code, name)
  select e.key, e.value #>> '{}' from jsonb_each(coalesce(d -> 'countries', '{}'::jsonb)) e where jsonb_typeof(e.value) = 'string'
  on conflict (code) do update set name = excluded.name where c.name is distinct from excluded.name;
  get diagnostics v_countries = row_count;
  insert into public.countries (code, name)
  select distinct substr(e.key, strpos(e.key, '|') + 1), substr(e.key, strpos(e.key, '|') + 1)
    from jsonb_each(case when jsonb_typeof(s -> 'interline') = 'object' then s -> 'interline' else '{}'::jsonb end) e
   where strpos(e.key, '|') > 0 and substr(e.key, strpos(e.key, '|') + 1) <> ''
  on conflict (code) do nothing;

  -- airports: the research's places and time zones (planner_data.coords and planner_data.utc)
  with c as (select e.key as code, e.value as v from jsonb_each(coalesce(d -> 'coords', '{}'::jsonb)) e where jsonb_typeof(e.value) = 'array'),
  u as (select e.key as code, private.json_num(e.value) as off from jsonb_each(coalesce(d -> 'utc', '{}'::jsonb)) e),
  src as (
    select coalesce(c.code, u.code) as code, c.v ->> 2 as city, c.v ->> 3 as cc,
           private.json_num(c.v -> 0) as lat, private.json_num(c.v -> 1) as lon, u.off
      from c full join u on u.code = c.code)
  insert into public.airports as a (code, city, country_code, lat, lon, utc_offset)
  select src.code, src.city, (select x.code from public.countries x where x.code = src.cc),
         case when abs(src.lat) <= 90 then round(src.lat, 5) end, case when abs(src.lon) <= 180 then round(src.lon, 5) end,
         case when abs(src.off) <= 14 then round(src.off, 2) end
    from src where src.code <> ''
  on conflict (code) do update set city = excluded.city, country_code = excluded.country_code, lat = excluded.lat,
    lon = excluded.lon, utc_offset = excluded.utc_offset
  where (a.city, a.country_code, a.lat, a.lon, a.utc_offset)
        is distinct from (excluded.city, excluded.country_code, excluded.lat, excluded.lon, excluded.utc_offset);
  get diagnostics v_airports = row_count;

  -- every other airport the planner names (connection times, night bans, hubs, routes, flights, plans, aircraft bases),
  -- by its code only, so nothing that names it is refused
  insert into public.airports (code)
  select distinct x.code from (
    select jsonb_object_keys(case when jsonb_typeof(p_mct) = 'object' then p_mct else '{}'::jsonb end) as code
    union all select jsonb_object_keys(case when jsonb_typeof(r -> 'curfews') = 'object' then r -> 'curfews' else '{}'::jsonb end)
    union all select jsonb_object_keys(case when jsonb_typeof(r -> 'utcOverrides') = 'object' then r -> 'utcOverrides' else '{}'::jsonb end)
    union all select h ->> 'code' from jsonb_array_elements(case when jsonb_typeof(r -> 'hubs') = 'array' then r -> 'hubs' else '[]'::jsonb end) h
    union all select v ->> i from jsonb_array_elements(case when jsonb_typeof(d -> 'routes') = 'array' then d -> 'routes' else '[]'::jsonb end) v, generate_series(1, 2) i
    union all select v ->> i from jsonb_array_elements(case when jsonb_typeof(s -> 'routesAdded') = 'array' then s -> 'routesAdded' else '[]'::jsonb end) v, generate_series(1, 2) i
    union all select split_part(k, '|', i) from jsonb_object_keys(case when jsonb_typeof(s -> 'routeEdits') = 'object' then s -> 'routeEdits' else '{}'::jsonb end) k, generate_series(2, 3) i
    union all select split_part(k, '|', i) from jsonb_object_keys(case when jsonb_typeof(s -> 'routeCabin') = 'object' then s -> 'routeCabin' else '{}'::jsonb end) k, generate_series(2, 3) i
    union all select split_part(f ->> 'routeKey', '|', i) from jsonb_array_elements(case when jsonb_typeof(s -> 'freqs') = 'array' then s -> 'freqs' else '[]'::jsonb end) f, generate_series(2, 3) i
    union all select split_part(f ->> 'routeKey', '|', i) from jsonb_array_elements(case when jsonb_typeof(s -> 'farePlan') = 'array' then s -> 'farePlan' else '[]'::jsonb end) f, generate_series(2, 3) i
    union all select p.value ->> 'base' from jsonb_each(case when jsonb_typeof(s -> 'plans') = 'object' then s -> 'plans' else '{}'::jsonb end) p
    union all select l ->> k from jsonb_each(case when jsonb_typeof(s -> 'plans') = 'object' then s -> 'plans' else '{}'::jsonb end) p,
                     jsonb_array_elements(case when jsonb_typeof(p.value -> 'legs') = 'array' then p.value -> 'legs' else '[]'::jsonb end) l,
                     unnest(array['from', 'to']) k
    union all select t ->> 'base' from jsonb_array_elements(case when jsonb_typeof(s -> 'tails') = 'array' then s -> 'tails' else '[]'::jsonb end) t
    union all select t ->> 'base' from jsonb_array_elements(case when jsonb_typeof(s -> 'deliveries') = 'array' then s -> 'deliveries' else '[]'::jsonb end) t
  ) x
   where x.code ~ '^[A-Z0-9]{3,4}$'
  on conflict (code) do nothing;
  get diagnostics v_codes = row_count;

  -- what this world says about them: connection times (a hub's own figure first, then site_content.mct), night bans
  -- and offset corrections
  with hub_mct as (
    select distinct on (h ->> 'code') h ->> 'code' as code, private.json_num(h -> 'mct') * 60 as m
      from jsonb_array_elements(case when jsonb_typeof(r -> 'hubs') = 'array' then r -> 'hubs' else '[]'::jsonb end) with ordinality as e(h, ord)
     where private.json_num(h -> 'mct') is not null
     order by h ->> 'code', e.ord),
  site_mct as (select e.key as code, private.json_num(e.value) as m
                 from jsonb_each(case when jsonb_typeof(p_mct) = 'object' then p_mct else '{}'::jsonb end) e),
  ban as (select e.key as code, regexp_match(e.value #>> '{}', '^(\d{1,2}:\d{2})-(\d{1,2}:\d{2})$') as m
            from jsonb_each(case when jsonb_typeof(r -> 'curfews') = 'object' then r -> 'curfews' else '{}'::jsonb end) e),
  ovr as (select e.key as code, private.json_num(e.value) as off
            from jsonb_each(case when jsonb_typeof(r -> 'utcOverrides') = 'object' then r -> 'utcOverrides' else '{}'::jsonb end) e),
  codes as (select code from hub_mct union select code from site_mct union select code from ban union select code from ovr),
  src as (
    select c.code,
           (select case when x.m = round(x.m) and abs(x.m) < 32000 then x.m::smallint end
              from (select coalesce(hm.m, sm.m) as m) x) as mct_min,
           case when private.clock_min(b.m[1]) is not null then make_time(private.clock_min(b.m[1]) / 60, private.clock_min(b.m[1]) % 60, 0) end as ban_from,
           case when private.clock_min(b.m[2]) is not null then make_time(private.clock_min(b.m[2]) / 60, private.clock_min(b.m[2]) % 60, 0) end as ban_to,
           case when abs(o.off) <= 14 then round(o.off, 2) end as off
      from codes c
      left join hub_mct hm on hm.code = c.code
      left join site_mct sm on sm.code = c.code
      left join ban b on b.code = c.code
      left join ovr o on o.code = c.code
     where exists (select 1 from public.airports a where a.code = c.code))
  insert into public.world_airports as x (world_id, airport_code, mct_min, night_ban_from, night_ban_to, utc_offset_override)
  select w, src.code, src.mct_min, src.ban_from, src.ban_to, src.off from src
  on conflict (world_id, airport_code) do update set mct_min = excluded.mct_min, night_ban_from = excluded.night_ban_from,
    night_ban_to = excluded.night_ban_to, utc_offset_override = excluded.utc_offset_override
  where (x.mct_min, x.night_ban_from, x.night_ban_to, x.utc_offset_override)
        is distinct from (excluded.mct_min, excluded.night_ban_from, excluded.night_ban_to, excluded.utc_offset_override);
  get diagnostics v_world = row_count;
  return jsonb_build_object('countries', v_countries, 'airports', v_airports, 'airports named only', v_codes, 'world_airports', v_world);
end
$function$;

-- ---------- 4b. types, cabins, markets, services, bases, buy lists, settings and world rules (design §3.1, §3.3,
-- §3.4, §3.7)
create or replace function private.load_planner_reference(p_world_id bigint, s jsonb, p_growth jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; r jsonb := coalesce(s -> 'ref', '{}'::jsonb); c jsonb; n int; v_out jsonb := '{}'::jsonb;
begin
  c := case when jsonb_typeof(r -> 'consts') = 'object' then r -> 'consts' else '{}'::jsonb end;

  -- aircraft types (ref.types), in the planner's order
  with src as (
    select distinct on (t ->> 'name') t, e.ord
      from jsonb_array_elements(case when jsonb_typeof(r -> 'types') = 'array' then r -> 'types' else '[]'::jsonb end) with ordinality as e(t, ord)
     where jsonb_typeof(t) = 'object' and coalesce(t ->> 'name', '') <> ''
     order by t ->> 'name', e.ord)
  insert into public.aircraft_types as x (world_id, name, family_no, seats_max, cruise_kmh, min_turn_min, gap_target_h,
                                          maint_per_hour, maint_per_cycle, ground_keep_min, price)
  select w, t ->> 'name', private.json_int(t -> 'family'), private.json_int(t -> 'seats'), private.json_int(t -> 'cruise'),
         (select v::smallint from private.json_int(t -> 'minTurn') v where abs(v) < 32000),
         (select v from private.json_num(t -> 'gap') v where abs(v) < 1000),
         (select v from private.json_num(t -> 'mHour') v where abs(v) < 1000),
         (select v from private.json_num(t -> 'mCycle') v where abs(v) < 1000),
         (select v::smallint from private.json_int(t -> 'greens') v where abs(v) < 32000),
         (select v * 1000000 from private.json_num(t -> 'priceM') v where abs(v) < 1000000)
    from src order by src.ord
  on conflict (world_id, name) do update set family_no = excluded.family_no, seats_max = excluded.seats_max,
    cruise_kmh = excluded.cruise_kmh, min_turn_min = excluded.min_turn_min, gap_target_h = excluded.gap_target_h,
    maint_per_hour = excluded.maint_per_hour, maint_per_cycle = excluded.maint_per_cycle,
    ground_keep_min = excluded.ground_keep_min, price = excluded.price
  where (x.family_no, x.seats_max, x.cruise_kmh, x.min_turn_min, x.gap_target_h, x.maint_per_hour, x.maint_per_cycle,
         x.ground_keep_min, x.price)
        is distinct from (excluded.family_no, excluded.seats_max, excluded.cruise_kmh, excluded.min_turn_min,
                          excluded.gap_target_h, excluded.maint_per_hour, excluded.maint_per_cycle,
                          excluded.ground_keep_min, excluded.price);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft_types', n);

  -- cabin layouts (ref.configs)
  with src as (
    select distinct on (t ->> 'code') t, e.ord
      from jsonb_array_elements(case when jsonb_typeof(r -> 'configs') = 'array' then r -> 'configs' else '[]'::jsonb end) with ordinality as e(t, ord)
     where jsonb_typeof(t) = 'object' and coalesce(t ->> 'code', '') <> ''
     order by t ->> 'code', e.ord)
  insert into public.cabin_configs as x (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats, cost, note)
  select w, t ->> 'code', (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = t ->> 'type'),
         case when t ->> 'cabin' in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort') then t ->> 'cabin' end,
         private.json_int(t -> 'seats'), private.json_int(t -> 'c'), private.json_int(t -> 'y'),
         (select v * 1000000 from private.json_num(t -> 'costM') v where abs(v) < 1000000), t ->> 'note'
    from src order by src.ord
  on conflict (world_id, code) do update set aircraft_type_id = excluded.aircraft_type_id, cabin = excluded.cabin,
    seats = excluded.seats, business_seats = excluded.business_seats, economy_seats = excluded.economy_seats,
    cost = excluded.cost, note = excluded.note
  where (x.aircraft_type_id, x.cabin, x.seats, x.business_seats, x.economy_seats, x.cost, x.note)
        is distinct from (excluded.aircraft_type_id, excluded.cabin, excluded.seats, excluded.business_seats,
                          excluded.economy_seats, excluded.cost, excluded.note);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('cabin_configs', n);

  -- markets (ref.markets, keyed "Airline|Market")
  with src as (
    select al.id as airline_id, substr(e.key, strpos(e.key, '|') + 1) as name, e.value as v
      from jsonb_each(case when jsonb_typeof(r -> 'markets') = 'object' then r -> 'markets' else '{}'::jsonb end) e
      join public.airlines al on al.world_id = w and al.planner_name = split_part(e.key, '|', 1)
     where strpos(e.key, '|') > 0 and jsonb_typeof(e.value) = 'object')
  insert into public.markets as x (world_id, airline_id, name, default_type_id, default_config_id, fare_y_pct, fare_j_pct)
  select w, src.airline_id, src.name,
         (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = src.v ->> 'aircraft'),
         (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = src.v ->> 'config'),
         (select v from private.json_num(src.v -> 'priceY') v where abs(v) < 10000),
         (select v from private.json_num(src.v -> 'priceJ') v where abs(v) < 10000)
    from src order by src.airline_id, src.name
  on conflict (airline_id, name) do update set default_type_id = excluded.default_type_id,
    default_config_id = excluded.default_config_id, fare_y_pct = excluded.fare_y_pct, fare_j_pct = excluded.fare_j_pct
  where (x.default_type_id, x.default_config_id, x.fare_y_pct, x.fare_j_pct)
        is distinct from (excluded.default_type_id, excluded.default_config_id, excluded.fare_y_pct, excluded.fare_j_pct);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('markets', n);

  -- on-board service (ref.services): "Legacy" means every airline without its own
  with src as (
    select distinct on (t ->> 'code') t, e.ord
      from jsonb_array_elements(case when jsonb_typeof(r -> 'services') = 'array' then r -> 'services' else '[]'::jsonb end) with ordinality as e(t, ord)
     where jsonb_typeof(t) = 'object' and coalesce(t ->> 'code', '') <> ''
     order by t ->> 'code', e.ord)
  insert into public.service_profiles as x (world_id, airline_id, code, up_to_km, note)
  select w, (select al.id from public.airlines al where al.world_id = w and al.planner_name = t ->> 'airline'),
         t ->> 'code', private.json_int(t -> 'upTo'), t ->> 'note'
    from src order by src.ord
  on conflict (world_id, code) do update set airline_id = excluded.airline_id, up_to_km = excluded.up_to_km, note = excluded.note
  where (x.airline_id, x.up_to_km, x.note) is distinct from (excluded.airline_id, excluded.up_to_km, excluded.note);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('service_profiles', n);

  -- hubs and focus cities (ref.hubs), in the planner's order; the main hubs as the planner's MAIN_HUB has them
  -- (web/planner/index.html; Ryanair has none, being exempt from hubs first)
  with main(planner_name, code) as (values ('Pan American', 'JFK'), ('Kingfisher', 'DEL'), ('Virgin Atlantic', 'LGW'),
                                           ('China Eastern', 'PVG'), ('Malaysia Airlines', 'KUL')),
  src as (
    select distinct on (al.id, h ->> 'code') al.id as airline_id, al.planner_name, h, e.ord
      from jsonb_array_elements(case when jsonb_typeof(r -> 'hubs') = 'array' then r -> 'hubs' else '[]'::jsonb end) with ordinality as e(h, ord)
      join public.airlines al on al.world_id = w and al.planner_name = h ->> 'airline'
     where jsonb_typeof(h) = 'object' and exists (select 1 from public.airports a where a.code = h ->> 'code')
     order by al.id, h ->> 'code', e.ord)
  insert into public.airline_bases as x (world_id, airline_id, airport_code, role, is_main, bank_times, flight_no_from,
                                         last_flight_no, hold_note, position)
  select w, src.airline_id, src.h ->> 'code', case when src.h ->> 'role' = 'focus' then 'focus' else 'hub' end,
         exists (select 1 from main where main.planner_name = src.planner_name and main.code = src.h ->> 'code'),
         case when jsonb_typeof(src.h -> 'banks') = 'array' and jsonb_array_length(src.h -> 'banks') <= 4 then
           array(select case when private.clock_min(b.v #>> '{}') is not null
                             then make_time(private.clock_min(b.v #>> '{}') / 60, private.clock_min(b.v #>> '{}') % 60, 0) end
                   from jsonb_array_elements(src.h -> 'banks') with ordinality as b(v, o) order by b.o) end,
         (select v::int from private.json_int(src.h -> 'block') v where abs(v) < 2000000000),
         (select v::int from private.json_int(src.h -> 'lastUsed') v where abs(v) < 2000000000),
         src.h ->> 'hold', (src.ord - 1)::int
    from src order by src.ord
  on conflict (airline_id, airport_code) do update set role = excluded.role, is_main = excluded.is_main,
    bank_times = excluded.bank_times, flight_no_from = excluded.flight_no_from, last_flight_no = excluded.last_flight_no,
    hold_note = excluded.hold_note, position = excluded.position
  where (x.role, x.is_main, x.bank_times, x.flight_no_from, x.last_flight_no, x.hold_note, x.position)
        is distinct from (excluded.role, excluded.is_main, excluded.bank_times, excluded.flight_no_from,
                          excluded.last_flight_no, excluded.hold_note, excluded.position);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('airline_bases', n);
  -- a focus city's hub: the airline's own base at that airport, else any base there
  with src as (
    select b.id, (select p.id from public.airline_bases p
                   where p.world_id = w and p.airport_code = h ->> 'parent' and p.id <> b.id
                   order by (p.airline_id = b.airline_id) desc, p.id limit 1) as parent_id
      from jsonb_array_elements(case when jsonb_typeof(r -> 'hubs') = 'array' then r -> 'hubs' else '[]'::jsonb end) h
      join public.airlines al on al.world_id = w and al.planner_name = h ->> 'airline'
      join public.airline_bases b on b.airline_id = al.id and b.airport_code = h ->> 'code')
  update public.airline_bases b set parent_base_id = src.parent_id
    from src where b.id = src.id and b.parent_base_id is distinct from src.parent_id;

  -- the types each airline may buy: the planner's BUY_TYPES (web/planner/index.html)
  insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id)
  select w, al.id, ty.id
    from public.airlines al
    join public.groups g on g.id = al.group_id and g.world_id = al.world_id and g.kind = 'ours'
    cross join lateral unnest(case when al.planner_name = 'Ryanair' then array['A321 NEO LIGHT', 'E195-E2']
                                   else array['A320NEO LIGHT', 'A321 NEO LIGHT', 'E195-E2', 'A321XLR', 'A350-900ULR'] end) as t(name)
    join public.aircraft_types ty on ty.world_id = w and ty.name = t.name
   where al.world_id = w
  on conflict (airline_id, aircraft_type_id) do nothing;
  delete from public.airline_aircraft_types x
   using public.airlines al, public.aircraft_types ty
   where x.world_id = w and al.id = x.airline_id and ty.id = x.aircraft_type_id
     and ty.name <> all (case when al.planner_name = 'Ryanair' then array['A321 NEO LIGHT', 'E195-E2']
                              else array['A320NEO LIGHT', 'A321 NEO LIGHT', 'E195-E2', 'A321XLR', 'A350-900ULR'] end);

  -- settings (design §3.7): the manual's rule numbers, the planner's ref.consts and timeMode as it stores them, its code
  -- constants (CUSHION, LEASE_PCT and the growth signals' thresholds in routeProfit() and patterns(),
  -- web/planner/index.html) and planner_meta.growthRules
  with src(airline_name, key, value, unit, description, since, reason) as (values
    (null, 'order_cushion', '500000'::jsonb, 'AS$', 'Cash that must stay in hand at the lowest point of the 14-day forecast after an order (manual §3; the planner''s CUSHION, 0.5M)', date '2026-10-07', 'The old surplus rule ignored flight income during the week'),
    (null, 'lease_estimate_pct', '10', '% of the price', 'Weekly lease as a share of the order price, used only for a type never leased yet (the planner''s LEASE_PCT)', null, null),
    (null, 'hub_first_departures', coalesce(p_growth #> '{hubsFirst,hubTarget}', '750'), 'departures a week', 'Hubs first: the main hub''s weekly departures before the airline opens another hub (manual §3; planner_meta.growthRules)', date '2026-10-05', 'Confirmed 8 Oct as the only test for opening a new base'),
    (null, 'contested_rival_weekly', coalesce(p_growth #> '{hubsFirst,contested,airportRivalWeekly}', '250'), 'departures a week', 'A new hub is contested when a rival flies more than this there a week (manual §3)', date '2026-10-05', null),
    (null, 'contested_rival_daily', coalesce(p_growth #> '{hubsFirst,contested,routeRivalPerDay}', '2'), 'flights a day', 'A new hub is contested when a rival flies more than this a day on a route we''d open with (manual §3)', date '2026-10-05', null),
    ('Ryanair', 'hub_first_exempt', to_jsonb(coalesce(p_growth #> '{hubsFirst,exempt}' ? 'Ryanair', true)), null, 'Ryanair is exempt from hubs first (manual §3)', date '2026-10-05', null),
    (null, 'connection_buffer_min', '0', 'minutes', 'Margin on top of the minimum connection time: none (manual §4)', date '2026-10-09', 'Gitesh: as long as it''s over the minimum connection time, it''s good'),
    (null, 'connection_max_wait_h', coalesce(c -> 'maxWait', '8'), 'hours', 'Departures leave within this long of the arrivals they collect (manual §4; the planner''s ref.consts.maxWait)', date '2026-10-06', null),
    (null, 'bank_arrival_window_min', coalesce(c -> 'arrwin', '60'), 'minutes', 'A bank''s arrival window (the planner''s ref.consts.arrwin)', null, null),
    (null, 'bank_departure_window_min', coalesce(c -> 'depwin', '60'), 'minutes', 'A bank''s departure window (the planner''s ref.consts.depwin)', null, null),
    (null, 'bank_buffer_min', coalesce(c -> 'buf', '0'), 'minutes', 'Buffer in the planner''s bank check (ref.consts.buf)', date '2026-10-09', null),
    (null, 'second_daily_gap_h', '3', 'hours', 'A second daily on a route sits at least this far from the existing flight (manual §4)', null, null),
    (null, 'turn_margin_min', coalesce(c -> 'turnMargin', '10'), 'minutes', 'Margin on top of the game''s turnaround: 10 to 15, 5 tolerated on the busiest aircraft (manual §4; ref.consts.turnMargin)', date '2026-09-25', 'Room for delays and slot availability'),
    (null, 'maintenance_min_pct', '100', '%', 'Maintenance at or above this is firm (manual §4)', date '2026-09-28', null),
    (null, 'maintenance_target_pct', '105', '%', 'Maintenance to aim for (manual §4)', date '2026-09-28', null),
    (null, 'maint_min_ground_min', coalesce(c -> 'maintMinGround', '120'), 'minutes', 'Shortest ground gap that counts for maintenance (ref.consts.maintMinGround)', null, null),
    (null, 'block_allowance_min', coalesce(c -> 'ovh', '25'), 'minutes', 'Block time estimate: this plus distance ÷ cruise speed (manual §4; ref.consts.ovh; speeds in aircraft_types.cruise_kmh)', null, null),
    (null, 'legal_gap_h', coalesce(c -> 'legalGap', '2'), 'hours', 'The planner''s legal gap (ref.consts.legalGap)', null, null),
    (null, 'fare_launch_pct', '100', '% of standard', 'New routes launch at this share of the standard fare, both cabins (manual §5; per-market prices in markets)', date '2026-09-20', 'Every lane ran full at lower fares'),
    ('Ryanair', 'fare_launch_pct', '85', '% of standard', 'Ryanair launches at 85%, economy only (manual §5)', date '2026-09-20', null),
    (null, 'growth_window_days', '7', 'days', 'Growth signals look at the last this many days of captures (routeProfit)', null, null),
    (null, 'growth_losing_min_departures', '2', 'departures', 'A route is losing once its average flight loses money over at least this many departures (routeProfit)', null, null),
    (null, 'growth_sold_out_share', '0.8', 'share of departures', 'Ready for another flight, or raise fares: sold out on at least this share of departures (routeProfit)', null, null),
    (null, 'growth_sold_out_min_departures', '4', 'departures', 'The sold-out signals need at least this many captured departures (routeProfit)', null, null),
    (null, 'growth_fix_min_departures', '5', 'departures', 'Fix or reduce needs at least this many departures (routeProfit)', null, null),
    (null, 'growth_fix_economy_pct', '75', '%', 'Fix or reduce: economy averaging under this (routeProfit)', null, null),
    (null, 'growth_fix_margin', '0.25', 'share of income', 'Fix or reduce: bottom-quarter profit a flight on a margin under this, once the airline has at least growth_fix_min_routes routes (routeProfit)', null, null),
    (null, 'growth_fix_min_routes', '8', 'routes', 'The bottom-quarter test needs at least this many routes (routeProfit)', null, null),
    (null, 'pattern_min_departures', '6', 'departures', 'Load patterns: cut or watch needs at least this many departures in the window (patterns)', null, null),
    (null, 'pattern_cut_under70_share', '0.4', 'share of departures', 'Load patterns: cut when at least this share flew under 70% (patterns)', null, null),
    (null, 'pattern_cut_under85_share', '0.6', 'share of departures', 'Load patterns: cut when at least this share flew under 85% (patterns)', null, null),
    (null, 'pattern_watch_under85_share', '0.3', 'share of departures', 'Load patterns: watch when at least this share flew under 85% (patterns)', null, null),
    (null, 'pattern_add_min_departures', '10', 'departures', 'Load patterns: add frequency needs at least this many departures (patterns)', null, null),
    (null, 'pattern_add_full_share', '0.85', 'share of departures', 'Load patterns: add frequency when at least this share flew 95% or more (patterns)', null, null),
    (null, 'load_leeway_days', coalesce(c -> 'leeway', '7'), 'days', 'A new route''s first days don''t count in load patterns (ref.consts.leeway; the planner''s default 7)', null, null),
    (null, 'load_window_days', coalesce(c -> 'lfWindow', '14'), 'days', 'Load patterns look back this many days (ref.consts.lfWindow; the planner''s default 14)', null, null),
    (null, 'capture_day_starts_utc', '"10:00"', 'UTC clock time', 'A capture day runs from this time to the same time the next day, so one evening''s capture is one day (design §2)', null, null),
    (null, 'planner_time_mode', coalesce(r -> 'timeMode', '"local"'), null, 'The old planner shows times local or UTC (ref.timeMode)', null, null))
  insert into public.settings as x (world_id, airline_id, key, value, unit, description, since, reason)
  select w, al.id, src.key, src.value, src.unit, src.description, src.since, src.reason
    from src left join public.airlines al on al.world_id = w and al.planner_name = src.airline_name
   where src.airline_name is null or al.id is not null
  on conflict on constraint settings_world_airline_key_key do update set value = excluded.value, unit = excluded.unit,
    description = excluded.description, since = excluded.since, reason = excluded.reason
  where (x.value, x.unit, x.description, x.since, x.reason)
        is distinct from (excluded.value, excluded.unit, excluded.description, excluded.since, excluded.reason);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('settings', n);

  -- world rules (design §3.7): Gander's house rules and mechanics (manual §9) and #12's permissions
  with src(key, value, kind, unit, description, since, source) as (values
    ('holdings_max', '8'::jsonb, 'house', 'holdings', 'Holdings per player: 6, plus 2 in low-demand countries', null::date, 'manual §9'),
    ('low_demand_holdings', '2', 'house', 'holdings', 'Of those, holdings that must be in low-demand countries', null, 'manual §9'),
    ('holdings_per_country', '{"US": 1, "CN": 1, "EU": 2}', 'house', 'holdings', 'At most 1 US, 1 China and 2 EU holdings', null, 'manual §9'),
    ('lcc_holdings_max', '1', 'house', 'holdings', 'At most 1 LCC; LCCs may fly outside their founding country', null, 'manual §9'),
    ('starting_capital', '45000000', 'house', 'AS$', 'Starting capital per holding', null, 'manual §9'),
    ('departures_per_airport_week', jsonb_build_object('value', coalesce(c -> 'depCap', '5000'::jsonb), 'then', 8000, 'after', '3 months'), 'house', 'departures a week', 'Departures a week per player per airport, rising to 8,000 after three months (the planner''s ref.consts.depCap)', null, 'manual §9'),
    ('same_route_gap_min', '5', 'house', 'minutes', 'At least this long between departures on the same route', null, 'manual §9'),
    ('fare_floor_pct', '60', 'house', '% of standard', 'Fare floor wherever another player flies the route, our own airlines included', null, 'manual §9'),
    ('freedom_routes_max', coalesce(p_growth #> '{freedomRoutes,maxPerAirline}', '30'), 'house', 'routes', 'Fifth- and eighth-freedom routes per airline (planner_meta.growthRules)', date '2026-10-05', 'manual §9'),
    ('alliance_max', '30', 'house', 'airlines', 'Alliances are capped at this many members', null, 'manual §9'),
    ('new_brand_route_days', '14', 'house', 'days', 'A newly claimed brand must have a route flying within this many days', null, 'manual §9'),
    ('demand_model', '"per airport"', 'game', null, 'Demand is per airport, not per city', null, 'manual §9'),
    ('treaties', 'null', 'game', null, 'The world''s traffic-rights settings: not recorded yet; to be copied from Gander''s settings page in the game', null, 'design §3.7'),
    ('time_zones', '"standard time all year"', 'game', null, 'The game runs standard time all year: JFK −5, London 0, Paris and Amsterdam +1, Delhi +5:30', null, 'manual §9'),
    ('subsidiaries_work', 'false', 'game', null, 'Subsidiaries don''t work with the game''s demand model, so we don''t use them', null, 'manual §9'),
    ('interline_own_airlines', 'true', 'permission', null, 'Interlines between our own airlines are allowed in Gander (an exclusive world)', null, 'decision #12'),
    ('capture_salary_step', 'true', 'permission', null, 'Setting salaries by script is allowed in Gander (since 10 Oct a separate script, run by hand on one airline)', null, 'decision #12'),
    ('world_scanner', 'true', 'permission', null, 'The world scanner is allowed in Gander', null, 'decision #12'),
    ('schedule_check', 'true', 'permission', null, 'Reading airlines'' public schedules (the planner''s Check screen) is allowed in Gander', null, 'decision #12'))
  insert into public.world_rules as x (world_id, key, value, kind, unit, description, since, source)
  select w, src.key, src.value, src.kind, src.unit, src.description, src.since, src.source from src
  on conflict (world_id, key) do update set value = excluded.value, kind = excluded.kind, unit = excluded.unit,
    description = excluded.description, since = excluded.since, source = excluded.source
  where (x.value, x.kind, x.unit, x.description, x.since, x.source)
        is distinct from (excluded.value, excluded.kind, excluded.unit, excluded.description, excluded.since, excluded.source);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('world_rules', n);
  return v_out;
end
$function$;

-- ---------- 4c. aircraft: tails and deliveries merged, one row per registration (design §3.3)
-- Today's type, cabin and base come from the tail; as ordered from the delivery. Each list's order is kept in extra
-- (tails_index, deliveries_index), since one table can't keep two orders by id; whatever else an item holds that the
-- columns don't goes into extra.tail or extra.delivery.
create or replace function private.load_planner_fleet(p_world_id bigint, s jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
  k_tail text[] := array['id', 'airline', 'base', 'type', 'config', 'status', 'maint', 'checkedOn', 'schedChangedOn'];
  k_delivery text[] := array['reg', 'airline', 'utc', 'date', 'base', 'type', 'config', 'plan'];
begin
  with t as (
    select distinct on (v ->> 'id') v ->> 'id' as reg, v, (e.ord - 1)::int as idx
      from jsonb_array_elements(case when jsonb_typeof(s -> 'tails') = 'array' then s -> 'tails' else '[]'::jsonb end) with ordinality as e(v, ord)
     where jsonb_typeof(v) = 'object' and coalesce(v ->> 'id', '') <> ''
     order by v ->> 'id', e.ord),
  d as (
    select distinct on (v ->> 'reg') v ->> 'reg' as reg, v, (e.ord - 1)::int as idx
      from jsonb_array_elements(case when jsonb_typeof(s -> 'deliveries') = 'array' then s -> 'deliveries' else '[]'::jsonb end) with ordinality as e(v, ord)
     where jsonb_typeof(v) = 'object' and coalesce(v ->> 'reg', '') <> ''
     order by v ->> 'reg', e.ord),
  m as (
    select coalesce(t.reg, d.reg) as reg, t.v as tv, t.idx as ti, d.v as dv, d.idx as di,
           (select al.id from public.airlines al where al.world_id = w and al.planner_name = coalesce(t.v ->> 'airline', d.v ->> 'airline')) as airline_id,
           private.json_ts(d.v -> 'utc') as delivery_at
      from t full join d on d.reg = t.reg),
  src as (
    select m.*, old.extra as old_extra,
           (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = coalesce(nullif(m.tv ->> 'type', ''), m.dv ->> 'type')) as type_id,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.tv ->> 'config') as config_id,
           (select a.code from public.airports a where a.code = case when m.tv is not null then m.tv ->> 'base' else m.dv ->> 'base' end) as base,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.dv ->> 'config') as order_config_id,
           (select a.code from public.airports a where a.code = m.dv ->> 'base') as order_base
      from m left join public.aircraft old on old.world_id = w and old.registration = m.reg
     where m.airline_id is not null)
  insert into public.aircraft as x (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, base_code, status,
                                    ordered_on, delivery_at, order_base_code, order_config_id, order_note, checked_on,
                                    schedule_changed_on, maintenance_note, extra)
  select w, src.airline_id, src.reg, src.type_id, src.config_id, src.base,
         case when src.tv is not null then 'active' when src.delivery_at <= now() then 'delivered' else 'on_order' end,
         private.json_date(src.dv -> 'date'), src.delivery_at, src.order_base, src.order_config_id, src.dv ->> 'plan',
         private.json_date(src.tv -> 'checkedOn'), private.json_date(src.tv -> 'schedChangedOn'), src.tv ->> 'maint',
         jsonb_strip_nulls(jsonb_build_object(
           'tails_index', src.ti, 'deliveries_index', src.di,
           'tail', case when src.tv is not null then nullif(private.planner_extra(src.tv, k_tail, src.old_extra -> 'tail'), '{}'::jsonb) end,
           'delivery', case when src.dv is not null then nullif(private.planner_extra(src.dv, k_delivery, src.old_extra -> 'delivery'), '{}'::jsonb) end))
    from src order by coalesce(src.ti, 100000 + src.di)
  on conflict (world_id, registration) do update set airline_id = excluded.airline_id,
    aircraft_type_id = excluded.aircraft_type_id, cabin_config_id = excluded.cabin_config_id, base_code = excluded.base_code,
    status = excluded.status, ordered_on = excluded.ordered_on, delivery_at = excluded.delivery_at,
    order_base_code = excluded.order_base_code, order_config_id = excluded.order_config_id, order_note = excluded.order_note,
    checked_on = excluded.checked_on, schedule_changed_on = excluded.schedule_changed_on,
    maintenance_note = excluded.maintenance_note, retired_on = null, extra = excluded.extra
  where (x.airline_id, x.aircraft_type_id, x.cabin_config_id, x.base_code, x.status, x.ordered_on, x.delivery_at,
         x.order_base_code, x.order_config_id, x.order_note, x.checked_on, x.schedule_changed_on, x.maintenance_note,
         x.retired_on, x.extra)
        is distinct from (excluded.airline_id, excluded.aircraft_type_id, excluded.cabin_config_id, excluded.base_code,
                          excluded.status, excluded.ordered_on, excluded.delivery_at, excluded.order_base_code,
                          excluded.order_config_id, excluded.order_note, excluded.checked_on, excluded.schedule_changed_on,
                          excluded.maintenance_note, null::date, excluded.extra);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft', n);

  -- "keep this cabin" decisions (cabinKeep, keyed "REG|Cabin")
  with src as (
    select a.id as aircraft_id, substr(e.key, strpos(e.key, '|') + 1) as cabin, private.json_date(e.value -> 'date') as decided_on
      from jsonb_each(case when jsonb_typeof(s -> 'cabinKeep') = 'object' then s -> 'cabinKeep' else '{}'::jsonb end) e
      join public.aircraft a on a.world_id = w and a.registration = split_part(e.key, '|', 1)
     where substr(e.key, strpos(e.key, '|') + 1) in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort'))
  insert into public.aircraft_cabin_keeps as x (world_id, aircraft_id, cabin, decided_on)
  select w, src.aircraft_id, src.cabin, src.decided_on from src
  on conflict (aircraft_id, cabin) do update set decided_on = excluded.decided_on where x.decided_on is distinct from excluded.decided_on;
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft_cabin_keeps', n);
  delete from public.aircraft_cabin_keeps x
   where x.world_id = w
     and not exists (select 1 from public.aircraft a
                      where a.id = x.aircraft_id
                        and coalesce(case when jsonb_typeof(s -> 'cabinKeep') = 'object' then s -> 'cabinKeep' end, '{}'::jsonb)
                            ? (a.registration || '|' || x.cabin));
  return v_out;
end
$function$;

-- ---------- 4d. routes, rotations and flight legs (design §3.4, §4)
-- Routes: the research (planner_data.routes), the routes added in the planner, their edits and cabins, and any route a
-- frequency or fare plan names that neither list has. A frequency becomes a rotation and two legs in UTC: the outbound's
-- local weekdays and times at the hub, the return's from the old planner's rule (it leaves on the local day the outbound
-- arrives, or the next day if it departs earlier than that arrival), and block times from the typed times.
create or replace function private.load_planner_network(p_world_id bigint, s jsonb, d jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
  k_freq text[] := array['id', 'routeKey', 'days', 'tail', 'noOut', 'noBack', 'depHub', 'arrDest', 'depDest', 'arrHub',
                         'service', 'price', 'launched', 'notes'];
begin
  -- ---- routes
  with research as (
    select v, e.ord from jsonb_array_elements(case when jsonb_typeof(d -> 'routes') = 'array' then d -> 'routes' else '[]'::jsonb end) with ordinality as e(v, ord)
     where jsonb_typeof(v) = 'array'),
  added as (
    select v, e.ord from jsonb_array_elements(case when jsonb_typeof(s -> 'routesAdded') = 'array' then s -> 'routesAdded' else '[]'::jsonb end) with ordinality as e(v, ord)
     where jsonb_typeof(v) = 'array'),
  edits as (select e.key, e.value as v from jsonb_each(case when jsonb_typeof(s -> 'routeEdits') = 'object' then s -> 'routeEdits' else '{}'::jsonb end) e
             where jsonb_typeof(e.value) = 'object'),
  cabins as (select e.key, e.value #>> '{}' as cabin from jsonb_each(case when jsonb_typeof(s -> 'routeCabin') = 'object' then s -> 'routeCabin' else '{}'::jsonb end) e),
  named as (
    select f ->> 'routeKey' as key from jsonb_array_elements(case when jsonb_typeof(s -> 'freqs') = 'array' then s -> 'freqs' else '[]'::jsonb end) f
    union select f ->> 'routeKey' from jsonb_array_elements(case when jsonb_typeof(s -> 'farePlan') = 'array' then s -> 'farePlan' else '[]'::jsonb end) f),
  listed as (
    select (v ->> 0) || '|' || (v ->> 1) || '|' || (v ->> 2) as key, v, 0 as rank, ord, 'research' as source from research
    union all
    select (v ->> 0) || '|' || (v ->> 1) || '|' || (v ->> 2), v, 1, ord, 'added' from added),
  -- one entry per route: what the planner added wins over the research, as the planner's routeMap has it
  best as (select distinct on (key) key, v, rank, ord, source from listed order by key, rank desc, ord),
  keys as (
    select key from best union select key from edits union select key from cabins union select key from named where key is not null),
  src as (
    select k.key, al.id as airline_id, split_part(k.key, '|', 2) as hub, split_part(k.key, '|', 3) as dest, b.v, b.source,
           coalesce(b.rank, 2) as rank, coalesce(b.ord, 0) as ord, e.v as edit, c.cabin
      from keys k
      join public.airlines al on al.world_id = w and al.planner_name = split_part(k.key, '|', 1)
      left join best b on b.key = k.key
      left join edits e on e.key = k.key
      left join cabins c on c.key = k.key
     where exists (select 1 from public.airports a where a.code = split_part(k.key, '|', 2))
       and exists (select 1 from public.airports a where a.code = split_part(k.key, '|', 3))
       and split_part(k.key, '|', 4) = '')
  insert into public.routes as x (world_id, airline_id, hub_code, dest_code, city, country_label, distance_km, market_id, stars,
                                  source, removed, removed_note, city_override, distance_override_km, market_override_id,
                                  stars_override, cabin_choice)
  select w, src.airline_id, src.hub, src.dest, src.v ->> 3, src.v ->> 4,
         (select v::int from private.json_int(src.v -> 5) v where abs(v) < 2000000000),
         (select m.id from public.markets m where m.airline_id = src.airline_id and m.name = src.v ->> 6),
         (select v::smallint from private.json_int(src.v -> 7) v where abs(v) < 32000),
         coalesce(src.source, 'research'), coalesce(src.edit -> 'removed' = 'true'::jsonb, false), src.edit ->> 'note',
         src.edit ->> 'city', (select v::int from private.json_int(src.edit -> 'dist') v where abs(v) < 2000000000),
         (select m.id from public.markets m where m.airline_id = src.airline_id and m.name = src.edit ->> 'market'),
         (select v::smallint from private.json_int(src.edit -> 'stars') v where abs(v) < 32000),
         case when src.cabin in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort') then src.cabin end
    from src order by src.rank, src.ord, src.key
  on conflict (airline_id, hub_code, dest_code) do update set city = excluded.city, country_label = excluded.country_label,
    distance_km = excluded.distance_km, market_id = excluded.market_id, stars = excluded.stars, source = excluded.source,
    removed = excluded.removed, removed_note = excluded.removed_note, city_override = excluded.city_override,
    distance_override_km = excluded.distance_override_km, market_override_id = excluded.market_override_id,
    stars_override = excluded.stars_override, cabin_choice = excluded.cabin_choice
  where (x.city, x.country_label, x.distance_km, x.market_id, x.stars, x.source, x.removed, x.removed_note, x.city_override,
         x.distance_override_km, x.market_override_id, x.stars_override, x.cabin_choice)
        is distinct from (excluded.city, excluded.country_label, excluded.distance_km, excluded.market_id, excluded.stars,
                          excluded.source, excluded.removed, excluded.removed_note, excluded.city_override,
                          excluded.distance_override_km, excluded.market_override_id, excluded.stars_override,
                          excluded.cabin_choice);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes', n);

  -- ---- frequencies: each one's times worked out once, in minutes
  if to_regclass('pg_temp.t_load_freqs') is null then
    create temporary table t_load_freqs (
    legacy_key text primary key, ord bigint, v jsonb, airline_id bigint, route_id bigint, hub text, dest text,
    aircraft_id bigint, old_extra jsonb, l1_days smallint[], l1_dep smallint, l1_block smallint, l2_days smallint[],
    l2_dep smallint, l2_block smallint) on commit drop;
  end if;
  truncate pg_temp.t_load_freqs;
  insert into pg_temp.t_load_freqs
  select y.k, y.ord, y.v, y.airline_id, y.route_id, y.hub_code, y.dest_code, y.aircraft_id, y.old_extra,
         private.shift_weekdays(y.days_local, y.s1), y.l1_dep, y.out_block,
         private.shift_weekdays(private.shift_weekdays(y.days_local, y.back_day), y.s2), y.l2_dep, y.l2_block
    from (
      select x.*,
             case when x.dep_h is not null then ((x.dep_h - x.oh) % 1440 + 1440) % 1440 end as l1_dep,
             case when x.dep_h is not null then floor((x.dep_h - x.oh) / 1440.0)::int else 0 end as s1,
             -- the return's day after the outbound's local day (the old planner's computeFreq): the outbound's arrival
             -- day, or the next one if the return departs earlier than that arrival
             case when x.dep_h is not null and x.out_block is not null and x.dep_d is not null
                  then floor((x.dep_h + x.out_block + x.od - x.oh) / 1440.0)::int
                       + case when x.dep_d < (((x.dep_h + x.out_block + x.od - x.oh) % 1440) + 1440) % 1440 then 1 else 0 end
                  else 0 end as back_day,
             case when x.dep_d is not null then ((x.dep_d - x.od) % 1440 + 1440) % 1440 end as l2_dep,
             case when x.dep_d is not null then floor((x.dep_d - x.od) / 1440.0)::int else 0 end as s2,
             case when x.dep_d is not null and x.arr_h is not null then ((x.arr_h - x.dep_d - (x.oh - x.od)) % 1440 + 1440) % 1440 end as l2_block
        from (
          select f.k, f.ord, f.v, al.id as airline_id, ro.id as route_id, ro.hub_code, ro.dest_code, ac.id as aircraft_id,
                 old.extra as old_extra, coalesce(private.weekday_set(f.v ->> 'days'), '{1,2,3,4,5,6,7}') as days_local,
                 t.dep_h, t.arr_d, t.dep_d, t.arr_h, o.oh, o.od,
                 case when t.dep_h is not null and t.arr_d is not null
                      then ((t.arr_d - t.dep_h - (o.od - o.oh)) % 1440 + 1440) % 1440 end as out_block
            from (select distinct on (v ->> 'id') v ->> 'id' as k, v, e.ord
                    from jsonb_array_elements(case when jsonb_typeof(s -> 'freqs') = 'array' then s -> 'freqs' else '[]'::jsonb end) with ordinality as e(v, ord)
                   where jsonb_typeof(v) = 'object' and coalesce(v ->> 'id', '') <> ''
                   order by v ->> 'id', e.ord) f
            join public.airlines al on al.world_id = w and al.planner_name = split_part(f.v ->> 'routeKey', '|', 1)
            join public.routes ro on ro.airline_id = al.id and ro.hub_code = split_part(f.v ->> 'routeKey', '|', 2)
                                 and ro.dest_code = split_part(f.v ->> 'routeKey', '|', 3)
            left join public.aircraft ac on ac.world_id = w and ac.registration = f.v ->> 'tail'
            left join public.rotations old on old.world_id = w and old.legacy_key = f.k
            left join public.airports ah on ah.code = ro.hub_code
            left join public.world_airports wh on wh.world_id = w and wh.airport_code = ro.hub_code
            left join public.airports ad on ad.code = ro.dest_code
            left join public.world_airports wd on wd.world_id = w and wd.airport_code = ro.dest_code
            -- each end's offset in minutes; an airport whose offset isn't known counts as UTC, as the planner counts it
            cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                                       round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
            cross join lateral (select private.clock_min(f.v ->> 'depHub') as dep_h, private.clock_min(f.v ->> 'arrDest') as arr_d,
                                       private.clock_min(f.v ->> 'depDest') as dep_d, private.clock_min(f.v ->> 'arrHub') as arr_h) t
          ) x) y;

  -- a rotation moving to another route takes its legs with it: they are written again below
  delete from public.flight_legs l using public.rotations r, pg_temp.t_load_freqs f
   where l.rotation_id = r.id and r.world_id = w and r.legacy_key = f.legacy_key and r.route_id <> f.route_id;
  insert into public.rotations as x (world_id, airline_id, route_id, legacy_key, service_code, fare_pct, launched_on, note, extra)
  select w, f.airline_id, f.route_id, f.legacy_key, f.v ->> 'service',
         (select v from private.json_num(f.v -> 'price') v where abs(v) < 10000), private.json_date(f.v -> 'launched'),
         f.v ->> 'notes', private.planner_extra(f.v, k_freq, f.old_extra)
    from pg_temp.t_load_freqs f order by f.ord
  on conflict (world_id, legacy_key) do update set airline_id = excluded.airline_id, route_id = excluded.route_id,
    service_code = excluded.service_code, fare_pct = excluded.fare_pct, launched_on = excluded.launched_on,
    note = excluded.note, extra = excluded.extra
  where (x.airline_id, x.route_id, x.service_code, x.fare_pct, x.launched_on, x.note, x.extra)
        is distinct from (excluded.airline_id, excluded.route_id, excluded.service_code, excluded.fare_pct,
                          excluded.launched_on, excluded.note, excluded.extra);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('rotations', n);

  insert into public.flight_legs as x (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id,
                                       days_utc, dep_utc_min, block_min)
  select w, f.airline_id, r.id, g.leg_no,
         (select v::int from private.json_int(f.v -> case g.leg_no when 1 then 'noOut' else 'noBack' end) v where v between 0 and 2000000000),
         case g.leg_no when 1 then f.hub else f.dest end, case g.leg_no when 1 then f.dest else f.hub end, f.aircraft_id,
         case g.leg_no when 1 then f.l1_days else f.l2_days end,
         case g.leg_no when 1 then f.l1_dep else f.l2_dep end,
         case g.leg_no when 1 then f.l1_block else f.l2_block end
    from pg_temp.t_load_freqs f
    join public.rotations r on r.world_id = w and r.legacy_key = f.legacy_key
    cross join (values (1::smallint), (2::smallint)) as g(leg_no)
   order by f.ord, g.leg_no
  on conflict (rotation_id, leg_no) do update set airline_id = excluded.airline_id, flight_no = excluded.flight_no,
    origin_code = excluded.origin_code, dest_code = excluded.dest_code, aircraft_id = excluded.aircraft_id,
    days_utc = excluded.days_utc, dep_utc_min = excluded.dep_utc_min, block_min = excluded.block_min
  where (x.airline_id, x.flight_no, x.origin_code, x.dest_code, x.aircraft_id, x.days_utc, x.dep_utc_min, x.block_min)
        is distinct from (excluded.airline_id, excluded.flight_no, excluded.origin_code, excluded.dest_code,
                          excluded.aircraft_id, excluded.days_utc, excluded.dep_utc_min, excluded.block_min);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('flight_legs', n);
  return v_out;
end
$function$;

-- ---------- 4e. plan cards, to-dos, the logs, fare plan, interline, monthly checks, dismissed alerts (design §3.5, §3.6)
create or replace function private.load_planner_work(p_world_id bigint, s jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
  k_plan text[] := array['base', 'title', 'note', 'legs'];
  k_todo text[] := array['id', 'title', 'date', 'done', 'doneAt', 'created', 'note', 'items'];
  k_fare text[] := array['id', 'airline', 'routeKey', 'cls', 'pct', 'from', 'proposed', 'status', 'why'];
begin
  -- ---- plan cards (plans, keyed by registration) and their legs, in UTC like flight legs
  with src as (
    select e.key as reg, e.value as v, a.id as aircraft_id, a.airline_id, old.extra as old_extra
      from jsonb_each(case when jsonb_typeof(s -> 'plans') = 'object' then s -> 'plans' else '{}'::jsonb end) e
      join public.aircraft a on a.world_id = w and a.registration = e.key
      left join public.plan_cards old on old.aircraft_id = a.id
     where jsonb_typeof(e.value) = 'object')
  insert into public.plan_cards as x (world_id, airline_id, aircraft_id, base_code, title, note, extra)
  select w, src.airline_id, src.aircraft_id, (select a.code from public.airports a where a.code = src.v ->> 'base'),
         src.v ->> 'title', src.v ->> 'note', private.planner_extra(src.v, k_plan, src.old_extra)
    from src order by src.reg
  on conflict (aircraft_id) do update set airline_id = excluded.airline_id, base_code = excluded.base_code,
    title = excluded.title, note = excluded.note, extra = excluded.extra
  where (x.airline_id, x.base_code, x.title, x.note, x.extra)
        is distinct from (excluded.airline_id, excluded.base_code, excluded.title, excluded.note, excluded.extra);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_cards', n);
  with src as (
    select p.id as plan_card_id, (e.ord)::int as position, l,
           (select a.code from public.airports a where a.code = l ->> 'from') as origin,
           (select a.code from public.airports a where a.code = l ->> 'to') as dest
      from jsonb_each(case when jsonb_typeof(s -> 'plans') = 'object' then s -> 'plans' else '{}'::jsonb end) pe
      join public.aircraft a on a.world_id = w and a.registration = pe.key
      join public.plan_cards p on p.aircraft_id = a.id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(pe.value -> 'legs') = 'array' then pe.value -> 'legs' else '[]'::jsonb end) with ordinality as e(l, ord)
     where jsonb_typeof(l) = 'object'),
  timed as (
    select src.*, private.clock_min(src.l ->> 'dep') as dep,
           (select m[1]::int * 60 + m[2]::int from regexp_match(btrim(src.l ->> 'block'), '^(\d{1,3}):([0-5]\d)$') m) as block,
           round(coalesce(wo.utc_offset_override, ao.utc_offset, 0) * 60)::int as oo
      from src
      left join public.airports ao on ao.code = src.origin
      left join public.world_airports wo on wo.world_id = w and wo.airport_code = src.origin)
  insert into public.plan_card_legs as x (world_id, plan_card_id, position, flight_no, origin_code, dest_code, dep_utc_min,
                                          block_min, service_code)
  select w, t.plan_card_id, t.position,
         (select v::int from private.json_int(t.l -> 'no') v where v between 0 and 2000000000), t.origin, t.dest,
         case when t.dep is not null then ((t.dep - t.oo) % 1440 + 1440) % 1440 end,
         case when t.block < 32000 then t.block end, t.l ->> 'svc'
    from timed t order by t.plan_card_id, t.position
  on conflict (plan_card_id, position) do update set flight_no = excluded.flight_no, origin_code = excluded.origin_code,
    dest_code = excluded.dest_code, dep_utc_min = excluded.dep_utc_min, block_min = excluded.block_min,
    service_code = excluded.service_code
  where (x.flight_no, x.origin_code, x.dest_code, x.dep_utc_min, x.block_min, x.service_code)
        is distinct from (excluded.flight_no, excluded.origin_code, excluded.dest_code, excluded.dep_utc_min,
                          excluded.block_min, excluded.service_code);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_card_legs', n);
  delete from public.plan_card_legs x using public.plan_cards p, public.aircraft a
   where x.plan_card_id = p.id and p.world_id = w and a.id = p.aircraft_id
     and x.position > coalesce(jsonb_array_length(case when jsonb_typeof(s #> array['plans', a.registration, 'legs']) = 'array'
                                                       then s #> array['plans', a.registration, 'legs'] end), 0);

  -- ---- to-dos and their steps
  with src as (
    select distinct on (v ->> 'id') v ->> 'id' as k, v, e.ord
      from jsonb_array_elements(case when jsonb_typeof(s -> 'todos') = 'array' then s -> 'todos' else '[]'::jsonb end) with ordinality as e(v, ord)
     where jsonb_typeof(v) = 'object' and coalesce(v ->> 'id', '') <> ''
     order by v ->> 'id', e.ord)
  insert into public.todos as x (world_id, legacy_key, title, due_on, done, done_at, note, created_at, extra)
  select w, src.k, coalesce(src.v ->> 'title', ''), private.json_date(src.v -> 'date'), coalesce(src.v -> 'done' = 'true'::jsonb, false),
         private.json_ts(src.v -> 'doneAt'), src.v ->> 'note',
         -- a to-do with no creation time of its own keeps the one it was first loaded with
         coalesce(private.json_ts(src.v -> 'created'), old.created_at, now()),
         private.planner_extra(src.v, k_todo, old.extra)
    from src left join public.todos old on old.world_id = w and old.legacy_key = src.k
   order by src.ord
  on conflict (world_id, legacy_key) do update set title = excluded.title, due_on = excluded.due_on, done = excluded.done,
    done_at = excluded.done_at, note = excluded.note, created_at = excluded.created_at, extra = excluded.extra
  where (x.title, x.due_on, x.done, x.done_at, x.note, x.created_at, x.extra)
        is distinct from (excluded.title, excluded.due_on, excluded.done, excluded.done_at, excluded.note,
                          excluded.created_at, excluded.extra);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todos', n);
  with src as (
    select t.id as todo_id, (e.ord)::int as position, case when jsonb_typeof(i) = 'string' then i #>> '{}' else i::text end as body
      from jsonb_array_elements(case when jsonb_typeof(s -> 'todos') = 'array' then s -> 'todos' else '[]'::jsonb end) v
      join public.todos t on t.world_id = w and t.legacy_key = v ->> 'id'
      cross join lateral jsonb_array_elements(case when jsonb_typeof(v -> 'items') = 'array' then v -> 'items' else '[]'::jsonb end) with ordinality as e(i, ord))
  insert into public.todo_items as x (world_id, todo_id, position, body)
  select w, src.todo_id, src.position, src.body from src order by src.todo_id, src.position
  on conflict (todo_id, position) do update set body = excluded.body where x.body is distinct from excluded.body;
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todo_items', n);
  delete from public.todo_items x using public.todos t
   where x.todo_id = t.id and t.world_id = w
     and x.position > coalesce((select jsonb_array_length(v -> 'items')
                                  from jsonb_array_elements(case when jsonb_typeof(s -> 'todos') = 'array' then s -> 'todos' else '[]'::jsonb end) v
                                 where v ->> 'id' = t.legacy_key and jsonb_typeof(v -> 'items') = 'array' limit 1), 0);

  -- ---- growth moves (growthLog) and money spent (capex): no ids, so identical entries are interchangeable (design §8)
  if to_regclass('pg_temp.t_load_log') is null then
    create temporary table t_load_log (kind text, ord bigint, airline_id bigint, day date, a text, b numeric,
                                                    note text, aircraft_id bigint, occ bigint) on commit drop;
  end if;
  truncate pg_temp.t_load_log;
  insert into pg_temp.t_load_log
  select 'growth', e.ord, al.id, private.json_date(v -> 'date'), v ->> 'move', null, v ->> 'note', null, null
    from jsonb_array_elements(case when jsonb_typeof(s -> 'growthLog') = 'array' then s -> 'growthLog' else '[]'::jsonb end) with ordinality as e(v, ord)
    join public.airlines al on al.world_id = w and al.planner_name = v ->> 'airline'
   where v ->> 'move' in ('big', 'freq', 'feeder') and private.json_date(v -> 'date') is not null;
  insert into pg_temp.t_load_log
  select 'spending', e.ord, al.id, private.json_date(v -> 'date'),
         -- the orders were logged without a kind (design §3.6)
         case when v ->> 'kind' in ('order', 'cabin', 'loss') then v ->> 'kind' else 'order' end,
         round(private.json_num(v -> 'amountM') * 1000000, 2), v ->> 'note',
         -- the aircraft, where the note starts with one of the airline's registrations
         (select a.id from public.aircraft a where a.world_id = w and a.airline_id = al.id
             and a.registration = split_part(btrim(coalesce(v ->> 'note', '')), ' ', 1)), null
    from jsonb_array_elements(case when jsonb_typeof(s -> 'capex') = 'array' then s -> 'capex' else '[]'::jsonb end) with ordinality as e(v, ord)
    join public.airlines al on al.world_id = w and al.planner_name = v ->> 'airline'
   where private.json_date(v -> 'date') is not null and abs(private.json_num(v -> 'amountM')) < 1000000;
  update pg_temp.t_load_log l set occ = x.occ
    from (select kind, ord, row_number() over (partition by kind, airline_id, day, a, b, note order by ord) as occ from pg_temp.t_load_log) x
   where x.kind = l.kind and x.ord = l.ord;
  with cur as (select g.*, row_number() over (partition by g.airline_id, g.logged_on, g.move, g.note order by g.id) as occ
                 from public.growth_log g where g.world_id = w)
  delete from public.growth_log g using cur
   where g.id = cur.id
     and not exists (select 1 from pg_temp.t_load_log l
                      where l.kind = 'growth' and (l.airline_id, l.day, l.a, l.note, l.occ)
                                                  is not distinct from (cur.airline_id, cur.logged_on, cur.move, cur.note, cur.occ));
  insert into public.growth_log (world_id, airline_id, logged_on, move, note)
  select w, l.airline_id, l.day, l.a, l.note from pg_temp.t_load_log l
   where l.kind = 'growth'
     and not exists (select 1 from (select g.*, row_number() over (partition by g.airline_id, g.logged_on, g.move, g.note order by g.id) as occ
                                      from public.growth_log g where g.world_id = w) cur
                      where (cur.airline_id, cur.logged_on, cur.move, cur.note, cur.occ)
                            is not distinct from (l.airline_id, l.day, l.a, l.note, l.occ))
   order by l.ord;
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('growth_log', n);
  with cur as (select s2.*, row_number() over (partition by s2.airline_id, s2.spent_on, s2.kind, s2.amount, s2.note order by s2.id) as occ
                 from public.spending_log s2 where s2.world_id = w)
  delete from public.spending_log x using cur
   where x.id = cur.id
     and not exists (select 1 from pg_temp.t_load_log l
                      where l.kind = 'spending' and (l.airline_id, l.day, l.a, l.b, l.note, l.occ)
                                                    is not distinct from (cur.airline_id, cur.spent_on, cur.kind, cur.amount, cur.note, cur.occ));
  insert into public.spending_log (world_id, airline_id, spent_on, amount, kind, aircraft_id, note)
  select w, l.airline_id, l.day, l.b, l.a, l.aircraft_id, l.note from pg_temp.t_load_log l
   where l.kind = 'spending'
     and not exists (select 1 from (select s2.*, row_number() over (partition by s2.airline_id, s2.spent_on, s2.kind, s2.amount, s2.note order by s2.id) as occ
                                      from public.spending_log s2 where s2.world_id = w) cur
                      where (cur.airline_id, cur.spent_on, cur.kind, cur.amount, cur.note, cur.occ)
                            is not distinct from (l.airline_id, l.day, l.a, l.b, l.note, l.occ))
   order by l.ord;
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('spending_log', n);
  update public.spending_log x set aircraft_id = l.aircraft_id
    from (select s2.*, row_number() over (partition by s2.airline_id, s2.spent_on, s2.kind, s2.amount, s2.note order by s2.id) as occ
            from public.spending_log s2 where s2.world_id = w) cur
    join pg_temp.t_load_log l on l.kind = 'spending' and (l.airline_id, l.day, l.a, l.b, l.note, l.occ)
                                 is not distinct from (cur.airline_id, cur.spent_on, cur.kind, cur.amount, cur.note, cur.occ)
   where x.id = cur.id and x.aircraft_id is distinct from l.aircraft_id;

  -- ---- fare plan
  with src as (
    select distinct on (v ->> 'id') v ->> 'id' as k, v, e.ord
      from jsonb_array_elements(case when jsonb_typeof(s -> 'farePlan') = 'array' then s -> 'farePlan' else '[]'::jsonb end) with ordinality as e(v, ord)
     where jsonb_typeof(v) = 'object' and coalesce(v ->> 'id', '') <> ''
     order by v ->> 'id', e.ord)
  insert into public.fare_plan as x (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from,
                                     proposed_on, status, reason, extra)
  select w, al.id,
         (select r.id from public.routes r join public.airlines ra on ra.id = r.airline_id
           where r.world_id = w and ra.planner_name || '|' || r.hub_code || '|' || r.dest_code = src.v ->> 'routeKey'),
         src.k, case when src.v ->> 'cls' in ('economy', 'business', 'first') then src.v ->> 'cls' end,
         (select v from private.json_num(src.v -> 'pct') v where abs(v) < 10000),
         (select v from private.json_num(src.v -> 'from') v where abs(v) < 1000000000000),
         private.json_date(src.v -> 'proposed'), case when src.v ->> 'status' = 'dropped' then 'dropped' else 'planned' end,
         src.v ->> 'why', private.planner_extra(src.v, k_fare, old.extra)
    from src
    join public.airlines al on al.world_id = w and al.planner_name = src.v ->> 'airline'
    left join public.fare_plan old on old.world_id = w and old.legacy_key = src.k
   order by src.ord
  on conflict (world_id, legacy_key) do update set airline_id = excluded.airline_id, route_id = excluded.route_id,
    cabin_class = excluded.cabin_class, change_pct = excluded.change_pct, fare_from = excluded.fare_from,
    proposed_on = excluded.proposed_on, status = excluded.status, reason = excluded.reason, extra = excluded.extra
  where (x.airline_id, x.route_id, x.cabin_class, x.change_pct, x.fare_from, x.proposed_on, x.status, x.reason, x.extra)
        is distinct from (excluded.airline_id, excluded.route_id, excluded.cabin_class, excluded.change_pct,
                          excluded.fare_from, excluded.proposed_on, excluded.status, excluded.reason, excluded.extra);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('fare_plan', n);

  -- ---- interline, keyed "Airline|country": the planner's "requested" is to_sign
  with src as (
    select al.id as airline_id, substr(e.key, strpos(e.key, '|') + 1) as cc, e.value as v
      from jsonb_each(case when jsonb_typeof(s -> 'interline') = 'object' then s -> 'interline' else '{}'::jsonb end) e
      join public.airlines al on al.world_id = w and al.planner_name = split_part(e.key, '|', 1)
     where jsonb_typeof(e.value) = 'object' and exists (select 1 from public.countries c where c.code = substr(e.key, strpos(e.key, '|') + 1)))
  insert into public.interline_agreements as x (world_id, airline_id, country_code, status, partner, decided_on, note)
  select w, src.airline_id, src.cc,
         case when src.v ->> 'status' in ('signed', 'declined', 'nopartner') then src.v ->> 'status' else 'to_sign' end,
         src.v ->> 'partner', private.json_date(src.v -> 'date'), src.v ->> 'notes'
    from src
  on conflict (airline_id, country_code) do update set status = excluded.status, partner = excluded.partner,
    decided_on = excluded.decided_on, note = excluded.note
  where (x.status, x.partner, x.decided_on, x.note) is distinct from (excluded.status, excluded.partner, excluded.decided_on, excluded.note);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('interline_agreements', n);

  -- ---- monthly checks: "Equinox" is the group as a whole
  with src as (
    select case when m.key = 'Equinox' then null else al.id end as airline_id, t.key as task, private.json_date(t.value) as day
      from jsonb_each(case when jsonb_typeof(s -> 'monthly') = 'object' then s -> 'monthly' else '{}'::jsonb end) m
      left join public.airlines al on al.world_id = w and al.planner_name = m.key
      cross join lateral jsonb_each(case when jsonb_typeof(m.value) = 'object' then m.value else '{}'::jsonb end) t
     where m.key = 'Equinox' or al.id is not null)
  insert into public.monthly_checks as x (world_id, airline_id, task, last_done_on)
  select w, src.airline_id, src.task, src.day from src
  on conflict on constraint monthly_checks_world_airline_task_key do update set last_done_on = excluded.last_done_on
  where x.last_done_on is distinct from excluded.last_done_on;
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('monthly_checks', n);

  -- ---- Home's dismissed alerts
  insert into public.dismissals as x (world_id, alert_key, dismissed_on)
  select w, e.key, private.json_date(e.value)
    from jsonb_each(case when jsonb_typeof(s -> 'dismissed') = 'object' then s -> 'dismissed' else '{}'::jsonb end) e
  on conflict (world_id, alert_key) do update set dismissed_on = excluded.dismissed_on
  where x.dismissed_on is distinct from excluded.dismissed_on;
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('dismissals', n);
  return v_out;
end
$function$;

-- ---------- 4f. cash and next-7-day costs typed by hand, or kept from before the capture (design §8, §9 step 3)
-- Every stored figure the capture doesn't give back exactly (capture_cash, rounded as the planner rounds) becomes a
-- cash_entries row, in AS$. A figure the planner doesn't have yet, although the capture does, gets no row: the planner
-- copies the capture in itself when it next opens (applyCaptureCash), and the getter shows the capture's figure.
create or replace function private.load_planner_money(p_world_id bigint, s jsonb, p_saved_at timestamptz)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n int;
begin
  if to_regclass('pg_temp.t_load_cash') is null then
    create temporary table t_load_cash (airline_id bigint, day date, cash numeric, fixed_next7 numeric) on commit drop;
  end if;
  truncate pg_temp.t_load_cash;
  with st as (
    select al.id as airline_id, private.json_date(to_jsonb(d.key)) as day, private.json_num(x.value) as m
      from jsonb_each(case when jsonb_typeof(s -> 'cash') = 'object' then s -> 'cash' else '{}'::jsonb end) d
      cross join lateral jsonb_each(case when jsonb_typeof(d.value) = 'object' then d.value else '{}'::jsonb end) x
      join public.airlines al on al.world_id = w and al.planner_name = x.key),
  fx as (
    select al.id as airline_id, private.json_date(to_jsonb(d.key)) as day, private.json_num(x.value) as m
      from jsonb_each(case when jsonb_typeof(s -> 'fixed7') = 'object' then s -> 'fixed7' else '{}'::jsonb end) d
      cross join lateral jsonb_each(case when jsonb_typeof(d.value) = 'object' then d.value else '{}'::jsonb end) x
      join public.airlines al on al.world_id = w and al.planner_name = x.key),
  cap as (
    select cc.airline_id, cc.day, floor(cc.cash / 10000 + 0.5) / 100 as cash_m,
           case when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as fixed_m
      from public.capture_cash cc where cc.world_id = w),
  pairs as (
    select coalesce(st.airline_id, fx.airline_id, cap.airline_id) as airline_id, coalesce(st.day, fx.day, cap.day) as day,
           st.m as st_cash, fx.m as st_fixed, cap.cash_m, cap.fixed_m
      from st
      full join fx on fx.airline_id = st.airline_id and fx.day = st.day
      full join cap on cap.airline_id = coalesce(st.airline_id, fx.airline_id) and cap.day = coalesce(st.day, fx.day))
  insert into pg_temp.t_load_cash
  select p.airline_id, p.day,
         case when p.st_cash is not null and p.st_cash is distinct from p.cash_m then round(p.st_cash * 1000000, 2) end,
         case when p.st_fixed is not null and p.st_fixed is distinct from p.fixed_m then round(p.st_fixed * 1000000, 2) end
    from pairs p
   where p.day is not null and abs(coalesce(p.st_cash, 0)) < 1000000 and abs(coalesce(p.st_fixed, 0)) < 1000000;
  delete from pg_temp.t_load_cash where cash is null and fixed_next7 is null;
  insert into public.cash_entries as x (world_id, airline_id, day, cash, fixed_next7, entered_at)
  select w, c.airline_id, c.day, c.cash, c.fixed_next7, p_saved_at from pg_temp.t_load_cash c
  on conflict (airline_id, day) do update set cash = excluded.cash, fixed_next7 = excluded.fixed_next7
  where (x.cash, x.fixed_next7) is distinct from (excluded.cash, excluded.fixed_next7);
  get diagnostics n = row_count;
  delete from public.cash_entries x
   where x.world_id = w and not exists (select 1 from pg_temp.t_load_cash c where c.airline_id = x.airline_id and c.day = x.day);
  return jsonb_build_object('cash_entries', n);
end
$function$;

-- ---------- 4g. loads typed in the planner (design §8, §9 step 3)
-- For every day of planner_loads: each flight's figure the capture doesn't give back (a typed load, or one the capture
-- has since changed) becomes a load_entries row, and a captured flight the day doesn't show becomes a cleared one; a
-- day's flags become a load_days row when the planner saved the day, the capture didn't write it, or its done differs
-- from the capture's. They are stamped no earlier than the month's last write and the latest loads capture, so they win
-- over the capture as they did.
create or replace function private.load_planner_loads(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; n_entries int; n_days int;
begin
  if to_regclass('pg_temp.t_load_loads') is null then
    create temporary table t_load_loads (airline_id bigint, game_date date, flight_no int, eco_pct numeric,
                                                     entered_at timestamptz) on commit drop;
  end if;
  if to_regclass('pg_temp.t_load_days') is null then
    create temporary table t_load_days (game_date date, done boolean, saved_at_ms bigint, entered_at timestamptz) on commit drop;
  end if;
  truncate pg_temp.t_load_loads, pg_temp.t_load_days;
  with ours as (
    select a.id, a.planner_name, a.active from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  latest as (select max(f.loads_captured_at) as at from public.game_flights f join ours on ours.id = f.airline_id),
  months as (select pl.month, private.json_object_or_empty(pl.json) as j,
                    greatest(to_timestamp(pl.saved_at / 1000.0), (select at from latest)) as stamp
               from public.planner_loads pl),
  days as (select m.stamp, private.json_date(to_jsonb(e.key)) as day, e.value as v
             from months m cross join lateral jsonb_each(m.j) e
            where jsonb_typeof(e.value) = 'object' and private.json_date(to_jsonb(e.key)) is not null),
  stored as (
    select d.day, d.stamp, o.id as airline_id, private.json_int(to_jsonb(split_part(f.key, '|', 2))) as flight_no,
           private.json_num(f.value) as v
      from days d
      cross join lateral jsonb_each(case when jsonb_typeof(d.v -> 'f') = 'object' then d.v -> 'f' else '{}'::jsonb end) f
      join ours o on o.planner_name = split_part(f.key, '|', 1)),
  caught as (
    select f.airline_id, f.game_date as day, f.flight_no, max(f.eco_pct) as v
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.eco_pct is not null
     group by f.airline_id, f.game_date, f.flight_no)
  insert into pg_temp.t_load_loads
  select st.airline_id, st.day, st.flight_no, st.v, st.stamp
    from stored st
    left join caught c on c.airline_id = st.airline_id and c.day = st.day and c.flight_no = st.flight_no
   where st.flight_no between 0 and 2000000000 and abs(st.v) < 10000 and st.v is distinct from c.v
  union all
  select c.airline_id, c.day, c.flight_no, null, d.stamp
    from caught c join days d on d.day = c.day
   where not exists (select 1 from stored st where st.airline_id = c.airline_id and st.day = c.day and st.flight_no = c.flight_no);

  with ours as (
    select a.id, a.active from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  latest as (select max(f.loads_captured_at) as at from public.game_flights f join ours on ours.id = f.airline_id),
  days as (select greatest(to_timestamp(pl.saved_at / 1000.0), (select at from latest)) as stamp,
                  private.json_date(to_jsonb(e.key)) as day, e.value as v
             from public.planner_loads pl cross join lateral jsonb_each(private.json_object_or_empty(pl.json)) e
            where jsonb_typeof(e.value) = 'object' and private.json_date(to_jsonb(e.key)) is not null),
  judged as (
    select d.*,
           exists (select 1 from public.game_flights f join ours on ours.id = f.airline_id
                    where f.flight_no is not null and f.game_date = d.day) as captured,
           not exists (select 1 from ours o where o.active
                        and not exists (select 1 from public.game_flights f
                                         where f.airline_id = o.id and f.flight_no is not null and f.game_date = d.day)) as complete
      from days d)
  insert into pg_temp.t_load_days
  select j.day, coalesce(j.v -> 'done' = 'true'::jsonb, false), private.json_int(j.v -> 'savedAt'), j.stamp
    from judged j
   where j.v ? 'savedAt' or not j.captured or coalesce(j.v -> 'done' = 'true'::jsonb, false) <> j.complete;

  insert into public.load_entries as x (world_id, airline_id, game_date, flight_no, eco_pct, entered_at)
  select w, l.airline_id, l.game_date, l.flight_no, l.eco_pct, l.entered_at from pg_temp.t_load_loads l
  on conflict (airline_id, game_date, flight_no) do update set eco_pct = excluded.eco_pct, entered_at = excluded.entered_at
  where (x.eco_pct, x.entered_at) is distinct from (excluded.eco_pct, excluded.entered_at);
  get diagnostics n_entries = row_count;
  delete from public.load_entries x
   where x.world_id = w
     and not exists (select 1 from pg_temp.t_load_loads l
                      where l.airline_id = x.airline_id and l.game_date = x.game_date and l.flight_no = x.flight_no);
  insert into public.load_days as x (world_id, game_date, done, saved_at_ms, entered_at)
  select w, d.game_date, d.done, d.saved_at_ms, d.entered_at from pg_temp.t_load_days d
  on conflict (world_id, game_date) do update set done = excluded.done, saved_at_ms = excluded.saved_at_ms,
    entered_at = excluded.entered_at
  where (x.done, x.saved_at_ms, x.entered_at) is distinct from (excluded.done, excluded.saved_at_ms, excluded.entered_at);
  get diagnostics n_days = row_count;
  delete from public.load_days x
   where x.world_id = w and not exists (select 1 from pg_temp.t_load_days d where d.game_date = x.game_date);
  return jsonb_build_object('load_entries', n_entries, 'load_days', n_days);
end
$function$;

-- ---------- 4h. what the old planner no longer has: removed, or retired where the capture's flights still point at it
create or replace function private.load_planner_tidy(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; r jsonb := coalesce(s -> 'ref', '{}'::jsonb); n int; v_out jsonb := '{}'::jsonb;
begin
  -- the planner state's own lists
  delete from public.plan_cards p using public.aircraft a
   where p.world_id = w and a.id = p.aircraft_id
     and not (coalesce(case when jsonb_typeof(s -> 'plans') = 'object' then s -> 'plans' end, '{}'::jsonb) ? a.registration);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_cards', n);
  delete from public.rotations x
   where x.world_id = w and x.legacy_key is not null
     and not exists (select 1 from pg_temp.t_load_freqs f where f.legacy_key = x.legacy_key);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('rotations', n);
  delete from public.todos x
   where x.world_id = w and x.legacy_key is not null
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'todos') = 'array' then s -> 'todos' else '[]'::jsonb end) v
                      where v ->> 'id' = x.legacy_key);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todos', n);
  delete from public.fare_plan x
   where x.world_id = w and x.legacy_key is not null
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'farePlan') = 'array' then s -> 'farePlan' else '[]'::jsonb end) v
                      where v ->> 'id' = x.legacy_key);
  delete from public.interline_agreements x using public.airlines al
   where x.world_id = w and al.id = x.airline_id
     and not (coalesce(case when jsonb_typeof(s -> 'interline') = 'object' then s -> 'interline' end, '{}'::jsonb)
              ? (al.planner_name || '|' || x.country_code));
  delete from public.monthly_checks x
   where x.world_id = w
     and not exists (select 1 from jsonb_each(case when jsonb_typeof(s -> 'monthly') = 'object' then s -> 'monthly' else '{}'::jsonb end) m
                      where jsonb_typeof(m.value) = 'object' and m.value ? x.task
                        and m.key = coalesce((select al.planner_name from public.airlines al where al.id = x.airline_id), 'Equinox'));
  delete from public.dismissals x
   where x.world_id = w
     and not (coalesce(case when jsonb_typeof(s -> 'dismissed') = 'object' then s -> 'dismissed' end, '{}'::jsonb) ? x.alert_key);

  -- aircraft in neither list: removed, or retired while anything still points at them (the capture's flights and
  -- payments, money spent)
  update public.aircraft a set status = 'retired', retired_on = coalesce(a.retired_on, current_date),
         extra = a.extra - array['tails_index', 'deliveries_index', 'tail', 'delivery']
   where a.world_id = w and a.status <> 'retired'
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'tails') = 'array' then s -> 'tails' else '[]'::jsonb end) v where v ->> 'id' = a.registration)
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'deliveries') = 'array' then s -> 'deliveries' else '[]'::jsonb end) v where v ->> 'reg' = a.registration)
     and (exists (select 1 from public.game_flights f where f.aircraft_id = a.id)
          or exists (select 1 from public.game_payments p where p.aircraft_id = a.id)
          or exists (select 1 from public.spending_log x where x.aircraft_id = a.id));
  delete from public.aircraft a
   where a.world_id = w and a.status <> 'retired'
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'tails') = 'array' then s -> 'tails' else '[]'::jsonb end) v where v ->> 'id' = a.registration)
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'deliveries') = 'array' then s -> 'deliveries' else '[]'::jsonb end) v where v ->> 'reg' = a.registration)
     and not exists (select 1 from public.flight_legs l where l.aircraft_id = a.id)
     and not exists (select 1 from public.plan_cards p where p.aircraft_id = a.id);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft', n);

  -- routes no list names any more, unless something still points at them
  delete from public.routes x using public.airlines al
   where x.world_id = w and al.id = x.airline_id
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(d -> 'routes') = 'array' then d -> 'routes' else '[]'::jsonb end) v
                      where (v ->> 0, v ->> 1, v ->> 2) = (al.planner_name, x.hub_code, x.dest_code))
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'routesAdded') = 'array' then s -> 'routesAdded' else '[]'::jsonb end) v
                      where (v ->> 0, v ->> 1, v ->> 2) = (al.planner_name, x.hub_code, x.dest_code))
     and not (coalesce(case when jsonb_typeof(s -> 'routeEdits') = 'object' then s -> 'routeEdits' end, '{}'::jsonb) ? (al.planner_name || '|' || x.hub_code || '|' || x.dest_code))
     and not (coalesce(case when jsonb_typeof(s -> 'routeCabin') = 'object' then s -> 'routeCabin' end, '{}'::jsonb) ? (al.planner_name || '|' || x.hub_code || '|' || x.dest_code))
     and not exists (select 1 from public.rotations o where o.route_id = x.id)
     and not exists (select 1 from public.fare_plan o where o.route_id = x.id)
     and not exists (select 1 from public.game_flights o where o.route_id = x.id);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes', n);
  -- a route only the research had, once the planner no longer adds or edits it, is a research route again
  update public.routes x set source = 'research', removed = false, removed_note = null, city_override = null,
         distance_override_km = null, market_override_id = null, stars_override = null, cabin_choice = null
    from public.airlines al
   where x.world_id = w and al.id = x.airline_id
     and (x.source = 'added' or x.removed or x.removed_note is not null or x.city_override is not null
          or x.distance_override_km is not null or x.market_override_id is not null or x.stars_override is not null
          or x.cabin_choice is not null)
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s -> 'routesAdded') = 'array' then s -> 'routesAdded' else '[]'::jsonb end) v
                      where (v ->> 0, v ->> 1, v ->> 2) = (al.planner_name, x.hub_code, x.dest_code))
     and not (coalesce(case when jsonb_typeof(s -> 'routeEdits') = 'object' then s -> 'routeEdits' end, '{}'::jsonb) ? (al.planner_name || '|' || x.hub_code || '|' || x.dest_code))
     and not (coalesce(case when jsonb_typeof(s -> 'routeCabin') = 'object' then s -> 'routeCabin' end, '{}'::jsonb) ? (al.planner_name || '|' || x.hub_code || '|' || x.dest_code));

  -- reference rows the planner no longer lists, unless something still points at them
  update public.airline_bases x set parent_base_id = null
   where x.world_id = w and x.parent_base_id in (
     select b.id from public.airline_bases b join public.airlines al on al.id = b.airline_id
      where b.world_id = w
        and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r -> 'hubs') = 'array' then r -> 'hubs' else '[]'::jsonb end) h
                         where h ->> 'airline' = al.planner_name and h ->> 'code' = b.airport_code));
  delete from public.airline_bases b using public.airlines al
   where b.world_id = w and al.id = b.airline_id
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r -> 'hubs') = 'array' then r -> 'hubs' else '[]'::jsonb end) h
                      where h ->> 'airline' = al.planner_name and h ->> 'code' = b.airport_code);
  delete from public.service_profiles x
   where x.world_id = w
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r -> 'services') = 'array' then r -> 'services' else '[]'::jsonb end) v
                      where v ->> 'code' = x.code);
  delete from public.markets x using public.airlines al
   where x.world_id = w and al.id = x.airline_id
     and not (coalesce(case when jsonb_typeof(r -> 'markets') = 'object' then r -> 'markets' end, '{}'::jsonb) ? (al.planner_name || '|' || x.name))
     and not exists (select 1 from public.routes o where o.market_id = x.id or o.market_override_id = x.id);
  delete from public.cabin_configs x
   where x.world_id = w
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r -> 'configs') = 'array' then r -> 'configs' else '[]'::jsonb end) v
                      where v ->> 'code' = x.code)
     and not exists (select 1 from public.aircraft o where o.cabin_config_id = x.id or o.order_config_id = x.id)
     and not exists (select 1 from public.markets o where o.default_config_id = x.id);
  delete from public.aircraft_types x
   where x.world_id = w
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r -> 'types') = 'array' then r -> 'types' else '[]'::jsonb end) v
                      where v ->> 'name' = x.name)
     and not exists (select 1 from public.aircraft o where o.aircraft_type_id = x.id)
     and not exists (select 1 from public.cabin_configs o where o.aircraft_type_id = x.id)
     and not exists (select 1 from public.markets o where o.default_type_id = x.id)
     and not exists (select 1 from public.airline_aircraft_types o where o.aircraft_type_id = x.id);
  -- what the world says about airports the planner no longer mentions
  delete from public.world_airports x
   where x.world_id = w
     and not (coalesce(case when jsonb_typeof(p_mct) = 'object' then p_mct end, '{}'::jsonb) ? x.airport_code)
     and not (coalesce(case when jsonb_typeof(r -> 'curfews') = 'object' then r -> 'curfews' end, '{}'::jsonb) ? x.airport_code)
     and not (coalesce(case when jsonb_typeof(r -> 'utcOverrides') = 'object' then r -> 'utcOverrides' end, '{}'::jsonb) ? x.airport_code)
     and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r -> 'hubs') = 'array' then r -> 'hubs' else '[]'::jsonb end) h
                      where h ->> 'code' = x.airport_code);
  return v_out;
end
$function$;

-- ---------- 4i. what the columns can't give back exactly
-- Builds the document from the tables and compares it, item by item, with the old one. For a list item whose table has
-- an extra column (tails, deliveries, freqs, plans, todos, farePlan), a key that differs (beyond the differences design
-- §9 allows) is kept in extra as the old document has it, or as null where the old item has no such key, so the getter
-- gives it back. Returns how often each key was kept this way. Expected: none.
create or replace function private.load_planner_extra(p_world_id bigint, s jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint := p_world_id; g jsonb; v_out jsonb;
begin
  g := (public.planner_state_get(w) ->> 'json')::jsonb;
  if to_regclass('pg_temp.t_load_patch') is null then
    create temporary table t_load_patch (section text, item_key text, key text, value jsonb) on commit drop;
  end if;
  truncate pg_temp.t_load_patch;
  -- each old item beside the getter's item with the same id, and where it sits in the old document
  with items as (
    select sec.section, o.item_key, o.item as old, n.item as new, '$.' || sec.section || '[' || o.ord || ']' as prefix
      from (values ('tails', 'id'), ('deliveries', 'reg'), ('freqs', 'id'), ('todos', 'id'), ('farePlan', 'id')) as sec(section, id_key)
      cross join lateral (select e.v ->> sec.id_key as item_key, e.v as item, e.ord - 1 as ord
                            from jsonb_array_elements(case when jsonb_typeof(s -> sec.section) = 'array' then s -> sec.section else '[]'::jsonb end) with ordinality as e(v, ord)
                           where jsonb_typeof(e.v) = 'object') o
      join lateral (select e.v as item from jsonb_array_elements(coalesce(g -> sec.section, '[]'::jsonb)) as e(v)
                     where e.v ->> sec.id_key = o.item_key limit 1) n on true
    union all
    select 'plans', o.key, o.value, g -> 'plans' -> o.key, '$.plans.' || o.key
      from jsonb_each(case when jsonb_typeof(s -> 'plans') = 'object' then s -> 'plans' else '{}'::jsonb end) o
     where jsonb_typeof(o.value) = 'object' and g -> 'plans' ? o.key),
  -- the item's own key under which each real difference sits: a key whose value differs deeper down (one leg of a plan
  -- card) is kept whole
  keys as (
    select distinct i.section, i.item_key, i.old,
           (regexp_match(substr(df.path, length(i.prefix) + 2), '^([^.\[]+)'))[1] as key
      from items i cross join lateral private.planner_json_differences(i.old, i.new, i.prefix) df
     where df.kind = 'differs' and length(df.path) > length(i.prefix))
  insert into pg_temp.t_load_patch
  select k.section, k.item_key, k.key, coalesce(k.old -> k.key, 'null'::jsonb) from keys k where k.key is not null;
  update public.rotations r set extra = r.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_load_patch where section = 'freqs' group by item_key) p
   where r.world_id = w and r.legacy_key = p.item_key and (r.extra || p.patch) is distinct from r.extra;
  update public.todos t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_load_patch where section = 'todos' group by item_key) p
   where t.world_id = w and t.legacy_key = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.fare_plan t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_load_patch where section = 'farePlan' group by item_key) p
   where t.world_id = w and t.legacy_key = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.plan_cards t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_load_patch where section = 'plans' group by item_key) p,
         public.aircraft a
   where t.world_id = w and a.id = t.aircraft_id and a.registration = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.aircraft a set extra = jsonb_set(a.extra, '{tail}', coalesce(a.extra -> 'tail', '{}'::jsonb) || p.patch)
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_load_patch where section = 'tails' group by item_key) p
   where a.world_id = w and a.registration = p.item_key and (coalesce(a.extra -> 'tail', '{}'::jsonb) || p.patch) is distinct from a.extra -> 'tail';
  update public.aircraft a set extra = jsonb_set(a.extra, '{delivery}', coalesce(a.extra -> 'delivery', '{}'::jsonb) || p.patch)
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_load_patch where section = 'deliveries' group by item_key) p
   where a.world_id = w and a.registration = p.item_key and (coalesce(a.extra -> 'delivery', '{}'::jsonb) || p.patch) is distinct from a.extra -> 'delivery';
  select coalesce(jsonb_object_agg(section || '.' || key, n), '{}'::jsonb) into v_out
    from (select section, key, count(*) as n from pg_temp.t_load_patch group by section, key) x;
  return v_out;
end
$function$;

-- ---------- 4j. the loader
-- Fills a world's planner tables from the old planner's storage (only the default world has any): planner_state,
-- planner_loads, planner_data, site_content.mct, planner_meta.growthRules and the planner's code constants. Runs as
-- migration with the change log off (design §6, §9). Run again, it brings the tables in line with today's
-- planner_state: rows are added, changed or removed as needed, ids that exist are kept, and nothing that didn't change
-- is touched. Returns how many rows each step wrote and which keys went to extra.
create or replace function private.load_planner(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare w bigint; s jsonb; d jsonb; v_mct jsonb; v_growth jsonb; v_saved timestamptz; v_out jsonb := '{}'::jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
  v_log text := current_setting('equinox.change_log', true);
begin
  select x.id into w from public.worlds x where x.id = p_world_id and x.is_default;
  if w is null then
    raise exception 'load_planner: world % isn''t the default world, and only the default world has old planner storage', p_world_id;
  end if;
  perform set_config('equinox.actor', 'migration', true), set_config('equinox.actor_detail', 'private.load_planner', true),
          set_config('equinox.change_log', 'off', true);

  select private.json_object_or_empty(p.json), to_timestamp(p.saved_at / 1000.0) into s, v_saved
    from public.planner_state p where p.id = 'main';
  s := coalesce(s, '{}'::jsonb);
  select x.value into d from public.planner_data x where x.key = 'DATA';
  d := case when jsonb_typeof(d) = 'object' then d else '{}'::jsonb end;
  select x.value into v_mct from public.site_content x where x.key = 'mct';
  select x.value into v_growth from public.planner_meta x where x.key = 'growthRules';
  v_growth := case when jsonb_typeof(v_growth) = 'object' then v_growth else '{}'::jsonb end;

  v_out := v_out || jsonb_build_object('places', private.load_planner_places(w, s, d, v_mct));
  -- the events' due times, now that the home airports' offsets are known: the cash comparison needs them
  perform private.fill_due_at(a.id) from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = w and g.kind = 'ours';
  v_out := v_out || jsonb_build_object('reference', private.load_planner_reference(w, s, v_growth));
  v_out := v_out || jsonb_build_object('fleet', private.load_planner_fleet(w, s));
  v_out := v_out || jsonb_build_object('network', private.load_planner_network(w, s, d));
  v_out := v_out || jsonb_build_object('work', private.load_planner_work(w, s));
  v_out := v_out || jsonb_build_object('money', private.load_planner_money(w, s, v_saved));
  v_out := v_out || jsonb_build_object('loads', private.load_planner_loads(w));
  v_out := v_out || jsonb_build_object('removed', private.load_planner_tidy(w, s, d, v_mct));
  v_out := v_out || jsonb_build_object('kept in extra', private.load_planner_extra(w, s));

  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true),
          set_config('equinox.change_log', coalesce(v_log, ''), true);
  return v_out;
end
$function$;

-- ============================================================ 5. the route and aircraft of each captured flight
-- For a world's captured flights that don't have them yet: the route, by the schedule's leg with that number and
-- direction, else the airline's route in that direction, else the other way (a return); the aircraft, by the
-- registration the loads page or the statement names.
create or replace function private.fill_flight_links(p_world_id bigint)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare v_routes int; v_aircraft int;
begin
  update public.game_flights f
     set route_id = coalesce(
           (select r.route_id from public.flight_legs l join public.rotations r on r.id = l.rotation_id
             where l.airline_id = f.airline_id and l.flight_no = f.flight_no and l.origin_code = f.origin_code
               and l.dest_code = f.dest_code
             order by r.id limit 1),
           (select r.id from public.routes r where r.airline_id = f.airline_id and r.hub_code = f.origin_code
               and r.dest_code = f.dest_code),
           (select r.id from public.routes r where r.airline_id = f.airline_id and r.hub_code = f.dest_code
               and r.dest_code = f.origin_code))
   where f.world_id = p_world_id and f.route_id is null and f.origin_code is not null and f.dest_code is not null
     and exists (select 1 from public.routes r where r.airline_id = f.airline_id
                    and ((r.hub_code, r.dest_code) = (f.origin_code, f.dest_code) or (r.hub_code, r.dest_code) = (f.dest_code, f.origin_code)));
  get diagnostics v_routes = row_count;
  update public.game_flights f set aircraft_id = a.id
    from public.aircraft a
   where f.world_id = p_world_id and f.aircraft_id is null and a.world_id = f.world_id
     and a.registration = coalesce(f.registration, f.maint_registration);
  get diagnostics v_aircraft = row_count;
  return jsonb_build_object('routes', v_routes, 'aircraft', v_aircraft);
end
$function$;

-- ============================================================ 6. the load, then the capture's matching
-- The airports now have time zones, so the money-only and loads-only rows the capture has written since pull request 3
-- pair up, events get their due time, and each captured flight its route and aircraft. From here on each capture
-- matches as it goes (private.capture_page).
do $load$
declare w bigint;
begin
  select x.id into w from public.worlds x where x.is_default;
  perform private.load_planner(w);
  perform private.capture_refresh(w);
  perform private.fill_flight_links(w);
end
$load$;

-- ============================================================ 7. access (design §5)
-- The getters run as the caller, so the tables' staff rules apply, and they refuse anyone who isn't staff themselves;
-- signed-in staff may call them, nobody signed out. The view is read-only to signed-in accounts and shows staff only.
-- The internal steps are closed.
revoke all on function public.planner_state_get(bigint), public.planner_state_version(bigint), public.planner_loads_get(bigint)
  from public, anon, authenticated;
grant execute on function public.planner_state_get(bigint), public.planner_state_version(bigint), public.planner_loads_get(bigint)
  to authenticated;
revoke all on table public.capture_cash from public, anon, authenticated;
grant select on table public.capture_cash to authenticated;
revoke all on function private.json_num(jsonb), private.json_int(jsonb), private.json_date(jsonb), private.json_ts(jsonb),
  private.clock_min(text), private.weekday_set(text), private.shift_weekdays(smallint[], int),
  private.planner_json_differences(jsonb, jsonb, text, text, boolean), private.json_object_or_empty(text),
  private.planner_extra(jsonb, text[], jsonb), private.load_planner_places(bigint, jsonb, jsonb, jsonb),
  private.load_planner_reference(bigint, jsonb, jsonb), private.load_planner_fleet(bigint, jsonb),
  private.load_planner_network(bigint, jsonb, jsonb), private.load_planner_work(bigint, jsonb),
  private.load_planner_money(bigint, jsonb, timestamptz), private.load_planner_loads(bigint),
  private.load_planner_tidy(bigint, jsonb, jsonb, jsonb), private.load_planner_extra(bigint, jsonb),
  private.load_planner(bigint), private.fill_flight_links(bigint)
  from public, anon, authenticated;

-- ============================================================ 8. descriptions (decision #10)
comment on function private.json_num(jsonb) is 'A number from the old planner''s JSON: a JSON number, or text that is plainly a number; null for anything else. Used by the loader.';
comment on function private.json_int(jsonb) is 'A whole number from the old planner''s JSON (a flight number, seats, minutes); null when it isn''t one. Used by the loader.';
comment on function private.json_date(jsonb) is 'A date written YYYY-MM-DD in the old planner''s JSON; null for anything else or a day that doesn''t exist. Used by the loader.';
comment on function private.json_ts(jsonb) is 'A moment written the ISO way in the old planner''s JSON (2026-09-29T17:53:16.155Z); null for anything else. Used by the loader.';
comment on function private.clock_min(text) is 'A local clock time as the old planner reads it ("07:30" or "7:30", up to 23:59), as minutes after midnight; null for anything else.';
comment on function private.weekday_set(text) is 'The weekdays in an old frequency''s days ("135"), as the old planner reads them: the digits 1 to 7, each once, sorted. Null when there are none.';
comment on function private.shift_weekdays(smallint[], integer) is 'ISO weekdays moved by whole days (−1: each a day earlier, Monday becomes Sunday), sorted. Turns local weekdays into UTC ones and back (design §4).';
comment on function private.planner_json_differences(jsonb, jsonb, text, text, boolean) is 'Compares an old planner document with one built from the tables (design §9): one row per difference, with its path and kind. The allowed kinds: a missing key equals null, numbers by value, flight numbers as text, a tail with no status equals "Active", savedAt and version (key order never shows: jsonb keeps none). Anything else is "differs". Used by the loader and the rehearsal''s tests.';
comment on function private.json_object_or_empty(text) is 'Stored JSON text read safely as an object; {} when it isn''t one. Used by the loader for planner_state and planner_loads.';
comment on function private.planner_extra(jsonb, text[], jsonb) is 'What an old list item keeps in its row''s extra: the keys its table has no column for, plus the earlier load''s stand-ins that still hold (a value the columns can''t give back exactly, or null for a key the item doesn''t have).';
comment on function private.load_planner_places(bigint, jsonb, jsonb, jsonb) is 'Loader step: countries and airports from the route research (planner_data), every other airport the planner names by its code, and what the world says about them (connection times from ref.hubs and site_content.mct, night bans from ref.curfews, ref.utcOverrides) into world_airports.';
comment on function private.load_planner_reference(bigint, jsonb, jsonb) is 'Loader step: aircraft types, cabin layouts, markets, service profiles, hubs and focus cities, the types each airline may buy (BUY_TYPES), and the first settings and world rules (design §3.7), from planner_state.ref, planner_meta.growthRules, the manual and the planner''s code constants.';
comment on function private.load_planner_fleet(bigint, jsonb) is 'Loader step: one aircraft row per registration from the old planner''s tails and deliveries (today''s type, cabin and base from the tail; as ordered from the delivery; each list''s order in extra), and the "keep this cabin" decisions.';
comment on function private.load_planner_network(bigint, jsonb, jsonb) is 'Loader step: routes (research, added, edits, route cabins) and each frequency as a rotation and two flight legs in UTC (design §4): weekdays and times from the local ones, the return''s day by the old planner''s rule, block times from the typed times.';
comment on function private.load_planner_work(bigint, jsonb) is 'Loader step: plan cards and their legs (in UTC), to-dos and their steps, growth moves, money spent, the fare plan, interline, monthly checks and dismissed alerts.';
comment on function private.load_planner_money(bigint, jsonb, timestamp with time zone) is 'Loader step: every cash and next-7-day figure the old planner holds that the capture doesn''t give back exactly (capture_cash, rounded as the planner rounds) becomes a cash_entries row, in AS$.';
comment on function private.load_planner_loads(bigint) is 'Loader step: every load in planner_loads the capture doesn''t give back becomes a load_entries row (null where a captured flight was cleared), and a day''s flags a load_days row where the planner saved the day, the capture didn''t write it, or its done differs from the capture''s.';
comment on function private.load_planner_tidy(bigint, jsonb, jsonb, jsonb) is 'Loader step, on a second run: removes the rows the old planner no longer has, or retires an aircraft the capture''s flights or payments still point at, and turns a route back into a research route once nothing adds or edits it.';
comment on function private.load_planner_extra(bigint, jsonb) is 'Loader step, last: builds the document with planner_state_get() and keeps in extra, as the old document has it, any key of a tail, delivery, frequency, plan card, to-do or fare plan that the columns don''t give back (beyond the differences design §9 allows). Returns how often each key was kept. Expected: none.';
comment on function private.load_planner(bigint) is 'Fills a world''s planner tables from the old planner''s storage (only the default world has any): planner_state, planner_loads, planner_data, site_content.mct, planner_meta.growthRules and the planner''s code constants (design §9 step 3). Runs as migration with the change log off. Run again, it brings the tables in line with today''s planner_state, keeping the ids that exist and touching nothing that didn''t change. Returns the rows each step wrote and the keys kept in extra.';
comment on function private.fill_flight_links(bigint) is 'The route and aircraft of a world''s captured flights that don''t have them yet: the route by the schedule''s leg with that number and direction, else the airline''s route that way or the other way; the aircraft by the registration the loads page or the statement names.';

comment on function public.planner_state_version(bigint) is 'The time of the latest logged change to a world''s planner tables (or to airports and countries), in milliseconds, never earlier than the old planner_state row''s last save: what the planner checks before each save (design §8). Staff only. Default: the default world.';
comment on function public.planner_state_get(bigint) is 'Today''s planner_state document built from the tables (design §8): {json: the document as text, saved_at: planner_state_version()}. Every list in the old planner''s order; cash and next-7-day costs from the capture unless typed; anything the tables have no column for from the row''s extra. Staff only. Not read by the planner yet: pull request 9 switches it over.';
comment on function public.planner_loads_get(bigint) is 'Today''s planner_loads documents built from game_flights, load_entries and load_days (design §8): one row per month, like planner_loads. Per flight and per day''s flags, the latest write wins, captured or typed. Staff only. Not read by the planner yet.';

comment on view public.capture_cash is 'Cash and the next 7 days'' payments per airline and capture date, from the capture, worked out as the planner does today: the latest balance of account 2800 that date, and the debits the events page lists for the 7 days after it was captured. What planner_state_get() shows unless cash_entries says otherwise. Shows the caller only what it may read.';
comment on column public.capture_cash.day is 'The capture date as the planner keys it: game_balance.captured_on, the UTC date';
comment on column public.capture_cash.cash is 'Cash, AS$: the balance of account 2800';
comment on column public.capture_cash.fixed_next7 is 'AS$ the events page lists as payments in the 7 days after the balance was captured; null when none';
comment on column public.capture_cash.cash_at is 'When the balance was captured';

comment on table public.airports is 'Every airport in the route research: city, country, position and UTC offset as the game gives them, the same in every world (a world''s own corrections are in world_airports). Loaded from planner_data.coords and planner_data.utc, plus code-only rows for any other airport the planner names (#13, pull request 4).';
comment on column public.game_flights.route_id is 'The route, by the schedule''s leg with that number and direction, else by its airports (filled by private.fill_flight_links)';
comment on column public.game_flights.aircraft_id is 'The aircraft, by the registration the loads page or the statement names (filled by private.fill_flight_links)';
comment on column public.aircraft.extra is 'For the adapter only: tails_index and deliveries_index, the aircraft''s place in the old planner''s two lists; and under tail and delivery, any field of those items the table can''t give back. Expected otherwise empty';

select set_config('equinox.change_log', '', true), set_config('equinox.actor', '', true),
       set_config('equinox.actor_detail', '', true);

-- apply_loads_from_capture(p_airline text)
CREATE OR REPLACE FUNCTION public.apply_loads_from_capture(p_airline text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_al bigint;
begin
  select a.id into v_al from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default
   where a.planner_name = p_airline;
  if v_al is null then return jsonb_build_object('days', 0); end if;
  return private.apply_loads_from_capture(v_al);
end
$function$
;

-- as_num(p text)
CREATE OR REPLACE FUNCTION public.as_num(p text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p is null or p !~ '[0-9]' then null else regexp_replace(p, '[^0-9.\-]', '', 'g')::numeric end;
$function$
;

-- auto_confirm_planner_user()
CREATE OR REPLACE FUNCTION public.auto_confirm_planner_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
begin
  if exists (select 1 from public.planner_users u where lower(u.email) = lower(new.email)) then
    new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  end if;
  return new;
end $function$
;

-- capture_airlines(p_key text)
CREATE OR REPLACE FUNCTION public.capture_airlines(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  return jsonb_build_object(
    'ok', true,
    'world', (select w.name from public.worlds w where w.id = v_world),
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object('game_id', a.game_id, 'name', a.planner_name,
                                                               'game_name', a.game_name, 'code', a.iata_code)
                                           order by a.position nulls last, a.id), '[]'::jsonb)
                   from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = v_world and a.active and g.kind = 'ours'));
end
$function$
;

-- capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
CREATE OR REPLACE FUNCTION public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'html') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', 'capture', true);
  delete from public.game_capture_raw where captured_at < now() - interval '14 days';   -- raw pages kept 14 days
  return private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
end
$function$
;

-- export_capture(p_secret text, p_days integer)
CREATE OR REPLACE FUNCTION public.export_capture(p_secret text, p_days integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'pnl', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) from public.game_flight_pnl f
             where f.ts >= now() - make_interval(days => p_days)),
    'loads', (select coalesce(jsonb_agg(to_jsonb(l) - 'captured_at'), '[]'::jsonb) from public.game_loads l
               where l.flight_date >= current_date - (p_days + 1)),
    -- the columns #13 added stay out, so the scripts get what they always got
    'events', (select coalesce(jsonb_agg(to_jsonb(e) - array['captured_at', 'world_id', 'airline_id', 'due_at']), '[]'::jsonb)
                 from public.game_events e where e.event_date >= current_date - p_days),
    'balance', (select coalesce(jsonb_agg(to_jsonb(b) - array['world_id', 'airline_id', 'capture_day']), '[]'::jsonb)
                  from public.game_balance b where b.account like '2800%' and b.captured_on >= current_date - p_days),
    'ops', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb) from public.game_ops_recent o),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('airline', r.airline, 'kind', r.kind, 'captured_at', r.captured_at)), '[]'::jsonb)
               from public.game_capture_raw r where r.captured_at >= now() - make_interval(days => p_days) and r.kind <> 'html'));
end
$function$
;

-- export_for_report(p_secret text, p_kind text, p_arg text)
CREATE OR REPLACE FUNCTION public.export_for_report(p_secret text, p_kind text, p_arg text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'snapshots' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'taken_at', taken_at, 'week', week, 'status', status) order by id), '[]'::jsonb) from public.game_snapshots);
  elsif p_kind = 'airlines' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', enterprise_id, 'name', name, 'flights', flights, 'n_weekly', n_weekly)), '[]'::jsonb) from public.game_snapshot_airlines where snapshot_id = p_arg::bigint);
  elsif p_kind = 'airports' then
    return (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'info', info, 'stations', stations, 'news', news)), '[]'::jsonb) from public.game_snapshot_airports where snapshot_id = p_arg::bigint);
  elsif p_kind = 'planner' then
    return jsonb_build_object('state', (select json::jsonb from public.planner_state where id = 'main'),
                              'loads', (select coalesce(jsonb_object_agg(month, json::jsonb), '{}'::jsonb) from public.planner_loads));
  end if;
  raise exception 'unknown kind';
end $function$
;

-- export_planner_data(p_secret text)
CREATE OR REPLACE FUNCTION public.export_planner_data(p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return (select jsonb_object_agg(key, value) from public.planner_data);
end $function$
;

-- export_repo_bootstrap(p_secret text)
CREATE OR REPLACE FUNCTION public.export_repo_bootstrap(p_secret text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'supabase_migrations'
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'scripts', (select coalesce(jsonb_agg(jsonb_build_object('name', name, 'content', content) order by name), '[]'::jsonb) from public.planner_scripts),
    'migrations', (select coalesce(jsonb_agg(jsonb_build_object('version', version, 'name', name, 'statements', statements) order by version), '[]'::jsonb) from supabase_migrations.schema_migrations),
    'functions', (select coalesce(jsonb_agg(jsonb_build_object('name', p.proname, 'args', pg_get_function_identity_arguments(p.oid), 'def', pg_get_functiondef(p.oid)) order by p.proname), '[]'::jsonb)
                  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f'),
    'views', (select coalesce(jsonb_agg(jsonb_build_object('name', viewname, 'def', definition) order by viewname), '[]'::jsonb) from pg_views where schemaname = 'public'));
end $function$
;

-- ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
CREATE OR REPLACE FUNCTION public.ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint;
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'start' then
    insert into public.game_snapshots(week, note) values (p_payload->>'week', p_payload->>'note') returning id into v_id;
    return jsonb_build_object('snapshot_id', v_id);
  elsif p_kind = 'airline' then
    insert into public.game_snapshot_airlines(snapshot_id, enterprise_id, name, flights, n_flights, n_weekly, n_airports)
    values ((p_payload->>'snapshot_id')::bigint, (p_payload->>'enterprise_id')::int, p_payload->>'name', coalesce(p_payload->'flights','[]'::jsonb),
            (p_payload->>'n_flights')::int, (p_payload->>'n_weekly')::int, (p_payload->>'n_airports')::int)
    on conflict (snapshot_id, enterprise_id) do update set name = excluded.name, flights = excluded.flights, n_flights = excluded.n_flights, n_weekly = excluded.n_weekly, n_airports = excluded.n_airports;
    return jsonb_build_object('ok', true);
  elsif p_kind = 'airport' then
    insert into public.game_snapshot_airports(snapshot_id, code, airport_id, info, stations, news)
    values ((p_payload->>'snapshot_id')::bigint, p_payload->>'code', (p_payload->>'airport_id')::int, p_payload->'info', p_payload->'stations', p_payload->'news')
    on conflict (snapshot_id, code) do update set airport_id = excluded.airport_id, info = excluded.info, stations = excluded.stations, news = excluded.news;
    return jsonb_build_object('ok', true);
  elsif p_kind = 'finish' then
    update public.game_snapshots set status = 'done', note = coalesce(p_payload->>'note', note) where id = (p_payload->>'snapshot_id')::bigint;
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown kind';
end $function$
;

-- is_planner_user()
CREATE OR REPLACE FUNCTION public.is_planner_user()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.planner_users u where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$function$
;

-- parse_capture(p_id bigint)
CREATE OR REPLACE FUNCTION public.parse_capture(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return private.capture_page(p_id);
end
$function$
;

-- planner_data_set(p_secret text, p_key text, p_value jsonb)
CREATE OR REPLACE FUNCTION public.planner_data_set(p_secret text, p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  insert into public.planner_data(key, value) values (p_key, p_value) on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true, 'bytes', length(p_value::text));
end $function$
;

-- planner_loads_get(p_world_id bigint)
CREATE OR REPLACE FUNCTION public.planner_loads_get(p_world_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(month text, "json" text, saved_at bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$
;

-- planner_state_get(p_world_id bigint)
CREATE OR REPLACE FUNCTION public.planner_state_get(p_world_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
    'consts', (select jsonb_object_agg(m.k, s.value order by m.k)
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
                 private_days.days_local
            from (select case when l1.dep_utc_min is null then l1.days_utc
                              else array(select distinct ((((d - 1 + floor((l1.dep_utc_min + o.oh) / 1440.0)::int) % 7) + 7) % 7 + 1)::smallint
                                           from unnest(l1.days_utc) as d order by 1) end as days_local) private_days) x
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
$function$
;

-- planner_state_version(p_world_id bigint)
CREATE OR REPLACE FUNCTION public.planner_state_version(p_world_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$
;

-- save_loads(p_month text, p_days jsonb)
CREATE OR REPLACE FUNCTION public.save_loads(p_month text, p_days jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cur jsonb; d text; p jsonb; day jsonb; f jsonb;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if not public.is_planner_user() then raise exception 'only planner staff can save loads' using errcode = '42501'; end if;
  if p_month is null or p_month !~ '^\d{4}-\d{2}$' then raise exception 'month must be YYYY-MM, got %', p_month; end if;
  if jsonb_typeof(p_days) is distinct from 'object' then raise exception 'days must be an object keyed by date'; end if;
  insert into public.planner_loads(month, json, saved_at) values (p_month, '{}', 0) on conflict (month) do nothing;
  select json::jsonb into cur from public.planner_loads where month = p_month for update;
  cur := coalesce(cur, '{}'::jsonb) - '__savedAt';   -- a browser-only marker that older saves wrote into the document
  for d, p in select key, value from jsonb_each(p_days) loop
    if d !~ ('^' || p_month || '-\d{2}$') then raise exception 'day % is not in month %', d, p_month; end if;
    if jsonb_typeof(p) is distinct from 'object' then raise exception 'day % must be an object', d; end if;
    day := coalesce(cur->d, '{"done": false, "f": {}}'::jsonb);
    if p ? 'f' then
      f := coalesce(p->'f', '{}'::jsonb);                                         -- the whole day's entry, as typed
    else
      f := (coalesce(day->'f', '{}'::jsonb) || coalesce(p->'set', '{}'::jsonb))   -- single flights: set these ...
           - array(select jsonb_array_elements_text(coalesce(p->'del', '[]'::jsonb)));   -- ... and clear these
    end if;
    day := jsonb_set(day, '{f}', f, true);
    if p ? 'done' then day := day || jsonb_build_object('done', p->'done'); end if;
    if p ? 'savedAt' then day := day || jsonb_build_object('savedAt', p->'savedAt'); end if;
    cur := jsonb_set(cur, array[d], day, true);
  end loop;
  update public.planner_loads set json = cur::text, saved_at = ms where month = p_month;
  return jsonb_build_object('month', p_month, 'json', cur, 'saved_at', ms);
end $function$
;

-- save_script(p_secret text, p_name text, p_content text)
CREATE OR REPLACE FUNCTION public.save_script(p_secret text, p_name text, p_content text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  insert into public.planner_scripts(name, content) values (p_name, p_content)
  on conflict (name) do update set content = excluded.content, updated_at = now();
  return jsonb_build_object('ok', true, 'name', p_name, 'bytes', length(p_content));
end $function$
;

-- site_admin(p_secret text, p_kind text, p_payload jsonb)
CREATE OR REPLACE FUNCTION public.site_admin(p_secret text, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'post' then
    insert into public.site_posts(slug, published_at, title, summary, body, tag, airline, image, image_credit, auto)
    values (p_payload->>'slug', coalesce((p_payload->>'at')::timestamptz, now()), p_payload->>'title', p_payload->>'summary', p_payload->>'body', p_payload->>'tag', p_payload->>'airline', p_payload->>'image', p_payload->>'credit', coalesce((p_payload->>'auto')::boolean, false))
    on conflict (slug) do update set published_at = excluded.published_at, title = excluded.title, summary = excluded.summary, body = excluded.body, tag = excluded.tag, airline = excluded.airline, image = excluded.image, image_credit = excluded.image_credit;
  elsif p_kind = 'report' then
    insert into public.site_reports(kind, period, title, summary, published_at, status, pdf_b64)
    values (p_payload->>'kind', p_payload->>'period', p_payload->>'title', p_payload->>'summary', (p_payload->>'at')::timestamptz, coalesce(p_payload->>'status', 'published'), p_payload->>'pdf')
    on conflict (kind, period) do update set title = excluded.title, summary = excluded.summary, published_at = excluded.published_at, status = excluded.status, pdf_b64 = coalesce(excluded.pdf_b64, public.site_reports.pdf_b64);
  elsif p_kind = 'content' then
    insert into public.site_content(key, value) values (p_payload->>'key', p_payload->'value') on conflict (key) do update set value = excluded.value, updated_at = now();
  else raise exception 'unknown kind'; end if;
  return jsonb_build_object('ok', true);
end $function$
;

-- site_investor(p_password text)
CREATE OR REPLACE FUNCTION public.site_investor(p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare h text;
begin
  select pass_hash into h from public.report_access limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then return jsonb_build_object('ok', false); end if;
  return (with s as (select json::jsonb j from public.planner_state where id = 'main')
    select jsonb_build_object('ok', true, 'cash', j->'cash', 'fixed7', j->'fixed7',
      'capex', (select coalesce(jsonb_agg(jsonb_build_object('date', x->>'date', 'airline', x->>'airline', 'm', x->'amountM', 'kind', x->>'kind')), '[]'::jsonb) from jsonb_array_elements(j->'capex') x),
      'markets', (select value from public.site_content where key = 'markets'),
      'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'period', period, 'title', title, 'summary', summary, 'at', published_at, 'status', status, 'has_pdf', pdf_b64 is not null) order by coalesce(published_at, now() + interval '1 year') desc), '[]'::jsonb) from public.site_reports where kind <> 'newsletter')) from s);
end $function$
;

-- site_newsletter(p_id bigint)
CREATE OR REPLACE FUNCTION public.site_newsletter(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('ok', true, 'title', title, 'pdf', pdf_b64) from public.site_reports where id = p_id and kind = 'newsletter' and status = 'published';
$function$
;

-- site_public()
CREATE OR REPLACE FUNCTION public.site_public()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (select json::jsonb j from public.planner_state where id = 'main'),
  live as (select distinct split_part(f->>'routeKey','|',1) al, split_part(f->>'routeKey','|',2) hub from s, jsonb_array_elements(j->'freqs') f)
  select jsonb_build_object(
    'updated_at', (select updated_at from public.planner_state where id = 'main'),
    'hubs', (select coalesce(jsonb_agg(jsonb_build_object('code', h->>'code', 'airline', h->>'airline', 'role', h->>'role')), '[]'::jsonb) from s, jsonb_array_elements(j->'ref'->'hubs') h where exists (select 1 from live where live.al = h->>'airline' and live.hub = h->>'code')),
    'tails', (select coalesce(jsonb_agg(jsonb_build_object('id', t->>'id', 'airline', t->>'airline', 'type', t->>'type')), '[]'::jsonb) from s, jsonb_array_elements(j->'tails') t),
    'freqs', (select coalesce(jsonb_agg(jsonb_build_object('r', f->>'routeKey', 't', f->>'tail', 'a', f->>'depHub', 'b', f->>'arrDest', 'c', f->>'depDest', 'd', f->>'arrHub', 'days', f->>'days', 'o', f->>'noOut', 'k', f->>'noBack', 'l', f->>'launched')), '[]'::jsonb) from s, jsonb_array_elements(j->'freqs') f),
    'interline', (select coalesce(jsonb_agg(jsonb_build_object('pair', k, 'partner', j->'interline'->k->>'partner', 'date', j->'interline'->k->>'date')), '[]'::jsonb) from s, jsonb_object_keys(j->'interline') k where j->'interline'->k->>'status' = 'signed'),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'at', published_at, 'title', title, 'summary', summary, 'body', body, 'tag', tag, 'airline', airline, 'image', image, 'credit', image_credit) order by published_at desc), '[]'::jsonb) from public.site_posts),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'period', period, 'title', title, 'summary', case when kind = 'newsletter' then summary end, 'at', published_at, 'status', status, 'has_pdf', pdf_b64 is not null) order by coalesce(published_at, now() + interval '1 year') desc), '[]'::jsonb) from public.site_reports),
    'content', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.site_content where key <> 'markets')
  );
$function$
;

-- site_remove_airline_logo(p_airline text)
CREATE OR REPLACE FUNCTION public.site_remove_airline_logo(p_airline text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  update public.site_content set value = value #- array['logos', p_airline], updated_at = now() where key = 'media';
  return jsonb_build_object('ok', true);
end $function$
;

-- site_remove_airport_photo(p_code text)
CREATE OR REPLACE FUNCTION public.site_remove_airport_photo(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  update public.site_content set value = value #- array['airports', p_code], updated_at = now() where key = 'media';
  return jsonb_build_object('ok', true);
end $function$
;

-- site_report(p_id bigint, p_password text)
CREATE OR REPLACE FUNCTION public.site_report(p_id bigint, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare h text;
begin
  select pass_hash into h from public.report_access limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then
    return jsonb_build_object('ok', false, 'error', 'wrong_password');
  end if;
  return (select jsonb_build_object('ok', true, 'title', title, 'pdf', pdf_b64) from public.site_reports where id = p_id and status = 'published');
end $function$
;

-- site_set_airline_logo(p_airline text, p_url text, p_path text)
CREATE OR REPLACE FUNCTION public.site_set_airline_logo(p_airline text, p_url text, p_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m jsonb;
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  if p_airline not in ('Pan American','Kingfisher','Ryanair','Virgin Atlantic','China Eastern','Malaysia Airlines') or p_url !~ '^https://' then raise exception 'bad input'; end if;
  select value into m from public.site_content where key = 'media';
  m := coalesce(m, '{}'::jsonb);
  m := jsonb_set(m, '{logos}', coalesce(m->'logos', '{}'::jsonb), true);
  m := jsonb_set(m, array['logos', p_airline], jsonb_strip_nulls(jsonb_build_object('url', p_url, 'path', p_path, 'at', now())), true);
  insert into public.site_content(key, value) values ('media', m) on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true);
end $function$
;

-- site_set_airport_photo(p_code text, p_url text, p_credit text, p_path text)
CREATE OR REPLACE FUNCTION public.site_set_airport_photo(p_code text, p_url text, p_credit text DEFAULT NULL::text, p_path text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m jsonb;
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  if p_code !~ '^[A-Z0-9]{3}$' or p_url !~ '^https://' then raise exception 'bad input'; end if;
  select value into m from public.site_content where key = 'media';
  m := coalesce(m, '{}'::jsonb);
  m := jsonb_set(m, '{airports}', coalesce(m->'airports', '{}'::jsonb), true);
  m := jsonb_set(m, array['airports', p_code], jsonb_strip_nulls(jsonb_build_object('url', p_url, 'creator', nullif(p_credit, ''), 'uploaded', true, 'path', p_path, 'at', now())), true);
  insert into public.site_content(key, value) values ('media', m) on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true);
end $function$
;

-- touch_updated_at()
CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin new.updated_at = now(); return new; end $function$
;

-- ===== private schema (decision #13): trigger functions and helpers, not exposed by the data API =====

-- private.airport_offset_min(p_world_id bigint, p_code text)
CREATE OR REPLACE FUNCTION private.airport_offset_min(p_world_id bigint, p_code text)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select round(coalesce(wa.utc_offset_override, a.utc_offset) * 60)::int
    from public.airports a
    left join public.world_airports wa on wa.world_id = p_world_id and wa.airport_code = a.code
   where a.code = p_code
$function$

;

-- private.apply_loads_from_capture(p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.apply_loads_from_capture(p_airline_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare d record; mon text; cur jsonb; day jsonb; f jsonb; n int := 0; v_name text; v_world bigint;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  select coalesce(a.planner_name, a.public_name, a.game_name, a.game_id::text), a.world_id into v_name, v_world from public.airlines a where a.id = p_airline_id;
  for d in select distinct g.game_date from public.game_flights g
            where g.airline_id = p_airline_id and g.flight_no is not null and g.game_date >= current_date - 3 loop
    mon := to_char(d.game_date, 'YYYY-MM');
    select pl.json::jsonb into cur from public.planner_loads pl where pl.month = mon for update;
    cur := coalesce(cur, '{}'::jsonb);
    day := coalesce(cur -> (d.game_date::text), '{}'::jsonb);
    select coalesce(jsonb_object_agg(v_name || '|' || g.flight_no::text, g.eco_pct), '{}'::jsonb) into f
      from public.game_flights g
     where g.airline_id = p_airline_id and g.flight_no is not null and g.game_date = d.game_date and g.eco_pct is not null;
    day := jsonb_set(day, '{f}', coalesce(day -> 'f', '{}'::jsonb) || f, true);
    day := day || jsonb_build_object('done', coalesce(day -> 'done' = 'true'::jsonb, false)
                                             or private.capture_day_complete(v_world, d.game_date),
                                     'captured', now(), 'source', 'capture');
    cur := jsonb_set(cur, array[d.game_date::text], day, true);
    -- saved_at moves on, so a browser holding an older copy of the month takes this one when it next loads
    insert into public.planner_loads (month, json, saved_at) values (mon, cur::text, ms)
      on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
    n := n + 1;
  end loop;
  return jsonb_build_object('days', n);
end
$function$

;

-- private.capture_day(p_world_id bigint, p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.capture_day(p_world_id bigint, p_at timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select ((p_at at time zone 'UTC')
          - coalesce((select (s.value #>> '{}')::time from public.settings s
                       where s.world_id = p_world_id and s.airline_id is null and s.key = 'capture_day_starts_utc'),
                     time '10:00')::interval)::date
$function$

;

-- private.capture_day_complete(p_world_id bigint, p_day date)
CREATE OR REPLACE FUNCTION private.capture_day_complete(p_world_id bigint, p_day date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  span as (select private.capture_day_start(p_world_id, p_day) as from_at)
  select exists (select 1 from ours)
     and not exists (
       select 1 from ours o, span
        where (select count(distinct r.kind) from public.game_capture_raw r
                where r.airline_id = o.id and r.kind in ('statement', 'events', 'pnl', 'balance', 'loads')
                  and r.captured_at >= span.from_at and r.captured_at < span.from_at + interval '1 day') < 5)
$function$

;

-- private.capture_day_start(p_world_id bigint, p_day date)
CREATE OR REPLACE FUNCTION private.capture_day_start(p_world_id bigint, p_day date)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select (p_day + coalesce((select (s.value #>> '{}')::time from public.settings s
                             where s.world_id = p_world_id and s.airline_id is null and s.key = 'capture_day_starts_utc'),
                           time '10:00')) at time zone 'UTC'
$function$

;

-- private.capture_find_airline(p_world_id bigint, p_airline text)
CREATE OR REPLACE FUNCTION private.capture_find_airline(p_world_id bigint, p_airline text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select case when count(*) = 1 then min(a.id) end
    from public.airlines a
    join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = p_world_id and g.kind = 'ours' and p_airline is not null
     and case
           when btrim(p_airline) ~ '^[0-9]{1,9}$' then a.game_id = btrim(p_airline)::int
           else lower(btrim(p_airline)) in (lower(a.planner_name), lower(a.public_name), lower(a.game_name))
                -- the names the capture has matched since 7 Oct, by their start (e.g. "Pan Am" for Pan American)
                or exists (select 1 from (values ('pan am%', 'Pan American'), ('kingfisher%', 'Kingfisher'),
                                                 ('ryanair%', 'Ryanair'), ('virgin%', 'Virgin Atlantic'),
                                                 ('china eastern%', 'China Eastern'), ('malaysia%', 'Malaysia Airlines'))
                                         as legacy (pattern, planner_name)
                            where p_airline ilike legacy.pattern and legacy.planner_name = a.planner_name)
         end
$function$

;

-- private.capture_key_world(p_key text)
CREATE OR REPLACE FUNCTION private.capture_key_world(p_key text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select k.world_id from public.capture_keys k
   where p_key is not null and extensions.crypt(p_key, k.key_hash) = k.key_hash
   order by k.id
   limit 1
$function$

;

-- private.capture_page(p_raw_id bigint)
CREATE OR REPLACE FUNCTION private.capture_page(p_raw_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  r record; row_ jsonb; c text[]; n int := 0; cur_date date; d text; tsv timestamptz; amt numeric; v_side text;
  v_descr text; dt date; ep int; es int; bp int; bs int; fp int; fs int; cu int; cc int;
  last_ts timestamptz := null; blkn int := 0; maint_pending boolean := false; seen jsonb := '{}'::jsonb; k text; o int; b int;
  v_at timestamptz; v_today date; yr int; v_minutes timestamptz[] := '{}'; v_off int; v_code text; v_dep text;
  v_arr text; t record; v_day date;
begin
  select * into r from public.game_capture_raw where id = p_raw_id;
  if not found then return '{"ok": false}'::jsonb; end if;
  v_at := r.captured_at;
  v_today := (v_at at time zone 'UTC')::date;
  yr := extract(year from (v_at at time zone 'UTC'))::int;

  if r.kind = 'statement' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if array_length(c, 1) < 3 or c[1] !~ '^\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substr(c[1], 1, 6); v_descr := c[2];
      tsv := make_timestamptz(yr, substr(d, 4, 2)::int, substr(d, 1, 2)::int, substr(c[1], 8, 2)::int, substr(c[1], 11, 2)::int, 0, 'UTC');
      if tsv > v_at + interval '2 days' then tsv := tsv - interval '1 year'; end if;
      amt := public.as_num(c[3]); v_side := case when c[3] ~ 'C\s*$' then 'C' else 'D' end;
      if amt is null then continue; end if;
      -- blocks: the lines of one flight, when several flights post in the same minute (as since 8 Oct)
      if last_ts is distinct from tsv then last_ts := tsv; blkn := 0; maint_pending := false; end if;
      if v_descr like 'Maintenance of%' then blkn := blkn + 1; maint_pending := true; b := blkn;
      elsif v_descr = 'Passenger transport income' then
        if maint_pending then maint_pending := false; else blkn := blkn + 1; end if; b := blkn;
      elsif v_descr ilike 'Leasing rate%' or v_descr ilike 'Week-end closing%' then b := 0;
      else b := greatest(blkn, 1); end if;
      k := tsv::text || '|' || v_descr || '|' || amt::text; o := coalesce((seen ->> k)::int, 0) + 1;
      seen := seen || jsonb_build_object(k, o);
      insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, route, pax, occ, blk, captured_at)
      values (r.world_id, r.airline_id, r.airline, tsv, v_descr, amt, v_side, substring(v_descr from '\(([A-Z]{3}-[A-Z]{3})\)'),
              (substring(v_descr from 'of (\d+) passengers'))::int, o, b, v_at)
      on conflict on constraint game_statement_pkey do update set blk = excluded.blk;
      n := n + 1;
      v_minutes := v_minutes || tsv;
    end loop;
    perform private.fold_statement(r.airline_id, array(select distinct x from unnest(v_minutes) x));
    perform private.match_flights(r.airline_id);

  elsif r.kind = 'events' then
    select private.airport_offset_min(a.world_id, a.home_airport_code) into v_off from public.airlines a where a.id = r.airline_id;
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if c[1] ~ '^\w+, \d{2}\.\d{2}\.' then
        d := substring(c[1] from '(\d{2}\.\d{2})\.'); cur_date := make_date(yr, substr(d, 4, 2)::int, substr(d, 1, 2)::int);
        if cur_date < v_today - 200 then cur_date := cur_date + interval '1 year'; end if;
        c := c[2:];
      end if;
      if cur_date is null or array_length(c, 1) < 2 or c[1] !~ '^\d{2}:\d{2}$' then continue; end if;
      insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, credit, debit, balance,
                                      captured_at, due_at)
      values (r.world_id, r.airline_id, r.airline, cur_date, c[1], c[2], public.as_num(c[3]), public.as_num(c[4]),
              public.as_num(c[5]), v_at, private.local_to_utc(cur_date, c[1], v_off))
      on conflict do nothing;
      n := n + 1;
    end loop;
    perform private.fill_due_at(r.airline_id);

  elsif r.kind = 'loads' then
    -- Load monitoring row: code, tail, origin, "07.10. 04:10 LT", destination, "07.10. 05:23 LT", eco fare,
    -- "156 / 156 (100%)", bus fare, bus, first fare, first, cargo rate, "27 / 32 (84%)", status, details
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c, 1) < 15 or c[1] !~ '^[A-Z0-9]{2,3}\s?\d{1,5}' or c[4] !~ '\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substring(c[4] from '(\d{2}\.\d{2})\.'); dt := make_date(yr, substr(d, 4, 2)::int, substr(d, 1, 2)::int);
      if dt > v_today + 2 then dt := dt - interval '1 year'; end if;
      ep := (substring(c[8] from '^\s*(\d+)'))::int; es := (substring(c[8] from '/\s*(\d+)'))::int;
      bp := (substring(c[10] from '^\s*(\d+)'))::int; bs := (substring(c[10] from '/\s*(\d+)'))::int;
      fp := (substring(c[12] from '^\s*(\d+)'))::int; fs := (substring(c[12] from '/\s*(\d+)'))::int;
      cu := (substring(c[14] from '^\s*(\d+)'))::int; cc := (substring(c[14] from '/\s*(\d+)'))::int;
      v_code := regexp_replace(c[1], '\s+', ' ');
      v_dep := substring(c[4] from '(\d{2}:\d{2})'); v_arr := substring(c[6] from '(\d{2}:\d{2})');
      select * into t from private.loads_times(r.world_id, dt, v_dep, v_arr, c[3], c[5]);
      insert into public.game_flights as f (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local,
             arr_local, dep_at, arr_at, registration, status, eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats,
             bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct, cargo_units, cargo_cap, cargo_rate, cargo_pct,
             loads_captured_at)
      values (r.world_id, r.airline_id, dt, (substring(v_code from '^[A-Z0-9]{2,3}\s?(\d{1,5})'))::int, c[3], c[5], v_dep,
              v_arr, t.dep_at, t.arr_at, c[2], c[15],
              ep, es, public.as_num(c[7]), public.as_num(substring(c[8] from '\((\d+)%\)')),
              bp, bs, public.as_num(c[9]), public.as_num(substring(c[10] from '\((\d+)%\)')),
              fp, fs, public.as_num(c[11]), public.as_num(substring(c[12] from '\((\d+)%\)')),
              cu, cc, public.as_num(c[13]), public.as_num(substring(c[14] from '\((\d+)%\)')), v_at)
      on conflict (airline_id, game_date, flight_no, dep_local) where flight_no is not null do update set
        origin_code = excluded.origin_code, dest_code = excluded.dest_code, arr_local = excluded.arr_local,
        dep_at = coalesce(excluded.dep_at, f.dep_at), arr_at = coalesce(excluded.arr_at, f.arr_at),
        registration = excluded.registration, status = excluded.status,
        eco_pax = excluded.eco_pax, eco_seats = excluded.eco_seats, eco_fare = excluded.eco_fare, eco_pct = excluded.eco_pct,
        bus_pax = excluded.bus_pax, bus_seats = excluded.bus_seats, bus_fare = excluded.bus_fare, bus_pct = excluded.bus_pct,
        fst_pax = excluded.fst_pax, fst_seats = excluded.fst_seats, fst_fare = excluded.fst_fare, fst_pct = excluded.fst_pct,
        cargo_units = excluded.cargo_units, cargo_cap = excluded.cargo_cap, cargo_rate = excluded.cargo_rate,
        cargo_pct = excluded.cargo_pct, loads_captured_at = excluded.loads_captured_at;
      n := n + 1;
    end loop;
    perform private.fill_flight_times(r.airline_id);
    perform private.match_flights(r.airline_id);

  elsif r.kind = 'pnl' then
    v_day := private.capture_day(r.world_id, v_at);
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c, 1) < 3 or c[2] !~ 'AS\$' then continue; end if;
      insert into public.game_pnl (world_id, airline_id, airline, captured_on, capture_day, line, current_p, last_p, total_p, captured_at)
      values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1], public.as_num(c[2]), public.as_num(c[3]),
              public.as_num(c[array_length(c, 1)]), v_at)
      on conflict (airline, captured_on, line) do update set current_p = excluded.current_p, last_p = excluded.last_p,
        total_p = excluded.total_p, capture_day = excluded.capture_day;
      n := n + 1;
    end loop;

  elsif r.kind = 'balance' then
    v_day := private.capture_day(r.world_id, v_at);
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c, 1) >= 3 and c[1] ~ '^\d{3,4}$' then
        insert into public.game_balance (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1] || ' ' || c[2], public.as_num(c[3]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day;
        n := n + 1;
      end if;
      if array_length(c, 1) >= 6 and c[4] ~ '^\d{3,4}$' then
        insert into public.game_balance (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[4] || ' ' || c[5], public.as_num(c[6]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day;
        n := n + 1;
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'kind', r.kind, 'rows', n);
end
$function$

;

-- private.capture_refresh(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.capture_refresh(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a record; v_times int := 0; v_due int := 0; v_matched int := 0;
begin
  for a in select al.id from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
            where al.world_id = p_world_id and g.kind = 'ours' order by al.id loop
    v_times := v_times + private.fill_flight_times(a.id);
    v_due := v_due + private.fill_due_at(a.id);
    v_matched := v_matched + private.match_flights(a.id);
  end loop;
  return jsonb_build_object('times', v_times, 'due_at', v_due, 'matched', v_matched);
end
$function$

;

-- private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean)
CREATE OR REPLACE FUNCTION private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_al bigint; v_name text; v_rid bigint; v_res jsonb; v_day date;
begin
  v_al := private.capture_find_airline(p_world_id, p_airline);
  if v_al is null then
    return jsonb_build_object('ok', false, 'error', 'not an airline of this capture key''s world: ' || coalesce(p_airline, '(none)'));
  end if;
  select coalesce(a.planner_name, a.public_name, a.game_name, a.game_id::text) into v_name from public.airlines a where a.id = v_al;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (p_world_id, v_al, v_name, p_kind, p_page, coalesce(p_rows, '[]'::jsonb), p_at)
  returning id into v_rid;
  if p_kind = 'html' then return jsonb_build_object('ok', true, 'kind', 'html', 'rows', 1, 'airline', v_name); end if;   -- page inspection: stored only
  begin
    v_res := private.capture_page(v_rid) || jsonb_build_object('airline', v_name);
    if p_kind = 'loads' and p_loads_step then v_res := v_res || private.apply_loads_from_capture(v_al); end if;
  exception when others then
    v_res := jsonb_build_object('ok', false, 'airline', v_name, 'error', 'parse: ' || sqlerrm, 'raw_id', v_rid);   -- the raw rows stay for inspection
  end;
  v_day := private.capture_day(p_world_id, p_at);
  return v_res || jsonb_build_object('capture_day', v_day, 'day_complete', private.capture_day_complete(p_world_id, v_day));
end
$function$

;

-- private.check_leg_route()
CREATE OR REPLACE FUNCTION private.check_leg_route()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r record;
begin
  select ro.hub_code, ro.dest_code into r
    from public.rotations rot join public.routes ro on ro.id = rot.route_id
   where rot.id = new.rotation_id;
  -- no rotation found: the foreign key refuses a rotation that doesn't exist, and the access rules refuse a caller who
  -- can't read it
  if not found then return new; end if;
  if (new.leg_no = 1 and (new.origin_code, new.dest_code) is distinct from (r.hub_code, r.dest_code))
     or (new.leg_no = 2 and (new.origin_code, new.dest_code) is distinct from (r.dest_code, r.hub_code)) then
    raise exception 'flight leg % of rotation % flies % to %, but its route is % to % (leg 1 leaves the hub, leg 2 returns to it)',
      new.leg_no, new.rotation_id, new.origin_code, new.dest_code, r.hub_code, r.dest_code
      using errcode = 'check_violation';
  end if;
  return new;
end
$function$

;

-- private.check_route_legs()
CREATE OR REPLACE FUNCTION private.check_route_legs()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare bad bigint;
begin
  select l.id into bad
    from public.flight_legs l
    join public.rotations rot on rot.id = l.rotation_id
    join public.routes ro on ro.id = rot.route_id
   where (case when tg_table_name = 'routes' then ro.id else rot.id end) = new.id
     and ((l.leg_no = 1 and (l.origin_code, l.dest_code) is distinct from (ro.hub_code, ro.dest_code))
       or (l.leg_no = 2 and (l.origin_code, l.dest_code) is distinct from (ro.dest_code, ro.hub_code)))
   limit 1;
  if bad is not null then
    raise exception 'this change to % % would leave flight leg % not matching its route', tg_table_name, new.id, bad
      using errcode = 'check_violation';
  end if;
  return null;
end
$function$

;

-- private.clock_min(p text)
CREATE OR REPLACE FUNCTION private.clock_min(p text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when m[1]::int <= 23 and m[2]::int <= 59 then m[1]::int * 60 + m[2]::int end
    from (select regexp_match(btrim(p), '^(\d{1,2}):(\d{2})$') as m) x
$function$
;

-- private.fill_due_at(p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.fill_due_at(p_airline_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_off int; v_n int;
begin
  select private.airport_offset_min(a.world_id, a.home_airport_code) into v_off from public.airlines a where a.id = p_airline_id;
  if v_off is null then return 0; end if;
  update public.game_events e set due_at = private.local_to_utc(e.event_date, e.event_time, v_off)
   where e.airline_id = p_airline_id and e.due_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end
$function$

;

-- private.fill_flight_links(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.fill_flight_links(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.fill_flight_times(p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.fill_flight_times(p_airline_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  with x as (
    select f.id, t.dep_at, t.arr_at
      from public.game_flights f
      cross join lateral private.loads_times(f.world_id, f.game_date, f.dep_local, f.arr_local, f.origin_code, f.dest_code) t
     where f.airline_id = p_airline_id and f.flight_no is not null
       and (f.dep_at is null or (f.arr_at is null and f.arr_local is not null)))
  update public.game_flights f set dep_at = x.dep_at, arr_at = x.arr_at
    from x
   where f.id = x.id and x.dep_at is not null and (f.dep_at, f.arr_at) is distinct from (x.dep_at, x.arr_at);
  get diagnostics v_n = row_count;
  return v_n;
end
$function$

;

-- private.fold_statement(p_airline_id bigint, p_minutes timestamp with time zone[])
CREATE OR REPLACE FUNCTION private.fold_statement(p_airline_id bigint, p_minutes timestamp with time zone[])
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_world bigint; v_n int;
begin
  if p_minutes is null or cardinality(p_minutes) = 0 then return 0; end if;
  select a.world_id into v_world from public.airlines a where a.id = p_airline_id;

  -- 1. these minutes' lines let go of their flights; they are tied again in 4
  update public.game_statement set flight_id = null
   where airline_id = p_airline_id and ts = any (p_minutes) and flight_id is not null;

  -- 2. money whose block is gone or changed: a money-only row goes; a flight already matched to its loads keeps them and
  --    loses the money, which 3 puts back as a money-only row to be matched again
  with b as materialized (select * from private.statement_blocks(p_airline_id, p_minutes) x where x.is_flight)
  delete from public.game_flights f
   where f.airline_id = p_airline_id and f.posted_at = any (p_minutes) and f.flight_no is null
     and not exists (select 1 from b where b.ts = f.posted_at and b.blk = f.statement_blk);
  with b as materialized (select * from private.statement_blocks(p_airline_id, p_minutes) x where x.is_flight)
  update public.game_flights f
     set posted_at = null, statement_blk = null, statement_routes = null, maint_registration = null, statement_pax = null,
         pax_income = null, cargo_income = null, fuel = null, onboard = null, handling = null, landing = null,
         atc = null, maintenance = null, income_total = null, cost_total = null, money_captured_at = null
   where f.airline_id = p_airline_id and f.posted_at = any (p_minutes) and f.flight_no is not null
     and not exists (select 1 from b where b.ts = f.posted_at and b.blk = f.statement_blk and b.routes_n = 1
                                       and b.route = f.origin_code || '-' || f.dest_code);

  -- 3. each flight block's money, by its minute and block; dep_at is the statement time until loads are matched
  insert into public.game_flights as f (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code,
         dest_code, dep_at, maint_registration, statement_pax, pax_income, cargo_income, fuel, onboard, handling,
         landing, atc, maintenance, income_total, cost_total, money_captured_at)
  select v_world, p_airline_id, b.ts, b.blk, b.routes_n, split_part(b.route, '-', 1), split_part(b.route, '-', 2), b.ts,
         b.tail, b.pax, b.pax_income, b.cargo_income, b.fuel, b.onboard, b.handling, b.landing, b.atc, b.maintenance,
         b.income_total, b.cost_total, b.captured_at
    from private.statement_blocks(p_airline_id, p_minutes) b
   where b.is_flight
  on conflict (airline_id, posted_at, statement_blk) where posted_at is not null do update set
    statement_routes = excluded.statement_routes,
    origin_code = case when f.flight_no is null then excluded.origin_code else f.origin_code end,
    dest_code = case when f.flight_no is null then excluded.dest_code else f.dest_code end,
    dep_at = case when f.flight_no is null then excluded.dep_at else f.dep_at end,
    maint_registration = excluded.maint_registration, statement_pax = excluded.statement_pax,
    pax_income = excluded.pax_income, cargo_income = excluded.cargo_income, fuel = excluded.fuel,
    onboard = excluded.onboard, handling = excluded.handling, landing = excluded.landing, atc = excluded.atc,
    maintenance = excluded.maintenance, income_total = excluded.income_total, cost_total = excluded.cost_total,
    money_captured_at = excluded.money_captured_at
  where (f.statement_routes, f.maint_registration, f.statement_pax, f.pax_income, f.cargo_income, f.fuel, f.onboard,
         f.handling, f.landing, f.atc, f.maintenance, f.income_total, f.cost_total, f.money_captured_at)
        is distinct from
        (excluded.statement_routes, excluded.maint_registration, excluded.statement_pax, excluded.pax_income,
         excluded.cargo_income, excluded.fuel, excluded.onboard, excluded.handling, excluded.landing, excluded.atc,
         excluded.maintenance, excluded.income_total, excluded.cost_total, excluded.money_captured_at)
     or (f.flight_no is null and (f.origin_code, f.dest_code, f.dep_at)
                                 is distinct from (excluded.origin_code, excluded.dest_code, excluded.dep_at));
  get diagnostics v_n = row_count;

  -- 4. each flight line points at its flight
  update public.game_statement s set flight_id = f.id
    from public.game_flights f
   where s.airline_id = p_airline_id and s.ts = any (p_minutes) and not private.is_payment_line(s.descr, s.blk)
     and f.airline_id = p_airline_id and f.posted_at = s.ts and f.statement_blk = s.blk;

  -- 5. every other line is a payment, one row per statement line
  insert into public.game_payments as p (world_id, airline_id, paid_at, kind, registration, descr, amount, side, occ,
         statement_blk)
  select v_world, p_airline_id, s.ts, private.payment_kind(s.descr), private.payment_registration(s.descr), s.descr,
         s.amount, s.side, s.occ, s.blk
    from public.game_statement s
   where s.airline_id = p_airline_id and s.ts = any (p_minutes) and s.flight_id is null
  on conflict (airline_id, paid_at, descr, amount, occ) do update set
    kind = excluded.kind, registration = excluded.registration, side = excluded.side, statement_blk = excluded.statement_blk
  where (p.kind, p.registration, p.side, p.statement_blk)
        is distinct from (excluded.kind, excluded.registration, excluded.side, excluded.statement_blk);
  delete from public.game_payments p
   where p.airline_id = p_airline_id and p.paid_at = any (p_minutes)
     and not exists (select 1 from public.game_statement s
                      where s.airline_id = p_airline_id and s.ts = p.paid_at and s.descr = p.descr
                        and s.amount = p.amount and s.occ = p.occ and s.flight_id is null);
  return v_n;
end
$function$

;

-- private.is_payment_line(p_descr text, p_blk integer)
CREATE OR REPLACE FUNCTION private.is_payment_line(p_descr text, p_blk integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(p_blk, 1) = 0 or private.payment_kind(p_descr) <> 'other'
$function$

;

-- private.is_weekday_set(p_days smallint[])
CREATE OR REPLACE FUNCTION private.is_weekday_set(p_days smallint[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select p_days is not null
     and cardinality(p_days) between 1 and 7
     and array_ndims(p_days) = 1
     and p_days = array(select distinct d from unnest(p_days) as d where d between 1 and 7 order by d)
$function$

;

-- private.json_date(p jsonb)
CREATE OR REPLACE FUNCTION private.json_date(p jsonb)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  if jsonb_typeof(p) is distinct from 'string' or (p #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return (p #>> '{}')::date;
exception when others then
  return null;
end
$function$
;

-- private.json_int(p jsonb)
CREATE OR REPLACE FUNCTION private.json_int(p jsonb)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when n = trunc(n) and abs(n) < 1e15 then n::bigint end from (select private.json_num(p) as n) x
$function$
;

-- private.json_num(p jsonb)
CREATE OR REPLACE FUNCTION private.json_num(p jsonb)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case jsonb_typeof(p)
           when 'number' then (p #>> '{}')::numeric
           when 'string' then case when (p #>> '{}') ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(p #>> '{}')::numeric end
         end
$function$
;

-- private.json_object_or_empty(p text)
CREATE OR REPLACE FUNCTION private.json_object_or_empty(p text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare j jsonb;
begin
  j := p::jsonb;
  return case when jsonb_typeof(j) = 'object' then j else '{}'::jsonb end;
exception when others then
  return '{}'::jsonb;
end
$function$
;

-- private.json_ts(p jsonb)
CREATE OR REPLACE FUNCTION private.json_ts(p jsonb)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  if jsonb_typeof(p) is distinct from 'string'
     or (p #>> '{}') !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}(:?\d{2})?)$' then
    return null;
  end if;
  return (p #>> '{}')::timestamptz;
exception when others then
  return null;
end
$function$
;

-- private.load_planner(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.load_planner(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_extra(p_world_id bigint, s jsonb)
CREATE OR REPLACE FUNCTION private.load_planner_extra(p_world_id bigint, s jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_fleet(p_world_id bigint, s jsonb)
CREATE OR REPLACE FUNCTION private.load_planner_fleet(p_world_id bigint, s jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_loads(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.load_planner_loads(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_money(p_world_id bigint, s jsonb, p_saved_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.load_planner_money(p_world_id bigint, s jsonb, p_saved_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
           st.m as st_cash, fx.m as st_fixed, cap.cash_m, cap.fixed_m, st.airline_id is not null as has_cash
      from st
      full join fx on fx.airline_id = st.airline_id and fx.day = st.day
      full join cap on cap.airline_id = coalesce(st.airline_id, fx.airline_id) and cap.day = coalesce(st.day, fx.day))
  insert into pg_temp.t_load_cash
  select p.airline_id, p.day,
         case when p.st_cash is not null and p.st_cash is distinct from p.cash_m then round(p.st_cash * 1000000, 2) end,
         case when p.st_fixed is distinct from p.fixed_m then round(coalesce(p.st_fixed, 0) * 1000000, 2) end
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
$function$
;

-- private.load_planner_network(p_world_id bigint, s jsonb, d jsonb)
CREATE OR REPLACE FUNCTION private.load_planner_network(p_world_id bigint, s jsonb, d jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_places(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)
CREATE OR REPLACE FUNCTION private.load_planner_places(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_reference(p_world_id bigint, s jsonb, p_growth jsonb)
CREATE OR REPLACE FUNCTION private.load_planner_reference(p_world_id bigint, s jsonb, p_growth jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_tidy(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)
CREATE OR REPLACE FUNCTION private.load_planner_tidy(p_world_id bigint, s jsonb, d jsonb, p_mct jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.load_planner_work(p_world_id bigint, s jsonb)
CREATE OR REPLACE FUNCTION private.load_planner_work(p_world_id bigint, s jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.loads_times(p_world_id bigint, p_game_date date, p_dep_local text, p_arr_local text, p_origin text, p_dest text, OUT dep_at timestamp with time zone, OUT arr_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.loads_times(p_world_id bigint, p_game_date date, p_dep_local text, p_arr_local text, p_origin text, p_dest text, OUT dep_at timestamp with time zone, OUT arr_at timestamp with time zone)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare o int; d int;
begin
  o := private.airport_offset_min(p_world_id, p_origin);
  dep_at := private.local_to_utc(p_game_date, p_dep_local, o);
  if dep_at is null or coalesce(p_arr_local, '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then return; end if;
  d := private.airport_offset_min(p_world_id, p_dest);
  if d is null then return; end if;
  arr_at := dep_at + make_interval(mins => (((split_part(p_arr_local, ':', 1)::int * 60 + split_part(p_arr_local, ':', 2)::int)
                                             - (split_part(p_dep_local, ':', 1)::int * 60 + split_part(p_dep_local, ':', 2)::int)
                                             - (d - o)) % 1440 + 1440) % 1440);
end
$function$

;

-- private.local_to_utc(p_date date, p_time text, p_offset_min integer)
CREATE OR REPLACE FUNCTION private.local_to_utc(p_date date, p_time text, p_offset_min integer)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p_date is not null and p_offset_min is not null and p_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
              then ((p_date + p_time::time) - make_interval(mins => p_offset_min)) at time zone 'UTC' end
$function$

;

-- private.log_change()
CREATE OR REPLACE FUNCTION private.log_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  -- the role the change was made as: authenticated through the data API, postgres for Claude, jobs and migrations
  v_role text := coalesce(nullif(current_setting('role', true), 'none'), session_user);
  v_oldrow jsonb;
  v_newrow jsonb;
  v_old jsonb;
  v_new jsonb;
  v_key jsonb;
  v_world bigint;
  v_actor text := nullif(current_setting('equinox.actor', true), '');
  v_detail text := nullif(current_setting('equinox.actor_detail', true), '');
begin
  -- the data load switches logging off; honoured only for postgres, so the website and planner can't
  if current_setting('equinox.change_log', true) = 'off' and session_user = 'postgres' and v_role = 'postgres' then
    return null;
  end if;
  if tg_op <> 'INSERT' then v_oldrow := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_newrow := to_jsonb(new); end if;
  if tg_op = 'UPDATE' then
    -- only the columns that changed, ignoring updated_at; nothing at all when nothing changed
    select jsonb_object_agg(n.key, v_oldrow -> n.key), jsonb_object_agg(n.key, n.value)
      into v_old, v_new
      from jsonb_each(v_newrow) as n
     where n.key <> 'updated_at' and n.value is distinct from (v_oldrow -> n.key);
    if v_new is null then return null; end if;
  else
    v_old := v_oldrow;   -- a delete keeps the whole old row
    v_new := v_newrow;   -- an insert keeps the whole new row
  end if;
  -- the row's primary key, e.g. {"id": 812}
  select jsonb_object_agg(a.attname, coalesce(v_newrow, v_oldrow) -> a.attname::text)
    into v_key
    from pg_catalog.pg_index i
    cross join lateral unnest(i.indkey::smallint[]) as k(attnum)
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = tg_relid and i.indisprimary;
  v_world := (coalesce(v_newrow, v_oldrow) ->> (case when tg_table_name = 'worlds' then 'id' else 'world_id' end))::bigint;
  -- who: whatever the writer named for its transaction; if nothing, planner for a signed-in user, otherwise unset
  if v_actor is null then
    v_actor := case when auth.uid() is not null then 'planner' else 'unset' end;
  elsif v_actor not in ('planner', 'claude', 'capture', 'script', 'job', 'migration', 'unset') then
    v_detail := concat_ws(' · ', 'named itself ' || v_actor, v_detail);   -- nothing is refused
    v_actor := 'unset';
  end if;
  insert into public.change_log (world_id, table_name, row_key, op, old_values, new_values, actor, actor_detail, db_role, txid)
  values (v_world, tg_table_name, v_key, lower(tg_op), v_old, v_new, v_actor, v_detail, v_role, pg_catalog.txid_current());
  return null;
end
$function$

;

-- private.match_flights(p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.match_flights(p_airline_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  g record; mid bigint[]; mat timestamptz[]; mreg text[]; lid bigint[]; lat timestamptz[]; lreg text[];
  n int; m int; i int; j int; w int; cnt int[]; cst bigint[]; ch smallint[];
  c_best int; k_best bigint; ch_best smallint; gap bigint; matched int := 0;
begin
  for g in
    select f.origin_code, f.dest_code from public.game_flights f
     where f.airline_id = p_airline_id and f.flight_no is null and f.posted_at is not null and f.statement_routes = 1
    intersect
    select f.origin_code, f.dest_code from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at is null and f.flight_no is not null and f.dep_at is not null
  loop
    select array_agg(f.id order by f.posted_at, f.statement_blk), array_agg(f.posted_at order by f.posted_at, f.statement_blk),
           array_agg(f.maint_registration order by f.posted_at, f.statement_blk)
      into mid, mat, mreg
      from public.game_flights f
     where f.airline_id = p_airline_id and f.flight_no is null and f.posted_at is not null and f.statement_routes = 1
       and f.origin_code = g.origin_code and f.dest_code = g.dest_code;
    select array_agg(f.id order by f.dep_at, f.flight_no, f.id), array_agg(f.dep_at order by f.dep_at, f.flight_no, f.id),
           array_agg(f.registration order by f.dep_at, f.flight_no, f.id)
      into lid, lat, lreg
      from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at is null and f.flight_no is not null and f.dep_at is not null
       and f.origin_code = g.origin_code and f.dest_code = g.dest_code;
    n := cardinality(mid); m := cardinality(lid); w := m + 1;
    -- cell (i, j), the best pairing of the first i blocks with the first j loads rows, is at i * w + j + 1
    cnt := array_fill(0, array[(n + 1) * w]);
    cst := array_fill(0::bigint, array[(n + 1) * w]);
    ch := array_fill(0::smallint, array[(n + 1) * w]);
    for i in 1 .. n loop
      for j in 1 .. m loop
        c_best := cnt[(i - 1) * w + j + 1]; k_best := cst[(i - 1) * w + j + 1]; ch_best := 1;   -- block i unpaired
        if cnt[i * w + j] > c_best or (cnt[i * w + j] = c_best and cst[i * w + j] < k_best) then   -- loads row j unpaired
          c_best := cnt[i * w + j]; k_best := cst[i * w + j]; ch_best := 2;
        end if;
        gap := extract(epoch from (mat[i] - lat[j]))::bigint;   -- posted minus scheduled, seconds
        if gap between -1800 and 10800 and (mreg[i] is null or lreg[j] is null or mreg[i] = lreg[j])
           and (cnt[(i - 1) * w + j] + 1 > c_best
                or (cnt[(i - 1) * w + j] + 1 = c_best and cst[(i - 1) * w + j] + abs(gap) <= k_best)) then
          c_best := cnt[(i - 1) * w + j] + 1; k_best := cst[(i - 1) * w + j] + abs(gap); ch_best := 3;   -- paired
        end if;
        cnt[i * w + j + 1] := c_best; cst[i * w + j + 1] := k_best; ch[i * w + j + 1] := ch_best;
      end loop;
    end loop;
    i := n; j := m;
    while i > 0 and j > 0 loop
      if ch[i * w + j + 1] = 3 then
        if private.merge_flight(mid[i], lid[j]) then matched := matched + 1; end if;
        i := i - 1; j := j - 1;
      elsif ch[i * w + j + 1] = 1 then i := i - 1;
      else j := j - 1;
      end if;
    end loop;
  end loop;
  return matched;
end
$function$

;

-- private.merge_flight(p_money_id bigint, p_loads_id bigint)
CREATE OR REPLACE FUNCTION private.merge_flight(p_money_id bigint, p_loads_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare l public.game_flights;
begin
  perform 1 from public.game_flights where id = p_money_id and flight_no is null and posted_at is not null for update;
  if not found then return false; end if;
  delete from public.game_flights where id = p_loads_id and posted_at is null and flight_no is not null returning * into l;
  if not found then return false; end if;
  update public.game_flights
     set game_date = l.game_date, flight_no = l.flight_no, origin_code = l.origin_code, dest_code = l.dest_code,
         dep_local = l.dep_local, arr_local = l.arr_local, dep_at = l.dep_at, arr_at = l.arr_at,
         route_id = coalesce(route_id, l.route_id), aircraft_id = coalesce(aircraft_id, l.aircraft_id),
         registration = l.registration, status = l.status,
         eco_pax = l.eco_pax, eco_seats = l.eco_seats, eco_fare = l.eco_fare, eco_pct = l.eco_pct,
         bus_pax = l.bus_pax, bus_seats = l.bus_seats, bus_fare = l.bus_fare, bus_pct = l.bus_pct,
         fst_pax = l.fst_pax, fst_seats = l.fst_seats, fst_fare = l.fst_fare, fst_pct = l.fst_pct,
         cargo_units = l.cargo_units, cargo_cap = l.cargo_cap, cargo_rate = l.cargo_rate, cargo_pct = l.cargo_pct,
         loads_captured_at = l.loads_captured_at
   where id = p_money_id;
  return true;
end
$function$

;

-- private.payment_kind(p_descr text)
CREATE OR REPLACE FUNCTION private.payment_kind(p_descr text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_descr ilike 'Leasing rate%' then 'lease'
    when p_descr ilike 'Week-end closing%' or p_descr ilike '%salaries%' then 'salaries'
    when p_descr ilike '%deposit%' then 'deposit'
    when p_descr ilike '%purchase%' then 'purchase'
    when p_descr ilike '%configuration%' then 'refit'
    when p_descr ilike '%cabin%' then 'cabin'
    else 'other' end
$function$

;

-- private.payment_registration(p_descr text)
CREATE OR REPLACE FUNCTION private.payment_registration(p_descr text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select substring(p_descr from '(?:for|of) ([A-Z0-9]{1,3}-[A-Z0-9]{2,6}|N[0-9]{1,5}[A-Z]{0,2})(?:$|[ ,.;(])')
$function$

;

-- private.planner_extra(p_item jsonb, p_known text[], p_old_extra jsonb)
CREATE OR REPLACE FUNCTION private.planner_extra(p_item jsonb, p_known text[], p_old_extra jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(p_item) e where e.key <> all (p_known)), '{}'::jsonb)
         || coalesce((select jsonb_object_agg(o.key, o.value) from jsonb_each(coalesce(p_old_extra, '{}'::jsonb)) o
                       where o.key = any (p_known)
                         and ((p_item ? o.key and p_item -> o.key = o.value) or (not p_item ? o.key and o.value = 'null'::jsonb))),
                     '{}'::jsonb)
$function$
;

-- private.planner_json_differences(p_old jsonb, p_new jsonb, p_path text, p_key text, p_in_list boolean)
CREATE OR REPLACE FUNCTION private.planner_json_differences(p_old jsonb, p_new jsonb, p_path text DEFAULT '$'::text, p_key text DEFAULT NULL::text, p_in_list boolean DEFAULT false)
 RETURNS TABLE(path text, kind text)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.restore_row(p_table text, p_row_key jsonb, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.restore_row(p_table text, p_row_key jsonb, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_rel regclass;
  v_keys text[];
  v_cols text[];
  v_match text;
  v_cur jsonb;
  v_state jsonb;
  e record;
begin
  -- only tables the change log covers
  if not exists (select 1 from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid
                  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relname = p_table
                   and t.tgfoid = 'private.log_change()'::pg_catalog.regprocedure) then
    raise exception 'restore_row: % is not a table the change log covers', p_table;
  end if;
  v_rel := pg_catalog.format('public.%I', p_table)::pg_catalog.regclass;
  select array_agg(a.attname::text order by k.ord) into v_keys
    from pg_catalog.pg_index i
    cross join lateral unnest(i.indkey::smallint[]) with ordinality as k(attnum, ord)
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
   where i.indrelid = v_rel and i.indisprimary;
  if p_row_key is null or jsonb_typeof(p_row_key) <> 'object'
     or (select count(*) from jsonb_object_keys(p_row_key)) <> cardinality(v_keys)
     or exists (select 1 from unnest(v_keys) as k where not p_row_key ? k) then
    raise exception 'restore_row: the row key must name exactly the primary key of %: %', p_table, v_keys;
  end if;
  select array_agg(a.attname::text order by a.attnum) into v_cols
    from pg_catalog.pg_attribute a
   where a.attrelid = v_rel and a.attnum > 0 and not a.attisdropped and a.attgenerated = '';
  -- (key columns) = (the same columns read from the given key)
  v_match := pg_catalog.format('(%s) = (select %s from jsonb_populate_record(null::%s, $1) k)',
    (select string_agg(pg_catalog.format('t.%I', c), ', ') from unnest(v_keys) as c),
    (select string_agg(pg_catalog.format('k.%I', c), ', ') from unnest(v_keys) as c), v_rel);

  execute pg_catalog.format('select to_jsonb(t) from %s t where %s', v_rel, v_match) into v_cur using p_row_key;
  -- replay the log backwards, newest first, down to the moment asked for
  v_state := v_cur;
  for e in select op, old_values from public.change_log
            where table_name = p_table and row_key = p_row_key and changed_at > p_as_of
            order by changed_at desc, id desc loop
    if e.op = 'insert' then v_state := null;                                       -- it didn't exist before
    elsif e.op = 'delete' then v_state := e.old_values;                            -- it was there, whole
    else v_state := coalesce(v_state, '{}'::jsonb) || coalesce(e.old_values, '{}'::jsonb);   -- undo the changed columns
    end if;
  end loop;

  if v_state is null then
    if v_cur is not null then
      execute pg_catalog.format('delete from %s t where %s', v_rel, v_match) using p_row_key;
    end if;
  elsif v_cur is null then
    execute pg_catalog.format('insert into %s (%s) overriding system value select %s from jsonb_populate_record(null::%s, $1) r',
      v_rel, (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_cols) as c),
      (select string_agg(pg_catalog.format('r.%I', c), ', ') from unnest(v_cols) as c), v_rel) using v_state;
  elsif v_state is distinct from v_cur then
    execute pg_catalog.format('update %s t set (%s) = (select %s from jsonb_populate_record(null::%s, $2) r) where %s',
      v_rel, (select string_agg(pg_catalog.format('%I', c), ', ') from unnest(v_cols) as c where c <> all (v_keys)),
      (select string_agg(pg_catalog.format('r.%I', c), ', ') from unnest(v_cols) as c where c <> all (v_keys)),
      v_rel, v_match) using p_row_key, v_state;
  end if;
  return v_state;
end
$function$

;

-- private.set_updated_at()
CREATE OR REPLACE FUNCTION private.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' then
    new.updated_at := now();
  elsif (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    new.updated_at := now();
  else
    new.updated_at := old.updated_at;   -- an update that changes nothing leaves the row as it was
  end if;
  return new;
end
$function$

;

-- private.shift_weekdays(p smallint[], p_days integer)
CREATE OR REPLACE FUNCTION private.shift_weekdays(p smallint[], p_days integer)
 RETURNS smallint[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array(select distinct ((((d - 1 + p_days) % 7) + 7) % 7 + 1)::smallint from unnest(p) as d order by 1)
$function$
;

-- private.statement_blocks(p_airline_id bigint, p_minutes timestamp with time zone[])
CREATE OR REPLACE FUNCTION private.statement_blocks(p_airline_id bigint, p_minutes timestamp with time zone[])
 RETURNS TABLE(ts timestamp with time zone, blk integer, is_flight boolean, route text, routes_n integer, pax integer, tail text, pax_income numeric, cargo_income numeric, fuel numeric, onboard numeric, handling numeric, landing numeric, atc numeric, maintenance numeric, income_total numeric, cost_total numeric, captured_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select s.ts, s.blk,
         bool_or(c.cat <> 'other' or c.route is not null),
         max(c.route), count(distinct c.route)::int,
         max((substring(s.descr from 'Passenger handling of (\d+) passengers'))::int),
         max(substring(s.descr from 'Maintenance of ([A-Z0-9-]+)')),
         sum(s.amount) filter (where c.cat = 'pax_income'), sum(s.amount) filter (where c.cat = 'cargo_income'),
         sum(s.amount) filter (where c.cat = 'fuel'), sum(s.amount) filter (where c.cat = 'onboard'),
         sum(s.amount) filter (where c.cat = 'handling'), sum(s.amount) filter (where c.cat = 'landing'),
         sum(s.amount) filter (where c.cat = 'atc'), sum(s.amount) filter (where c.cat = 'maintenance'),
         coalesce(sum(s.amount) filter (where s.side = 'C'), 0),
         coalesce(sum(s.amount) filter (where s.side is distinct from 'C'), 0),
         max(s.captured_at)
    from public.game_statement s
    cross join lateral (select private.statement_category(s.descr) as cat,
                               substring(s.descr from '\(([A-Z]{3}-[A-Z]{3})\)') as route) c
   where s.airline_id = p_airline_id and s.ts = any (p_minutes) and not private.is_payment_line(s.descr, s.blk)
   group by s.ts, s.blk
$function$

;

-- private.statement_category(p_descr text)
CREATE OR REPLACE FUNCTION private.statement_category(p_descr text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_descr = 'Passenger transport income' then 'pax_income'
    when p_descr = 'Cargo transport income' then 'cargo_income'
    when p_descr like 'Fuel%' then 'fuel'
    when p_descr like 'On-board services%' then 'onboard'
    when p_descr like 'Aircraft handling%' or p_descr like 'Passenger handling%' or p_descr like 'Cargo logistic%' then 'handling'
    when p_descr like 'Airport landing fee%' then 'landing'
    when p_descr like 'Air traffic control fee%' then 'atc'
    when p_descr like 'Maintenance of%' then 'maintenance'
    else 'other' end
$function$

;

-- private.weekday_set(p text)
CREATE OR REPLACE FUNCTION private.weekday_set(p text)
 RETURNS smallint[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select nullif(array(select distinct d::smallint from regexp_split_to_table(coalesce(p, ''), '') as d
                       where d ~ '^[1-7]$' order by 1), '{}')
$function$
;

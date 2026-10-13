-- adapter_clean_days(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.adapter_clean_days(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare w bigint; v_day date; n int := 0;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  select x.id into w from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default);
  if w is null then raise exception 'no such world: %', p_world_id; end if;
  -- the capture day p_as_of falls in, as private.capture_day() works it out
  v_day := ((p_as_of at time zone 'UTC')
            - coalesce((select (s.value #>> '{}')::time from public.settings s
                         where s.world_id = w and s.airline_id is null and s.key = 'capture_day_starts_utc'), time '10:00')::interval)::date;
  if not exists (select 1 from public.adapter_check_days d where d.world_id = w and d.day = v_day) then
    v_day := v_day - 1;
  end if;
  while exists (select 1 from public.adapter_check_days d where d.world_id = w and d.day = v_day and d.clean) loop
    n := n + 1;
    v_day := v_day - 1;
  end loop;
  return n;
end
$function$
;

-- aircraft_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.aircraft_profit(p_airline_id bigint, p_days integer DEFAULT 7, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_route_profit(p_airline_id, p_days, coalesce(p_as_of, now()));
  return jsonb_build_object('airline_id', p_airline_id, 'days', p_days, 'as_of', d -> 'as_of', 'since', d -> 'since', 'aircraft', d -> 'aircraft');
end
$function$

;

-- airline_cards(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.airline_cards(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_airline_cards(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$

;

-- airline_profit(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.airline_profit(p_airline_id bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_fin_stats(p_airline_id, coalesce(p_as_of, now()));
  return jsonb_build_object('airline_id', p_airline_id, 'as_of', d -> 'as_of', 'profit_day', d -> 'profit_day',
                            'span_days', d -> 'span_days', 'early', d -> 'early', 'days', d -> 'days');
end
$function$

;

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
  return private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
end
$function$
;

-- capture_status(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.capture_status(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_capture_status(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$

;

-- cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.cash_forecast(p_airline_id bigint, p_orders jsonb DEFAULT '[]'::jsonb, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_cash_forecast(p_airline_id, coalesce(p_orders, '[]'::jsonb), coalesce(p_as_of, now()));
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
 SET search_path TO ''
AS $function$
declare v_arg jsonb;
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
  elsif p_kind = 'figures' then
    -- the captured figures (design §8) for every airline; p_arg: {"as_of": ..., "world": ...}, both optional
    v_arg := coalesce(nullif(btrim(coalesce(p_arg, '')), '')::jsonb, '{}'::jsonb);
    if jsonb_typeof(v_arg) <> 'object' then raise exception 'figures: p_arg is a JSON object, {"as_of": ..., "world": ...}' using errcode = '22023'; end if;
    return private.fig_export(private.fig_world((v_arg ->> 'world')::bigint), coalesce((v_arg ->> 'as_of')::timestamptz, now()));
  end if;
  raise exception 'unknown kind';
end
$function$

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

-- fare_changes(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.fare_changes(p_airline_id bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_route_profit(p_airline_id, 7, coalesce(p_as_of, now()));
  return jsonb_build_object('airline_id', p_airline_id, 'as_of', d -> 'as_of', 'changes', d -> 'fare_changes');
end
$function$

;

-- growth_signals(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.growth_signals(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_growth_signals(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$

;

-- hub_progress(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.hub_progress(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_hub_progress(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$

;

-- ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
CREATE OR REPLACE FUNCTION public.ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_world bigint; v_scan bigint; v_al bigint; v_res jsonb; n int := 0;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('start', 'airline', 'airport', 'finish', 'markets') then raise exception 'unknown kind'; end if;
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'ingest_snapshot'), true);
  if p_kind = 'start' then
    select x.id into v_world from public.worlds x where x.is_default;
    insert into public.game_scans (world_id, week, note) values (v_world, p_payload ->> 'week', p_payload ->> 'note')
    returning id into v_scan;
    v_res := jsonb_build_object('snapshot_id', v_scan);
  else
    select s.id, s.world_id into v_scan, v_world from public.game_scans s where s.id = (p_payload ->> 'snapshot_id')::bigint;
    if v_scan is null and p_kind <> 'finish' then
      raise exception 'no such scan: %', coalesce(p_payload ->> 'snapshot_id', '(none)');
    end if;
    if p_kind = 'airline' then
      v_al := private.scan_airline(v_world, (p_payload ->> 'enterprise_id')::int, p_payload ->> 'name');
      insert into public.game_scan_airlines as x (scan_id, world_id, enterprise_id, airline_id, name, n_flights, n_weekly, n_airports, position)
      values (v_scan, v_world, (p_payload ->> 'enterprise_id')::int, v_al, p_payload ->> 'name',
              (p_payload ->> 'n_flights')::int, (p_payload ->> 'n_weekly')::int, (p_payload ->> 'n_airports')::int,
              (select coalesce(max(y.position), 0) + 1 from public.game_scan_airlines y where y.scan_id = v_scan))
      on conflict (scan_id, enterprise_id) do update set airline_id = excluded.airline_id, name = excluded.name,
        n_flights = excluded.n_flights, n_weekly = excluded.n_weekly, n_airports = excluded.n_airports;
      insert into public.game_scan_schedules as x (scan_id, world_id, airline_id, flights)
      values (v_scan, v_world, v_al, coalesce(p_payload -> 'flights', '[]'::jsonb))
      on conflict (scan_id, airline_id) do update set flights = excluded.flights;
      v_res := jsonb_build_object('ok', true);
    elsif p_kind = 'airport' then
      -- the airlines stationed there are airlines the scan saw too
      perform private.scan_airline(v_world, (st ->> 'enterprise_id')::int, st ->> 'name')
         from jsonb_array_elements(case when jsonb_typeof(p_payload -> 'stations') = 'array' then p_payload -> 'stations' else '[]'::jsonb end) st
        where (st ->> 'enterprise_id') ~ '^\d{1,9}$';
      insert into public.game_scan_airports as x (scan_id, world_id, airport_code, game_airport_id, info, stations, news, position)
      values (v_scan, v_world, p_payload ->> 'code', (p_payload ->> 'airport_id')::int, p_payload -> 'info',
              p_payload -> 'stations', p_payload -> 'news',
              (select coalesce(max(y.position), 0) + 1 from public.game_scan_airports y where y.scan_id = v_scan))
      on conflict (scan_id, airport_code) do update set game_airport_id = excluded.game_airport_id, info = excluded.info,
        stations = excluded.stations, news = excluded.news;
      v_res := jsonb_build_object('ok', true);
    elsif p_kind = 'finish' then
      if v_scan is not null then
        update public.game_scans set status = 'done', note = coalesce(p_payload ->> 'note', note) where id = v_scan;
        perform private.scan_summarise(v_scan);
      end if;
      v_res := jsonb_build_object('ok', true);
    elsif p_kind = 'markets' then
      if jsonb_typeof(p_payload -> 'markets') is distinct from 'array' then
        raise exception 'markets: the payload needs a list, markets: [{enterprise_id, market, weekly_departures, city_pairs}]';
      end if;
      perform private.scan_airline(v_world, x.game_id, null)
         from (select distinct (m ->> 'enterprise_id')::int as game_id from jsonb_array_elements(p_payload -> 'markets') m
                where (m ->> 'enterprise_id') ~ '^\d{1,9}$') x;
      delete from public.scan_airline_markets where scan_id = v_scan;
      insert into public.scan_airline_markets (scan_id, world_id, airline_id, market, weekly_departures, city_pairs)
      select v_scan, v_world, al.id, m ->> 'market', (m ->> 'weekly_departures')::int, (m ->> 'city_pairs')::int
        from jsonb_array_elements(p_payload -> 'markets') m
        join public.airlines al on al.world_id = v_world and al.game_id = (m ->> 'enterprise_id')::int
       where (m ->> 'enterprise_id') ~ '^\d{1,9}$' and coalesce(m ->> 'market', '') <> '';
      get diagnostics n = row_count;
      v_res := jsonb_build_object('ok', true, 'rows', n);
    end if;
  end if;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return v_res;
end
$function$
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

-- loads_day_captured(p_world_id bigint, p_day date)
CREATE OR REPLACE FUNCTION public.loads_day_captured(p_world_id bigint, p_day date)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_from timestamptz;
begin
  if not (current_user = 'postgres' or public.is_planner_user()) then
    raise exception 'only planner staff can read the planner' using errcode = '42501';
  end if;
  -- the date's capture day starts at capture_day_starts_utc (design §2)
  v_from := (p_day + coalesce((select (s.value #>> '{}')::time from public.settings s
                               where s.world_id = p_world_id and s.airline_id is null and s.key = 'capture_day_starts_utc'),
                              time '10:00')) at time zone 'UTC';
  return exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = p_world_id and a.active and g.kind = 'ours')
     and not exists (
           select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
            where a.world_id = p_world_id and a.active and g.kind = 'ours'
              and not exists (select 1 from public.game_flights f
                               where f.airline_id = a.id and f.game_date = p_day and f.flight_no is not null
                                 and f.loads_captured_at >= v_from)
              and not exists (select 1 from public.game_capture_raw r
                               where r.airline_id = a.id and r.kind = 'loads'
                                 and r.captured_at >= v_from and r.captured_at < v_from + interval '1 day'));
end
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
 SET search_path TO ''
AS $function$
declare w bigint; v_tables jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  -- the old planner reads its route research from here until #18
  insert into public.planner_data as x (key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  if p_key = 'DATA' then
    -- the change log names the script, unless the caller named itself (design §6)
    perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
            set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'planner_data_set'), true);
    select x.id into w from public.worlds x where x.is_default;
    v_tables := private.research_apply(w, p_value);
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  end if;
  return jsonb_build_object('ok', true, 'bytes', length(p_value::text))
         || case when v_tables is null then '{}'::jsonb else jsonb_build_object('tables', v_tables) end;
end
$function$
;

-- planner_item_delete(p_section text, p_key text)
CREATE OR REPLACE FUNCTION public.planner_item_delete(p_section text, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_res jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  select x.id into w from public.worlds x where x.is_default;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  v_res := private.planner_apply(w, private.planner_doc_with_item((public.planner_state_get(w) ->> 'json')::jsonb, p_section, p_key, null),
                                 'item', null, null, null, null);
  return jsonb_build_object('saved_at', public.planner_state_version(w), 'applied', v_res -> 'applied', 'skipped', 0, 'reload', false);
end
$function$
;

-- planner_item_put(p_section text, p_key text, p_value jsonb)
CREATE OR REPLACE FUNCTION public.planner_item_put(p_section text, p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_res jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  if p_value is null or p_value = 'null'::jsonb then
    raise exception 'planner_item_put needs a value: planner_item_delete removes an item' using errcode = '22023';
  end if;
  select x.id into w from public.worlds x where x.is_default;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  v_res := private.planner_apply(w, private.planner_doc_with_item((public.planner_state_get(w) ->> 'json')::jsonb, p_section, p_key, p_value),
                                 'item', null, null, null, null);
  return jsonb_build_object('saved_at', public.planner_state_version(w), 'applied', v_res -> 'applied', 'skipped', 0, 'reload', false);
end
$function$
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
      -- the one rule (design §8): every active airline of the world was captured for that date
      cross join lateral (select public.loads_day_captured(w, d.day) as complete) c)
  select to_char(dd.day, 'YYYY-MM'),
         jsonb_object_agg(dd.day::text, dd.j)::text,
         coalesce(floor(extract(epoch from max(dd.at)) * 1000)::bigint, 0)
    from doc_days dd
   group by to_char(dd.day, 'YYYY-MM')
   order by 1;
end
$function$
;

-- planner_save(p_changes jsonb, p_client text)
CREATE OR REPLACE FUNCTION public.planner_save(p_changes jsonb, p_client text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    if v_key = 'null'::jsonb then v_key := null; end if;
    if v_vals = 'null'::jsonb then v_vals := null; end if;
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
      if coalesce(v_vals, '{}'::jsonb) = '{}'::jsonb then
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
    v_list := v_list || jsonb_build_array(jsonb_build_object('n', i, 'table', v_table, 'op', v_op, 'key', v_key,
                                                             'values', v_vals, 'base', c ->> 'base', 'pk', to_jsonb(v_pk)));
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
    select string_agg(format('t.%1$I = k.%1$I', p), ' and ') into v_where from jsonb_array_elements_text(c -> 'pk') as p;
    if c ->> 'op' = 'insert' then
      select string_agg(format('%I', k), ', ' order by k), string_agg(format('r.%I', k), ', ' order by k)
        into v_names, v_from from jsonb_object_keys(c -> 'values') as k;
      execute format('insert into public.%1$I as t (%2$s) select %3$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r '
                     'returning to_jsonb(t), t.updated_at', v_table, v_names, v_from)
         into v_row, v_at using c -> 'values';
    elsif c ->> 'op' = 'update' then
      select string_agg(format('%1$I = r.%1$I', k), ', ' order by k) into v_names from jsonb_object_keys(c -> 'values') as k;
      execute format('update public.%1$I t set %2$s from pg_catalog.jsonb_populate_record(null::public.%1$I, $1) r, '
                     'pg_catalog.jsonb_populate_record(null::public.%1$I, $2) k where %3$s returning to_jsonb(t), t.updated_at',
                     v_table, v_names, v_where)
         into v_row, v_at using c -> 'values', c -> 'key';
    else
      execute format('delete from public.%1$I t using pg_catalog.jsonb_populate_record(null::public.%1$I, $1) k where %2$s '
                     'returning to_jsonb(t)', v_table, v_where)
         into v_row using c -> 'key';
      v_at := null;
    end if;
    if v_row is null then
      raise exception 'planner_save: change %: the row wasn''t there to %', c ->> 'n', c ->> 'op';
    end if;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'table', v_table, 'op', c ->> 'op',
      'key', (select jsonb_object_agg(p, v_row -> p) from jsonb_array_elements_text(c -> 'pk') as p),
      'updated_at', to_jsonb(v_at)));
  end loop;
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return jsonb_build_object('ok', true, 'rows', v_rows);
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

  -- ---------- ref: hubs, consts, types, configs, services, markets, curfews, utcOverrides, timeMode, gameLinks. A layout
  -- with no type, or a market with no default layout or aircraft, has "" (as the planner adds them); a layout's seats
  -- left empty are ""; its cabin is as typed
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
                  'code', c.code, 'type', coalesce(t.name, ''), 'cabin', c.cabin, 'seats', coalesce(to_jsonb(c.seats), '""'),
                  'c', c.business_seats, 'y', c.economy_seats, 'costM', trim_scale(c.cost / 1000000),
                  'note', c.note)) order by c.id), '[]'::jsonb)
                  from public.cabin_configs c left join public.aircraft_types t on t.id = c.aircraft_type_id
                 where c.world_id = w),
    'services', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                   'code', p.code, 'airline', coalesce(al.planner_name, 'Legacy'), 'upTo', p.up_to_km, 'note', p.note))
                   order by p.id), '[]'::jsonb)
                   from public.service_profiles p left join public.airlines al on al.id = p.airline_id
                  where p.world_id = w),
    'markets', (select coalesce(jsonb_object_agg(al.planner_name || '|' || m.name,
                  jsonb_build_object('config', coalesce(c.code, ''), 'aircraft', coalesce(t.name, ''), 'priceY', trim_scale(m.fare_y_pct),
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

  -- ---------- routes added (a route with no market has ""), route edits (market "" when the edit clears it; {} for an
  -- edit that changes nothing, as restoring a removed route leaves it), route cabins
  select coalesce(jsonb_agg(jsonb_build_array(al.planner_name, r.hub_code, r.dest_code, r.city, r.country_label, r.distance_km,
                                              coalesce(m.name, ''), r.stars) order by r.id), '[]'::jsonb)
    into v_added
    from public.routes r join public.airlines al on al.id = r.airline_id left join public.markets m on m.id = r.market_id
   where r.world_id = w and r.source = 'added';
  select coalesce(jsonb_object_agg(al.planner_name || '|' || r.hub_code || '|' || r.dest_code,
           jsonb_strip_nulls(jsonb_build_object('removed', case when r.removed then true end, 'note', r.removed_note,
             'city', r.city_override, 'dist', r.distance_override_km,
             'market', case when r.market_cleared then '' else mo.name end, 'stars', r.stars_override))), '{}'::jsonb)
    into v_edits
    from public.routes r join public.airlines al on al.id = r.airline_id left join public.markets mo on mo.id = r.market_override_id
   where r.world_id = w
     and (r.edit_kept or r.removed or r.removed_note is not null or r.city_override is not null or r.distance_override_km is not null
          or r.market_override_id is not null or r.market_cleared or r.stars_override is not null);
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

-- planner_state_put(p_json text, p_saved_at bigint, p_base bigint, p_client text)
CREATE OR REPLACE FUNCTION public.planner_state_put(p_json text, p_saved_at bigint, p_base bigint, p_client text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_doc jsonb; v_res jsonb; v_since timestamptz;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can save the planner' using errcode = '42501'; end if;
  begin
    v_doc := p_json::jsonb;
  exception when others then
    raise exception 'the planner document isn''t JSON' using errcode = '22023';
  end;
  if jsonb_typeof(v_doc) is distinct from 'object' then raise exception 'the planner document isn''t a JSON object' using errcode = '22023'; end if;
  select x.id into w from public.worlds x where x.is_default;
  -- the last microsecond of the base's millisecond (exact interval arithmetic, no floating point)
  v_since := timestamptz 'epoch' + (coalesce(p_base, p_saved_at) + 1) * interval '1 millisecond' - interval '1 microsecond';
  v_res := private.planner_apply(w, v_doc, 'save', v_since, nullif(p_client, ''), 'planner', nullif(p_client, ''));
  return jsonb_build_object('saved_at', public.planner_state_version(w), 'applied', v_res -> 'applied',
                            'skipped', v_res -> 'skipped', 'reload', (v_res ->> 'skipped')::int > 0,
                            'skipped_items', v_res -> 'skipped_items');
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

-- route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.route_profit(p_airline_id bigint, p_days integer DEFAULT 7, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_route_profit(p_airline_id, p_days, coalesce(p_as_of, now())) - 'aircraft' - 'fare_changes';
end
$function$

;

-- rules_input(p_world_id bigint)
CREATE OR REPLACE FUNCTION public.rules_input(p_world_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then
    raise exception 'only planner staff can read the planning rules' using errcode = '42501';
  end if;
  return private.rules_input_doc(p_world_id);
end
$function$
;

-- save_loads(p_month text, p_days jsonb)
CREATE OR REPLACE FUNCTION public.save_loads(p_month text, p_days jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cur jsonb; d text; p jsonb; day jsonb; f jsonb; v_days jsonb := '{}'::jsonb; w bigint; v_saved bigint;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
  v_frozen boolean := private.planner_frozen_since('public.planner_loads'::regclass) is not null;
begin
  if not public.is_planner_user() then raise exception 'only planner staff can save loads' using errcode = '42501'; end if;
  if p_month is null or p_month !~ '^\d{4}-\d{2}$' then raise exception 'month must be YYYY-MM, got %', p_month; end if;
  if jsonb_typeof(p_days) is distinct from 'object' then raise exception 'days must be an object keyed by date'; end if;
  select x.id into w from public.worlds x where x.is_default;
  if v_frozen then
    -- two saves of one month queue instead of racing
    perform pg_advisory_xact_lock(hashtextextended('equinox loads ' || p_month, w));
    select g.json::jsonb into cur from public.planner_loads_get(w) g where g.month = p_month;
  else
    insert into public.planner_loads (month, json, saved_at) values (p_month, '{}', 0) on conflict (month) do nothing;
    select pl.json::jsonb into cur from public.planner_loads pl where pl.month = p_month for update;
  end if;
  cur := coalesce(cur, '{}'::jsonb) - '__savedAt';   -- a browser-only marker that older saves wrote into the document
  for d, p in select e.key, e.value from jsonb_each(p_days) e loop
    if d !~ ('^' || p_month || '-\d{2}$') then raise exception 'day % is not in month %', d, p_month; end if;
    if jsonb_typeof(p) is distinct from 'object' then raise exception 'day % must be an object', d; end if;
    day := coalesce(cur -> d, '{"done": false, "f": {}}'::jsonb);
    if p ? 'f' then
      f := coalesce(p -> 'f', '{}'::jsonb);                                          -- the whole day's entry, as typed
    else
      f := (coalesce(day -> 'f', '{}'::jsonb) || coalesce(p -> 'set', '{}'::jsonb))   -- single flights: set these ...
           - array(select jsonb_array_elements_text(coalesce(p -> 'del', '[]'::jsonb)));   -- ... and clear these
    end if;
    day := jsonb_set(day, '{f}', f, true);
    if p ? 'done' then day := day || jsonb_build_object('done', p -> 'done'); end if;
    if p ? 'savedAt' then day := day || jsonb_build_object('savedAt', p -> 'savedAt'); end if;
    cur := jsonb_set(cur, array[d], day, true);
    v_days := v_days || jsonb_build_object(d, day);
  end loop;

  if v_frozen then
    perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', 'save_loads', true);
    perform private.loads_mirror_days(w, v_days, now());
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
    select g.json::jsonb, g.saved_at into cur, v_saved from public.planner_loads_get(w) g where g.month = p_month;
    return jsonb_build_object('month', p_month, 'json', coalesce(cur, '{}'::jsonb), 'saved_at', coalesce(v_saved, ms));
  end if;

  begin
    perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', 'save_loads', true);
    perform private.loads_mirror_days(w, v_days, now());
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  exception when others then
    perform private.job_run_add('adapter_mirror', w, clock_timestamp(), 'failed', 'save_loads: ' || sqlerrm,
                                jsonb_build_object('table', 'planner_loads', 'month', p_month, 'sqlstate', sqlstate));
  end;
  update public.planner_loads set json = cur::text, saved_at = ms where month = p_month;
  return jsonb_build_object('month', p_month, 'json', cur, 'saved_at', ms);
end
$function$
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
 SET search_path TO ''
AS $function$
declare v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'post' then
    insert into public.site_posts as x (slug, published_at, title, summary, body, tag, airline, image, image_credit, auto)
    values (p_payload->>'slug', coalesce((p_payload->>'at')::timestamptz, now()), p_payload->>'title', p_payload->>'summary', p_payload->>'body',
            p_payload->>'tag', p_payload->>'airline', p_payload->>'image', p_payload->>'credit', coalesce((p_payload->>'auto')::boolean, false))
    on conflict (slug) do update set published_at = excluded.published_at, title = excluded.title, summary = excluded.summary, body = excluded.body,
      tag = excluded.tag, airline = excluded.airline, image = excluded.image, image_credit = excluded.image_credit;
  elsif p_kind = 'report' then
    insert into public.site_reports as x (kind, period, title, summary, published_at, status, pdf_b64)
    values (p_payload->>'kind', p_payload->>'period', p_payload->>'title', p_payload->>'summary', (p_payload->>'at')::timestamptz,
            coalesce(p_payload->>'status', 'published'), p_payload->>'pdf')
    on conflict (kind, period) do update set title = excluded.title, summary = excluded.summary, published_at = excluded.published_at,
      status = excluded.status, pdf_b64 = coalesce(excluded.pdf_b64, x.pdf_b64);
  elsif p_kind = 'content' then
    if p_payload->>'key' = 'mct' then
      -- connection times live in world_airports (design §2), which site_public() reads; the change log names the script,
      -- unless the caller named itself (design §6)
      perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
              set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'site_admin'), true);
      perform private.world_mct_set((select x.id from public.worlds x where x.is_default), p_payload->'value');
      perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
    end if;
    -- kept for every key, mct included: until the switch-over the adapter falls back on site_content.mct for a hub
    insert into public.site_content as x (key, value) values (p_payload->>'key', p_payload->'value')
    on conflict (key) do update set value = excluded.value, updated_at = now();
  else raise exception 'unknown kind'; end if;
  return jsonb_build_object('ok', true);
end
$function$
;

-- site_investor(p_password text)
CREATE OR REPLACE FUNCTION public.site_investor(p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h text; w bigint; v_doc jsonb;
begin
  select r.pass_hash into h from public.report_access r limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then return jsonb_build_object('ok', false); end if;
  select x.id into w from public.worlds x where x.is_default;
  -- cash and next-7-day costs exactly as the planner gets them (design §8): the capture's figure unless typed by hand
  v_doc := (public.planner_state_get(w) ->> 'json')::jsonb;
  return jsonb_build_object('ok', true, 'cash', v_doc -> 'cash', 'fixed7', v_doc -> 'fixed7',
    -- money spent, in the planner's order and millions; orders were logged without a kind
    'capex', (select coalesce(jsonb_agg(jsonb_build_object('date', s.spent_on::text, 'airline', al.planner_name,
                                                           'm', trim_scale(s.amount / 1000000),
                                                           'kind', case when s.kind <> 'order' then s.kind end) order by s.id), '[]'::jsonb)
                from public.spending_log s join public.airlines al on al.id = s.airline_id
               where s.world_id = w),
    'markets', (select c.value from public.site_content c where c.key = 'markets'),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period', r.period, 'title', r.title,
                                                             'summary', r.summary, 'at', r.published_at, 'status', r.status,
                                                             'has_pdf', r.pdf_b64 is not null)
                                          order by coalesce(r.published_at, now() + interval '1 year') desc), '[]'::jsonb)
                  from public.site_reports r where r.kind <> 'newsletter'));
end
$function$
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
 SET search_path TO ''
AS $function$
  with w as (select x.id from public.worlds x where x.is_default),
  -- each frequency as planner_state_get() gives it (the same joins and local times, design §4), in its order
  freqs as (
    select r.id, r.airline_id, ro.hub_code,
           jsonb_build_object(
             'routeKey', al.planner_name || '|' || ro.hub_code || '|' || ro.dest_code,
             'days', (select string_agg(d::text, '' order by d) from unnest(x.days_local) as d),
             'tail', coalesce(ac.registration, ''),
             'noOut', coalesce(l1.flight_no::text, ''),
             'noBack', coalesce(l2.flight_no::text, ''),
             'depHub', coalesce(to_char(make_time(x.dep_hub / 60, x.dep_hub % 60, 0), 'HH24:MI'), ''),
             'arrDest', coalesce(to_char(make_time(x.arr_dest / 60, x.arr_dest % 60, 0), 'HH24:MI'), ''),
             'depDest', coalesce(to_char(make_time(x.dep_dest / 60, x.dep_dest % 60, 0), 'HH24:MI'), ''),
             'arrHub', coalesce(to_char(make_time(x.arr_hub / 60, x.arr_hub % 60, 0), 'HH24:MI'), ''),
             'launched', r.launched_on::text)
           || r.extra as j
      from w
      join public.rotations r on r.world_id = w.id
      join public.routes ro on ro.id = r.route_id
      join public.airlines al on al.id = r.airline_id
      left join public.flight_legs l1 on l1.rotation_id = r.id and l1.leg_no = 1
      left join public.flight_legs l2 on l2.rotation_id = r.id and l2.leg_no = 2
      left join public.aircraft ac on ac.id = coalesce(l1.aircraft_id, l2.aircraft_id)
      left join public.airports ah on ah.code = ro.hub_code
      left join public.world_airports wh on wh.world_id = w.id and wh.airport_code = ro.hub_code
      left join public.airports ad on ad.code = ro.dest_code
      left join public.world_airports wd on wd.world_id = w.id and wd.airport_code = ro.dest_code
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
                                         from unnest(l1.days_utc) as d order by 1) end as days_local) dl) x),
  -- each aircraft flying (a tail in the old planner), in the tails list's order
  tails as (
    select a.id, (a.extra ->> 'tails_index')::int as ord,
           jsonb_strip_nulls(jsonb_build_object('id', a.registration, 'airline', al.planner_name, 'type', coalesce(t.name, '')))
           || coalesce(a.extra -> 'tail', '{}'::jsonb) as j
      from w
      join public.aircraft a on a.world_id = w.id and a.extra ? 'tails_index'
      join public.airlines al on al.id = a.airline_id
      left join public.aircraft_types t on t.id = a.aircraft_type_id)
  select jsonb_build_object(
    -- when the planner's data last changed (planner_state_version())
    'updated_at', (select to_timestamp(nullif(public.planner_state_version(w.id), 0) / 1000.0) from w),
    -- our airlines in the world the website shows, in display order: what the website used to keep in its code
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                   'key', a.planner_name, 'name', a.public_name, 'code', a.iata_code, 'color', a.livery_color,
                   'slug', a.slug, 'region', a.region_text, 'role', a.role_text, 'blurb', a.blurb, 'photo', a.photo_city,
                   'position', a.position) order by a.position nulls last, a.id), '[]'::jsonb)
                   from w
                   join public.airlines a on a.world_id = w.id
                   join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where g.kind = 'ours' and a.active and a.planner_name is not null),
    -- hubs and focus cities an airline of theirs flies from: code, airline and role only (no banks, no connection times)
    'hubs', (select coalesce(jsonb_agg(jsonb_build_object('code', b.airport_code, 'airline', al.planner_name, 'role', b.role)
                                       order by b.position, b.id), '[]'::jsonb)
               from w
               join public.airline_bases b on b.world_id = w.id
               join public.airlines al on al.id = b.airline_id
              where exists (select 1 from freqs f where f.airline_id = b.airline_id and f.hub_code = b.airport_code)),
    'tails', (select coalesce(jsonb_agg(jsonb_build_object('id', t.j ->> 'id', 'airline', t.j ->> 'airline', 'type', t.j ->> 'type')
                                        order by t.ord, t.id), '[]'::jsonb) from tails t),
    'freqs', (select coalesce(jsonb_agg(jsonb_build_object('r', f.j ->> 'routeKey', 't', f.j ->> 'tail', 'a', f.j ->> 'depHub',
                                                           'b', f.j ->> 'arrDest', 'c', f.j ->> 'depDest', 'd', f.j ->> 'arrHub',
                                                           'days', f.j ->> 'days', 'o', f.j ->> 'noOut', 'k', f.j ->> 'noBack',
                                                           'l', f.j ->> 'launched') order by f.id), '[]'::jsonb) from freqs f),
    -- signed interline agreements, in the order the old document's keys came in (jsonb: shorter keys first, then bytes)
    'interline', (select coalesce(jsonb_agg(jsonb_build_object('pair', x.pair, 'partner', x.partner, 'date', x.date)
                                            order by octet_length(x.pair), x.pair collate "C"), '[]'::jsonb)
                    from (select al.planner_name || '|' || i.country_code as pair, i.partner, i.decided_on::text as date
                            from w
                            join public.interline_agreements i on i.world_id = w.id
                            join public.airlines al on al.id = i.airline_id
                           where i.status = 'signed') x),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', p.slug, 'at', p.published_at, 'title', p.title, 'summary', p.summary,
                                                           'body', p.body, 'tag', p.tag, 'airline', p.airline, 'image', p.image,
                                                           'credit', p.image_credit) order by p.published_at desc), '[]'::jsonb)
                from public.site_posts p),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period', r.period, 'title', r.title,
                                                             'summary', case when r.kind = 'newsletter' then r.summary end,
                                                             'at', r.published_at, 'status', r.status, 'has_pdf', r.pdf_b64 is not null)
                                          order by coalesce(r.published_at, now() + interval '1 year') desc), '[]'::jsonb)
                  from public.site_reports r),
    -- site_content's keys (photos, logos ...; markets is the investors'), with mct from world_airports, and the longest
    -- wait for a connection from settings (connection_max_wait_h, hours, manual §4), for the trip search (#19)
    'content', coalesce((select jsonb_object_agg(c.key, c.value) from public.site_content c where c.key not in ('markets', 'mct')), '{}'::jsonb)
               || coalesce((select jsonb_build_object('mct', jsonb_object_agg(wa.airport_code, wa.mct_min))
                              from w join public.world_airports wa on wa.world_id = w.id
                             where wa.mct_min is not null
                            having count(*) > 0), '{}'::jsonb)
               || coalesce((select jsonb_build_object('connection_max_wait_h', (s.value #>> '{}')::numeric)
                              from w join public.settings s on s.world_id = w.id
                             where s.airline_id is null and s.key = 'connection_max_wait_h'
                               and (s.value #>> '{}') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$'), '{}'::jsonb)
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
 SET search_path TO ''
AS $function$
declare m jsonb;
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  -- one of our airlines (by the planner's name for it) in the world the planner shows (#14), not a list in the code
  if not exists (select 1 from public.airlines a
                   join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                   join public.worlds x on x.id = a.world_id and x.is_default
                  where a.planner_name = p_airline and g.kind = 'ours')
     or p_url is null or p_url !~ '^https://' then
    raise exception 'bad input';
  end if;
  select c.value into m from public.site_content c where c.key = 'media';
  m := coalesce(m, '{}'::jsonb);
  m := jsonb_set(m, '{logos}', coalesce(m->'logos', '{}'::jsonb), true);
  m := jsonb_set(m, array['logos', p_airline], jsonb_strip_nulls(jsonb_build_object('url', p_url, 'path', p_path, 'at', now())), true);
  insert into public.site_content as x (key, value) values ('media', m) on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true);
end
$function$
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

-- private.adapter_mirror_loads()
CREATE OR REPLACE FUNCTION private.adapter_mirror_loads()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; t0 timestamptz := clock_timestamp(); t1 timestamptz; v_doc jsonb; v_res jsonb; v_got jsonb;
  v_n int; v_note text; v_details jsonb; v_json text; v_saved bigint; v_ver text;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  select p.json, p.saved_at, p.ctid::text into v_json, v_saved, v_ver from public.planner_loads p where p.month = new.month;
  if not found or private.adapter_seen('planner_loads ' || new.month || ' ' || v_ver) then return null; end if;
  begin
    select x.id into w from public.worlds x where x.is_default;
    begin
      v_doc := v_json::jsonb;
      if jsonb_typeof(v_doc) is distinct from 'object' then raise exception 'planner_loads.json isn''t a JSON object'; end if;
      perform set_config('equinox.actor', 'planner', true), set_config('equinox.actor_detail', 'mirror', true);
      v_res := private.loads_mirror_days(w, (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(v_doc) e
                                               where e.key like new.month || '-%'), now());
      perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
      perform private.job_run_add('adapter_mirror', w, t0, 'ok',
        case when (v_res ->> 'load_entries')::int + (v_res ->> 'load_days')::int = 0 then 'planner_loads ' || new.month || ': nothing to copy'
             else 'planner_loads ' || new.month || ': copied ' || (v_res ->> 'load_entries') || ' load(s), ' || (v_res ->> 'load_days') || ' day flag(s)' end,
        jsonb_build_object('table', 'planner_loads', 'month', new.month, 'rows', v_res,
                           'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)));
    exception when others then
      perform private.job_run_add('adapter_mirror', w, t0, 'failed', 'planner_loads ' || new.month || ': ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_loads', 'month', new.month, 'sqlstate', sqlstate));
    end;
    t1 := clock_timestamp();
    begin
      select g.json::jsonb into v_got from public.planner_loads_get(w) g where g.month = new.month;
      with c as (select * from private.planner_json_diff(v_doc, coalesce(v_got, '{}'::jsonb)))
      select count(*) filter (where c.kind = 'differs'),
             (select string_agg(z.place || ' ×' || z.n, ', ' order by z.place)
                from (select private.planner_place(c2.path) as place, count(*) as n from c c2 where c2.kind = 'differs' group by 1) z),
             jsonb_build_object('table', 'planner_loads', 'month', new.month, 'saved_at', v_saved,
               'paths', coalesce((select jsonb_agg(z.path order by z.path) from (select c2.path from c c2 where c2.kind = 'differs' order by c2.path limit 200) z), '[]'::jsonb),
               'allowed', coalesce((select jsonb_object_agg(z.kind, z.n) from (select c2.kind, count(*) as n from c c2 where c2.kind <> 'differs' group by 1) z), '{}'::jsonb),
               'ms', round(extract(epoch from clock_timestamp() - t1) * 1000))
        into v_n, v_note, v_details
        from c;
      perform private.job_run_add('adapter_check', w, t1, case when v_n = 0 then 'ok' else 'failed' end,
        case when v_n = 0 then 'planner_loads_get() equals planner_loads ' || new.month
             else 'planner_loads ' || new.month || ' differs at: ' || v_note end, v_details);
    exception when others then
      perform private.job_run_add('adapter_check', w, t1, 'failed', 'planner_loads ' || new.month || ': the comparison stopped: ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_loads', 'month', new.month, 'sqlstate', sqlstate));
    end;
  exception when others then
    null;   -- nothing here may stop the write
  end;
  return null;
end
$function$

;

-- private.adapter_mirror_state()
CREATE OR REPLACE FUNCTION private.adapter_mirror_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; t0 timestamptz := clock_timestamp(); t1 timestamptz; v_doc jsonb; v_res jsonb; v_got jsonb;
  v_n int; v_note text; v_details jsonb; v_json text; v_saved bigint; v_ver text; v_dup text;
begin
  if new.id is distinct from 'main' then return null; end if;
  select p.json, p.saved_at, p.ctid::text into v_json, v_saved, v_ver from public.planner_state p where p.id = 'main';
  if not found or private.adapter_seen('planner_state ' || v_ver) then return null; end if;
  begin
    select x.id into w from public.worlds x where x.is_default;
    begin
      v_doc := v_json::jsonb;
      if jsonb_typeof(v_doc) is distinct from 'object' then raise exception 'planner_state.json isn''t a JSON object'; end if;
      v_res := private.planner_apply(w, v_doc, 'mirror', null, null, 'planner', 'mirror');
      perform private.job_run_add('adapter_mirror', w, t0, 'ok',
        case when (v_res ->> 'applied')::int = 0 then 'planner_state: nothing to copy'
             else 'planner_state: copied ' || (v_res ->> 'applied') || ' item(s)' end,
        jsonb_build_object('table', 'planner_state', 'items', (v_res ->> 'applied')::int, 'rows', v_res -> 'rows',
                           'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)));
    exception when others then
      v_res := null;
      perform private.job_run_add('adapter_mirror', w, t0, 'failed', 'planner_state: ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_state', 'sqlstate', sqlstate));
    end;
    t1 := clock_timestamp();
    begin
      v_got := coalesce(v_res -> 'doc', (public.planner_state_get(w) ->> 'json')::jsonb);
      with c as (select * from private.planner_state_check(w, v_doc, v_saved, v_got))
      select count(*) filter (where c.kind = 'differs'),
             (select string_agg(z.place || ' ×' || z.n, ', ' order by z.place)
                from (select private.planner_place(c2.path) as place, count(*) as n from c c2 where c2.kind = 'differs' group by 1) z),
             jsonb_build_object('table', 'planner_state', 'saved_at', v_saved,
               'paths', coalesce((select jsonb_agg(z.path order by z.path) from (select c2.path from c c2 where c2.kind = 'differs' order by c2.path limit 200) z), '[]'::jsonb),
               'cash', coalesce((select jsonb_agg(c2.why order by c2.path) from c c2 where c2.why is not null), '[]'::jsonb),
               'allowed', coalesce((select jsonb_object_agg(z.kind, z.n) from (select c2.kind, count(*) as n from c c2 where c2.kind <> 'differs' group by 1) z), '{}'::jsonb),
               'ms', round(extract(epoch from clock_timestamp() - t1) * 1000))
        into v_n, v_note, v_details
        from c;
      -- a code the planner lists twice is said first, plainly (the tables keep one)
      v_dup := private.planner_duplicates(v_doc);
      perform private.job_run_add('adapter_check', w, t1, case when v_n = 0 then 'ok' else 'failed' end,
        case when v_n = 0 then 'planner_state_get() equals planner_state'
             else coalesce(v_dup || '; ', '') || 'planner_state differs at: ' || v_note end,
        v_details || jsonb_strip_nulls(jsonb_build_object('duplicates', v_dup)));
    exception when others then
      perform private.job_run_add('adapter_check', w, t1, 'failed', 'planner_state: the comparison stopped: ' || sqlerrm,
                                  jsonb_build_object('table', 'planner_state', 'sqlstate', sqlstate));
    end;
  exception when others then
    null;   -- nothing here may stop the save
  end;
  return null;
end
$function$

;

-- private.adapter_seen(p_key text)
CREATE OR REPLACE FUNCTION private.adapter_seen(p_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_seen text := coalesce(current_setting('equinox.adapter_seen', true), '');
begin
  if position('|' || p_key || '|' in v_seen) > 0 then return true; end if;
  perform set_config('equinox.adapter_seen', v_seen || '|' || p_key || '|', true);
  return false;
end
$function$

;

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
  if private.planner_frozen_since('public.planner_loads'::regclass) is not null then
    return jsonb_build_object('days', 0);
  end if;
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
                                             or public.loads_day_captured(v_world, d.game_date),
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

-- private.archive_check_args(p_month date, p_table text)
CREATE OR REPLACE FUNCTION private.archive_check_args(p_month date, p_table text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if p_table is null or not exists (select 1 from private.archive_tables() t where t.table_name = p_table) then
    raise exception 'archive refused: % is not a table the archive may touch (design §7: %)', coalesce(p_table, 'null'),
      (select string_agg(t.table_name, ', ') from private.archive_tables() t) using errcode = '42501';
  end if;
  if p_month is null or p_month <> date_trunc('month', p_month)::date then
    raise exception 'archive refused: the month must be given as its first day (e.g. 2026-10-01), not %', coalesce(p_month::text, 'null')
      using errcode = '22023';
  end if;
end
$function$
;

-- private.archive_checksum(p_month date, p_table text, OUT rows bigint, OUT checksum text)
CREATE OR REPLACE FUNCTION private.archive_checksum(p_month date, p_table text, OUT rows bigint, OUT checksum text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO, YMD'
 SET "IntervalStyle" TO 'postgres'
 SET extra_float_digits TO '1'
 SET bytea_output TO 'hex'
AS $function$
begin
  perform private.archive_check_args(p_month, p_table);
  execute format('select count(*), md5(coalesce(string_agg(t::text, E''\n'' order by %s), '''')) from public.%I t where %s',
                 private.archive_order(p_table, 't'), p_table, private.archive_where(p_month, p_table, 't'))
     into rows, checksum;
end
$function$
;

-- private.archive_delete(p_month date, p_table text, p_expected_count bigint, p_checksum text)
CREATE OR REPLACE FUNCTION private.archive_delete(p_month date, p_table text, p_expected_count bigint, p_checksum text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO, YMD'
 SET "IntervalStyle" TO 'postgres'
 SET extra_float_digits TO '1'
 SET bytea_output TO 'hex'
AS $function$
declare
  t0 timestamptz := clock_timestamp(); v_kept date; c record; v_reasons text[] := '{}'; n bigint; v_deleted bigint;
  v_sum text; v_version text; v_job bigint; v_label text;
begin
  perform private.archive_check_args(p_month, p_table);
  v_label := p_table || ' ' || to_char(p_month, 'YYYY-MM');
  execute format('lock table public.%I in share row exclusive mode', p_table);
  v_kept := private.archive_kept_from(p_table, (now() at time zone 'UTC')::date);
  if p_month >= v_kept then
    v_reasons := v_reasons || format('%s is inside the kept window (%s keeps %s, from %s on)', to_char(p_month, 'YYYY-MM'),
      p_table, case when p_table = 'change_log' then 'the last 12 full months' else 'one full calendar month' end, to_char(v_kept, 'YYYY-MM'));
  end if;
  select * into c from private.archive_checksum(p_month, p_table);
  if p_expected_count is distinct from c.rows then
    v_reasons := v_reasons || format('the count doesn''t match (%s expected, %s there now)', coalesce(p_expected_count::text, 'none'), c.rows);
  end if;
  if p_checksum is distinct from c.checksum then
    v_reasons := v_reasons || 'the checksum doesn''t match (the rows changed since the manifest)'::text;
  end if;
  if p_table = 'game_flights' then
    -- every flight of the month is in route_days, as many per route and day as game_flights has (history_flows's rule)
    execute format($q$
      with f as (
        select x.airline_id, x.origin_code, x.dest_code, coalesce((x.dep_at at time zone 'UTC')::date, x.game_date) as day, count(*) as n
          from public.game_flights x
         where %s and (x.flight_no is not null or x.pax_income is not null)
           and coalesce(x.origin_code, '') <> '' and coalesce(x.dest_code, '') <> ''
         group by 1, 2, 3, 4)
      select count(*) from f
        left join public.route_days r on r.airline_id = f.airline_id and r.origin_code = f.origin_code
                                     and r.dest_code = f.dest_code and r.day = f.day
       where r.flights is distinct from f.n::int$q$, private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s route day(s) of the month aren''t in route_days as game_flights has them (run private.history_flows() for the month first)', n);
    end if;
    execute format('select count(*) from public.game_statement s join public.game_flights x on x.id = s.flight_id where %s',
                   private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s statement line(s) still point at these flights (the statement clean-up removes them after 14 days once it is switched on)', n);
    end if;
  end if;
  if cardinality(v_reasons) > 0 then
    raise exception 'archive_delete refused %: %', v_label, array_to_string(v_reasons, '; ') using errcode = 'P0001';
  end if;

  -- the delete, checking the rows it removes against the manifest's count and checksum
  execute format('with d as (delete from public.%I t where %s returning t.*) select count(*), md5(coalesce(string_agg(d::text, E''\n'' order by %s), '''')) from d',
                 p_table, private.archive_where(p_month, p_table, 't'), private.archive_order(p_table, 'd'))
     into v_deleted, v_sum;
  if v_deleted <> p_expected_count or v_sum <> p_checksum then
    raise exception 'archive_delete stopped %: the rows it was deleting weren''t the manifest''s (% rows); nothing was deleted', v_label, v_deleted;
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into v_version;
  end if;
  insert into public.job_runs (job, started_at, finished_at, status, for_month, note, details)
  values ('archive', t0, clock_timestamp(), 'ok', p_month,
          format('%s: %s row(s) archived and deleted', v_label, v_deleted),
          jsonb_build_object('table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'rows', v_deleted, 'checksum', v_sum,
                             'migration_version', v_version))
  returning id into v_job;
  return jsonb_build_object('table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'deleted', v_deleted, 'job_run_id', v_job);
end
$function$
;

-- private.archive_due(p_as_of date)
CREATE OR REPLACE FUNCTION private.archive_due(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(table_name text, month date, rows bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
  with k as (
    select t.table_name, private.archive_kept_from(t.table_name, coalesce(p_as_of, (now() at time zone 'UTC')::date)) as kept_from
      from private.archive_tables() t)
  select x.table_name, x.month, x.rows from (
    select 'game_flights' as table_name, date_trunc('month', coalesce(f.dep_at at time zone 'UTC', f.game_date::timestamp))::date as month, count(*) as rows
      from public.game_flights f, k
     where k.table_name = 'game_flights' and coalesce(f.dep_at at time zone 'UTC', f.game_date::timestamp) < k.kept_from::timestamp
     group by 2
    union all
    select 'game_events', date_trunc('month', e.event_date)::date, count(*)
      from public.game_events e, k
     where k.table_name = 'game_events' and e.event_date < k.kept_from
     group by 2
    union all
    select 'game_scan_schedules', date_trunc('month', s.taken_at at time zone 'UTC')::date, count(*)
      from public.game_scan_schedules x join public.game_scans s on s.id = x.scan_id, k
     where k.table_name = 'game_scan_schedules' and s.taken_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'game_scan_airports', date_trunc('month', s.taken_at at time zone 'UTC')::date, count(*)
      from public.game_scan_airports x join public.game_scans s on s.id = x.scan_id, k
     where k.table_name = 'game_scan_airports' and s.taken_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'change_log', date_trunc('month', c.changed_at at time zone 'UTC')::date, count(*)
      from public.change_log c, k
     where k.table_name = 'change_log' and c.changed_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2) x
   order by x.month, x.table_name
$function$
;

-- private.archive_kept_from(p_table text, p_as_of date)
CREATE OR REPLACE FUNCTION private.archive_kept_from(p_table text, p_as_of date)
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select (date_trunc('month', p_as_of) - make_interval(months => t.keep_months))::date
    from private.archive_tables() t where t.table_name = p_table
$function$
;

-- private.archive_manifest(p_month date, p_table text)
CREATE OR REPLACE FUNCTION private.archive_manifest(p_month date, p_table text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO, YMD'
 SET "IntervalStyle" TO 'postgres'
 SET extra_float_digits TO '1'
 SET bytea_output TO 'hex'
AS $function$
declare c record; v_version text; v_kept date := private.archive_kept_from(p_table, (now() at time zone 'UTC')::date);
begin
  perform private.archive_check_args(p_month, p_table);
  select * into c from private.archive_checksum(p_month, p_table);
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into v_version;
  end if;
  return jsonb_build_object(
    'table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'rows', c.rows, 'checksum', c.checksum,
    'checksum_method', 'md5 of every row as Postgres prints it (timezone UTC, datestyle ISO), joined by newlines, in primary-key order',
    'primary_key_order', private.archive_order(p_table, 't'),
    'month_of', (select t.month_of from private.archive_tables() t where t.table_name = p_table),
    'kept_from', to_char(v_kept, 'YYYY-MM'), 'due', p_month < v_kept,
    'layout', (select jsonb_agg(jsonb_build_object('column', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
                                                   'not_null', a.attnotnull, 'generated', a.attgenerated <> '',
                                                   'identity', a.attidentity <> '') order by a.attnum)
                 from pg_catalog.pg_attribute a
                where a.attrelid = ('public.' || p_table)::regclass and a.attnum > 0 and not a.attisdropped),
    'migration_version', v_version,
    'query', private.archive_select(p_month, p_table),
    'made_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
end
$function$
;

-- private.archive_order(p_table text, p_as text)
CREATE OR REPLACE FUNCTION private.archive_order(p_table text, p_as text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare a text := quote_ident(p_as);
begin
  return case p_table
    when 'game_flights' then format('%1$s.id', a)
    when 'game_events' then format('%1$s.airline collate "C", %1$s.event_date, %1$s.event_time collate "C", %1$s.descr collate "C"', a)
    when 'game_scan_schedules' then format('%1$s.scan_id, %1$s.airline_id', a)
    when 'game_scan_airports' then format('%1$s.scan_id, %1$s.airport_code collate "C"', a)
    when 'change_log' then format('%1$s.id', a)
  end;
end
$function$
;

-- private.archive_select(p_month date, p_table text)
CREATE OR REPLACE FUNCTION private.archive_select(p_month date, p_table text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  perform private.archive_check_args(p_month, p_table);
  return format('select t.* from public.%I t where %s order by %s', p_table, private.archive_where(p_month, p_table, 't'),
                private.archive_order(p_table, 't'));
end
$function$
;

-- private.archive_tables()
CREATE OR REPLACE FUNCTION private.archive_tables()
 RETURNS TABLE(table_name text, month_of text, keep_months integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select * from (values ('game_flights', 'dep_at (UTC); the game''s date where dep_at isn''t known', 1),
                        ('game_events', 'event_date', 1),
                        ('game_scan_schedules', 'the scan''s time (game_scans.taken_at, UTC)', 1),
                        ('game_scan_airports', 'the scan''s time (game_scans.taken_at, UTC)', 1),
                        ('change_log', 'changed_at (UTC)', 12)) v(table_name, month_of, keep_months)
$function$
;

-- private.archive_where(p_month date, p_table text, p_as text)
CREATE OR REPLACE FUNCTION private.archive_where(p_month date, p_table text, p_as text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  f text := quote_literal(to_char(p_month, 'YYYY-MM-DD') || ' 00:00:00+00') || '::timestamptz';
  t text := quote_literal(to_char((p_month + interval '1 month')::date, 'YYYY-MM-DD') || ' 00:00:00+00') || '::timestamptz';
  fd text := quote_literal(to_char(p_month, 'YYYY-MM-DD')) || '::date';
  td text := quote_literal(to_char((p_month + interval '1 month')::date, 'YYYY-MM-DD')) || '::date';
  a text := quote_ident(p_as);
begin
  perform private.archive_check_args(p_month, p_table);
  return case p_table
    when 'game_flights' then format('((%1$s.dep_at >= %2$s and %1$s.dep_at < %3$s) or (%1$s.dep_at is null and %1$s.game_date >= %4$s and %1$s.game_date < %5$s))', a, f, t, fd, td)
    when 'game_events' then format('(%1$s.event_date >= %2$s and %1$s.event_date < %3$s)', a, fd, td)
    when 'game_scan_schedules' then format('exists (select 1 from public.game_scans s where s.id = %1$s.scan_id and s.taken_at >= %2$s and s.taken_at < %3$s)', a, f, t)
    when 'game_scan_airports' then format('exists (select 1 from public.game_scans s where s.id = %1$s.scan_id and s.taken_at >= %2$s and s.taken_at < %3$s)', a, f, t)
    when 'change_log' then format('(%1$s.changed_at >= %2$s and %1$s.changed_at < %3$s)', a, f, t)
  end;
end
$function$
;

-- private.backup_runs_insert()
CREATE OR REPLACE FUNCTION private.backup_runs_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_at timestamptz := coalesce(new.ran_at, now()); v_id bigint;
begin
  if new.kind is null or new.kind not in ('nightly', 'manual', 'test') then
    raise exception 'backup_runs: kind must be nightly, manual or test, not %', coalesce(new.kind, 'null') using errcode = '23514';
  end if;
  if new.ok is null then
    raise exception 'backup_runs: ok is required' using errcode = '23502';
  end if;
  insert into public.job_runs (job, started_at, finished_at, status, note, details)
  values ('backup', v_at, v_at, case when new.ok then 'ok' else 'failed' end, new.note,
          jsonb_strip_nulls(jsonb_build_object('kind', new.kind, 'tables', new.tables, 'rows', new.rows, 'files', new.files,
                                               'bytes', new.bytes, 'commit_sha', new.commit_sha, 'object_key', new.object_key)))
  returning id into v_id;
  new.id := v_id;
  new.ran_at := v_at;
  return new;
end
$function$
;

-- private.caller_is_staff()
CREATE OR REPLACE FUNCTION private.caller_is_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select public.is_planner_user()
      or (session_user = 'postgres' and coalesce(nullif(current_setting('role', true), 'none'), session_user) = 'postgres')
$function$

;

-- private.capex_key(p_airline text, p_day date, p_kind text, p_amount numeric, p_note text)
CREATE OR REPLACE FUNCTION private.capex_key(p_airline text, p_day date, p_kind text, p_amount numeric, p_note text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_array(p_airline, p_day, p_kind, round(p_amount, 2), p_note)::text
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
      -- the figures and their time from the same capture: the latest
      insert into public.game_pnl as x (world_id, airline_id, airline, captured_on, capture_day, line, current_p, last_p, total_p, captured_at)
      values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1], public.as_num(c[2]), public.as_num(c[3]),
              public.as_num(c[array_length(c, 1)]), v_at)
      on conflict (airline, captured_on, line) do update set current_p = excluded.current_p, last_p = excluded.last_p,
        total_p = excluded.total_p, capture_day = excluded.capture_day, captured_at = excluded.captured_at
      where excluded.captured_at >= x.captured_at;
      n := n + 1;
    end loop;

  elsif r.kind = 'balance' then
    v_day := private.capture_day(r.world_id, v_at);
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      -- the figures and their time from the same capture: the latest
      if array_length(c, 1) >= 3 and c[1] ~ '^\d{3,4}$' then
        insert into public.game_balance as x (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[1] || ' ' || c[2], public.as_num(c[3]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day,
          captured_at = excluded.captured_at
        where excluded.captured_at >= x.captured_at;
        n := n + 1;
      end if;
      if array_length(c, 1) >= 6 and c[4] ~ '^\d{3,4}$' then
        insert into public.game_balance as x (world_id, airline_id, airline, captured_on, capture_day, account, amount, captured_at)
        values (r.world_id, r.airline_id, r.airline, v_today, v_day, c[4] || ' ' || c[5], public.as_num(c[6]), v_at)
        on conflict (airline, captured_on, account) do update set amount = excluded.amount, capture_day = excluded.capture_day,
          captured_at = excluded.captured_at
        where excluded.captured_at >= x.captured_at;
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
declare v_al bigint; v_name text; v_rid bigint; v_res jsonb; v_day date; v_complete boolean; v_snap jsonb;
  t0 timestamptz;
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
  v_complete := private.capture_day_complete(p_world_id, v_day);
  -- the daily snapshot, when this page completes the day's capture (design §7)
  if v_complete and p_kind in ('statement', 'events', 'pnl', 'balance', 'loads') and private.snapshot_due(p_world_id, v_day, p_at) then
    t0 := clock_timestamp();
    begin
      v_snap := private.take_snapshot(p_world_id, v_day, p_at, 'capture');
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'ok', v_day,
              format('capture complete: %s airline(s), %s route day(s)', v_snap ->> 'airlines', v_snap ->> 'route_days'), v_snap);
    exception when others then
      v_snap := jsonb_build_object('ok', false, 'error', sqlerrm);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'failed', v_day, 'snapshot: ' || sqlerrm,
              jsonb_build_object('at', p_at, 'source', 'capture'));
    end;
  end if;
  return v_res || jsonb_build_object('capture_day', v_day, 'day_complete', v_complete)
         || case when v_snap is null then '{}'::jsonb else jsonb_build_object('snapshot', v_snap) end;
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

-- private.fig_airline_cards(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_airline_cards(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_today date := (p_as_of at time zone 'UTC')::date; v_from date; v_ops jsonb;
        v_leases jsonb := private.fig_lease_map(p_world_id, p_as_of);
begin
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
$function$

;

-- private.fig_airline_world(p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.fig_airline_world(p_airline_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare w bigint;
begin
  select a.world_id into w from public.airlines a where a.id = p_airline_id;
  if w is null then raise exception 'no such airline: %', coalesce(p_airline_id::text, 'none given') using errcode = '22023'; end if;
  return w;
end
$function$

;

-- private.fig_airlines(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.fig_airlines(p_world_id bigint)
 RETURNS TABLE(airline_id bigint, ord integer, iata_code text, name text, home_code text, main_code text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select a.id, (row_number() over (order by a.position nulls last, a.id))::int, a.iata_code,
         coalesce(a.public_name, a.planner_name, a.game_name), private.fig_home(a.id),
         (select b.airport_code from public.airline_bases b where b.airline_id = a.id and b.is_main order by b.id limit 1)
    from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = p_world_id and g.kind = 'ours' and a.active
$function$

;

-- private.fig_capex(p_airline_id bigint, p_d0 date, p_d1 date)
CREATE OR REPLACE FUNCTION private.fig_capex(p_airline_id bigint, p_d0 date, p_d1 date)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(sum(s.amount), 0) / 1000000 from public.spending_log s
   where s.airline_id = p_airline_id and s.kind <> 'loss' and s.spent_on > p_d0 and s.spent_on <= p_d1
$function$

;

-- private.fig_capture_status(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_capture_status(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with d as (select (p_as_of at time zone 'UTC')::date as d0),
  al as (select * from private.fig_airlines(p_world_id) where home_code is not null),
  k as (select * from unnest(array['loads', 'statement', 'events', 'pnl', 'balance']) with ordinality as k(kind, o)),
  runs as (select r.airline_id, r.kind, (r.captured_at at time zone 'UTC')::date as day, max(r.captured_at) as at
             from public.game_capture_raw r, d
            where r.world_id = p_world_id and r.captured_at <= p_as_of
              and r.captured_at >= ((d.d0 - 1)::timestamp at time zone 'UTC')
            group by 1, 2, 3),
  fl as (select f.airline_id, f.game_date, count(distinct f.flight_no)::int as n
           from public.game_flights f, d
          where f.world_id = p_world_id and f.flight_no is not null and f.game_date in (d.d0, d.d0 - 1) and f.loads_captured_at <= p_as_of
          group by 1, 2),
  rows_ as (
    select al.airline_id, al.ord, al.iata_code, al.name,
           (select jsonb_object_agg(k.kind, jsonb_build_object('today', private.fig_ts(t.at), 'yesterday', private.fig_ts(y.at)) order by k.o)
              from k left join runs t on t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0
                     left join runs y on y.airline_id = al.airline_id and y.kind = k.kind and y.day = d.d0 - 1) as pages,
           (select coalesce(jsonb_agg(k.kind order by k.o), '[]'::jsonb) from k
             where not exists (select 1 from runs t where t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0)) as missing,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0) as flights_today,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0 - 1) as flights_yesterday
      from al, d)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'today', (select d0 from d), 'yesterday', (select d0 - 1 from d),
    'airlines', coalesce(jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'code', r.iata_code, 'name', r.name, 'pages', r.pages,
        'flights_today', r.flights_today, 'flights_yesterday', r.flights_yesterday, 'missing', r.missing,
        'status', case when jsonb_array_length(r.missing) = 0 then 'complete' when jsonb_array_length(r.missing) = 5 then 'not captured' else 'missing' end)
        order by r.ord), '[]'::jsonb))
    from rows_ r
$function$

;

-- private.fig_cash_days(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_cash_days(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS TABLE(day date, cash numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with t as (select (p_as_of at time zone 'UTC')::date as today),
  cap as (select distinct on (b.captured_on) b.captured_on as day, b.amount
            from public.game_balance b
           where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_at <= p_as_of
             and b.captured_on <= (select today from t) and b.amount is not null
           order by b.captured_on, b.captured_at desc),
  typed as (select e.day, e.cash from public.cash_entries e
             where e.airline_id = p_airline_id and e.day <= (select today from t) and e.cash is not null)
  select coalesce(c.day, e.day),
         case when c.day is not null and c.day >= (select today from t) - 7 then floor(c.amount / 10000 + 0.5) / 100
              when e.day is not null then e.cash / 1000000
              else floor(c.amount / 10000 + 0.5) / 100 end
    from cap c full join typed e on e.day = c.day
$function$

;

-- private.fig_cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone, p_lease_map jsonb)
CREATE OR REPLACE FUNCTION private.fig_cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamp with time zone, p_lease_map jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_home text; v_amount numeric; v_t0 timestamptz; v_cash0 numeric;
  v_flights bigint; v_income numeric; v_costs numeric; v_per_flight numeric; v_fpd numeric; v_ops_day numeric;
  v_cushion numeric; v_pct numeric; v_lease_map jsonb;
  v_pat timestamptz[]; v_pam numeric[]; v_pwhat text[]; v_prep boolean[];
  v_t timestamptz[]; v_v numeric[]; v_li int; v_cause jsonb;
  v_types jsonb; v_p numeric; v_l numeric;
  v_o jsonb; v_oty record; v_n int; v_sum_p numeric := 0; v_sum_l numeric := 0; v_olist jsonb := '[]'::jsonb; v_orders jsonb;
  v_low_after record; v_next jsonb; v_now jsonb;
  v_doc jsonb;
begin
  v_home := private.fig_home(p_airline_id);
  v_doc := jsonb_build_object('airline_id', p_airline_id, 'home_airport', v_home, 'as_of', private.fig_ts(p_as_of));
  -- cashForecast(): the airline's latest balance captured in the last 7 days (CAP.bal)
  select b.amount, b.captured_at into v_amount, v_t0
    from public.game_balance b
   where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_at <= p_as_of
   order by b.captured_at desc limit 1;
  if v_t0 is null or v_home is null then
    return v_doc || jsonb_build_object('status', 'no capture', 'missing', 'a capture: balance sheet, events and bank statement');
  end if;
  v_cash0 := coalesce(v_amount, 0) / 1000000;
  v_doc := v_doc || jsonb_build_object('cash', v_cash0, 'cash_at', private.fig_ts(v_t0));
  -- flight profit from the last 24 hours of the bank statement (game_ops_recent); fewer than 5 flights isn't enough
  select o.flights, o.income, o.costs into v_flights, v_income, v_costs from private.fig_ops_recent(p_airline_id, p_as_of) o;
  if v_flights is null or v_flights < 5 then
    return v_doc || jsonb_build_object('status', 'missing', 'missing', 'a bank statement capture');
  end if;
  v_per_flight := (v_income - v_costs) / v_flights / 1000000;
  -- flightsPerDay(): the planned flights a day
  select coalesce(sum(f.flights_week::numeric / 7), 0) into v_fpd from private.fig_freqs(w, p_airline_id) f where f.live and f.airline_id = p_airline_id;
  v_ops_day := v_per_flight * v_fpd;
  v_cushion := private.fig_num(w, p_airline_id, 'order_cushion') / 1000000;
  v_pct := private.fig_num(w, p_airline_id, 'lease_estimate_pct') / 100;

  -- every scheduled payment after the capture, and each one in its first week again a week later where the game
  -- doesn't list that far yet; up to 14 days after the capture
  with ev as (select e.at, e.amount, e.descr, e.event_date, e.event_time from private.fig_events(w, p_as_of, p_airline_id) e
               where e.airline_id = p_airline_id and e.at > v_t0),
  hz as (select coalesce(max(ev.at), v_t0) as h from ev),
  allp as (select ev.at, ev.amount, ev.descr, false as rep, ev.event_date, ev.event_time from ev
           union all
           select ev.at + interval '168 hours', ev.amount, ev.descr, true, ev.event_date, ev.event_time from ev, hz
            where ev.at <= v_t0 + interval '168 hours' and ev.at + interval '168 hours' > hz.h)
  select coalesce(array_agg(a.at order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.amount order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.descr order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.rep order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}')
    into v_pat, v_pam, v_pwhat, v_prep
    from allp a where a.at <= v_t0 + interval '336 hours';

  -- the balance at each payment and at the capture's moment on each of the 14 days after it
  select array_agg(y.t order by y.t), array_agg(y.v order by y.t) into v_t, v_v
    from (select x.t, v_cash0 + v_ops_day * (extract(epoch from (x.t - v_t0)) / 86400)
                      - coalesce((select sum(p.a) from unnest(v_pat, v_pam) as p(at, a) where p.at <= x.t), 0) as v
            from (select unnest(v_pat) as t union select v_t0 + i * interval '24 hours' from generate_series(0, 14) i) x) y;
  -- the lowest point (the first, if two are equal), and the payment that makes it: the largest at that moment, else the
  -- largest in the day before it
  select u.i into v_li from unnest(v_v) with ordinality as u(v, i) order by u.v, u.i limit 1;
  select jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) into v_cause
    from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)
   where p.at = v_t[v_li] order by p.amount desc, p.i limit 1;
  if v_cause is null then
    select jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) into v_cause
      from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)
     where p.at <= v_t[v_li] and p.at > v_t[v_li] - interval '24 hours' order by p.amount desc, p.i limit 1;
  end if;

  -- leaseM(): each type's weekly lease, the highest leasing payment seen for it in the events (any airline), else
  -- lease_estimate_pct of its price
  v_lease_map := coalesce(p_lease_map, private.fig_lease_map(w, p_as_of));

  -- each type the airline may buy (airline_aircraft_types): the first day in the next 14 it can be ordered and keep the
  -- cushion (fits() at the capture's moment on each day), with its price (cabin included) and its own lease; how many at
  -- once if today, up to 9 (the most n for which every point from then on keeps the cushion after n orders)
  with ty as (
    select t.id, t.name, t.price / 1000000 as price, cc.code as cabin, coalesce(cc.cost, 0) / 1000000 as cabin_cost,
           (v_lease_map ->> private.fig_type_key(t.name))::numeric as seen_lease
      from public.airline_aircraft_types aat
      join public.aircraft_types t on t.id = aat.aircraft_type_id
      left join public.cabin_configs cc on cc.id = private.fig_order_cabin(p_airline_id, t.id)
     where aat.airline_id = p_airline_id and coalesce(t.price, 0) <> 0),
  tp as (select ty.*, ty.price + ty.cabin_cost as p, coalesce(ty.seen_lease, ty.price * v_pct) as l from ty),
  -- for an order placed on day d, each point from then on and how many of its own lease payments have fallen by then
  -- (worked out once for all types)
  pw as materialized (
    select d.d, x.t, x.v, private.fig_lease_weeks(x.t, v_t0 + d.d * interval '24 hours') as wk
      from generate_series(0, 14) as d(d)
      join unnest(v_t, v_v) as x(t, v) on x.t >= v_t0 + d.d * interval '24 hours'),
  ok as (select tp.id, pw.d, bool_and(pw.v - (tp.p + tp.l * pw.wk) >= v_cushion) as fits
           from tp cross join pw
          group by tp.id, pw.d),
  first_day as (select ok.id, min(ok.d) filter (where ok.fits) as d from ok group by ok.id),
  most as (select tp.id, least(9, floor(min((pw.v - v_cushion) / (tp.p + tp.l * pw.wk))))::int as n
             from tp join pw on pw.d = 0 group by tp.id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'aircraft_type_id', tp.id, 'type', tp.name, 'price', tp.price, 'cabin', tp.cabin, 'cabin_cost', tp.cabin_cost,
           'price_with_cabin', tp.p, 'lease_week', tp.l, 'lease_seen', tp.seen_lease is not null,
           'safe_day', f.d, 'safe_from', private.fig_ts(v_t0 + f.d * interval '24 hours'),
           'count_today', case when f.d = 0 then m.n end) order by tp.id), '[]'::jsonb)
    into v_types
    from tp join first_day f on f.id = tp.id join most m on m.id = tp.id;

  -- orderNow() and fcNext(): what can be ordered today (dearest first), else the first safe day
  select coalesce(jsonb_agg(x ->> 'type' order by (x ->> 'price_with_cabin')::numeric desc, (x ->> 'aircraft_type_id')::bigint), '[]'::jsonb)
    into v_now from jsonb_array_elements(v_types) x where (x ->> 'safe_day')::int = 0;
  if jsonb_array_length(v_now) > 0 then
    v_next := jsonb_build_object('when', 'now', 'types', v_now);
  else
    select jsonb_build_object('when', 'later', 'type', x ->> 'type', 'aircraft_type_id', (x ->> 'aircraft_type_id')::bigint,
                              'safe_day', (x ->> 'safe_day')::int, 'safe_from', x ->> 'safe_from')
      into v_next
      from jsonb_array_elements(v_types) x where x ->> 'safe_day' is not null
     order by (x ->> 'safe_day')::int, (x ->> 'price_with_cabin')::numeric desc, (x ->> 'aircraft_type_id')::bigint limit 1;
    v_next := coalesce(v_next, jsonb_build_object('when', 'not within 14 days'));
  end if;

  -- p_orders: several orders tested together, all placed now, each with its own lease (manual §3)
  if p_orders is not null and jsonb_typeof(p_orders) <> 'array' then
    raise exception 'p_orders must be a list: [{"type": "<aircraft type>", "count": 1}, ...]' using errcode = '22023';
  end if;
  if p_orders is not null and jsonb_array_length(p_orders) > 0 then
    for v_o in select * from jsonb_array_elements(p_orders) loop
      if jsonb_typeof(v_o) <> 'object' then raise exception 'p_orders: each order is an object, e.g. {"type": "A321 NEO LIGHT", "count": 1}' using errcode = '22023'; end if;
      select t.id, t.name, coalesce(t.price, 0) / 1000000 as price, cc.code as cabin, coalesce(cc.cost, 0) / 1000000 as cabin_cost,
             (v_lease_map ->> private.fig_type_key(t.name))::numeric as seen_lease,
             exists (select 1 from public.airline_aircraft_types aat where aat.airline_id = p_airline_id and aat.aircraft_type_id = t.id) as may_buy
        into v_oty
        from public.aircraft_types t
        left join public.cabin_configs cc on cc.id = private.fig_order_cabin(p_airline_id, t.id)
       where t.world_id = w and (t.id = (v_o ->> 'aircraft_type_id')::bigint or (v_o ? 'type' and t.name = v_o ->> 'type'))
       order by t.id limit 1;
      if v_oty.id is null then raise exception 'p_orders: no such aircraft type: %', coalesce(v_o ->> 'type', v_o ->> 'aircraft_type_id') using errcode = '22023'; end if;
      v_n := coalesce((v_o ->> 'count')::int, 1);
      if v_n < 1 then raise exception 'p_orders: the count must be 1 or more' using errcode = '22023'; end if;
      v_p := v_oty.price + v_oty.cabin_cost;
      v_l := coalesce(v_oty.seen_lease, v_oty.price * v_pct);
      v_sum_p := v_sum_p + v_n * v_p; v_sum_l := v_sum_l + v_n * v_l;
      v_olist := v_olist || jsonb_build_object('aircraft_type_id', v_oty.id, 'type', v_oty.name, 'count', v_n, 'may_buy', v_oty.may_buy,
                                               'price_with_cabin', v_p, 'lease_week', v_l, 'lease_seen', v_oty.seen_lease is not null);
    end loop;
    select x.t, x.v - (v_sum_p + v_sum_l * private.fig_lease_weeks(x.t, v_t0)) as v
      into v_low_after
      from unnest(v_t, v_v) with ordinality as x(t, v, i)
     order by 2, x.i limit 1;
    v_orders := jsonb_build_object('orders', v_olist,
                                   'safe', private.fig_fits(v_t, v_v, v_t0, 1, v_sum_p, v_sum_l, v_cushion),
                                   'lowest', jsonb_build_object('at', private.fig_ts(v_low_after.t), 'balance', v_low_after.v),
                                   -- the forecast after the orders: each point less their prices and the leases fallen by then
                                   'points', (select jsonb_agg(jsonb_build_object('at', private.fig_ts(x.t),
                                                'balance', x.v - (v_sum_p + v_sum_l * private.fig_lease_weeks(x.t, v_t0))) order by x.i)
                                                from unnest(v_t, v_v) with ordinality as x(t, v, i)));
  end if;

  return v_doc || jsonb_build_object(
    'status', 'ok',
    'profit_per_flight', v_per_flight, 'flights_per_day', v_fpd, 'flight_profit_day', v_ops_day,
    'cushion', v_cushion,
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) order by p.i), '[]'::jsonb)
                   from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)),
    'payments_next_7_days', (select coalesce(sum(p.a), 0) from unnest(v_pat, v_pam) as p(at, a) where p.at <= v_t0 + interval '168 hours'),
    'points', (select jsonb_agg(jsonb_build_object('at', private.fig_ts(x.t), 'balance', x.v) order by x.i)
                 from unnest(v_t, v_v) with ordinality as x(t, v, i)),
    'lowest', jsonb_build_object('at', private.fig_ts(v_t[v_li]), 'balance', v_v[v_li], 'payment', v_cause),
    'types', v_types,
    'can_order_now', v_now,
    'next_order', v_next)
    || case when v_orders is null then '{}'::jsonb else jsonb_build_object('orders_tested', v_orders) end;
end
$function$

;

-- private.fig_day_captured(p_world_id bigint, p_day date, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_day_captured(p_world_id bigint, p_day date, p_as_of timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  s as (select private.capture_day_start(p_world_id, p_day) as v_from)
  select exists (select 1 from ours)
     and not exists (
       select 1 from ours a, s
        where not exists (select 1 from public.game_flights f
                           where f.airline_id = a.id and f.game_date = p_day and f.flight_no is not null
                             and f.loads_captured_at >= s.v_from and f.loads_captured_at <= p_as_of)
          and not exists (select 1 from public.game_capture_raw r
                           where r.airline_id = a.id and r.kind = 'loads' and r.captured_at <= p_as_of
                             and r.captured_at >= s.v_from and r.captured_at < s.v_from + interval '1 day'))
$function$

;

-- private.fig_day_ops(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)
CREATE OR REPLACE FUNCTION private.fig_day_ops(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)
 RETURNS TABLE(day date, airline_id bigint, flights integer, aircraft integer, load numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with fl as (select x.* from private.fig_flights_on(p_world_id, p_from, p_to) x where x.launched_on is null or x.launched_on <= x.day),
  ld as (select * from private.fig_load_days(p_world_id, p_as_of, p_from, p_to)),
  lv as (select * from private.fig_load_values(p_world_id, p_as_of, p_from, p_to) x where x.v is not null),
  j as (select fl.day, fl.airline_id, fl.tail, lv.v, coalesce(ld.done, false) as done, coalesce(ld.captured, false) as captured,
               ld.day is not null as has_day
          from fl
          left join ld on ld.day = fl.day
          left join lv on lv.day = fl.day and lv.airline_id = fl.airline_id and lv.flight_no = fl.flight_no)
  select j.day, j.airline_id, count(*)::int, count(distinct j.tail)::int,
         case when bool_and(j.has_day) and bool_and(j.done)
              then avg(case when coalesce(j.v, 0) = 0 then 97.5 else j.v end) filter (where not j.captured or j.v is not null) end
    from j group by j.day, j.airline_id
$function$

;

-- private.fig_eq_off(p_code text)
CREATE OR REPLACE FUNCTION private.fig_eq_off(p_code text)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((select round(a.utc_offset * 60)::int from public.airports a where a.code = p_code), 0)
$function$

;

-- private.fig_events(p_world_id bigint, p_as_of timestamp with time zone, p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.fig_events(p_world_id bigint, p_as_of timestamp with time zone, p_airline_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(airline_id bigint, at timestamp with time zone, amount numeric, descr text, event_date date, event_time text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with t as (select (p_as_of at time zone 'UTC')::date as today),
  f as (select coalesce(min(b.captured_on), (select today from t) - 7) as first_day
          from public.game_balance b
         where b.world_id = p_world_id and b.account like '2800%' and b.captured_at <= p_as_of
           and b.captured_on >= (select today from t) - 7)
  select e.airline_id, private.local_to_utc(e.event_date, e.event_time, private.fig_eq_off(h.code)), e.debit / 1000000,
         e.descr, e.event_date, e.event_time
    from public.game_events e
    cross join f
    join public.airlines a on a.id = e.airline_id
    left join public.airline_bases mb on mb.airline_id = e.airline_id and mb.is_main
    cross join lateral (select coalesce(mb.airport_code, a.home_airport_code) as code) h   -- fig_home()
   where e.world_id = p_world_id and (p_airline_id is null or e.airline_id = p_airline_id) and e.debit > 0 and e.captured_at <= p_as_of
     and e.event_date >= f.first_day and e.event_date <= (select today from t) + 16
$function$

;

-- private.fig_export(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_export(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  return jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of),
    'airline_cards', private.fig_airline_cards(p_world_id, p_as_of),
    'growth_signals', private.fig_growth_signals(p_world_id, p_as_of),
    'hub_progress', private.fig_hub_progress(p_world_id, p_as_of),
    'capture_status', private.fig_capture_status(p_world_id, p_as_of),
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
        'airline_id', al.airline_id, 'code', al.iata_code, 'name', al.name,
        'cash_forecast', private.fig_cash_forecast(al.airline_id, '[]'::jsonb, p_as_of),
        'airline_profit', private.fig_fin_stats(al.airline_id, p_as_of) -> 'days',
        'route_profit', jsonb_build_object('1', r1.d - 'aircraft' - 'fare_changes', '3', r3.d - 'aircraft' - 'fare_changes',
                                           '7', r7.d - 'aircraft' - 'fare_changes'),
        'aircraft_profit', jsonb_build_object('1', r1.d -> 'aircraft', '3', r3.d -> 'aircraft', '7', r7.d -> 'aircraft'),
        'fare_changes', r7.d -> 'fare_changes') order by al.ord), '[]'::jsonb)
        from private.fig_airlines(p_world_id) al
        -- offset 0 keeps each document worked out once (folded into the outer query, each use would work it out again)
        cross join lateral (select private.fig_route_profit(al.airline_id, 1, p_as_of) as d offset 0) r1
        cross join lateral (select private.fig_route_profit(al.airline_id, 3, p_as_of) as d offset 0) r3
        cross join lateral (select private.fig_route_profit(al.airline_id, 7, p_as_of) as d offset 0) r7));
end
$function$

;

-- private.fig_fin_stats(p_airline_id bigint, p_as_of timestamp with time zone, p_ops jsonb)
CREATE OR REPLACE FUNCTION private.fig_fin_stats(p_airline_id bigint, p_as_of timestamp with time zone, p_ops jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_s jsonb; v_ops jsonb; v_iv jsonb; v_from date;
  v_last_d date; v_last_c numeric; v_first_d date; v_first_c numeric; v_span int; v_profit numeric;
  v_avg_tails numeric; v_per_ac numeric; v_flying int; v_fly_val numeric; v_avg_price numeric;
  v_now_f int; v_then_f int; v_then_t int; v_load7 numeric; v_on_order int;
begin
  select coalesce(jsonb_agg(jsonb_build_object('d', c.day, 'c', c.cash) order by c.day), '[]'::jsonb) into v_s
    from private.fig_cash_days(p_airline_id, p_as_of) c;
  if p_ops is not null then
    v_ops := coalesce(p_ops -> p_airline_id::text, '{}'::jsonb);
  else
    v_from := least(coalesce((v_s -> 0 ->> 'd')::date, v_today), v_today - 7);
    select coalesce(jsonb_object_agg(o.day::text, jsonb_build_object('flights', o.flights, 'aircraft', o.aircraft, 'load', o.load)), '{}'::jsonb)
      into v_ops from private.fig_day_ops(w, p_as_of, v_from, v_today) o where o.airline_id = p_airline_id;
  end if;
  -- each interval between two reported days: change in cash plus that period's order payments, per day
  with s as (select (x ->> 'd')::date as d, (x ->> 'c')::numeric as c, i from jsonb_array_elements(v_s) with ordinality as e(x, i))
  select coalesce(jsonb_agg(jsonb_build_object(
           'date', p.d, 'cash', p.c, 'change', p.c - q.c, 'order_payments', cap.v, 'days', greatest(1, p.d - q.d),
           'profit_day', (p.c - q.c + cap.v) / greatest(1, p.d - q.d),
           'aircraft', coalesce((v_ops -> p.d::text ->> 'aircraft')::int, 0),
           'flights', coalesce((v_ops -> p.d::text ->> 'flights')::int, 0),
           'load', (v_ops -> p.d::text ->> 'load')::numeric) order by p.i), '[]'::jsonb)
    into v_iv
    from s p join s q on q.i = p.i - 1
    cross join lateral (select private.fig_capex(p_airline_id, q.d, p.d) as v offset 0) cap;
  -- profit over the last 7 days (an early read over fewer), and per aircraft flying in that time
  if jsonb_array_length(v_s) > 0 then
    v_last_d := (v_s -> -1 ->> 'd')::date; v_last_c := (v_s -> -1 ->> 'c')::numeric;
    select (x ->> 'd')::date, (x ->> 'c')::numeric into v_first_d, v_first_c
      from jsonb_array_elements(v_s) with ordinality as e(x, i) where v_last_d - (x ->> 'd')::date <= 7 order by i limit 1;
    v_span := v_last_d - v_first_d;
    v_profit := case when v_span <> 0 then (v_last_c - v_first_c + private.fig_capex(p_airline_id, v_first_d, v_last_d)) / v_span end;
    select avg((x ->> 'aircraft')::numeric) into v_avg_tails from jsonb_array_elements(v_iv) x where (x ->> 'date')::date > v_first_d;
    v_per_ac := case when v_profit is not null and coalesce(v_avg_tails, 0) <> 0 then v_profit / v_avg_tails end;
  end if;
  -- the fleet (the old planner's tails: aircraft in service) and its value at today's prices
  select count(*)::int, coalesce(sum(coalesce(t.price, 0)), 0) / 1000000 into v_flying, v_fly_val
    from public.aircraft a left join public.aircraft_types t on t.id = a.aircraft_type_id
   where a.airline_id = p_airline_id and a.status = 'active';
  v_avg_price := case when v_flying > 0 then v_fly_val / v_flying else 0 end;
  v_now_f := coalesce((v_ops -> v_today::text ->> 'flights')::int, 0);
  v_then_f := coalesce((v_ops -> (v_today - 7)::text ->> 'flights')::int, 0);
  v_then_t := coalesce((v_ops -> (v_today - 7)::text ->> 'aircraft')::int, 0);
  select avg((v_ops -> (v_today - k)::text ->> 'load')::numeric) into v_load7 from generate_series(0, 6) k;
  select count(*)::int into v_on_order from public.aircraft a where a.airline_id = p_airline_id and a.status in ('on_order', 'delivered');
  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of),
    'profit_day', v_profit, 'span_days', v_span, 'early', case when v_span is not null then v_span < 7 end,
    'per_aircraft_day', v_per_ac,
    'return_on_fleet_pct_week', case when v_profit is not null and v_fly_val <> 0 then v_profit * 7 / v_fly_val * 100 end,
    'payback_days', case when v_per_ac > 0 and v_avg_price <> 0 then v_avg_price / v_per_ac end,
    'funds_aircraft_every_days', case when v_profit > 0 and v_avg_price <> 0 then v_avg_price / v_profit end,
    'fleet', v_flying, 'fleet_added_this_week', v_flying - v_then_t, 'on_order', v_on_order,
    'fleet_value', v_fly_val, 'average_price', v_avg_price,
    'flights_day', v_now_f, 'flights_added_this_week', v_now_f - v_then_f,
    'load_7_days', v_load7,
    'days', v_iv);
end
$function$

;

-- private.fig_fits(p_t timestamp with time zone[], p_v numeric[], p_td timestamp with time zone, p_n integer, p_price numeric, p_lease numeric, p_cushion numeric)
CREATE OR REPLACE FUNCTION private.fig_fits(p_t timestamp with time zone[], p_v numeric[], p_td timestamp with time zone, p_n integer, p_price numeric, p_lease numeric, p_cushion numeric)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(bool_and(x.v - p_n * (p_price + p_lease * private.fig_lease_weeks(x.t, p_td)) >= p_cushion), true)
    from unnest(p_t, p_v) as x(t, v)
   where x.t >= p_td
$function$

;

-- private.fig_flag(p_world_id bigint, p_airline_id bigint, p_key text)
CREATE OR REPLACE FUNCTION private.fig_flag(p_world_id bigint, p_airline_id bigint, p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::boolean from public.settings s
                    where s.world_id = p_world_id and s.key = p_key and (s.airline_id is null or s.airline_id = p_airline_id)
                    order by s.airline_id nulls last limit 1), false)
$function$

;

-- private.fig_flights_on(p_world_id bigint, p_from date, p_to date)
CREATE OR REPLACE FUNCTION private.fig_flights_on(p_world_id bigint, p_from date, p_to date)
 RETURNS TABLE(day date, airline_id bigint, flight_no integer, route_id bigint, tail text, launched_on date)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with f as (select * from private.fig_freqs(p_world_id) x where x.live),
  d as (select g::date as day, extract(isodow from g)::smallint as wd
          from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') g)
  select d.day, f.airline_id, f.no_out, f.route_id, f.tail, f.launched_on
    from f join d on d.wd = any (f.out_days) where f.no_out is not null
  union all
  select d.day, f.airline_id, f.no_back, f.route_id, f.tail, f.launched_on
    from f join d on d.wd = any (f.back_days) where f.no_back is not null
$function$

;

-- private.fig_freqs(p_world_id bigint, p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.fig_freqs(p_world_id bigint, p_airline_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(rotation_id bigint, airline_id bigint, route_id bigint, hub_code text, dest_code text, live boolean, days_n integer, flights_week integer, has_back boolean, tail text, launched_on date, no_out integer, no_back integer, out_days smallint[], back_days smallint[])
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select r.id, r.airline_id, r.route_id, ro.hub_code, ro.dest_code,
         not ro.removed and ro.airline_id = r.airline_id,
         coalesce(cardinality(l1.days_utc), 7),
         (case when l2.flight_no is not null then 2 else 1 end) * coalesce(cardinality(l1.days_utc), 7),
         l2.flight_no is not null,
         coalesce(ac.registration, ''), r.launched_on, l1.flight_no, coalesce(l2.flight_no, l1.flight_no - 1),
         case when l1.id is null then null
              when l1.dep_utc_min is null then l1.days_utc
              else private.shift_weekdays(l1.days_utc, floor((l1.dep_utc_min + o.oh) / 1440.0)::int) end,
         case when l1.id is null or l2.id is null or l2.dep_utc_min is null then null
              else private.shift_weekdays(l2.days_utc, floor((l2.dep_utc_min + o.od) / 1440.0)::int) end
    from public.rotations r
    join public.routes ro on ro.id = r.route_id
    left join public.flight_legs l1 on l1.rotation_id = r.id and l1.leg_no = 1
    left join public.flight_legs l2 on l2.rotation_id = r.id and l2.leg_no = 2
    left join public.aircraft ac on ac.id = coalesce(l1.aircraft_id, l2.aircraft_id)
    left join public.airports ah on ah.code = ro.hub_code
    left join public.world_airports wh on wh.world_id = r.world_id and wh.airport_code = ro.hub_code
    left join public.airports ad on ad.code = ro.dest_code
    left join public.world_airports wd on wd.world_id = r.world_id and wd.airport_code = ro.dest_code
    cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                               round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
   where r.world_id = p_world_id and (p_airline_id is null or r.airline_id = p_airline_id)
$function$

;

-- private.fig_group_today(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_group_today(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_cash numeric; v_flights bigint; v_income numeric; v_costs numeric; v_ops numeric; v_fpd numeric;
  v_ground text[]; v_lease numeric; v_closing numeric; v_ground_lease numeric;
begin
  select b.amount / 1000000 into v_cash from public.game_balance b
   where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_at <= p_as_of
   order by b.captured_at desc limit 1;
  select o.flights, o.income, o.costs into v_flights, v_income, v_costs from private.fig_ops_recent(p_airline_id, p_as_of) o;
  if v_flights >= 5 then
    select coalesce(sum(f.flights_week::numeric / 7), 0) into v_fpd from private.fig_freqs(w, p_airline_id) f where f.live and f.airline_id = p_airline_id;
    v_ops := (v_income - v_costs) / v_flights * v_fpd / 1000000;
  end if;
  select coalesce(array_agg(a.registration order by a.delivery_at, a.registration), '{}') into v_ground
    from public.aircraft a
   where a.airline_id = p_airline_id and a.status in ('on_order', 'delivered') and a.delivery_at <= p_as_of;
  select coalesce(sum(e.amount) filter (where e.descr ~* 'Leasing payment'), 0) / 7,
         coalesce(sum(e.amount) filter (where e.descr ~* 'Week-end closing'), 0) / 7,
         coalesce(sum(e.amount) filter (where exists (select 1 from unnest(v_ground) g where strpos(e.descr, g || ' ') > 0)), 0) / 7
    into v_lease, v_closing, v_ground_lease
    from private.fig_events(w, p_as_of, p_airline_id) e
   where e.airline_id = p_airline_id and e.at > p_as_of and e.at <= p_as_of + interval '168 hours';
  return jsonb_build_object('airline_id', p_airline_id, 'cash', v_cash, 'flight_profit_day', v_ops,
                            'leases_day', v_lease, 'closing_day', v_closing, 'net_day', v_ops - v_lease - v_closing,
                            'on_ground', to_jsonb(v_ground), 'on_ground_lease_day', v_ground_lease);
end
$function$

;

-- private.fig_growth_signals(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_growth_signals(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_days int := private.fig_num(p_world_id, null, 'growth_window_days')::int; v_docs jsonb;
begin
  -- each airline's route and aircraft profit over the growth window, for those with flights captured
  select coalesce(jsonb_agg(jsonb_build_object('airline_id', al.airline_id, 'ord', al.ord, 'doc', x.doc) order by al.ord), '[]'::jsonb) into v_docs
    from private.fig_airlines(p_world_id) al
    cross join lateral (select private.fig_route_profit(al.airline_id, v_days, p_as_of) as doc offset 0) x   -- once each
   where al.home_code is not null and (x.doc ->> 'flights')::int > 0;
  return (
    with r as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
                 from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'routes') with ordinality as e(x, i)),
    t as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
            from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'aircraft') with ordinality as e(x, i))
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'days', v_days,
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
$function$

;

-- private.fig_home(p_airline_id bigint)
CREATE OR REPLACE FUNCTION private.fig_home(p_airline_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((select b.airport_code from public.airline_bases b where b.airline_id = p_airline_id and b.is_main order by b.id limit 1),
                  (select a.home_airport_code from public.airlines a where a.id = p_airline_id))
$function$

;

-- private.fig_hub_progress(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_hub_progress(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_scan bigint; v_scan_at timestamptz; v_has_schedules boolean;
begin
  -- the latest world scan by then that has its airport summary
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = p_world_id and s.taken_at <= p_as_of
     and exists (select 1 from public.scan_airline_airports x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  v_has_schedules := exists (select 1 from public.game_scan_schedules x where x.scan_id = v_scan);
  return (
    with al as (select * from private.fig_airlines(p_world_id)),
    fq as (select * from private.fig_freqs(p_world_id) f where f.live),
    rivals as (select a.id from public.airlines a left join public.groups g on g.id = a.group_id
                where a.world_id = p_world_id and coalesce(g.kind, 'rival') <> 'ours'),
    -- the scan's rival flights from our bases, flights a week by origin, destination and airline (read once for all bases)
    sched as materialized (
      select f ->> 2 as origin, f ->> 3 as dest, sc.airline_id, coalesce(ra.public_name, ra.game_name, ra.planner_name) as name,
             sum(length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')))::int as weekly
        from public.game_scan_schedules sc
        join public.airlines ra on ra.id = sc.airline_id
        cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
       where v_has_schedules and sc.scan_id = v_scan and sc.airline_id in (select id from rivals)
         and jsonb_typeof(f) = 'array' and coalesce(f ->> 3, '') <> ''
         and f ->> 2 in (select b.airport_code from public.airline_bases b where b.world_id = p_world_id and not b.is_main)
       group by f ->> 2, f ->> 3, sc.airline_id, ra.public_name, ra.game_name, ra.planner_name),
    hubs as (
      select al.airline_id, al.ord, al.iata_code, al.name, al.main_code,
             private.fig_flag(p_world_id, al.airline_id, 'hub_first_exempt') as exempt,
             private.fig_num(p_world_id, al.airline_id, 'hub_first_departures') as target,
             -- departures a week flying from the main hub: outbound legs from it, and returns from it
             case when al.main_code is not null then
               (select coalesce(sum(f.days_n) filter (where f.hub_code = al.main_code), 0)
                       + coalesce(sum(f.days_n) filter (where f.dest_code = al.main_code and f.has_back), 0)
                  from fq f where f.airline_id = al.airline_id)::int end as departures,
             -- and those on the plan cards of aircraft not yet filed (each leg's days; every day unless set)
             case when al.main_code is not null then
               coalesce((select sum(coalesce(cardinality(l.days_utc), 7))
                           from public.aircraft a
                           join public.plan_cards c on c.aircraft_id = a.id
                           join public.plan_card_legs l on l.plan_card_id = c.id
                          where a.airline_id = al.airline_id and a.status in ('on_order', 'delivered') and l.origin_code = al.main_code), 0)::int end as planned
        from al),
    bases as (
      select b.airline_id, b.airport_code, b.role, b.position, b.id,
             (select jsonb_build_object('airline_id', x.airline_id, 'name', coalesce(ra.public_name, ra.game_name, ra.planner_name), 'weekly', x.weekly_departures)
                from public.scan_airline_airports x join public.airlines ra on ra.id = x.airline_id
               where x.scan_id = v_scan and x.airport_code = b.airport_code and x.airline_id in (select id from rivals)
               order by x.weekly_departures desc, x.airline_id limit 1) as top_rival,
             case when v_has_schedules then (
               select coalesce(jsonb_agg(jsonb_build_object('dest', z.dest, 'airline_id', z.airline_id, 'name', z.name, 'weekly', z.weekly)
                                         order by z.weekly desc, z.dest, z.airline_id), '[]'::jsonb)
                 from sched z
                where z.origin = b.airport_code and z.weekly > 7 * private.fig_num(p_world_id, b.airline_id, 'contested_rival_daily')) end as routes
        from public.airline_bases b
       where b.world_id = p_world_id and not b.is_main)
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of),
      'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at), 'schedules', v_has_schedules) end,
      'airlines', coalesce((select jsonb_agg(jsonb_build_object(
          'airline_id', h.airline_id, 'code', h.iata_code, 'name', h.name, 'main_hub', h.main_code,
          'exempt', h.exempt, 'target', h.target, 'departures', h.departures, 'planned', h.planned,
          'percent', h.departures / h.target * 100,
          'bases', coalesce((select jsonb_agg(jsonb_build_object(
              'code', b.airport_code, 'role', b.role, 'top_rival', b.top_rival,
              'contested_by_departures', coalesce((b.top_rival ->> 'weekly')::numeric > private.fig_num(p_world_id, b.airline_id, 'contested_rival_weekly'), false),
              'contested_routes', b.routes,
              'contested', coalesce((b.top_rival ->> 'weekly')::numeric > private.fig_num(p_world_id, b.airline_id, 'contested_rival_weekly'), false)
                           or coalesce(jsonb_array_length(b.routes) > 0, false))
              order by b.position nulls last, b.id) from bases b where b.airline_id = h.airline_id), '[]'::jsonb))
          order by h.ord) from hubs h), '[]'::jsonb)));
end
$function$

;

-- private.fig_lease_map(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_lease_map(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_object_agg(x.k, x.m), '{}'::jsonb)
    from (select private.fig_type_key((regexp_match(e.descr, 'Leasing payment for [^(]*\(([^)]+)\)', 'i'))[1]) as k, max(e.amount) as m
            from private.fig_events(p_world_id, p_as_of) e
           where e.descr ~* 'Leasing payment for'
           group by 1) x
   where x.k <> ''
$function$

;

-- private.fig_lease_weeks(p_t timestamp with time zone, p_td timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_lease_weeks(p_t timestamp with time zone, p_td timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select greatest(0, floor(extract(epoch from (p_t - (p_td + interval '168 hours'))) / 604800) + 1)::int
$function$

;

-- private.fig_load_days(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)
CREATE OR REPLACE FUNCTION private.fig_load_days(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)
 RETURNS TABLE(day date, done boolean, captured boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and g.kind = 'ours'),
  flown as (
    select f.airline_id, f.game_date, f.loads_captured_at
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.game_date is not null and f.loads_captured_at <= p_as_of),
  captures as (
    select r.airline_id, r.captured_at from public.game_capture_raw r join ours on ours.id = r.airline_id
     where r.kind = 'loads' and r.captured_at <= p_as_of
    union
    select f.airline_id, f.loads_captured_at from flown f),
  stamped as (
    select x.airline_id, x.day, max(c.captured_at) as at
      from (select distinct f.airline_id, f.game_date as day from flown f where f.game_date between p_from and p_to) x
      join captures c on c.airline_id = x.airline_id and (c.captured_at at time zone 'UTC')::date - 3 <= x.day
     group by x.airline_id, x.day),
  flags as (
    select ld.* from public.load_days ld
     where ld.world_id = p_world_id and ld.game_date between p_from and p_to and (ld.entered_at is null or ld.entered_at <= p_as_of)),
  days as (
    select f.game_date as day from flown f where f.game_date between p_from and p_to
    union select fl.game_date from flags fl
    union select e.game_date from public.load_entries e join ours on ours.id = e.airline_id
           where e.world_id = p_world_id and e.game_date between p_from and p_to and (e.entered_at is null or e.entered_at <= p_as_of)),
  day_stamp as (select s.day, max(s.at) as at from stamped s group by s.day)
  select d.day,
         case when ld.game_date is null then private.fig_day_captured(p_world_id, d.day, p_as_of)
              when ds.at is not null and (ld.entered_at is null or ds.at > ld.entered_at)
                then ld.done or private.fig_day_captured(p_world_id, d.day, p_as_of)
              else ld.done end,
         ds.day is not null
    from days d
    left join flags ld on ld.game_date = d.day
    left join day_stamp ds on ds.day = d.day
$function$

;

-- private.fig_load_values(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)
CREATE OR REPLACE FUNCTION private.fig_load_values(p_world_id bigint, p_as_of timestamp with time zone, p_from date, p_to date)
 RETURNS TABLE(day date, airline_id bigint, flight_no integer, v numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and g.kind = 'ours'),
  flown as (
    select f.airline_id, f.game_date, f.flight_no, f.eco_pct, f.loads_captured_at
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.game_date is not null and f.loads_captured_at <= p_as_of),
  captures as (
    select r.airline_id, r.captured_at from public.game_capture_raw r join ours on ours.id = r.airline_id
     where r.kind = 'loads' and r.captured_at <= p_as_of
    union
    select f.airline_id, f.loads_captured_at from flown f),
  stamped as (
    select x.airline_id, x.day, max(c.captured_at) as at
      from (select distinct f.airline_id, f.game_date as day from flown f where f.game_date between p_from and p_to) x
      join captures c on c.airline_id = x.airline_id and (c.captured_at at time zone 'UTC')::date - 3 <= x.day
     group by x.airline_id, x.day),
  caught as (
    select f.airline_id, f.game_date as day, f.flight_no, max(f.eco_pct) as eco_pct
      from flown f where f.eco_pct is not null and f.game_date between p_from and p_to
     group by f.airline_id, f.game_date, f.flight_no),
  typed as (
    select e.* from public.load_entries e join ours on ours.id = e.airline_id
     where e.world_id = p_world_id and e.game_date between p_from and p_to and (e.entered_at is null or e.entered_at <= p_as_of))
  select coalesce(c.day, e.game_date), coalesce(c.airline_id, e.airline_id), coalesce(c.flight_no, e.flight_no),
         case when e.airline_id is not null and (c.eco_pct is null or s.at is null or e.entered_at is null or e.entered_at >= s.at)
              then trim_scale(e.eco_pct) else c.eco_pct end
    from caught c
    full join typed e on e.airline_id = c.airline_id and e.game_date = c.day and e.flight_no = c.flight_no
    left join stamped s on s.airline_id = coalesce(c.airline_id, e.airline_id) and s.day = coalesce(c.day, e.game_date)
$function$

;

-- private.fig_num(p_world_id bigint, p_airline_id bigint, p_key text)
CREATE OR REPLACE FUNCTION private.fig_num(p_world_id bigint, p_airline_id bigint, p_key text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  select s.value into v from public.settings s
   where s.world_id = p_world_id and s.key = p_key and (s.airline_id is null or s.airline_id = p_airline_id)
   order by s.airline_id nulls last limit 1;
  if v is null or jsonb_typeof(v) <> 'number' then
    raise exception 'setting % is missing or isn''t a number', p_key using errcode = '22023';
  end if;
  return (v #>> '{}')::numeric;
end
$function$

;

-- private.fig_ops_recent(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_ops_recent(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS TABLE(flights bigint, income numeric, costs numeric, last_ts timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with money as (
    select f.posted_at as ts, f.income_total as income, f.cost_total as costs, (f.pax_income is not null)::int as flights
      from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at is not null and coalesce(f.money_captured_at, f.posted_at) <= p_as_of
    union all
    select p.paid_at, case when p.side = 'C' then p.amount else 0 end, case when p.side = 'C' then 0 else p.amount end, 0
      from public.game_payments p
     where p.airline_id = p_airline_id and p.kind = 'other' and p.created_at <= p_as_of),
  last as (
    select max(x.ts) as lt from (
      select f.posted_at as ts from public.game_flights f
       where f.airline_id = p_airline_id and f.posted_at is not null and coalesce(f.money_captured_at, f.posted_at) <= p_as_of
      union all
      select p.paid_at from public.game_payments p where p.airline_id = p_airline_id and p.created_at <= p_as_of) x)
  select sum(m.flights)::bigint, coalesce(sum(m.income), 0), coalesce(sum(m.costs), 0), max(l.lt)
    from money m cross join last l
   where l.lt is not null and m.ts > l.lt - interval '24 hours'
$function$

;

-- private.fig_order_cabin(p_airline_id bigint, p_type_id bigint)
CREATE OR REPLACE FUNCTION private.fig_order_cabin(p_airline_id bigint, p_type_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with al as (select a.id, a.is_lcc from public.airlines a where a.id = p_airline_id),
  c as (select cc.id, cc.cabin from public.cabin_configs cc where cc.aircraft_type_id = p_type_id),
  want as (select case when al.is_lcc and exists (select 1 from c where c.cabin = 'Standard') then 'Standard'
                       when exists (select 1 from c where c.cabin = 'Leisure') then 'Leisure'
                       else 'Comfort' end as cabin from al)
  select c.id from c, want
   where c.cabin = want.cabin
   order by exists (select 1 from public.markets m where m.airline_id = p_airline_id and m.default_config_id = c.id) desc,
            exists (select 1 from public.markets m where m.default_config_id = c.id) desc, c.id desc
   limit 1
$function$

;

-- private.fig_patterns(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_patterns(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_today date := (p_as_of at time zone 'UTC')::date; v_to date; v_from date; v_lw int;
begin
  v_to := v_today + 2;
  v_from := v_to - private.fig_num(p_world_id, null, 'load_window_days')::int + 1;
  v_lw := private.fig_num(p_world_id, null, 'load_leeway_days')::int;
  return (
    with ld as (select * from private.fig_load_days(p_world_id, p_as_of, v_from, v_to) x where x.done),
    lv as (select * from private.fig_load_values(p_world_id, p_as_of, v_from, v_to) x where x.v is not null),
    fl as (select x.day, x.airline_id, x.flight_no, x.route_id, lv.v
             from private.fig_flights_on(p_world_id, v_from, v_to) x
             join ld on ld.day = x.day
             left join lv on lv.day = x.day and lv.airline_id = x.airline_id and lv.flight_no = x.flight_no
            where not (x.launched_on is not null and x.day - x.launched_on < v_lw)
              and not (ld.captured and lv.v is null)),
    p as (select fl.route_id, fl.airline_id, count(*)::int as n,
                 count(*) filter (where coalesce(fl.v, 0) = 0 or fl.v >= 95)::int as full_n,
                 count(*) filter (where fl.v > 0 and fl.v >= 85 and fl.v < 95)::int as b95,
                 count(*) filter (where fl.v > 0 and fl.v >= 70 and fl.v < 85)::int as b85,
                 count(*) filter (where fl.v > 0 and fl.v < 70)::int as b70,
                 count(distinct fl.day)::int as days, count(distinct fl.flight_no)::int as flights
            from fl group by fl.route_id, fl.airline_id),
    th as (select x.airline_id,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_min_departures') as min_n,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_cut_under70_share') as cut70,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_cut_under85_share') as cut85,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_watch_under85_share') as watch85,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_add_min_departures') as add_n,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_add_full_share') as add_full
             from (select distinct p.airline_id from p) x),
    m as (select p.*, ro.hub_code, ro.dest_code, a.position, th.min_n, th.cut70, th.cut85, th.watch85, th.add_n, th.add_full
            from p join public.routes ro on ro.id = p.route_id join public.airlines a on a.id = p.airline_id
            join th on th.airline_id = p.airline_id),
    s as (select m.*, case when m.n >= m.min_n and (m.b70::numeric / m.n >= m.cut70 or (m.b85 + m.b70)::numeric / m.n >= m.cut85) then 'cut'
                           when m.n >= m.min_n and (m.b85 + m.b70)::numeric / m.n >= m.watch85 then 'watch'
                           when m.n >= m.add_n and m.full_n::numeric / m.n >= m.add_full then 'add'
                           else 'hold' end as mark
            from m)
    select coalesce(jsonb_agg(jsonb_build_object(
             'airline_id', s.airline_id, 'route_id', s.route_id, 'hub', s.hub_code, 'dest', s.dest_code,
             'departures', s.n, 'full', s.full_n, 'under_95', s.b95, 'under_85', s.b85, 'under_70', s.b70,
             'days', s.days, 'flights', s.flights, 'mark', s.mark,
             'why', case s.mark when 'cut' then 'under 85% on most departures — reduce frequency or downgauge'
                                when 'watch' then 'a third of departures under 85%'
                                when 'add' then '95%+ on nearly every departure — add frequency or upgauge' else '' end)
             order by s.position nulls last, s.airline_id, s.hub_code, s.dest_code), '[]'::jsonb)
      from s);
end
$function$

;

-- private.fig_route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_since timestamptz; v_pnl jsonb; v_loads jsonb; v_used boolean[]; v_mp int[] := '{}'; v_ml int[] := '{}';
  c record; v_cur int := -1; v_got boolean := false;
  v_losing numeric; v_sold_share numeric; v_sold_min numeric; v_fix_min numeric; v_fix_eco numeric; v_fix_routes numeric; v_fix_margin numeric;
begin
  if p_days is null or p_days < 1 then raise exception 'p_days must be 1 or more' using errcode = '22023'; end if;
  v_losing := private.fig_num(w, p_airline_id, 'growth_losing_min_departures');
  v_sold_share := private.fig_num(w, p_airline_id, 'growth_sold_out_share');
  v_sold_min := private.fig_num(w, p_airline_id, 'growth_sold_out_min_departures');
  v_fix_min := private.fig_num(w, p_airline_id, 'growth_fix_min_departures');
  v_fix_eco := private.fig_num(w, p_airline_id, 'growth_fix_economy_pct');
  v_fix_routes := private.fig_num(w, p_airline_id, 'growth_fix_min_routes');
  v_fix_margin := private.fig_num(w, p_airline_id, 'growth_fix_margin');
  -- the statement blocks posted since now − p_days (inside the old planner's window of 8 UTC days), as game_flight_pnl
  -- groups them: one per minute and block, its route when its lines name one, and its money
  v_since := greatest(p_as_of - p_days * interval '24 hours', (v_today - 8)::timestamp at time zone 'UTC');
  with money as (
    select f.posted_at as ts, f.statement_blk::int as blk, f.statement_routes::int as routes_n,
           case when f.statement_routes > 0 then f.origin_code || '-' || f.dest_code end as route,
           f.maint_registration as tail, f.pax_income, f.cargo_income, f.fuel, f.onboard, f.handling, f.landing, f.atc, f.maintenance,
           f.income_total as income, f.cost_total as costs
      from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at >= v_since and coalesce(f.money_captured_at, f.posted_at) <= p_as_of
    union all
    select p.paid_at, p.statement_blk::int, 0, null, null, null, null, null, null, null, null, null, null,
           case when p.side = 'C' then p.amount else 0 end, case when p.side = 'C' then 0 else p.amount end
      from public.game_payments p
     where p.airline_id = p_airline_id and p.paid_at >= v_since and p.created_at <= p_as_of
       and coalesce(p.statement_blk::int, 1) > 0 and p.kind = 'other'),
  pnl as (
    select m.ts, m.blk, max(m.route) as route, coalesce(max(m.routes_n), 0) as routes_n, max(m.tail) as tail,
           coalesce(sum(m.pax_income), 0) as pax_income, coalesce(sum(m.cargo_income), 0) as cargo_income,
           coalesce(sum(m.fuel), 0) as fuel, coalesce(sum(m.onboard), 0) as onboard, coalesce(sum(m.handling), 0) as handling,
           coalesce(sum(m.landing), 0) as landing, coalesce(sum(m.atc), 0) as atc, coalesce(sum(m.maintenance), 0) as maintenance,
           coalesce(sum(m.income) - sum(m.costs), 0) as profit
      from money m group by m.ts, m.blk)
  select coalesce(jsonb_agg(to_jsonb(x) order by x.i), '[]'::jsonb) into v_pnl
    from (select pnl.*, (row_number() over (order by pnl.ts, pnl.blk nulls first))::int as i from pnl) x;
  -- the loads of the last 9 days (CAP.loads: one per date and flight number) with a route and departure time, each
  -- departure in UTC from its origin's offset (capDepUTC)
  select coalesce(jsonb_agg(to_jsonb(y) order by y.j), '[]'::jsonb) into v_loads
    from (select x.*, (row_number() over (order by x.id))::int as j,
                 private.local_to_utc(x.game_date, x.dep_local, private.fig_eq_off(x.origin)) as dep_utc
            from (select distinct on (f.game_date, f.flight_no) f.id, f.game_date, f.flight_no, f.origin_code as origin,
                         f.dest_code as dest, f.dep_local, f.registration, f.eco_pct as eco, f.bus_pct as bus,
                         f.cargo_pct as cargo, trim_scale(f.eco_fare) as eco_fare
                    from public.game_flights f
                   where f.airline_id = p_airline_id and f.flight_no is not null and f.game_date >= v_today - 9
                     and f.loads_captured_at <= p_as_of
                   order by f.game_date, f.flight_no, f.id desc) x
           where coalesce(x.origin, '') <> '' and coalesce(x.dest, '') <> '' and coalesce(x.dep_local, '') <> '') y;

  -- each one-route block, in order, takes the nearest loads row of its route departing within 31 minutes that no earlier
  -- block took (the first in the list on a tie)
  v_used := array_fill(false, array[greatest(jsonb_array_length(v_loads), 1)]);
  for c in
    select p.i, l.j
      from jsonb_to_recordset(v_pnl) as p(i int, ts timestamptz, route text, routes_n int)
      join jsonb_to_recordset(v_loads) as l(j int, origin text, dest text, dep_utc timestamptz)
        on p.routes_n = 1 and p.route is not null and l.dep_utc is not null
       and l.origin = split_part(p.route, '-', 1) and l.dest = split_part(p.route, '-', 2)
       and abs(extract(epoch from (l.dep_utc - p.ts))) < 1860
     order by p.i, abs(extract(epoch from (l.dep_utc - p.ts))), l.j
  loop
    if c.i <> v_cur then v_cur := c.i; v_got := false; end if;
    if v_got or v_used[c.j] then continue; end if;
    v_used[c.j] := true; v_got := true;
    v_mp := v_mp || c.i; v_ml := v_ml || c.j;
  end loop;

  return (
    with p as (select * from jsonb_to_recordset(v_pnl) as x(i int, ts timestamptz, route text, routes_n int, tail text, profit numeric,
                                                             pax_income numeric, cargo_income numeric, fuel numeric, onboard numeric,
                                                             handling numeric, landing numeric, atc numeric, maintenance numeric)),
    l as (select * from jsonb_to_recordset(v_loads) as x(j int, game_date date, origin text, dest text, registration text,
                                                          eco numeric, bus numeric, cargo numeric, eco_fare numeric)),
    m as (select * from unnest(v_mp, v_ml) as m(i, j)),
    fl as (select p.*, split_part(p.route, '-', 1) as o, split_part(p.route, '-', 2) as d, l.j, l.eco, l.bus, l.cargo, l.eco_fare,
                  coalesce(nullif(l.registration, ''), nullif(p.tail, '')) as reg
             from p left join m on m.i = p.i left join l on l.j = m.j
            where p.route is not null and p.routes_n = 1),
    -- keyOf(): the route as the airline's list has it, either way round, else as flown (materialized: worked out once,
    -- not again for each flight joined to it)
    rk as materialized (select distinct fl.o, fl.d, coalesce(r1.id, r2.id) as route_id,
                  coalesce(r1.hub_code, r2.hub_code, fl.o) as hub, coalesce(r1.dest_code, r2.dest_code, fl.d) as dest
             from fl
             left join public.routes r1 on r1.airline_id = p_airline_id and not r1.removed and r1.hub_code = fl.o and r1.dest_code = fl.d
             left join public.routes r2 on r2.airline_id = p_airline_id and not r2.removed and r2.hub_code = fl.d and r2.dest_code = fl.o),
    -- the airline's rotations (an aircraft flies only its own airline's rotations, so legsDay's rotations by aircraft are
    -- among them)
    fq as (select * from private.fig_freqs(w, p_airline_id)),
    wk as (select f.route_id, sum(f.flights_week)::int as wk from fq f where f.live and f.airline_id = p_airline_id group by f.route_id),
    g as (select rk.hub, rk.dest, rk.route_id, count(*)::int as n, sum(fl.profit) / 1000000 as profit,
                 sum(fl.pax_income + fl.cargo_income) / 1000000 as income,
                 avg(fl.eco) as eco_a, avg(fl.bus) as bus_a, avg(fl.cargo) as cargo_a, avg(fl.eco_fare) as fare_a,
                 count(fl.eco)::int as eco_n, (count(*) filter (where fl.eco >= 100))::int as sold, min(fl.i) as first_i
            from fl join rk on rk.o = fl.o and rk.d = fl.d
           group by rk.hub, rk.dest, rk.route_id),
    r as (select g.*, g.profit / g.n as ppf, case when g.income > 0 then g.profit / g.income end as margin,
                 coalesce(wk.wk, 0) as wk, (g.profit / g.n) * coalesce(wk.wk, 0) as pwk,
                 case when g.eco_n > 0 then g.sold::numeric / g.eco_n end as sold_share
            from g left join wk on wk.route_id = g.route_id),
    pp as (select array_agg(r.ppf order by r.ppf) as a from r),
    q as (select pp.a[floor(cardinality(pp.a) / 2.0)::int + 1] as med, pp.a[floor(cardinality(pp.a) * 0.25)::int + 1] as q25,
                 coalesce(cardinality(pp.a), 0) as len from pp),
    mk as (select r.*, case when r.ppf < 0 and r.n >= v_losing then 'losing'
                            when r.sold_share is not null and r.sold_share >= v_sold_share and r.n >= v_sold_min
                              then case when r.ppf >= q.med then 'add' else 'raise' end
                            when r.n >= v_fix_min and r.eco_a is not null and r.eco_a < v_fix_eco then 'fix'
                            when r.n >= v_fix_min and q.len >= v_fix_routes and r.ppf <= q.q25 and r.margin is not null and r.margin < v_fix_margin then 'fix-margin'
                            else 'hold' end as k, q.med
             from r cross join q),
    routes as (select coalesce(jsonb_agg(jsonb_build_object(
                 'route_id', mk.route_id, 'hub', mk.hub, 'dest', mk.dest, 'flights', mk.n, 'profit', mk.profit, 'income', mk.income,
                 'margin', mk.margin, 'profit_per_flight', mk.ppf, 'flights_week', mk.wk, 'profit_week', mk.pwk,
                 'economy', mk.eco_a, 'business', mk.bus_a, 'cargo', mk.cargo_a, 'economy_fare', mk.fare_a,
                 'sold_out', mk.sold, 'with_loads', mk.eco_n, 'sold_out_share', mk.sold_share,
                 'mark', case when mk.k = 'fix-margin' then 'fix' else mk.k end,
                 'why', case mk.k when 'losing' then 'its average flight loses money'
                                  when 'add' then format('sold out on %s of %s departures, profit a flight above the airline''s middle route', mk.sold, mk.eco_n)
                                  when 'raise' then format('sold out on %s of %s departures, profit a flight below the airline''s middle route', mk.sold, mk.eco_n)
                                  when 'fix' then format('economy averaging %s%%', floor(mk.eco_a + 0.5))
                                  when 'fix-margin' then format('bottom-quarter profit a flight on a margin under %s%%', floor(v_fix_margin * 100 + 0.5))
                                  else '' end)
                 order by mk.pwk desc, mk.ppf desc, mk.first_i), '[]'::jsonb) as v from mk),
    -- the aircraft: each one's average flight × its scheduled flights a day, plus its statement lines without a route
    -- spread over the days captured, less its lease a day (the last leasing payment the events list for it, ÷ 7)
    lease as materialized (select distinct on (x.reg) x.reg, x.amount
                from (select (regexp_match(e.descr, 'Leasing payment for ([A-Z0-9-]+)'))[1] as reg, e.amount, e.event_date, e.event_time
                        from private.fig_events(w, p_as_of, p_airline_id) e where e.airline_id = p_airline_id) x
               where x.reg is not null order by x.reg, x.event_date desc, x.event_time desc),
    extra as (select p.tail as reg, sum(p.profit) / 1000000 as v from p where p.route is null and coalesce(p.tail, '') <> '' group by p.tail),
    capdays as (select greatest(1, least(p_days, count(distinct (p.ts at time zone 'UTC')::date)))::int as v from p),
    legs as (select f.tail as reg, sum(f.flights_week::numeric / 7) as v from fq f group by f.tail),
    tl as (select fl.reg, count(*)::int as n, sum(fl.profit) / 1000000 as profit, min(fl.i) as first_i
             from fl where fl.reg is not null group by fl.reg),
    t as (select tl.*, (tl.profit / tl.n) * coalesce(nullif(lg.v, 0), tl.n) + coalesce(ex.v, 0) / cd.v as day, ls.amount / 7 as ls,
                 coalesce((select ty.name from public.aircraft a join public.aircraft_types ty on ty.id = a.aircraft_type_id
                            where a.world_id = w and a.registration = tl.reg and a.status = 'active' limit 1), '') as type,
                 (select coalesce(jsonb_agg(z.lab order by z.fi), '[]'::jsonb)
                    from (select fl2.o || '–' || fl2.d as lab, min(fl2.i) as fi from fl fl2 where fl2.reg = tl.reg group by 1) z) as routes
            from tl cross join capdays cd
            left join legs lg on lg.reg = tl.reg left join extra ex on ex.reg = tl.reg left join lease ls on ls.reg = tl.reg),
    aircraft as (select coalesce(jsonb_agg(jsonb_build_object(
                   'registration', t.reg, 'type', t.type, 'flights', t.n, 'flight_profit_day', t.day, 'lease_day', t.ls,
                   'net_day', t.day - t.ls, 'routes', t.routes)
                   order by coalesce(t.day - t.ls, t.day) desc, t.first_i), '[]'::jsonb) as v from t),
    -- the fare changes: each route's average captured economy fare by date against the date before, over 1% apart
    fd as (select l.origin, l.dest, l.game_date, avg(l.eco_fare) as fare, avg(l.eco) as eco
             from l where l.eco_fare is not null group by l.origin, l.dest, l.game_date),
    ch as (select fd.*, lag(fd.fare) over w1 as prev_fare, lag(fd.eco) over w1 as prev_eco
             from fd window w1 as (partition by fd.origin, fd.dest order by fd.game_date)),
    changes as (select coalesce(jsonb_agg(jsonb_build_object(
                  'origin', ch.origin, 'dest', ch.dest, 'date', ch.game_date, 'fare_before', ch.prev_fare, 'fare_after', ch.fare,
                  'economy_before', ch.prev_eco, 'economy_after', ch.eco)
                  order by ch.game_date desc, ch.origin, ch.dest), '[]'::jsonb) as v
                  from ch where ch.prev_fare is not null and ch.prev_fare <> 0 and ch.fare <> 0 and abs(ch.fare - ch.prev_fare) / ch.prev_fare > 0.01),
    av as (select count(*)::int as n,
                  jsonb_build_object('passengers', sum(fl.pax_income), 'cargo', sum(fl.cargo_income), 'fuel', sum(fl.fuel),
                                     'handling', sum(fl.handling), 'onboard', sum(fl.onboard), 'landing', sum(fl.landing),
                                     'air_traffic', sum(fl.atc), 'maintenance', sum(fl.maintenance)) as sums,
                  count(*) filter (where fl.j is not null)::int as matched
             from fl)
    select jsonb_build_object(
             'airline_id', p_airline_id, 'days', p_days, 'as_of', private.fig_ts(p_as_of), 'since', private.fig_ts(v_since),
             'flights', av.n, 'matched', av.matched, 'mixed', (select count(*)::int from p where p.routes_n > 1),
             'average_flight', case when av.n = 0 then null
                                    else (select jsonb_object_agg(e.key, (e.value #>> '{}')::numeric / av.n / 1000000) from jsonb_each(av.sums) e) end,
             'routes', (select v from routes), 'aircraft', (select v from aircraft), 'fare_changes', (select v from changes))
      from av);
end
$function$

;

-- private.fig_ts(p timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_ts(p timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select to_char(p at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$function$

;

-- private.fig_type_key(p text)
CREATE OR REPLACE FUNCTION private.fig_type_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select regexp_replace(regexp_replace(regexp_replace(upper(coalesce(p, '')), 'AIRBUS', '', 'g'), 'EMBRAER', 'E', 'g'), '[^A-Z0-9]', '', 'g')
$function$

;

-- private.fig_world(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.fig_world(p_world_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare w bigint;
begin
  select x.id into w from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default) order by x.id limit 1;
  if w is null then raise exception 'no such world: %', coalesce(p_world_id::text, 'no default world') using errcode = '22023'; end if;
  return w;
end
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

-- private.freeze_planner_state()
CREATE OR REPLACE FUNCTION private.freeze_planner_state()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_since text := coalesce(private.planner_frozen_since('public.planner_state'::regclass),
                                 private.planner_frozen_since('public.planner_loads'::regclass),
                                 to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC');
  t text;
begin
  foreach t in array array['planner_state', 'planner_loads'] loop
    if private.planner_frozen_since(('public.' || t)::regclass) is not null then
      continue;
    elsif exists (select 1 from pg_catalog.pg_trigger x where x.tgrelid = ('public.' || t)::regclass and x.tgname = 'planner_frozen') then
      execute format('alter table public.%I enable trigger planner_frozen', t);   -- switched off by hand: on again
    else
      execute format('create trigger planner_frozen before insert or update or delete or truncate on public.%I '
                     'for each statement execute function private.planner_frozen(%L)', t, v_since);
      execute format('comment on trigger planner_frozen on public.%I is %L', t,
                     'The switch-over (#13, design §8): refuses every write to the old row, "frozen since ' || v_since
                     || '; write to the tables". private.unfreeze_planner_state() lifts it.');
    end if;
  end loop;
  return v_since;
end
$function$
;


-- private.growth_key(p_airline text, p_day date, p_move text, p_note text)
CREATE OR REPLACE FUNCTION private.growth_key(p_airline text, p_day date, p_move text, p_note text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_array(p_airline, p_day, p_move, p_note)::text
$function$

;

-- private.history_cash(p_world_id bigint, p_day date, p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.history_cash(p_world_id bigint, p_day date, p_at timestamp with time zone)
 RETURNS TABLE(airline_id bigint, cash numeric, fixed_next7 numeric, cash_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  bal as (
    select distinct on (b.airline_id) b.airline_id, b.amount, b.captured_at
      from public.game_balance b
     where b.world_id = p_world_id and b.capture_day = p_day and b.account like '2800%' and b.amount is not null
       and b.captured_at <= p_at
     order by b.airline_id, b.captured_at desc)
  select o.id,
         case when bal.airline_id is not null then bal.amount else ce.cash end,
         case when bal.airline_id is not null
              then (select sum(e.debit) from public.game_events e
                     where e.airline_id = o.id and e.debit > 0 and e.due_at > bal.captured_at
                       and e.due_at <= bal.captured_at + interval '7 days')
              else ce.fixed_next7 end,
         bal.captured_at
    from ours o
    left join bal on bal.airline_id = o.id
    left join public.cash_entries ce on ce.airline_id = o.id and ce.day = p_day
$function$

;

-- private.history_fleet(p_world_id bigint, p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.history_fleet(p_world_id bigint, p_at timestamp with time zone)
 RETURNS TABLE(airline_id bigint, aircraft_by_type jsonb, aircraft_total integer, on_order integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  ac as (
    select x.airline_id, coalesce(t.name, '(no type)') as type_name, x.ordered_on, x.status, x.delivery_at,
           x.status = 'retired' and (x.retired_on is null or x.retired_on <= (p_at at time zone 'UTC')::date) as gone
      from public.aircraft x left join public.aircraft_types t on t.id = x.aircraft_type_id
     where x.world_id = p_world_id),
  st as (
    select ac.airline_id, ac.type_name,
           not ac.gone and ac.status <> 'on_order' and (ac.delivery_at is null or ac.delivery_at <= p_at) as flying,
           not ac.gone and (ac.status = 'on_order' or ac.delivery_at > p_at)
             and (ac.ordered_on is null or ac.ordered_on <= (p_at at time zone 'UTC')::date) as ordered
      from ac),
  by_type as (
    select s.airline_id, s.type_name, count(*)::int as n from st s where s.flying group by s.airline_id, s.type_name)
  select o.id,
         coalesce((select jsonb_object_agg(b.type_name, b.n) from by_type b where b.airline_id = o.id), '{}'::jsonb),
         (select count(*)::int from st s where s.airline_id = o.id and s.flying),
         (select count(*)::int from st s where s.airline_id = o.id and s.ordered)
    from ours o
$function$

;

-- private.history_flows(p_world_id bigint, p_from date, p_to date)
CREATE OR REPLACE FUNCTION private.history_flows(p_world_id bigint, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare n_routes int := 0; n_days int := 0;
begin
  if p_from is null or p_to is null or p_to < p_from then
    return jsonb_build_object('route_days', 0, 'airline_days', 0);
  end if;
  if to_regclass('pg_temp.t_history_rows') is null then
    create temporary table t_history_rows (airline_id bigint, route_id bigint, origin_code text, dest_code text, day date,
      is_flight boolean, has_loads boolean, pax int, seats int, eco_pax int, eco_seats int, eco_fare numeric, income numeric,
      costs numeric) on commit drop;
  end if;
  truncate pg_temp.t_history_rows;
  insert into pg_temp.t_history_rows
  select f.airline_id, f.route_id, nullif(f.origin_code, ''), nullif(f.dest_code, ''),
         coalesce((f.dep_at at time zone 'UTC')::date, f.game_date),
         f.flight_no is not null or f.pax_income is not null, f.flight_no is not null,
         case when f.flight_no is not null then coalesce(f.eco_pax, 0) + coalesce(f.bus_pax, 0) + coalesce(f.fst_pax, 0)
              else f.statement_pax end,
         case when f.flight_no is not null then coalesce(f.eco_seats, 0) + coalesce(f.bus_seats, 0) + coalesce(f.fst_seats, 0) end,
         case when f.flight_no is not null then f.eco_pax end, case when f.flight_no is not null then f.eco_seats end,
         f.eco_fare, f.income_total, f.cost_total
    from public.game_flights f
   where f.world_id = p_world_id
     and f.dep_at >= (p_from::timestamp at time zone 'UTC') and f.dep_at < ((p_to + 1)::timestamp at time zone 'UTC')
  union all
  select f.airline_id, f.route_id, nullif(f.origin_code, ''), nullif(f.dest_code, ''), f.game_date, true, true,
         coalesce(f.eco_pax, 0) + coalesce(f.bus_pax, 0) + coalesce(f.fst_pax, 0),
         coalesce(f.eco_seats, 0) + coalesce(f.bus_seats, 0) + coalesce(f.fst_seats, 0),
         f.eco_pax, f.eco_seats, f.eco_fare, f.income_total, f.cost_total
    from public.game_flights f
   where f.world_id = p_world_id and f.dep_at is null and f.flight_no is not null and f.game_date between p_from and p_to;

  delete from public.route_days r where r.world_id = p_world_id and r.day between p_from and p_to;
  insert into public.route_days (world_id, airline_id, route_id, origin_code, dest_code, day, flights, passengers, seats,
                                 revenue, costs, profit, eco_fare_avg)
  select p_world_id, x.airline_id, max(x.route_id), x.origin_code, x.dest_code, x.day, count(*)::int,
         sum(x.pax)::int, sum(x.seats)::int,
         coalesce(sum(x.income), 0), coalesce(sum(x.costs), 0), coalesce(sum(x.income), 0) - coalesce(sum(x.costs), 0),
         round(coalesce(sum(x.eco_fare * x.eco_pax) filter (where x.eco_pax > 0)
                          / nullif(sum(x.eco_pax) filter (where x.eco_pax > 0 and x.eco_fare is not null), 0),
                        avg(x.eco_fare)), 2)
    from pg_temp.t_history_rows x
   where x.is_flight and x.origin_code is not null and x.dest_code is not null
   group by x.airline_id, x.origin_code, x.dest_code, x.day;
  get diagnostics n_routes = row_count;

  update public.airline_days a
     set flights_flown = coalesce(v.flights, 0), passengers = coalesce(v.pax, 0), seats_flown = coalesce(v.seats, 0),
         load_pct = round(100.0 * v.loads_pax / nullif(v.seats, 0), 1),
         eco_load_pct = round(100.0 * v.eco_pax / nullif(v.eco_seats, 0), 1),
         revenue = coalesce(v.income, 0), flight_costs = coalesce(v.costs, 0),
         flight_profit = coalesce(v.income, 0) - coalesce(v.costs, 0),
         leases_paid = coalesce(p.leases, 0), salaries_paid = coalesce(p.salaries, 0), purchases_paid = coalesce(p.purchases, 0)
    from public.airline_days d
    left join lateral (
      select count(*) filter (where x.is_flight) as flights,
             sum(x.pax) filter (where x.is_flight) as pax,
             sum(x.seats) filter (where x.is_flight and x.has_loads) as seats,
             sum(x.pax) filter (where x.is_flight and x.has_loads) as loads_pax,
             sum(x.eco_pax) filter (where x.is_flight and x.has_loads) as eco_pax,
             sum(x.eco_seats) filter (where x.is_flight and x.has_loads) as eco_seats,
             sum(x.income) as income, sum(x.costs) as costs
        from pg_temp.t_history_rows x where x.airline_id = d.airline_id and x.day = d.day) v on true
    left join lateral (
      select sum(case when y.side = 'C' then -y.amount else y.amount end) filter (where y.kind = 'lease') as leases,
             sum(case when y.side = 'C' then -y.amount else y.amount end) filter (where y.kind = 'salaries') as salaries,
             sum(case when y.side = 'C' then -y.amount else y.amount end)
               filter (where y.kind in ('purchase', 'deposit', 'cabin', 'refit')) as purchases
        from public.game_payments y
       where y.airline_id = d.airline_id
         and y.paid_at >= (d.day::timestamp at time zone 'UTC') and y.paid_at < ((d.day + 1)::timestamp at time zone 'UTC')) p on true
   where a.airline_id = d.airline_id and a.day = d.day and d.world_id = p_world_id and d.day between p_from and p_to;
  get diagnostics n_days = row_count;
  truncate pg_temp.t_history_rows;
  return jsonb_build_object('route_days', n_routes, 'airline_days', n_days);
end
$function$

;

-- private.history_schedule(p_world_id bigint, p_day date)
CREATE OR REPLACE FUNCTION private.history_schedule(p_world_id bigint, p_day date)
 RETURNS TABLE(airline_id bigint, weekly_departures integer, weekly_seats integer, destinations integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select r.airline_id, sum(cardinality(l.days_utc))::int,
         sum(cardinality(l.days_utc) * coalesce(c.seats, t.seats_max, 0))::int,
         count(distinct ro.dest_code)::int
    from public.rotations r
    join public.routes ro on ro.id = r.route_id
    join public.flight_legs l on l.rotation_id = r.id
    left join public.aircraft a on a.id = l.aircraft_id
    left join public.cabin_configs c on c.id = a.cabin_config_id
    left join public.aircraft_types t on t.id = a.aircraft_type_id
   where r.world_id = p_world_id and (r.launched_on is null or r.launched_on <= p_day)
   group by r.airline_id
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

-- private.job_cleanup(p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.job_cleanup(p_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_at timestamptz := coalesce(p_at, now()); v_cut timestamptz := coalesce(p_at, now()) - interval '14 days'; w record;
  t0 timestamptz; n_raw int; v_on boolean; n_old bigint; n_tied bigint; n_paid bigint; n_del int; v_status text;
  v_note text; v_details jsonb; v_out jsonb := '[]'::jsonb;
begin
  perform set_config('equinox.actor', 'job', true), set_config('equinox.actor_detail', 'cleanup', true);
  for w in select x.id from public.worlds x
            where exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                           where a.world_id = x.id and a.active and g.kind = 'ours')
               or exists (select 1 from public.game_capture_raw r where r.world_id = x.id)
            order by x.id loop
    t0 := clock_timestamp(); n_del := 0; v_status := 'ok';
    begin
      delete from public.game_capture_raw r where r.world_id = w.id and r.captured_at < v_cut;
      get diagnostics n_raw = row_count;

      v_on := coalesce((select (s.value #>> '{}')::boolean from public.settings s
                         where s.world_id = w.id and s.airline_id is null and s.key = 'statement_cleanup_enabled'), false);
      select count(*), count(*) filter (where s.flight_id is not null),
             count(*) filter (where s.flight_id is null
                                and exists (select 1 from public.game_payments p
                                             where p.airline_id = s.airline_id and p.paid_at = s.ts and p.descr = s.descr
                                               and p.amount = s.amount and p.occ = s.occ))
        into n_old, n_tied, n_paid
        from public.game_statement s
       where s.world_id = w.id and s.ts < v_cut;
      if not v_on then
        v_note := format('statement lines: switched off (settings.statement_cleanup_enabled), %s older than 14 days kept', n_old);
      elsif n_old = 0 then
        v_note := 'statement lines: none older than 14 days';
      elsif n_old <> n_tied + n_paid then
        v_status := 'failed';
        v_note := format('statement lines: %s of the %s older than 14 days aren''t in game_flights or game_payments, so none were deleted',
                         n_old - n_tied - n_paid, n_old);
      else
        delete from public.game_statement s
         where s.world_id = w.id and s.ts < v_cut
           and (s.flight_id is not null
                or exists (select 1 from public.game_payments p
                            where p.airline_id = s.airline_id and p.paid_at = s.ts and p.descr = s.descr
                              and p.amount = s.amount and p.occ = s.occ));
        get diagnostics n_del = row_count;
        v_note := format('statement lines: %s deleted (older than 14 days; %s in game_flights, %s in game_payments)', n_del, n_tied, n_paid);
      end if;
      v_note := format('raw pages: %s deleted (older than 14 days); ', n_raw) || v_note;
      v_details := jsonb_build_object('before', v_cut, 'raw_deleted', n_raw, 'statement_enabled', v_on,
                                      'statement_old', n_old, 'statement_in_flights', n_tied, 'statement_in_payments', n_paid,
                                      'statement_deleted', n_del);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('cleanup', w.id, t0, clock_timestamp(), v_status, private.capture_day(w.id, v_at), v_note, v_details);
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', v_status, 'note', v_note) || v_details;
    exception when others then
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('cleanup', w.id, t0, clock_timestamp(), 'failed', private.capture_day(w.id, v_at), 'clean-up: ' || sqlerrm,
              jsonb_build_object('before', v_cut, 'sqlstate', sqlstate));
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', 'failed', 'note', sqlerrm);
    end;
  end loop;
  return v_out;
end
$function$
;

-- private.job_run_add(p_job text, p_world_id bigint, p_started_at timestamp with time zone, p_status text, p_note text, p_details jsonb)
CREATE OR REPLACE FUNCTION private.job_run_add(p_job text, p_world_id bigint, p_started_at timestamp with time zone, p_status text, p_note text, p_details jsonb)
 RETURNS bigint
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
  values (p_job, p_world_id, p_started_at, clock_timestamp(), p_status,
          case when p_world_id is not null then private.capture_day(p_world_id, p_started_at) end, p_note, p_details)
  returning id
$function$

;

-- private.job_snapshot_fallback(p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.job_snapshot_fallback(p_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_at timestamptz := coalesce(p_at, now()); w record; t0 timestamptz; v_last date; v_first date; d date;
  v_moment timestamptz; v_snap jsonb; n int; v_filled date[]; v_taken boolean; v_complete boolean; v_airlines int;
  v_routes int; v_earlier int; v_had text; v_note text; v_details jsonb; v_out jsonb := '[]'::jsonb;
begin
  perform set_config('equinox.actor', 'job', true), set_config('equinox.actor_detail', 'snapshot_fallback', true);
  for w in select x.id from public.worlds x
            where exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                           where a.world_id = x.id and a.active and g.kind = 'ours')
            order by x.id loop
    t0 := clock_timestamp(); v_filled := '{}'; v_taken := false; v_complete := null; v_airlines := 0; v_routes := 0;
    v_earlier := 0; v_last := null;
    begin
      v_last := private.capture_day(w.id, v_at) - 1;
      select min(ad.day) into v_first from public.airline_days ad where ad.world_id = w.id;
      v_first := least(coalesce(v_first, v_last), v_last);
      select string_agg(distinct ad.source, ', ') into v_had from public.airline_days ad where ad.world_id = w.id and ad.day = v_last;
      for d in select g::date from generate_series(v_first, v_last, interval '1 day') g
                where not exists (select 1 from public.airline_days ad where ad.world_id = w.id and ad.day = g::date)
                order by 1 loop
        -- the snapshot stands for the end of that capture day (or now, for a run before the day ends)
        v_moment := least(private.capture_day_start(w.id, d + 1), v_at);
        v_snap := private.take_snapshot(w.id, d, v_moment, 'fallback');
        update public.airline_days ad
           set cash = b.amount, cash_at = b.captured_at,
               fixed_next7 = (select sum(e.debit) from public.game_events e
                               where e.airline_id = ad.airline_id and e.debit > 0 and e.due_at > b.captured_at
                                 and e.due_at <= b.captured_at + interval '7 days')
          from (select distinct on (x.airline_id) x.airline_id, x.amount, x.captured_at
                  from public.game_balance x
                 where x.world_id = w.id and x.account like '2800%' and x.amount is not null and x.captured_at <= v_moment
                 order by x.airline_id, x.captured_at desc) b
         where ad.world_id = w.id and ad.day = d and ad.source = 'fallback' and ad.cash is null and b.airline_id = ad.airline_id;
        get diagnostics n = row_count;
        if d = v_last then
          v_taken := true; v_complete := (v_snap ->> 'complete')::boolean; v_airlines := (v_snap ->> 'airlines')::int;
          v_routes := coalesce((v_snap ->> 'route_days')::int, 0); v_earlier := n;
        else
          v_filled := v_filled || d;
        end if;
      end loop;
      v_note := case when v_taken
                     then format('%s: no complete capture, so the fallback took the snapshot (%s airline(s)%s%s)',
                                 to_char(v_last, 'DD Mon'), v_airlines,
                                 case when v_complete then '; the capture was complete' else '; capture incomplete' end,
                                 case when v_earlier > 0 then format('; cash from an earlier balance for %s', v_earlier) else '' end)
                     else format('%s: the snapshot was already there (%s)', to_char(v_last, 'DD Mon'),
                                 case v_had when 'capture' then 'taken by the capture' when 'fallback' then 'taken by an earlier run'
                                            else coalesce(v_had, 'none') end) end
                || case when cardinality(v_filled) > 0
                        then format('; filled %s missed day(s): %s', cardinality(v_filled),
                                    (select string_agg(to_char(x, 'DD Mon'), ', ' order by x) from unnest(v_filled) x))
                        else '' end;
      v_details := jsonb_build_object('day', v_last, 'taken', v_taken, 'complete', v_complete, 'airlines', v_airlines,
                                      'route_days', v_routes, 'cash_from_earlier_balance', v_earlier,
                                      'filled', to_jsonb(v_filled), 'at', v_at);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot_fallback', w.id, t0, clock_timestamp(), 'ok', v_last, v_note, v_details);
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', 'ok', 'note', v_note) || v_details;
    exception when others then
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot_fallback', w.id, t0, clock_timestamp(), 'failed', v_last, 'snapshot fallback: ' || sqlerrm,
              jsonb_build_object('at', v_at, 'sqlstate', sqlstate));
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', 'failed', 'note', sqlerrm);
    end;
  end loop;
  return v_out;
end
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
           (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = coalesce(nullif(m.tv ->> 'type', ''), m.dv ->> 'type') order by ty.id limit 1) as type_id,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.tv ->> 'config' order by cc.id limit 1) as config_id,
           (select a.code from public.airports a where a.code = case when m.tv is not null then m.tv ->> 'base' else m.dv ->> 'base' end) as base,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.dv ->> 'config' order by cc.id limit 1) as order_config_id,
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
           -- the getter's done for a captured day: the one rule (public.loads_day_captured)
           public.loads_day_captured(w, d.day) as complete
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
       and not (private.planner_ref_blank('ref.types', t ->> 'name')
                and exists (select 1 from public.aircraft_types y where y.world_id = w and y.name = t ->> 'name'))
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
  on conflict (world_id, name) where name not in ('New type', '')
  do update set family_no = excluded.family_no, seats_max = excluded.seats_max,
    cruise_kmh = excluded.cruise_kmh, min_turn_min = excluded.min_turn_min, gap_target_h = excluded.gap_target_h,
    maint_per_hour = excluded.maint_per_hour, maint_per_cycle = excluded.maint_per_cycle,
    ground_keep_min = excluded.ground_keep_min, price = excluded.price
  where (x.family_no, x.seats_max, x.cruise_kmh, x.min_turn_min, x.gap_target_h, x.maint_per_hour, x.maint_per_cycle,
         x.ground_keep_min, x.price)
        is distinct from (excluded.family_no, excluded.seats_max, excluded.cruise_kmh, excluded.min_turn_min,
                          excluded.gap_target_h, excluded.maint_per_hour, excluded.maint_per_cycle,
                          excluded.ground_keep_min, excluded.price);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft_types', n);

  -- cabin layouts (ref.configs), the cabin as typed
  with src as (
    select distinct on (t ->> 'code') t, e.ord
      from jsonb_array_elements(case when jsonb_typeof(r -> 'configs') = 'array' then r -> 'configs' else '[]'::jsonb end) with ordinality as e(t, ord)
     where jsonb_typeof(t) = 'object' and coalesce(t ->> 'code', '') <> ''
       and not (private.planner_ref_blank('ref.configs', t ->> 'code')
                and exists (select 1 from public.cabin_configs y where y.world_id = w and y.code = t ->> 'code'))
     order by t ->> 'code', e.ord)
  insert into public.cabin_configs as x (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats, cost, note)
  select w, t ->> 'code', (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = t ->> 'type' order by ty.id limit 1),
         t ->> 'cabin',
         private.json_int(t -> 'seats'), private.json_int(t -> 'c'), private.json_int(t -> 'y'),
         (select v * 1000000 from private.json_num(t -> 'costM') v where abs(v) < 1000000), t ->> 'note'
    from src order by src.ord
  on conflict (world_id, code) where code not in ('NEW', '')
  do update set aircraft_type_id = excluded.aircraft_type_id, cabin = excluded.cabin,
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
         (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = src.v ->> 'aircraft' order by ty.id limit 1),
         (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = src.v ->> 'config' order by cc.id limit 1),
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
       and not (private.planner_ref_blank('ref.services', t ->> 'code')
                and exists (select 1 from public.service_profiles y where y.world_id = w and y.code = t ->> 'code'))
     order by t ->> 'code', e.ord)
  insert into public.service_profiles as x (world_id, airline_id, code, up_to_km, note)
  select w, (select al.id from public.airlines al where al.world_id = w and al.planner_name = t ->> 'airline'),
         t ->> 'code', private.json_int(t -> 'upTo'), t ->> 'note'
    from src order by src.ord
  on conflict (world_id, code) where code not in ('S5', '')
  do update set airline_id = excluded.airline_id, up_to_km = excluded.up_to_km, note = excluded.note
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

  -- ---- interline, keyed "Airline|country": the planner's "requested" is to_sign; a record with no status (the
  -- planner's "not contacted") has none
  with src as (
    select al.id as airline_id, substr(e.key, strpos(e.key, '|') + 1) as cc, e.value as v
      from jsonb_each(case when jsonb_typeof(s -> 'interline') = 'object' then s -> 'interline' else '{}'::jsonb end) e
      join public.airlines al on al.world_id = w and al.planner_name = split_part(e.key, '|', 1)
     where jsonb_typeof(e.value) = 'object' and exists (select 1 from public.countries c where c.code = substr(e.key, strpos(e.key, '|') + 1)))
  insert into public.interline_agreements as x (world_id, airline_id, country_code, status, partner, decided_on, note)
  select w, src.airline_id, src.cc,
         case when src.v ->> 'status' in ('signed', 'declined', 'nopartner') then src.v ->> 'status'
              when src.v ->> 'status' is not null then 'to_sign' end,
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

-- private.loads_mirror_days(p_world_id bigint, p_days jsonb, p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.loads_mirror_days(p_world_id bigint, p_days jsonb, p_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int; m int;
begin
  if jsonb_typeof(p_days) is distinct from 'object' or p_days = '{}'::jsonb then
    return jsonb_build_object('load_entries', 0, 'load_days', 0);
  end if;
  if to_regclass('pg_temp.t_lm_days') is null then
    create temporary table t_lm_days (day date primary key, v jsonb, got jsonb) on commit drop;
  end if;
  truncate pg_temp.t_lm_days;
  insert into pg_temp.t_lm_days (day, v)
  select private.json_date(to_jsonb(e.key)), e.value from jsonb_each(p_days) e
   where private.json_date(to_jsonb(e.key)) is not null and jsonb_typeof(e.value) = 'object'
  on conflict (day) do nothing;
  update pg_temp.t_lm_days t set got = g.v
    from (select d.key::date as day, d.value as v
            from public.planner_loads_get(w) pl cross join lateral jsonb_each(pl.json::jsonb) d
           where pl.month in (select distinct to_char(x.day, 'YYYY-MM') from pg_temp.t_lm_days x)) g
   where g.day = t.day;

  with ours as (
    select a.id, a.planner_name from public.airlines a
      join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = w and g.kind = 'ours'),
  tf as (select t.day, f.key, f.value from pg_temp.t_lm_days t
           cross join lateral jsonb_each(case when jsonb_typeof(t.v -> 'f') = 'object' then t.v -> 'f' else '{}'::jsonb end) f),
  gf as (select t.day, f.key, f.value from pg_temp.t_lm_days t
           cross join lateral jsonb_each(case when jsonb_typeof(t.got -> 'f') = 'object' then t.got -> 'f' else '{}'::jsonb end) f),
  fd as (select coalesce(tf.day, gf.day) as day, coalesce(tf.key, gf.key) as k, tf.value as tv
           from tf full join gf on gf.day = tf.day and gf.key = tf.key
          where tf.value is distinct from gf.value)
  insert into public.load_entries as x (world_id, airline_id, game_date, flight_no, eco_pct, entered_at)
  select w, o.id, fd.day, private.json_int(to_jsonb(split_part(fd.k, '|', 2))),
         (select v from private.json_num(fd.tv) v where abs(v) < 10000), p_at
    from fd join ours o on o.planner_name = split_part(fd.k, '|', 1)
   where private.json_int(to_jsonb(split_part(fd.k, '|', 2))) between 0 and 2000000000
  on conflict (airline_id, game_date, flight_no) do update set eco_pct = excluded.eco_pct, entered_at = excluded.entered_at
  where (x.eco_pct, x.entered_at) is distinct from (excluded.eco_pct, excluded.entered_at);
  get diagnostics n = row_count;

  -- a day whose flags the getter shows differently: stamped again even when the row already says the same, since a
  -- capture since then is what makes the getter differ (it counts the day complete once every airline has flown it,
  -- while the capture's loads step waits for all of the capture day's pages)
  insert into public.load_days as x (world_id, game_date, done, saved_at_ms, entered_at)
  select w, t.day, coalesce(t.v -> 'done' = 'true'::jsonb, false), private.json_int(t.v -> 'savedAt'), p_at
    from pg_temp.t_lm_days t
   where coalesce(t.v -> 'done', 'false'::jsonb) is distinct from coalesce(t.got -> 'done', 'false'::jsonb)
      or (t.v -> 'savedAt') is distinct from (t.got -> 'savedAt')
  on conflict (world_id, game_date) do update set done = excluded.done, saved_at_ms = excluded.saved_at_ms,
    entered_at = excluded.entered_at
  where (x.done, x.saved_at_ms, x.entered_at) is distinct from (excluded.done, excluded.saved_at_ms, excluded.entered_at);
  get diagnostics m = row_count;
  return jsonb_build_object('load_entries', n, 'load_days', m);
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

-- private.planner_apply(p_world_id bigint, p_doc jsonb, p_mode text, p_base timestamp with time zone, p_client text, p_actor text, p_detail text)
CREATE OR REPLACE FUNCTION private.planner_apply(p_world_id bigint, p_doc jsonb, p_mode text, p_base timestamp with time zone, p_client text, p_actor text, p_detail text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; v_cur jsonb; v_doc jsonb; v_rows jsonb := '{}'::jsonb; v_applied int; v_skipped int;
  v_skipped_items jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if p_mode not in ('save', 'mirror', 'item') then raise exception 'planner_apply: unknown mode %', p_mode; end if;
  if jsonb_typeof(p_doc) is distinct from 'object' then raise exception 'planner_apply: the document isn''t a JSON object'; end if;
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  v_cur := (public.planner_state_get(w) ->> 'json')::jsonb;

  if to_regclass('pg_temp.t_pa') is null then
    create temporary table t_pa (section text, key text, grp text, new_pos int, cur_pos int, new_item jsonb,
      cur_item jsonb, state text, eff_item jsonb, primary key (section, key)) on commit drop;
  end if;
  truncate pg_temp.t_pa;
  -- eff_item: the document's item, or the tables' where the document has none of an unchanged item (an item that is
  -- skipped below keeps the tables')
  insert into pg_temp.t_pa (section, key, grp, new_pos, cur_pos, new_item, cur_item, state, eff_item)
  select coalesce(n.section, c.section), coalesce(n.key, c.key), coalesce(n.grp, c.grp), n.pos, c.pos, n.item, c.item,
         case when n.item is null or c.item is null then 'changed'
              when n.item = c.item then 'same'
              when exists (select 1 from private.planner_json_diff(n.item, c.item,
                             case when n.section = 'tails' then '$.tails[' || n.pos || ']' else '$' end) d
                            where d.kind = 'differs') then 'changed'
              else 'same' end,
         n.item
    from private.planner_items(p_doc) n
    full join private.planner_items(v_cur) c on c.section = n.section and c.key = n.key;

  if p_mode = 'save' then
    update pg_temp.t_pa p set state = 'skipped', eff_item = p.cur_item
      from (select distinct t.section, t.key from private.planner_touched(w, coalesce(p_base, now()), p_client) t) t
     where p.state = 'changed' and p.section = t.section and p.grp = t.key;
  end if;
  select count(*) filter (where state = 'changed'), count(*) filter (where state = 'skipped'),
         coalesce(jsonb_agg(section || ' ' || key order by section, key) filter (where state = 'skipped'), '[]'::jsonb)
    into v_applied, v_skipped, v_skipped_items
    from pg_temp.t_pa;
  if v_applied = 0 then
    return jsonb_build_object('applied', 0, 'skipped', v_skipped, 'skipped_items', v_skipped_items, 'rows', v_rows, 'doc', v_cur);
  end if;

  if p_actor is not null then
    perform set_config('equinox.actor', p_actor, true), set_config('equinox.actor_detail', coalesce(p_detail, ''), true);
  end if;
  v_rows := v_rows || private.planner_apply_places(w);
  v_rows := v_rows || private.planner_apply_reference(w);
  v_rows := v_rows || private.planner_apply_routes(w);
  v_rows := v_rows || private.planner_apply_fleet(w);
  v_rows := v_rows || private.planner_apply_flights(w);
  v_rows := v_rows || private.planner_apply_work(w, v_skipped = 0);
  v_rows := v_rows || private.planner_apply_money(w);
  v_rows := v_rows || private.planner_apply_tidy(w);
  v_doc := private.planner_apply_extra(w);
  if p_actor is not null then
    perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  end if;
  return jsonb_build_object('applied', v_applied, 'skipped', v_skipped, 'skipped_items', v_skipped_items,
                            'rows', (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(v_rows) e where e.value <> '0'::jsonb),
                            'doc', v_doc);
end
$function$

;

-- private.planner_apply_extra(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_extra(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; g jsonb; n int;
begin
  g := (public.planner_state_get(w) ->> 'json')::jsonb;
  if not exists (select 1 from pg_temp.t_pa where state = 'changed' and new_item is not null
                    and section in ('tails', 'deliveries', 'freqs', 'plans', 'todos', 'farePlan')) then
    return g;
  end if;
  if to_regclass('pg_temp.t_pa_patch') is null then
    create temporary table t_pa_patch (section text, item_key text, key text, value jsonb) on commit drop;
  end if;
  truncate pg_temp.t_pa_patch;
  with written as (
    select p.section, p.key, p.new_item,
           case when p.section = 'plans' then '$.plans.' || p.key else '$.' || p.section || '[' || p.new_pos || ']' end as prefix
      from pg_temp.t_pa p
     where p.state = 'changed' and p.new_item is not null and p.section in ('tails', 'deliveries', 'freqs', 'plans', 'todos', 'farePlan')),
  built as (select b.section, b.key, b.item from private.planner_items(g) b
             where b.section in ('tails', 'deliveries', 'freqs', 'plans', 'todos', 'farePlan')),
  keys as (
    select distinct x.section, x.key, x.new_item, (regexp_match(substr(df.path, length(x.prefix) + 2), '^([^.\[]+)'))[1] as k
      from written x join built b on b.section = x.section and b.key = x.key
      cross join lateral private.planner_json_diff(x.new_item, b.item, x.prefix) df
     where df.kind = 'differs' and length(df.path) > length(x.prefix))
  insert into pg_temp.t_pa_patch
  select k.section, k.key, k.k, coalesce(k.new_item -> k.k, 'null'::jsonb) from keys k where k.k is not null;
  get diagnostics n = row_count;
  if n = 0 then return g; end if;
  update public.rotations r set extra = r.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'freqs' group by item_key) p
   where r.world_id = w and r.legacy_key = p.item_key and (r.extra || p.patch) is distinct from r.extra;
  update public.todos t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'todos' group by item_key) p
   where t.world_id = w and t.legacy_key = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.fare_plan t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'farePlan' group by item_key) p
   where t.world_id = w and t.legacy_key = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.plan_cards t set extra = t.extra || p.patch
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'plans' group by item_key) p,
         public.aircraft a
   where t.world_id = w and a.id = t.aircraft_id and a.registration = p.item_key and (t.extra || p.patch) is distinct from t.extra;
  update public.aircraft a set extra = jsonb_set(a.extra, '{tail}', coalesce(a.extra -> 'tail', '{}'::jsonb) || p.patch)
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'tails' group by item_key) p
   where a.world_id = w and a.registration = p.item_key and (coalesce(a.extra -> 'tail', '{}'::jsonb) || p.patch) is distinct from a.extra -> 'tail';
  update public.aircraft a set extra = jsonb_set(a.extra, '{delivery}', coalesce(a.extra -> 'delivery', '{}'::jsonb) || p.patch)
    from (select item_key, jsonb_object_agg(key, value) as patch from pg_temp.t_pa_patch where section = 'deliveries' group by item_key) p
   where a.world_id = w and a.registration = p.item_key and (coalesce(a.extra -> 'delivery', '{}'::jsonb) || p.patch) is distinct from a.extra -> 'delivery';
  return (public.planner_state_get(w) ->> 'json')::jsonb;
end
$function$

;

-- private.planner_apply_fleet(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_fleet(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
  k_tail text[] := array['id', 'airline', 'base', 'type', 'config', 'status', 'maint', 'checkedOn', 'schedChangedOn'];
  k_delivery text[] := array['reg', 'airline', 'utc', 'date', 'base', 'type', 'config', 'plan'];
begin
  if not exists (select 1 from pg_temp.t_pa where section in ('tails', 'deliveries') and state = 'changed') then return v_out; end if;
  with regs as (select distinct p.key as reg from pg_temp.t_pa p where p.section in ('tails', 'deliveries') and p.state = 'changed'),
  m as (
    select r.reg, t.eff_item as tv, d.eff_item as dv,
           case when t.state <> 'skipped' then t.new_pos end as ti,
           case when d.state <> 'skipped' then d.new_pos end as di,
           (select al.id from public.airlines al where al.world_id = w and al.planner_name = coalesce(t.eff_item ->> 'airline', d.eff_item ->> 'airline')) as airline_id,
           private.json_ts(d.eff_item -> 'utc') as delivery_at
      from regs r
      left join pg_temp.t_pa t on t.section = 'tails' and t.key = r.reg
      left join pg_temp.t_pa d on d.section = 'deliveries' and d.key = r.reg),
  src as (
    select m.*, old.extra as old_extra,
           (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = coalesce(nullif(m.tv ->> 'type', ''), m.dv ->> 'type') order by ty.id limit 1) as type_id,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.tv ->> 'config' order by cc.id limit 1) as config_id,
           (select a.code from public.airports a where a.code = case when m.tv is not null then m.tv ->> 'base' else m.dv ->> 'base' end) as base,
           (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = m.dv ->> 'config' order by cc.id limit 1) as order_config_id,
           (select a.code from public.airports a where a.code = m.dv ->> 'base') as order_base
      from m left join public.aircraft old on old.world_id = w and old.registration = m.reg
     where m.airline_id is not null and (m.tv is not null or m.dv is not null))
  insert into public.aircraft as x (world_id, airline_id, registration, aircraft_type_id, cabin_config_id, base_code, status,
                                    ordered_on, delivery_at, order_base_code, order_config_id, order_note, checked_on,
                                    schedule_changed_on, maintenance_note, extra)
  select w, src.airline_id, src.reg, src.type_id, src.config_id, src.base,
         case when src.tv is not null then 'active' when src.delivery_at <= now() then 'delivered' else 'on_order' end,
         private.json_date(src.dv -> 'date'), src.delivery_at, src.order_base, src.order_config_id, src.dv ->> 'plan',
         private.json_date(src.tv -> 'checkedOn'), private.json_date(src.tv -> 'schedChangedOn'), src.tv ->> 'maint',
         jsonb_strip_nulls(jsonb_build_object(
           'tails_index', case when src.tv is not null then coalesce(src.ti, (src.old_extra ->> 'tails_index')::int) end,
           'deliveries_index', case when src.dv is not null then coalesce(src.di, (src.old_extra ->> 'deliveries_index')::int) end,
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

  -- the others keep their place in each list (it moves when an item before them goes)
  update public.aircraft a set extra = jsonb_set(a.extra, '{tails_index}', to_jsonb(p.new_pos))
    from pg_temp.t_pa p
   where p.section = 'tails' and p.state = 'same' and a.world_id = w and a.registration = p.key
     and a.extra ? 'tails_index' and (a.extra -> 'tails_index') is distinct from to_jsonb(p.new_pos);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('tails moved', n);
  update public.aircraft a set extra = jsonb_set(a.extra, '{deliveries_index}', to_jsonb(p.new_pos))
    from pg_temp.t_pa p
   where p.section = 'deliveries' and p.state = 'same' and a.world_id = w and a.registration = p.key
     and a.extra ? 'deliveries_index' and (a.extra -> 'deliveries_index') is distinct from to_jsonb(p.new_pos);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('deliveries moved', n);
  return v_out;
end
$function$

;

-- private.planner_apply_flights(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_flights(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
  k_freq text[] := array['id', 'routeKey', 'days', 'tail', 'noOut', 'noBack', 'depHub', 'arrDest', 'depDest', 'arrHub',
                         'service', 'price', 'launched', 'notes'];
  k_plan text[] := array['base', 'title', 'note', 'legs'];
begin
  -- ---- frequencies
  if exists (select 1 from pg_temp.t_pa where section = 'freqs' and state = 'changed') then
    delete from public.rotations r using pg_temp.t_pa p
     where p.section = 'freqs' and p.state = 'changed' and p.new_item is null and r.world_id = w and r.legacy_key = p.key;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('rotations removed', n);

    if to_regclass('pg_temp.t_pa_freqs') is null then
      create temporary table t_pa_freqs (
        legacy_key text primary key, ord bigint, v jsonb, airline_id bigint, route_id bigint, hub text, dest text,
        aircraft_id bigint, old_extra jsonb, l1_days smallint[], l1_dep smallint, l1_block smallint, l2_days smallint[],
        l2_dep smallint, l2_block smallint) on commit drop;
    end if;
    truncate pg_temp.t_pa_freqs;
    insert into pg_temp.t_pa_freqs
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
            select f.key as k, f.new_pos as ord, f.new_item as v, al.id as airline_id, ro.id as route_id, ro.hub_code, ro.dest_code,
                   ac.id as aircraft_id, old.extra as old_extra,
                   coalesce(private.weekday_set(f.new_item ->> 'days'), '{1,2,3,4,5,6,7}') as days_local,
                   t.dep_h, t.arr_d, t.dep_d, t.arr_h, o.oh, o.od,
                   case when t.dep_h is not null and t.arr_d is not null
                        then ((t.arr_d - t.dep_h - (o.od - o.oh)) % 1440 + 1440) % 1440 end as out_block
              from pg_temp.t_pa f
              join public.airlines al on al.world_id = w and al.planner_name = split_part(f.new_item ->> 'routeKey', '|', 1)
              join public.routes ro on ro.airline_id = al.id and ro.hub_code = split_part(f.new_item ->> 'routeKey', '|', 2)
                                   and ro.dest_code = split_part(f.new_item ->> 'routeKey', '|', 3)
              left join public.aircraft ac on ac.world_id = w and ac.registration = f.new_item ->> 'tail'
              left join public.rotations old on old.world_id = w and old.legacy_key = f.key
              left join public.airports ah on ah.code = ro.hub_code
              left join public.world_airports wh on wh.world_id = w and wh.airport_code = ro.hub_code
              left join public.airports ad on ad.code = ro.dest_code
              left join public.world_airports wd on wd.world_id = w and wd.airport_code = ro.dest_code
              -- each end's offset in minutes; an airport whose offset isn't known counts as UTC, as the planner counts it
              cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                                         round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
              cross join lateral (select private.clock_min(f.new_item ->> 'depHub') as dep_h, private.clock_min(f.new_item ->> 'arrDest') as arr_d,
                                         private.clock_min(f.new_item ->> 'depDest') as dep_d, private.clock_min(f.new_item ->> 'arrHub') as arr_h) t
             where f.section = 'freqs' and f.state = 'changed' and f.new_item is not null
            ) x) y;

    -- a rotation moving to another route takes its legs with it: they are written again below
    delete from public.flight_legs l using public.rotations r, pg_temp.t_pa_freqs f
     where l.rotation_id = r.id and r.world_id = w and r.legacy_key = f.legacy_key and r.route_id <> f.route_id;
    insert into public.rotations as x (world_id, airline_id, route_id, legacy_key, service_code, fare_pct, launched_on, note, extra)
    select w, f.airline_id, f.route_id, f.legacy_key, f.v ->> 'service',
           (select v from private.json_num(f.v -> 'price') v where abs(v) < 10000), private.json_date(f.v -> 'launched'),
           f.v ->> 'notes', private.planner_extra(f.v, k_freq, f.old_extra)
      from pg_temp.t_pa_freqs f order by f.ord
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
      from pg_temp.t_pa_freqs f
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
  end if;

  -- ---- plan cards (keyed by registration) and their legs
  if exists (select 1 from pg_temp.t_pa where section = 'plans' and state = 'changed') then
    delete from public.plan_cards c using pg_temp.t_pa p, public.aircraft a
     where p.section = 'plans' and p.state = 'changed' and p.new_item is null
       and a.world_id = w and a.registration = p.key and c.aircraft_id = a.id;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_cards removed', n);
    insert into public.plan_cards as x (world_id, airline_id, aircraft_id, base_code, title, note, extra)
    select w, a.airline_id, a.id, (select ap.code from public.airports ap where ap.code = p.new_item ->> 'base'),
           p.new_item ->> 'title', p.new_item ->> 'note', private.planner_extra(p.new_item, k_plan, old.extra)
      from pg_temp.t_pa p
      join public.aircraft a on a.world_id = w and a.registration = p.key
      left join public.plan_cards old on old.aircraft_id = a.id
     where p.section = 'plans' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object'
     order by p.key
    on conflict (aircraft_id) do update set airline_id = excluded.airline_id, base_code = excluded.base_code,
      title = excluded.title, note = excluded.note, extra = excluded.extra
    where (x.airline_id, x.base_code, x.title, x.note, x.extra)
          is distinct from (excluded.airline_id, excluded.base_code, excluded.title, excluded.note, excluded.extra);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('plan_cards', n);
    with src as (
      select c.id as plan_card_id, (e.ord)::int as position, l,
             (select ap.code from public.airports ap where ap.code = l ->> 'from') as origin,
             (select ap.code from public.airports ap where ap.code = l ->> 'to') as dest
        from pg_temp.t_pa p
        join public.aircraft a on a.world_id = w and a.registration = p.key
        join public.plan_cards c on c.aircraft_id = a.id
        cross join lateral jsonb_array_elements(case when jsonb_typeof(p.new_item -> 'legs') = 'array' then p.new_item -> 'legs' else '[]'::jsonb end) with ordinality as e(l, ord)
       where p.section = 'plans' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object' and jsonb_typeof(l) = 'object'),
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
    delete from public.plan_card_legs x using pg_temp.t_pa p, public.aircraft a, public.plan_cards c
     where p.section = 'plans' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object'
       and a.world_id = w and a.registration = p.key and c.aircraft_id = a.id and x.plan_card_id = c.id
       and x.position > coalesce(jsonb_array_length(case when jsonb_typeof(p.new_item -> 'legs') = 'array' then p.new_item -> 'legs' end), 0);
  end if;
  return v_out;
end
$function$

;

-- private.planner_apply_money(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_money(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int; m int;
begin
  if not exists (select 1 from pg_temp.t_pa where section in ('cash', 'fixed7') and state = 'changed') then return '{}'::jsonb; end if;
  if to_regclass('pg_temp.t_pa_cash') is null then
    create temporary table t_pa_cash (airline_id bigint, day date, cash numeric, fixed_next7 numeric,
                                      primary key (airline_id, day)) on commit drop;
  end if;
  truncate pg_temp.t_pa_cash;
  with pairs as (
    select distinct split_part(p.key, '|', 1) as day_key, substr(p.key, strpos(p.key, '|') + 1) as airline_name
      from pg_temp.t_pa p where p.section in ('cash', 'fixed7') and p.state = 'changed'),
  src as (
    select al.id as airline_id, private.json_date(to_jsonb(x.day_key)) as day,
           private.json_num((select q.eff_item from pg_temp.t_pa q where q.section = 'cash' and q.key = x.day_key || '|' || x.airline_name)) as st_cash,
           private.json_num((select q.eff_item from pg_temp.t_pa q where q.section = 'fixed7' and q.key = x.day_key || '|' || x.airline_name)) as st_fixed
      from pairs x join public.airlines al on al.world_id = w and al.planner_name = x.airline_name),
  cap as (
    select cc.airline_id, cc.day, floor(cc.cash / 10000 + 0.5) / 100 as cash_m,
           case when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as fixed_m
      from public.capture_cash cc where cc.world_id = w and cc.airline_id in (select airline_id from src))
  insert into pg_temp.t_pa_cash
  select s.airline_id, s.day,
         case when s.st_cash is not null and s.st_cash is distinct from c.cash_m and abs(s.st_cash) < 1000000 then round(s.st_cash * 1000000, 2) end,
         case when s.st_fixed is not null and s.st_fixed is distinct from c.fixed_m and abs(s.st_fixed) < 1000000 then round(s.st_fixed * 1000000, 2) end
    from src s left join cap c on c.airline_id = s.airline_id and c.day = s.day
   where s.day is not null;
  insert into public.cash_entries as x (world_id, airline_id, day, cash, fixed_next7, entered_at)
  select w, c.airline_id, c.day, c.cash, c.fixed_next7, now() from pg_temp.t_pa_cash c
   where c.cash is not null or c.fixed_next7 is not null
  on conflict (airline_id, day) do update set cash = excluded.cash, fixed_next7 = excluded.fixed_next7, entered_at = excluded.entered_at
  where (x.cash, x.fixed_next7) is distinct from (excluded.cash, excluded.fixed_next7);
  get diagnostics n = row_count;
  delete from public.cash_entries x using pg_temp.t_pa_cash c
   where x.airline_id = c.airline_id and x.day = c.day and c.cash is null and c.fixed_next7 is null;
  get diagnostics m = row_count;
  return jsonb_build_object('cash_entries', n, 'cash_entries removed', m);
end
$function$

;

-- private.planner_apply_places(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_places(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare n int; m int;
begin
  insert into public.airports (code)
  select distinct x.code from (
    select p.new_item ->> 'base' as code from pg_temp.t_pa p where p.section in ('tails', 'deliveries', 'plans') and p.state = 'changed'
    union all select p.new_item ->> i from pg_temp.t_pa p, generate_series(1, 2) i where p.section = 'routesAdded' and p.state = 'changed'
    union all select split_part(p.key, '|', i) from pg_temp.t_pa p, generate_series(2, 3) i
               where p.section in ('routesAdded', 'routeEdits', 'routeCabin') and p.state = 'changed'
    union all select split_part(p.new_item ->> 'routeKey', '|', i) from pg_temp.t_pa p, generate_series(2, 3) i
               where p.section in ('freqs', 'farePlan') and p.state = 'changed'
    union all select l ->> k from pg_temp.t_pa p
                cross join lateral jsonb_array_elements(case when jsonb_typeof(p.new_item -> 'legs') = 'array' then p.new_item -> 'legs' else '[]'::jsonb end) l
                cross join unnest(array['from', 'to']) k
               where p.section = 'plans' and p.state = 'changed'
    union all select p.new_item ->> 'code' from pg_temp.t_pa p where p.section = 'ref.hubs' and p.state = 'changed'
    union all select p.key from pg_temp.t_pa p where p.section in ('ref.curfews', 'ref.utcOverrides') and p.state = 'changed' and p.new_item is not null
  ) x
   where x.code ~ '^[A-Z0-9]{3,4}$'
  on conflict (code) do nothing;
  get diagnostics n = row_count;
  insert into public.countries (code, name)
  select distinct substr(p.key, strpos(p.key, '|') + 1), substr(p.key, strpos(p.key, '|') + 1)
    from pg_temp.t_pa p
   where p.section = 'interline' and p.state = 'changed' and p.new_item is not null and strpos(p.key, '|') > 0
     and substr(p.key, strpos(p.key, '|') + 1) <> ''
  on conflict (code) do nothing;
  get diagnostics m = row_count;
  return jsonb_build_object('airports', n, 'countries', m);
end
$function$

;

-- private.planner_apply_reference(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_reference(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb; v_mct jsonb;
begin
  if not exists (select 1 from pg_temp.t_pa where section like 'ref.%' and state = 'changed') then return v_out; end if;

  if exists (select 1 from pg_temp.t_pa where section in ('ref.types', 'ref.configs', 'ref.services') and state = 'changed') then
    -- each row's place in its list before this save
    if to_regclass('pg_temp.t_pa_ref') is null then
      create temporary table t_pa_ref (section text, pos int, id bigint, primary key (section, pos)) on commit drop;
    end if;
    if to_regclass('pg_temp.t_pa_ref_row') is null then
      create temporary table t_pa_ref_row (section text, key text, id bigint, primary key (section, key)) on commit drop;
    end if;
    truncate pg_temp.t_pa_ref, pg_temp.t_pa_ref_row;
    insert into pg_temp.t_pa_ref
    select 'ref.types', (row_number() over (order by t.id) - 1)::int, t.id from public.aircraft_types t where t.world_id = w
    union all select 'ref.configs', (row_number() over (order by c.id) - 1)::int, c.id from public.cabin_configs c where c.world_id = w
    union all select 'ref.services', (row_number() over (order by s.id) - 1)::int, s.id from public.service_profiles s where s.world_id = w;
    -- the row an entry is written to where its code alone doesn't say: a blank entry still at its place, and an entry
    -- renamed in place (into a blank code, or one no other row has)
    insert into pg_temp.t_pa_ref_row (section, key, id)
    select p.section, p.key, m.id
      from pg_temp.t_pa p join pg_temp.t_pa_ref m on m.section = p.section and m.pos = p.cur_pos
     where p.section in ('ref.types', 'ref.configs', 'ref.services') and p.state = 'changed'
       and p.new_item is not null and p.cur_item is not null and private.planner_ref_blank(p.section, p.grp)
    union all
    select a.section, a.key, m.id
      from pg_temp.t_pa r
      join pg_temp.t_pa a on a.section = r.section and a.new_pos = r.cur_pos and a.state = 'changed' and a.cur_item is null
                         and a.new_item is not null
      join pg_temp.t_pa_ref m on m.section = r.section and m.pos = r.cur_pos
     where r.section in ('ref.types', 'ref.configs', 'ref.services') and r.state = 'changed' and r.new_item is null
       and (private.planner_ref_blank(a.section, a.grp)
            or (not exists (select 1 from public.aircraft_types x where a.section = 'ref.types' and x.world_id = w and x.name = a.grp)
                and not exists (select 1 from public.cabin_configs x where a.section = 'ref.configs' and x.world_id = w and x.code = a.grp)
                and not exists (select 1 from public.service_profiles x where a.section = 'ref.services' and x.world_id = w and x.code = a.grp)));

    -- aircraft types (ref.types)
    with src as (
      select p.grp as name, p.new_pos, r.id, private.json_int(t -> 'family') as family_no, private.json_int(t -> 'seats') as seats_max,
             private.json_int(t -> 'cruise') as cruise_kmh,
             (select v::smallint from private.json_int(t -> 'minTurn') v where abs(v) < 32000) as min_turn_min,
             (select v from private.json_num(t -> 'gap') v where abs(v) < 1000) as gap_target_h,
             (select v from private.json_num(t -> 'mHour') v where abs(v) < 1000) as maint_per_hour,
             (select v from private.json_num(t -> 'mCycle') v where abs(v) < 1000) as maint_per_cycle,
             (select v::smallint from private.json_int(t -> 'greens') v where abs(v) < 32000) as ground_keep_min,
             (select v * 1000000 from private.json_num(t -> 'priceM') v where abs(v) < 1000000) as price
        from pg_temp.t_pa p cross join lateral (select p.new_item as t) i
        left join pg_temp.t_pa_ref_row r on r.section = p.section and r.key = p.key
       where p.section = 'ref.types' and p.state = 'changed' and p.new_item is not null),
    upd as (
      update public.aircraft_types x set name = s.name, family_no = s.family_no, seats_max = s.seats_max, cruise_kmh = s.cruise_kmh,
             min_turn_min = s.min_turn_min, gap_target_h = s.gap_target_h, maint_per_hour = s.maint_per_hour,
             maint_per_cycle = s.maint_per_cycle, ground_keep_min = s.ground_keep_min, price = s.price
        from src s
       where s.id is not null and x.id = s.id
         and (x.name, x.family_no, x.seats_max, x.cruise_kmh, x.min_turn_min, x.gap_target_h, x.maint_per_hour, x.maint_per_cycle,
              x.ground_keep_min, x.price)
             is distinct from (s.name, s.family_no, s.seats_max, s.cruise_kmh, s.min_turn_min, s.gap_target_h, s.maint_per_hour,
                               s.maint_per_cycle, s.ground_keep_min, s.price)
      returning 1),
    ins as (
      insert into public.aircraft_types as x (world_id, name, family_no, seats_max, cruise_kmh, min_turn_min, gap_target_h,
                                              maint_per_hour, maint_per_cycle, ground_keep_min, price)
      select w, s.name, s.family_no, s.seats_max, s.cruise_kmh, s.min_turn_min, s.gap_target_h, s.maint_per_hour, s.maint_per_cycle,
             s.ground_keep_min, s.price
        from src s where s.id is null order by s.new_pos
      on conflict (world_id, name) where name not in ('New type', '')
      do update set family_no = excluded.family_no, seats_max = excluded.seats_max,
        cruise_kmh = excluded.cruise_kmh, min_turn_min = excluded.min_turn_min, gap_target_h = excluded.gap_target_h,
        maint_per_hour = excluded.maint_per_hour, maint_per_cycle = excluded.maint_per_cycle,
        ground_keep_min = excluded.ground_keep_min, price = excluded.price
      where (x.family_no, x.seats_max, x.cruise_kmh, x.min_turn_min, x.gap_target_h, x.maint_per_hour, x.maint_per_cycle,
             x.ground_keep_min, x.price)
            is distinct from (excluded.family_no, excluded.seats_max, excluded.cruise_kmh, excluded.min_turn_min,
                              excluded.gap_target_h, excluded.maint_per_hour, excluded.maint_per_cycle,
                              excluded.ground_keep_min, excluded.price)
      returning 1)
    select (select count(*) from upd) + (select count(*) from ins) into n;
    v_out := v_out || jsonb_build_object('aircraft_types', n);

    -- cabin layouts (ref.configs), the cabin as typed
    with src as (
      select p.grp as code, p.new_pos, r.id,
             (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = t ->> 'type' order by ty.id limit 1) as type_id,
             t ->> 'cabin' as cabin, private.json_int(t -> 'seats') as seats, private.json_int(t -> 'c') as business_seats,
             private.json_int(t -> 'y') as economy_seats,
             (select v * 1000000 from private.json_num(t -> 'costM') v where abs(v) < 1000000) as cost, t ->> 'note' as note
        from pg_temp.t_pa p cross join lateral (select p.new_item as t) i
        left join pg_temp.t_pa_ref_row r on r.section = p.section and r.key = p.key
       where p.section = 'ref.configs' and p.state = 'changed' and p.new_item is not null),
    upd as (
      update public.cabin_configs x set code = s.code, aircraft_type_id = s.type_id, cabin = s.cabin, seats = s.seats,
             business_seats = s.business_seats, economy_seats = s.economy_seats, cost = s.cost, note = s.note
        from src s
       where s.id is not null and x.id = s.id
         and (x.code, x.aircraft_type_id, x.cabin, x.seats, x.business_seats, x.economy_seats, x.cost, x.note)
             is distinct from (s.code, s.type_id, s.cabin, s.seats, s.business_seats, s.economy_seats, s.cost, s.note)
      returning 1),
    ins as (
      insert into public.cabin_configs as x (world_id, code, aircraft_type_id, cabin, seats, business_seats, economy_seats, cost, note)
      select w, s.code, s.type_id, s.cabin, s.seats, s.business_seats, s.economy_seats, s.cost, s.note
        from src s where s.id is null order by s.new_pos
      on conflict (world_id, code) where code not in ('NEW', '')
      do update set aircraft_type_id = excluded.aircraft_type_id, cabin = excluded.cabin,
        seats = excluded.seats, business_seats = excluded.business_seats, economy_seats = excluded.economy_seats,
        cost = excluded.cost, note = excluded.note
      where (x.aircraft_type_id, x.cabin, x.seats, x.business_seats, x.economy_seats, x.cost, x.note)
            is distinct from (excluded.aircraft_type_id, excluded.cabin, excluded.seats, excluded.business_seats,
                              excluded.economy_seats, excluded.cost, excluded.note)
      returning 1)
    select (select count(*) from upd) + (select count(*) from ins) into n;
    v_out := v_out || jsonb_build_object('cabin_configs', n);

    -- on-board service (ref.services): "Legacy" means every airline without its own
    with src as (
      select p.grp as code, p.new_pos, r.id,
             (select al.id from public.airlines al where al.world_id = w and al.planner_name = t ->> 'airline') as airline_id,
             private.json_int(t -> 'upTo') as up_to_km, t ->> 'note' as note
        from pg_temp.t_pa p cross join lateral (select p.new_item as t) i
        left join pg_temp.t_pa_ref_row r on r.section = p.section and r.key = p.key
       where p.section = 'ref.services' and p.state = 'changed' and p.new_item is not null),
    upd as (
      update public.service_profiles x set code = s.code, airline_id = s.airline_id, up_to_km = s.up_to_km, note = s.note
        from src s
       where s.id is not null and x.id = s.id
         and (x.code, x.airline_id, x.up_to_km, x.note) is distinct from (s.code, s.airline_id, s.up_to_km, s.note)
      returning 1),
    ins as (
      insert into public.service_profiles as x (world_id, airline_id, code, up_to_km, note)
      select w, s.airline_id, s.code, s.up_to_km, s.note from src s where s.id is null order by s.new_pos
      on conflict (world_id, code) where code not in ('S5', '')
      do update set airline_id = excluded.airline_id, up_to_km = excluded.up_to_km, note = excluded.note
      where (x.airline_id, x.up_to_km, x.note) is distinct from (excluded.airline_id, excluded.up_to_km, excluded.note)
      returning 1)
    select (select count(*) from upd) + (select count(*) from ins) into n;
    v_out := v_out || jsonb_build_object('service_profiles', n);
  end if;

  -- markets (ref.markets, keyed "Airline|Market")
  insert into public.markets as x (world_id, airline_id, name, default_type_id, default_config_id, fare_y_pct, fare_j_pct)
  select w, al.id, substr(p.key, strpos(p.key, '|') + 1),
         (select ty.id from public.aircraft_types ty where ty.world_id = w and ty.name = p.new_item ->> 'aircraft' order by ty.id limit 1),
         (select cc.id from public.cabin_configs cc where cc.world_id = w and cc.code = p.new_item ->> 'config' order by cc.id limit 1),
         (select v from private.json_num(p.new_item -> 'priceY') v where abs(v) < 10000),
         (select v from private.json_num(p.new_item -> 'priceJ') v where abs(v) < 10000)
    from pg_temp.t_pa p join public.airlines al on al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
   where p.section = 'ref.markets' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object' and strpos(p.key, '|') > 0
  on conflict (airline_id, name) do update set default_type_id = excluded.default_type_id,
    default_config_id = excluded.default_config_id, fare_y_pct = excluded.fare_y_pct, fare_j_pct = excluded.fare_j_pct
  where (x.default_type_id, x.default_config_id, x.fare_y_pct, x.fare_j_pct)
        is distinct from (excluded.default_type_id, excluded.default_config_id, excluded.fare_y_pct, excluded.fare_j_pct);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('markets', n);

  -- the planner's constants (ref.consts) as settings, at the loader's default when the planner leaves one out; depCap is
  -- the house rule's figure; and the time mode (ref.timeMode)
  with m(k, setting, dflt) as (values ('buf', 'bank_buffer_min', '0'::jsonb), ('ovh', 'block_allowance_min', '25'),
         ('arrwin', 'bank_arrival_window_min', '60'), ('depwin', 'bank_departure_window_min', '60'),
         ('maxWait', 'connection_max_wait_h', '8'), ('legalGap', 'legal_gap_h', '2'), ('turnMargin', 'turn_margin_min', '10'),
         ('maintMinGround', 'maint_min_ground_min', '120'), ('leeway', 'load_leeway_days', '7'), ('lfWindow', 'load_window_days', '14'))
  update public.settings s set value = coalesce(p.new_item, m.dflt)
    from pg_temp.t_pa p join m on m.k = p.key
   where p.section = 'ref.consts' and p.state = 'changed' and s.world_id = w and s.airline_id is null and s.key = m.setting
     and s.value is distinct from coalesce(p.new_item, m.dflt);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('settings', n);
  update public.world_rules r set value = jsonb_set(r.value, '{value}', coalesce(p.new_item, '5000'::jsonb))
    from pg_temp.t_pa p
   where p.section = 'ref.consts' and p.key = 'depCap' and p.state = 'changed' and r.world_id = w
     and r.key = 'departures_per_airport_week' and jsonb_typeof(r.value) = 'object'
     and r.value -> 'value' is distinct from coalesce(p.new_item, '5000'::jsonb);
  get diagnostics n = row_count; v_out := v_out || jsonb_build_object('world_rules', n);
  update public.settings s set value = coalesce(p.new_item, '"local"'::jsonb)
    from pg_temp.t_pa p
   where p.section = 'ref.timeMode' and p.state = 'changed' and s.world_id = w and s.airline_id is null
     and s.key = 'planner_time_mode' and s.value is distinct from coalesce(p.new_item, '"local"'::jsonb);

  -- hubs and focus cities (ref.hubs): gone ones first (nothing may point at them), then the rest in the planner's order;
  -- the main hubs as the planner's MAIN_HUB has them (the loader's list)
  if exists (select 1 from pg_temp.t_pa where section = 'ref.hubs' and state = 'changed') then
    update public.airline_bases x set parent_base_id = null
     where x.world_id = w and x.parent_base_id in (
       select b.id from pg_temp.t_pa p
         join public.airlines al on al.world_id = w and al.planner_name = p.cur_item ->> 'airline'
         join public.airline_bases b on b.airline_id = al.id and b.airport_code = p.cur_item ->> 'code'
        where p.section = 'ref.hubs' and p.state = 'changed' and p.new_item is null);
    delete from public.airline_bases b
     using pg_temp.t_pa p, public.airlines al
     where p.section = 'ref.hubs' and p.state = 'changed' and p.new_item is null
       and al.world_id = w and al.planner_name = p.cur_item ->> 'airline' and b.airline_id = al.id and b.airport_code = p.cur_item ->> 'code';
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('airline_bases removed', n);
    with main(planner_name, code) as (values ('Pan American', 'JFK'), ('Kingfisher', 'DEL'), ('Virgin Atlantic', 'LGW'),
                                             ('China Eastern', 'PVG'), ('Malaysia Airlines', 'KUL'))
    insert into public.airline_bases as x (world_id, airline_id, airport_code, role, is_main, bank_times, flight_no_from,
                                           last_flight_no, hold_note, position)
    select w, al.id, h ->> 'code', case when h ->> 'role' = 'focus' then 'focus' else 'hub' end,
           exists (select 1 from main where main.planner_name = al.planner_name and main.code = h ->> 'code'),
           case when jsonb_typeof(h -> 'banks') = 'array' and jsonb_array_length(h -> 'banks') <= 4 then
             array(select case when private.clock_min(b.v #>> '{}') is not null
                               then make_time(private.clock_min(b.v #>> '{}') / 60, private.clock_min(b.v #>> '{}') % 60, 0) end
                     from jsonb_array_elements(h -> 'banks') with ordinality as b(v, o) order by b.o) end,
           (select v::int from private.json_int(h -> 'block') v where abs(v) < 2000000000),
           (select v::int from private.json_int(h -> 'lastUsed') v where abs(v) < 2000000000),
           h ->> 'hold', p.new_pos
      from pg_temp.t_pa p cross join lateral (select p.new_item as h) i
      join public.airlines al on al.world_id = w and al.planner_name = h ->> 'airline'
     where p.section = 'ref.hubs' and p.state = 'changed' and p.new_item is not null
       and exists (select 1 from public.airports a where a.code = h ->> 'code')
     order by p.new_pos
    on conflict (airline_id, airport_code) do update set role = excluded.role, is_main = excluded.is_main,
      bank_times = excluded.bank_times, flight_no_from = excluded.flight_no_from, last_flight_no = excluded.last_flight_no,
      hold_note = excluded.hold_note, position = excluded.position
    where (x.role, x.is_main, x.bank_times, x.flight_no_from, x.last_flight_no, x.hold_note, x.position)
          is distinct from (excluded.role, excluded.is_main, excluded.bank_times, excluded.flight_no_from,
                            excluded.last_flight_no, excluded.hold_note, excluded.position);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('airline_bases', n);
    -- the others keep their place in the list
    update public.airline_bases b set position = p.new_pos
      from pg_temp.t_pa p join public.airlines al on al.world_id = w and al.planner_name = p.new_item ->> 'airline'
     where p.section = 'ref.hubs' and p.state = 'same' and b.airline_id = al.id and b.airport_code = p.new_item ->> 'code'
       and b.position is distinct from p.new_pos;
    -- a focus city's hub: the airline's own base at that airport, else any base there
    update public.airline_bases b set parent_base_id = x.parent_id
      from (select b2.id, (select q.id from public.airline_bases q
                            where q.world_id = w and q.airport_code = p.eff_item ->> 'parent' and q.id <> b2.id
                            order by (q.airline_id = b2.airline_id) desc, q.id limit 1) as parent_id
              from pg_temp.t_pa p
              join public.airlines al on al.world_id = w and al.planner_name = p.eff_item ->> 'airline'
              join public.airline_bases b2 on b2.airline_id = al.id and b2.airport_code = p.eff_item ->> 'code'
             where p.section = 'ref.hubs' and p.eff_item is not null) x
     where b.id = x.id and b.parent_base_id is distinct from x.parent_id;
  end if;

  -- what the world says about the airports the changed hubs, night bans and offsets name: a hub's own connection time
  -- (the first in the list) else site_content.mct, the night ban, the offset correction (as the loader works them out)
  if exists (select 1 from pg_temp.t_pa where section in ('ref.hubs', 'ref.curfews', 'ref.utcOverrides') and state = 'changed') then
    select s.value into v_mct from public.site_content s where s.key = 'mct';
    v_mct := case when jsonb_typeof(v_mct) = 'object' then v_mct else '{}'::jsonb end;
    if to_regclass('pg_temp.t_pa_codes') is null then
      create temporary table t_pa_codes (code text primary key, mct_min smallint, ban_from time, ban_to time, off numeric) on commit drop;
    end if;
    truncate pg_temp.t_pa_codes;
    with codes as (
      select coalesce(p.new_item, p.cur_item) ->> 'code' as code from pg_temp.t_pa p where p.section = 'ref.hubs' and p.state = 'changed'
      union select p.key from pg_temp.t_pa p where p.section in ('ref.curfews', 'ref.utcOverrides') and p.state = 'changed'),
    hub_mct as (
      select distinct on (p.eff_item ->> 'code') p.eff_item ->> 'code' as code, private.json_num(p.eff_item -> 'mct') * 60 as m
        from pg_temp.t_pa p
       where p.section = 'ref.hubs' and p.eff_item is not null and private.json_num(p.eff_item -> 'mct') is not null
       order by p.eff_item ->> 'code', coalesce(p.new_pos, p.cur_pos)),
    ban as (select p.key as code, regexp_match(p.eff_item #>> '{}', '^(\d{1,2}:\d{2})-(\d{1,2}:\d{2})$') as m
              from pg_temp.t_pa p where p.section = 'ref.curfews' and p.eff_item is not null),
    ovr as (select p.key as code, private.json_num(p.eff_item) as off
              from pg_temp.t_pa p where p.section = 'ref.utcOverrides' and p.eff_item is not null)
    insert into pg_temp.t_pa_codes
    select c.code,
           (select case when x.m = round(x.m) and abs(x.m) < 32000 then x.m::smallint end
              from (select coalesce(hm.m, private.json_num(v_mct -> c.code)) as m) x),
           case when private.clock_min(b.m[1]) is not null then make_time(private.clock_min(b.m[1]) / 60, private.clock_min(b.m[1]) % 60, 0) end,
           case when private.clock_min(b.m[2]) is not null then make_time(private.clock_min(b.m[2]) / 60, private.clock_min(b.m[2]) % 60, 0) end,
           case when abs(o.off) <= 14 then round(o.off, 2) end
      from codes c
      left join hub_mct hm on hm.code = c.code
      left join ban b on b.code = c.code
      left join ovr o on o.code = c.code
     where c.code is not null and exists (select 1 from public.airports a where a.code = c.code);
    insert into public.world_airports as x (world_id, airport_code, mct_min, night_ban_from, night_ban_to, utc_offset_override)
    select w, c.code, c.mct_min, c.ban_from, c.ban_to, c.off from pg_temp.t_pa_codes c
     where c.mct_min is not null or c.ban_from is not null or c.ban_to is not null or c.off is not null
        or exists (select 1 from public.world_airports y where y.world_id = w and y.airport_code = c.code)
    on conflict (world_id, airport_code) do update set mct_min = excluded.mct_min, night_ban_from = excluded.night_ban_from,
      night_ban_to = excluded.night_ban_to, utc_offset_override = excluded.utc_offset_override
    where (x.mct_min, x.night_ban_from, x.night_ban_to, x.utc_offset_override)
          is distinct from (excluded.mct_min, excluded.night_ban_from, excluded.night_ban_to, excluded.utc_offset_override);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('world_airports', n);
    -- a row nothing describes any more goes (the loader's tidy-up)
    delete from public.world_airports x using pg_temp.t_pa_codes c
     where x.world_id = w and x.airport_code = c.code
       and x.mct_min is null and x.night_ban_from is null and x.night_ban_to is null and x.utc_offset_override is null
       and x.game_airport_id is null and not x.closed and x.note is null and not (v_mct ? c.code)
       and not exists (select 1 from public.airline_bases b where b.world_id = w and b.airport_code = c.code);
  end if;
  return v_out;
end
$function$

;

-- private.planner_apply_routes(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_routes(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int;
begin
  if to_regclass('pg_temp.t_pa_routes') is null then
    create temporary table t_pa_routes (key text primary key, airline_id bigint, hub text, dest text, added jsonb, ord int,
      edit jsonb, cabin jsonb, named boolean, research jsonb, checked boolean not null default false) on commit drop;
  end if;
  truncate pg_temp.t_pa_routes;
  if not exists (select 1 from pg_temp.t_pa where state = 'changed'
                    and section in ('routesAdded', 'routeEdits', 'routeCabin', 'freqs', 'farePlan')) then
    return '{}'::jsonb;
  end if;
  insert into pg_temp.t_pa_routes (key, airline_id, hub, dest, added, ord, edit, cabin, named)
  select k.key, al.id, split_part(k.key, '|', 2), split_part(k.key, '|', 3),
         (select p.eff_item from pg_temp.t_pa p where p.section = 'routesAdded' and p.key = k.key and jsonb_typeof(p.eff_item) = 'array'),
         (select coalesce(p.new_pos, p.cur_pos) from pg_temp.t_pa p where p.section = 'routesAdded' and p.key = k.key),
         (select p.eff_item from pg_temp.t_pa p where p.section = 'routeEdits' and p.key = k.key and jsonb_typeof(p.eff_item) = 'object'),
         (select p.eff_item from pg_temp.t_pa p where p.section = 'routeCabin' and p.key = k.key),
         exists (select 1 from pg_temp.t_pa p where p.section in ('freqs', 'farePlan') and p.eff_item ->> 'routeKey' = k.key)
    from (select p.key from pg_temp.t_pa p where p.section in ('routesAdded', 'routeEdits', 'routeCabin') and p.state = 'changed'
          union
          select p.new_item ->> 'routeKey' from pg_temp.t_pa p
           where p.section in ('freqs', 'farePlan') and p.state = 'changed' and p.new_item ->> 'routeKey' is not null) k
    join public.airlines al on al.world_id = w and al.planner_name = split_part(k.key, '|', 1)
   where split_part(k.key, '|', 4) = ''
     and exists (select 1 from public.airports a where a.code = split_part(k.key, '|', 2))
     and exists (select 1 from public.airports a where a.code = split_part(k.key, '|', 3));

  -- the research's own entry, where it may be needed: a route that isn't added and isn't a research row yet, or was
  -- added until now, or that nothing names any more (to know whether it stays as a research route)
  update pg_temp.t_pa_routes r set checked = true
   where r.added is null
     and (not exists (select 1 from public.routes o where o.airline_id = r.airline_id and o.hub_code = r.hub and o.dest_code = r.dest and o.source = 'research')
          or (r.edit is null and r.cabin is null and not r.named));
  if exists (select 1 from pg_temp.t_pa_routes where checked) then
    update pg_temp.t_pa_routes r set research = x.v
      from (select distinct on (k.k) k.k, e.v
              from jsonb_array_elements((select case when jsonb_typeof(d.value -> 'routes') = 'array' then d.value -> 'routes' else '[]'::jsonb end
                                           from public.planner_data d where d.key = 'DATA')) with ordinality as e(v, ord)
              cross join lateral (select (e.v ->> 0) || '|' || (e.v ->> 1) || '|' || (e.v ->> 2) as k) k
             where jsonb_typeof(e.v) = 'array' and k.k in (select key from pg_temp.t_pa_routes where checked)
             order by k.k, e.ord) x
     where r.key = x.k;
  end if;

  insert into public.routes as x (world_id, airline_id, hub_code, dest_code, city, country_label, distance_km, market_id, stars,
                                  source, removed, removed_note, city_override, distance_override_km, market_override_id,
                                  market_cleared, stars_override, edit_kept, cabin_choice)
  select w, r.airline_id, r.hub, r.dest,
         case when s.keep then old.city else s.src ->> 3 end,
         case when s.keep then old.country_label else s.src ->> 4 end,
         case when s.keep then old.distance_km else (select v::int from private.json_int(s.src -> 5) v where abs(v) < 2000000000) end,
         case when s.keep then old.market_id else (select m.id from public.markets m where m.airline_id = r.airline_id and m.name = s.src ->> 6) end,
         case when s.keep then old.stars else (select v::smallint from private.json_int(s.src -> 7) v where abs(v) < 32000) end,
         case when r.added is not null then 'added' else 'research' end,
         e.removed, e.note, e.city, e.dist, e.market_id, e.market_cleared, e.stars,
         -- an edit that changes nothing (restoring a removed route leaves {}) is kept as such
         r.edit is not null and not (e.removed or e.note is not null or e.city is not null or e.dist is not null
                                     or e.market_id is not null or e.market_cleared or e.stars is not null),
         case when r.cabin #>> '{}' in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort') then r.cabin #>> '{}' end
    from pg_temp.t_pa_routes r
    left join public.routes old on old.airline_id = r.airline_id and old.hub_code = r.hub and old.dest_code = r.dest
    cross join lateral (select case when r.added is not null then r.added when old.id is null or old.source = 'added' then r.research end as src,
                               (r.added is null and old.id is not null and old.source = 'research') as keep) s
    cross join lateral (
      select coalesce(r.edit -> 'removed' = 'true'::jsonb, false) as removed, r.edit ->> 'note' as note, r.edit ->> 'city' as city,
             (select v::int from private.json_int(r.edit -> 'dist') v where abs(v) < 2000000000) as dist,
             (select m.id from public.markets m where m.airline_id = r.airline_id and m.name = r.edit ->> 'market') as market_id,
             coalesce(r.edit ->> 'market' = '', false) as market_cleared,
             (select v::smallint from private.json_int(r.edit -> 'stars') v where abs(v) < 32000) as stars) e
   where old.id is not null or r.added is not null or r.edit is not null or r.cabin is not null or r.research is not null or r.named
   order by r.added is null, r.ord, r.key   -- routes added in the planner in its order: the getter lists them by id
  on conflict (airline_id, hub_code, dest_code) do update set city = excluded.city, country_label = excluded.country_label,
    distance_km = excluded.distance_km, market_id = excluded.market_id, stars = excluded.stars, source = excluded.source,
    removed = excluded.removed, removed_note = excluded.removed_note, city_override = excluded.city_override,
    distance_override_km = excluded.distance_override_km, market_override_id = excluded.market_override_id,
    market_cleared = excluded.market_cleared, stars_override = excluded.stars_override, edit_kept = excluded.edit_kept,
    cabin_choice = excluded.cabin_choice
  where (x.city, x.country_label, x.distance_km, x.market_id, x.stars, x.source, x.removed, x.removed_note, x.city_override,
         x.distance_override_km, x.market_override_id, x.market_cleared, x.stars_override, x.edit_kept, x.cabin_choice)
        is distinct from (excluded.city, excluded.country_label, excluded.distance_km, excluded.market_id, excluded.stars,
                          excluded.source, excluded.removed, excluded.removed_note, excluded.city_override,
                          excluded.distance_override_km, excluded.market_override_id, excluded.market_cleared,
                          excluded.stars_override, excluded.edit_kept, excluded.cabin_choice);
  get diagnostics n = row_count;
  return jsonb_build_object('routes', n);
end
$function$

;

-- private.planner_apply_tidy(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.planner_apply_tidy(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb;
begin
  if exists (select 1 from pg_temp.t_pa where section in ('tails', 'deliveries') and state = 'changed') then
    if to_regclass('pg_temp.t_pa_gone') is null then
      create temporary table t_pa_gone (id bigint primary key) on commit drop;
    end if;
    truncate pg_temp.t_pa_gone;
    insert into pg_temp.t_pa_gone
    select a.id from public.aircraft a
     where a.world_id = w
       and a.registration in (select p.key from pg_temp.t_pa p where p.section in ('tails', 'deliveries') and p.state = 'changed')
       and not exists (select 1 from pg_temp.t_pa p where p.section in ('tails', 'deliveries') and p.key = a.registration and p.eff_item is not null);
    update public.aircraft a set status = 'retired', retired_on = coalesce(a.retired_on, current_date),
           extra = a.extra - array['tails_index', 'deliveries_index', 'tail', 'delivery']
     where a.id in (select id from pg_temp.t_pa_gone) and a.status <> 'retired'
       and (exists (select 1 from public.game_flights f where f.aircraft_id = a.id)
            or exists (select 1 from public.game_payments p where p.aircraft_id = a.id)
            or exists (select 1 from public.spending_log x where x.aircraft_id = a.id));
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft retired', n);
    delete from public.aircraft a
     where a.id in (select id from pg_temp.t_pa_gone) and a.status <> 'retired'
       and not exists (select 1 from public.flight_legs l where l.aircraft_id = a.id)
       and not exists (select 1 from public.plan_cards p where p.aircraft_id = a.id)
       and not exists (select 1 from public.aircraft_cabin_keeps k where k.aircraft_id = a.id);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft removed', n);
    update public.aircraft a set extra = a.extra - array['tails_index', 'deliveries_index', 'tail', 'delivery']
     where a.id in (select id from pg_temp.t_pa_gone) and a.extra ?| array['tails_index', 'deliveries_index', 'tail', 'delivery'];
  end if;

  if to_regclass('pg_temp.t_pa_routes') is not null then
    delete from public.routes x using pg_temp.t_pa_routes r
     where x.airline_id = r.airline_id and x.hub_code = r.hub and x.dest_code = r.dest
       and r.checked and r.research is null and r.added is null and r.edit is null and r.cabin is null
       and not exists (select 1 from pg_temp.t_pa p where p.section in ('freqs', 'farePlan') and p.eff_item ->> 'routeKey' = r.key)
       and not exists (select 1 from public.rotations o where o.route_id = x.id)
       and not exists (select 1 from public.fare_plan o where o.route_id = x.id)
       and not exists (select 1 from public.game_flights o where o.route_id = x.id);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes removed', n);
  end if;

  if exists (select 1 from pg_temp.t_pa where section like 'ref.%' and state = 'changed' and new_item is null) then
    delete from public.markets x using pg_temp.t_pa p, public.airlines al
     where p.section = 'ref.markets' and p.state = 'changed' and p.new_item is null
       and al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
       and x.airline_id = al.id and x.name = substr(p.key, strpos(p.key, '|') + 1)
       and not exists (select 1 from public.routes o where o.market_id = x.id or o.market_override_id = x.id);
    -- types, layouts and services by their place before the save (private.planner_apply_reference), unless the row was
    -- renamed in place
    if exists (select 1 from pg_temp.t_pa where section in ('ref.types', 'ref.configs', 'ref.services') and state = 'changed') then
      delete from public.cabin_configs x using pg_temp.t_pa p, pg_temp.t_pa_ref m
       where p.section = 'ref.configs' and p.state = 'changed' and p.new_item is null
         and m.section = p.section and m.pos = p.cur_pos and x.id = m.id
         and not exists (select 1 from pg_temp.t_pa_ref_row k where k.section = p.section and k.id = x.id)
         and not exists (select 1 from public.aircraft o where o.cabin_config_id = x.id or o.order_config_id = x.id)
         and not exists (select 1 from public.markets o where o.default_config_id = x.id);
      delete from public.aircraft_types x using pg_temp.t_pa p, pg_temp.t_pa_ref m
       where p.section = 'ref.types' and p.state = 'changed' and p.new_item is null
         and m.section = p.section and m.pos = p.cur_pos and x.id = m.id
         and not exists (select 1 from pg_temp.t_pa_ref_row k where k.section = p.section and k.id = x.id)
         and not exists (select 1 from public.aircraft o where o.aircraft_type_id = x.id)
         and not exists (select 1 from public.cabin_configs o where o.aircraft_type_id = x.id)
         and not exists (select 1 from public.markets o where o.default_type_id = x.id)
         and not exists (select 1 from public.airline_aircraft_types o where o.aircraft_type_id = x.id);
      delete from public.service_profiles x using pg_temp.t_pa p, pg_temp.t_pa_ref m
       where p.section = 'ref.services' and p.state = 'changed' and p.new_item is null
         and m.section = p.section and m.pos = p.cur_pos and x.id = m.id
         and not exists (select 1 from pg_temp.t_pa_ref_row k where k.section = p.section and k.id = x.id);
    end if;
  end if;
  return v_out;
end
$function$

;

-- private.planner_apply_work(p_world_id bigint, p_keep_order boolean)
CREATE OR REPLACE FUNCTION private.planner_apply_work(p_world_id bigint, p_keep_order boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; n int; v_out jsonb := '{}'::jsonb; v_first bigint;
  k_todo text[] := array['id', 'title', 'date', 'done', 'doneAt', 'created', 'note', 'items'];
  k_fare text[] := array['id', 'airline', 'routeKey', 'cls', 'pct', 'from', 'proposed', 'status', 'why'];
begin
  -- ---- to-dos and their steps
  if exists (select 1 from pg_temp.t_pa where section = 'todos' and state = 'changed') then
    delete from public.todos t using pg_temp.t_pa p
     where p.section = 'todos' and p.state = 'changed' and p.new_item is null and t.world_id = w and t.legacy_key = p.key;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todos removed', n);
    insert into public.todos as x (world_id, legacy_key, title, due_on, done, done_at, note, created_at, extra)
    select w, p.key, coalesce(v ->> 'title', ''), private.json_date(v -> 'date'), coalesce(v -> 'done' = 'true'::jsonb, false),
           private.json_ts(v -> 'doneAt'), v ->> 'note',
           -- a to-do with no creation time of its own keeps the one it has
           coalesce(private.json_ts(v -> 'created'), old.created_at, now()),
           private.planner_extra(v, k_todo, old.extra)
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      left join public.todos old on old.world_id = w and old.legacy_key = p.key
     where p.section = 'todos' and p.state = 'changed' and p.new_item is not null
     order by p.new_pos
    on conflict (world_id, legacy_key) do update set title = excluded.title, due_on = excluded.due_on, done = excluded.done,
      done_at = excluded.done_at, note = excluded.note, created_at = excluded.created_at, extra = excluded.extra
    where (x.title, x.due_on, x.done, x.done_at, x.note, x.created_at, x.extra)
          is distinct from (excluded.title, excluded.due_on, excluded.done, excluded.done_at, excluded.note,
                            excluded.created_at, excluded.extra);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todos', n);
    insert into public.todo_items as x (world_id, todo_id, position, body)
    select w, t.id, (e.ord)::int, case when jsonb_typeof(e.i) = 'string' then e.i #>> '{}' else e.i::text end
      from pg_temp.t_pa p
      join public.todos t on t.world_id = w and t.legacy_key = p.key
      cross join lateral jsonb_array_elements(case when jsonb_typeof(p.new_item -> 'items') = 'array' then p.new_item -> 'items' else '[]'::jsonb end) with ordinality as e(i, ord)
     where p.section = 'todos' and p.state = 'changed' and p.new_item is not null
     order by t.id, e.ord
    on conflict (todo_id, position) do update set body = excluded.body where x.body is distinct from excluded.body;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('todo_items', n);
    delete from public.todo_items x using pg_temp.t_pa p, public.todos t
     where p.section = 'todos' and p.state = 'changed' and p.new_item is not null
       and t.world_id = w and t.legacy_key = p.key and x.todo_id = t.id
       and x.position > coalesce(jsonb_array_length(case when jsonb_typeof(p.new_item -> 'items') = 'array' then p.new_item -> 'items' end), 0);
  end if;

  -- ---- fare plan
  if exists (select 1 from pg_temp.t_pa where section = 'farePlan' and state = 'changed') then
    delete from public.fare_plan t using pg_temp.t_pa p
     where p.section = 'farePlan' and p.state = 'changed' and p.new_item is null and t.world_id = w and t.legacy_key = p.key;
    insert into public.fare_plan as x (world_id, airline_id, route_id, legacy_key, cabin_class, change_pct, fare_from,
                                       proposed_on, status, reason, extra)
    select w, al.id,
           (select r.id from public.routes r join public.airlines ra on ra.id = r.airline_id
             where r.world_id = w and ra.planner_name || '|' || r.hub_code || '|' || r.dest_code = v ->> 'routeKey'),
           p.key, case when v ->> 'cls' in ('economy', 'business', 'first') then v ->> 'cls' end,
           (select x2 from private.json_num(v -> 'pct') x2 where abs(x2) < 10000),
           (select x2 from private.json_num(v -> 'from') x2 where abs(x2) < 1000000000000),
           private.json_date(v -> 'proposed'), case when v ->> 'status' = 'dropped' then 'dropped' else 'planned' end,
           v ->> 'why', private.planner_extra(v, k_fare, old.extra)
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      join public.airlines al on al.world_id = w and al.planner_name = v ->> 'airline'
      left join public.fare_plan old on old.world_id = w and old.legacy_key = p.key
     where p.section = 'farePlan' and p.state = 'changed' and p.new_item is not null
     order by p.new_pos
    on conflict (world_id, legacy_key) do update set airline_id = excluded.airline_id, route_id = excluded.route_id,
      cabin_class = excluded.cabin_class, change_pct = excluded.change_pct, fare_from = excluded.fare_from,
      proposed_on = excluded.proposed_on, status = excluded.status, reason = excluded.reason, extra = excluded.extra
    where (x.airline_id, x.route_id, x.cabin_class, x.change_pct, x.fare_from, x.proposed_on, x.status, x.reason, x.extra)
          is distinct from (excluded.airline_id, excluded.route_id, excluded.cabin_class, excluded.change_pct,
                            excluded.fare_from, excluded.proposed_on, excluded.status, excluded.reason, excluded.extra);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('fare_plan', n);
  end if;

  -- ---- interline, keyed "Airline|country": the planner's "requested" is to_sign; a record with no status (the planner's
  -- "not contacted") has none
  if exists (select 1 from pg_temp.t_pa where section = 'interline' and state = 'changed') then
    delete from public.interline_agreements x using pg_temp.t_pa p, public.airlines al
     where p.section = 'interline' and p.state = 'changed' and p.new_item is null
       and al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
       and x.airline_id = al.id and x.country_code = substr(p.key, strpos(p.key, '|') + 1);
    insert into public.interline_agreements as x (world_id, airline_id, country_code, status, partner, decided_on, note)
    select w, al.id, substr(p.key, strpos(p.key, '|') + 1),
           case when v ->> 'status' in ('signed', 'declined', 'nopartner') then v ->> 'status'
                when v ->> 'status' is not null then 'to_sign' end,
           v ->> 'partner', private.json_date(v -> 'date'), v ->> 'notes'
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      join public.airlines al on al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
     where p.section = 'interline' and p.state = 'changed' and jsonb_typeof(p.new_item) = 'object'
       and exists (select 1 from public.countries c where c.code = substr(p.key, strpos(p.key, '|') + 1))
    on conflict (airline_id, country_code) do update set status = excluded.status, partner = excluded.partner,
      decided_on = excluded.decided_on, note = excluded.note
    where (x.status, x.partner, x.decided_on, x.note) is distinct from (excluded.status, excluded.partner, excluded.decided_on, excluded.note);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('interline_agreements', n);
  end if;

  -- ---- monthly checks, keyed "Airline|task": "Equinox" is the group as a whole
  if exists (select 1 from pg_temp.t_pa where section = 'monthly' and state = 'changed') then
    delete from public.monthly_checks x using pg_temp.t_pa p
     where p.section = 'monthly' and p.state = 'changed' and p.new_item is null and x.world_id = w
       and x.task = substr(p.key, strpos(p.key, '|') + 1)
       and x.airline_id is not distinct from (select al.id from public.airlines al where al.world_id = w and al.planner_name = split_part(p.key, '|', 1)
                                                 and split_part(p.key, '|', 1) <> 'Equinox');
    insert into public.monthly_checks as x (world_id, airline_id, task, last_done_on)
    select w, al.id, substr(p.key, strpos(p.key, '|') + 1), private.json_date(p.new_item)
      from pg_temp.t_pa p
      left join public.airlines al on al.world_id = w and al.planner_name = split_part(p.key, '|', 1) and split_part(p.key, '|', 1) <> 'Equinox'
     where p.section = 'monthly' and p.state = 'changed' and p.new_item is not null
       and (split_part(p.key, '|', 1) = 'Equinox' or al.id is not null)
    on conflict on constraint monthly_checks_world_airline_task_key do update set last_done_on = excluded.last_done_on
    where x.last_done_on is distinct from excluded.last_done_on;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('monthly_checks', n);
  end if;

  -- ---- Home's dismissed alerts
  if exists (select 1 from pg_temp.t_pa where section = 'dismissed' and state = 'changed') then
    delete from public.dismissals x using pg_temp.t_pa p
     where p.section = 'dismissed' and p.state = 'changed' and p.new_item is null and x.world_id = w and x.alert_key = p.key;
    insert into public.dismissals as x (world_id, alert_key, dismissed_on)
    select w, p.key, private.json_date(p.new_item) from pg_temp.t_pa p
     where p.section = 'dismissed' and p.state = 'changed' and p.new_item is not null
    on conflict (world_id, alert_key) do update set dismissed_on = excluded.dismissed_on
    where x.dismissed_on is distinct from excluded.dismissed_on;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('dismissals', n);
  end if;

  -- ---- "keep this cabin" decisions, keyed "REG|Cabin"
  if exists (select 1 from pg_temp.t_pa where section = 'cabinKeep' and state = 'changed') then
    delete from public.aircraft_cabin_keeps x using pg_temp.t_pa p, public.aircraft a
     where p.section = 'cabinKeep' and p.state = 'changed' and p.new_item is null
       and a.world_id = w and a.registration = split_part(p.key, '|', 1)
       and x.aircraft_id = a.id and x.cabin = substr(p.key, strpos(p.key, '|') + 1);
    insert into public.aircraft_cabin_keeps as x (world_id, aircraft_id, cabin, decided_on)
    select w, a.id, substr(p.key, strpos(p.key, '|') + 1), private.json_date(p.new_item -> 'date')
      from pg_temp.t_pa p join public.aircraft a on a.world_id = w and a.registration = split_part(p.key, '|', 1)
     where p.section = 'cabinKeep' and p.state = 'changed' and p.new_item is not null
       and substr(p.key, strpos(p.key, '|') + 1) in ('Standard', 'Leisure', 'Leisure Plus', 'Comfort')
    on conflict (aircraft_id, cabin) do update set decided_on = excluded.decided_on where x.decided_on is distinct from excluded.decided_on;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('aircraft_cabin_keeps', n);
  end if;

  -- ---- money spent (capex)
  if exists (select 1 from pg_temp.t_pa where section = 'capex' and state = 'changed') then
    with gone as (select p.grp, count(*) as n from pg_temp.t_pa p
                   where p.section = 'capex' and p.state = 'changed' and p.new_item is null group by p.grp),
    stored as (select s.id, row_number() over (partition by k.k order by s.id desc) as rn, k.k
                 from public.spending_log s join public.airlines al on al.id = s.airline_id
                 cross join lateral (select private.capex_key(al.planner_name, s.spent_on, s.kind, s.amount, s.note) as k) k
                where s.world_id = w)
    delete from public.spending_log s using stored r join gone g on g.grp = r.k where s.id = r.id and r.rn <= g.n;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('spending_log removed', n);
    insert into public.spending_log (world_id, airline_id, spent_on, amount, kind, aircraft_id, note)
    select w, al.id, private.json_date(v -> 'date'), round(private.json_num(v -> 'amountM') * 1000000, 2),
           case when v ->> 'kind' in ('order', 'cabin', 'loss') then v ->> 'kind' else 'order' end,
           -- the aircraft, where the note starts with one of the airline's registrations
           (select a.id from public.aircraft a where a.world_id = w and a.airline_id = al.id
               and a.registration = split_part(btrim(coalesce(v ->> 'note', '')), ' ', 1)),
           v ->> 'note'
      from pg_temp.t_pa p cross join lateral (select p.new_item as v) i
      join public.airlines al on al.world_id = w and al.planner_name = v ->> 'airline'
     where p.section = 'capex' and p.state = 'changed' and p.new_item is not null and p.cur_item is null and p.grp not like 'unparsed %'
     order by p.new_pos;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('spending_log', n);
    if p_keep_order then
      with stored as (
        select s.id, k.k || '#' || row_number() over (partition by k.k order by s.id) as kk, row_number() over (order by s.id) as rn
          from public.spending_log s join public.airlines al on al.id = s.airline_id
          cross join lateral (select private.capex_key(al.planner_name, s.spent_on, s.kind, s.amount, s.note) as k) k
         where s.world_id = w),
      wanted as (
        select p.key as kk, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
         where p.section = 'capex' and p.new_item is not null and p.grp not like 'unparsed %'
           and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline'))
      select min(coalesce(s.rn, x.rn)) into v_first from stored s full join wanted x on x.rn = s.rn where s.kk is distinct from x.kk;
      if v_first is not null then
        delete from public.spending_log s
         where s.id in (select id from (select s2.id, row_number() over (order by s2.id) as rn from public.spending_log s2 where s2.world_id = w) z
                         where z.rn >= v_first);
        insert into public.spending_log (world_id, airline_id, spent_on, amount, kind, aircraft_id, note)
        select w, al.id, private.json_date(v -> 'date'), round(private.json_num(v -> 'amountM') * 1000000, 2),
               case when v ->> 'kind' in ('order', 'cabin', 'loss') then v ->> 'kind' else 'order' end,
               (select a.id from public.aircraft a where a.world_id = w and a.airline_id = al.id
                   and a.registration = split_part(btrim(coalesce(v ->> 'note', '')), ' ', 1)),
               v ->> 'note'
          from (select p.new_item as v, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
                 where p.section = 'capex' and p.new_item is not null and p.grp not like 'unparsed %'
                   and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline')) x
          join public.airlines al on al.world_id = w and al.planner_name = x.v ->> 'airline'
         where x.rn >= v_first
         order by x.rn;
        get diagnostics n = row_count; v_out := v_out || jsonb_build_object('spending_log written again in order', n);
      end if;
    end if;
  end if;

  -- ---- growth moves (growthLog)
  if exists (select 1 from pg_temp.t_pa where section = 'growthLog' and state = 'changed') then
    with gone as (select p.grp, count(*) as n from pg_temp.t_pa p
                   where p.section = 'growthLog' and p.state = 'changed' and p.new_item is null group by p.grp),
    stored as (select g.id, row_number() over (partition by k.k order by g.id desc) as rn, k.k
                 from public.growth_log g join public.airlines al on al.id = g.airline_id
                 cross join lateral (select private.growth_key(al.planner_name, g.logged_on, g.move, g.note) as k) k
                where g.world_id = w)
    delete from public.growth_log g using stored r join gone x on x.grp = r.k where g.id = r.id and r.rn <= x.n;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('growth_log removed', n);
    insert into public.growth_log (world_id, airline_id, logged_on, move, note)
    select w, al.id, private.json_date(p.new_item -> 'date'), p.new_item ->> 'move', p.new_item ->> 'note'
      from pg_temp.t_pa p join public.airlines al on al.world_id = w and al.planner_name = p.new_item ->> 'airline'
     where p.section = 'growthLog' and p.state = 'changed' and p.new_item is not null and p.cur_item is null and p.grp not like 'unparsed %'
     order by p.new_pos;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('growth_log', n);
    if p_keep_order then
      with stored as (
        select g.id, k.k || '#' || row_number() over (partition by k.k order by g.id) as kk, row_number() over (order by g.id) as rn
          from public.growth_log g join public.airlines al on al.id = g.airline_id
          cross join lateral (select private.growth_key(al.planner_name, g.logged_on, g.move, g.note) as k) k
         where g.world_id = w),
      wanted as (
        select p.key as kk, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
         where p.section = 'growthLog' and p.new_item is not null and p.grp not like 'unparsed %'
           and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline'))
      select min(coalesce(s.rn, x.rn)) into v_first from stored s full join wanted x on x.rn = s.rn where s.kk is distinct from x.kk;
      if v_first is not null then
        delete from public.growth_log g
         where g.id in (select id from (select g2.id, row_number() over (order by g2.id) as rn from public.growth_log g2 where g2.world_id = w) z
                         where z.rn >= v_first);
        insert into public.growth_log (world_id, airline_id, logged_on, move, note)
        select w, al.id, private.json_date(x.v -> 'date'), x.v ->> 'move', x.v ->> 'note'
          from (select p.new_item as v, row_number() over (order by p.new_pos) as rn from pg_temp.t_pa p
                 where p.section = 'growthLog' and p.new_item is not null and p.grp not like 'unparsed %'
                   and exists (select 1 from public.airlines al where al.world_id = w and al.planner_name = p.new_item ->> 'airline')) x
          join public.airlines al on al.world_id = w and al.planner_name = x.v ->> 'airline'
         where x.rn >= v_first
         order by x.rn;
        get diagnostics n = row_count; v_out := v_out || jsonb_build_object('growth_log written again in order', n);
      end if;
    end if;
  end if;
  return v_out;
end
$function$

;

-- private.planner_doc_with_item(p_doc jsonb, p_section text, p_key text, p_value jsonb)
CREATE OR REPLACE FUNCTION private.planner_doc_with_item(p_doc jsonb, p_section text, p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_path text[]; v_list jsonb; v_id text; v_out jsonb := '[]'::jsonb; e jsonb; v_done boolean := false; i int;
begin
  if p_value = 'null'::jsonb then p_value := null; end if;
  if p_section in ('plans', 'routeEdits', 'routeCabin', 'interline', 'dismissed', 'cabinKeep', 'monthly', 'cash', 'fixed7',
                   'ref.markets', 'ref.curfews', 'ref.utcOverrides', 'ref.gameLinks', 'ref.consts') then
    if coalesce(p_key, '') = '' then raise exception '% needs a key', p_section; end if;
    v_path := case when p_section like 'ref.%' then array['ref', substr(p_section, 5)] else array[p_section] end;
    v_list := case when jsonb_typeof(p_doc #> v_path) = 'object' then p_doc #> v_path else '{}'::jsonb end;
    v_list := case when p_value is null then v_list - p_key else v_list || jsonb_build_object(p_key, p_value) end;
  elsif p_section = 'ref.timeMode' then
    return case when p_value is null then jsonb_set(p_doc, '{ref}', coalesce(p_doc -> 'ref', '{}'::jsonb) - 'timeMode')
                else jsonb_set(p_doc, '{ref}', coalesce(p_doc -> 'ref', '{}'::jsonb) || jsonb_build_object('timeMode', p_value)) end;
  elsif p_section in ('tails', 'deliveries', 'freqs', 'todos', 'farePlan', 'routesAdded', 'ref.hubs', 'ref.types', 'ref.configs', 'ref.services') then
    if coalesce(p_key, '') = '' then raise exception '% needs a key', p_section; end if;
    v_path := case when p_section like 'ref.%' then array['ref', substr(p_section, 5)] else array[p_section] end;
    v_id := case p_section when 'deliveries' then 'reg' when 'ref.types' then 'name' when 'ref.configs' then 'code'
                           when 'ref.services' then 'code' else 'id' end;
    if p_value is not null then
      if p_section = 'routesAdded' then
        if jsonb_typeof(p_value) <> 'array' or (p_value ->> 0) || '|' || (p_value ->> 1) || '|' || (p_value ->> 2) is distinct from p_key then
          raise exception 'a route added is [airline, hub, destination, ...] and its key airline|hub|destination';
        end if;
      elsif jsonb_typeof(p_value) <> 'object' then
        raise exception 'an item of % is a JSON object', p_section;
      elsif p_section = 'ref.hubs' then
        if (p_value ->> 'airline') || '|' || (p_value ->> 'code') is distinct from p_key then
          raise exception 'a hub''s key is its airline|code';
        end if;
      else
        p_value := p_value || jsonb_build_object(v_id, p_key);
      end if;
    end if;
    for e in select x from jsonb_array_elements(case when jsonb_typeof(p_doc #> v_path) = 'array' then p_doc #> v_path else '[]'::jsonb end) as x loop
      if (case when p_section = 'routesAdded' and jsonb_typeof(e) = 'array' then (e ->> 0) || '|' || (e ->> 1) || '|' || (e ->> 2)
               when p_section = 'ref.hubs' and jsonb_typeof(e) = 'object' then (e ->> 'airline') || '|' || (e ->> 'code')
               when jsonb_typeof(e) = 'object' then e ->> v_id end) is not distinct from p_key then
        if not v_done and p_value is not null then v_out := v_out || jsonb_build_array(p_value); end if;
        v_done := true;
      else
        v_out := v_out || jsonb_build_array(e);
      end if;
    end loop;
    if not v_done and p_value is not null then v_out := v_out || jsonb_build_array(p_value); end if;
    v_list := v_out;
  elsif p_section in ('capex', 'growthLog') then
    v_path := array[p_section];
    v_list := case when jsonb_typeof(p_doc -> p_section) = 'array' then p_doc -> p_section else '[]'::jsonb end;
    if p_value is not null and jsonb_typeof(p_value) <> 'object' then raise exception 'an entry of % is a JSON object', p_section; end if;
    if coalesce(p_key, '') = '' then
      if p_value is null then raise exception 'say which entry of % to remove: its place, 0 first', p_section; end if;
      v_list := v_list || jsonb_build_array(p_value);
    else
      if p_key !~ '^\d+$' or p_key::int >= jsonb_array_length(v_list) then
        raise exception '% has no entry %', p_section, p_key;
      end if;
      i := p_key::int;
      v_list := case when p_value is null then v_list - i else jsonb_set(v_list, array[i::text], p_value) end;
    end if;
  else
    raise exception 'unknown section: %', p_section;
  end if;
  if v_path[1] = 'ref' then
    return jsonb_set(p_doc, '{ref}', coalesce(case when jsonb_typeof(p_doc -> 'ref') = 'object' then p_doc -> 'ref' end, '{}'::jsonb)
                                     || jsonb_build_object(v_path[2], v_list));
  end if;
  return p_doc || jsonb_build_object(v_path[1], v_list);
end
$function$

;

-- private.planner_duplicates(p_doc jsonb)
CREATE OR REPLACE FUNCTION private.planner_duplicates(p_doc jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select string_agg(format('duplicate code %s in %s', x.code, x.section), ', ' order by x.section, x.code)
    from (select 'ref.' || s.sub as section, c.code
            from (values ('hubs'), ('types'), ('configs'), ('services')) as s(sub)
            cross join lateral jsonb_array_elements(case when jsonb_typeof(p_doc #> array['ref', s.sub]) = 'array'
                                                         then p_doc #> array['ref', s.sub] else '[]'::jsonb end) as e(v)
            cross join lateral (select case s.sub when 'hubs' then (e.v ->> 'airline') || '|' || (e.v ->> 'code')
                                                  when 'types' then e.v ->> 'name' else e.v ->> 'code' end as code) c
           where jsonb_typeof(e.v) = 'object' and coalesce(c.code, '') <> '' and not private.planner_ref_blank('ref.' || s.sub, c.code)
           group by 1, 2
          having count(*) > 1) x
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

-- private.planner_frozen()
CREATE OR REPLACE FUNCTION private.planner_frozen()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'frozen since %; write to the tables', tg_argv[0]
    using errcode = '42501',
          detail = format('%s is the old planner''s storage, kept unchanged as the fallback since the switch-over (#13, design §8).', tg_table_name),
          hint = 'The planner saves through planner_state_put() and save_loads(). A data-only change goes through planner_item_put() or plain SQL after the equinox.actor line (manual §1). private.unfreeze_planner_state() undoes the switch-over.';
end
$function$
;


-- private.planner_frozen_since(p_table regclass)
CREATE OR REPLACE FUNCTION private.planner_frozen_since(p_table regclass)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select split_part(encode(t.tgargs, 'escape'), '\000', 1)
    from pg_catalog.pg_trigger t
   where t.tgrelid = p_table and t.tgname = 'planner_frozen' and t.tgenabled <> 'D'
$function$
;


-- private.planner_items(p_doc jsonb)
CREATE OR REPLACE FUNCTION private.planner_items(p_doc jsonb)
 RETURNS TABLE(section text, key text, grp text, pos integer, item jsonb)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select s.section, x.k, x.k, x.pos, x.v
    from (values ('tails', 'id'), ('deliveries', 'reg'), ('freqs', 'id'), ('todos', 'id'), ('farePlan', 'id')) as s(section, id_key)
    cross join lateral (
      select distinct on (e.v ->> s.id_key) e.v ->> s.id_key as k, (e.ord - 1)::int as pos, e.v
        from jsonb_array_elements(case when jsonb_typeof(p_doc -> s.section) = 'array' then p_doc -> s.section else '[]'::jsonb end) with ordinality as e(v, ord)
       where jsonb_typeof(e.v) = 'object' and coalesce(e.v ->> s.id_key, '') <> ''
       order by e.v ->> s.id_key, e.ord) x
  union all
  select 'ref.' || s.sub, x.k, x.g, x.pos, x.v
    from (values ('hubs'), ('types'), ('configs'), ('services')) as s(sub)
    cross join lateral (
      select distinct on (kk.k) kk.k, kk.g, (e.ord - 1)::int as pos, e.v
        from jsonb_array_elements(case when jsonb_typeof(p_doc #> array['ref', s.sub]) = 'array' then p_doc #> array['ref', s.sub] else '[]'::jsonb end) with ordinality as e(v, ord)
        cross join lateral (select case s.sub when 'hubs' then (e.v ->> 'airline') || '|' || (e.v ->> 'code')
                                              when 'types' then e.v ->> 'name' else e.v ->> 'code' end as g) c
        -- a blank code (private.planner_ref_blank) may repeat: such an entry is told apart by its place
        cross join lateral (select case when private.planner_ref_blank('ref.' || s.sub, c.g) then c.g || '@' || (e.ord - 1) else c.g end as k,
                                   c.g) kk
       where jsonb_typeof(e.v) = 'object' and (coalesce(kk.g, '') <> '' or private.planner_ref_blank('ref.' || s.sub, kk.g))
       order by kk.k, e.ord) x
  union all
  select 'routesAdded', x.k, x.k, x.pos, x.v
    from (select distinct on (kk.k) kk.k, (e.ord - 1)::int as pos, e.v
            from jsonb_array_elements(case when jsonb_typeof(p_doc -> 'routesAdded') = 'array' then p_doc -> 'routesAdded' else '[]'::jsonb end) with ordinality as e(v, ord)
            cross join lateral (select (e.v ->> 0) || '|' || (e.v ->> 1) || '|' || (e.v ->> 2) as k) kk
           where jsonb_typeof(e.v) = 'array' and kk.k is not null
           order by kk.k, e.ord) x
  union all
  select s.section, e.key, e.key, null::int, e.value
    from unnest(array['plans', 'routeEdits', 'routeCabin', 'interline', 'dismissed', 'cabinKeep']) as s(section)
    cross join lateral jsonb_each(case when jsonb_typeof(p_doc -> s.section) = 'object' then p_doc -> s.section else '{}'::jsonb end) e
   where e.value <> 'null'::jsonb
  union all
  select 'ref.' || s.sub, e.key, e.key, null::int, e.value
    from unnest(array['markets', 'curfews', 'utcOverrides', 'gameLinks', 'consts']) as s(sub)
    cross join lateral jsonb_each(case when jsonb_typeof(p_doc #> array['ref', s.sub]) = 'object' then p_doc #> array['ref', s.sub] else '{}'::jsonb end) e
   where e.value <> 'null'::jsonb
  union all
  select 'ref.timeMode', '', '', null::int, p_doc #> '{ref,timeMode}'
   where coalesce(p_doc #> '{ref,timeMode}', 'null'::jsonb) <> 'null'::jsonb
  union all
  select 'monthly', m.key || '|' || t.key, m.key || '|' || t.key, null::int, t.value
    from jsonb_each(case when jsonb_typeof(p_doc -> 'monthly') = 'object' then p_doc -> 'monthly' else '{}'::jsonb end) m
    cross join lateral jsonb_each(case when jsonb_typeof(m.value) = 'object' then m.value else '{}'::jsonb end) t
   where t.value <> 'null'::jsonb
  union all
  select s.section, d.key || '|' || a.key, d.key || '|' || a.key, null::int, a.value
    from unnest(array['cash', 'fixed7']) as s(section)
    cross join lateral jsonb_each(case when jsonb_typeof(p_doc -> s.section) = 'object' then p_doc -> s.section else '{}'::jsonb end) d
    cross join lateral jsonb_each(case when jsonb_typeof(d.value) = 'object' then d.value else '{}'::jsonb end) a
   where a.value <> 'null'::jsonb
  union all
  select x.section, x.content || '#' || row_number() over (partition by x.section, x.content order by x.pos), x.content, x.pos, x.v
    from (select 'capex' as section, (e.ord - 1)::int as pos, e.v,
                 case when private.json_date(e.v -> 'date') is not null and abs(private.json_num(e.v -> 'amountM')) < 1000000
                           and e.v ->> 'airline' is not null
                      then private.capex_key(e.v ->> 'airline', private.json_date(e.v -> 'date'),
                                             case when e.v ->> 'kind' in ('order', 'cabin', 'loss') then e.v ->> 'kind' else 'order' end,
                                             private.json_num(e.v -> 'amountM') * 1000000, e.v ->> 'note')
                      else 'unparsed ' || e.v::text end as content
            from jsonb_array_elements(case when jsonb_typeof(p_doc -> 'capex') = 'array' then p_doc -> 'capex' else '[]'::jsonb end) with ordinality as e(v, ord)
           where jsonb_typeof(e.v) = 'object'
          union all
          select 'growthLog', (e.ord - 1)::int, e.v,
                 case when private.json_date(e.v -> 'date') is not null and e.v ->> 'move' in ('big', 'freq', 'feeder') and e.v ->> 'airline' is not null
                      then private.growth_key(e.v ->> 'airline', private.json_date(e.v -> 'date'), e.v ->> 'move', e.v ->> 'note')
                      else 'unparsed ' || e.v::text end
            from jsonb_array_elements(case when jsonb_typeof(p_doc -> 'growthLog') = 'array' then p_doc -> 'growthLog' else '[]'::jsonb end) with ordinality as e(v, ord)
           where jsonb_typeof(e.v) = 'object') x
$function$

;

-- private.planner_json_diff(p_old jsonb, p_new jsonb, p_path text, p_key text, p_in_list boolean)
CREATE OR REPLACE FUNCTION private.planner_json_diff(p_old jsonb, p_new jsonb, p_path text DEFAULT '$'::text, p_key text DEFAULT NULL::text, p_in_list boolean DEFAULT false)
 RETURNS TABLE(path text, kind text)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare k text; i int; n_old int; n_new int;
begin
  if p_old = p_new then return; end if;
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
        return query select * from private.planner_json_diff(p_old -> k, p_new -> k, p_path || '.' || k, k, false);
      end loop;
    when 'array' then
      n_old := jsonb_array_length(p_old); n_new := jsonb_array_length(p_new);
      for i in 0 .. greatest(n_old, n_new) - 1 loop
        return query select * from private.planner_json_diff(p_old -> i, p_new -> i, p_path || '[' || i || ']', p_key, true);
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

-- private.planner_place(p_path text)
CREATE OR REPLACE FUNCTION private.planner_place(p_path text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(p_path, '\[\d+\]', '[]', 'g'),
           '^(\$\.(plans|cash|fixed7|interline|routeEdits|routeCabin|monthly|dismissed|cabinKeep|ref\.markets|ref\.curfews|ref\.gameLinks|ref\.utcOverrides|ref\.consts))\.[^.\[]+', '\1.{}'),
           '^\$\.\d{4}-\d{2}-\d{2}', '$.{day}'), '\.f\..+$', '.f.{flight}')
$function$

;

-- private.planner_ref_blank(p_section text, p_code text)
CREATE OR REPLACE FUNCTION private.planner_ref_blank(p_section text, p_code text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select p_section in ('ref.types', 'ref.configs', 'ref.services')
         and (p_code = '' or p_code = case p_section when 'ref.types' then 'New type' when 'ref.configs' then 'NEW' else 'S5' end)
$function$

;

-- private.planner_state_check(p_world_id bigint, p_old jsonb, p_saved_at bigint, p_new jsonb)
CREATE OR REPLACE FUNCTION private.planner_state_check(p_world_id bigint, p_old jsonb, p_saved_at bigint, p_new jsonb)
 RETURNS TABLE(path text, kind text, why text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with d as (select x.path, x.kind from private.planner_json_diff(p_old, p_new) x),
  x as (
    select d.path, m[1] as sec, m[2] as day, m[3] as airline
      from d cross join lateral regexp_match(d.path, '^\$\.(cash|fixed7)\.([^.]+)(?:\.(.+))?$') as m
     where d.kind = 'differs' and m is not null),
  -- every entry behind a difference there, one per airline and date (a whole date differs when one side has none)
  entries as (
    select x.path, x.sec, x.day, x.airline from x where x.airline is not null
    union
    select x.path, x.sec, x.day, k.airline from x
      cross join lateral (select jsonb_object_keys(case when jsonb_typeof(p_new #> array[x.sec, x.day]) = 'object' then p_new #> array[x.sec, x.day] else '{}'::jsonb end)
                          union
                          select jsonb_object_keys(case when jsonb_typeof(p_old #> array[x.sec, x.day]) = 'object' then p_old #> array[x.sec, x.day] else '{}'::jsonb end)) as k(airline)
     where x.airline is null),
  money as (
    select e.path, e.sec, e.day, e.airline, p_old #> array[e.sec, e.day, e.airline] as had, p_new #> array[e.sec, e.day, e.airline] as got,
           cc.cash_at,
           case when e.sec = 'cash' then floor(cc.cash / 10000 + 0.5) / 100
                when cc.fixed_next7 > 0 then floor(cc.fixed_next7 / 10000 + 0.5) / 100 end as figure
      from entries e
      left join public.airlines al on al.planner_name = e.airline and al.world_id = p_world_id
      left join public.capture_cash cc on cc.airline_id = al.id and cc.day = private.json_date(to_jsonb(e.day)))
  select d.path, d.kind,
         case when d.kind = 'differs' then
           (select string_agg(format('%s %s %s (%s; %s)', m.sec, m.day, m.airline,
                     case when m.had is null then 'only in the tables' when m.got is null then 'only in planner_state' else 'the figure differs' end,
                     case when m.cash_at is null then 'no capture that date'
                          when m.figure is distinct from (case when jsonb_typeof(m.got) = 'number' then (m.got #>> '{}')::numeric end) then 'not the capture''s figure'
                          when m.cash_at > to_timestamp(p_saved_at / 1000.0) then 'captured after the planner last saved'
                          else 'captured before the planner last saved' end), ', ' order by m.sec, m.day, m.airline)
              from money m where m.path = d.path) end
    from d
$function$
;

-- private.planner_touched(p_world_id bigint, p_since timestamp with time zone, p_client text)
CREATE OR REPLACE FUNCTION private.planner_touched(p_world_id bigint, p_since timestamp with time zone, p_client text)
 RETURNS TABLE(section text, key text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ch as (
    select distinct l.table_name, l.row_key from public.change_log l
     where l.world_id = p_world_id and l.changed_at > p_since
       and not (p_client is not null and l.actor = 'planner' and l.actor_detail is not distinct from p_client)),
  -- what each of those rows was since then: the log's values (whole rows for an addition or a removal, the changed
  -- columns for a change), the row as it is now, and its key
  img as (
    select l.table_name, l.row_key, v.img
      from ch join public.change_log l on l.world_id = p_world_id and l.table_name = ch.table_name and l.row_key = ch.row_key and l.changed_at > p_since
      cross join lateral (values (l.old_values), (l.new_values)) as v(img)
     where v.img is not null
    union all select ch.table_name, ch.row_key, ch.row_key from ch
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.aircraft t on ch.table_name = 'aircraft' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.rotations t on ch.table_name = 'rotations' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.flight_legs t on ch.table_name = 'flight_legs' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.routes t on ch.table_name = 'routes' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.plan_cards t on ch.table_name = 'plan_cards' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.plan_card_legs t on ch.table_name = 'plan_card_legs' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.todos t on ch.table_name = 'todos' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.todo_items t on ch.table_name = 'todo_items' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.fare_plan t on ch.table_name = 'fare_plan' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.growth_log t on ch.table_name = 'growth_log' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.spending_log t on ch.table_name = 'spending_log' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.interline_agreements t on ch.table_name = 'interline_agreements' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.monthly_checks t on ch.table_name = 'monthly_checks' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.airline_bases t on ch.table_name = 'airline_bases' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.aircraft_types t on ch.table_name = 'aircraft_types' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.cabin_configs t on ch.table_name = 'cabin_configs' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.service_profiles t on ch.table_name = 'service_profiles' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.markets t on ch.table_name = 'markets' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.settings t on ch.table_name = 'settings' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.world_rules t on ch.table_name = 'world_rules' and t.id = (ch.row_key ->> 'id')::bigint
    union all select ch.table_name, ch.row_key, to_jsonb(t) from ch join public.airlines t on ch.table_name = 'airlines' and t.id = (ch.row_key ->> 'id')::bigint),
  names as (select a.id, a.planner_name from public.airlines a where a.world_id = p_world_id),
  -- a parent's identity, now or as the log had it since (it may have gone)
  parent as (
    select t.table_name, (t.row_key ->> 'id')::bigint as id, t.col, t.val from (
      select 'rotations' as table_name, jsonb_build_object('id', r.id) as row_key, 'legacy_key' as col, r.legacy_key as val from public.rotations r where r.world_id = p_world_id
      union all select 'todos', jsonb_build_object('id', r.id), 'legacy_key', r.legacy_key from public.todos r where r.world_id = p_world_id
      union all select 'aircraft', jsonb_build_object('id', r.id), 'registration', r.registration from public.aircraft r where r.world_id = p_world_id
      union all select 'plan_cards', jsonb_build_object('id', r.id), 'aircraft_id', r.aircraft_id::text from public.plan_cards r where r.world_id = p_world_id
      union all
      select l.table_name, l.row_key, c.col, coalesce(l.old_values, l.new_values) ->> c.col
        from public.change_log l
        join (values ('rotations', 'legacy_key'), ('todos', 'legacy_key'), ('aircraft', 'registration'), ('plan_cards', 'aircraft_id')) as c(tbl, col)
          on c.tbl = l.table_name
       where l.world_id = p_world_id and l.changed_at > p_since and coalesce(l.old_values, l.new_values) ? c.col) t
     where t.val is not null),
  regs as (select p.id, p.val as reg from parent p where p.table_name = 'aircraft')
  select x.section, x.key from (
    -- aircraft: its tail and its delivery; and its plan card when it was renamed
    select s.section, i.img ->> 'registration' as key from img i cross join unnest(array['tails', 'deliveries']) as s(section)
     where i.table_name = 'aircraft' and i.img ? 'registration'
    union all
    select 'plans', i.img ->> 'registration' from img i
     where i.table_name = 'aircraft' and i.img ? 'registration'
       and exists (select 1 from public.change_log l where l.world_id = p_world_id and l.table_name = 'aircraft' and l.row_key = i.row_key
                      and l.changed_at > p_since and l.op = 'update' and l.new_values ? 'registration')
    union all
    select 'freqs', i.img ->> 'legacy_key' from img i where i.table_name = 'rotations' and i.img ? 'legacy_key'
    union all
    select 'freqs', p.val from img i join parent p on p.table_name = 'rotations' and p.id = (i.img ->> 'rotation_id')::bigint
     where i.table_name = 'flight_legs' and i.img ? 'rotation_id'
    union all
    select s.section, n.planner_name || '|' || (i.img ->> 'hub_code') || '|' || (i.img ->> 'dest_code')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
      cross join unnest(array['routesAdded', 'routeEdits', 'routeCabin']) as s(section)
     where i.table_name = 'routes' and i.img ?& array['airline_id', 'hub_code', 'dest_code']
    union all
    select 'plans', r.reg from img i join regs r on r.id = (i.img ->> 'aircraft_id')::bigint
     where i.table_name = 'plan_cards' and i.img ? 'aircraft_id'
    union all
    select 'plans', r.reg from img i
      join parent p on p.table_name = 'plan_cards' and p.id = (i.img ->> 'plan_card_id')::bigint
      join regs r on r.id = p.val::bigint
     where i.table_name = 'plan_card_legs' and i.img ? 'plan_card_id'
    union all
    select 'todos', i.img ->> 'legacy_key' from img i where i.table_name = 'todos' and i.img ? 'legacy_key'
    union all
    select 'todos', p.val from img i join parent p on p.table_name = 'todos' and p.id = (i.img ->> 'todo_id')::bigint
     where i.table_name = 'todo_items' and i.img ? 'todo_id'
    union all
    select 'farePlan', i.img ->> 'legacy_key' from img i where i.table_name = 'fare_plan' and i.img ? 'legacy_key'
    union all
    select 'growthLog', private.growth_key(n.planner_name, (i.img ->> 'logged_on')::date, i.img ->> 'move', i.img ->> 'note')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'growth_log' and i.img ?& array['airline_id', 'logged_on', 'move']
    union all
    select 'capex', private.capex_key(n.planner_name, (i.img ->> 'spent_on')::date, i.img ->> 'kind', (i.img ->> 'amount')::numeric, i.img ->> 'note')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'spending_log' and i.img ?& array['airline_id', 'spent_on', 'kind', 'amount']
    union all
    select 'interline', n.planner_name || '|' || (i.img ->> 'country_code')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'interline_agreements' and i.img ?& array['airline_id', 'country_code']
    union all
    select 'monthly', coalesce(n.planner_name, 'Equinox') || '|' || (i.img ->> 'task')
      from img i left join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'monthly_checks' and i.img ?& array['airline_id', 'task']
    union all
    select 'dismissed', i.img ->> 'alert_key' from img i where i.table_name = 'dismissals' and i.img ? 'alert_key'
    union all
    select 'cabinKeep', r.reg || '|' || (i.img ->> 'cabin') from img i join regs r on r.id = (i.img ->> 'aircraft_id')::bigint
     where i.table_name = 'aircraft_cabin_keeps' and i.img ?& array['aircraft_id', 'cabin']
    union all
    select s.section, (i.img ->> 'day') || '|' || n.planner_name
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint cross join unnest(array['cash', 'fixed7']) as s(section)
     where i.table_name = 'cash_entries' and i.img ?& array['airline_id', 'day']
    union all
    select 'ref.hubs', n.planner_name || '|' || (i.img ->> 'airport_code')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'airline_bases' and i.img ?& array['airline_id', 'airport_code']
    union all
    select s.section, i.img ->> 'airport_code' from img i cross join unnest(array['ref.curfews', 'ref.utcOverrides']) as s(section)
     where i.table_name = 'world_airports' and i.img ? 'airport_code'
    union all
    select 'ref.hubs', n.planner_name || '|' || b.airport_code
      from img i join public.airline_bases b on b.world_id = p_world_id and b.airport_code = i.img ->> 'airport_code'
      join names n on n.id = b.airline_id
     where i.table_name = 'world_airports'
    union all
    select 'ref.types', i.img ->> 'name' from img i where i.table_name = 'aircraft_types' and i.img ? 'name'
    union all
    select 'ref.configs', i.img ->> 'code' from img i where i.table_name = 'cabin_configs' and i.img ? 'code'
    union all
    select 'ref.services', i.img ->> 'code' from img i where i.table_name = 'service_profiles' and i.img ? 'code'
    union all
    select 'ref.markets', n.planner_name || '|' || (i.img ->> 'name')
      from img i join names n on n.id = (i.img ->> 'airline_id')::bigint
     where i.table_name = 'markets' and i.img ?& array['airline_id', 'name']
    union all
    select case when i.img ->> 'key' = 'planner_time_mode' then 'ref.timeMode' else 'ref.consts' end, m.k
      from img i join (values ('buf', 'bank_buffer_min'), ('ovh', 'block_allowance_min'), ('arrwin', 'bank_arrival_window_min'),
                              ('depwin', 'bank_departure_window_min'), ('maxWait', 'connection_max_wait_h'), ('legalGap', 'legal_gap_h'),
                              ('turnMargin', 'turn_margin_min'), ('maintMinGround', 'maint_min_ground_min'),
                              ('leeway', 'load_leeway_days'), ('lfWindow', 'load_window_days'), ('', 'planner_time_mode')) as m(k, setting)
        on m.setting = i.img ->> 'key'
     where i.table_name = 'settings' and i.img ? 'key' and i.img -> 'airline_id' = 'null'::jsonb
    union all
    select 'ref.consts', 'depCap' from img i where i.table_name = 'world_rules' and i.img ->> 'key' = 'departures_per_airport_week'
    union all
    select 'ref.gameLinks', i.img ->> 'planner_name' from img i where i.table_name = 'airlines' and i.img ? 'planner_name'
  ) x
   where x.key is not null
$function$

;

-- private.research_apply(p_world_id bigint, p_doc jsonb)
CREATE OR REPLACE FUNCTION private.research_apply(p_world_id bigint, p_doc jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := p_world_id; d jsonb := p_doc; n int; v_out jsonb := '{}'::jsonb; v_held text[];
begin
  if jsonb_typeof(d) is distinct from 'object' then return v_out; end if;

  -- countries: added or renamed (none removed: airports, airlines and interline point at them)
  if jsonb_typeof(d -> 'countries') = 'object' then
    insert into public.countries as c (code, name)
    select e.key, e.value #>> '{}' from jsonb_each(d -> 'countries') e where jsonb_typeof(e.value) = 'string'
    on conflict (code) do update set name = excluded.name where c.name is distinct from excluded.name;
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('countries', n);
  end if;

  -- airports: city, country and position from coords (none removed: the tables point at them)
  if jsonb_typeof(d -> 'coords') = 'object' then
    with src as (
      select e.key as code, e.value ->> 2 as city, e.value ->> 3 as cc,
             private.json_num(e.value -> 0) as lat, private.json_num(e.value -> 1) as lon
        from jsonb_each(d -> 'coords') e where jsonb_typeof(e.value) = 'array' and e.key <> '')
    insert into public.airports as a (code, city, country_code, lat, lon)
    select src.code, src.city, (select x.code from public.countries x where x.code = src.cc),
           case when abs(src.lat) <= 90 then round(src.lat, 5) end, case when abs(src.lon) <= 180 then round(src.lon, 5) end
      from src
    on conflict (code) do update set city = excluded.city, country_code = excluded.country_code, lat = excluded.lat, lon = excluded.lon
    where (a.city, a.country_code, a.lat, a.lon) is distinct from (excluded.city, excluded.country_code, excluded.lat, excluded.lon);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('airports', n);
  end if;

  -- airports: UTC offsets. Flights and plan-card legs are stored in UTC, worked out with the offset they were typed
  -- under, so a new offset for an airport they use (without the world's own correction) would move them on screen.
  -- Design §4: the game is right and the legs are re-timed in a one-off fix, so such an offset is held back and named.
  if jsonb_typeof(d -> 'utc') = 'object' then
    if to_regclass('pg_temp.t_research_utc') is null then
      create temporary table t_research_utc (code text primary key, off numeric(4,2)) on commit drop;
    end if;
    truncate pg_temp.t_research_utc;
    -- the offset as private.json_num() reads it (a number, or digits in a string), worked out in line for speed
    insert into pg_temp.t_research_utc (code, off)
    select e.key, case when abs(n.off) <= 14 then round(n.off, 2) end
      from jsonb_each(d -> 'utc') e
      cross join lateral (
        select case jsonb_typeof(e.value) when 'number' then (e.value #>> '{}')::numeric
                 when 'string' then case when (e.value #>> '{}') ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(e.value #>> '{}')::numeric end end as off) n
     where e.key <> '';
    with changed as materialized (
      select u.code from pg_temp.t_research_utc u join public.airports a on a.code = u.code
       where a.utc_offset is distinct from u.off)
    select array_agg(c.code order by c.code) into v_held
      from changed c
     where exists (select 1 from public.flight_legs l
                    where (l.origin_code = c.code or l.dest_code = c.code)
                      and not exists (select 1 from public.world_airports x where x.world_id = l.world_id and x.airport_code = c.code
                                                                             and x.utc_offset_override is not null))
        or exists (select 1 from public.plan_card_legs l
                    where (l.origin_code = c.code or l.dest_code = c.code)
                      and not exists (select 1 from public.world_airports x where x.world_id = l.world_id and x.airport_code = c.code
                                                                             and x.utc_offset_override is not null));
    insert into public.airports as a (code, utc_offset)
    select u.code, u.off from pg_temp.t_research_utc u where u.code <> all (coalesce(v_held, '{}'))
    on conflict (code) do update set utc_offset = excluded.utc_offset where a.utc_offset is distinct from excluded.utc_offset;
    get diagnostics n = row_count;
    v_out := v_out || jsonb_build_object('utc offsets', n, 'utc offsets held back', to_jsonb(coalesce(v_held, '{}')));
  end if;

  -- routes: the research's own figures on research routes (a route added in the planner keeps its own, and the
  -- planner's overrides are never touched); a research route the research no longer lists goes, unless it carries an
  -- edit or a cabin, or a frequency, fare plan or flown flight points at it
  if jsonb_typeof(d -> 'routes') = 'array' then
    -- every airport a route names, by its code only, so no route is refused
    insert into public.airports (code)
    select distinct v ->> i from jsonb_array_elements(d -> 'routes') v, generate_series(1, 2) i
     where jsonb_typeof(v) = 'array' and (v ->> i) ~ '^[A-Z0-9]{3,4}$'
    on conflict (code) do nothing;
    if to_regclass('pg_temp.t_research_routes') is null then
      create temporary table t_research_routes (airline_id bigint, hub text, dest text, ord bigint, city text,
        country_label text, distance_km int, market text, stars smallint, primary key (airline_id, hub, dest)) on commit drop;
    end if;
    truncate pg_temp.t_research_routes;
    -- one entry per route: the first the research lists. Distance and stars are whole numbers, as private.json_int()
    -- reads them (a number, or digits in a string), worked out here in line: the function call per row took over a
    -- second for the 4,400 routes
    insert into pg_temp.t_research_routes (airline_id, hub, dest, ord, city, country_label, distance_km, market, stars)
    select distinct on (al.id, e.v ->> 1, e.v ->> 2) al.id, e.v ->> 1, e.v ->> 2, e.ord, e.v ->> 3, e.v ->> 4,
           case when n.dist = trunc(n.dist) and abs(n.dist) < 2000000000 then n.dist::int end, e.v ->> 6,
           case when n.stars = trunc(n.stars) and abs(n.stars) < 32000 then n.stars::smallint end
      from jsonb_array_elements(d -> 'routes') with ordinality as e(v, ord)
      join public.airlines al on al.world_id = w and al.planner_name = e.v ->> 0
      cross join lateral (
        select case jsonb_typeof(e.v -> 5) when 'number' then (e.v ->> 5)::numeric
                 when 'string' then case when (e.v ->> 5) ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(e.v ->> 5)::numeric end end as dist,
               case jsonb_typeof(e.v -> 7) when 'number' then (e.v ->> 7)::numeric
                 when 'string' then case when (e.v ->> 7) ~ '^\s*-?\d+(\.\d+)?\s*$' then btrim(e.v ->> 7)::numeric end end as stars) n
     where jsonb_typeof(e.v) = 'array'
       and exists (select 1 from public.airports a where a.code = e.v ->> 1)
       and exists (select 1 from public.airports a where a.code = e.v ->> 2)
     order by al.id, e.v ->> 1, e.v ->> 2, e.ord;
    insert into public.routes as x (world_id, airline_id, hub_code, dest_code, city, country_label, distance_km, market_id, stars, source)
    select w, r.airline_id, r.hub, r.dest, r.city, r.country_label, r.distance_km,
           (select m.id from public.markets m where m.airline_id = r.airline_id and m.name = r.market),
           r.stars, 'research'
      from pg_temp.t_research_routes r order by r.ord
    on conflict (airline_id, hub_code, dest_code) do update set city = excluded.city, country_label = excluded.country_label,
      distance_km = excluded.distance_km, market_id = excluded.market_id, stars = excluded.stars
    where x.source = 'research'
      and (x.city, x.country_label, x.distance_km, x.market_id, x.stars)
          is distinct from (excluded.city, excluded.country_label, excluded.distance_km, excluded.market_id, excluded.stars);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes', n);
    delete from public.routes x
     where x.world_id = w and x.source = 'research'
       and not exists (select 1 from pg_temp.t_research_routes r where r.airline_id = x.airline_id and r.hub = x.hub_code and r.dest = x.dest_code)
       and not x.removed and x.removed_note is null and x.city_override is null and x.distance_override_km is null
       and x.market_override_id is null and not x.market_cleared and x.stars_override is null and not x.edit_kept
       and x.cabin_choice is null
       and not exists (select 1 from public.rotations o where o.route_id = x.id)
       and not exists (select 1 from public.fare_plan o where o.route_id = x.id)
       and not exists (select 1 from public.game_flights o where o.route_id = x.id);
    get diagnostics n = row_count; v_out := v_out || jsonb_build_object('routes removed', n);
  end if;
  return v_out;
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

-- private.rules_input_doc(p_world_id bigint)
CREATE OR REPLACE FUNCTION private.rules_input_doc(p_world_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$
;

-- private.scan_airline(p_world_id bigint, p_game_id integer, p_name text)
CREATE OR REPLACE FUNCTION private.scan_airline(p_world_id bigint, p_game_id integer, p_name text)
 RETURNS bigint
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_id bigint; v_name text := nullif(btrim(p_name), '');
begin
  if p_game_id is null then return null; end if;
  select a.id into v_id from public.airlines a where a.world_id = p_world_id and a.game_id = p_game_id;
  if v_id is null then
    insert into public.airlines (world_id, game_id, game_name) values (p_world_id, p_game_id, v_name)
    on conflict (world_id, game_id) do nothing
    returning id into v_id;
    if v_id is null then
      select a.id into v_id from public.airlines a where a.world_id = p_world_id and a.game_id = p_game_id;
    end if;
  elsif v_name is not null then
    update public.airlines a set game_name = v_name
     where a.id = v_id and a.game_name is distinct from v_name
       and not exists (select 1 from public.groups g where g.id = a.group_id and g.kind = 'ours');
  end if;
  return v_id;
end
$function$

;

-- private.scan_summarise(p_scan_id bigint)
CREATE OR REPLACE FUNCTION private.scan_summarise(p_scan_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare n int := 0;
begin
  if not exists (select 1 from public.game_scan_schedules s where s.scan_id = p_scan_id) then return 0; end if;
  delete from public.scan_airline_airports where scan_id = p_scan_id;
  insert into public.scan_airline_airports (scan_id, world_id, airline_id, airport_code, weekly_departures, destinations)
  select s.scan_id, s.world_id, s.airline_id, f ->> 2,
         sum(length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')))::int,
         count(distinct nullif(f ->> 3, ''))::int
    from public.game_scan_schedules s
    cross join lateral jsonb_array_elements(case when jsonb_typeof(s.flights) = 'array' then s.flights else '[]'::jsonb end) f
   where s.scan_id = p_scan_id and jsonb_typeof(f) = 'array' and coalesce(f ->> 2, '') <> ''
     and regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g') <> ''
   group by s.scan_id, s.world_id, s.airline_id, f ->> 2;
  get diagnostics n = row_count;
  return n;
end
$function$

;

-- private.schedule_jobs()
CREATE OR REPLACE FUNCTION private.schedule_jobs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  perform cron.schedule('equinox-snapshot-fallback', '0 10 * * *', 'select private.job_snapshot_fallback()');
  perform cron.schedule('equinox-cleanup', '20 10 * * *', 'select private.job_cleanup()');
  return (select jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'command', j.command, 'active', j.active)
                           order by j.jobname)
            from cron.job j where j.jobname like 'equinox-%');
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

-- private.snapshot_due(p_world_id bigint, p_day date, p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.snapshot_due(p_world_id bigint, p_day date, p_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  span as (
    select private.capture_day_start(p_world_id, p_day) as from_at,
           (select max(d.taken_at) from public.airline_days d
             where d.world_id = p_world_id and d.day = p_day and d.source = 'capture') as last_at)
  select exists (select 1 from ours)
     and not exists (
       select 1 from ours o, span
        where (select count(distinct r.kind) from public.game_capture_raw r
                where r.airline_id = o.id and r.kind in ('statement', 'events', 'pnl', 'balance', 'loads')
                  and r.captured_at >= span.from_at and r.captured_at < span.from_at + interval '1 day'
                  and (span.last_at is null or r.captured_at > span.last_at) and r.captured_at <= p_at) < 5)
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

-- private.take_snapshot(p_world_id bigint, p_day date, p_at timestamp with time zone, p_source text, p_flows boolean)
CREATE OR REPLACE FUNCTION private.take_snapshot(p_world_id bigint, p_day date, p_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source text DEFAULT 'capture'::text, p_flows boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_at timestamptz := coalesce(p_at, now()); v_complete boolean; n int; v_flows jsonb;
begin
  if p_source is null or p_source not in ('capture', 'fallback', 'backfill') then
    raise exception 'take_snapshot: source must be capture, fallback or backfill, not %', coalesce(p_source, 'null');
  end if;
  v_complete := private.capture_day_complete(p_world_id, p_day);
  insert into public.airline_days as x (world_id, airline_id, day, complete, source, taken_at, aircraft_by_type,
         aircraft_total, on_order, weekly_departures, weekly_seats, destinations, cash, fixed_next7, cash_at)
  select p_world_id, a.id, p_day, v_complete, p_source, v_at, coalesce(f.aircraft_by_type, '{}'::jsonb),
         coalesce(f.aircraft_total, 0), coalesce(f.on_order, 0), coalesce(s.weekly_departures, 0),
         coalesce(s.weekly_seats, 0), coalesce(s.destinations, 0), c.cash, c.fixed_next7, c.cash_at
    from public.airlines a
    join public.groups g on g.id = a.group_id and g.world_id = a.world_id
    left join private.history_fleet(p_world_id, v_at) f on f.airline_id = a.id
    left join private.history_schedule(p_world_id, p_day) s on s.airline_id = a.id
    left join private.history_cash(p_world_id, p_day, v_at) c on c.airline_id = a.id
   where a.world_id = p_world_id and a.active and g.kind = 'ours' and (a.founded_on is null or a.founded_on <= p_day)
  on conflict (airline_id, day) do update set
    complete = excluded.complete, source = excluded.source, taken_at = excluded.taken_at,
    aircraft_by_type = excluded.aircraft_by_type, aircraft_total = excluded.aircraft_total, on_order = excluded.on_order,
    weekly_departures = excluded.weekly_departures, weekly_seats = excluded.weekly_seats,
    destinations = excluded.destinations, cash = excluded.cash, fixed_next7 = excluded.fixed_next7, cash_at = excluded.cash_at
  where x.source <> 'capture' or excluded.source = 'capture';
  get diagnostics n = row_count;
  if p_flows then v_flows := private.history_flows(p_world_id, p_day - 2, p_day); end if;
  return jsonb_build_object('day', p_day, 'source', p_source, 'complete', v_complete, 'at', v_at, 'airlines', n)
         || coalesce(v_flows, '{}'::jsonb);
end
$function$

;

-- private.unfreeze_planner_state()
CREATE OR REPLACE FUNCTION private.unfreeze_planner_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare w bigint := (select x.id from public.worlds x where x.is_default);
  v_since text := coalesce(private.planner_frozen_since('public.planner_state'::regclass),
                           private.planner_frozen_since('public.planner_loads'::regclass));
  g jsonb; n_months int;
begin
  -- no planner save or item put runs meanwhile
  perform pg_advisory_xact_lock(hashtextextended('equinox planner world', w));
  drop trigger if exists planner_frozen on public.planner_state;
  drop trigger if exists planner_frozen on public.planner_loads;
  g := public.planner_state_get(w);
  insert into public.planner_state (id, json, saved_at) values ('main', g ->> 'json', (g ->> 'saved_at')::bigint)
  on conflict (id) do update set json = excluded.json, saved_at = excluded.saved_at;
  insert into public.planner_loads (month, json, saved_at)
  select l.month, l.json, l.saved_at from public.planner_loads_get(w) l
  on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
  get diagnostics n_months = row_count;
  grant insert, update on table public.planner_state to authenticated;
  -- the side by side again (after the writes above, so they aren't copied back)
  if not exists (select 1 from pg_catalog.pg_trigger x where x.tgrelid = 'public.planner_state'::regclass and x.tgname = 'adapter_mirror') then
    create constraint trigger adapter_mirror after insert or update on public.planner_state
      deferrable initially deferred for each row execute function private.adapter_mirror_state();
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger x where x.tgrelid = 'public.planner_loads'::regclass and x.tgname = 'adapter_mirror') then
    create constraint trigger adapter_mirror after insert or update on public.planner_loads
      deferrable initially deferred for each row execute function private.adapter_mirror_loads();
  end if;
  return jsonb_build_object('was_frozen_since', v_since, 'planner_state_saved_at', (g ->> 'saved_at')::bigint,
                            'planner_loads_months', n_months, 'side_by_side', 'on',
                            'next', 'revert the switch-over''s pull request, then reload every open planner tab');
end
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
-- private.world_mct_set(p_world_id bigint, p_mct jsonb)
CREATE OR REPLACE FUNCTION private.world_mct_set(p_world_id bigint, p_mct jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare bad text; n_set int; n_cleared int; n_gone int; v_cleared text[];
begin
  if jsonb_typeof(p_mct) is distinct from 'object' then
    raise exception 'mct must be an object of airport code: minutes' using errcode = '22023';
  end if;
  select string_agg(e.key, ', ' order by e.key) into bad from jsonb_each(p_mct) e
   where e.key !~ '^[A-Z0-9]{3,4}$' or private.json_int(e.value) is null or private.json_int(e.value) not between 0 and 1440;
  if bad is not null then
    raise exception 'mct: not an airport code with whole minutes (0 to 1440): %', bad using errcode = '22023';
  end if;
  insert into public.airports (code) select e.key from jsonb_each(p_mct) e on conflict (code) do nothing;
  insert into public.world_airports as x (world_id, airport_code, mct_min)
  select p_world_id, e.key, private.json_int(e.value)::smallint from jsonb_each(p_mct) e
  on conflict (world_id, airport_code) do update set mct_min = excluded.mct_min where x.mct_min is distinct from excluded.mct_min;
  get diagnostics n_set = row_count;
  with c as (
    update public.world_airports x set mct_min = null
     where x.world_id = p_world_id and x.mct_min is not null and not (p_mct ? x.airport_code)
    returning x.airport_code)
  select array_agg(c.airport_code), count(*) into v_cleared, n_cleared from c;
  delete from public.world_airports x
   where x.world_id = p_world_id and x.airport_code = any (coalesce(v_cleared, '{}'))
     and x.mct_min is null and x.night_ban_from is null and x.night_ban_to is null and x.utc_offset_override is null
     and x.game_airport_id is null and not x.closed and x.note is null
     and not exists (select 1 from public.airline_bases b where b.world_id = p_world_id and b.airport_code = x.airport_code);
  get diagnostics n_gone = row_count;
  return jsonb_build_object('set', n_set, 'cleared', n_cleared, 'removed', n_gone);
end
$function$
;

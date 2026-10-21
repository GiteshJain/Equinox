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
                            'span_days', d -> 'span_days', 'early', d -> 'early',
                            'days', (select coalesce(jsonb_agg(x || jsonb_build_object('per_aircraft_day',
                                              case when coalesce((x ->> 'aircraft')::int, 0) <> 0
                                                   then (x ->> 'profit_day')::numeric / (x ->> 'aircraft')::int end) order by i), '[]'::jsonb)
                                       from jsonb_array_elements(d -> 'days') with ordinality as e(x, i)));
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
declare v_world bigint; v_res jsonb;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'html') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', 'capture', true);
  v_res := private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
  -- the capture panel prints rows (or error) after "<airline> · loads ": after the loads page, the airline's verdict goes
  -- there (#21), so the userscript needs no change; the count stays under count
  if p_kind = 'loads' and v_res ? 'airline_verdict' then
    v_res := v_res || jsonb_build_object('count', coalesce(v_res -> 'rows', '0'::jsonb), 'rows', private.capture_panel_words(v_res));
  end if;
  return v_res;
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

-- cash_log(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.cash_log(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_cash_log(private.fig_world(p_world_id), coalesce(p_as_of, now()));
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
 SET statement_timeout TO '30s'
AS $function$
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
$function$

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

-- fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_fare_ladder(p_airline_id, coalesce(p_as_of, now()));
end
$function$

;

-- fare_plan_status(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.fare_plan_status(p_airline_id bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_fare_plan(p_airline_id, coalesce(p_as_of, now()));
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

-- loads_by_day(p_world_id bigint, p_from date, p_to date)
CREATE OR REPLACE FUNCTION public.loads_by_day(p_world_id bigint, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the planner' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then
    raise exception 'loads_by_day: from and to are dates, to on or after from, at most 62 days apart' using errcode = '22023';
  end if;
  w := private.fig_world(p_world_id);
  return (
    with ours as (
      select a.id, a.planner_name from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
       where a.world_id = w and g.kind = 'ours'),
    vals as (select v.* from private.fig_load_values(w, now(), p_from, p_to) v),
    days as (select d.* from private.fig_load_days(w, now(), p_from, p_to) d)
    select coalesce(jsonb_object_agg(d.day::text,
             jsonb_build_object(
               -- the day as the old planner's loads document held it: done (the one rule, design §8, unless a flag typed
               -- after the day's last capture says otherwise) and each flight's economy load (captured or typed, the latest)
               'done', coalesce(d.done, false),
               'f', coalesce((select jsonb_object_agg(o.planner_name || '|' || v.flight_no, v.v)
                                from vals v join ours o on o.id = v.airline_id
                               where v.day = d.day and v.v is not null and o.planner_name is not null), '{}'::jsonb),
               -- the typed rows behind it, with the updated_at a save changes them from
               'entries', coalesce((select jsonb_agg(jsonb_build_object('airline_id', e.airline_id, 'flight_no', e.flight_no,
                                                                        'eco_pct', trim_scale(e.eco_pct), 'updated_at', e.updated_at)
                                                     order by e.airline_id, e.flight_no)
                                      from public.load_entries e join ours o on o.id = e.airline_id
                                     where e.world_id = w and e.game_date = d.day), '[]'::jsonb),
               'flags', (select jsonb_build_object('done', ld.done, 'saved_at_ms', ld.saved_at_ms, 'updated_at', ld.updated_at)
                           from public.load_days ld where ld.world_id = w and ld.game_date = d.day))
             || case when d.captured then jsonb_build_object('source', 'capture') else '{}'::jsonb end
             || coalesce((select jsonb_build_object('savedAt', ld.saved_at_ms) from public.load_days ld
                           where ld.world_id = w and ld.game_date = d.day and ld.saved_at_ms is not null), '{}'::jsonb)),
             '{}'::jsonb)
      from days d);
end
$function$

;

-- order_cabin(p_airline_id bigint, p_type_id bigint)
CREATE OR REPLACE FUNCTION public.order_cabin(p_airline_id bigint, p_type_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the planner' using errcode = '42501'; end if;
  v_id := private.fig_order_cabin(p_airline_id, p_type_id);
  return (select jsonb_build_object('id', c.id, 'code', c.code, 'cabin', c.cabin, 'cost', c.cost, 'aircraft_type_id', c.aircraft_type_id)
            from public.cabin_configs c where c.id = v_id);
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
  -- only the route research is kept, in its own tables: the old planner's planner_data went with it (the clean-up)
  if p_key is distinct from 'DATA' then
    raise exception 'planner_data_set: only key DATA (the route research) is kept since the clean-up (build pull request 14)' using errcode = '22023';
  end if;
  -- the change log names the script, unless the caller named itself (design §6)
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'planner_data_set'), true);
  select x.id into w from public.worlds x where x.is_default;
  v_tables := private.research_apply(w, p_value);
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return jsonb_build_object('ok', true, 'bytes', length(p_value::text))
         || case when v_tables is null then '{}'::jsonb else jsonb_build_object('tables', v_tables) end;
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
  -- the 33 planner tables, each with the change-log trigger (migration 20261009210000_planner_tables.sql, §4; the 33rd,
  -- airline_order_cabins, 20261015220000_last_leftovers.sql)
  v_tables constant text[] := array[
    'worlds', 'groups', 'airlines', 'airline_bases', 'airline_aircraft_types',
    'countries', 'airports', 'world_airports',
    'aircraft_types', 'cabin_configs', 'aircraft', 'aircraft_cabin_keeps',
    'markets', 'service_profiles', 'routes', 'rotations', 'flight_legs',
    'plan_cards', 'plan_card_legs',
    'todos', 'todo_items', 'growth_log', 'spending_log', 'fare_plan', 'interline_agreements', 'monthly_checks',
    'dismissals', 'cash_entries', 'load_entries', 'load_days',
    'settings', 'world_rules', 'airline_order_cabins'];
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
      raise exception 'planner_save: change %: % isn''t one of the planner''s tables (only the 33 the change log covers)',
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
$function$

;

-- route_loads(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.route_loads(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_route_loads(private.fig_world(p_world_id), coalesce(p_as_of, now()));
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
declare d jsonb; a jsonb; v_in numeric; v_out numeric;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_route_profit(p_airline_id, p_days, coalesce(p_as_of, now())) - 'aircraft' - 'fare_changes';
  a := d -> 'average_flight';
  if jsonb_typeof(a) = 'object' then
    v_in := coalesce((a ->> 'passengers')::numeric, 0) + coalesce((a ->> 'cargo')::numeric, 0);
    v_out := coalesce((a ->> 'fuel')::numeric, 0) + coalesce((a ->> 'handling')::numeric, 0) + coalesce((a ->> 'onboard')::numeric, 0)
           + coalesce((a ->> 'landing')::numeric, 0) + coalesce((a ->> 'air_traffic')::numeric, 0) + coalesce((a ->> 'maintenance')::numeric, 0);
    d := jsonb_set(d, '{average_flight}', a || jsonb_build_object('income', v_in, 'costs', v_out, 'profit', v_in - v_out,
                                                                   'margin', case when v_in <> 0 then (v_in - v_out) / v_in end));
  end if;
  return d;
end
$function$

;

-- rules_input(p_world_id bigint, p_routes text)
CREATE OR REPLACE FUNCTION public.rules_input(p_world_id bigint DEFAULT NULL::bigint, p_routes text DEFAULT 'all'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then
    raise exception 'only planner staff can read the planning rules' using errcode = '42501';
  end if;
  return private.rules_input_doc(p_world_id, p_routes);
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
declare h text; w bigint; v_cash jsonb; v_fixed jsonb;
begin
  select r.pass_hash into h from public.report_access r limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then return jsonb_build_object('ok', false); end if;
  select x.id into w from public.worlds x where x.is_default;
  -- cash and next-7-day costs by date and airline, in millions (design §8): the capture's figure unless a cash_entries row
  -- says otherwise, rounded as the planner rounds (to 0.01M); next-7-day costs only when above zero. As the old planner's
  -- document had them (until the clean-up, build pull request 14, through planner_state_get())
  with pairs as (
    select coalesce(e.airline_id, cc.airline_id) as airline_id, coalesce(e.day, cc.day) as day,
           coalesce(e.cash / 1000000, floor(cc.cash / 10000 + 0.5) / 100) as cash_m,
           coalesce(e.fixed_next7, cc.fixed_next7) as fixed_raw,
           e.fixed_next7 is not null as fixed_typed
      from (select * from public.cash_entries x where x.world_id = w) e
      full join (select * from public.capture_cash x where x.world_id = w) cc on cc.airline_id = e.airline_id and cc.day = e.day),
  named as (
    select al.planner_name, p.day::text as day, trim_scale(p.cash_m) as cash_m,
           case when p.fixed_raw > 0 then trim_scale(case when p.fixed_typed then p.fixed_raw / 1000000
                                                          else floor(p.fixed_raw / 10000 + 0.5) / 100 end) end as fixed_m
      from pairs p join public.airlines al on al.id = p.airline_id)
  select (select coalesce(jsonb_object_agg(x.day, x.v), '{}'::jsonb)
            from (select n.day, jsonb_object_agg(n.planner_name, n.cash_m) as v from named n where n.cash_m is not null group by n.day) x),
         (select coalesce(jsonb_object_agg(x.day, x.v), '{}'::jsonb)
            from (select n.day, jsonb_object_agg(n.planner_name, n.fixed_m) as v from named n where n.fixed_m is not null group by n.day) x)
    into v_cash, v_fixed;
  return jsonb_build_object('ok', true, 'cash', v_cash, 'fixed7', v_fixed,
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
  -- each frequency with its local times (design §4), in its order
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
  -- each aircraft flying (status active), in the order it was added, as the planner's Tails lists it
  tails as (
    select a.id,
           jsonb_strip_nulls(jsonb_build_object('id', a.registration, 'airline', al.planner_name, 'type', coalesce(t.name, '')))
           || coalesce(a.extra -> 'tail', '{}'::jsonb) as j
      from w
      join public.aircraft a on a.world_id = w.id and a.status = 'active'
      join public.airlines al on al.id = a.airline_id
      left join public.aircraft_types t on t.id = a.aircraft_type_id)
  select jsonb_build_object(
    -- when the planner's data last changed: its latest logged change in the world, or to airports and countries
    -- (which carry no world), to the millisecond
    'updated_at', (select to_timestamp(floor(extract(epoch from greatest(
                              (select max(c.changed_at) from public.change_log c where c.world_id = w.id),
                              (select max(c.changed_at) from public.change_log c where c.world_id is null))) * 1000) / 1000.0)
                     from w),
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
                                        order by t.id), '[]'::jsonb) from tails t),
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

-- system_status(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION public.system_status(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_at timestamptz := coalesce(p_as_of, now()); v_month timestamptz; v_snap jsonb; v_job jsonb; v_fb timestamptz;
  v_backup jsonb; v_good jsonb; v_arch jsonb; v_clean jsonb; v_scan jsonb; v_db bigint; v_pdf bigint; v_site bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the systems board' using errcode = '42501'; end if;
  w := private.fig_world(p_world_id);
  v_month := date_trunc('month', v_at at time zone 'UTC') at time zone 'UTC';

  -- the daily snapshot: the latest capture day in the daily history, and how it was taken
  select jsonb_build_object('day', x.day, 'source', x.source, 'complete', x.complete, 'taken_at', private.fig_ts(x.taken_at), 'airlines', x.airlines)
    into v_snap
    from (select ad.day, string_agg(distinct ad.source, ', ') as source, bool_and(ad.complete) as complete, max(ad.taken_at) as taken_at,
                 count(*)::int as airlines
            from public.airline_days ad
           where ad.world_id = w and ad.taken_at <= v_at
           group by ad.day order by ad.day desc limit 1) x;
  select jsonb_build_object('job', j.job, 'status', j.status, 'at', private.fig_ts(j.started_at), 'note', left(j.note, 300))
    into v_job
    from public.job_runs j
   where j.job in ('snapshot', 'snapshot_fallback') and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;
  select max(j.started_at) into v_fb from public.job_runs j
   where j.job = 'snapshot_fallback' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at;

  -- the nightly backup: its latest run, and the latest good copy (a good run passed its restore check)
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'ok', b.ok, 'kind', b.kind, 'note', left(b.note, 300))
    into v_backup
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'bytes', b.bytes, 'tables', b.tables, 'rows', b.rows, 'files', b.files,
                            'object_key', b.object_key)
    into v_good
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ok and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;

  -- the monthly archive: its runs this month, its latest run, and any table and month whose latest run failed
  select jsonb_build_object(
           'last_at', private.fig_ts(max(j.started_at)),
           'month', (v_at at time zone 'UTC')::date - (extract(day from v_at at time zone 'UTC')::int - 1),
           'runs_this_month', count(*) filter (where j.started_at >= v_month),
           'ok_this_month', count(*) filter (where j.started_at >= v_month and j.status = 'ok'),
           'rows_this_month', coalesce(sum((j.details ->> 'rows')::bigint) filter (where j.started_at >= v_month and j.status = 'ok'), 0),
           'failed', coalesce((select jsonb_agg(jsonb_build_object('table', f.details ->> 'table', 'month', f.for_month, 'at', private.fig_ts(f.started_at),
                                                                   'note', left(f.note, 200)) order by f.started_at)
                                 from (select distinct on (x.details ->> 'table', x.for_month) x.*
                                         from public.job_runs x
                                        where x.job = 'archive' and x.started_at <= v_at and x.status <> 'running'
                                        order by x.details ->> 'table', x.for_month, x.started_at desc, x.id desc) f
                                where f.status = 'failed'), '[]'::jsonb))
    into v_arch
    from public.job_runs j where j.job = 'archive' and j.started_at <= v_at and j.status <> 'running';

  -- the clean-ups: the latest run
  select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
    into v_clean
    from public.job_runs j
   where j.job = 'cleanup' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;

  -- the world scan: the latest that has its airport summary (as hub_progress() reads it)
  select jsonb_build_object('taken_at', private.fig_ts(s.taken_at), 'week', s.week, 'status', s.status)
    into v_scan
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at and exists (select 1 from public.scan_airline_airports x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;

  -- usage the database can measure, each against its trigger (manual §1; #16, #17, #20): now, whatever the moment
  v_db := pg_database_size(current_database());
  select coalesce(sum(octet_length(r.pdf_b64)), 0) * 3 / 4 into v_pdf from public.site_reports r where r.pdf_b64 is not null;
  v_site := octet_length(public.site_public()::text);

  return jsonb_build_object(
    'world_id', w, 'as_of', private.fig_ts(v_at),
    'capture', private.fig_capture_status(w, v_at) -> 'airlines',
    'snapshot', coalesce(v_snap, '{}'::jsonb) || jsonb_build_object('last_run', v_job, 'fallback_at', private.fig_ts(v_fb)),
    'backup', jsonb_build_object('last', v_backup, 'last_good', v_good),
    'archive', v_arch,
    'cleanup', v_clean,
    'scan', v_scan,
    'usage', jsonb_build_array(
      jsonb_build_object('key', 'database', 'label', 'Database size', 'bytes', v_db, 'trigger_bytes', 350 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'report_pdfs', 'label', 'Report PDFs', 'bytes', v_pdf, 'trigger_bytes', 50 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'site_public', 'label', 'The website''s data', 'bytes', v_site, 'trigger_bytes', 500 * 1024::bigint)));
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

-- private.briefing_doc(p_airline_id bigint, p_as_of timestamp with time zone)
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

-- private.capture_airline_verdict(p_airline_id bigint, p_at timestamp with time zone)
CREATE OR REPLACE FUNCTION private.capture_airline_verdict(p_airline_id bigint, p_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with a as (select al.world_id, private.capture_day(al.world_id, p_at) as day from public.airlines al where al.id = p_airline_id),
  span as (select private.capture_day_start(a.world_id, a.day) as from_at from a),
  k as (select * from unnest(array['events', 'statement', 'pnl', 'balance', 'loads'],
                             array['events', 'statement', 'income statement', 'balance sheet', 'loads']) with ordinality as k(kind, label, o)),
  latest as (
    select distinct on (r.kind) r.kind, r.verdict, r.verdict_note, r.captured_at
      from public.game_capture_raw r, span
     where r.airline_id = p_airline_id and r.kind in ('events', 'statement', 'pnl', 'balance', 'loads')
       and r.captured_at >= span.from_at and r.captured_at <= p_at
     order by r.kind, r.captured_at desc, r.id desc),
  j as (select k.kind, k.label, k.o, l.verdict, l.verdict_note as note, l.captured_at from k left join latest l on l.kind = k.kind),
  v as (select case when bool_or(j.verdict = 'broken') then 'broken'
                    when bool_or(j.verdict = 'short') or bool_or(j.captured_at is null) then 'short'
                    when bool_or(j.verdict = 'ok') then 'ok' end as verdict
          from j)
  select jsonb_build_object(
    'capture_day', (select a.day from a),
    'at', private.fig_ts(max(j.captured_at)),
    'verdict', v.verdict,
    'words', case when v.verdict = 'ok' then 'all good'
                  when v.verdict is null then 'not checked (captured before the page checks)'
                  else v.verdict || ': ' || string_agg(case when j.captured_at is null then j.label || ' not captured'
                                                            when j.verdict in ('short', 'broken') then j.note end, '; ' order by j.o) end,
    'missing', coalesce(jsonb_agg(j.kind order by j.o) filter (where j.captured_at is null), '[]'::jsonb),
    'pages', jsonb_object_agg(j.kind, case when j.captured_at is not null
                                           then jsonb_build_object('verdict', j.verdict, 'note', j.note, 'at', private.fig_ts(j.captured_at)) end))
    from j, v
   group by v.verdict
$function$

;

-- private.capture_check(p_raw_id bigint, p_parse jsonb, p_expect jsonb)
CREATE OR REPLACE FUNCTION private.capture_check(p_raw_id bigint, p_parse jsonb, p_expect jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r record; v_err text; v_read int; v_cash boolean; v_exp jsonb; v_j jsonb; v_lmin numeric; v_smin numeric;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.rows, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found or r.kind not in ('statement', 'events', 'loads', 'pnl', 'balance') then return null; end if;
  v_err := case when coalesce((p_parse ->> 'ok')::boolean, false) then null else coalesce(p_parse ->> 'error', 'no answer from the reader') end;
  v_read := case when jsonb_typeof(p_parse -> 'rows') = 'number' then (p_parse ->> 'rows')::int end;
  v_exp := coalesce(p_expect, private.capture_expect(p_raw_id));
  if r.kind = 'balance' then
    -- the cash account as the reader takes it: account 2800 in a row's first or fourth cell, with a figure beside it
    v_cash := exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.rows) = 'array' then r.rows else '[]'::jsonb end) e(row_)
                       where jsonb_typeof(e.row_) = 'array'
                         and ((jsonb_array_length(e.row_) >= 3 and e.row_ ->> 0 = '2800' and public.as_num(e.row_ ->> 2) is not null)
                           or (jsonb_array_length(e.row_) >= 6 and e.row_ ->> 3 = '2800' and public.as_num(e.row_ ->> 5) is not null)));
  end if;
  select coalesce((select (s.value #>> '{}')::numeric from public.settings s
                    where s.world_id = r.world_id and s.airline_id is null and s.key = 'capture_loads_min_share'), 0.9),
         coalesce((select (s.value #>> '{}')::numeric from public.settings s
                    where s.world_id = r.world_id and s.airline_id is null and s.key = 'capture_statement_min_share'), 0.5)
    into v_lmin, v_smin;
  v_j := private.capture_judge(r.kind, v_read, v_err, v_cash, v_exp, v_lmin, v_smin);
  update public.game_capture_raw x set verdict = v_j ->> 'verdict', verdict_note = v_j ->> 'note', verdict_facts = v_j -> 'facts'
   where x.id = p_raw_id;
  return jsonb_build_object('kind', r.kind, 'verdict', v_j ->> 'verdict', 'note', v_j ->> 'note', 'at', private.fig_ts(r.captured_at))
         || (v_j -> 'facts');
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

-- private.capture_expect(p_raw_id bigint)
CREATE OR REPLACE FUNCTION private.capture_expect(p_raw_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare r record; v_from timestamptz; n int; v_med numeric; v_nights int; v_day date;
begin
  select x.id, x.world_id, x.airline_id, x.kind, x.captured_at into r from public.game_capture_raw x where x.id = p_raw_id;
  if not found then return '{}'::jsonb; end if;
  if r.kind = 'loads' then
    -- the page's window is the game's "-24h": the flights that departed in the 24 hours before the capture
    v_from := r.captured_at - interval '24 hours';
    -- the aircraft that have flown: each registration the airline's captured loads named before this page (a new
    -- aircraft counts from the first capture that shows it flying; on 15 Oct the aircraft filed 13 Oct hadn't flown yet)
    with flown as (
      select distinct f.registration from public.game_flights f
       where f.airline_id = r.airline_id and f.registration is not null and f.loads_captured_at < r.captured_at)
    select count(*)::int into n
      from public.flight_legs l
      join public.rotations ro on ro.id = l.rotation_id
      left join public.aircraft ac on ac.id = l.aircraft_id
     cross join lateral generate_series(date_trunc('day', v_from at time zone 'UTC'), date_trunc('day', r.captured_at at time zone 'UTC'),
                                        interval '1 day') d(day)
     cross join lateral (select (d.day + make_interval(mins => l.dep_utc_min::int)) at time zone 'UTC' as dep_at) x
     where l.airline_id = r.airline_id and l.dep_utc_min is not null
       and extract(isodow from d.day)::smallint = any (l.days_utc)
       -- a rotation counts from the day after it launched: an aircraft's first day is rarely flown in full (on 13 Oct,
       -- the day new aircraft were filed, none of their flights had flown by the evening's capture)
       and (ro.launched_on is null or ro.launched_on < d.day::date)
       and x.dep_at > v_from and x.dep_at <= r.captured_at
       -- a leg with an aircraft counts once that aircraft has flown; a leg with none counts as before
       and (l.aircraft_id is null or exists (select 1 from flown fl where fl.registration = ac.registration));
    return jsonb_build_object('scheduled', n, 'window_from', private.fig_ts(v_from), 'window_to', private.fig_ts(r.captured_at));
  elsif r.kind = 'statement' then
    v_day := private.capture_day(r.world_id, r.captured_at);
    with nights as (
      select distinct on (private.capture_day(p.world_id, p.captured_at)) private.capture_day(p.world_id, p.captured_at) as day,
             private.capture_statement_lines(p.rows) as lines
        from public.game_capture_raw p
       where p.airline_id = r.airline_id and p.kind = 'statement' and p.captured_at < r.captured_at
         and private.capture_day(p.world_id, p.captured_at) < v_day
       order by private.capture_day(p.world_id, p.captured_at) desc, p.captured_at desc, p.id desc),
    recent as (select n.lines from nights n order by n.day desc limit 7)
    select percentile_cont(0.5) within group (order by x.lines)::numeric, count(*)::int into v_med, v_nights from recent x;
    return jsonb_build_object('median_lines', round(v_med, 1), 'nights', v_nights);
  end if;
  return '{}'::jsonb;
end
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

-- private.capture_judge(p_kind text, p_read integer, p_error text, p_cash boolean, p_expect jsonb, p_loads_min numeric, p_statement_min numeric)
CREATE OR REPLACE FUNCTION private.capture_judge(p_kind text, p_read integer, p_error text, p_cash boolean, p_expect jsonb, p_loads_min numeric, p_statement_min numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v text := 'ok'; v_note text; v_exp numeric; v_label text; v_facts jsonb;
begin
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance') then return null; end if;
  v_label := case p_kind when 'pnl' then 'income statement' when 'balance' then 'balance sheet' else p_kind end;
  v_facts := coalesce(p_expect, '{}'::jsonb) || jsonb_build_object('read', p_read);
  if p_error is not null then
    return jsonb_build_object('verdict', 'broken', 'note', v_label || ' didn''t read (' || left(p_error, 160) || ')',
                              'facts', v_facts || jsonb_build_object('error', left(p_error, 300)));
  end if;
  if p_kind = 'loads' then
    v_exp := (p_expect ->> 'scheduled')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_loads_min,
                                             'share', case when v_exp > 0 then round(coalesce(p_read, 0) / v_exp, 3) end);
    if v_exp > 0 and coalesce(p_read, 0) < p_loads_min * v_exp then v := 'short'; end if;
    v_note := case when v_exp is null then format('loads %s flights', coalesce(p_read, 0))
                   when v_exp = 0 then format('loads %s flights, none scheduled', coalesce(p_read, 0))
                   else format('loads %s of %s flights', coalesce(p_read, 0), v_exp) end;
  elsif p_kind = 'statement' then
    v_exp := (p_expect ->> 'median_lines')::numeric;
    v_facts := v_facts || jsonb_build_object('min_share', p_statement_min);
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := 'statement: no lines';
    elsif v_exp > 0 and p_read < p_statement_min * v_exp then
      v := 'short'; v_note := format('statement %s line%s, usually about %s', p_read, case when p_read = 1 then '' else 's' end, round(v_exp));
    else
      v_note := format('statement %s line%s', p_read, case when p_read = 1 then '' else 's' end) || case when v_exp > 0 then format(' (usually about %s)', round(v_exp)) else '' end;
    end if;
  elsif p_kind = 'balance' then
    v_facts := v_facts || jsonb_build_object('cash', coalesce(p_cash, false));
    if not coalesce(p_cash, false) then
      v := 'broken'; v_note := 'balance sheet without the cash account (2800)';
    else
      v_note := format('balance sheet %s row%s, the cash account there', coalesce(p_read, 0), case when p_read = 1 then '' else 's' end);
    end if;
  else
    if coalesce(p_read, 0) = 0 then
      v := 'short'; v_note := v_label || ': no rows';
    else
      v_note := format('%s %s row%s', v_label, p_read, case when p_read = 1 then '' else 's' end);
    end if;
  end if;
  return jsonb_build_object('verdict', v, 'note', v_note, 'facts', v_facts);
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

-- private.capture_panel_words(p_reply jsonb)
CREATE OR REPLACE FUNCTION private.capture_panel_words(p_reply jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v jsonb := p_reply -> 'airline_verdict'; l jsonb := p_reply -> 'verdict'; v_first text; v_head text;
        v_parts text[] := '{}'; k text; p jsonb;
begin
  v_first := case when coalesce((p_reply ->> 'ok')::boolean, false) then coalesce(p_reply ->> 'rows', '0') || ' flights read'
                  else 'didn''t read (' || left(coalesce(p_reply ->> 'error', 'no answer'), 120) || ')' end;
  if v is null or jsonb_typeof(v) <> 'object' then return v_first; end if;
  v_head := case v ->> 'verdict' when 'ok' then 'all good' when 'short' then 'short' when 'broken' then 'broken' else 'not checked' end;
  foreach k in array array['events', 'statement', 'pnl', 'balance'] loop
    p := v -> 'pages' -> k;
    if p is null or jsonb_typeof(p) <> 'object' then
      v_parts := v_parts || (case k when 'pnl' then 'income statement' when 'balance' then 'balance sheet' else k end || ' not captured');
    elsif p ->> 'verdict' in ('short', 'broken') then
      v_parts := v_parts || (p ->> 'note');
    end if;
  end loop;
  v_parts := v_parts || case when l ->> 'verdict' = 'broken' then 'loads unreadable, 0 of ' || coalesce(l ->> 'scheduled', '?')
                             else format('loads %s of %s', coalesce(l ->> 'read', p_reply ->> 'rows', '0'), coalesce(l ->> 'scheduled', '?')) end;
  return v_first || E'\n' || coalesce(p_reply ->> 'airline', 'this airline') || ': ' || v_head || ' · ' || array_to_string(v_parts, ' · ');
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

-- private.capture_statement_lines(p_rows jsonb)
CREATE OR REPLACE FUNCTION private.capture_statement_lines(p_rows jsonb)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select count(*)::int
    from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else '[]'::jsonb end) e(row_)
   where jsonb_typeof(e.row_) = 'array'
     and (select c.x from jsonb_array_elements_text(e.row_) with ordinality c(x, o) where c.x <> '' order by c.o limit 1)
         ~ '^\d{2}\.\d{2}\. \d{2}:\d{2}'
$function$

;

-- private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean)
CREATE OR REPLACE FUNCTION private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_al bigint; v_name text; v_rid bigint; v_res jsonb; v_day date; v_complete boolean; v_snap jsonb;
  t0 timestamptz; v_check jsonb;
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
  exception when others then
    v_res := jsonb_build_object('ok', false, 'airline', v_name, 'error', 'parse: ' || sqlerrm, 'raw_id', v_rid);   -- the raw rows stay for inspection
  end;
  -- the page's check (#21): one verdict, kept on the raw page; a check that fails never loses the page
  begin
    v_check := private.capture_check(v_rid, v_res);
  exception when others then
    v_check := jsonb_build_object('kind', p_kind, 'verdict', null, 'note', 'the check failed: ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('verdict', v_check);
  -- the loads page is the airline's last: the reply also judges the airline's capture as it stands
  if p_kind = 'loads' then
    v_res := v_res || jsonb_build_object('airline_verdict', private.capture_airline_verdict(v_al, p_at));
  end if;
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

-- private.fig_airline_cards(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_airline_cards(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0 - 1) as flights_yesterday,
           -- the airline's latest page of any kind by the moment, whenever it was (#21, #23)
           (select max(r.captured_at) from public.game_capture_raw r
             where r.airline_id = al.airline_id and r.kind in ('statement', 'events', 'loads', 'pnl', 'balance') and r.captured_at <= p_as_of) as last_at
      from al, d),
  judged as (select r.*, case when r.last_at is not null then private.capture_airline_verdict(r.airline_id, r.last_at) end as v from rows_ r)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'today', (select d0 from d), 'yesterday', (select d0 - 1 from d),
    'airlines', coalesce(jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'code', r.iata_code, 'name', r.name, 'pages', r.pages,
        'flights_today', r.flights_today, 'flights_yesterday', r.flights_yesterday, 'missing', r.missing,
        'status', case when jsonb_array_length(r.missing) = 0 then 'complete' when jsonb_array_length(r.missing) = 5 then 'not captured' else 'missing' end,
        'last_at', private.fig_ts(r.last_at),
        'verdict', r.v -> 'verdict', 'verdict_words', r.v -> 'words', 'verdict_at', r.v -> 'at',
        'verdict_day', r.v -> 'capture_day', 'verdicts', r.v -> 'pages')
        order by r.ord), '[]'::jsonb))
    from judged r
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

-- private.fig_cash_log(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_cash_log(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_today date := (p_as_of at time zone 'UTC')::date;
begin
  return (
    with al as materialized (select * from private.fig_airlines(p_world_id)),
    cd as (select al.airline_id, c.day, c.cash from al cross join lateral private.fig_cash_days(al.airline_id, p_as_of) c),
    typed as (select e.airline_id, e.day, e.cash, e.fixed_next7, e.updated_at from public.cash_entries e where e.world_id = p_world_id),
    cap as (select cc.airline_id, cc.day, cc.cash, cc.fixed_next7 from public.capture_cash cc where cc.world_id = p_world_id),
    bal as (select distinct on (b.airline_id, b.captured_on) b.airline_id, b.captured_on as day, b.captured_at
              from public.game_balance b join al on al.airline_id = b.airline_id and al.home_code is not null
             where b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_on <= v_today and b.captured_at <= p_as_of
               and b.amount is not null
             order by b.airline_id, b.captured_on, b.captured_at desc),
    ev as materialized (select e.airline_id, e.at, e.amount from private.fig_events(p_world_id, p_as_of) e),
    fx as (select bal.airline_id, bal.day,
                  (select sum(ev.amount) from ev where ev.airline_id = bal.airline_id and ev.at > bal.captured_at
                                                   and ev.at <= bal.captured_at + interval '168 hours') as m
             from bal),
    -- the tables' figures for an airline and day (planner_state_get), the capture's rounded as the planner rounds
    pair as (select coalesce(t.airline_id, c.airline_id) as airline_id, coalesce(t.day, c.day) as day,
                    coalesce(t.cash / 1000000, floor(c.cash / 10000 + 0.5) / 100) as stored_cash,
                    case when coalesce(t.fixed_next7, c.fixed_next7) > 0
                         then case when t.fixed_next7 is not null then t.fixed_next7 / 1000000 else floor(c.fixed_next7 / 10000 + 0.5) / 100 end end as stored_fixed,
                    floor(c.cash / 10000 + 0.5) / 100 as captured_cash,
                    case when c.fixed_next7 > 0 then floor(c.fixed_next7 / 10000 + 0.5) / 100 end as captured_fixed,
                    t.airline_id is not null as typed, t.cash as typed_cash, t.fixed_next7 as typed_fixed, t.updated_at as typed_at
               from typed t full join cap c on c.airline_id = t.airline_id and c.day = t.day),
    shown as (select cd.airline_id, cd.day, cd.cash,
                     case when fx.m > 0 then floor(fx.m * 100 + 0.5) / 100 else p.stored_fixed end as fixed
                from cd
                left join fx on fx.airline_id = cd.airline_id and fx.day = cd.day
                left join pair p on p.airline_id = cd.airline_id and p.day = cd.day)
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'today', v_today,
      'airlines', coalesce(jsonb_agg(jsonb_build_object(
          'airline_id', al.airline_id, 'code', al.iata_code, 'name', al.name,
          'days', (select coalesce(jsonb_agg(jsonb_build_object('day', s.day, 'cash', trim_scale(s.cash), 'fixed', trim_scale(s.fixed)) order by s.day), '[]'::jsonb)
                     from shown s where s.airline_id = al.airline_id),
          'today', (select jsonb_build_object(
                      'day', v_today,
                      'shown_cash', (select trim_scale(s.cash) from shown s where s.airline_id = al.airline_id and s.day = v_today),
                      'shown_fixed', coalesce((select trim_scale(s.fixed) from shown s where s.airline_id = al.airline_id and s.day = v_today),
                                              (select trim_scale(p.stored_fixed) from pair p where p.airline_id = al.airline_id and p.day = v_today)),
                      'stored_cash', trim_scale(p.stored_cash), 'stored_fixed', trim_scale(p.stored_fixed),
                      'captured_cash', trim_scale(p.captured_cash), 'captured_fixed', trim_scale(p.captured_fixed),
                      'entry', case when coalesce(p.typed, false) then jsonb_build_object('cash', p.typed_cash, 'fixed_next7', p.typed_fixed, 'updated_at', p.typed_at) end)
                      from (select 1) one left join pair p on p.airline_id = al.airline_id and p.day = v_today))
          order by al.ord), '[]'::jsonb))
      from al);
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
  select e.airline_id, private.local_to_utc(e.event_date, e.event_time, coalesce(private.airport_offset_min(p_world_id, h.code), 0)), e.debit / 1000000,
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

-- private.fig_fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_week date;
  v_step numeric; v_up numeric; v_down numeric; v_min numeric; v_hold numeric; v_cap numeric; v_launch numeric; v_floor numeric;
  v_new_days numeric;
  v_scan bigint; v_scan_at timestamptz;
  v_rows jsonb; v_actions jsonb := '[]'::jsonb; v_n int := 0;
  v_cabin text; v_after jsonb; v_set jsonb; v_b record; v_r record; v_mode numeric; v_alone int; v_with int; v_lv numeric;
begin
  v_step := private.fig_num(w, p_airline_id, 'fare_ladder_step_pts');
  v_up := private.fig_num(w, p_airline_id, 'fare_ladder_up_share');
  v_down := private.fig_num(w, p_airline_id, 'fare_ladder_down_share');
  v_min := private.fig_num(w, p_airline_id, 'fare_ladder_min_departures');
  v_hold := private.fig_num(w, p_airline_id, 'fare_ladder_hold_weeks');
  v_cap := private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_launch := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
  -- this Saturday: the latest Saturday on or before the moment's UTC date. A move recorded on the fare plan since then is
  -- this week's (on the fare plan already); the levels before it are the ones the week's move starts from
  v_week := v_today - ((extract(isodow from v_today)::int + 1) % 7);
  -- the latest finished world scan by then with its schedules: who else flies each pair (the 60% floor)
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;

  with
  ro as (select r.id, r.hub_code, r.dest_code from public.routes r where r.airline_id = p_airline_id and r.world_id = w and not r.removed),
  fq as materialized (select * from private.fig_freqs(w, p_airline_id)),
  -- a route's age: its earliest rotation's launch day, as route profit has it (growth_new_route_days)
  age as (select f.route_id, min(f.launched_on) as first_day from fq f group by f.route_id),
  -- business seats on an aircraft flying one of the route's rotations
  biz as (select distinct f.route_id from fq f
            join public.flight_legs fl on fl.rotation_id = f.rotation_id
            join public.aircraft a on a.id = fl.aircraft_id
            join public.cabin_configs cc on cc.id = a.cabin_config_id
           where f.live and coalesce(cc.business_seats, 0) > 0),
  -- every captured loads row of the airline by then (one per date and flight number, the latest), with its route as the
  -- airline's list has it, either way round (as route profit matches them: route_id is often empty)
  lf as materialized (
    select coalesce(r1.id, r2.id) as route_id, x.*
      from (select distinct on (f.game_date, f.flight_no) f.game_date, f.origin_code as o, f.dest_code as d, f.dep_at,
                   f.eco_pct, f.eco_fare, f.bus_pct, f.bus_seats, f.bus_fare
              from public.game_flights f
             where f.airline_id = p_airline_id and f.flight_no is not null and f.loads_captured_at <= p_as_of and f.game_date <= v_today
             order by f.game_date, f.flight_no, f.id desc) x
      left join ro r1 on r1.hub_code = x.o and r1.dest_code = x.d
      left join ro r2 on r2.hub_code = x.d and r2.dest_code = x.o
     where coalesce(r1.id, r2.id) is not null),
  -- by cabin: economy on every row with its load, business on flights with business seats
  lc as (select lf.route_id, 'economy'::text as cabin, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare from lf where lf.eco_pct is not null
         union all
         select lf.route_id, 'business', lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known)
  st as (select lc.route_id, lc.cabin, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare
           from lc
          where coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') >= p_as_of - interval '7 days'
            and coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') < p_as_of
          group by lc.route_id, lc.cabin),
  -- each captured day's average fare by cabin; the latest, and the first (economy's from the daily history too, kept for
  -- good once the flights are archived)
  fd as (select lc.route_id, lc.cabin, lc.game_date as day, avg(lc.fare) as fare from lc where lc.fare is not null group by 1, 2, 3),
  latest as (select distinct on (fd.route_id, fd.cabin) fd.* from fd order by fd.route_id, fd.cabin, fd.day desc),
  firsts as (select distinct on (y.route_id, y.cabin) y.*
               from (select fd.route_id, fd.cabin, fd.day, fd.fare from fd
                     union all
                     select coalesce(r1.id, r2.id), 'economy', d.day, avg(d.eco_fare_avg)
                       from public.route_days d
                       left join ro r1 on r1.hub_code = d.origin_code and r1.dest_code = d.dest_code
                       left join ro r2 on r2.hub_code = d.dest_code and r2.dest_code = d.origin_code
                      where d.airline_id = p_airline_id and d.eco_fare_avg is not null and d.day <= v_today and coalesce(r1.id, r2.id) is not null
                      group by 1, 3) y
              order by y.route_id, y.cabin, y.day, y.fare),
  -- the levels the fare plan recorded (manual §5): before this Saturday, the latest is the level; since it, this week's move
  rec as (select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, fp.level_pct, fp.ladder_move, fp.proposed_on, fp.reason
            from public.fare_plan fp
           where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped'
             and fp.proposed_on <= v_today),
  prev as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on < v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  wk as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on >= v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  dn as (select r.route_id, r.cabin, max(r.proposed_on) as down_on from rec r where r.ladder_move = 'down' and r.proposed_on < v_week group by 1, 2),
  -- whether the captures show this week's move yet (fare_plan_status()'s rule)
  seen as (select (e ->> 'id')::bigint as id, (e ->> 'applied')::boolean as applied, (e ->> 'seen_on')::date as seen_on
             from jsonb_array_elements(case when exists (select 1 from wk) then private.fig_fare_plan(p_airline_id, p_as_of) -> 'plan' else '[]'::jsonb end) e),
  -- another player on the pair, either way round (our own airlines included, manual §9): the latest scan, and our other
  -- airlines' own flights
  pairs as (select distinct least(ro.hub_code, ro.dest_code) as a, greatest(ro.hub_code, ro.dest_code) as b from ro),
  other as (select least(f ->> 2, f ->> 3) as a, greatest(f ->> 2, f ->> 3) as b
              from public.game_scan_schedules sc
              cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
             where sc.scan_id = v_scan and sc.airline_id <> p_airline_id and jsonb_typeof(f) = 'array'
            union
            select least(l.origin_code, l.dest_code), greatest(l.origin_code, l.dest_code)
              from public.flight_legs l where l.world_id = w and l.airline_id <> p_airline_id),
  contested as (select p.a, p.b from pairs p where exists (select 1 from other o where o.a = p.a and o.b = p.b)),
  -- the routes and cabins on the ladder: each flying route in economy, and in business where its aircraft have business
  -- seats; any with flights captured in the 7 days or a move recorded this week
  rc as (select distinct x.route_id, x.cabin
           from (select f.route_id, 'economy'::text as cabin from fq f where f.live
                 union all select bz.route_id, 'business' from biz bz
                 union all select st.route_id, st.cabin from st
                 union all select wk.route_id, wk.cabin from wk) x
           join ro on ro.id = x.route_id),
  lv as (select rc.route_id, rc.cabin, ro.hub_code as hub, ro.dest_code as dest,
                coalesce(st.n, 0) as n, coalesce(st.sold, 0) as sold, st.fare as fare_week,
                lt.fare as latest_fare, lt.day as latest_on, fi.fare as first_fare, fi.day as first_on,
                coalesce(pv.level_pct, v_launch) as level, pv.id is not null as recorded,
                wk.id as plan_id, wk.level_pct as plan_level, wk.ladder_move as plan_move, wk.reason as plan_reason,
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, ag.first_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested
           from rc join ro on ro.id = rc.route_id
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin
           left join firsts fi on fi.route_id = rc.route_id and fi.cabin = rc.cabin
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin
           left join age ag on ag.route_id = rc.route_id),
  mv as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                v_launch + v_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(v_launch, case when lv.contested then v_floor end) as floor_pct,
                coalesce(lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held
           from lv),
  dc as (select mv.*,
                case when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     when mv.held then 'held'
                     when mv.share >= v_up then case when mv.level >= mv.cap_pct then 'capped' else 'up' end
                     when mv.share >= v_down then 'hold'
                     when mv.level <= mv.floor_pct then 'floor'
                     else 'down' end as k
           from mv),
  fin as (select dc.*,
                 case dc.k when 'planned' then dc.plan_move when 'up' then 'up' when 'down' then 'down' else 'hold' end as move,
                 case dc.k when 'planned' then dc.plan_level
                           when 'up' then least(dc.level + v_step, dc.cap_pct)
                           when 'down' then greatest(dc.level - v_step, dc.floor_pct)
                           else dc.level end as new_level,
                 case when dc.contested and v_floor > v_launch then format('the %s%% floor', trim_scale(v_floor))
                      else format('launch (%s%%)', trim_scale(v_launch)) end as floor_words
            from dc),
  od as (select fin.*,
                 case fin.k
                   when 'planned' then coalesce(fin.plan_reason, 'on the fare plan')
                   when 'young' then format('new route, launched %s', to_char(fin.first_day, 'FMDD Mon'))
                   when 'few' then case when fin.n = 0 then 'no departures captured'
                                        else format('%s departure%s captured, needs %s', fin.n, case when fin.n = 1 then '' else 's' end, trim_scale(v_min)) end
                   when 'held' then format('held after a step down on %s', to_char(fin.down_on, 'FMDD Mon'))
                   when 'up' then format('sold out %s of %s', fin.sold, fin.n)
                                  || case when fin.level + v_step >= fin.cap_pct then format(', up to the %s%% cap', trim_scale(fin.cap_pct)) else '' end
                   when 'capped' then format('sold out %s of %s, capped at %s%%', fin.sold, fin.n, trim_scale(fin.cap_pct))
                   when 'hold' then format('sold out %s of %s', fin.sold, fin.n)
                   when 'down' then format('sold out %s of %s', fin.sold, fin.n)
                                    || case when fin.level - v_step <= fin.floor_pct then ', down to ' || fin.floor_words else '' end
                   else format('sold out %s of %s, at %s', fin.sold, fin.n, fin.floor_words) end as reason,
                 case when fin.latest_fare is not null and fin.first_fare > 0 then round(fin.latest_fare / fin.first_fare * v_launch, 1) end as fare_index
            from fin)
  select coalesce(jsonb_agg(jsonb_build_object(
           'route_id', o.route_id, 'hub', o.hub, 'dest', o.dest, 'cabin', o.cabin,
           'departures', o.n, 'sold_out', o.sold, 'sold_out_share', round(o.share, 1), 'average_fare', round(o.fare_week, 2),
           'first_fare', round(o.first_fare, 2), 'first_on', o.first_on, 'latest_fare', round(o.latest_fare, 2), 'latest_on', o.latest_on,
           'fare_index', o.fare_index,
           -- the index against the level the game should show: this week's, once the captures see it
           'index_matches', case when o.fare_index is null then null
                                 else abs(o.fare_index - case when o.plan_id is not null and o.applied then o.new_level else o.level end) <= 1 end,
           'level', trim_scale(o.level), 'recorded', o.recorded, 'steps', trim_scale(round((o.level - v_launch) / v_step, 1)),
           'move', o.move, 'new_level', trim_scale(o.new_level), 'new_steps', trim_scale(round((o.new_level - v_launch) / v_step, 1)),
           'change_pct', case when o.level > 0 then trim_scale(round((o.new_level / o.level - 1) * 100, 1)) end,
           'reason', o.reason, 'contested', o.contested, 'floor', trim_scale(o.floor_pct), 'cap', trim_scale(o.cap_pct), 'new_route', o.young,
           'planned', o.plan_id is not null, 'plan_id', o.plan_id, 'applied', o.applied, 'seen_on', o.seen_on,
           -- what Put on the fare plan writes: every level that changes, and a hold that follows a step down
           'to_plan', o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k = 'held'))
           order by o.hub, o.dest, o.cabin desc), '[]'::jsonb)
    into v_rows from od o;

  -- the game's Ticket price adjustments, cabin by cabin: each action sets a level with the baseline default price, so the
  -- order matters. For each base, in the bases' order: when setting the whole base to its most common new level (From
  -- base, To anywhere; From anywhere, To base) and then the single routes that differ takes fewer actions than single
  -- routes alone, the two base actions go first. Then every route still not at its new level, two actions each (From A to
  -- B, From B to A).
  foreach v_cabin in array array['economy', 'business'] loop
    v_after := '{}'::jsonb;
    for v_b in select y.airport_code from (
               select distinct on (x2.airport_code) x2.airport_code, x2.position, x2.id
                 from public.airline_bases x2 where x2.airline_id = p_airline_id and x2.world_id = w
                order by x2.airport_code, x2.position nulls last, x2.id) y
              order by y.position nulls last, y.id loop
      select count(*) filter (where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric)::int * 2 into v_alone
        from jsonb_array_elements(v_rows) e
       where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest');
      select (e ->> 'new_level')::numeric into v_mode
        from jsonb_array_elements(v_rows) e
       where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest')
       group by 1 order by count(*) desc, 1 limit 1;
      if v_mode is null then continue; end if;
      select 2 + 2 * (count(*) filter (where (e ->> 'new_level')::numeric <> v_mode))::int into v_with
        from jsonb_array_elements(v_rows) e
       where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest');
      if v_with < v_alone then
        foreach v_set in array array[jsonb_build_array(v_b.airport_code, 'anywhere'), jsonb_build_array('anywhere', v_b.airport_code)] loop
          v_n := v_n + 1;
          v_actions := v_actions || jsonb_build_object(
            'n', v_n, 'kind', 'base', 'base', v_b.airport_code, 'cabin', v_cabin, 'from', v_set ->> 0, 'to', v_set ->> 1,
            'level', trim_scale(v_mode), 'sign', case when v_mode >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_mode - 100)),
            'baseline', 'default price',
            'text', format('From %s to %s: %s%s%% of the default price, %s', v_set ->> 0, v_set ->> 1,
                           case when v_mode >= 100 then '+' else '−' end, trim_scale(abs(v_mode - 100)), v_cabin));
        end loop;
        select v_after || coalesce(jsonb_object_agg(e ->> 'route_id', v_mode), '{}'::jsonb) into v_after
          from jsonb_array_elements(v_rows) e
         where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest');
      end if;
    end loop;
    for v_r in select e ->> 'route_id' as route_id, e ->> 'hub' as hub, e ->> 'dest' as dest, (e ->> 'level')::numeric as level,
                    (e ->> 'new_level')::numeric as new_level
               from jsonb_array_elements(v_rows) e where e ->> 'cabin' = v_cabin order by e ->> 'hub', e ->> 'dest' loop
      v_lv := coalesce((v_after ->> v_r.route_id)::numeric, v_r.level);
      if v_lv = v_r.new_level then continue; end if;
      foreach v_set in array array[jsonb_build_array(v_r.hub, v_r.dest), jsonb_build_array(v_r.dest, v_r.hub)] loop
        v_n := v_n + 1;
        v_actions := v_actions || jsonb_build_object(
          'n', v_n, 'kind', 'route', 'route', v_r.hub || '–' || v_r.dest, 'cabin', v_cabin, 'from', v_set ->> 0, 'to', v_set ->> 1,
          'level', trim_scale(v_r.new_level), 'sign', case when v_r.new_level >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_r.new_level - 100)),
          'baseline', 'default price',
          'text', format('From %s to %s: %s%s%% of the default price, %s', v_set ->> 0, v_set ->> 1,
                         case when v_r.new_level >= 100 then '+' else '−' end, trim_scale(abs(v_r.new_level - 100)), v_cabin));
      end loop;
    end loop;
  end loop;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of), 'week_of', v_week,
    'from', private.fig_ts(p_as_of - interval '7 days'), 'to', private.fig_ts(p_as_of),
    'settings', jsonb_build_object('step_pts', v_step, 'up_share', v_up, 'down_share', v_down, 'min_departures', v_min,
                                   'hold_weeks', v_hold, 'cap_pts', v_cap, 'launch_pct', v_launch, 'cap_pct', v_launch + v_cap,
                                   'floor_pct', v_floor, 'new_route_days', v_new_days),
    'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
    'moves', jsonb_build_object(
      'up', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'up'),
      'hold', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'hold'),
      'down', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'down')),
    'to_plan', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'to_plan')::boolean),
    'planned', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'planned')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'A rival starting on a pair pauses that route for a week (manual §5): that needs this week''s scan set against last week''s (step 4), so for now the figure pauses nothing and the Saturday review checks the scan by hand.',
      'The fare index is the latest captured fare against the first, times the launch level: a level more than 1 point from it is flagged, not changed.'));
end
$function$

;

-- private.fig_fare_plan(p_airline_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_fare_plan(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
begin
  return (
    with l as (select distinct on (f.game_date, f.flight_no) f.game_date, f.origin_code as origin, f.dest_code as dest,
                      f.eco_pct as eco, trim_scale(f.eco_fare) as fare,
                      f.bus_pct as bus, case when coalesce(f.bus_seats, 0) > 0 then trim_scale(f.bus_fare) end as bfare
                 from public.game_flights f
                where f.airline_id = p_airline_id and f.flight_no is not null and f.game_date >= v_today - 9
                  and f.loads_captured_at <= p_as_of
                order by f.game_date, f.flight_no, f.id desc),
    r as (select ro.id, ro.hub_code, ro.dest_code from public.routes ro where ro.airline_id = p_airline_id and ro.world_id = w),
    -- each route's fares and economy loads by date: the day's average fare, and the loads summed with their count (the
    -- before and after are averages over every flight, not over the days)
    rd as materialized (
      select r.id as route_id, l.game_date as day, avg(l.fare) as fare, sum(l.eco) as eco_sum, count(l.eco) as eco_n
        from r join l on l.fare is not null
         and ((l.origin = r.hub_code and l.dest = r.dest_code) or (l.origin = r.dest_code and l.dest = r.hub_code))
       group by r.id, l.game_date),
    -- the same in business, for the fare ladder's business rows (flights with business seats)
    rb as materialized (
      select r.id as route_id, l.game_date as day, avg(l.bfare) as fare, sum(l.bus) as eco_sum, count(l.bus) as eco_n
        from r join l on l.bfare is not null
         and ((l.origin = r.hub_code and l.dest = r.dest_code) or (l.origin = r.dest_code and l.dest = r.hub_code))
       group by r.id, l.game_date),
    p as (select fp.*, ro.hub_code, ro.dest_code,
                 fp.fare_from * (1 + fp.change_pct / 100) as target,
                 case when fp.level_pct is not null and fp.cabin_class = 'business'
                      then (select rb.fare from rb where rb.route_id = fp.route_id order by rb.day desc limit 1)
                      else (select rd.fare from rd where rd.route_id = fp.route_id order by rd.day desc limit 1) end as cur,
                 case
                   -- a fare test: seen once at least half the change shows in the day's average fare, on or after the day it
                   -- was proposed
                   when fp.level_pct is null
                     then (select min(rd.day) from rd where rd.route_id = fp.route_id and rd.day >= fp.proposed_on
                              and rd.fare >= fp.fare_from * (1 + fp.change_pct / 200))
                   -- the fare ladder's: seen once the day's average fare in its cabin is the fare then times the expected
                   -- ratio, within 1%, on or after the day it was proposed
                   when fp.cabin_class = 'business'
                     then (select min(rb.day) from rb where rb.route_id = fp.route_id and rb.day >= fp.proposed_on and fp.fare_from > 0
                              and abs(rb.fare / fp.fare_from - (1 + coalesce(fp.change_pct, 0) / 100)) <= 0.01)
                   else (select min(rd.day) from rd where rd.route_id = fp.route_id and rd.day >= fp.proposed_on and fp.fare_from > 0
                            and abs(rd.fare / fp.fare_from - (1 + coalesce(fp.change_pct, 0) / 100)) <= 0.01) end as seen,
                 fp.level_pct is not null and fp.cabin_class = 'business' as biz
            from public.fare_plan fp left join public.routes ro on ro.id = fp.route_id
           where fp.airline_id = p_airline_id and fp.status <> 'dropped')
    select jsonb_build_object(
      'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of),
      'plan', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', p.id, 'legacy_key', p.legacy_key, 'route_id', p.route_id, 'hub', p.hub_code, 'dest', p.dest_code,
                 'cabin_class', p.cabin_class, 'change_pct', trim_scale(p.change_pct), 'fare_from', trim_scale(p.fare_from),
                 'proposed_on', p.proposed_on, 'status', p.status, 'reason', p.reason, 'updated_at', p.updated_at,
                 'fare_now', p.cur, 'target', p.target, 'applied', p.seen is not null, 'seen_on', p.seen,
                 'economy_before', case when p.seen is null then null
                                        when p.biz then (select sum(rb.eco_sum) / nullif(sum(rb.eco_n), 0) from rb where rb.route_id = p.route_id and rb.day < p.seen)
                                        else (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.day < p.seen) end,
                 'economy_after', case when p.seen is null then null
                                       when p.biz then (select sum(rb.eco_sum) / nullif(sum(rb.eco_n), 0) from rb where rb.route_id = p.route_id and rb.day >= p.seen)
                                       else (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.day >= p.seen) end,
                 'level_pct', trim_scale(p.level_pct), 'ladder_move', p.ladder_move)
                 order by p.id) from p), '[]'::jsonb),
      'fares', coalesce((select jsonb_agg(jsonb_build_object('route_id', x.route_id, 'hub', r.hub_code, 'dest', r.dest_code, 'day', x.day, 'fare', x.fare)
                                          order by x.route_id)
                           from (select distinct on (rd.route_id) rd.route_id, rd.day, rd.fare from rd order by rd.route_id, rd.day desc) x
                           join r on r.id = x.route_id), '[]'::jsonb)));
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
                            'leases_day', v_lease, 'closing_day', v_closing, 'leases_and_closing_day', v_lease + v_closing,
                            'net_day', v_ops - v_lease - v_closing,
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
  select case when x.airline_id is not null then x.order_config_id else t.order_config_id end
    from public.airlines a
    join public.aircraft_types t on t.id = p_type_id
    left join public.airline_order_cabins x on x.airline_id = a.id and x.aircraft_type_id = t.id
   where a.id = p_airline_id
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

-- private.fig_route_loads(p_world_id bigint, p_as_of timestamp with time zone)
CREATE OR REPLACE FUNCTION private.fig_route_loads(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with d as (select (p_as_of at time zone 'UTC')::date as d0),
  ld as (select x.* from d cross join lateral private.fig_load_days(p_world_id, p_as_of, d.d0 - 6, d.d0) x where x.done),
  lv as (select x.* from d cross join lateral private.fig_load_values(p_world_id, p_as_of, d.d0 - 6, d.d0) x where x.v is not null),
  fl as materialized (
    select x.day, x.airline_id, x.flight_no, x.route_id, lv.v
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
          from fl group by fl.route_id, fl.airline_id),
  -- each flight number's, as loadStats() keeps them under "F|airline|number": the same figures over the same flights
  f as (select fl.airline_id, fl.flight_no, count(*)::int as n,
               sum(case when coalesce(fl.v, 0) = 0 then 97.5 else fl.v end) as s,
               count(*) filter (where coalesce(fl.v, 0) = 0 or fl.v >= 95)::int as full_n,
               count(*) filter (where fl.v > 0 and fl.v >= 85 and fl.v < 95)::int as b95,
               count(*) filter (where fl.v > 0 and fl.v >= 70 and fl.v < 85)::int as b85,
               count(*) filter (where fl.v > 0 and fl.v < 70)::int as b70,
               count(distinct fl.day)::int as days
          from fl where fl.flight_no is not null group by fl.airline_id, fl.flight_no)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'from', (select d0 - 6 from d), 'to', (select d0 from d),
    'routes', coalesce((select jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'route_id', r.route_id, 'hub', ro.hub_code, 'dest', ro.dest_code,
        'departures', r.n, 'sum', r.s, 'average', r.s / r.n, 'full', r.full_n, 'under_95', r.b95, 'under_85', r.b85,
        'under_70', r.b70, 'days', r.days)
        order by a.position nulls last, r.airline_id, ro.hub_code, ro.dest_code)
      from r join public.routes ro on ro.id = r.route_id join public.airlines a on a.id = r.airline_id), '[]'::jsonb),
    'flights', coalesce((select jsonb_agg(jsonb_build_object(
        'airline_id', f.airline_id, 'flight_no', f.flight_no,
        'departures', f.n, 'sum', f.s, 'average', f.s / f.n, 'full', f.full_n, 'under_95', f.b95, 'under_85', f.b85,
        'under_70', f.b70, 'days', f.days)
        order by a.position nulls last, f.airline_id, f.flight_no)
      from f join public.airlines a on a.id = f.airline_id), '[]'::jsonb))
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
  v_losing numeric; v_sold_share numeric; v_sold_min numeric; v_fix_min numeric; v_fix_eco numeric; v_fix_routes numeric; v_fix_margin numeric; v_new_days numeric;
  v_margin_min numeric; v_allow_min numeric;
begin
  if p_days is null or p_days < 1 then raise exception 'p_days must be 1 or more' using errcode = '22023'; end if;
  v_losing := private.fig_num(w, p_airline_id, 'growth_losing_min_departures');
  v_sold_share := private.fig_num(w, p_airline_id, 'growth_sold_out_share');
  v_sold_min := private.fig_num(w, p_airline_id, 'growth_sold_out_min_departures');
  v_fix_min := private.fig_num(w, p_airline_id, 'growth_fix_min_departures');
  v_fix_eco := private.fig_num(w, p_airline_id, 'growth_fix_economy_pct');
  v_fix_routes := private.fig_num(w, p_airline_id, 'growth_fix_min_routes');
  v_fix_margin := private.fig_num(w, p_airline_id, 'growth_fix_margin');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  v_margin_min := private.fig_num(w, p_airline_id, 'turn_margin_min');
  v_allow_min := private.fig_num(w, p_airline_id, 'block_allowance_min');
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
  -- departure in UTC from its origin's offset in the world, with its correction (capDepUTC; since the clean-up)
  select coalesce(jsonb_agg(to_jsonb(y) order by y.j), '[]'::jsonb) into v_loads
    from (select x.*, (row_number() over (order by x.id))::int as j,
                 private.local_to_utc(x.game_date, x.dep_local, coalesce(private.airport_offset_min(w, x.origin), 0)) as dep_utc
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
    -- a route's age: its earliest rotation's launch day (a second daily added later doesn't make an old route new)
    age as (select f.route_id, min(f.launched_on) as first_day from fq f where f.airline_id = p_airline_id group by f.route_id),
    -- a route's aircraft hours a flight (manual §3, 17 Oct): each of its legs' block time (or, untimed, the estimate:
    -- block_allowance_min + distance ÷ the type's cruise speed) plus the type's turnaround (min_turn_min) and the turn
    -- margin (turn_margin_min), averaged over the flights a week each leg flies
    hrs as (select ro.id as route_id,
                   sum((coalesce(l.block_min, round(ro.distance_km::numeric / ty.cruise_kmh * 60 + v_allow_min)) + ty.min_turn_min + v_margin_min)
                       * coalesce(cardinality(l.days_utc), 7))::numeric
                     / nullif(sum(coalesce(cardinality(l.days_utc), 7)), 0) / 60 as h
              from public.rotations rt
              join public.routes ro on ro.id = rt.route_id
              join public.flight_legs l on l.rotation_id = rt.id
              join public.aircraft a on a.id = l.aircraft_id
              join public.aircraft_types ty on ty.id = a.aircraft_type_id
             where rt.airline_id = p_airline_id and ty.min_turn_min is not null
               and (l.block_min is not null or (ro.distance_km is not null and ty.cruise_kmh > 0))
             group by ro.id),
    g as (select rk.hub, rk.dest, rk.route_id, count(*)::int as n, sum(fl.profit) / 1000000 as profit,
                 sum(fl.pax_income + fl.cargo_income) / 1000000 as income,
                 avg(fl.eco) as eco_a, avg(fl.bus) as bus_a, avg(fl.cargo) as cargo_a, avg(fl.eco_fare) as fare_a,
                 count(fl.eco)::int as eco_n, (count(*) filter (where fl.eco >= 100))::int as sold, min(fl.i) as first_i
            from fl join rk on rk.o = fl.o and rk.d = fl.d
           group by rk.hub, rk.dest, rk.route_id),
    r as (select g.*, g.profit / g.n as ppf, case when g.income > 0 then g.profit / g.income end as margin,
                 coalesce(wk.wk, 0) as wk, (g.profit / g.n) * coalesce(wk.wk, 0) as pwk,
                 case when g.eco_n > 0 then g.sold::numeric / g.eco_n end as sold_share,
                 -- young: launched fewer than growth_new_route_days days ago; no launch day on record counts as old
                 coalesce(ag.first_day is not null and v_today - ag.first_day < v_new_days, false) as young,
                 hh.h as hours, case when hh.h > 0 then (g.profit / g.n) / hh.h end as pph
            from g left join wk on wk.route_id = g.route_id left join age ag on ag.route_id = g.route_id
            left join hrs hh on hh.route_id = g.route_id),
    pp as (select array_agg(r.ppf order by r.ppf) as a, array_agg(r.pph order by r.pph) filter (where r.pph is not null) as h from r),
    -- the middle route: by profit a flight, and by profit an aircraft hour among the routes with their hours
    q as (select pp.a[floor(cardinality(pp.a) / 2.0)::int + 1] as med, pp.a[floor(cardinality(pp.a) * 0.25)::int + 1] as q25,
                 pp.h[floor(cardinality(pp.h) / 2.0)::int + 1] as med_h,
                 coalesce(cardinality(pp.a), 0) as len from pp),
    mk as (select r.*, case when r.ppf < 0 and r.n >= v_losing and not r.young then 'losing'
                            when r.sold_share is not null and r.sold_share >= v_sold_share and r.n >= v_sold_min
                              -- add at or above the middle route's profit an aircraft hour, raise below; a route with no
                              -- aircraft hours (no legs on record) is compared by profit a flight, as before 17 Oct
                              then case when r.pph is not null and q.med_h is not null then case when r.pph >= q.med_h then 'add' else 'raise' end
                                        when r.ppf >= q.med then 'add' else 'raise' end
                            when r.n >= v_fix_min and not r.young and r.eco_a is not null and r.eco_a < v_fix_eco then 'fix'
                            when r.n >= v_fix_min and not r.young and q.len >= v_fix_routes and r.ppf <= q.q25 and r.margin is not null and r.margin < v_fix_margin then 'fix-margin'
                            else 'hold' end as k, q.med, q.med_h
             from r cross join q),
    routes as (select coalesce(jsonb_agg(jsonb_build_object(
                 'route_id', mk.route_id, 'hub', mk.hub, 'dest', mk.dest, 'flights', mk.n, 'profit', mk.profit, 'income', mk.income,
                 'margin', mk.margin, 'profit_per_flight', mk.ppf, 'flights_week', mk.wk, 'profit_week', mk.pwk,
                 'aircraft_hours', mk.hours, 'profit_per_aircraft_hour', mk.pph,
                 'economy', mk.eco_a, 'business', mk.bus_a, 'cargo', mk.cargo_a, 'economy_fare', mk.fare_a,
                 'sold_out', mk.sold, 'with_loads', mk.eco_n, 'sold_out_share', mk.sold_share,
                 'mark', case when mk.k = 'fix-margin' then 'fix' else mk.k end,
                 'why', case mk.k when 'losing' then 'its average flight loses money'
                                  when 'add' then format('sold out on %s of %s departures, profit %s at or above the airline''s middle route', mk.sold, mk.eco_n,
                                                         case when mk.pph is not null and mk.med_h is not null then 'an aircraft hour' else 'a flight' end)
                                  when 'raise' then format('sold out on %s of %s departures, profit %s below the airline''s middle route', mk.sold, mk.eco_n,
                                                           case when mk.pph is not null and mk.med_h is not null then 'an aircraft hour' else 'a flight' end)
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
    when p_descr ilike '%training%' then 'cabin'
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

-- private.rules_input_doc(p_world_id bigint, p_routes text)
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


-- apply_loads_from_capture(p_airline text)
CREATE OR REPLACE FUNCTION public.apply_loads_from_capture(p_airline text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d record; mon text; cur jsonb; day jsonb; f jsonb; n int := 0; alnames int;
  ms bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  for d in select distinct flight_date from public.game_loads where airline = p_airline and flight_date >= current_date - 3 loop
    mon := to_char(d.flight_date, 'YYYY-MM');
    select json::jsonb into cur from public.planner_loads where month = mon for update; cur := coalesce(cur, '{}'::jsonb);
    day := coalesce(cur->(d.flight_date::text), '{}'::jsonb);
    f := coalesce(day->'f', '{}'::jsonb);
    -- economy load per flight, keyed the way the planner keys its reports: "Airline|flight number"
    select coalesce(jsonb_object_agg(airline||'|'||regexp_replace(code, '^[A-Z0-9]+\s*', ''), eco), '{}'::jsonb) into f
      from (select airline, code, eco from public.game_loads where airline = p_airline and flight_date = d.flight_date and eco is not null) q;
    day := jsonb_set(day, '{f}', coalesce(day->'f', '{}'::jsonb) || f, true);
    select count(distinct airline) into alnames from public.game_loads where flight_date = d.flight_date;
    day := day || jsonb_build_object('done', alnames >= 6, 'captured', now(), 'source', 'capture');
    cur := jsonb_set(cur, array[d.flight_date::text], day, true);
    -- saved_at moves on, so a browser holding an older copy of the month takes this one when it next loads
    insert into public.planner_loads(month, json, saved_at) values (mon, cur::text, ms)
      on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
    n := n + 1;
  end loop;
  return jsonb_build_object('days', n);
end $function$
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

-- capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
CREATE OR REPLACE FUNCTION public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare ok boolean; rid bigint; al text; res jsonb;
begin
  select exists(select 1 from public.capture_keys k where extensions.crypt(p_key, k.key_hash) = k.key_hash) into ok;
  if not ok then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  al := case when p_airline ilike 'pan am%' then 'Pan American' when p_airline ilike 'kingfisher%' then 'Kingfisher' when p_airline ilike 'ryanair%' then 'Ryanair'
             when p_airline ilike 'virgin%' then 'Virgin Atlantic' when p_airline ilike 'china eastern%' then 'China Eastern' when p_airline ilike 'malaysia%' then 'Malaysia Airlines' else p_airline end;
  if p_kind not in ('statement','events','loads','pnl','balance','html') then return jsonb_build_object('ok', false, 'error', 'bad kind'); end if;
  delete from public.game_capture_raw where captured_at < now() - interval '14 days';   -- raw pages kept 14 days; the parsed tables keep everything
  insert into public.game_capture_raw(airline, kind, page_url, rows) values (al, p_kind, p_page, coalesce(p_rows, '[]'::jsonb)) returning id into rid;
  if p_kind = 'html' then return jsonb_build_object('ok', true, 'kind', 'html', 'rows', 1, 'airline', al); end if;
  begin
    res := public.parse_capture(rid) || jsonb_build_object('airline', al);
    if p_kind = 'loads' then res := res || public.apply_loads_from_capture(al); end if;
  exception when others then
    res := jsonb_build_object('ok', false, 'airline', al, 'error', 'parse: ' || sqlerrm, 'raw_id', rid);
  end;
  return res;
end $function$
;

-- export_capture(p_secret text, p_days integer)
CREATE OR REPLACE FUNCTION public.export_capture(p_secret text, p_days integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'pnl', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) from public.game_flight_pnl f where f.ts >= now() - make_interval(days => p_days)),
    'loads', (select coalesce(jsonb_agg(to_jsonb(l) - 'captured_at'), '[]'::jsonb) from public.game_loads l where l.flight_date >= current_date - (p_days + 1)),
    'events', (select coalesce(jsonb_agg(to_jsonb(e) - 'captured_at'), '[]'::jsonb) from public.game_events e where e.event_date >= current_date - p_days),
    'balance', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from public.game_balance b where b.account like '2800%' and b.captured_on >= current_date - p_days),
    'ops', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb) from public.game_ops_recent o),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('airline', airline, 'kind', kind, 'captured_at', captured_at)), '[]'::jsonb) from public.game_capture_raw where captured_at >= now() - make_interval(days => p_days) and kind <> 'html'));
end $function$
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
 SET search_path TO 'public'
AS $function$
declare r record; row_ jsonb; c text[]; n int := 0; cur_date date; yr int := extract(year from now())::int; d text; tsv timestamptz; amt numeric; v_side text; v_descr text; dt date;
  ep int; es int; bp int; bs int; fp int; fs int; cu int; cc int;
  last_ts timestamptz := null; blkn int := 0; maint_pending boolean := false; seen jsonb := '{}'::jsonb; k text; o int; b int;
begin
  select * into r from public.game_capture_raw where id = p_id; if r is null then return '{"ok":false}'; end if;
  if r.kind = 'statement' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if array_length(c,1) < 3 or c[1] !~ '^\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substr(c[1],1,6); v_descr := c[2];
      tsv := make_timestamptz(yr, substr(d,4,2)::int, substr(d,1,2)::int, substr(c[1],8,2)::int, substr(c[1],11,2)::int, 0, 'UTC');
      if tsv > now() + interval '2 days' then tsv := tsv - interval '1 year'; end if;
      amt := public.as_num(c[3]); v_side := case when c[3] ~ 'C\s*$' then 'C' else 'D' end;
      if amt is null then continue; end if;
      if last_ts is distinct from tsv then last_ts := tsv; blkn := 0; maint_pending := false; end if;
      if v_descr like 'Maintenance of%' then blkn := blkn + 1; maint_pending := true; b := blkn;
      elsif v_descr = 'Passenger transport income' then if maint_pending then maint_pending := false; else blkn := blkn + 1; end if; b := blkn;
      elsif v_descr ilike 'Leasing rate%' or v_descr ilike 'Week-end closing%' then b := 0;
      else b := greatest(blkn, 1); end if;
      k := tsv::text || '|' || v_descr || '|' || amt::text; o := coalesce((seen->>k)::int, 0) + 1; seen := seen || jsonb_build_object(k, o);
      insert into public.game_statement(airline, ts, descr, amount, side, route, pax, occ, blk)
      values (r.airline, tsv, v_descr, amt, v_side, substring(v_descr from '\(([A-Z]{3}-[A-Z]{3})\)'), (substring(v_descr from 'of (\d+) passengers'))::int, o, b)
      on conflict on constraint game_statement_pkey do update set blk = excluded.blk; n := n + 1;
    end loop;
  elsif r.kind = 'events' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select x from jsonb_array_elements_text(row_) x where x <> '');
      if c[1] ~ '^\w+, \d{2}\.\d{2}\.' then
        d := substring(c[1] from '(\d{2}\.\d{2})\.'); cur_date := make_date(yr, substr(d,4,2)::int, substr(d,1,2)::int);
        if cur_date < current_date - 200 then cur_date := cur_date + interval '1 year'; end if;
        c := c[2:];
      end if;
      if cur_date is null or array_length(c,1) < 2 or c[1] !~ '^\d{2}:\d{2}$' then continue; end if;
      insert into public.game_events(airline, event_date, event_time, descr, credit, debit, balance)
      values (r.airline, cur_date, c[1], c[2], public.as_num(c[3]), public.as_num(c[4]), public.as_num(c[5])) on conflict do nothing; n := n + 1;
    end loop;
  elsif r.kind = 'loads' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c,1) < 15 or c[1] !~ '^[A-Z0-9]{2,3}\s?\d{1,5}' or c[4] !~ '\d{2}\.\d{2}\. \d{2}:\d{2}' then continue; end if;
      d := substring(c[4] from '(\d{2}\.\d{2})\.'); dt := make_date(yr, substr(d,4,2)::int, substr(d,1,2)::int); if dt > current_date + 2 then dt := dt - interval '1 year'; end if;
      ep := (substring(c[8] from '^\s*(\d+)'))::int; es := (substring(c[8] from '/\s*(\d+)'))::int;
      bp := (substring(c[10] from '^\s*(\d+)'))::int; bs := (substring(c[10] from '/\s*(\d+)'))::int;
      fp := (substring(c[12] from '^\s*(\d+)'))::int; fs := (substring(c[12] from '/\s*(\d+)'))::int;
      cu := (substring(c[14] from '^\s*(\d+)'))::int; cc := (substring(c[14] from '/\s*(\d+)'))::int;
      insert into public.game_loads(airline, flight_date, code, dep_time, tail, origin, dest, arr_time, status,
        eco, bus, fst, cargo, eco_pax, eco_seats, eco_fare, bus_pax, bus_seats, bus_fare, fst_pax, fst_seats, fst_fare, cargo_units, cargo_cap, cargo_rate)
      values (r.airline, dt, regexp_replace(c[1], '\s+', ' '), substring(c[4] from '(\d{2}:\d{2})'), c[2], c[3], c[5], substring(c[6] from '(\d{2}:\d{2})'), c[15],
        public.as_num(substring(c[8] from '\((\d+)%\)')), public.as_num(substring(c[10] from '\((\d+)%\)')), public.as_num(substring(c[12] from '\((\d+)%\)')), public.as_num(substring(c[14] from '\((\d+)%\)')),
        ep, es, public.as_num(c[7]), bp, bs, public.as_num(c[9]), fp, fs, public.as_num(c[11]), cu, cc, public.as_num(c[13]))
      on conflict (airline, flight_date, code, dep_time) do update set tail = excluded.tail, origin = excluded.origin, dest = excluded.dest, arr_time = excluded.arr_time, status = excluded.status,
        eco = excluded.eco, bus = excluded.bus, fst = excluded.fst, cargo = excluded.cargo, eco_pax = excluded.eco_pax, eco_seats = excluded.eco_seats, eco_fare = excluded.eco_fare,
        bus_pax = excluded.bus_pax, bus_seats = excluded.bus_seats, bus_fare = excluded.bus_fare, fst_pax = excluded.fst_pax, fst_seats = excluded.fst_seats, fst_fare = excluded.fst_fare,
        cargo_units = excluded.cargo_units, cargo_cap = excluded.cargo_cap, cargo_rate = excluded.cargo_rate, captured_at = now();
      n := n + 1;
    end loop;
  elsif r.kind = 'pnl' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c,1) < 3 or c[2] !~ 'AS\$' then continue; end if;
      insert into public.game_pnl(airline, captured_on, line, current_p, last_p, total_p) values (r.airline, current_date, c[1], public.as_num(c[2]), public.as_num(c[3]), public.as_num(c[array_length(c,1)]))
      on conflict (airline, captured_on, line) do update set current_p = excluded.current_p, last_p = excluded.last_p, total_p = excluded.total_p; n := n + 1;
    end loop;
  elsif r.kind = 'balance' then
    for row_ in select * from jsonb_array_elements(r.rows) loop
      c := array(select jsonb_array_elements_text(row_));
      if array_length(c,1) >= 3 and c[1] ~ '^\d{3,4}$' then
        insert into public.game_balance(airline, captured_on, account, amount) values (r.airline, current_date, c[1]||' '||c[2], public.as_num(c[3])) on conflict (airline, captured_on, account) do update set amount = excluded.amount; n := n + 1; end if;
      if array_length(c,1) >= 6 and c[4] ~ '^\d{3,4}$' then
        insert into public.game_balance(airline, captured_on, account, amount) values (r.airline, current_date, c[4]||' '||c[5], public.as_num(c[6])) on conflict (airline, captured_on, account) do update set amount = excluded.amount; n := n + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'kind', r.kind, 'rows', n);
end $function$
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
-- captured loads become the planner's nightly report, so the Review boards work without pasting
create or replace function public.apply_loads_from_capture(p_airline text) returns jsonb language plpgsql security definer set search_path = public as $$
declare d record; mon text; cur jsonb; day jsonb; f jsonb; n int := 0; alnames int;
begin
  for d in select distinct flight_date from public.game_loads where airline = p_airline and flight_date >= current_date - 3 loop
    mon := to_char(d.flight_date, 'YYYY-MM');
    select json::jsonb into cur from public.planner_loads where month = mon; cur := coalesce(cur, '{}'::jsonb);
    day := coalesce(cur->(d.flight_date::text), '{}'::jsonb);
    f := coalesce(day->'f', '{}'::jsonb);
    -- economy load per flight, keyed the way the planner keys its reports: "Airline|flight number"
    select coalesce(jsonb_object_agg(airline||'|'||regexp_replace(code, '^[A-Z0-9]+\s*', ''), eco), '{}'::jsonb) into f
      from (select airline, code, eco from public.game_loads where airline = p_airline and flight_date = d.flight_date and eco is not null) q;
    day := jsonb_set(day, '{f}', coalesce(day->'f', '{}'::jsonb) || f, true);
    select count(distinct airline) into alnames from public.game_loads where flight_date = d.flight_date;
    day := day || jsonb_build_object('done', alnames >= 6, 'captured', now(), 'source', 'capture');
    cur := jsonb_set(cur, array[d.flight_date::text], day, true);
    insert into public.planner_loads(month, json) values (mon, cur::text) on conflict (month) do update set json = excluded.json;
    n := n + 1;
  end loop;
  return jsonb_build_object('days', n);
end $$;
revoke all on function public.apply_loads_from_capture(text) from public, anon;

create or replace function public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare ok boolean; rid bigint; al text; res jsonb;
begin
  select exists(select 1 from public.capture_keys k where extensions.crypt(p_key, k.key_hash) = k.key_hash) into ok;
  if not ok then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  al := case when p_airline ilike 'pan am%' then 'Pan American' when p_airline ilike 'kingfisher%' then 'Kingfisher' when p_airline ilike 'ryanair%' then 'Ryanair'
             when p_airline ilike 'virgin%' then 'Virgin Atlantic' when p_airline ilike 'china eastern%' then 'China Eastern' when p_airline ilike 'malaysia%' then 'Malaysia Airlines' else p_airline end;
  if p_kind not in ('statement','events','loads','pnl','balance') then return jsonb_build_object('ok', false, 'error', 'bad kind'); end if;
  insert into public.game_capture_raw(airline, kind, page_url, rows) values (al, p_kind, p_page, coalesce(p_rows, '[]'::jsonb)) returning id into rid;
  res := public.parse_capture(rid) || jsonb_build_object('airline', al);
  if p_kind = 'loads' then res := res || public.apply_loads_from_capture(al); end if;
  return res;
end $$;;

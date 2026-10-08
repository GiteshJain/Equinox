create or replace function public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare ok boolean; rid bigint; al text; res jsonb;
begin
  select exists(select 1 from public.capture_keys k where extensions.crypt(p_key, k.key_hash) = k.key_hash) into ok;
  if not ok then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  al := case when p_airline ilike 'pan am%' then 'Pan American' when p_airline ilike 'kingfisher%' then 'Kingfisher' when p_airline ilike 'ryanair%' then 'Ryanair'
             when p_airline ilike 'virgin%' then 'Virgin Atlantic' when p_airline ilike 'china eastern%' then 'China Eastern' when p_airline ilike 'malaysia%' then 'Malaysia Airlines' else p_airline end;
  if p_kind not in ('statement','events','loads','pnl','balance','html') then return jsonb_build_object('ok', false, 'error', 'bad kind'); end if;
  insert into public.game_capture_raw(airline, kind, page_url, rows) values (al, p_kind, p_page, coalesce(p_rows, '[]'::jsonb)) returning id into rid;
  if p_kind = 'html' then return jsonb_build_object('ok', true, 'kind', 'html', 'rows', 1, 'airline', al); end if;   -- page inspection: stored only
  begin
    res := public.parse_capture(rid) || jsonb_build_object('airline', al);
    if p_kind = 'loads' then res := res || public.apply_loads_from_capture(al); end if;
  exception when others then
    res := jsonb_build_object('ok', false, 'airline', al, 'error', 'parse: ' || sqlerrm, 'raw_id', rid);
  end;
  return res;
end $$;;

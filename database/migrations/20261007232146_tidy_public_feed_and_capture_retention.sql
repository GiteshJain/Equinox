create or replace function public.site_public() returns jsonb language sql stable security definer set search_path = public as $$
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
$$;

create or replace function public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
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
end $$;

-- clean-up: the two scans taken with the faulty scanner, the faulty script copy, the inspection page
delete from public.game_snapshot_airlines where snapshot_id in (1, 2);
delete from public.game_snapshot_airports where snapshot_id in (1, 2);
delete from public.game_snapshots where id in (1, 2);
delete from public.planner_scripts where name = 'gscan.py';
delete from public.game_capture_raw where kind = 'html';;

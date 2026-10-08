-- the planner's route research moves out of its public page file, behind staff sign-in
create table if not exists public.planner_data (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
alter table public.planner_data enable row level security;
drop policy if exists "planner staff read data" on public.planner_data;
create policy "planner staff read data" on public.planner_data for select to authenticated using (public.is_planner_user());
create or replace function public.planner_data_set(p_secret text, p_key text, p_value jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  insert into public.planner_data(key, value) values (p_key, p_value) on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ok', true, 'bytes', length(p_value::text));
end $$;
revoke all on function public.planner_data_set(text, text, jsonb) from public;
grant execute on function public.planner_data_set(text, text, jsonb) to anon;
-- public feed: no cabin layouts either (seats on the website are estimated from aircraft type)
create or replace function public.site_public() returns jsonb language sql stable security definer set search_path = public as $$
  with s as (select json::jsonb j from public.planner_state where id = 'main'),
  live as (select distinct split_part(f->>'routeKey','|',1) al, split_part(f->>'routeKey','|',2) hub from s, jsonb_array_elements(j->'freqs') f)
  select jsonb_build_object(
    'updated_at', (select updated_at from public.planner_state where id = 'main'),
    'hubs', (select coalesce(jsonb_agg(jsonb_build_object('code', h->>'code', 'airline', h->>'airline', 'role', h->>'role')), '[]'::jsonb) from s, jsonb_array_elements(j->'ref'->'hubs') h where exists (select 1 from live where live.al = h->>'airline' and live.hub = h->>'code')),
    'tails', (select coalesce(jsonb_agg(jsonb_build_object('id', t->>'id', 'airline', t->>'airline', 'type', t->>'type')), '[]'::jsonb) from s, jsonb_array_elements(j->'tails') t),
    'configs', '[]'::jsonb,
    'freqs', (select coalesce(jsonb_agg(jsonb_build_object('r', f->>'routeKey', 't', f->>'tail', 'a', f->>'depHub', 'b', f->>'arrDest', 'c', f->>'depDest', 'd', f->>'arrHub', 'days', f->>'days', 'o', f->>'noOut', 'k', f->>'noBack', 'l', f->>'launched')), '[]'::jsonb) from s, jsonb_array_elements(j->'freqs') f),
    'onorder', '[]'::jsonb,
    'interline', (select coalesce(jsonb_agg(jsonb_build_object('pair', k, 'partner', j->'interline'->k->>'partner', 'date', j->'interline'->k->>'date')), '[]'::jsonb) from s, jsonb_object_keys(j->'interline') k where j->'interline'->k->>'status' = 'signed'),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'at', published_at, 'title', title, 'summary', summary, 'body', body, 'tag', tag, 'airline', airline, 'image', image, 'credit', image_credit) order by published_at desc), '[]'::jsonb) from public.site_posts),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'period', period, 'title', title, 'summary', case when kind = 'newsletter' then summary end, 'at', published_at, 'status', status, 'has_pdf', pdf_b64 is not null) order by coalesce(published_at, now() + interval '1 year') desc), '[]'::jsonb) from public.site_reports),
    'content', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.site_content where key <> 'markets')
  );
$$;
-- inside investor relations: report summaries come back
create or replace function public.site_investor(p_password text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare h text;
begin
  select pass_hash into h from public.report_access limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then return jsonb_build_object('ok', false); end if;
  return (with s as (select json::jsonb j from public.planner_state where id = 'main')
    select jsonb_build_object('ok', true, 'cash', j->'cash', 'fixed7', j->'fixed7',
      'capex', (select coalesce(jsonb_agg(jsonb_build_object('date', x->>'date', 'airline', x->>'airline', 'm', x->'amountM', 'kind', x->>'kind')), '[]'::jsonb) from jsonb_array_elements(j->'capex') x),
      'markets', (select value from public.site_content where key = 'markets'),
      'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'period', period, 'title', title, 'summary', summary, 'at', published_at, 'status', status, 'has_pdf', pdf_b64 is not null) order by coalesce(published_at, now() + interval '1 year') desc), '[]'::jsonb) from public.site_reports where kind <> 'newsletter')) from s);
end $$;;

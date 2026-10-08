create table if not exists public.site_posts (
  id bigserial primary key, slug text unique, published_at timestamptz not null default now(),
  title text not null, summary text, body text, tag text, airline text, image text, image_credit text, auto boolean not null default false
);
create table if not exists public.site_reports (
  id bigserial primary key, kind text not null check (kind in ('weekly','monthly','annual')), period text not null, title text not null,
  summary text, published_at timestamptz, status text not null default 'published', pdf_b64 text, unique (kind, period)
);
create table if not exists public.site_content (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
alter table public.site_posts enable row level security;
alter table public.site_reports enable row level security;
alter table public.site_content enable row level security;

-- everything the public website shows, in one call: no private planner fields
create or replace function public.site_public() returns jsonb language sql stable security definer set search_path = public as $$
  with s as (select json::jsonb j from public.planner_state where id = 'main')
  select jsonb_build_object(
    'updated_at', (select updated_at from public.planner_state where id = 'main'),
    'hubs', (select coalesce(jsonb_agg(jsonb_build_object('code', h->>'code', 'airline', h->>'airline', 'role', h->>'role', 'parent', h->>'parent', 'banks', h->'banks', 'mct', h->'mct')), '[]'::jsonb) from s, jsonb_array_elements(j->'ref'->'hubs') h),
    'tails', (select coalesce(jsonb_agg(jsonb_build_object('id', t->>'id', 'airline', t->>'airline', 'type', t->>'type', 'config', t->>'config', 'base', t->>'base')), '[]'::jsonb) from s, jsonb_array_elements(j->'tails') t),
    'configs', (select coalesce(jsonb_agg(jsonb_build_object('code', c->>'code', 'seats', c->'seats', 'cabin', c->>'cabin', 'c', c->'c', 'y', c->'y')), '[]'::jsonb) from s, jsonb_array_elements(j->'ref'->'configs') c),
    'freqs', (select coalesce(jsonb_agg(jsonb_build_object('r', f->>'routeKey', 't', f->>'tail', 'a', f->>'depHub', 'b', f->>'arrDest', 'c', f->>'depDest', 'd', f->>'arrHub', 'days', f->>'days', 'o', f->>'noOut', 'k', f->>'noBack', 'l', f->>'launched')), '[]'::jsonb) from s, jsonb_array_elements(j->'freqs') f),
    'onorder', (select coalesce(jsonb_agg(jsonb_build_object('reg', d->>'reg', 'airline', d->>'airline', 'type', d->>'type', 'utc', d->>'utc')), '[]'::jsonb) from s, jsonb_array_elements(j->'deliveries') d where not exists (select 1 from jsonb_array_elements(j->'tails') t where t->>'id' = d->>'reg')),
    'interline', (select coalesce(jsonb_agg(jsonb_build_object('pair', k, 'partner', j->'interline'->k->>'partner', 'date', j->'interline'->k->>'date')), '[]'::jsonb) from s, jsonb_object_keys(j->'interline') k where j->'interline'->k->>'status' = 'signed'),
    'cash', (select j->'cash' from s), 'fixed7', (select j->'fixed7' from s),
    'capex', (select coalesce(jsonb_agg(jsonb_build_object('date', x->>'date', 'airline', x->>'airline', 'm', x->'amountM', 'kind', x->>'kind')), '[]'::jsonb) from s, jsonb_array_elements(j->'capex') x),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'at', published_at, 'title', title, 'summary', summary, 'body', body, 'tag', tag, 'airline', airline, 'image', image, 'credit', image_credit) order by published_at desc), '[]'::jsonb) from public.site_posts),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'period', period, 'title', title, 'summary', summary, 'at', published_at, 'status', status, 'has_pdf', pdf_b64 is not null) order by coalesce(published_at, now() + interval '1 year') desc), '[]'::jsonb) from public.site_reports),
    'content', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.site_content)
  );
$$;
create or replace function public.site_report(p_id bigint) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('title', title, 'pdf', pdf_b64) from public.site_reports where id = p_id and status = 'published';
$$;
-- writing site content from the planning workspace (secret-checked)
create or replace function public.site_admin(p_secret text, p_kind text, p_payload jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.site_public() from public; revoke all on function public.site_report(bigint) from public; revoke all on function public.site_admin(text, text, jsonb) from public;
grant execute on function public.site_public() to anon, authenticated;
grant execute on function public.site_report(bigint) to anon, authenticated;
grant execute on function public.site_admin(text, text, jsonb) to anon, authenticated;;

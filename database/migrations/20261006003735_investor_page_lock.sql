-- the public feed no longer carries financials or market positions: those move behind the investor password
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
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'at', published_at, 'title', title, 'summary', summary, 'body', body, 'tag', tag, 'airline', airline, 'image', image, 'credit', image_credit) order by published_at desc), '[]'::jsonb) from public.site_posts),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'period', period, 'title', title, 'summary', summary, 'at', published_at, 'status', status, 'has_pdf', pdf_b64 is not null) order by coalesce(published_at, now() + interval '1 year') desc), '[]'::jsonb) from public.site_reports),
    'content', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.site_content where key <> 'markets')
  );
$$;
-- everything the investor page shows, only with the investor password
create or replace function public.site_investor(p_password text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare h text;
begin
  select pass_hash into h from public.report_access limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then return jsonb_build_object('ok', false); end if;
  return (with s as (select json::jsonb j from public.planner_state where id = 'main')
    select jsonb_build_object('ok', true, 'cash', j->'cash', 'fixed7', j->'fixed7',
      'capex', (select coalesce(jsonb_agg(jsonb_build_object('date', x->>'date', 'airline', x->>'airline', 'm', x->'amountM', 'kind', x->>'kind')), '[]'::jsonb) from jsonb_array_elements(j->'capex') x),
      'markets', (select value from public.site_content where key = 'markets')) from s);
end $$;
revoke all on function public.site_investor(text) from public;
grant execute on function public.site_investor(text) to anon, authenticated;;

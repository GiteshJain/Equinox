-- public feed: only hubs and bases that are actually operating, no bank or transfer times, no aircraft on order,
-- and investor reports listed by title only
create or replace function public.site_public() returns jsonb language sql stable security definer set search_path = public as $$
  with s as (select json::jsonb j from public.planner_state where id = 'main'),
  live as (select distinct split_part(f->>'routeKey','|',1) al, split_part(f->>'routeKey','|',2) hub from s, jsonb_array_elements(j->'freqs') f)
  select jsonb_build_object(
    'updated_at', (select updated_at from public.planner_state where id = 'main'),
    'hubs', (select coalesce(jsonb_agg(jsonb_build_object('code', h->>'code', 'airline', h->>'airline', 'role', h->>'role')), '[]'::jsonb) from s, jsonb_array_elements(j->'ref'->'hubs') h where exists (select 1 from live where live.al = h->>'airline' and live.hub = h->>'code')),
    'tails', (select coalesce(jsonb_agg(jsonb_build_object('id', t->>'id', 'airline', t->>'airline', 'type', t->>'type', 'config', t->>'config', 'base', t->>'base')), '[]'::jsonb) from s, jsonb_array_elements(j->'tails') t),
    'configs', (select coalesce(jsonb_agg(jsonb_build_object('code', c->>'code', 'seats', c->'seats')), '[]'::jsonb) from s, jsonb_array_elements(j->'ref'->'configs') c),
    'freqs', (select coalesce(jsonb_agg(jsonb_build_object('r', f->>'routeKey', 't', f->>'tail', 'a', f->>'depHub', 'b', f->>'arrDest', 'c', f->>'depDest', 'd', f->>'arrHub', 'days', f->>'days', 'o', f->>'noOut', 'k', f->>'noBack', 'l', f->>'launched')), '[]'::jsonb) from s, jsonb_array_elements(j->'freqs') f),
    'onorder', '[]'::jsonb,
    'interline', (select coalesce(jsonb_agg(jsonb_build_object('pair', k, 'partner', j->'interline'->k->>'partner', 'date', j->'interline'->k->>'date')), '[]'::jsonb) from s, jsonb_object_keys(j->'interline') k where j->'interline'->k->>'status' = 'signed'),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'at', published_at, 'title', title, 'summary', summary, 'body', body, 'tag', tag, 'airline', airline, 'image', image, 'credit', image_credit) order by published_at desc), '[]'::jsonb) from public.site_posts),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'period', period, 'title', title, 'summary', case when kind = 'newsletter' then summary end, 'at', published_at, 'status', status, 'has_pdf', pdf_b64 is not null) order by coalesce(published_at, now() + interval '1 year') desc), '[]'::jsonb) from public.site_reports),
    'content', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.site_content where key <> 'markets')
  );
$$;
-- the competitor scans: planner staff only (not any signed-in account)
drop policy if exists "signed-in can read snapshots" on public.game_snapshots;
drop policy if exists "signed-in can read snapshot airlines" on public.game_snapshot_airlines;
drop policy if exists "signed-in can read snapshot airports" on public.game_snapshot_airports;
create policy "planner staff read snapshots" on public.game_snapshots for select to authenticated using (public.is_planner_user());
create policy "planner staff read snapshot airlines" on public.game_snapshot_airlines for select to authenticated using (public.is_planner_user());
create policy "planner staff read snapshot airports" on public.game_snapshot_airports for select to authenticated using (public.is_planner_user());;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('site-photos', 'site-photos', true, 3145728, array['image/jpeg','image/webp','image/png'])
on conflict (id) do update set public = true, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg','image/webp','image/png'];

-- only planner staff (the same allowlist the planner uses) can add, change or remove photos; anyone can view them
drop policy if exists "planner staff upload site photos" on storage.objects;
drop policy if exists "planner staff update site photos" on storage.objects;
drop policy if exists "planner staff delete site photos" on storage.objects;
create policy "planner staff upload site photos" on storage.objects for insert to authenticated with check (bucket_id = 'site-photos' and public.is_planner_user());
create policy "planner staff update site photos" on storage.objects for update to authenticated using (bucket_id = 'site-photos' and public.is_planner_user()) with check (bucket_id = 'site-photos' and public.is_planner_user());
create policy "planner staff delete site photos" on storage.objects for delete to authenticated using (bucket_id = 'site-photos' and public.is_planner_user());

-- a destination photo for one airport (by code), or remove it
create or replace function public.site_set_airport_photo(p_code text, p_url text, p_credit text default null, p_path text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
create or replace function public.site_remove_airport_photo(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  update public.site_content set value = value #- array['airports', p_code], updated_at = now() where key = 'media';
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.site_set_airport_photo(text, text, text, text) from public, anon;
revoke all on function public.site_remove_airport_photo(text) from public, anon;
grant execute on function public.site_set_airport_photo(text, text, text, text) to authenticated;
grant execute on function public.site_remove_airport_photo(text) to authenticated;;

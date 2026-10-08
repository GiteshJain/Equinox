create or replace function public.site_set_airline_logo(p_airline text, p_url text, p_path text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
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
end $$;
create or replace function public.site_remove_airline_logo(p_airline text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_planner_user() then raise exception 'not allowed'; end if;
  update public.site_content set value = value #- array['logos', p_airline], updated_at = now() where key = 'media';
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.site_set_airline_logo(text, text, text) from public, anon;
revoke all on function public.site_remove_airline_logo(text) from public, anon;
grant execute on function public.site_set_airline_logo(text, text, text) to authenticated;
grant execute on function public.site_remove_airline_logo(text) to authenticated;;

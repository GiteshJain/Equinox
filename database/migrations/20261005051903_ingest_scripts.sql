create or replace function public.save_script(p_secret text, p_name text, p_content text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  insert into public.planner_scripts(name, content) values (p_name, p_content)
  on conflict (name) do update set content = excluded.content, updated_at = now();
  return jsonb_build_object('ok', true, 'name', p_name, 'bytes', length(p_content));
end $$;
revoke all on function public.save_script(text, text, text) from public;
grant execute on function public.save_script(text, text, text) to anon, authenticated;;

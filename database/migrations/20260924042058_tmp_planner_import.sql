
create or replace function public.planner_import(p_table text, p_id text, p_json text, p_saved bigint, p_secret text)
returns text language plpgsql security definer set search_path = public as $$
begin
  if p_secret <> '4e7f6135d71bcd7c80402b966bec6864' then raise exception 'denied'; end if;
  if p_table = 'state' then
    insert into planner_state (id, json, saved_at) values (p_id, p_json, p_saved)
    on conflict (id) do update set json = excluded.json, saved_at = excluded.saved_at;
  elsif p_table = 'loads' then
    insert into planner_loads (month, json, saved_at) values (p_id, p_json, p_saved)
    on conflict (month) do update set json = excluded.json, saved_at = excluded.saved_at;
  end if;
  return 'ok';
end $$;
grant execute on function public.planner_import(text, text, text, bigint, text) to anon;
;

create or replace function public.export_planner_data(p_secret text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return (select jsonb_object_agg(key, value) from public.planner_data);
end $$;
revoke all on function public.export_planner_data(text) from public;
grant execute on function public.export_planner_data(text) to anon;;

create or replace function public.export_for_report(p_secret text, p_kind text, p_arg text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'snapshots' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'taken_at', taken_at, 'week', week, 'status', status) order by id), '[]'::jsonb) from public.game_snapshots);
  elsif p_kind = 'airlines' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', enterprise_id, 'name', name, 'flights', flights, 'n_weekly', n_weekly)), '[]'::jsonb) from public.game_snapshot_airlines where snapshot_id = p_arg::bigint);
  elsif p_kind = 'airports' then
    return (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'info', info, 'stations', stations, 'news', news)), '[]'::jsonb) from public.game_snapshot_airports where snapshot_id = p_arg::bigint);
  elsif p_kind = 'planner' then
    return jsonb_build_object('state', (select json::jsonb from public.planner_state where id = 'main'),
                              'loads', (select coalesce(jsonb_object_agg(month, json::jsonb), '{}'::jsonb) from public.planner_loads));
  end if;
  raise exception 'unknown kind';
end $$;
revoke all on function public.export_for_report(text, text, text) from public;
grant execute on function public.export_for_report(text, text, text) to anon, authenticated;;

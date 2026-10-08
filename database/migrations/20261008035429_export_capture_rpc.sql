-- captured game data for Claude's report scripts (secret-checked, like the other exports)
create or replace function public.export_capture(p_secret text, p_days int default 8) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'pnl', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) from public.game_flight_pnl f where f.ts >= now() - make_interval(days => p_days)),
    'loads', (select coalesce(jsonb_agg(to_jsonb(l) - 'captured_at'), '[]'::jsonb) from public.game_loads l where l.flight_date >= current_date - (p_days + 1)),
    'events', (select coalesce(jsonb_agg(to_jsonb(e) - 'captured_at'), '[]'::jsonb) from public.game_events e where e.event_date >= current_date - p_days),
    'balance', (select coalesce(jsonb_agg(to_jsonb(b)), '[]'::jsonb) from public.game_balance b where b.account like '2800%' and b.captured_on >= current_date - p_days),
    'ops', (select coalesce(jsonb_agg(to_jsonb(o)), '[]'::jsonb) from public.game_ops_recent o),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('airline', airline, 'kind', kind, 'captured_at', captured_at)), '[]'::jsonb) from public.game_capture_raw where captured_at >= now() - make_interval(days => p_days) and kind <> 'html'));
end $$;
revoke all on function public.export_capture(text, int) from public;
grant execute on function public.export_capture(text, int) to anon;;

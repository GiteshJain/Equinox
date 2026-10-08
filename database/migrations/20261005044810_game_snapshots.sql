create table if not exists public.game_snapshots (
  id bigserial primary key,
  taken_at timestamptz not null default now(),
  week text,
  note text,
  status text not null default 'running'
);
create table if not exists public.game_snapshot_airlines (
  snapshot_id bigint not null references public.game_snapshots(id) on delete cascade,
  enterprise_id int not null,
  name text,
  flights jsonb not null default '[]'::jsonb,
  n_flights int,
  n_weekly int,
  n_airports int,
  primary key (snapshot_id, enterprise_id)
);
create table if not exists public.game_snapshot_airports (
  snapshot_id bigint not null references public.game_snapshots(id) on delete cascade,
  code text not null,
  airport_id int,
  info jsonb,
  stations jsonb,
  news jsonb,
  primary key (snapshot_id, code)
);
create table if not exists public.ingest_secret (secret text not null);

alter table public.game_snapshots enable row level security;
alter table public.game_snapshot_airlines enable row level security;
alter table public.game_snapshot_airports enable row level security;
alter table public.ingest_secret enable row level security;

create policy "signed-in can read snapshots" on public.game_snapshots for select to authenticated using (true);
create policy "signed-in can read snapshot airlines" on public.game_snapshot_airlines for select to authenticated using (true);
create policy "signed-in can read snapshot airports" on public.game_snapshot_airports for select to authenticated using (true);

-- the weekly scanner writes through this function only; it checks a secret kept in a table nobody else can read
create or replace function public.ingest_snapshot(p_secret text, p_kind text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not exists (select 1 from public.ingest_secret where secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'start' then
    insert into public.game_snapshots(week, note) values (p_payload->>'week', p_payload->>'note') returning id into v_id;
    return jsonb_build_object('snapshot_id', v_id);
  elsif p_kind = 'airline' then
    insert into public.game_snapshot_airlines(snapshot_id, enterprise_id, name, flights, n_flights, n_weekly, n_airports)
    values ((p_payload->>'snapshot_id')::bigint, (p_payload->>'enterprise_id')::int, p_payload->>'name', coalesce(p_payload->'flights','[]'::jsonb),
            (p_payload->>'n_flights')::int, (p_payload->>'n_weekly')::int, (p_payload->>'n_airports')::int)
    on conflict (snapshot_id, enterprise_id) do update set name = excluded.name, flights = excluded.flights, n_flights = excluded.n_flights, n_weekly = excluded.n_weekly, n_airports = excluded.n_airports;
    return jsonb_build_object('ok', true);
  elsif p_kind = 'airport' then
    insert into public.game_snapshot_airports(snapshot_id, code, airport_id, info, stations, news)
    values ((p_payload->>'snapshot_id')::bigint, p_payload->>'code', (p_payload->>'airport_id')::int, p_payload->'info', p_payload->'stations', p_payload->'news')
    on conflict (snapshot_id, code) do update set airport_id = excluded.airport_id, info = excluded.info, stations = excluded.stations, news = excluded.news;
    return jsonb_build_object('ok', true);
  elsif p_kind = 'finish' then
    update public.game_snapshots set status = 'done', note = coalesce(p_payload->>'note', note) where id = (p_payload->>'snapshot_id')::bigint;
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown kind';
end $$;
revoke all on function public.ingest_snapshot(text, text, jsonb) from public;
grant execute on function public.ingest_snapshot(text, text, jsonb) to anon, authenticated;;

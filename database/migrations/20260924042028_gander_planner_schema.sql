
create table if not exists public.planner_users (
  email text primary key
);
insert into public.planner_users (email) values ('jgitesh88@gmail.com') on conflict do nothing;

create table if not exists public.planner_state (
  id text primary key default 'main',
  json text not null,
  saved_at bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.planner_loads (
  month text primary key,
  json text not null,
  saved_at bigint not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.planner_users enable row level security;
alter table public.planner_state enable row level security;
alter table public.planner_loads enable row level security;

create or replace function public.is_planner_user() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.planner_users u where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
revoke all on function public.is_planner_user() from public;
grant execute on function public.is_planner_user() to authenticated;

create policy "planner users read state"   on public.planner_state for select to authenticated using (public.is_planner_user());
create policy "planner users insert state" on public.planner_state for insert to authenticated with check (public.is_planner_user());
create policy "planner users update state" on public.planner_state for update to authenticated using (public.is_planner_user()) with check (public.is_planner_user());
create policy "planner users read loads"   on public.planner_loads for select to authenticated using (public.is_planner_user());
create policy "planner users insert loads" on public.planner_loads for insert to authenticated with check (public.is_planner_user());
create policy "planner users update loads" on public.planner_loads for update to authenticated using (public.is_planner_user()) with check (public.is_planner_user());
create policy "planner users see themselves" on public.planner_users for select to authenticated using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end $$;
create trigger planner_state_touch before update on public.planner_state for each row execute function public.touch_updated_at();
create trigger planner_loads_touch before update on public.planner_loads for each row execute function public.touch_updated_at();
;

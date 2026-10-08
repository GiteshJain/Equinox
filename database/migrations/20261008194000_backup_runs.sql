-- decision #6: one row per run of the nightly backup (repository equinox-backups), so the planner can show whether
-- last night's copy worked and warn when there's no good copy. The job writes with the database connection string;
-- planner staff can read.
create table if not exists public.backup_runs (
  id bigint generated always as identity primary key,
  ran_at timestamptz not null default now(),
  kind text not null check (kind in ('nightly', 'manual', 'test')),
  ok boolean not null,
  tables integer,
  rows bigint,
  files integer,
  bytes bigint,
  commit_sha text,
  note text
);
alter table public.backup_runs enable row level security;
drop policy if exists "planner staff read backup_runs" on public.backup_runs;
create policy "planner staff read backup_runs" on public.backup_runs for select to authenticated using (public.is_planner_user());
drop policy if exists "backup job writes backup_runs" on public.backup_runs;
create policy "backup job writes backup_runs" on public.backup_runs for insert to postgres with check (true);
grant select on public.backup_runs to authenticated;
grant select, insert on public.backup_runs to postgres;

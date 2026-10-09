-- Backups move to Cloudflare R2 (decision #16; spec docs/specs/2026-10-09-backups-to-r2.md, PR 2).
-- backup_runs gets object_key, the R2 key (object name) of each run's copy. The backup job fills it in once it stops
-- committing copies to git (equinox-backups PR 3); earlier runs keep their commit_sha. Adds a column and updates
-- descriptions; removes nothing.

alter table public.backup_runs add column if not exists object_key text;

comment on column public.backup_runs.object_key is 'R2 key of that run''s copy (from 9 Oct; earlier runs have commit_sha)';

comment on table public.backup_runs is 'One row per run of the nightly backup (decision #6): when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied. The copies live in Cloudflare R2 (decision #16): each night''s is kept 30 days, and the month''s first is kept for good, also as a file on a monthly GitHub release in equinox-backups. Written by the backup job in equinox-backups. Read by the planner''s Capture board and the backup line on Home.';

-- GITESH RUNS THIS FILE HIMSELF in Supabase's SQL editor (operating manual §1), AFTER the Building chat has applied
-- 20261011150000_jobs.sql: it takes away access and drops a rule, so it isn't applied from a chat. Paste the two lines
-- below and press Run; the Building chat then records it and checks it.
--
-- Decision #13, build pull request 7 (design §3.12, §3.13, §5). No row changes.
--   1. Signed-in accounts can no longer write the retired backup_runs_before_13 (the old backup_runs table). Supabase's
--      old defaults may still give them write rights there: its row rules refuse their rows, but not a truncate. They
--      keep reading it, as staff.
--   2. Its rule letting the backup job add rows goes: the job now writes through the backup_runs view into job_runs,
--      and nothing writes the old table.
-- It needs the main migration first (before it, the table still has its old name and is the one the backup job writes).
revoke insert, update, delete, truncate, references, trigger on public.backup_runs_before_13 from authenticated;
drop policy if exists "backup job writes backup_runs" on public.backup_runs_before_13;

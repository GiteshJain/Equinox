-- #13 pull request 7 (the jobs): saved before the new migrations, for database/tests/jobs_test.sql.
--   backup_runs: every run as it reads (every column but id, which job_runs numbers for itself), so the test can show the
--     view reads exactly as before, the night the table becomes a view and every night after;
--   jobs_state: whether the copy had the jobs already (a backup carries pg_cron but never its schedules, so the test
--     knows whether this rehearsal scheduled them).
create table rehearsal_before.backup_runs as
select ran_at, kind, ok, tables, rows, files, bytes, commit_sha, note, object_key from public.backup_runs;

create table rehearsal_before.jobs_state as
select to_regprocedure('private.schedule_jobs()') is not null as existed;

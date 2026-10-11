-- The automatic jobs (#13 build, pull request 7; design §3.11, §3.12, §5, §7; the jobs brief). Run by database/rehearse.sh
-- on the copy of last night's backup, after the new migrations, inside a transaction that is rolled back. A failed
-- check stops with an error that says which (dates, counts and job names, never figures).
--   1. The scheduler: pg_cron is on, and the night the jobs' migration is applied the copy has the two jobs as it left
--      them (rehearse.sh pauses them for the tests and keeps that state in rehearsal_before.cron_jobs; a backup never
--      carries schedules, so on later nights there are none). Every night: private.schedule_jobs() makes exactly the
--      two, active, at 10:00 and 10:20 UTC, run as postgres, and again changes nothing. The new functions are
--      postgres's only, run as the caller with an empty search path; capture_ingest() no longer deletes raw pages.
--   2. backup_runs reads exactly as before (every column but id), the night it becomes a view and after; an insert as
--      the backup job makes it lands in job_runs and reads back the same; what the old table refused is refused; only
--      staff read it.
--   3. The 10:00 UTC fallback: a day with a snapshot is left alone; the day just ended without one, and a missed day
--      before it, each get one (source fallback, complete as the capture was, at the end of the capture day, cash as
--      design §7 says); every other day is untouched; one job_runs row a run.
--   4. The 10:20 UTC clean-ups: raw pages older than 14 days go and younger ones stay; with the statement clean-up off
--      (as it ships) no statement line goes; switched on, only lines older than 14 days that are in game_flights or
--      game_payments go, and if any isn't, none does and the run fails; one job_runs row a run.

-- ---------------------------------------------------------------- 1. the scheduler and the catalogue
do $test$
declare
  v_fresh boolean; bad text; n int; r record; v_jobs jsonb; v_again jsonb;
  fns regprocedure[] := array['private.backup_runs_insert()', 'private.job_snapshot_fallback(timestamptz)',
    'private.job_cleanup(timestamptz)', 'private.archive_tables()', 'private.archive_kept_from(text, date)',
    'private.archive_check_args(date, text)', 'private.archive_where(date, text, text)', 'private.archive_order(text, text)',
    'private.archive_select(date, text)', 'private.archive_checksum(date, text)', 'private.archive_manifest(date, text)',
    'private.archive_due(date)', 'private.archive_delete(date, text, bigint, text)', 'private.schedule_jobs()']::regprocedure[];
begin
  assert exists (select 1 from pg_extension where extname = 'pg_cron'), 'pg_cron isn''t switched on';
  -- the night the migration runs on the copy: the jobs as it scheduled them (before rehearse.sh paused them)
  if to_regclass('rehearsal_before.jobs_state') is not null then
    execute 'select not existed from rehearsal_before.jobs_state limit 1' into v_fresh;
  end if;
  if coalesce(v_fresh, false) then
    if to_regclass('rehearsal_before.cron_jobs') is not null then
      execute $q$select string_agg(format('%s %s %s %s %s', jobname, schedule, command, username, active), '; ' order by jobname)
                   from rehearsal_before.cron_jobs where jobname like 'equinox-%'$q$ into bad;
    else
      select string_agg(format('%s %s %s %s %s', jobname, schedule, command, username, active), '; ' order by jobname) into bad
        from cron.job where jobname like 'equinox-%';
    end if;
    assert bad = 'equinox-cleanup 20 10 * * * select private.job_cleanup() postgres t; equinox-snapshot-fallback 0 10 * * * select private.job_snapshot_fallback() postgres t',
      'the migration didn''t leave the two jobs as designed: ' || coalesce(bad, 'none');
  end if;
  -- private.schedule_jobs(), from nothing and again
  perform cron.unschedule(j.jobname) from cron.job j where j.jobname like 'equinox-%';
  v_jobs := private.schedule_jobs();
  v_again := private.schedule_jobs();
  assert v_jobs = '[{"job": "equinox-cleanup", "active": true, "command": "select private.job_cleanup()", "schedule": "20 10 * * *"}, {"job": "equinox-snapshot-fallback", "active": true, "command": "select private.job_snapshot_fallback()", "schedule": "0 10 * * *"}]'::jsonb,
    'private.schedule_jobs() made: ' || v_jobs::text;
  assert v_again = v_jobs and (select count(*) from cron.job where jobname like 'equinox-%') = 2, 'private.schedule_jobs() a second time changed the jobs';
  assert (select bool_and(username = 'postgres' and database = current_database()) from cron.job where jobname like 'equinox-%'),
    'the jobs don''t run as postgres in this database';

  -- the new functions: postgres only, run as the caller, empty search path
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid = any (fns)
     and (p.prosecdef or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
          or has_function_privilege('service_role', p.oid, 'execute') or not coalesce('search_path=""' = any (p.proconfig), false));
  assert bad is null, 'functions open to others, run as owner or without an empty search path: ' || bad;
  assert (select count(*) from pg_proc p where p.oid = any (fns)) = cardinality(fns), 'a new function is missing';
  -- capture_ingest() is called as before, and the raw pages are the clean-up's now
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.oid = 'public.capture_ingest(text, text, text, text, jsonb)'::regprocedure
     and not (p.prosecdef and has_function_privilege('anon', p.oid, 'execute') and coalesce('search_path=""' = any (p.proconfig), false));
  assert bad is null, 'capture_ingest() isn''t called as before';
  assert pg_get_functiondef('public.capture_ingest(text, text, text, text, jsonb)'::regprocedure) !~* 'delete\s+from\s+public\.game_capture_raw',
    'capture_ingest() still deletes raw pages';

  -- backup_runs: a view that shows the caller only what it may read, with its insert trigger; anon nothing, staff read
  assert (select c.relkind = 'v' and coalesce('security_invoker=true' = any (c.reloptions), false) from pg_class c
           where c.oid = 'public.backup_runs'::regclass), 'backup_runs isn''t a security_invoker view';
  assert exists (select 1 from pg_trigger t where t.tgrelid = 'public.backup_runs'::regclass and t.tgname = 'backup_runs_insert'
                    and t.tgfoid = 'private.backup_runs_insert()'::regprocedure), 'backup_runs has no insert trigger';
  select string_agg(x.priv, ', ') into bad from unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) x(priv)
   where has_table_privilege('anon', 'public.backup_runs', x.priv);
  assert bad is null, 'anon holds on backup_runs: ' || bad;
  select string_agg(x.priv, ', ') into bad from unnest(array['insert', 'update', 'delete', 'truncate', 'references', 'trigger']) x(priv)
   where has_table_privilege('authenticated', 'public.backup_runs', x.priv);
  assert bad is null, 'authenticated can write backup_runs: ' || bad;
  assert has_table_privilege('authenticated', 'public.backup_runs', 'select'), 'staff can''t read backup_runs';
  assert to_regclass('public.backup_runs_before_13') is not null, 'backup_runs_before_13 is missing';
  raise notice 'pg_cron on; %; schedule_jobs() makes equinox-snapshot-fallback (0 10 * * *) and equinox-cleanup (20 10 * * *), active, as postgres, and again changes nothing; % new functions postgres only; capture_ingest() leaves raw pages to the clean-up',
    case when coalesce(v_fresh, false) then 'the migration scheduled both jobs (paused on this copy for the tests)'
         else 'the copy had the jobs already (a backup carries no schedules)' end, cardinality(fns);
end
$test$;

-- ---------------------------------------------------------------- 2. backup_runs reads as before, and its insert
do $test$
declare n_before bigint; n_now bigint; bad bigint; v_id bigint; j record; v_moved boolean; v_old bigint;
begin
  assert to_regclass('rehearsal_before.backup_runs') is not null, 'the backup runs weren''t saved before the changes (database/tests/before/jobs_before.sql)';
  execute 'select count(*) from rehearsal_before.backup_runs' into n_before;
  select count(*) into n_now from public.backup_runs;
  assert n_now = n_before, format('backup_runs has %s rows, %s before', n_now, n_before);
  execute $q$select count(*) from (
      (select ran_at, kind, ok, tables, rows, files, bytes, commit_sha, note, object_key from rehearsal_before.backup_runs
       except all
       select ran_at, kind, ok, tables, rows, files, bytes, commit_sha, note, object_key from public.backup_runs)
      union all
      (select ran_at, kind, ok, tables, rows, files, bytes, commit_sha, note, object_key from public.backup_runs
       except all
       select ran_at, kind, ok, tables, rows, files, bytes, commit_sha, note, object_key from rehearsal_before.backup_runs)) x$q$
     into bad;
  assert bad = 0, format('%s backup run(s) read differently from before', bad);
  execute 'select not backup_runs_moved from rehearsal_before.jobs_state limit 1' into v_moved;
  if v_moved then
    select count(*) into v_old from public.backup_runs_before_13;
    assert v_old = n_before, format('backup_runs_before_13 has %s rows, %s before', v_old, n_before);
  end if;

  -- as the backup job writes it (scripts/report.sh): the newest row, the same values back, a job_runs row of job backup
  insert into public.backup_runs (kind, ok, tables, rows, files, bytes, object_key, note)
  values ('test', true, 3, 1234567890123, 5, 6789012345, 'test/equinox-backup-test.tar.gz', null) returning id into v_id;
  select * into j from public.job_runs where id = v_id;
  assert j.job = 'backup' and j.status = 'ok' and j.started_at = j.finished_at and j.world_id is null
     and j.details = '{"kind": "test", "rows": 1234567890123, "bytes": 6789012345, "files": 5, "tables": 3, "object_key": "test/equinox-backup-test.tar.gz"}'::jsonb,
    'the insert didn''t land in job_runs as a backup row: ' || coalesce(j.details::text, 'no row');
  assert (select (b.kind, b.ok, b.tables, b.rows, b.files, b.bytes, b.object_key, b.note, b.commit_sha)
                 is not distinct from ('test', true, 3, 1234567890123::bigint, 5, 6789012345::bigint, 'test/equinox-backup-test.tar.gz', null::text, null::text)
            from public.backup_runs b where b.id = v_id), 'the inserted run reads back differently';
  insert into public.backup_runs (kind, ok, note) values ('nightly', false, 'restore check failed (above)') returning id into v_id;
  assert (select status = 'failed' and note = 'restore check failed (above)' from public.job_runs where id = v_id), 'a failed run isn''t failed in job_runs';
  assert (select b.id from public.backup_runs b order by b.ran_at desc, b.id desc limit 1) = v_id, 'the newest run isn''t first';
  -- refused as the old table refused them
  begin
    insert into public.backup_runs (kind, ok) values ('weekly', true);
    assert false, 'a kind other than nightly, manual or test was taken';
  exception when check_violation then null;
  end;
  begin
    insert into public.backup_runs (kind, ok) values ('manual', null);
    assert false, 'a run without ok was taken';
  exception when not_null_violation then null;
  end;
  raise notice 'backup_runs: % run(s) read exactly as before (every column but id)%; an insert as the backup job makes it lands in job_runs (job backup) and reads back the same; a bad kind or no ok refused',
    n_before, case when v_moved then ', and the old table kept them as backup_runs_before_13' else '' end;
end
$test$;

-- only staff read it
create temporary table t_backup_seen (who text primary key, n bigint) on commit drop;
grant insert on t_backup_seen to authenticated;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d2", "email": "jobs-not-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
insert into t_backup_seen select 'not staff', count(*) from public.backup_runs;
reset role;
insert into public.planner_users (email) values ('jobs-staff@example.com') on conflict do nothing;
do $$ begin perform set_config('request.jwt.claims',
  '{"sub": "00000000-0000-4000-8000-0000000000d1", "email": "jobs-staff@example.com", "role": "authenticated"}', true); end $$;
set local role authenticated;
insert into t_backup_seen select 'staff', count(*) from public.backup_runs;
reset role;
do $test$
begin
  assert (select n from t_backup_seen where who = 'not staff') = 0, 'an account that isn''t staff reads backup_runs';
  assert (select n from t_backup_seen where who = 'staff') = (select count(*) from public.backup_runs), 'staff don''t read every backup run';
end
$test$;

-- ---------------------------------------------------------------- 3. the 10:00 UTC fallback
create temporary table t_days (airline_id bigint, day date, complete boolean, source text, taken_at timestamptz,
  aircraft_by_type jsonb, aircraft_total int, on_order int, weekly_departures int, weekly_seats int, destinations int,
  cash numeric, fixed_next7 numeric, cash_at timestamptz) on commit drop;
do $test$
declare
  w bigint := (select id from public.worlds where is_default); v_at timestamptz; v_last date; v_gap date; v_res jsonb;
  j record; n bigint; bad text; v_runs bigint; t0 timestamptz; v_ms numeric; v_expect int; v_earlier int := 0; v_typed int := 0;
  v_day_bal int := 0;
begin
  if not exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where a.world_id = w and a.active and g.kind = 'ours') then
    raise notice 'fallback: the copy has no active airline of ours, nothing to check'; return;
  end if;
  -- the run as pg_cron starts it: just after today's 10:00 UTC (the end of the capture day just ended)
  v_at := private.capture_day_start(w, private.capture_day(w, now())) + interval '1 minute';
  v_last := private.capture_day(w, v_at) - 1;
  v_gap := v_last - 3;
  v_expect := (select count(*) from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                where a.world_id = w and a.active and g.kind = 'ours' and (a.founded_on is null or a.founded_on <= v_last));

  -- a. every day up to the one just ended has its snapshot (whatever the copy had, after one run); a second run changes none
  perform private.job_snapshot_fallback(v_at);
  insert into t_days select airline_id, day, complete, source, taken_at, aircraft_by_type, aircraft_total, on_order,
         weekly_departures, weekly_seats, destinations, cash, fixed_next7, cash_at
    from public.airline_days where world_id = w;
  select count(*) into v_runs from public.job_runs where job = 'snapshot_fallback';
  v_res := private.job_snapshot_fallback(v_at);
  assert (select count(*) from public.job_runs where job = 'snapshot_fallback') = v_runs + 1, 'a run didn''t write exactly one job_runs row';
  select * into j from public.job_runs where job = 'snapshot_fallback' order by id desc limit 1;
  assert j.status = 'ok' and j.world_id = w and j.for_day = v_last and (j.details ->> 'taken')::boolean = false
     and j.details -> 'filled' = '[]'::jsonb, format('a run with every snapshot there: %s %s', j.status, j.note);
  select count(*) into n from (
    (select airline_id, day, complete, source, taken_at, aircraft_by_type, aircraft_total, on_order, weekly_departures, weekly_seats,
            destinations, cash, fixed_next7, cash_at from public.airline_days where world_id = w
     except select * from t_days)
    union all
    (select * from t_days except select airline_id, day, complete, source, taken_at, aircraft_by_type, aircraft_total, on_order,
            weekly_departures, weekly_seats, destinations, cash, fixed_next7, cash_at from public.airline_days where world_id = w)) x;
  assert n = 0, format('a run with every snapshot there changed %s airline day(s)', n);
  assert exists (select 1 from public.airline_days where world_id = w and day = v_last), 'the day just ended has no snapshot after a run';

  -- b. the day just ended without a snapshot, and a missed day three days before it
  delete from public.airline_days where world_id = w and day in (v_last, v_gap);
  delete from t_days where day in (v_last, v_gap);
  t0 := clock_timestamp();
  v_res := private.job_snapshot_fallback(v_at);
  v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  select * into j from public.job_runs where job = 'snapshot_fallback' order by id desc limit 1;
  assert j.status = 'ok' and j.for_day = v_last and (j.details ->> 'taken')::boolean and j.details -> 'filled' = to_jsonb(array[v_gap]),
    format('the run that had to take the snapshot: %s, %s (%s)', j.status, j.note, j.details);
  select string_agg(format('%s %s', d.day, d.airline_id), ', ') into bad from (
    select g.d::date as day, a.id as airline_id
      from public.airlines a join public.groups gr on gr.id = a.group_id and gr.world_id = a.world_id
      cross join (values (v_last), (v_gap)) g(d)
     where a.world_id = w and a.active and gr.kind = 'ours' and (a.founded_on is null or a.founded_on <= g.d)) d
   where not exists (select 1 from public.airline_days x where x.airline_id = d.airline_id and x.day = d.day and x.source = 'fallback'
                        and x.complete = private.capture_day_complete(w, d.day)
                        and x.taken_at = least(private.capture_day_start(w, d.day + 1), v_at));
  assert bad is null, 'missing or wrongly marked fallback days: ' || bad;
  -- cash (design §7): that capture day's latest balance up to then; else a figure typed for the day; else the latest
  -- balance before (with its time)
  select string_agg(format('%s %s (%s)', d.day, d.airline_id, x.src), ', ') into bad
    from public.airline_days d
    cross join lateral (
      select coalesce(
        (select jsonb_build_object('src', 'day', 'cash', b.amount, 'at', b.captured_at) from public.game_balance b
          where b.airline_id = d.airline_id and b.capture_day = d.day and b.account like '2800%' and b.amount is not null
            and b.captured_at <= d.taken_at order by b.captured_at desc limit 1),
        (select jsonb_build_object('src', 'typed', 'cash', c.cash, 'at', null) from public.cash_entries c
          where c.airline_id = d.airline_id and c.day = d.day and c.cash is not null),
        (select jsonb_build_object('src', 'earlier', 'cash', b.amount, 'at', b.captured_at) from public.game_balance b
          where b.airline_id = d.airline_id and b.account like '2800%' and b.amount is not null and b.captured_at <= d.taken_at
          order by b.captured_at desc limit 1),
        '{"src": "none"}'::jsonb) as e) e
    cross join lateral (select e.e ->> 'src' as src) x
   where d.world_id = w and d.day in (v_last, v_gap)
     and (d.cash is distinct from (e.e ->> 'cash')::numeric or d.cash_at is distinct from (e.e ->> 'at')::timestamptz);
  assert bad is null, 'fallback days whose cash isn''t design §7''s: ' || bad;
  select count(*) filter (where x.src = 'day'), count(*) filter (where x.src = 'earlier')
    into v_day_bal, v_earlier
    from public.airline_days d
    cross join lateral (select case when d.cash_at is null then 'typed or none'
                                    when exists (select 1 from public.game_balance b where b.airline_id = d.airline_id and b.capture_day = d.day
                                                    and b.captured_at = d.cash_at and b.account like '2800%') then 'day'
                                    else 'earlier' end as src) x
   where d.world_id = w and d.day in (v_last, v_gap);
  -- every other day as it was
  select count(*) into n from (
    (select airline_id, day, complete, source, taken_at, aircraft_by_type, aircraft_total, on_order, weekly_departures, weekly_seats,
            destinations, cash, fixed_next7, cash_at from public.airline_days where world_id = w and day not in (v_last, v_gap)
     except select * from t_days)
    union all
    (select * from t_days except select airline_id, day, complete, source, taken_at, aircraft_by_type, aircraft_total, on_order,
            weekly_departures, weekly_seats, destinations, cash, fixed_next7, cash_at from public.airline_days where world_id = w and day not in (v_last, v_gap))) x;
  assert n = 0, format('the fallback changed %s airline day(s) that had a snapshot', n);
  -- and a capture's snapshot is never replaced by it
  assert not exists (select 1 from t_days t where t.source = 'capture'
                        and not exists (select 1 from public.airline_days d where d.airline_id = t.airline_id and d.day = t.day and d.source = 'capture')),
    'a snapshot from the capture was replaced';
  raise notice 'fallback: with every snapshot there a run changes nothing (one job_runs row, ok); with % (just ended) and % (missed) taken out, one run takes both (source fallback, % airline(s) each, complete as the capture was, as at the end of the capture day; cash: % from that capture day''s balance, % from an earlier one, the rest typed or none) and leaves the other % day(s) alone, in % ms',
    to_char(v_last, 'DD Mon'), to_char(v_gap, 'DD Mon'), v_expect, v_day_bal, v_earlier, (select count(distinct day) from t_days), v_ms;
end
$test$;

-- ---------------------------------------------------------------- 4. the 10:20 UTC clean-ups
do $test$
declare
  w bigint := (select id from public.worlds where is_default); a record; v_at timestamptz := now(); v_cut timestamptz;
  n_raw_old bigint; v_young bigint; v_old_page bigint; j record; v_flight bigint; n_lines bigint; n_old bigint; v_runs bigint;
  v_recent_ts timestamptz; v_old_ts timestamptz;
begin
  v_cut := v_at - interval '14 days';
  select al.id, al.planner_name, al.world_id into a
    from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
   where al.world_id = w and al.active and g.kind = 'ours' order by al.id limit 1;
  if a.id is null then raise notice 'clean-ups: the copy has no active airline of ours, nothing to check'; return; end if;
  assert (select bool_and(s.value = 'false'::jsonb) and count(*) = (select count(*) from public.worlds)
            from public.settings s where s.key = 'statement_cleanup_enabled' and s.airline_id is null),
    'statement_cleanup_enabled isn''t false for every world (it ships switched off)';

  -- raw pages: one 15 days old, one 13 days old
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (w, a.id, a.planner_name, 'html', 'jobs-test', '[]', v_at - interval '15 days') returning id into v_old_page;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (w, a.id, a.planner_name, 'html', 'jobs-test', '[]', v_at - interval '13 days') returning id into v_young;
  select count(*) into n_raw_old from public.game_capture_raw where world_id = w and captured_at < v_cut;

  -- statement lines 16 days old: one tied to its flight, one a payment; and a recent one in neither (never touched)
  v_old_ts := date_trunc('minute', v_at - interval '16 days'); v_recent_ts := date_trunc('minute', v_at - interval '2 days');
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, dep_at,
                                   pax_income, income_total, cost_total, money_captured_at)
  values (w, a.id, v_old_ts, 9, 1, 'ZZA', 'ZZB', v_old_ts, 100, 100, 40, v_at - interval '16 days') returning id into v_flight;
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id)
  values (w, a.id, a.planner_name, v_old_ts, 'Passenger transport income (ZZA-ZZB) jobs-test', 100, 'C', 1, 9, v_flight);
  insert into public.game_payments (world_id, airline_id, paid_at, kind, descr, amount, side, occ, statement_blk)
  values (w, a.id, v_old_ts, 'other', 'jobs-test payment', 7, 'D', 1, 0);
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id)
  values (w, a.id, a.planner_name, v_old_ts, 'jobs-test payment', 7, 'D', 1, 0, null);
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id)
  values (w, a.id, a.planner_name, v_recent_ts, 'jobs-test recent', 3, 'D', 1, 0, null);
  select count(*) into n_lines from public.game_statement where world_id = w;
  select count(*) into n_old from public.game_statement where world_id = w and ts < v_cut;

  -- switched off, as it ships: raw pages go, statement lines stay
  select count(*) into v_runs from public.job_runs where job = 'cleanup';
  perform private.job_cleanup(v_at);
  assert (select count(*) from public.job_runs where job = 'cleanup') = v_runs + (select count(*) from public.worlds x
            where exists (select 1 from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
                           where al.world_id = x.id and al.active and g.kind = 'ours')
               or exists (select 1 from public.game_capture_raw r where r.world_id = x.id)),
    'a run didn''t write one job_runs row per world';
  select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
  assert j.status = 'ok' and (j.details ->> 'raw_deleted')::bigint = n_raw_old and not (j.details ->> 'statement_enabled')::boolean
     and (j.details ->> 'statement_deleted')::int = 0, format('the clean-up, switched off: %s, %s', j.status, j.note);
  assert not exists (select 1 from public.game_capture_raw where world_id = w and captured_at < v_cut), 'a raw page older than 14 days is left';
  assert exists (select 1 from public.game_capture_raw where id = v_young), 'a raw page 13 days old was deleted';
  assert not exists (select 1 from public.game_capture_raw where id = v_old_page), 'the raw page 15 days old is still there';
  assert (select count(*) from public.game_statement where world_id = w) = n_lines, 'statement lines went while the clean-up is switched off';

  -- switched on: every line older than 14 days goes, being in game_flights or game_payments; the rest stay
  update public.settings set value = 'true' where world_id = w and airline_id is null and key = 'statement_cleanup_enabled';
  perform private.job_cleanup(v_at);
  select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
  if (j.details ->> 'statement_old')::bigint = (j.details ->> 'statement_in_flights')::bigint + (j.details ->> 'statement_in_payments')::bigint then
    assert j.status = 'ok' and (j.details ->> 'statement_deleted')::bigint = n_old, format('the clean-up, switched on: %s, %s', j.status, j.note);
    assert not exists (select 1 from public.game_statement where world_id = w and ts < v_cut), 'a statement line older than 14 days is left';
    assert (select count(*) from public.game_statement where world_id = w) = n_lines - n_old, 'statement lines younger than 14 days went';
    assert exists (select 1 from public.game_flights where id = v_flight) and exists (select 1 from public.game_payments where descr = 'jobs-test payment'),
      'the clean-up touched game_flights or game_payments';
  else
    raise exception 'the copy has statement lines older than 14 days in neither game_flights nor game_payments (%): the statement clean-up would refuse to run on it', j.note;
  end if;

  -- a line older than 14 days in neither: none goes, the run fails and says so
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id)
  values (w, a.id, a.planner_name, v_old_ts, 'jobs-test unfolded', 5, 'D', 1, 0, null);
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, dep_at,
                                   pax_income, income_total, cost_total, money_captured_at)
  values (w, a.id, v_old_ts, 8, 1, 'ZZA', 'ZZB', v_old_ts, 100, 100, 40, v_at - interval '16 days') returning id into v_flight;
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id)
  values (w, a.id, a.planner_name, v_old_ts, 'Passenger transport income (ZZA-ZZB) jobs-test 2', 100, 'C', 1, 8, v_flight);
  perform private.job_cleanup(v_at);
  select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
  assert j.status = 'failed' and j.note like '%1 of the 2 older than 14 days aren''t in game_flights or game_payments, so none were deleted%'
     and (select count(*) from public.game_statement where world_id = w and ts < v_cut) = 2,
    format('a line in neither: %s, %s', j.status, j.note);
  raise notice 'clean-ups: % raw page(s) older than 14 days deleted, one 13 days old kept; switched off (as it ships) no statement line goes; switched on the % older than 14 days go (in game_flights or game_payments) and younger ones stay; one older line in neither and none goes, the run failed and says so; one job_runs row per world a run',
    n_raw_old, n_old;
end
$test$;

do $$ begin raise notice 'jobs: all checks passed'; end $$;

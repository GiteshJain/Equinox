-- The nightly rehearsal's result in job_runs (spec docs/specs/2026-11-15-rehearsal-on-today.md; migration
-- 20261115120000). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a
-- transaction that is rolled back, so the read it makes of GitHub is never sent. A failed check stops with an error that
-- says which (names, counts and words, never keys).
--   1. The catalogue: job_runs takes rehearsal and rehearsal_read, and still refuses a job it doesn't know; the two new
--      functions are postgres's only (not anon, authenticated, service_role or public), run as the caller with an empty
--      search path, and described; private.schedule_jobs() lists equinox-rehearsal-read every hour at :50.
--   2. private.rehearsal_record() on a hand-made answer in GitHub's shape: a passed nightly run becomes an ok row, a
--      failed one a failed row, each with its run's address and words; a run started by hand on main is recorded; a pull
--      request's run, a fork's, another branch's, another workflow's, a cancelled run and one still running write
--      nothing; text from the answer (the commit message) never reaches the note. The same answer again changes nothing;
--      a re-run that passed turns the failed row ok; an answer with no list of runs is refused.
--   3. private.rehearsal_read(): answers made by hand in pg_net's table are noted on their read rows (a 200 recorded
--      through private.rehearsal_record(), a 403 failed, one gone after 6 hours failed), a new read row is written with
--      its request id, and read rows older than 14 days go while the nightly runs' rows stay.
--   4. system_status()'s rehearsal part: the last run with its note and address, the last that passed, and the last read
--      of GitHub. (Today and Systems with a failed night, a good one and none for 36 hours: the planner's unit tests.)

-- One run in GitHub's shape (the fields private.rehearsal_record() reads, and a commit message it must never keep), a
-- day ahead of anything the copy has; the ids are far above any real run's.
create function pg_temp.reh_run(p_id bigint, p_event text, p_branch text, p_status text, p_conclusion text, p_day int,
                                p_minutes int, p_repo text default 'GiteshJain/Equinox',
                                p_path text default '.github/workflows/database-rehearsal.yml', p_attempt int default 1)
returns jsonb language sql as $$
  select jsonb_build_object(
    'id', p_id, 'name', 'Database rehearsal', 'path', p_path, 'event', p_event, 'head_branch', p_branch,
    'status', p_status, 'conclusion', p_conclusion, 'run_attempt', p_attempt,
    'head_sha', '0123456789abcdef0123456789abcdef01234567',
    'display_title', 'a commit message that must not reach the note',
    'run_started_at', to_char((date_trunc('day', now() at time zone 'UTC') + interval '2 days' + p_day * interval '1 day' + interval '15 hours'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'created_at', to_char((date_trunc('day', now() at time zone 'UTC') + interval '2 days' + p_day * interval '1 day' + interval '15 hours'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'updated_at', to_char((date_trunc('day', now() at time zone 'UTC') + interval '2 days' + p_day * interval '1 day' + interval '15 hours' + p_minutes * interval '1 minute'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'html_url', 'https://github.com/' || p_repo || '/actions/runs/' || p_id,
    'repository', jsonb_build_object('full_name', 'GiteshJain/Equinox'),
    'head_repository', jsonb_build_object('full_name', p_repo))
$$;

create function pg_temp.reh_answer(p_rerun boolean default false)
returns jsonb language sql as $$
  select jsonb_build_object('total_count', 9, 'workflow_runs', jsonb_build_array(
    pg_temp.reh_run(990000000001, 'schedule', 'main', 'completed', 'success', 0, 13),
    case when p_rerun then pg_temp.reh_run(990000000002, 'schedule', 'main', 'completed', 'success', 1, 21, p_attempt => 2)
         else pg_temp.reh_run(990000000002, 'schedule', 'main', 'completed', 'failure', 1, 21) end,
    pg_temp.reh_run(990000000003, 'workflow_dispatch', 'main', 'completed', 'success', 2, 12),
    pg_temp.reh_run(990000000004, 'pull_request', 'rehearsal-on-today', 'completed', 'failure', 3, 9),
    pg_temp.reh_run(990000000005, 'pull_request', 'main', 'completed', 'failure', 4, 9, 'someone/Equinox'),
    pg_temp.reh_run(990000000006, 'workflow_dispatch', 'other-branch', 'completed', 'failure', 5, 9),
    pg_temp.reh_run(990000000007, 'schedule', 'main', 'completed', 'cancelled', 6, 2),
    pg_temp.reh_run(990000000008, 'schedule', 'main', 'in_progress', null, 7, 0),
    pg_temp.reh_run(990000000009, 'schedule', 'main', 'completed', 'failure', 8, 5, p_path => '.github/workflows/checks.yml')))
$$;

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare f regprocedure; r jsonb;
  fns regprocedure[] := array['private.rehearsal_record(jsonb)', 'private.rehearsal_read(timestamptz)']::regprocedure[];
begin
  perform private.job_run_add('rehearsal', null, now() - interval '400 days', 'ok', 'catalogue check', null);
  perform private.job_run_add('rehearsal_read', null, now() - interval '400 days', 'ok', 'catalogue check', null);
  begin
    perform private.job_run_add('rehearsal_nothing', null, now() - interval '400 days', 'ok', 'catalogue check', null);
    raise exception 'job_runs took a job it doesn''t know';
  exception when check_violation then null;
  end;
  delete from public.job_runs j where j.note = 'catalogue check' and j.job in ('rehearsal', 'rehearsal_read');
  foreach f in array fns loop
    assert not exists (select 1 from pg_proc p where p.oid = f
                         and (p.prosecdef or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                              or has_function_privilege('service_role', p.oid, 'execute') or not coalesce('search_path=""' = any (p.proconfig), false)
                              or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0)
                              or length(coalesce(obj_description(p.oid, 'pg_proc'), '')) < 60)),
      f::text || ' is open to others, runs as owner, has no empty search path or no description';
  end loop;
  assert position('rehearsal_read' in coalesce(col_description('public.job_runs'::regclass,
           (select attnum from pg_attribute where attrelid = 'public.job_runs'::regclass and attname = 'job')), '')) > 0,
    'job_runs.job''s description doesn''t name the rehearsal''s jobs';
  r := private.schedule_jobs();
  assert r @> '[{"job": "equinox-rehearsal-read", "schedule": "50 * * * *", "command": "select private.rehearsal_read()"}]'::jsonb,
    'private.schedule_jobs() doesn''t list the rehearsal''s read every hour at :50: ' || r::text;
  raise notice 'job_runs takes rehearsal and rehearsal_read, two new functions postgres''s only, schedule_jobs() lists the read every hour at :50';
end
$test$;

-- ---------------------------------------------------------------- 2. the record
do $test$
declare r jsonb; j record; n0 bigint;
begin
  select count(*) into n0 from public.job_runs where job = 'rehearsal';
  r := private.rehearsal_record(pg_temp.reh_answer());
  assert r = '{"seen": 4, "added": 3, "changed": 0}'::jsonb,
    'the record didn''t see the four nightly runs on main (one cancelled) and add three: ' || r::text;
  assert (select count(*) from public.job_runs where job = 'rehearsal') = n0 + 3, 'the record wrote other than three rows';
  select * into j from public.job_runs x where x.job = 'rehearsal' and x.details ->> 'run_id' = '990000000001';
  assert j.status = 'ok' and j.note = 'passed: every part on the latest backup, in 13 min' and j.world_id is null
     and j.details ->> 'url' = 'https://github.com/GiteshJain/Equinox/actions/runs/990000000001'
     and j.details ->> 'conclusion' = 'success' and j.details ->> 'event' = 'schedule'
     and j.finished_at - j.started_at = interval '13 minutes' and j.for_day = (j.started_at at time zone 'UTC')::date,
    'a passed night isn''t an ok row with its words, address and times: ' || coalesce(j.note, 'no row');
  select * into j from public.job_runs x where x.job = 'rehearsal' and x.details ->> 'run_id' = '990000000002';
  assert j.status = 'failed' and j.note = 'failed (failure) after 21 min: the log is on GitHub''s Actions page, run 990000000002',
    'a failed night isn''t a failed row with its words: ' || coalesce(j.note, 'no row');
  select * into j from public.job_runs x where x.job = 'rehearsal' and x.details ->> 'run_id' = '990000000003';
  assert j.status = 'ok' and j.note like '% (started by hand)', 'a run started by hand on main isn''t recorded as one: ' || coalesce(j.note, 'no row');
  assert not exists (select 1 from public.job_runs x where x.job = 'rehearsal'
                        and x.details ->> 'run_id' in ('990000000004', '990000000005', '990000000006', '990000000007', '990000000008', '990000000009')),
    'a pull request''s run, a fork''s, another branch''s, a cancelled one, one still running or another workflow''s was recorded';
  assert not exists (select 1 from public.job_runs x where x.job = 'rehearsal' and (x.note like '%commit message%' or x.details::text like '%commit message%')),
    'text from GitHub''s answer reached a row';
  -- the same answer again changes nothing; a re-run that passed turns the failed row ok
  r := private.rehearsal_record(pg_temp.reh_answer());
  assert r = '{"seen": 4, "added": 0, "changed": 0}'::jsonb, 'the same answer again changed something: ' || r::text;
  r := private.rehearsal_record(pg_temp.reh_answer(true));
  assert r = '{"seen": 4, "added": 0, "changed": 1}'::jsonb, 'a re-run didn''t change its row: ' || r::text;
  select * into j from public.job_runs x where x.job = 'rehearsal' and x.details ->> 'run_id' = '990000000002';
  assert j.status = 'ok' and j.note = 'passed: every part on the latest backup, in 21 min (attempt 2)' and j.details -> 'attempt' = '2'::jsonb,
    'the re-run that passed didn''t turn the row ok: ' || coalesce(j.note, 'no row');
  -- no list of runs
  begin
    perform private.rehearsal_record('{"message": "Not Found"}'::jsonb);
    raise exception 'the record took an answer with no list of runs';
  exception when raise_exception then
    if sqlerrm = 'the record took an answer with no list of runs' then raise; end if;
  end;
  delete from public.job_runs x where x.job = 'rehearsal' and x.details ->> 'run_id' like '9900000000%';
  raise notice 'rehearsal_record(): a passed night ok, a failed night failed, one by hand on main recorded; a pull request''s, a fork''s, another branch''s, another workflow''s, a cancelled and a running run not; the same answer changes nothing, a re-run turns its row ok, no list refused';
end
$test$;

-- ---------------------------------------------------------------- 3. the read
do $test$
declare r jsonb; net_ok boolean := true; id200 bigint; id403 bigint; idgone bigint; idold bigint; j record;
begin
  begin
    insert into net._http_response (id, status_code, content, timed_out, error_msg, created)
    values (-424301, 200, pg_temp.reh_answer()::text, false, null, now()),
           (-424303, 403, '{"message": "API rate limit exceeded"}', false, null, now());
  exception when others then
    net_ok := false;
    raise notice 'pg_net''s answers can''t be written here (%), so noting the answer is tested only with none', sqlerrm;
  end;
  id200 := private.job_run_add('rehearsal_read', null, now() - interval '61 minutes', 'ok', 'asked GitHub (test)', jsonb_build_object('request_id', -424301));
  id403 := private.job_run_add('rehearsal_read', null, now() - interval '60 minutes', 'ok', 'asked GitHub (test)', jsonb_build_object('request_id', -424303));
  idgone := private.job_run_add('rehearsal_read', null, now() - interval '7 hours', 'ok', 'asked GitHub (test)', jsonb_build_object('request_id', -424309));
  idold := private.job_run_add('rehearsal_read', null, now() - interval '15 days', 'ok', 'asked GitHub (test)', jsonb_build_object('request_id', -424310));
  r := private.rehearsal_read();
  if net_ok then
    select * into j from public.job_runs where id = id200;
    assert j.status = 'ok' and j.note = 'read GitHub: 4 nightly run(s) listed, 3 new, 0 changed' and j.details -> 'answer' = '200'::jsonb,
      'a 200 isn''t noted as read with what it recorded: ' || coalesce(j.note, 'no row');
    assert (select count(*) from public.job_runs x where x.job = 'rehearsal' and x.details ->> 'run_id' like '9900000000%') = 3,
      'the 200''s runs weren''t recorded';
    select * into j from public.job_runs where id = id403;
    assert j.status = 'failed' and j.note = 'GitHub answered 403', 'a 403 isn''t noted as failed: ' || coalesce(j.note, 'no row');
  else
    assert (select status = 'ok' and not details ? 'answer' from public.job_runs where id = id200), 'an answer not yet come was noted';
  end if;
  select * into j from public.job_runs where id = idgone;
  assert j.status = 'failed' and j.note = 'GitHub''s answer was no longer kept (pg_net keeps 6 hours)',
    'an answer gone after 6 hours isn''t noted as failed: ' || coalesce(j.note, 'no row');
  assert not exists (select 1 from public.job_runs where id = idold), 'a read row older than 14 days was kept';
  select * into j from public.job_runs x where x.job = 'rehearsal_read' order by x.id desc limit 1;
  assert (j.status = 'ok' and (j.details ->> 'request_id')::bigint = (r ->> 'request_id')::bigint and j.note like 'asked GitHub for the nightly rehearsal''s runs (request %')
      or (j.status = 'failed' and j.note like 'the read failed: %'),
    'the read didn''t write its own row: ' || coalesce(j.note, 'no row');
  delete from public.job_runs x where x.job = 'rehearsal' and x.details ->> 'run_id' like '9900000000%';
  raise notice 'rehearsal_read(): % ; an answer gone after 6 hours failed, read rows over 14 days gone, its own row written (%)',
    case when net_ok then 'a 200 recorded (3 runs), a 403 failed' else 'no answers could be made' end, j.status;
end
$test$;

-- ---------------------------------------------------------------- 4. system_status()'s rehearsal part
do $test$
declare d jsonb; w bigint := (select id from public.worlds where is_default); t0 timestamptz := now() + interval '30 days';
begin
  perform private.job_run_add('rehearsal', null, t0 + interval '1 hour', 'ok', 'passed: every part on the latest backup, in 13 min',
                              '{"run_id": 990000000101, "url": "https://github.com/GiteshJain/Equinox/actions/runs/990000000101"}'::jsonb);
  perform private.job_run_add('rehearsal_read', null, t0 + interval '2 hours', 'ok', 'read GitHub: 1 nightly run(s) listed, 1 new, 0 changed',
                              '{"request_id": -424401, "answer": 200}'::jsonb);
  d := public.system_status(w, t0 + interval '3 hours') -> 'rehearsal';
  assert d #>> '{last,status}' = 'ok' and d #>> '{last_ok,at}' = private.fig_ts(t0 + interval '1 hour')
     and d #>> '{last,url}' = 'https://github.com/GiteshJain/Equinox/actions/runs/990000000101'
     and d #>> '{read,status}' = 'ok' and d #>> '{read,at}' = private.fig_ts(t0 + interval '2 hours'),
    'a passed night and a read aren''t the last run, the last good run and the read: ' || coalesce(d::text, 'none');
  perform private.job_run_add('rehearsal', null, t0 + interval '25 hours', 'failed', 'failed (failure) after 21 min: the log is on GitHub''s Actions page, run 990000000102',
                              '{"run_id": 990000000102}'::jsonb);
  d := public.system_status(w, t0 + interval '26 hours') -> 'rehearsal';
  assert d #>> '{last,status}' = 'failed' and d #>> '{last,note}' like 'failed (failure) after 21 min%' and d #>> '{last_ok,at}' = private.fig_ts(t0 + interval '1 hour'),
    'a failed night isn''t the last run, with the last good one before it: ' || d::text;
  raise notice 'system_status()''s rehearsal part: a passed night as the last run and the last good run, the read, then a failed night as the last run';
end
$test$;

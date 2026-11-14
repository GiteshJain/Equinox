-- The nightly database rehearsal's result in job_runs, so a failed night shows on Today and the Systems board (15 Nov
-- 2026; to-do 239, settling to-do 234's steps 1 and 11; brief docs/briefs/2026-11-15-nightly-rehearsal-failure.md, option
-- B; spec docs/specs/2026-11-15-rehearsal-on-today.md).
--
-- Why: the whole rehearsal runs every night on main (GitHub's timer, 08:43 UTC, often hours late), and a failed night
-- reached only GitHub's failure email. Manual §7: every job writes a row to job_runs, and Today warns when any job's last
-- run failed. The rehearsal wrote none.
--
-- How: the database reads the result itself, every hour, from GitHub's public API (the Equinox repository is public, so
-- no key is needed and none is sent). Only GitHub can write what it reads, so nobody can post a result, and the workflow
-- is unchanged. Gitesh adds nothing.
--
-- Adds two functions and one scheduled job; widens one rule; replaces two functions with the same arguments (create or
-- replace keeps their grants). Drops, renames and deletes nothing, so it can be applied from the chat:
--   1. job_runs.job also takes rehearsal (one row per nightly run on main, written when the database sees it finished) and
--      rehearsal_read (one row per hourly read of GitHub, with pg_net's request id, its answer noted on it the hour after).
--   2. private.rehearsal_record(answer): from GitHub's list of the workflow's runs, every finished run of
--      .github/workflows/database-rehearsal.yml in GiteshJain/Equinox on main, started by the timer (schedule) or by hand
--      (workflow_dispatch), becomes one job_runs row (rehearsal): ok when it passed, failed when it failed, timed out or
--      couldn't start; a cancelled or skipped run writes nothing (the run that replaced it reports). A pull request's run
--      is never recorded. A run already recorded is changed only when GitHub re-ran it or its result changed. Only
--      numbers, times, GitHub's fixed result words and the run's address are kept: never a commit message or any other
--      text from the answer.
--      private.rehearsal_read(at): the job (pg_cron equinox-rehearsal-read, every hour at :50). Notes the answers to
--      earlier reads (net._http_response, kept 6 hours; a 200 goes to private.rehearsal_record()), then asks GitHub again
--      (GET .../actions/workflows/database-rehearsal.yml/runs?branch=main&per_page=10, no key) and writes its
--      rehearsal_read row; read rows older than 14 days go.
--   3. private.schedule_jobs() also schedules equinox-rehearsal-read, and is run here.
--   4. system_status() also gives rehearsal: the last nightly run (when, ok or failed, its note and address), the last
--      that passed, and the last read of GitHub (when, ok or failed, its note).
-- The rehearsal's own copy never reads: its scheduled jobs are paused for the tests (database/rehearse.sh), and its
-- tests run inside a transaction that is rolled back, so a read they make is never sent.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261115120000_rehearsal_on_today', true);

-- ============================================================ 1. job_runs takes the rehearsal's two jobs
alter table public.job_runs
  drop constraint job_runs_job_check,
  add constraint job_runs_job_check check (job in ('backup', 'snapshot', 'snapshot_fallback', 'cleanup', 'archive', 'adapter_mirror',
                                                   'adapter_check', 'capture_unattended', 'capture_dispatch', 'figures',
                                                   'rehearsal', 'rehearsal_read'));
comment on column public.job_runs.job is 'backup, snapshot, snapshot_fallback, cleanup or archive; since 10 Nov capture_dispatch (the database asking GitHub to start the unattended capture, 09:30 and 21:30 UTC) and capture_unattended (the unattended capture''s run, written by the GitHub job in equinox-backups); since 11 Nov figures (a set of the planner''s figures stored, private.figures_refresh()); since 15 Nov rehearsal (a nightly database rehearsal on main, read from GitHub by private.rehearsal_read()) and rehearsal_read (each hourly read of GitHub); adapter_mirror and adapter_check are the old adapter''s runs, until the clean-up (build pull request 14)';

do $describe$
declare d text := obj_description('public.job_runs'::regclass, 'pg_class');
begin
  if position('rehearsal_read' in coalesce(d, '')) = 0 then
    execute format('comment on table public.job_runs is %L', coalesce(d, '')
      || ' Since 15 Nov also the nightly database rehearsal (spec docs/specs/2026-11-15-rehearsal-on-today.md): rehearsal, one row per nightly run on main (its details: run_id, attempt, event, conclusion, url, head_sha), and rehearsal_read, each hourly read of GitHub''s public API that finds them.');
  end if;
end
$describe$;

-- ============================================================ 2. the record and the read
create or replace function private.rehearsal_record(p_answer jsonb)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  c_path constant text := '.github/workflows/database-rehearsal.yml';
  c_repo constant text := 'giteshjain/equinox';
  c_runs constant text := 'https://github.com/GiteshJain/Equinox/actions/runs/';
  r jsonb; v_id bigint; v_attempt int; v_conclusion text; v_status text; v_started timestamptz; v_finished timestamptz;
  v_min int; v_note text; v_details jsonb; v_row record; v_added int := 0; v_changed int := 0; v_seen int := 0;
begin
  if jsonb_typeof(p_answer -> 'workflow_runs') is distinct from 'array' then
    raise exception 'GitHub''s answer has no list of runs';
  end if;
  for r in select x from jsonb_array_elements(p_answer -> 'workflow_runs') x loop
    -- only the nightly run on main, in this repository: a pull request's run (or a fork's) is never recorded
    continue when coalesce(r ->> 'path', '') <> c_path
               or lower(coalesce(r #>> '{repository,full_name}', '')) <> c_repo
               or lower(coalesce(r #>> '{head_repository,full_name}', '')) <> c_repo
               or coalesce(r ->> 'head_branch', '') <> 'main'
               or coalesce(r ->> 'event', '') not in ('schedule', 'workflow_dispatch')
               or coalesce(r ->> 'status', '') <> 'completed'
               or coalesce(r ->> 'id', '') !~ '^[0-9]{1,20}$';
    v_seen := v_seen + 1;
    v_conclusion := r ->> 'conclusion';
    v_status := case when v_conclusion = 'success' then 'ok'
                     when v_conclusion in ('failure', 'timed_out', 'startup_failure', 'action_required') then 'failed' end;
    -- cancelled (a newer run replaced it), skipped, neutral or stale: nothing to record
    continue when v_status is null;
    v_id := (r ->> 'id')::bigint;
    v_attempt := case when coalesce(r ->> 'run_attempt', '') ~ '^[0-9]{1,6}$' then (r ->> 'run_attempt')::int else 1 end;
    v_started := coalesce((r ->> 'run_started_at')::timestamptz, (r ->> 'created_at')::timestamptz);
    v_finished := (r ->> 'updated_at')::timestamptz;
    v_min := greatest(0, round(extract(epoch from (v_finished - v_started)) / 60))::int;
    v_note := case when v_status = 'ok' then 'passed: every part on the latest backup, in ' || v_min || ' min'
                   else 'failed (' || replace(v_conclusion, '_', ' ') || ') after ' || v_min || ' min: the log is on GitHub''s Actions page, run ' || v_id end
              || case when r ->> 'event' = 'workflow_dispatch' then ' (started by hand)' else '' end
              || case when v_attempt > 1 then ' (attempt ' || v_attempt || ')' else '' end;
    v_details := jsonb_build_object('run_id', v_id, 'attempt', v_attempt, 'event', r ->> 'event', 'conclusion', v_conclusion,
                                    'url', c_runs || v_id,
                                    'head_sha', case when coalesce(r ->> 'head_sha', '') ~ '^[0-9a-f]{40}$' then r ->> 'head_sha' end);
    select j.id, j.status, j.details into v_row from public.job_runs j
     where j.job = 'rehearsal' and j.details ->> 'run_id' = v_id::text
     order by j.id desc limit 1;
    if not found then
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('rehearsal', null, v_started, v_finished, v_status, (v_started at time zone 'UTC')::date, v_note, v_details);
      v_added := v_added + 1;
    elsif v_attempt > coalesce((v_row.details ->> 'attempt')::int, 1) or v_conclusion is distinct from v_row.details ->> 'conclusion' then
      update public.job_runs j
         set started_at = v_started, finished_at = v_finished, status = v_status, note = v_note, details = v_details
       where j.id = v_row.id;
      v_changed := v_changed + 1;
    end if;
  end loop;
  return jsonb_build_object('seen', v_seen, 'added', v_added, 'changed', v_changed);
end
$function$;

create or replace function private.rehearsal_read(p_at timestamptz default null)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  c_url constant text := 'https://api.github.com/repos/GiteshJain/Equinox/actions/workflows/database-rehearsal.yml/runs';
  v_at timestamptz := coalesce(p_at, now());
  r record; v_resp record; v_res jsonb; v_words text; v_ok boolean; v_req bigint; v_noted int := 0; v_waiting int := 0;
  v_status text := 'ok'; v_note text; v_new int := 0;
begin
  -- 1. the answers to earlier reads (pg_net keeps an answer 6 hours)
  for r in select j.id, (j.details ->> 'request_id')::bigint as request_id, j.started_at
             from public.job_runs j
            where j.job = 'rehearsal_read' and j.details ? 'request_id' and not j.details ? 'answer'
              and j.started_at > v_at - interval '2 days'
            order by j.started_at, j.id
  loop
    select x.status_code, x.content, x.timed_out, x.error_msg into v_resp from net._http_response x where x.id = r.request_id;
    if not found then
      if r.started_at < v_at - interval '6 hours' then
        update public.job_runs j
           set status = 'failed', note = 'GitHub''s answer was no longer kept (pg_net keeps 6 hours)',
               details = j.details || jsonb_build_object('answer', null)
         where j.id = r.id;
        v_noted := v_noted + 1;
      else
        v_waiting := v_waiting + 1;
      end if;
      continue;
    end if;
    v_ok := false;
    if v_resp.status_code = 200 then
      begin
        v_res := private.rehearsal_record(v_resp.content::jsonb);
        v_ok := true;
        v_new := v_new + (v_res ->> 'added')::int + (v_res ->> 'changed')::int;
        v_words := 'read GitHub: ' || (v_res ->> 'seen') || ' nightly run(s) listed, ' || (v_res ->> 'added') || ' new, '
                   || (v_res ->> 'changed') || ' changed';
      exception when others then
        v_words := 'GitHub''s answer didn''t read: ' || left(sqlerrm, 200);
      end;
    else
      v_words := case when v_resp.status_code is not null then 'GitHub answered ' || v_resp.status_code
                      when coalesce(v_resp.timed_out, false) then 'GitHub didn''t answer in time'
                      else 'GitHub couldn''t be reached: ' || left(coalesce(v_resp.error_msg, 'no answer'), 200) end;
    end if;
    update public.job_runs j
       set status = case when v_ok then 'ok' else 'failed' end, note = v_words,
           details = j.details || jsonb_build_object('answer', v_resp.status_code) || coalesce(v_res, '{}'::jsonb)
     where j.id = r.id;
    v_res := null;
    v_noted := v_noted + 1;
  end loop;

  -- 2. ask again: the workflow's latest runs on main, from GitHub's public API, with no key
  begin
    v_req := net.http_get(
      url := c_url,
      params := jsonb_build_object('branch', 'main', 'per_page', '10', 'exclude_pull_requests', 'true'),
      headers := jsonb_build_object('Accept', 'application/vnd.github+json', 'X-GitHub-Api-Version', '2022-11-28',
                                    'User-Agent', 'equinox-rehearsal-read'),
      timeout_milliseconds := 10000);
    v_note := 'asked GitHub for the nightly rehearsal''s runs (request ' || v_req || '); its answer is noted at the next read';
  exception when others then
    v_status := 'failed'; v_note := 'the read failed: ' || left(sqlerrm, 200); v_req := null;
  end;
  perform private.job_run_add('rehearsal_read', null, v_at, v_status, v_note,
                              case when v_req is not null then jsonb_build_object('request_id', v_req) else '{}'::jsonb end);

  -- 3. the read rows older than 14 days go (the nightly runs' rows stay)
  delete from public.job_runs j where j.job = 'rehearsal_read' and j.started_at < v_at - interval '14 days';

  return jsonb_build_object('status', v_status, 'request_id', v_req, 'noted', v_noted, 'waiting', v_waiting, 'recorded', v_new);
end
$function$;

-- ============================================================ 3. the schedule
create or replace function private.schedule_jobs()
returns jsonb
language plpgsql
set search_path to ''
as $function$
begin
  perform cron.schedule('equinox-snapshot-fallback', '0 10 * * *', 'select private.job_snapshot_fallback()');
  perform cron.schedule('equinox-cleanup', '20 10 * * *', 'select private.job_cleanup()');
  -- the unattended capture (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §1): the start at 09:30 and
  -- 21:30 UTC, and GitHub's answer noted ten minutes later
  perform cron.schedule('equinox-capture-dispatch', '30 9,21 * * *', 'select private.capture_dispatch()');
  perform cron.schedule('equinox-capture-dispatch-answer', '40 9,21 * * *', 'select private.capture_dispatch_answer()');
  -- the planner's figures stored after every capture (since 11 Nov, spec docs/specs/2026-11-11-stored-figures.md §1):
  -- every minute; most minutes it finds nothing to do
  perform cron.schedule('equinox-figures', '* * * * *', 'select private.figures_refresh()');
  -- the nightly rehearsal's result read from GitHub (since 15 Nov, spec docs/specs/2026-11-15-rehearsal-on-today.md):
  -- every hour at :50
  perform cron.schedule('equinox-rehearsal-read', '50 * * * *', 'select private.rehearsal_read()');
  return (select jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'command', j.command, 'active', j.active)
                           order by j.jobname)
            from cron.job j where j.jobname like 'equinox-%');
end
$function$;

-- ============================================================ 4. the Systems board
CREATE OR REPLACE FUNCTION public.system_status(p_world_id bigint DEFAULT NULL::bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w bigint; v_at timestamptz := coalesce(p_as_of, now()); v_month timestamptz; v_snap jsonb; v_job jsonb; v_fb timestamptz;
  v_backup jsonb; v_good jsonb; v_arch jsonb; v_clean jsonb; v_scan jsonb; v_stopped jsonb; v_market jsonb; v_un jsonb; v_db bigint; v_pdf bigint; v_site bigint;
  v_figs bigint; v_reh jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the systems board' using errcode = '42501'; end if;
  w := private.fig_world(p_world_id);
  v_month := date_trunc('month', v_at at time zone 'UTC') at time zone 'UTC';

  -- the daily snapshot: the latest capture day in the daily history, and how it was taken
  select jsonb_build_object('day', x.day, 'source', x.source, 'complete', x.complete, 'taken_at', private.fig_ts(x.taken_at), 'airlines', x.airlines)
    into v_snap
    from (select ad.day, string_agg(distinct ad.source, ', ') as source, bool_and(ad.complete) as complete, max(ad.taken_at) as taken_at,
                 count(*)::int as airlines
            from public.airline_days ad
           where ad.world_id = w and ad.taken_at <= v_at
           group by ad.day order by ad.day desc limit 1) x;
  select jsonb_build_object('job', j.job, 'status', j.status, 'at', private.fig_ts(j.started_at), 'note', left(j.note, 300))
    into v_job
    from public.job_runs j
   where j.job in ('snapshot', 'snapshot_fallback') and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;
  select max(j.started_at) into v_fb from public.job_runs j
   where j.job = 'snapshot_fallback' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at;

  -- the nightly backup: its latest run, and the latest good copy (a good run passed its restore check)
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'ok', b.ok, 'kind', b.kind, 'note', left(b.note, 300))
    into v_backup
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;
  select jsonb_build_object('ran_at', private.fig_ts(b.ran_at), 'bytes', b.bytes, 'tables', b.tables, 'rows', b.rows, 'files', b.files,
                            'object_key', b.object_key)
    into v_good
    from public.backup_runs b where coalesce(b.kind, '') <> 'test' and b.ok and b.ran_at <= v_at order by b.ran_at desc, b.id desc limit 1;

  -- the monthly archive: its runs this month, its latest run, and any table and month whose latest run failed
  select jsonb_build_object(
           'last_at', private.fig_ts(max(j.started_at)),
           'month', (v_at at time zone 'UTC')::date - (extract(day from v_at at time zone 'UTC')::int - 1),
           'runs_this_month', count(*) filter (where j.started_at >= v_month),
           'ok_this_month', count(*) filter (where j.started_at >= v_month and j.status = 'ok'),
           'rows_this_month', coalesce(sum((j.details ->> 'rows')::bigint) filter (where j.started_at >= v_month and j.status = 'ok'), 0),
           'failed', coalesce((select jsonb_agg(jsonb_build_object('table', f.details ->> 'table', 'month', f.for_month, 'at', private.fig_ts(f.started_at),
                                                                   'note', left(f.note, 200)) order by f.started_at)
                                 from (select distinct on (x.details ->> 'table', x.for_month) x.*
                                         from public.job_runs x
                                        where x.job = 'archive' and x.started_at <= v_at and x.status <> 'running'
                                        order by x.details ->> 'table', x.for_month, x.started_at desc, x.id desc) f
                                where f.status = 'failed'), '[]'::jsonb))
    into v_arch
    from public.job_runs j where j.job = 'archive' and j.started_at <= v_at and j.status <> 'running';

  -- the clean-ups: the latest run
  select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
    into v_clean
    from public.job_runs j
   where j.job = 'cleanup' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
   order by j.started_at desc, j.id desc limit 1;

  -- the world scan: the latest that has its airport summary (as hub_progress() reads it)
  -- since 23 Oct (spec docs/specs/2026-10-23-rival-fleets.md §5) with the overview pages it read and failed
  select jsonb_build_object('taken_at', private.fig_ts(s.taken_at), 'week', s.week, 'status', s.status,
                            'fleet_pages', (select count(*) from public.scan_airline_profile p where p.scan_id = s.id and p.read_ok)::int,
                            'fleet_failed', (select count(*) from public.scan_airline_profile p where p.scan_id = s.id and not p.read_ok)::int)
    into v_scan
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at and exists (select 1 from public.scan_airline_airports x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  -- a scan that stopped part-way since the latest finished one (spec docs/specs/2026-10-21-tidy-ups.md §1): marked stopped
  -- when the next scan started, or left unfinished for over an hour (nothing carries it on: private.scan_open())
  select jsonb_build_object('id', s.id, 'taken_at', private.fig_ts(s.taken_at), 'status', s.status, 'note', left(s.note, 300))
         || private.scan_progress(s.id)
    into v_stopped
    from public.game_scans s
   where s.world_id = w and s.taken_at <= v_at
     and (s.status = 'stopped' or (s.status not in ('done', 'stopped') and s.taken_at <= v_at - interval '1 hour'))
     and s.taken_at > coalesce((select max(d.taken_at) from public.game_scans d where d.world_id = w and d.status = 'done' and d.taken_at <= v_at),
                               '-infinity'::timestamptz)
   order by s.taken_at desc, s.id desc limit 1;

  -- the market pages (spec docs/specs/2026-10-30-market-pages.md): the latest finished run, its age, pages and failed
  select jsonb_build_object('id', r.id, 'started_at', private.fig_ts(r.started_at), 'finished_at', private.fig_ts(r.finished_at),
                            'age_days', round((extract(epoch from v_at - r.finished_at) / 86400)::numeric, 1),
                            'pages_read', r.pages_read, 'pages_failed', r.pages_failed, 'note', left(r.note, 300))
    into v_market
    from public.market_runs r
   where r.world_id = w and r.status = 'done' and r.started_at <= v_at
   order by r.started_at desc, r.id desc limit 1;

  -- the unattended capture (since 10 Nov, spec docs/specs/2026-11-10-unattended-capture.md §3): Today's setting, its last
  -- run and last good run (job_runs, capture_unattended, written by the GitHub job) and the database's last start of it
  select jsonb_build_object(
           'warn_h', (select s.value from public.settings s where s.world_id = w and s.airline_id is null and s.key = 'capture_unattended_warn_h'),
           'last', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
                      from public.job_runs j
                     where j.job = 'capture_unattended' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
                     order by j.started_at desc, j.id desc limit 1),
           'last_ok', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
                         from public.job_runs j
                        where j.job = 'capture_unattended' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status = 'ok'
                        order by j.started_at desc, j.id desc limit 1),
           'dispatch', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
                          from public.job_runs j
                         where j.job = 'capture_dispatch' and (j.world_id = w or j.world_id is null) and j.started_at <= v_at and j.status <> 'running'
                         order by j.started_at desc, j.id desc limit 1))
    into v_un;

  -- the nightly database rehearsal on main (since 15 Nov, spec docs/specs/2026-11-15-rehearsal-on-today.md): its last run
  -- and last good run (job_runs, rehearsal, read from GitHub by private.rehearsal_read()) and the last read of GitHub
  select jsonb_build_object(
           'last', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300),
                                              'url', j.details ->> 'url')
                      from public.job_runs j
                     where j.job = 'rehearsal' and j.started_at <= v_at and j.status <> 'running'
                     order by j.started_at desc, j.id desc limit 1),
           'last_ok', (select jsonb_build_object('at', private.fig_ts(j.started_at))
                         from public.job_runs j
                        where j.job = 'rehearsal' and j.started_at <= v_at and j.status = 'ok'
                        order by j.started_at desc, j.id desc limit 1),
           'read', (select jsonb_build_object('at', private.fig_ts(j.started_at), 'status', j.status, 'note', left(j.note, 300))
                      from public.job_runs j
                     where j.job = 'rehearsal_read' and j.started_at <= v_at and j.details ? 'answer'
                     order by j.started_at desc, j.id desc limit 1))
    into v_reh;

  -- usage the database can measure, each against its trigger (manual §1; #16, #17, #20): now, whatever the moment
  v_db := pg_database_size(current_database());
  select coalesce(sum(octet_length(r.pdf_b64)), 0) * 3 / 4 into v_pdf from public.site_reports r where r.pdf_b64 is not null;
  v_site := octet_length(public.site_public()::text);
  -- the stored figures (since 11 Nov, spec docs/specs/2026-11-11-stored-figures.md §1): the table with its indexes and TOAST,
  -- amber from 50 MB (the board marks amber at 70% of the trigger)
  v_figs := pg_total_relation_size('public.planner_figures'::regclass);

  return jsonb_build_object(
    'world_id', w, 'as_of', private.fig_ts(v_at),
    'capture', private.fig_capture_status(w, v_at) -> 'airlines',
    'snapshot', coalesce(v_snap, '{}'::jsonb) || jsonb_build_object('last_run', v_job, 'fallback_at', private.fig_ts(v_fb)),
    'backup', jsonb_build_object('last', v_backup, 'last_good', v_good),
    'archive', v_arch,
    'cleanup', v_clean,
    'scan', v_scan,
    'scan_stopped', v_stopped,
    'market', v_market,
    'unattended', v_un,
    'rehearsal', v_reh,
    'usage', jsonb_build_array(
      jsonb_build_object('key', 'database', 'label', 'Database size', 'bytes', v_db, 'trigger_bytes', 350 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'report_pdfs', 'label', 'Report PDFs', 'bytes', v_pdf, 'trigger_bytes', 50 * 1024 * 1024::bigint),
      jsonb_build_object('key', 'site_public', 'label', 'The website''s data', 'bytes', v_site, 'trigger_bytes', 500 * 1024::bigint),
      jsonb_build_object('key', 'planner_figures', 'label', 'Stored planner figures', 'bytes', v_figs,
                         'trigger_bytes', 50 * 1024 * 1024 * 10 / 7::bigint)));
end
$function$;

do $describe$
declare d text := obj_description('public.system_status(bigint, timestamptz)'::regprocedure, 'pg_proc');
begin
  if position('rehearsal' in coalesce(d, '')) = 0 then
    execute format('comment on function public.system_status(bigint, timestamptz) is %L', coalesce(d, '')
      || ' Since 15 Nov (spec docs/specs/2026-11-15-rehearsal-on-today.md) also rehearsal: the nightly database rehearsal on main as read from GitHub (job_runs, rehearsal): last (at, status, note, url), last_ok (at), and read, the last hourly read of GitHub (job_runs, rehearsal_read: at, status, note).');
  end if;
end
$describe$;

-- ============================================================ access
-- The internal functions: postgres only (the job runs as postgres).
revoke all on function private.rehearsal_record(jsonb), private.rehearsal_read(timestamptz)
  from public, anon, authenticated, service_role;

-- ============================================================ descriptions
comment on function private.rehearsal_record(jsonb) is 'Records the nightly database rehearsal''s results (since 15 Nov; spec docs/specs/2026-11-15-rehearsal-on-today.md): from GitHub''s answer listing the runs of .github/workflows/database-rehearsal.yml (its workflow_runs), every finished run in GiteshJain/Equinox on main started by the timer (schedule) or by hand (workflow_dispatch) becomes one job_runs row (rehearsal; started_at the run''s start, finished_at its end, for_day its UTC day): ok when it passed (success), failed when it failed, timed out, couldn''t start or waited for approval; a cancelled, skipped or neutral run writes nothing. A pull request''s run, a fork''s or another branch''s is never recorded. A run already recorded (details.run_id) changes only when GitHub re-ran it (a higher attempt) or its result changed. Keeps numbers, times, GitHub''s result word and the run''s address only, never a commit message or other text from the answer. Raises when the answer has no list of runs. Answers seen, added and changed. postgres only.';
comment on function private.rehearsal_read(timestamp with time zone) is 'Reads the nightly database rehearsal''s results from GitHub (pg_cron equinox-rehearsal-read, every hour at :50, as postgres; since 15 Nov, to-do 239, spec docs/specs/2026-11-15-rehearsal-on-today.md): first notes the answer to each earlier read of the last two days that has none yet (pg_net''s net._http_response, kept 6 hours): a 200 goes to private.rehearsal_record() and the read row stays ok with how many runs it listed, added and changed; another status, a time-out, no answer or an answer that doesn''t read makes that read row failed with the words (an answer older than 6 hours is gone, and the row says so). Then asks GitHub''s public API again (GET https://api.github.com/repos/GiteshJain/Equinox/actions/workflows/database-rehearsal.yml/runs?branch=main&per_page=10, through pg_net, no key: the repository is public) and writes one job_runs row (rehearsal_read, with the request id). Read rows older than 14 days are deleted; the nightly runs'' rows stay. p_at: the run''s moment, default now (for the checks). postgres only.';
comment on function private.schedule_jobs() is 'Schedules the database jobs with pg_cron, by name, so it can run again safely: equinox-snapshot-fallback at 10:00 UTC (private.job_snapshot_fallback), equinox-cleanup at 10:20 UTC (private.job_cleanup), since 10 Nov equinox-capture-dispatch at 09:30 and 21:30 UTC (private.capture_dispatch) and equinox-capture-dispatch-answer at 09:40 and 21:40 UTC (private.capture_dispatch_answer), since 11 Nov equinox-figures every minute (private.figures_refresh, the stored planner figures), and since 15 Nov equinox-rehearsal-read every hour at :50 (private.rehearsal_read, the nightly rehearsal''s result from GitHub). Run by migrations 20261011150000_jobs, 20261110040000_unattended_capture, 20261111020000_stored_figures and 20261115120000_rehearsal_on_today, and again after a full restore (the backup copies no schedules). Answers with the jobs as the scheduler has them.';

select private.schedule_jobs();

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

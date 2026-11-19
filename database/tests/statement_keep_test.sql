-- Statement lines kept 3 days, and the scheduler's log trimmed to 7 (to-do 252; spec docs/specs/2026-11-19-statement-keep.md;
-- migration 20261119100000_statement_keep.sql). Run by database/rehearse.sh on the copy of last night's backup, after the
-- new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (counts,
-- times and keys, never figures).
-- Nothing here depends on what the copy holds, the date or the weekday: the statement checks run in a world of its own
-- with hand-made rows, once for a run on each of the next seven days (the run's moment moved, as p_at allows); the
-- scheduler's log checks count only the rows they add, and switch the default world's statement part off for that run
-- so the copy's lines can't fail it.
--   1. The catalogue: settings.statement_keep_days (3) and cron_log_keep_days (7) in every world, in days, described,
--      with the brief as their reason; job_cleanup()'s and archive_delete()'s descriptions and archive_delete()'s refusal
--      name the setting; postgres, which runs equinox-cleanup, may delete from cron.job_run_details.
--   2. A world of its own, a run on each of seven days: raw pages 15 days old go and 13 days old stay; statement lines
--      older than 3 days go (a flight's and a payment's), one exactly 3 days old and younger ones stay, game_flights and
--      game_payments are untouched; the note says 3 days; details give the statement's cut (now less 3 days) apart from
--      the raw pages' (now less 14). Then a line older than 3 days in neither: none goes, the run fails and says so.
--      Then the setting taken away: no line goes, the note says why. Then 1 day: the 2-day line goes too.
--   3. The scheduler's log, in the default world's row only: rows older than 7 days go (one still running counted by its
--      start), a row 6 days old stays; the note and details say so; without the setting none goes.

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
declare d text;
begin
  assert (select count(*) = (select count(*) from public.worlds)
                 and bool_and(s.value = '3'::jsonb and s.unit = 'days' and length(coalesce(s.description, '')) > 60
                              and coalesce(s.reason, '') like '%2026-11-18-database-growth%')
            from public.settings s where s.key = 'statement_keep_days' and s.airline_id is null),
    'settings.statement_keep_days isn''t 3 days, described and with its reason, in every world';
  assert (select count(*) = (select count(*) from public.worlds)
                 and bool_and(s.value = '7'::jsonb and s.unit = 'days' and length(coalesce(s.description, '')) > 60
                              and coalesce(s.reason, '') like '%2026-11-18-database-growth%')
            from public.settings s where s.key = 'cron_log_keep_days' and s.airline_id is null),
    'settings.cron_log_keep_days isn''t 7 days, described and with its reason, in every world';
  d := coalesce(obj_description('private.job_cleanup(timestamptz)'::regprocedure, 'pg_proc'), '');
  assert position('statement_keep_days' in d) > 0 and position('cron_log_keep_days' in d) > 0,
    'private.job_cleanup()''s description doesn''t name statement_keep_days and cron_log_keep_days';
  assert position('statement_keep_days' in coalesce(obj_description('private.archive_delete(date, text, bigint, text)'::regprocedure, 'pg_proc'), '')) > 0
     and position('statement_keep_days' in pg_get_functiondef('private.archive_delete(date, text, bigint, text)'::regprocedure)) > 0
     and position('after 14 days' in pg_get_functiondef('private.archive_delete(date, text, bigint, text)'::regprocedure)) = 0,
    'private.archive_delete() still says the statement clean-up removes lines after 14 days';
  assert position('14 days' in coalesce(obj_description('public.game_statement'::regclass, 'pg_class'), '')) = 0
      or position('statement_keep_days' in coalesce(obj_description('public.game_statement'::regclass, 'pg_class'), '')) > 0,
    'game_statement''s description doesn''t name statement_keep_days';
  assert has_table_privilege('postgres', 'cron.job_run_details', 'delete'),
    'postgres, which runs equinox-cleanup, may not delete from cron.job_run_details';
  raise notice 'catalogue: statement_keep_days 3 and cron_log_keep_days 7 days in every world, described; the clean-up and the archive''s guard name the setting; postgres may delete the scheduler''s log';
end
$test$;

-- ---------------------------------------------------------------- 2. a world of its own, a run on each of seven days
do $test$
declare
  w bigint; g bigint; al bigint; v_day int; v_at timestamptz; j record; f1 bigint; f2 bigint; v_raw_old bigint;
  v_raw_young bigint; n_fl bigint; n_pay bigint; v_days text := '';
  t_old timestamptz; t_edge timestamptz; t_young timestamptz;
begin
  insert into public.worlds (name, game_host, kind) values ('statement keep test', 'statement-keep.test', 'exclusive') returning id into w;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, active) values (w, g, 990252, 'Keep Test Air', true) returning id into al;
  insert into public.settings (world_id, airline_id, key, value, unit, description) values
    (w, null, 'statement_cleanup_enabled', 'true', null, 'statement keep test'),
    (w, null, 'statement_keep_days', '3', 'days', 'statement keep test');

  for v_day in 0 .. 6 loop
    -- the run's moment: 10:20 UTC on each of the next seven days, so every weekday is a run day once
    v_at := (current_date + v_day)::timestamp at time zone 'UTC' + interval '10 hours 20 minutes';
    begin
      t_old := date_trunc('minute', v_at - interval '4 days'); t_edge := v_at - interval '3 days';
      t_young := date_trunc('minute', v_at - interval '2 days');
      insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
      values (w, al, 'Keep Test Air', 'html', 'statement-keep-test', '[]', v_at - interval '15 days') returning id into v_raw_old;
      insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
      values (w, al, 'Keep Test Air', 'html', 'statement-keep-test', '[]', v_at - interval '13 days') returning id into v_raw_young;
      -- 4 days old: a flight's line and a payment's; exactly 3 days old: a flight's line; 2 days old: a payment's
      insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, dep_at,
                                       pax_income, income_total, cost_total, money_captured_at)
      values (w, al, t_old, 1, 1, 'ZZA', 'ZZB', t_old, 100, 100, 40, t_old) returning id into f1;
      insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, dep_at,
                                       pax_income, income_total, cost_total, money_captured_at)
      values (w, al, t_edge, 1, 1, 'ZZA', 'ZZB', t_edge, 100, 100, 40, t_edge) returning id into f2;
      insert into public.game_payments (world_id, airline_id, paid_at, kind, descr, amount, side, occ, statement_blk)
      values (w, al, t_old, 'other', 'keep-test payment', 7, 'D', 1, 0);
      insert into public.game_payments (world_id, airline_id, paid_at, kind, descr, amount, side, occ, statement_blk)
      values (w, al, t_young, 'other', 'keep-test young', 3, 'D', 1, 0);
      insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id) values
        (w, al, 'Keep Test Air', t_old, 'Passenger transport income (ZZA-ZZB) keep-test', 100, 'C', 1, 1, f1),
        (w, al, 'Keep Test Air', t_old, 'keep-test payment', 7, 'D', 1, 0, null),
        (w, al, 'Keep Test Air', t_edge, 'Passenger transport income (ZZA-ZZB) keep-test', 100, 'C', 1, 1, f2),
        (w, al, 'Keep Test Air', t_young, 'keep-test young', 3, 'D', 1, 0, null);
      select count(*) into n_fl from public.game_flights where world_id = w;
      select count(*) into n_pay from public.game_payments where world_id = w;

      perform private.job_cleanup(v_at);
      select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
      assert j.status = 'ok' and j.note like 'raw pages: 1 deleted (older than 14 days); statement lines: 2 deleted (older than 3 days; 1 in game_flights, 1 in game_payments); %',
        format('day %s (%s): the run: %s, %s', v_day, to_char(v_at, 'Dy DD Mon'), j.status, j.note);
      assert (j.details ->> 'statement_keep_days')::int = 3 and (j.details ->> 'statement_deleted')::int = 2
         and (j.details ->> 'statement_before')::timestamptz = v_at - interval '3 days'
         and (j.details ->> 'before')::timestamptz = v_at - interval '14 days' and not j.details ? 'cron_log_deleted',
        format('day %s: the details don''t give each cut apart: %s', v_day, j.details);
      assert not exists (select 1 from public.game_capture_raw where id = v_raw_old) and exists (select 1 from public.game_capture_raw where id = v_raw_young),
        format('day %s: raw pages aren''t kept 14 days', v_day);
      assert (select string_agg(s.descr || '@' || extract(epoch from v_at - s.ts)::int / 3600, ', ' order by s.ts) from public.game_statement s where s.world_id = w)
             = 'Passenger transport income (ZZA-ZZB) keep-test@72, keep-test young@48',
        format('day %s: the lines left aren''t the one exactly 3 days old and the younger one: %s', v_day,
               (select string_agg(s.descr || ' ' || s.ts, ', ') from public.game_statement s where s.world_id = w));
      assert (select count(*) from public.game_flights where world_id = w) = n_fl and (select count(*) from public.game_payments where world_id = w) = n_pay,
        format('day %s: the clean-up touched game_flights or game_payments', v_day);

      -- a line older than 3 days in neither: none goes, the run fails and says so
      insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id) values
        (w, al, 'Keep Test Air', t_old, 'keep-test unfolded', 5, 'D', 1, 0, null),
        (w, al, 'Keep Test Air', t_old, 'Passenger transport income (ZZA-ZZB) keep-test 2', 100, 'C', 1, 1, f1);
      perform private.job_cleanup(v_at);
      select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
      assert j.status = 'failed' and j.note like '%statement lines: 1 of the 2 older than 3 days aren''t in game_flights or game_payments, so none were deleted%'
         and (select count(*) from public.game_statement where world_id = w and ts < v_at - interval '3 days') = 2,
        format('day %s: a line in neither: %s, %s', v_day, j.status, j.note);
      delete from public.game_statement where world_id = w and descr = 'keep-test unfolded';

      -- without the setting: no line goes, and the note says why
      delete from public.settings where world_id = w and airline_id is null and key = 'statement_keep_days';
      perform private.job_cleanup(v_at);
      select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
      assert j.status = 'ok' and j.note like '%statement lines: none deleted (no settings.statement_keep_days of 1 day or more)%'
         and (select count(*) from public.game_statement where world_id = w) = 3 and j.details -> 'statement_keep_days' = 'null'::jsonb,
        format('day %s: without the setting: %s, %s', v_day, j.status, j.note);

      -- 1 day: the 3-day and 2-day lines go too, with the second 4-day one
      insert into public.settings (world_id, airline_id, key, value, unit, description) values (w, null, 'statement_keep_days', '1', 'days', 'statement keep test');
      perform private.job_cleanup(v_at);
      select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
      assert j.status = 'ok' and j.note like '%statement lines: 3 deleted (older than 1 days; 2 in game_flights, 1 in game_payments)%'
         and not exists (select 1 from public.game_statement where world_id = w),
        format('day %s: with 1 day: %s, %s', v_day, j.status, j.note);

      v_days := v_days || to_char(v_at, 'Dy ');
      raise exception 'statement keep test: next day';
    exception when others then
      if sqlerrm <> 'statement keep test: next day' then raise; end if;   -- each day starts from the same rows
    end;
  end loop;
  raise notice 'a world of its own, a run on each of %(10:20 UTC): raw pages 15 days old go, 13 kept; lines older than 3 days go (a flight''s, a payment''s), exactly 3 days old and younger stay, flights and payments untouched; the details give the statement''s cut and the raw pages'' apart; a line in neither fails the run and none goes; without the setting none goes; 1 day takes the 2-day line',
    v_days;
end
$test$;

-- ---------------------------------------------------------------- 3. the scheduler's log
do $test$
declare
  dw bigint := (select id from public.worlds where is_default); v_at timestamptz := now() + interval '3 days'; j record;
  r_old bigint; r_running bigint; r_young bigint; n_before bigint; v_prev bigint;
begin
  if dw is null then raise notice 'the scheduler''s log: no default world, nothing to check'; return; end if;
  -- the copy's statement lines aren't this part's business: switched off for this run, so they can't fail it
  update public.settings set value = 'false' where world_id = dw and airline_id is null and key = 'statement_cleanup_enabled';
  insert into cron.job_run_details (jobid, job_pid, database, username, command, status, return_message, start_time, end_time)
  values (990252, 1, current_database(), 'postgres', 'select 1 -- statement keep test', 'succeeded', '1 row', v_at - interval '8 days', v_at - interval '8 days' + interval '1 second')
  returning runid into r_old;
  insert into cron.job_run_details (jobid, job_pid, database, username, command, status, return_message, start_time, end_time)
  values (990252, 1, current_database(), 'postgres', 'select 1 -- statement keep test', 'running', null, v_at - interval '9 days', null)
  returning runid into r_running;
  insert into cron.job_run_details (jobid, job_pid, database, username, command, status, return_message, start_time, end_time)
  values (990252, 1, current_database(), 'postgres', 'select 1 -- statement keep test', 'succeeded', '1 row', v_at - interval '6 days', v_at - interval '6 days' + interval '1 second')
  returning runid into r_young;
  select count(*) into n_before from cron.job_run_details d where coalesce(d.end_time, d.start_time) < v_at - interval '7 days';

  v_prev := coalesce((select max(id) from public.job_runs), 0);
  perform private.job_cleanup(v_at);
  select * into j from public.job_runs where job = 'cleanup' and world_id = dw order by id desc limit 1;
  assert j.note like format('%%; scheduler''s log: %s deleted (older than 7 days)', n_before)
     and (j.details ->> 'cron_log_deleted')::bigint = n_before and (j.details ->> 'cron_log_keep_days')::int = 7
     and (j.details ->> 'cron_log_before')::timestamptz = v_at - interval '7 days',
    format('the default world''s row doesn''t count the scheduler''s log: %s, %s', j.note, j.details);
  assert not exists (select 1 from cron.job_run_details where runid in (r_old, r_running))
     and exists (select 1 from cron.job_run_details where runid = r_young),
    'the scheduler''s log isn''t trimmed to 7 days (by its end, or its start while running)';
  assert not exists (select 1 from public.job_runs x where x.job = 'cleanup' and x.id > v_prev and x.world_id <> dw and x.details ? 'cron_log_deleted'),
    'another world''s row trims the scheduler''s log too';

  -- without the setting none goes
  insert into cron.job_run_details (jobid, job_pid, database, username, command, status, return_message, start_time, end_time)
  values (990252, 1, current_database(), 'postgres', 'select 1 -- statement keep test', 'succeeded', '1 row', v_at - interval '8 days', v_at - interval '8 days')
  returning runid into r_old;
  delete from public.settings where world_id = dw and airline_id is null and key = 'cron_log_keep_days';
  perform private.job_cleanup(v_at);
  select * into j from public.job_runs where job = 'cleanup' and world_id = dw order by id desc limit 1;
  assert j.note like '%; scheduler''s log: none deleted (no settings.cron_log_keep_days)' and exists (select 1 from cron.job_run_details where runid = r_old),
    format('without the setting: %s', j.note);
  raise notice 'the scheduler''s log: % row(s) older than 7 days deleted in the default world''s row (one still running, by its start), one 6 days old kept; none without the setting', n_before;
end
$test$;

do $$ begin raise notice 'statement keep: all checks passed'; end $$;

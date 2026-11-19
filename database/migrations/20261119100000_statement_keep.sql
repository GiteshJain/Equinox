-- Statement lines kept 3 days, and the scheduler's log trimmed to 7 (19 Nov 2026; to-do 252; brief
-- docs/briefs/2026-11-18-database-growth.md, Gitesh 19 Nov: "keep statement lines 3 days, trim the scheduler's log,
-- then compact once"; spec docs/specs/2026-11-19-statement-keep.md).
--
-- Why: the database is about 247 MB (amber 245, trigger 350, manual §1). game_statement's primary-key index is 30.4 MB
-- against an 18 MB table of about 110,000 lines and grew 1.9 MB in a day; about 10,300 lines come in a day. Nothing
-- reads a line once it is folded into game_flights or game_payments (the spec lists every reader). The scheduler's own
-- log (cron.job_run_details, about 1,470 rows a day since the figures job runs every minute) is never trimmed.
--
-- What changes, every night at 10:20 UTC (private.job_cleanup(), pg_cron equinox-cleanup):
--   - statement lines are kept settings.statement_keep_days (3) days, not 14. Still only while
--     settings.statement_cleanup_enabled is true, and still only once every older line is in game_flights or
--     game_payments (counted first; otherwise none goes and the run fails, saying how many aren't). Without the setting
--     (or with one that isn't a whole number of days, 1 or more) no line goes, and the note says so.
--   - raw pages stay 14 days; the world scans' part is untouched.
--   - the scheduler's log: rows older than settings.cron_log_keep_days (7) go, once a run (in the default world's row;
--     the log is the database's, not a world's), in a block of its own: a failure there fails the run, says why and
--     undoes only its own delete. Without the setting nothing goes.
--   - the job_runs row's details give each cut on its own: before (the raw pages', as it was), statement_before and
--     statement_keep_days, and cron_log_before / cron_log_keep_days / cron_log_deleted; its note gives the days used.
-- private.archive_delete()'s reason for a flight a line still points at names the setting instead of "14 days".
--
-- The first run deletes about 11 days of lines (about 80,000 rows) as one statement; on a copy with 110,000 lines it
-- took well under a second locally (spec, "the first run").
--
-- Adds two settings; replaces two functions with the same arguments (create or replace keeps their grants) and four
-- descriptions. Drops and deletes nothing itself, so it can be applied from the chat.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261119100000_statement_keep', true);

-- ============================================================ 1. the settings
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'statement_keep_days', '3'::jsonb, 'days',
       'How long bank-statement lines (game_statement) are kept (manual §7, the 10:20 UTC clean-ups): while '
       'statement_cleanup_enabled is true, private.job_cleanup() deletes lines older than this many days, only once every '
       'one is in game_flights or game_payments. A whole number, 1 or more; without this row no line is deleted. Raw '
       'capture pages keep 14 days whatever this says.',
       date '2026-11-19',
       'Gitesh, 19 Nov: docs/briefs/2026-11-18-database-growth.md, statement lines 3 days (was 14) with the scheduler''s log trimmed and one compaction; nothing reads a folded line, raw pages keep 14 days and backups 30'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'cron_log_keep_days', '7'::jsonb, 'days',
       'How long the scheduler''s own log (cron.job_run_details, one row per pg_cron run) is kept (manual §7, the 10:20 '
       'UTC clean-ups): private.job_cleanup() deletes rows older than this many days once a run, reading the default '
       'world''s row. A whole number, 1 or more; without it nothing is deleted. job_runs, our own record, is not touched.',
       date '2026-11-19',
       'Gitesh, 19 Nov: docs/briefs/2026-11-18-database-growth.md (about 1,470 rows a day since the figures job runs every minute, never trimmed; the log is only for debugging)'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2. the clean-up
create or replace function private.job_cleanup(p_at timestamp with time zone default null)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_at timestamptz := coalesce(p_at, now()); v_cut timestamptz := coalesce(p_at, now()) - interval '14 days'; w record;
  t0 timestamptz; n_raw int; v_on boolean; n_old bigint; n_tied bigint; n_paid bigint; n_del int; v_status text;
  v_note text; v_details jsonb; v_scan jsonb; v_out jsonb := '[]'::jsonb; v_keep int; v_stmt_cut timestamptz;
  v_cron_world bigint; v_cron_days int; v_cron_cut timestamptz; n_cron int; v_cron_note text; v_cron jsonb;
begin
  perform set_config('equinox.actor', 'job', true), set_config('equinox.actor_detail', 'cleanup', true);
  -- the scheduler's log is the database's, not a world's: trimmed once a run, in the default world's row (else the first)
  select x.id into v_cron_world from public.worlds x order by x.is_default desc, x.id limit 1;
  for w in select x.id from public.worlds x
            where exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                           where a.world_id = x.id and a.active and g.kind = 'ours')
               or exists (select 1 from public.game_capture_raw r where r.world_id = x.id)
            order by x.id loop
    t0 := clock_timestamp(); n_del := 0; v_status := 'ok'; n_old := 0; n_tied := 0; n_paid := 0; v_cron := '{}'::jsonb;
    begin
      delete from public.game_capture_raw r where r.world_id = w.id and r.captured_at < v_cut;
      get diagnostics n_raw = row_count;

      -- statement lines: kept settings.statement_keep_days (since 19 Nov; 14 days before)
      v_on := coalesce((select (s.value #>> '{}')::boolean from public.settings s
                         where s.world_id = w.id and s.airline_id is null and s.key = 'statement_cleanup_enabled'), false);
      v_keep := (select (s.value #>> '{}')::int from public.settings s
                  where s.world_id = w.id and s.airline_id is null and s.key = 'statement_keep_days'
                    and jsonb_typeof(s.value) = 'number' and (s.value #>> '{}') ~ '^[0-9]+$' and (s.value #>> '{}')::int >= 1);
      v_stmt_cut := v_at - make_interval(days => v_keep);
      if v_keep is not null then
        select count(*), count(*) filter (where s.flight_id is not null),
               count(*) filter (where s.flight_id is null
                                  and exists (select 1 from public.game_payments p
                                               where p.airline_id = s.airline_id and p.paid_at = s.ts and p.descr = s.descr
                                                 and p.amount = s.amount and p.occ = s.occ))
          into n_old, n_tied, n_paid
          from public.game_statement s
         where s.world_id = w.id and s.ts < v_stmt_cut;
      end if;
      if v_keep is null then
        v_note := 'statement lines: none deleted (no settings.statement_keep_days of 1 day or more)';
      elsif not v_on then
        v_note := format('statement lines: switched off (settings.statement_cleanup_enabled), %s older than %s days kept', n_old, v_keep);
      elsif n_old = 0 then
        v_note := format('statement lines: none older than %s days', v_keep);
      elsif n_old <> n_tied + n_paid then
        v_status := 'failed';
        v_note := format('statement lines: %s of the %s older than %s days aren''t in game_flights or game_payments, so none were deleted',
                         n_old - n_tied - n_paid, n_old, v_keep);
      else
        -- one statement: about 80,000 lines the first night, about 10,300 a night after (spec, "the first run")
        delete from public.game_statement s
         where s.world_id = w.id and s.ts < v_stmt_cut
           and (s.flight_id is not null
                or exists (select 1 from public.game_payments p
                            where p.airline_id = s.airline_id and p.paid_at = s.ts and p.descr = s.descr
                              and p.amount = s.amount and p.occ = s.occ));
        get diagnostics n_del = row_count;
        v_note := format('statement lines: %s deleted (older than %s days; %s in game_flights, %s in game_payments)', n_del, v_keep, n_tied, n_paid);
      end if;
      v_note := format('raw pages: %s deleted (older than 14 days); ', n_raw) || v_note;
      -- the world scans (since 15 Nov, spec docs/specs/2026-11-15-scan-cleanup.md): in a block of its own, so a failure
      -- there undoes only its own deletes, fails the run and says so
      begin
        v_scan := private.scan_cleanup(w.id, v_at);
      exception when others then
        v_status := 'failed';
        v_scan := jsonb_build_object('scan_enabled', null, 'note', 'world scans: failed, nothing deleted: ' || sqlerrm);
      end;
      v_note := v_note || '; ' || (v_scan ->> 'note');
      -- the scheduler's log (since 19 Nov), once a run: in a block of its own, so a failure (no right to delete there)
      -- fails the run, says why and undoes only this delete
      if w.id = v_cron_world then
        v_cron_days := (select (s.value #>> '{}')::int from public.settings s
                         where s.world_id = w.id and s.airline_id is null and s.key = 'cron_log_keep_days'
                           and jsonb_typeof(s.value) = 'number' and (s.value #>> '{}') ~ '^[0-9]+$' and (s.value #>> '{}')::int >= 1);
        v_cron_cut := v_at - make_interval(days => v_cron_days); n_cron := 0;
        if v_cron_days is null then
          v_cron_note := 'scheduler''s log: none deleted (no settings.cron_log_keep_days)';
        else
          begin
            delete from cron.job_run_details d where coalesce(d.end_time, d.start_time) < v_cron_cut;
            get diagnostics n_cron = row_count;
            v_cron_note := format('scheduler''s log: %s deleted (older than %s days)', n_cron, v_cron_days);
          exception when others then
            v_status := 'failed'; n_cron := null;
            v_cron_note := 'scheduler''s log: failed, nothing deleted: ' || sqlerrm;
          end;
        end if;
        v_note := v_note || '; ' || v_cron_note;
        v_cron := jsonb_build_object('cron_log_keep_days', v_cron_days, 'cron_log_before', v_cron_cut, 'cron_log_deleted', n_cron);
      end if;
      v_details := jsonb_build_object('before', v_cut, 'raw_deleted', n_raw, 'statement_enabled', v_on,
                                      'statement_keep_days', v_keep, 'statement_before', v_stmt_cut,
                                      'statement_old', n_old, 'statement_in_flights', n_tied, 'statement_in_payments', n_paid,
                                      'statement_deleted', n_del) || (v_scan - 'note') || v_cron;
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('cleanup', w.id, t0, clock_timestamp(), v_status, private.capture_day(w.id, v_at), v_note, v_details);
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', v_status, 'note', v_note) || v_details;
    exception when others then
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('cleanup', w.id, t0, clock_timestamp(), 'failed', private.capture_day(w.id, v_at), 'clean-up: ' || sqlerrm,
              jsonb_build_object('before', v_cut, 'statement_before', v_stmt_cut, 'sqlstate', sqlstate));
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', 'failed', 'note', sqlerrm);
    end;
  end loop;
  return v_out;
end
$function$;

-- ============================================================ 3. the archive's guard names the setting
create or replace function private.archive_delete(p_month date, p_table text, p_expected_count bigint, p_checksum text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
 SET "DateStyle" TO 'ISO, YMD'
 SET "IntervalStyle" TO 'postgres'
 SET extra_float_digits TO '1'
 SET bytea_output TO 'hex'
AS $function$
declare
  t0 timestamptz := clock_timestamp(); v_kept date; c record; v_reasons text[] := '{}'; n bigint; v_deleted bigint;
  v_sum text; v_version text; v_job bigint; v_label text;
begin
  perform private.archive_check_args(p_month, p_table);
  v_label := p_table || ' ' || to_char(p_month, 'YYYY-MM');
  execute format('lock table public.%I in share row exclusive mode', p_table);
  v_kept := private.archive_kept_from(p_table, (now() at time zone 'UTC')::date);
  if p_month >= v_kept then
    v_reasons := v_reasons || format('%s is inside the kept window (%s keeps %s, from %s on)', to_char(p_month, 'YYYY-MM'),
      p_table, case when p_table = 'change_log' then 'the last 12 full months' else 'one full calendar month' end, to_char(v_kept, 'YYYY-MM'));
  end if;
  select * into c from private.archive_checksum(p_month, p_table);
  if p_expected_count is distinct from c.rows then
    v_reasons := v_reasons || format('the count doesn''t match (%s expected, %s there now)', coalesce(p_expected_count::text, 'none'), c.rows);
  end if;
  if p_checksum is distinct from c.checksum then
    v_reasons := v_reasons || 'the checksum doesn''t match (the rows changed since the manifest)'::text;
  end if;
  if p_table = 'game_flights' then
    -- every flight of the month is in route_days, as many per route and day as game_flights has (history_flows's rule)
    execute format($q$
      with f as (
        select x.airline_id, x.origin_code, x.dest_code, coalesce((x.dep_at at time zone 'UTC')::date, x.game_date) as day, count(*) as n
          from public.game_flights x
         where %s and (x.flight_no is not null or x.pax_income is not null)
           and coalesce(x.origin_code, '') <> '' and coalesce(x.dest_code, '') <> ''
         group by 1, 2, 3, 4)
      select count(*) from f
        left join public.route_days r on r.airline_id = f.airline_id and r.origin_code = f.origin_code
                                     and r.dest_code = f.dest_code and r.day = f.day
       where r.flights is distinct from f.n::int$q$, private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s route day(s) of the month aren''t in route_days as game_flights has them (run private.history_flows() for the month first)', n);
    end if;
    execute format('select count(*) from public.game_statement s join public.game_flights x on x.id = s.flight_id where %s',
                   private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s statement line(s) still point at these flights (the statement clean-up removes them once older than settings.statement_keep_days, %s days, while it is switched on)',
                                       n, coalesce((select s.value #>> '{}' from public.settings s join public.worlds w on w.id = s.world_id and w.is_default
                                                     where s.airline_id is null and s.key = 'statement_keep_days'), 'not set'));
    end if;
  end if;
  if p_table = 'market_reads' then
    -- the reads go last: their fares and shares point at them, and are archived first
    execute format('select (select count(*) from public.market_fares f where f.read_id in (select x.id from public.market_reads x where %1$s))
                         + (select count(*) from public.market_shares s where s.read_id in (select x.id from public.market_reads x where %1$s))',
                   private.archive_where(p_month, p_table, 'x')) into n;
    if n > 0 then
      v_reasons := v_reasons || format('%s market_fares or market_shares row(s) still point at these reads (archive those tables'' month first)', n);
    end if;
  end if;
  if cardinality(v_reasons) > 0 then
    raise exception 'archive_delete refused %: %', v_label, array_to_string(v_reasons, '; ') using errcode = 'P0001';
  end if;

  -- the delete, checking the rows it removes against the manifest's count and checksum
  execute format('with d as (delete from public.%I t where %s returning t.*) select count(*), md5(coalesce(string_agg(d::text, E''\n'' order by %s), '''')) from d',
                 p_table, private.archive_where(p_month, p_table, 't'), private.archive_order(p_table, 'd'))
     into v_deleted, v_sum;
  if v_deleted <> p_expected_count or v_sum <> p_checksum then
    raise exception 'archive_delete stopped %: the rows it was deleting weren''t the manifest''s (% rows); nothing was deleted', v_label, v_deleted;
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into v_version;
  end if;
  insert into public.job_runs (job, started_at, finished_at, status, for_month, note, details)
  values ('archive', t0, clock_timestamp(), 'ok', p_month,
          format('%s: %s row(s) archived and deleted', v_label, v_deleted),
          jsonb_build_object('table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'rows', v_deleted, 'checksum', v_sum,
                             'migration_version', v_version))
  returning id into v_job;
  return jsonb_build_object('table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'deleted', v_deleted, 'job_run_id', v_job);
end
$function$;

-- ============================================================ 4. descriptions
comment on function private.job_cleanup(timestamp with time zone) is 'The 10:20 UTC job (pg_cron equinox-cleanup; design §7; manual §7): per world, deletes raw pages (game_capture_raw) older than 14 days, and, while settings.statement_cleanup_enabled is true, statement lines older than settings.statement_keep_days (3 since 19 Nov; 14 before; none without the setting), only once every one is in game_flights or game_payments (counted first; otherwise none goes and the run fails, saying how many aren''t); since 15 Nov also the world scans'' connections and summaries older than settings.scan_keep_days (private.scan_cleanup(), in a block of its own: a failure there fails the run and undoes only its own deletes); since 19 Nov, once a run in the default world''s row, the scheduler''s log (cron.job_run_details) older than settings.cron_log_keep_days (7), in a block of its own too (spec docs/specs/2026-11-19-statement-keep.md). One job_runs row per world (cleanup), failed with the error rather than raised; its note gives each part''s counts and days, its details each cut on its own (before: the raw pages''; statement_before; cron_log_before). p_at: the run''s moment, default now (for the checks).';
comment on table public.game_statement is 'Bank-statement lines from the capture, as the game lists them. Each line is folded into a flight (flight_id) in game_flights or into game_payments. Kept settings.statement_keep_days (3 days since 19 Nov; 14 before) while the statement clean-up is switched on (settings.statement_cleanup_enabled; the 10:20 UTC job deletes older lines only once every one is in game_flights or game_payments); the raw pages keep 14 days and the nightly backups 30. Written by the capture (private.capture_page).';
do $d$
declare d text;
begin
  d := obj_description('private.archive_delete(date, text, bigint, text)'::regprocedure, 'pg_proc');
  if position('statement_keep_days' in coalesce(d, '')) = 0 then
    execute format('comment on function private.archive_delete(date, text, bigint, text) is %L', coalesce(d, '')
      || ' Since 19 Nov its reason for flights that statement lines still point at names settings.statement_keep_days (spec docs/specs/2026-11-19-statement-keep.md).');
  end if;
end
$d$;
update public.settings
   set description = 'The 10:20 UTC clean-up deletes statement lines older than settings.statement_keep_days (3 since 19 Nov; 14 before; only once each is in game_flights or game_payments) while this is true (design §7; manual §7)'
 where key = 'statement_cleanup_enabled' and airline_id is null;

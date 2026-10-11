-- The automatic jobs and their warnings (decision #13, build pull request 7).
-- Design: docs/design/2026-10-09-data-model.md (§3.11, §3.12, §5, §6, §7, §10 row 7); the jobs brief
-- docs/briefs/2026-10-09-jobs.md (option B). Spec: docs/specs/2026-10-11-jobs.md.
--
-- Adds and changes; removes nothing. What needs a removal (signed-in accounts' leftover write access to the retired
-- backup_runs table, and its old insert rule) is 20261011150100_jobs_removals.sql, which Gitesh runs after this one.
--   1. job_runs takes over backup_runs (§3.12): its rows move into job_runs (job backup), the table becomes
--      backup_runs_before_13, and backup_runs is a view of today's shape whose insert lands in job_runs, so the nightly
--      backup keeps working whatever the deploy order;
--   2. the 10:00 UTC snapshot fallback (§7): the snapshot of the capture day just ended when no complete capture took
--      it (complete = false, source fallback, cash from the latest balance before it), and any day since the history
--      began that has none;
--   3. the 10:20 UTC clean-ups (§7): raw pages older than 14 days (moved out of capture_ingest(), which did it on every
--      page), and statement lines older than 14 days once each is in game_flights or game_payments. The statement
--      clean-up ships switched off (settings.statement_cleanup_enabled = false);
--   4. the archive's database side (§7): what's due, the manifest of a table's month, the query its rows are exported
--      with, and the guarded delete, private.archive_delete(), the only way the archive removes rows;
--   5. pg_cron switched on, with the two jobs (private.schedule_jobs());
--   6. access and descriptions.
-- Every job writes one job_runs row per run (per world). Apply it when no capture is running.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261011150000_jobs', true);

-- ============================================================ 1. job_runs takes over backup_runs (§3.11, §3.12)
-- Every backup run so far becomes a job_runs row (job backup): its time as both start and finish, ok or failed, its
-- note, and the rest in details (kind, tables, rows, files, bytes, commit_sha, object_key, and its old id).
insert into public.job_runs (job, started_at, finished_at, status, note, details)
select 'backup', b.ran_at, b.ran_at, case when b.ok then 'ok' else 'failed' end, b.note,
       jsonb_strip_nulls(jsonb_build_object('kind', b.kind, 'tables', b.tables, 'rows', b.rows, 'files', b.files,
                                            'bytes', b.bytes, 'commit_sha', b.commit_sha, 'object_key', b.object_key,
                                            'backup_runs_id', b.id))
  from public.backup_runs b
 order by b.id;

-- The table keeps its rows under a new name until #18; the view takes its name in the same transaction, so nothing ever
-- sees neither.
alter table public.backup_runs rename to backup_runs_before_13;

create view public.backup_runs with (security_invoker = true) as
select j.id, j.started_at as ran_at, j.details ->> 'kind' as kind, j.status = 'ok' as ok,
       (j.details ->> 'tables')::integer as tables, (j.details ->> 'rows')::bigint as rows,
       (j.details ->> 'files')::integer as files, (j.details ->> 'bytes')::bigint as bytes,
       j.details ->> 'commit_sha' as commit_sha, j.note, j.details ->> 'object_key' as object_key
  from public.job_runs j
 where j.job = 'backup';

-- The backup job's row (scripts/report.sh in equinox-backups inserts kind, ok, tables, rows, files, bytes, object_key,
-- note) becomes a job_runs row; the same values are refused as the old table refused them.
create or replace function private.backup_runs_insert()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare v_at timestamptz := coalesce(new.ran_at, now()); v_id bigint;
begin
  if new.kind is null or new.kind not in ('nightly', 'manual', 'test') then
    raise exception 'backup_runs: kind must be nightly, manual or test, not %', coalesce(new.kind, 'null') using errcode = '23514';
  end if;
  if new.ok is null then
    raise exception 'backup_runs: ok is required' using errcode = '23502';
  end if;
  insert into public.job_runs (job, started_at, finished_at, status, note, details)
  values ('backup', v_at, v_at, case when new.ok then 'ok' else 'failed' end, new.note,
          jsonb_strip_nulls(jsonb_build_object('kind', new.kind, 'tables', new.tables, 'rows', new.rows, 'files', new.files,
                                               'bytes', new.bytes, 'commit_sha', new.commit_sha, 'object_key', new.object_key)))
  returning id into v_id;
  new.id := v_id;
  new.ran_at := v_at;
  return new;
end
$function$;

create trigger backup_runs_insert instead of insert on public.backup_runs
  for each row execute function private.backup_runs_insert();

-- ============================================================ 2. the 10:00 UTC snapshot fallback (§7)
-- For each world with active airlines of ours: the capture day that has just ended (design §2: it ends at 10:00 UTC),
-- and any earlier day since the history began, gets a snapshot if it has none (private.take_snapshot, source fallback).
-- complete says whether that day's capture was complete (normally not, or the capture would have taken it). Cash with
-- no balance that capture day and none typed comes from the latest balance before the snapshot's moment (design §7). A
-- day that has a snapshot is left alone. One job_runs row per world (snapshot_fallback); a failure is recorded, never
-- raised. p_at is the run's moment (default now), for the checks.
create or replace function private.job_snapshot_fallback(p_at timestamptz default null)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare
  v_at timestamptz := coalesce(p_at, now()); w record; t0 timestamptz; v_last date; v_first date; d date;
  v_moment timestamptz; v_snap jsonb; n int; v_filled date[]; v_taken boolean; v_complete boolean; v_airlines int;
  v_routes int; v_earlier int; v_had text; v_note text; v_details jsonb; v_out jsonb := '[]'::jsonb;
begin
  perform set_config('equinox.actor', 'job', true), set_config('equinox.actor_detail', 'snapshot_fallback', true);
  for w in select x.id from public.worlds x
            where exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                           where a.world_id = x.id and a.active and g.kind = 'ours')
            order by x.id loop
    t0 := clock_timestamp(); v_filled := '{}'; v_taken := false; v_complete := null; v_airlines := 0; v_routes := 0;
    v_earlier := 0; v_last := null;
    begin
      v_last := private.capture_day(w.id, v_at) - 1;
      select min(ad.day) into v_first from public.airline_days ad where ad.world_id = w.id;
      v_first := least(coalesce(v_first, v_last), v_last);
      select string_agg(distinct ad.source, ', ') into v_had from public.airline_days ad where ad.world_id = w.id and ad.day = v_last;
      for d in select g::date from generate_series(v_first, v_last, interval '1 day') g
                where not exists (select 1 from public.airline_days ad where ad.world_id = w.id and ad.day = g::date)
                order by 1 loop
        -- the snapshot stands for the end of that capture day (or now, for a run before the day ends)
        v_moment := least(private.capture_day_start(w.id, d + 1), v_at);
        v_snap := private.take_snapshot(w.id, d, v_moment, 'fallback');
        update public.airline_days ad
           set cash = b.amount, cash_at = b.captured_at,
               fixed_next7 = (select sum(e.debit) from public.game_events e
                               where e.airline_id = ad.airline_id and e.debit > 0 and e.due_at > b.captured_at
                                 and e.due_at <= b.captured_at + interval '7 days')
          from (select distinct on (x.airline_id) x.airline_id, x.amount, x.captured_at
                  from public.game_balance x
                 where x.world_id = w.id and x.account like '2800%' and x.amount is not null and x.captured_at <= v_moment
                 order by x.airline_id, x.captured_at desc) b
         where ad.world_id = w.id and ad.day = d and ad.source = 'fallback' and ad.cash is null and b.airline_id = ad.airline_id;
        get diagnostics n = row_count;
        if d = v_last then
          v_taken := true; v_complete := (v_snap ->> 'complete')::boolean; v_airlines := (v_snap ->> 'airlines')::int;
          v_routes := coalesce((v_snap ->> 'route_days')::int, 0); v_earlier := n;
        else
          v_filled := v_filled || d;
        end if;
      end loop;
      v_note := case when v_taken
                     then format('%s: no complete capture, so the fallback took the snapshot (%s airline(s)%s%s)',
                                 to_char(v_last, 'DD Mon'), v_airlines,
                                 case when v_complete then '; the capture was complete' else '; capture incomplete' end,
                                 case when v_earlier > 0 then format('; cash from an earlier balance for %s', v_earlier) else '' end)
                     else format('%s: the snapshot was already there (%s)', to_char(v_last, 'DD Mon'),
                                 case v_had when 'capture' then 'taken by the capture' when 'fallback' then 'taken by an earlier run'
                                            else coalesce(v_had, 'none') end) end
                || case when cardinality(v_filled) > 0
                        then format('; filled %s missed day(s): %s', cardinality(v_filled),
                                    (select string_agg(to_char(x, 'DD Mon'), ', ' order by x) from unnest(v_filled) x))
                        else '' end;
      v_details := jsonb_build_object('day', v_last, 'taken', v_taken, 'complete', v_complete, 'airlines', v_airlines,
                                      'route_days', v_routes, 'cash_from_earlier_balance', v_earlier,
                                      'filled', to_jsonb(v_filled), 'at', v_at);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot_fallback', w.id, t0, clock_timestamp(), 'ok', v_last, v_note, v_details);
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', 'ok', 'note', v_note) || v_details;
    exception when others then
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot_fallback', w.id, t0, clock_timestamp(), 'failed', v_last, 'snapshot fallback: ' || sqlerrm,
              jsonb_build_object('at', v_at, 'sqlstate', sqlstate));
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', 'failed', 'note', sqlerrm);
    end;
  end loop;
  return v_out;
end
$function$;

-- ============================================================ 3. the 10:20 UTC clean-ups (§7)
-- Per world: raw pages older than 14 days go (capture_ingest() no longer deletes them on every page). Statement lines
-- older than 14 days go only while settings.statement_cleanup_enabled is true for the world, and only once every one of
-- them is in game_flights (tied to its flight) or game_payments (the job counts first; if any isn't, none goes and the
-- run is failed, naming how many). Lines from the last 14 days are never touched. One job_runs row per world
-- (cleanup); a failure is recorded, never raised. p_at is the run's moment (default now), for the checks.
create or replace function private.job_cleanup(p_at timestamptz default null)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare
  v_at timestamptz := coalesce(p_at, now()); v_cut timestamptz := coalesce(p_at, now()) - interval '14 days'; w record;
  t0 timestamptz; n_raw int; v_on boolean; n_old bigint; n_tied bigint; n_paid bigint; n_del int; v_status text;
  v_note text; v_details jsonb; v_out jsonb := '[]'::jsonb;
begin
  perform set_config('equinox.actor', 'job', true), set_config('equinox.actor_detail', 'cleanup', true);
  for w in select x.id from public.worlds x
            where exists (select 1 from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                           where a.world_id = x.id and a.active and g.kind = 'ours')
               or exists (select 1 from public.game_capture_raw r where r.world_id = x.id)
            order by x.id loop
    t0 := clock_timestamp(); n_del := 0; v_status := 'ok';
    begin
      delete from public.game_capture_raw r where r.world_id = w.id and r.captured_at < v_cut;
      get diagnostics n_raw = row_count;

      v_on := coalesce((select (s.value #>> '{}')::boolean from public.settings s
                         where s.world_id = w.id and s.airline_id is null and s.key = 'statement_cleanup_enabled'), false);
      select count(*), count(*) filter (where s.flight_id is not null),
             count(*) filter (where s.flight_id is null
                                and exists (select 1 from public.game_payments p
                                             where p.airline_id = s.airline_id and p.paid_at = s.ts and p.descr = s.descr
                                               and p.amount = s.amount and p.occ = s.occ))
        into n_old, n_tied, n_paid
        from public.game_statement s
       where s.world_id = w.id and s.ts < v_cut;
      if not v_on then
        v_note := format('statement lines: switched off (settings.statement_cleanup_enabled), %s older than 14 days kept', n_old);
      elsif n_old = 0 then
        v_note := 'statement lines: none older than 14 days';
      elsif n_old <> n_tied + n_paid then
        v_status := 'failed';
        v_note := format('statement lines: %s of the %s older than 14 days aren''t in game_flights or game_payments, so none were deleted',
                         n_old - n_tied - n_paid, n_old);
      else
        delete from public.game_statement s
         where s.world_id = w.id and s.ts < v_cut
           and (s.flight_id is not null
                or exists (select 1 from public.game_payments p
                            where p.airline_id = s.airline_id and p.paid_at = s.ts and p.descr = s.descr
                              and p.amount = s.amount and p.occ = s.occ));
        get diagnostics n_del = row_count;
        v_note := format('statement lines: %s deleted (older than 14 days; %s in game_flights, %s in game_payments)', n_del, n_tied, n_paid);
      end if;
      v_note := format('raw pages: %s deleted (older than 14 days); ', n_raw) || v_note;
      v_details := jsonb_build_object('before', v_cut, 'raw_deleted', n_raw, 'statement_enabled', v_on,
                                      'statement_old', n_old, 'statement_in_flights', n_tied, 'statement_in_payments', n_paid,
                                      'statement_deleted', n_del);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('cleanup', w.id, t0, clock_timestamp(), v_status, private.capture_day(w.id, v_at), v_note, v_details);
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', v_status, 'note', v_note) || v_details;
    exception when others then
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('cleanup', w.id, t0, clock_timestamp(), 'failed', private.capture_day(w.id, v_at), 'clean-up: ' || sqlerrm,
              jsonb_build_object('before', v_cut, 'sqlstate', sqlstate));
      v_out := v_out || jsonb_build_object('world_id', w.id, 'status', 'failed', 'note', sqlerrm);
    end;
  end loop;
  return v_out;
end
$function$;

-- The statement clean-up ships switched off (design §7): the Building chat switches it on once the per-flight backfill
-- (§9) is checked on live.
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'statement_cleanup_enabled', 'false'::jsonb, null,
       'The 10:20 UTC clean-up deletes statement lines older than 14 days (only once each is in game_flights or game_payments) while this is true (design §7)',
       date '2026-10-11', 'Ships off; the Building chat switches it on after checking the per-flight backfill on live'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- The capture stores and parses pages as before; raw pages older than 14 days are now the 10:20 UTC clean-up's.
create or replace function public.capture_ingest(p_key text, p_airline text, p_kind text, p_page text, p_rows jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_world bigint;
begin
  v_world := private.capture_key_world(p_key);
  if v_world is null then return jsonb_build_object('ok', false, 'error', 'bad key'); end if;
  if p_kind is null or p_kind not in ('statement', 'events', 'loads', 'pnl', 'balance', 'html') then
    return jsonb_build_object('ok', false, 'error', 'bad kind');
  end if;
  perform set_config('equinox.actor', 'capture', true);
  return private.capture_store(v_world, p_airline, p_kind, p_page, p_rows, now());
end
$function$;

-- ============================================================ 4. the archive's database side (§7)
-- The tables the archive may delete from, and how many full calendar months each keeps: detail one month (October
-- leaves on or after 1 December), the change log 12.
create or replace function private.archive_tables()
 returns table (table_name text, month_of text, keep_months int)
 language sql
 immutable
 set search_path to ''
as $function$
  select * from (values ('game_flights', 'dep_at (UTC); the game''s date where dep_at isn''t known', 1),
                        ('game_events', 'event_date', 1),
                        ('game_scan_schedules', 'the scan''s time (game_scans.taken_at, UTC)', 1),
                        ('game_scan_airports', 'the scan''s time (game_scans.taken_at, UTC)', 1),
                        ('change_log', 'changed_at (UTC)', 12)) v(table_name, month_of, keep_months)
$function$;

-- The first month a table still keeps on a day: everything before it may be archived
create or replace function private.archive_kept_from(p_table text, p_as_of date)
 returns date
 language sql
 stable
 set search_path to ''
as $function$
  select (date_trunc('month', p_as_of) - make_interval(months => t.keep_months))::date
    from private.archive_tables() t where t.table_name = p_table
$function$;

-- Refuses anything but a listed table and the first day of a month
create or replace function private.archive_check_args(p_month date, p_table text)
 returns void
 language plpgsql
 stable
 set search_path to ''
as $function$
begin
  if p_table is null or not exists (select 1 from private.archive_tables() t where t.table_name = p_table) then
    raise exception 'archive refused: % is not a table the archive may touch (design §7: %)', coalesce(p_table, 'null'),
      (select string_agg(t.table_name, ', ') from private.archive_tables() t) using errcode = '42501';
  end if;
  if p_month is null or p_month <> date_trunc('month', p_month)::date then
    raise exception 'archive refused: the month must be given as its first day (e.g. 2026-10-01), not %', coalesce(p_month::text, 'null')
      using errcode = '22023';
  end if;
end
$function$;

-- The rows of a table's month, as a condition on the table under the alias p_as (one rule for the manifest, the export
-- and the delete)
create or replace function private.archive_where(p_month date, p_table text, p_as text)
 returns text
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  f text := quote_literal(to_char(p_month, 'YYYY-MM-DD') || ' 00:00:00+00') || '::timestamptz';
  t text := quote_literal(to_char((p_month + interval '1 month')::date, 'YYYY-MM-DD') || ' 00:00:00+00') || '::timestamptz';
  fd text := quote_literal(to_char(p_month, 'YYYY-MM-DD')) || '::date';
  td text := quote_literal(to_char((p_month + interval '1 month')::date, 'YYYY-MM-DD')) || '::date';
  a text := quote_ident(p_as);
begin
  perform private.archive_check_args(p_month, p_table);
  return case p_table
    when 'game_flights' then format('((%1$s.dep_at >= %2$s and %1$s.dep_at < %3$s) or (%1$s.dep_at is null and %1$s.game_date >= %4$s and %1$s.game_date < %5$s))', a, f, t, fd, td)
    when 'game_events' then format('(%1$s.event_date >= %2$s and %1$s.event_date < %3$s)', a, fd, td)
    when 'game_scan_schedules' then format('exists (select 1 from public.game_scans s where s.id = %1$s.scan_id and s.taken_at >= %2$s and s.taken_at < %3$s)', a, f, t)
    when 'game_scan_airports' then format('exists (select 1 from public.game_scans s where s.id = %1$s.scan_id and s.taken_at >= %2$s and s.taken_at < %3$s)', a, f, t)
    when 'change_log' then format('(%1$s.changed_at >= %2$s and %1$s.changed_at < %3$s)', a, f, t)
  end;
end
$function$;

-- A table's primary key as an order (text columns in byte order, collate "C", so the order is the same anywhere)
create or replace function private.archive_order(p_table text, p_as text)
 returns text
 language plpgsql
 stable
 set search_path to ''
as $function$
declare a text := quote_ident(p_as);
begin
  return case p_table
    when 'game_flights' then format('%1$s.id', a)
    when 'game_events' then format('%1$s.airline collate "C", %1$s.event_date, %1$s.event_time collate "C", %1$s.descr collate "C"', a)
    when 'game_scan_schedules' then format('%1$s.scan_id, %1$s.airline_id', a)
    when 'game_scan_airports' then format('%1$s.scan_id, %1$s.airport_code collate "C"', a)
    when 'change_log' then format('%1$s.id', a)
  end;
end
$function$;

-- The query the archive step exports a table's month with: every column, in primary-key order
create or replace function private.archive_select(p_month date, p_table text)
 returns text
 language plpgsql
 stable
 set search_path to ''
as $function$
begin
  perform private.archive_check_args(p_month, p_table);
  return format('select t.* from public.%I t where %s order by %s', p_table, private.archive_where(p_month, p_table, 't'),
                private.archive_order(p_table, 't'));
end
$function$;

-- A table's month: how many rows, and the md5 of every row as text (Postgres's own row form, in UTC and ISO dates),
-- joined by newlines, in primary-key order
create or replace function private.archive_checksum(p_month date, p_table text, out rows bigint, out checksum text)
 language plpgsql
 stable
 set search_path to ''
 set timezone to 'UTC'
 set datestyle to 'ISO, YMD'
 set intervalstyle to 'postgres'
 set extra_float_digits to '1'
 set bytea_output to 'hex'
as $function$
begin
  perform private.archive_check_args(p_month, p_table);
  execute format('select count(*), md5(coalesce(string_agg(t::text, E''\n'' order by %s), '''')) from public.%I t where %s',
                 private.archive_order(p_table, 't'), p_table, private.archive_where(p_month, p_table, 't'))
     into rows, checksum;
end
$function$;

-- What the archive step stores beside a month's file (design §7): the row count, the checksum, the table's layout (its
-- columns and their types, and which are generated, so a restore leaves them out) and the latest migration version, so an
-- archive keeps its layout when #18 changes the tables
create or replace function private.archive_manifest(p_month date, p_table text)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
 set timezone to 'UTC'
 set datestyle to 'ISO, YMD'
 set intervalstyle to 'postgres'
 set extra_float_digits to '1'
 set bytea_output to 'hex'
as $function$
declare c record; v_version text; v_kept date := private.archive_kept_from(p_table, (now() at time zone 'UTC')::date);
begin
  perform private.archive_check_args(p_month, p_table);
  select * into c from private.archive_checksum(p_month, p_table);
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select max(version) from supabase_migrations.schema_migrations' into v_version;
  end if;
  return jsonb_build_object(
    'table', p_table, 'month', to_char(p_month, 'YYYY-MM'), 'rows', c.rows, 'checksum', c.checksum,
    'checksum_method', 'md5 of every row as Postgres prints it (timezone UTC, datestyle ISO), joined by newlines, in primary-key order',
    'primary_key_order', private.archive_order(p_table, 't'),
    'month_of', (select t.month_of from private.archive_tables() t where t.table_name = p_table),
    'kept_from', to_char(v_kept, 'YYYY-MM'), 'due', p_month < v_kept,
    'layout', (select jsonb_agg(jsonb_build_object('column', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
                                                   'not_null', a.attnotnull, 'generated', a.attgenerated <> '',
                                                   'identity', a.attidentity <> '') order by a.attnum)
                 from pg_catalog.pg_attribute a
                where a.attrelid = ('public.' || p_table)::regclass and a.attnum > 0 and not a.attisdropped),
    'migration_version', v_version,
    'query', private.archive_select(p_month, p_table),
    'made_at', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
end
$function$;

-- What the archive step has to do: each listed table's months that are older than its kept window and still have rows.
-- p_as_of is the day (default today, UTC), for the checks.
create or replace function private.archive_due(p_as_of date default null)
 returns table (table_name text, month date, rows bigint)
 language sql
 stable
 set search_path to ''
 set timezone to 'UTC'
as $function$
  with k as (
    select t.table_name, private.archive_kept_from(t.table_name, coalesce(p_as_of, (now() at time zone 'UTC')::date)) as kept_from
      from private.archive_tables() t)
  select x.table_name, x.month, x.rows from (
    select 'game_flights' as table_name, date_trunc('month', coalesce(f.dep_at at time zone 'UTC', f.game_date::timestamp))::date as month, count(*) as rows
      from public.game_flights f, k
     where k.table_name = 'game_flights' and coalesce(f.dep_at at time zone 'UTC', f.game_date::timestamp) < k.kept_from::timestamp
     group by 2
    union all
    select 'game_events', date_trunc('month', e.event_date)::date, count(*)
      from public.game_events e, k
     where k.table_name = 'game_events' and e.event_date < k.kept_from
     group by 2
    union all
    select 'game_scan_schedules', date_trunc('month', s.taken_at at time zone 'UTC')::date, count(*)
      from public.game_scan_schedules x join public.game_scans s on s.id = x.scan_id, k
     where k.table_name = 'game_scan_schedules' and s.taken_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'game_scan_airports', date_trunc('month', s.taken_at at time zone 'UTC')::date, count(*)
      from public.game_scan_airports x join public.game_scans s on s.id = x.scan_id, k
     where k.table_name = 'game_scan_airports' and s.taken_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2
    union all
    select 'change_log', date_trunc('month', c.changed_at at time zone 'UTC')::date, count(*)
      from public.change_log c, k
     where k.table_name = 'change_log' and c.changed_at < k.kept_from::timestamp at time zone 'UTC'
     group by 2) x
   order by x.month, x.table_name
$function$;

-- The guarded delete (design §7): the only way the archive removes rows. It refuses a table not listed, a month inside
-- the table's kept window, a count or checksum that no longer matches the rows (they changed since the manifest), and,
-- for game_flights, a month whose flights aren't all in route_days as game_flights has them, or whose flights statement
-- lines still point at. Every reason that applies is named in one refusal. Otherwise it deletes exactly those rows,
-- checking them again as they go (if they aren't the manifest's, nothing is deleted), and records the run in job_runs
-- (job archive, the month in for_month). The table is locked against writes while it works. postgres only.
create or replace function private.archive_delete(p_month date, p_table text, p_expected_count bigint, p_checksum text)
 returns jsonb
 language plpgsql
 set search_path to ''
 set timezone to 'UTC'
 set datestyle to 'ISO, YMD'
 set intervalstyle to 'postgres'
 set extra_float_digits to '1'
 set bytea_output to 'hex'
as $function$
declare
  t0 timestamptz := clock_timestamp(); v_kept date; c record; v_reasons text[] := '{}'; n bigint; v_deleted bigint;
  v_sum text; v_version text; v_job bigint; v_label text;
begin
  perform private.archive_check_args(p_month, p_table);
  v_label := p_table || ' ' || to_char(p_month, 'YYYY-MM');
  execute format('lock table public.%I in share row exclusive mode', p_table);
  v_kept := private.archive_kept_from(p_table, (now() at time zone 'UTC')::date);
  if p_month > v_kept then
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
      v_reasons := v_reasons || format('%s statement line(s) still point at these flights (the statement clean-up removes them after 14 days once it is switched on)', n);
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

-- ============================================================ 5. pg_cron and the two jobs (jobs brief, option B)
-- Supabase's scheduler, inside the database: it runs as postgres and needs no key. Times are UTC.
create extension if not exists pg_cron with schema pg_catalog;

-- (Re)schedules the two jobs by name, so it can run again safely: after a full restore (the backup copies no schedules)
-- or to put a job back. Returns the jobs as the scheduler has them.
create or replace function private.schedule_jobs()
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
begin
  perform cron.schedule('equinox-snapshot-fallback', '0 10 * * *', 'select private.job_snapshot_fallback()');
  perform cron.schedule('equinox-cleanup', '20 10 * * *', 'select private.job_cleanup()');
  return (select jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'command', j.command, 'active', j.active)
                           order by j.jobname)
            from cron.job j where j.jobname like 'equinox-%');
end
$function$;

select private.schedule_jobs();

-- ============================================================ 6. access (design §5)
-- The view: staff read it (through job_runs' staff read rule), nobody else; the backup job (postgres, its owner) adds
-- rows. The new functions: postgres only (the jobs run as postgres, and so does the backup job).
revoke all on table public.backup_runs from public, anon, authenticated;
grant select on table public.backup_runs to authenticated;
revoke all on function private.backup_runs_insert(), private.job_snapshot_fallback(timestamptz), private.job_cleanup(timestamptz),
  private.archive_tables(), private.archive_kept_from(text, date), private.archive_check_args(date, text),
  private.archive_where(date, text, text), private.archive_order(text, text), private.archive_select(date, text),
  private.archive_checksum(date, text), private.archive_manifest(date, text), private.archive_due(date),
  private.archive_delete(date, text, bigint, text), private.schedule_jobs()
  from public, anon, authenticated, service_role;

-- ============================================================ 7. descriptions (decision #10)
comment on view public.backup_runs is 'The nightly backup''s runs (decision #6), in the shape the backup job and the planner have always used: when, which kind (nightly, manual or test), whether it worked, and how many tables, rows, files and bytes it copied, with the copy''s R2 key. Since #13 pull request 7 a view of job_runs (job backup); an insert (scripts/report.sh in equinox-backups) becomes a job_runs row, so the job works whatever the deploy order. The old table is backup_runs_before_13. Read by the planner''s Capture board and the backup warnings on Home. Shows the caller only what it may read.';
comment on column public.backup_runs.id is 'The job_runs row''s id';
comment on column public.backup_runs.ran_at is 'When the run reported (job_runs.started_at)';
comment on column public.backup_runs.kind is 'nightly, manual or test (a pull request''s dry run)';
comment on column public.backup_runs.ok is 'Whether the whole run worked (job_runs.status ok)';
comment on column public.backup_runs.tables is 'Tables copied (job_runs.details)';
comment on column public.backup_runs.rows is 'Rows copied (job_runs.details)';
comment on column public.backup_runs.files is 'Site files copied (job_runs.details)';
comment on column public.backup_runs.bytes is 'Size of the copy before packing (job_runs.details)';
comment on column public.backup_runs.note is 'For a failed run, the end of its log (job_runs.note)';
comment on column public.backup_runs.commit_sha is 'The equinox-backups commit holding that night''s copy (8 and 9 Oct, before R2)';
comment on column public.backup_runs.object_key is 'R2 key of that run''s copy (from 9 Oct; earlier runs have commit_sha)';
comment on table public.backup_runs_before_13 is 'Retired by #13 (pull request 7): the backup runs table as it stood when its rows moved into job_runs (job backup). Nothing writes or reads it; the name backup_runs is now a view. Kept so a revert can put it back, until #18.';

comment on table public.job_runs is 'One row per run of every job (design §3.11): when it started and finished, ok or failed, the day or month it was for, a note and the details. The nightly backup (backup, through the backup_runs view, since #13 pull request 7, with every earlier run moved in), the daily snapshot (snapshot, by the capture; snapshot_fallback, the 10:00 UTC job), the 10:20 UTC clean-ups (cleanup) and the monthly archive (archive, one row per table and month, from the backup job); from #13''s pull request 5 to the switch-over, the side by side (adapter_mirror, adapter_check). The planner''s Home warns from it. Staff read it; only the database''s own functions and postgres write it. Not in the change log.';
comment on column public.job_runs.job is 'backup, snapshot, snapshot_fallback, cleanup, archive, adapter_mirror or adapter_check';
comment on column public.job_runs.for_day is 'The day it was for: a snapshot''s capture day (design §2: 10:00 to 10:00 UTC), or the capture day it ran in';
comment on column public.job_runs.for_month is 'The month it was for (its first day): an archive''s, the month archived';
comment on column public.job_runs.details is 'What a job records about itself: for backup its kind, tables, rows, files, bytes and the copy''s R2 key; for snapshot_fallback the day, whether it took the snapshot, and the missed days it filled; for cleanup what it deleted; for archive the table, rows, checksum, the files in R2 and on the release, and the layout version; for adapter_check the paths that differed (up to 200), why a cash or next-7-day figure wasn''t allowed, the allowed differences used and how long it took; for adapter_mirror the rows written';

comment on table public.game_capture_raw is 'Every page the capture sent, as rows of cells before parsing, with its world and airline. Kept 14 days: the 10:20 UTC clean-up (private.job_cleanup, #13 pull request 7) deletes older pages. Written by capture_ingest(). Read by private.capture_page(), completeness (private.capture_day_complete) and the planner''s Capture board.';
comment on table public.game_statement is 'Bank-statement lines from the capture, as the game lists them. Each line is folded into a flight (flight_id) in game_flights or into game_payments. Kept 14 days for checking once the statement clean-up is switched on (settings.statement_cleanup_enabled; the 10:20 UTC job deletes older lines only once every one is in game_flights or game_payments). Written by the capture (private.capture_page).';

comment on function public.capture_ingest(text, text, text, text, jsonb) is 'Entry point for the in-game capture. Checks the capture key, which belongs to one world; finds the airline by the game''s ID or, from older userscripts, by name, and refuses one outside the key''s world; keeps the raw page (the 10:20 UTC clean-up deletes it after 14 days) and parses it (private.capture_store, private.capture_page): bank statement into game_flights and game_payments, loads into game_flights. Answers with the capture day and whether it is complete; the page that completes the world''s capture for the day also takes the daily snapshot (airline_days, route_days) and answers with it.';
comment on function private.backup_runs_insert() is 'Instead-of-insert trigger on the backup_runs view (design §3.12): turns the backup job''s row into a job_runs row (job backup; ok or failed; its kind, counts, R2 key and commit in details) and answers with its id and time. Refuses a kind other than nightly, manual or test, or no ok, as the old table did.';
comment on function private.job_snapshot_fallback(timestamp with time zone) is 'The 10:00 UTC job (pg_cron equinox-snapshot-fallback; design §7): for each world with active airlines of ours, takes the snapshot of the capture day just ended if it has none (private.take_snapshot, source fallback; cash with no balance that capture day and none typed from the latest balance before it), and of any earlier day since the history began that has none. A day with a snapshot is left alone. One job_runs row per world (snapshot_fallback), failed with the error rather than raised. p_at: the run''s moment, default now (for the checks).';
comment on function private.job_cleanup(timestamp with time zone) is 'The 10:20 UTC job (pg_cron equinox-cleanup; design §7): per world, deletes raw pages (game_capture_raw) older than 14 days, and, while settings.statement_cleanup_enabled is true, statement lines older than 14 days, only once every one is in game_flights or game_payments (counted first; otherwise none goes and the run fails, saying how many aren''t). One job_runs row per world (cleanup), failed with the error rather than raised. p_at: the run''s moment, default now (for the checks).';
comment on function private.archive_tables() is 'The tables the monthly archive may delete from (design §7), what decides a row''s month, and how many full calendar months each keeps: game_flights, game_events, game_scan_schedules and game_scan_airports one; change_log 12.';
comment on function private.archive_kept_from(text, date) is 'The first month a table still keeps on a day (design §7): everything before it may be archived. For one month kept, on any day of December it is November, so October may go.';
comment on function private.archive_check_args(date, text) is 'Refuses a table the archive may not touch, or a month not given as its first day. Used by every archive function.';
comment on function private.archive_where(date, text, text) is 'A table''s month as a condition on the table under an alias: one rule for the manifest, the export and the delete. game_flights by dep_at in UTC (by the game''s date where dep_at isn''t known, as the daily history counts it), game_events by event_date, the scan tables by their scan''s time, change_log by changed_at.';
comment on function private.archive_order(text, text) is 'A table''s primary key as an order for the archive, text columns in byte order (collate "C"), so the order and the checksum are the same on any database.';
comment on function private.archive_select(date, text) is 'The query the archive step (equinox-backups) exports a table''s month with, in the same transaction as the manifest: every column, in primary-key order. postgres only.';
comment on function private.archive_checksum(date, text) is 'A table''s month: its row count and the md5 of every row as Postgres prints it (timezone UTC, ISO dates), joined by newlines, in primary-key order.';
comment on function private.archive_manifest(date, text) is 'The manifest the archive step stores beside a table''s month (design §7): row count, checksum (private.archive_checksum), the table''s layout (columns and types) and the latest migration version, whether the month is due, and the export query. postgres only.';
comment on function private.archive_due(date) is 'What the monthly archive has to do (design §7): each table''s months older than its kept window that still have rows, with their row counts, oldest first. Called by the archive step in equinox-backups every night (it runs on the first night on or after the 1st, and again each night until nothing is due). p_as_of: the day, default today in UTC (for the checks). postgres only.';
comment on function private.archive_delete(date, text, bigint, text) is 'The guarded delete (design §7), the only way the archive removes rows: refuses a table not listed, a month inside the kept window, a count or checksum that no longer matches, and for game_flights a month whose flights aren''t all in route_days or that statement lines still point at, naming every reason in one refusal. Otherwise deletes exactly those rows (checked again as they go), records the run in job_runs (job archive, for_month) and answers with what it deleted and the row''s id. Locks the table against writes while it works. postgres only.';
comment on function private.schedule_jobs() is 'Schedules the two database jobs with pg_cron, by name, so it can run again safely: equinox-snapshot-fallback at 10:00 UTC (private.job_snapshot_fallback) and equinox-cleanup at 10:20 UTC (private.job_cleanup). Run by migration 20261011150000_jobs, and again after a full restore (the backup copies no schedules). Answers with the jobs as the scheduler has them.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

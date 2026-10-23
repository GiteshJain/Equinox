-- The monthly archive's database side (#13 build, pull request 7; design §7). Run by database/rehearse.sh on the copy of
-- last night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an
-- error that says which (tables, months and counts, never rows).
--   1. What's due: each listed table's months before its kept window (one full calendar month; 12 for change_log), with
--      their row counts; nothing inside the window. Hand-made rows in an old month of each of the six tables (three
--      months back; change_log fourteen) are listed exactly; since 23 Oct scan_rival_connections (the rivals'
--      connections, spec docs/specs/2026-10-23-rival-connections.md §2) goes with the scan schedules; scan_pair_airlines
--      (each week's rivals by pair, kept for good, spec docs/specs/2026-10-23-rival-pairs-history.md §4) is left alone: never
--      listed or due, and the hand-made scan's kept rows stay through the delete.
--   2. The manifest: the row count, the checksum (worked out here independently: md5 of every row as Postgres prints it,
--      in UTC, joined by newlines, in primary-key order), the table's layout and the latest migration version; the
--      export query gives exactly those rows.
--   3. private.archive_delete() refuses, deleting nothing: a table not listed, a month not given as its first day, a month
--      inside the kept window (this month and last; change_log's last 12), a wrong count, a wrong checksum, and for
--      game_flights a month whose flights aren't all in route_days as game_flights has them, or that statement lines
--      still point at; every reason that applies is named in one refusal.
--   4. When everything matches it deletes exactly the month's rows of each table, nothing else, and writes one job_runs
--      row (archive, the month); asked again, it refuses (no rows left to match).

create temporary table t_arch (table_name text primary key, month date, rows bigint, manifest jsonb) on commit drop;
create temporary table t_counts (table_name text primary key, n bigint) on commit drop;

-- ---------------------------------------------------------------- 1. what's due, and hand-made old rows
do $test$
declare
  w bigint := (select id from public.worlds where is_default); a1 record; a2 record; v_today date := (now() at time zone 'UTC')::date;
  m date; mc date; v_scan bigint; d date; bad text; n bigint; f1 bigint;
begin
  assert (select string_agg(table_name || ':' || keep_months, ', ' order by table_name) from private.archive_tables())
         = 'change_log:12, game_events:1, game_flights:1, game_scan_airports:1, game_scan_schedules:1, scan_rival_connections:1',
    'the archive''s tables aren''t design §7''s';
  -- left alone (since 23 Oct): the week's rivals by pair are kept for good
  assert not exists (select 1 from private.archive_tables() t where t.table_name = 'scan_pair_airlines')
     and not exists (select 1 from private.archive_due() x where x.table_name = 'scan_pair_airlines'),
    'the archive lists scan_pair_airlines, which is kept for good';
  -- the kept window: one full calendar month (12 for change_log)
  assert private.archive_kept_from('game_flights', date '2026-12-01') = date '2026-11-01'
     and private.archive_kept_from('game_flights', date '2026-11-30') = date '2026-10-01'
     and private.archive_kept_from('change_log', date '2027-11-01') = date '2026-11-01', 'the kept window isn''t design §7''s';
  -- on the copy as it is: nothing inside the window is due
  select string_agg(x.table_name || ' ' || x.month, ', ') into bad from private.archive_due() x
   where x.month >= private.archive_kept_from(x.table_name, v_today);
  assert bad is null, 'due inside the kept window: ' || bad;
  select count(*) into n from private.archive_due();

  select al.id, al.planner_name into a1 from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
   where al.world_id = w and al.active and g.kind = 'ours' order by al.id limit 1;
  select al.id, al.planner_name into a2 from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
   where al.world_id = w and al.active and g.kind = 'ours' and al.id <> a1.id order by al.id limit 1;
  assert a1.id is not null and a2.id is not null, 'the copy needs two active airlines of ours';
  m := (date_trunc('month', v_today) - interval '3 months')::date;     -- e.g. July, on any day of October
  mc := (date_trunc('month', v_today) - interval '14 months')::date;   -- change_log keeps 12 full months
  insert into t_counts select 'game_flights', count(*) from public.game_flights;
  insert into t_counts select 'game_events', count(*) from public.game_events;
  insert into t_counts select 'game_scan_schedules', count(*) from public.game_scan_schedules;
  insert into t_counts select 'game_scan_airports', count(*) from public.game_scan_airports;
  insert into t_counts select 'scan_rival_connections', count(*) from public.scan_rival_connections;
  insert into t_counts select 'change_log', count(*) from public.change_log;
  insert into t_counts select 'scan_pair_airlines', count(*) from public.scan_pair_airlines;

  -- game_events: three payments in the month
  insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, debit, captured_at, due_at)
  select w, a1.id, a1.planner_name, m + g, '0' || g || ':00', 'jobs-test lease ' || g, 1000 * g, m + g, (m + g)::timestamp at time zone 'UTC'
    from generate_series(2, 4) g;
  -- game_flights: three flights' money (the 1st at 00:30 UTC on the month's first day, the last on its last day at
  -- 23:30), and a loads row with no departure time known, counted by the game's date; route_days as the history has them
  d := m;
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, dep_at,
                                   pax_income, income_total, cost_total)
  values (w, a1.id, d + time '00:30', 1, 1, 'ZZA', 'ZZB', (d + time '00:30') at time zone 'UTC', 100, 100, 40),
         (w, a1.id, d + time '05:00', 1, 1, 'ZZA', 'ZZB', (d + time '05:00') at time zone 'UTC', 120, 120, 40),
         (w, a2.id, (m + interval '1 month - 1 day')::date + time '23:30', 1, 1, 'ZZB', 'ZZA',
          ((m + interval '1 month - 1 day')::date + time '23:30') at time zone 'UTC', 90, 90, 30);
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, origin_code, dest_code, dep_local, arr_local, eco_pax, eco_seats)
  values (w, a2.id, m + 9, 9999, 'ZZB', 'ZZC', '07:30', '09:00', 10, 20);
  insert into public.route_days (world_id, airline_id, origin_code, dest_code, day, flights, passengers, seats, revenue, costs, profit)
  values (w, a1.id, 'ZZA', 'ZZB', d, 2, 0, null, 220, 80, 140),
         (w, a2.id, 'ZZB', 'ZZA', (m + interval '1 month - 1 day')::date, 1, 0, null, 90, 30, 60),
         (w, a2.id, 'ZZB', 'ZZC', m + 9, 1, 10, 20, 0, 0, 0);
  -- a flight just before and just after the month, which must stay
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, origin_code, dest_code, dep_at,
                                   pax_income, income_total, cost_total)
  values (w, a1.id, ((m - 1) + time '23:59') at time zone 'UTC', 2, 1, 'ZZA', 'ZZB', ((m - 1) + time '23:59') at time zone 'UTC', 1, 1, 1),
         (w, a1.id, ((m + interval '1 month')::date + time '00:00') at time zone 'UTC', 2, 1, 'ZZA', 'ZZB',
          ((m + interval '1 month')::date + time '00:00') at time zone 'UTC', 1, 1, 1);
  -- a world scan taken in the month: two airlines' schedules, two airports
  insert into public.game_scans (world_id, taken_at, week, status, note) values (w, (m + 4)::timestamp at time zone 'UTC', 'jobs-test', 'done', 'jobs-test')
  returning id into v_scan;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights)
  values (v_scan, w, a1.id, '[["ZZ", "1", "ZZA", "ZZB", "1234567", "07:00", "08:00", "A320", null]]'), (v_scan, w, a2.id, '[]');
  insert into public.game_scan_airports (scan_id, world_id, airport_code, game_airport_id, info, stations, news, position)
  values (v_scan, w, 'ZZA', 1, '{"name": "jobs-test"}', '[]', '[]', 1), (v_scan, w, 'ZZB', 2, '{}', '[]', '[]', 2);
  -- its rivals' connections (two rows; a1 stands in for the rival: the table takes any airline of the world)
  insert into public.scan_rival_connections (scan_id, world_id, airline_id, origin, dest, via, weekly_departures, best_gap_min)
  values (v_scan, w, a1.id, 'ZZA', 'ZZB', 'ZZC', 7, 120), (v_scan, w, a1.id, 'ZZB', 'ZZA', 'ZZC', 3, 95);
  -- its pairs kept for good (scan_pair_airlines, left alone by the archive): one row, which must stay
  insert into public.scan_pair_airlines (scan_id, world_id, airline_id, a, b, weekly_a_to_b, weekly_b_to_a, passenger)
  values (v_scan, w, a1.id, 'ZZA', 'ZZB', 7, 0, true);
  -- the change log: three rows fourteen months back
  insert into public.change_log (changed_at, world_id, table_name, row_key, op, old_values, new_values, actor, actor_detail)
  select (mc + g)::timestamp at time zone 'UTC', w, 'todos', jsonb_build_object('id', -g), 'update', '{"title": "a"}', '{"title": "b"}', 'claude', 'jobs-test'
    from generate_series(1, 3) g;

  insert into t_arch values ('game_events', m, 3, null), ('game_flights', m, 4, null), ('game_scan_schedules', m, 2, null),
                            ('game_scan_airports', m, 2, null), ('scan_rival_connections', m, 2, null), ('change_log', mc, 3, null);
  select string_agg(t.table_name, ', ') into bad from t_arch t
   where not exists (select 1 from private.archive_due() x where x.table_name = t.table_name and x.month = t.month and x.rows = t.rows);
  assert bad is null, 'the hand-made months aren''t due as made: ' || bad || ' (' || (select string_agg(x.table_name || ' ' || x.month || ' ' || x.rows, ', ') from private.archive_due() x) || ')';
  -- as they will be on the archive's first night for October: on 1 December, October is due; on 30 November it isn't
  assert exists (select 1 from private.archive_due((m + interval '2 months')::date) x where x.table_name = 'game_events' and x.month = m)
     and not exists (select 1 from private.archive_due((m + interval '2 months - 1 day')::date) x where x.table_name = 'game_events' and x.month = m),
    'a month isn''t due exactly from the 1st of the month after next';
  raise notice 'due: nothing inside the kept window on the copy (% table-month(s) due before the hand-made rows); the hand-made months listed exactly: % (detail, 3 months back) and % (change_log, 14 months back)',
    n, to_char(m, 'YYYY-MM'), to_char(mc, 'YYYY-MM');
end
$test$;

-- ---------------------------------------------------------------- 2. the manifest and the export query
set local timezone = 'UTC';
set local datestyle = 'ISO, YMD';
do $test$
declare r record; mf jsonb; v_sum text; n bigint; v_q text; v_layout jsonb; v_version text;
begin
  for r in select * from t_arch loop
    mf := private.archive_manifest(r.month, r.table_name);
    -- the checksum, worked out independently here: md5 of each row as text, newline-joined, in primary-key order
    execute format('select count(*), md5(coalesce(string_agg(t::text, E''\n'' order by %s), '''')) from (%s) t',
                   (select string_agg(case when format_type(a.atttypid, a.atttypmod) = 'text' then quote_ident(a.attname) || ' collate "C"'
                                           else quote_ident(a.attname) end, ', ' order by k.n)
                      from pg_index i cross join lateral unnest(i.indkey) with ordinality k(attnum, n)
                      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
                     where i.indrelid = ('public.' || r.table_name)::regclass and i.indisprimary),
                   private.archive_select(r.month, r.table_name))
       into n, v_sum;
    assert (mf ->> 'rows')::bigint = r.rows and n = r.rows, format('%s %s: %s rows in the manifest, %s exported, %s made', r.table_name, r.month, mf ->> 'rows', n, r.rows);
    assert mf ->> 'checksum' = v_sum, format('%s %s: the manifest''s checksum isn''t the rows'' in primary-key order', r.table_name, r.month);
    select jsonb_agg(jsonb_build_object('column', a.attname, 'type', format_type(a.atttypid, a.atttypmod), 'not_null', a.attnotnull,
                                        'generated', a.attgenerated <> '', 'identity', a.attidentity <> '') order by a.attnum)
      into v_layout from pg_attribute a where a.attrelid = ('public.' || r.table_name)::regclass and a.attnum > 0 and not a.attisdropped;
    assert mf -> 'layout' = v_layout, format('%s: the manifest''s layout isn''t the table''s', r.table_name);
    if to_regclass('supabase_migrations.schema_migrations') is not null then
      execute 'select max(version) from supabase_migrations.schema_migrations' into v_version;
      assert mf ->> 'migration_version' = v_version, format('%s: the manifest''s migration version isn''t the latest', r.table_name);
    end if;
    assert (mf ->> 'due')::boolean and mf ->> 'month' = to_char(r.month, 'YYYY-MM') and mf ->> 'table' = r.table_name,
      format('%s %s: the manifest says due %s, month %s', r.table_name, r.month, mf ->> 'due', mf ->> 'month');
    update t_arch set manifest = mf where table_name = r.table_name;
  end loop;
  raise notice 'manifests: count, checksum (md5 of the rows in primary-key order, checked independently), layout and migration version right for all % hand-made table-months; each export query gives exactly the counted rows',
    (select count(*) from t_arch);
end
$test$;

-- ---------------------------------------------------------------- 3. what archive_delete refuses
create temporary table t_refused (what text, msg text) on commit drop;
create or replace function pg_temp.refused(p_what text, p_month date, p_table text, p_count bigint, p_sum text, p_expect text)
 returns void language plpgsql as $f$
begin
  begin
    perform private.archive_delete(p_month, p_table, p_count, p_sum);
  exception when others then
    insert into t_refused values (p_what, sqlerrm);
    if sqlerrm not like p_expect then
      raise exception 'archive_delete refused % with "%", expected "%"', p_what, sqlerrm, p_expect;
    end if;
    return;
  end;
  raise exception 'archive_delete didn''t refuse %', p_what;
end
$f$;
do $test$
declare
  e record; f record; c record; v_cur date := date_trunc('month', (now() at time zone 'UTC')::date)::date; mf jsonb;
  n_before bigint; v_rd public.route_days; v_line text;
begin
  select * into e from t_arch where table_name = 'game_events';
  select * into f from t_arch where table_name = 'game_flights';
  select * into c from t_arch where table_name = 'change_log';
  select count(*) into n_before from public.game_events;
  perform pg_temp.refused('a table not listed (game_payments)', e.month, 'game_payments', 0, 'x', '%game_payments is not a table the archive may touch%');
  perform pg_temp.refused('a table not listed (airline_days)', e.month, 'airline_days', 0, 'x', '%airline_days is not a table%');
  perform pg_temp.refused('a table not listed (job_runs)', e.month, 'job_runs', 0, 'x', '%job_runs is not a table%');
  perform pg_temp.refused('no table', e.month, null, 0, 'x', '%null is not a table%');
  perform pg_temp.refused('a month not given as its first day', e.month + 1, 'game_events', 0, 'x', '%must be given as its first day%');
  -- inside the kept window, with the right count and checksum: this month and last (October on any day of November)
  mf := private.archive_manifest(v_cur, 'game_events');
  perform pg_temp.refused('this month', v_cur, 'game_events', (mf ->> 'rows')::bigint, mf ->> 'checksum', '%inside the kept window%');
  mf := private.archive_manifest((v_cur - interval '1 month')::date, 'game_flights');
  perform pg_temp.refused('last month', (v_cur - interval '1 month')::date, 'game_flights', (mf ->> 'rows')::bigint, mf ->> 'checksum', '%inside the kept window%');
  mf := private.archive_manifest((v_cur - interval '11 months')::date, 'change_log');
  perform pg_temp.refused('change_log 11 months back', (v_cur - interval '11 months')::date, 'change_log', (mf ->> 'rows')::bigint, mf ->> 'checksum', '%inside the kept window (change_log keeps the last 12 full months%');
  -- a wrong count, a wrong checksum
  perform pg_temp.refused('a wrong count', e.month, 'game_events', e.rows + 1, e.manifest ->> 'checksum', '%the count doesn''t match (4 expected, 3 there now)%');
  perform pg_temp.refused('a wrong checksum', e.month, 'game_events', e.rows, md5('not these rows'), '%the checksum doesn''t match%');
  -- rows changed since the manifest: one more event in the month
  insert into public.game_events (world_id, airline_id, airline, event_date, event_time, descr, debit)
  select world_id, airline_id, airline, event_date, '23:59', 'jobs-test late', 1 from public.game_events where descr = 'jobs-test lease 2';
  perform pg_temp.refused('rows changed since the manifest', e.month, 'game_events', e.rows, e.manifest ->> 'checksum', '%count doesn''t match%checksum doesn''t match%');
  delete from public.game_events where descr = 'jobs-test late';
  -- every reason at once
  perform pg_temp.refused('this month with a wrong count', v_cur, 'game_events', -1, 'x', '%inside the kept window%count doesn''t match%checksum doesn''t match%');
  -- game_flights: a route day missing, then one short, then a statement line pointing at a flight
  select * into v_rd from public.route_days where origin_code = 'ZZB' and dest_code = 'ZZC';
  delete from public.route_days where origin_code = 'ZZB' and dest_code = 'ZZC';
  perform pg_temp.refused('a route day missing', f.month, 'game_flights', f.rows, f.manifest ->> 'checksum', '%1 route day(s) of the month aren''t in route_days%');
  insert into public.route_days select (v_rd).*;
  update public.route_days set flights = 1 where origin_code = 'ZZA' and dest_code = 'ZZB' and day = f.month;
  perform pg_temp.refused('a route day short', f.month, 'game_flights', f.rows, f.manifest ->> 'checksum', '%1 route day(s) of the month aren''t in route_days%');
  update public.route_days set flights = 2 where origin_code = 'ZZA' and dest_code = 'ZZB' and day = f.month;
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk, flight_id)
  select x.world_id, x.airline_id, a.planner_name, x.posted_at, 'Passenger transport income (ZZA-ZZB) jobs-test', 100, 'C', 1, 1, x.id
    from public.game_flights x join public.airlines a on a.id = x.airline_id
   where x.origin_code = 'ZZA' and x.statement_blk = 1 and x.dep_at < (f.month + interval '1 day') limit 1;
  perform pg_temp.refused('a statement line pointing at a flight', f.month, 'game_flights', f.rows, f.manifest ->> 'checksum', '%1 statement line(s) still point at these flights%');
  delete from public.game_statement where descr = 'Passenger transport income (ZZA-ZZB) jobs-test';
  assert (select count(*) from public.game_events) = n_before, 'a refusal deleted rows';
  assert not exists (select 1 from public.job_runs where job = 'archive' and note like '%jobs-test%') , 'a refusal wrote a job_runs row';
  raise notice 'archive_delete refused, deleting nothing: % cases (tables not listed, a month not given as its first day, this month and last, change_log''s last 12, a wrong count, a wrong checksum, rows changed since the manifest, every reason at once, game_flights with a route day missing or short, a statement line still pointing)',
    (select count(*) from t_refused);
end
$test$;

-- ---------------------------------------------------------------- 4. the delete when everything matches
do $test$
declare r record; v_res jsonb; n bigint; j record; v_runs bigint;
begin
  for r in select * from t_arch order by table_name loop
    select count(*) into v_runs from public.job_runs where job = 'archive';
    v_res := private.archive_delete(r.month, r.table_name, (r.manifest ->> 'rows')::bigint, r.manifest ->> 'checksum');
    assert (v_res ->> 'deleted')::bigint = r.rows, format('%s %s: deleted %s, expected %s', r.table_name, r.month, v_res ->> 'deleted', r.rows);
    execute format('select count(*) from public.%I', r.table_name) into n;
    assert n = (select x.n from t_counts x where x.table_name = r.table_name) + (case when r.table_name = 'game_flights' then 2 else 0 end),
      format('%s: %s rows after the delete, %s before the hand-made ones', r.table_name, n, (select x.n from t_counts x where x.table_name = r.table_name));
    assert (select (private.archive_checksum(r.month, r.table_name)).rows) = 0, format('%s %s: rows of the month are left', r.table_name, r.month);
    assert (select count(*) from public.job_runs where job = 'archive') = v_runs + 1, format('%s: not one job_runs row', r.table_name);
    select * into j from public.job_runs where id = (v_res ->> 'job_run_id')::bigint;
    assert j.job = 'archive' and j.status = 'ok' and j.for_month = r.month and j.details ->> 'table' = r.table_name
       and (j.details ->> 'rows')::bigint = r.rows and j.details ->> 'checksum' = r.manifest ->> 'checksum',
      format('%s: the job_runs row: %s %s %s', r.table_name, j.status, j.for_month, j.details);
    perform pg_temp.refused(r.table_name || ' a second time', r.month, r.table_name, (r.manifest ->> 'rows')::bigint, r.manifest ->> 'checksum',
                            format('%%the count doesn''t match (%s expected, 0 there now)%%', r.rows));
  end loop;
  -- the week's rivals by pair stayed: the hand-made scan's row and every other
  assert (select count(*) from public.scan_pair_airlines) = (select x.n from t_counts x where x.table_name = 'scan_pair_airlines') + 1,
    'the archive''s deletes touched scan_pair_airlines, which is kept for good';
  begin
    perform private.archive_delete((select month from t_arch where table_name = 'game_scan_schedules'), 'scan_pair_airlines', 1, 'x');
    raise exception 'archive_delete didn''t refuse scan_pair_airlines';
  exception when others then
    if sqlerrm not like '%scan_pair_airlines is not a table the archive may touch%' then raise; end if;
  end;
  -- the flights just before and after the month stayed
  assert (select count(*) from public.game_flights where origin_code = 'ZZA' and statement_blk = 2) = 2, 'a flight outside the month went';
  raise notice 'archive_delete with the manifest''s count and checksum: exactly the month''s rows of each of the 6 tables went (the flights a minute either side stayed; scan_pair_airlines left alone and refused), one job_runs row each (archive, the month); asked again, refused';
end
$test$;

do $$ begin raise notice 'the archive''s database side: all checks passed'; end $$;

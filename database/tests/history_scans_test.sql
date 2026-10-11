-- The world scans, renamed and split (#13 build, pull request 6; design §3.9, §11 choice 2). Run by database/rehearse.sh
-- on the copy of last night's backup, after the new migrations, inside a transaction that is rolled back. Compares
-- against the outputs database/tests/before/history_before.sql saved before the migrations ran (rehearsal_before). A
-- failed check stops with an error that says which (scan ids and counts, never rows).
--   1. What the scripts get is what they got: export_for_report()'s list of scans, and every scan's airlines and
--      airports, exactly (the same JSON, in the same order); export_planner_data() exactly; export_repo_bootstrap()'s
--      scripts and migrations exactly, and every function and view it listed still there (its other parts list the
--      database's own code, which this pull request changes).
--   2. The stored scans in the new tables: each with its world; every airline a scan saw (scanned, or stationed at a
--      scanned airport) is an airlines row by game ID, and each scan's airline rows point at it; each has its schedule,
--      whose weekdays add up to its departures a week; every scan has its airport summaries, equal to a count made here
--      from its schedules. Their size is measured: what a scan adds for good, and a year of weekly scans.
--   3. ingest_snapshot(), signed out with the ingest secret as the scanner calls it: a hand-made small scan (start, two
--      airlines, one airport, finish) lands in game_scans, game_scan_airlines, game_scan_schedules and game_scan_airports
--      and builds its airport summaries; the airlines it saw are added (logged as script), ours left as they are; the
--      weekly report's market summaries (kind markets) are stored, and sending them again replaces them;
--      export_for_report() gives the scan back as it was sent. A wrong secret and an unknown kind are refused.

-- ---------------------------------------------------------------- 1. what the scripts get
do $test$
declare s text := 'scans-test-' || gen_random_uuid(); o record; a jsonb; b jsonb; n int := 0; v_sorted int := 0; bad text;
begin
  assert to_regclass('rehearsal_before.scan_outputs') is not null,
    'the outputs from before the changes weren''t saved (database/tests/before/history_before.sql)';
  insert into public.ingest_secret (secret) values (s);
  assert public.export_for_report(s, 'snapshots') = (select value from rehearsal_before.scan_outputs where name = 'snapshots'),
    'export_for_report(''snapshots'') differs from before';
  for o in select x.name, x.value from rehearsal_before.scan_outputs x where x.name ~ '^(airlines|airports) \d+$' order by x.name loop
    a := public.export_for_report(s, split_part(o.name, ' ', 1), split_part(o.name, ' ', 2));
    if a is distinct from o.value then
      if (select array_agg(e order by e::text) from jsonb_array_elements(a) e) = (select array_agg(e order by e::text) from jsonb_array_elements(o.value) e) then
        raise exception 'export_for_report(''%'') has the same entries as before, in another order (before: %)', o.name,
          case when (select bool_and(x.id >= coalesce(x.prev, x.id)) from (select (e ->> 'id')::int as id, lag((e ->> 'id')::int) over (order by i) as prev
                                                                              from jsonb_array_elements(o.value) with ordinality y(e, i)) x)
               then 'by game ID' else 'not by game ID' end;
      end if;
      raise exception 'export_for_report(''%'') differs from before (% entries before, % now)', o.name, jsonb_array_length(o.value), jsonb_array_length(a);
    end if;
    n := n + 1;
  end loop;
  assert public.export_planner_data(s) = (select value from rehearsal_before.scan_outputs where name = 'export_planner_data'),
    'export_planner_data() differs from before';
  a := public.export_repo_bootstrap(s);
  b := (select value from rehearsal_before.scan_outputs where name = 'export_repo_bootstrap');
  assert a -> 'scripts' = b -> 'scripts', 'export_repo_bootstrap()''s scripts differ from before';
  assert a -> 'migrations' = b -> 'migrations', 'export_repo_bootstrap()''s migrations differ from before';
  select string_agg(x.k, ', ') into bad from (
    select 'function ' || (e ->> 'name') || '(' || (e ->> 'args') || ')' as k from jsonb_array_elements(b -> 'functions') e
    except select 'function ' || (e ->> 'name') || '(' || (e ->> 'args') || ')' from jsonb_array_elements(a -> 'functions') e
    union all
    (select 'view ' || (e ->> 'name') from jsonb_array_elements(b -> 'views') e
     except select 'view ' || (e ->> 'name') from jsonb_array_elements(a -> 'views') e)) x;
  assert bad is null, 'export_repo_bootstrap() no longer lists: ' || bad;
  delete from public.ingest_secret where secret = s;
  raise notice 'export_for_report(): the scans and % scan lists (airlines and airports) exactly as before; export_planner_data() the same; export_repo_bootstrap()''s scripts and migrations the same, and everything it listed still there',
    n;
end
$test$;

-- ---------------------------------------------------------------- 2. the stored scans in the new tables
do $test$
declare bad text; n_scans int; n_rows bigint; v_bytes numeric; v_last bigint; v_last_rows bigint; v_last_bytes numeric;
begin
  select count(*) into n_scans from public.game_scans;
  assert not exists (select 1 from public.game_scans s left join public.worlds w on w.id = s.world_id where w.id is null),
    'a scan has no world';
  -- every airline a scan saw is an airlines row by game ID, in the scan's world
  select string_agg(distinct x.game_id::text, ', ') into bad from (
    select a.world_id, a.enterprise_id as game_id from public.game_scan_airlines a
    union
    select p.world_id, (st ->> 'enterprise_id')::int from public.game_scan_airports p
      cross join lateral jsonb_array_elements(case when jsonb_typeof(p.stations) = 'array' then p.stations else '[]'::jsonb end) st
     where (st ->> 'enterprise_id') ~ '^\d{1,9}$') x
   where not exists (select 1 from public.airlines al where al.world_id = x.world_id and al.game_id = x.game_id);
  assert bad is null, 'airlines a scan saw with no airlines row (game IDs): ' || left(bad, 300);
  select count(*)::text into bad from public.game_scan_airlines a join public.airlines al on al.id = a.airline_id
   where al.game_id <> a.enterprise_id or al.world_id <> a.world_id;
  assert bad = '0', bad || ' scanned airlines point at the wrong airlines row';
  -- each scanned airline has its schedule, and its weekdays add up to the departures a week the scanner counted
  select string_agg(format('%s/%s', a.scan_id, a.enterprise_id), ', ') into bad
    from public.game_scan_airlines a
    left join public.game_scan_schedules sc on sc.scan_id = a.scan_id and sc.airline_id = a.airline_id
   where sc.scan_id is null
      or a.n_flights is distinct from jsonb_array_length(sc.flights)
      or a.n_weekly is distinct from (select coalesce(sum(length(f ->> 4)), 0)::int from jsonb_array_elements(sc.flights) f);
  assert bad is null, 'scanned airlines whose schedule is missing or doesn''t add up (scan/game ID): ' || left(bad, 300);
  -- every scan has its airport summaries, equal to a count made here from its schedules
  select string_agg(distinct coalesce(x.scan_id, y.scan_id)::text, ', ') into bad
    from (select sc.scan_id, sc.airline_id, f ->> 2 as airport_code,
                 sum(length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')))::int as weekly_departures,
                 count(distinct nullif(f ->> 3, ''))::int as destinations
            from public.game_scan_schedules sc cross join lateral jsonb_array_elements(sc.flights) f
           where coalesce(f ->> 2, '') <> '' and regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g') <> ''
           group by 1, 2, 3) x
    full join (select * from public.scan_airline_airports z
                where exists (select 1 from public.game_scan_schedules sc where sc.scan_id = z.scan_id)) y using (scan_id, airline_id, airport_code)
   where (x.weekly_departures, x.destinations) is distinct from (y.weekly_departures, y.destinations);
  assert bad is null, 'airport summaries that don''t match their scan''s schedules (scans): ' || bad;
  select string_agg(s.id::text, ', ') into bad from public.game_scans s
   where exists (select 1 from public.game_scan_schedules sc where sc.scan_id = s.id)
     and not exists (select 1 from public.scan_airline_airports y where y.scan_id = s.id);
  assert bad is null, 'scans with no airport summaries: ' || bad;
  -- what a scan keeps for good: its totals and summaries (the schedules and airport pages are archived after a month)
  select max(id) into v_last from public.game_scans where exists (select 1 from public.scan_airline_airports y where y.scan_id = game_scans.id);
  select count(*), coalesce(sum(pg_column_size(y.*)), 0) into v_last_rows, v_last_bytes from public.scan_airline_airports y where y.scan_id = v_last;
  select count(*), coalesce(sum(pg_column_size(y.*)), 0) into n_rows, v_bytes from public.scan_airline_airports y;
  raise notice 'stored scans: %, each with its world; every airline they saw has an airlines row; every scanned airline has its schedule, adding up; the airport summaries match (% rows). Scan %: % summary rows, about % KB of data (with its indexes perhaps twice that), so about % MB a year with weekly scans, plus the market summaries',
    n_scans, n_rows, v_last, v_last_rows, round(v_last_bytes / 1024), round(v_last_bytes * 2 * 52 / 1048576.0, 1);
end
$test$;

-- ---------------------------------------------------------------- 3. ingest_snapshot(), signed out, as the scanner calls it
create temporary table t_scan (k text primary key, v text) on commit drop;
insert into t_scan values ('secret', 'scans-test-' || gen_random_uuid()),
                          ('log_from', coalesce((select max(id) from public.change_log), 0)::text),
                          ('kf_name', coalesce((select game_name from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default where a.game_id = 113), '(none)'));
insert into public.ingest_secret (secret) select v from t_scan where k = 'secret';
grant select, insert, update on t_scan to anon;
set local role anon;
do $test$
declare s text := (select v from t_scan where k = 'secret'); r jsonb; v_id bigint; refused boolean;
begin
  r := public.ingest_snapshot(s, 'start', '{"week": "W99", "note": "history test"}');
  v_id := (r ->> 'snapshot_id')::bigint;
  assert v_id is not null and r = jsonb_build_object('snapshot_id', v_id), 'start didn''t answer as before: ' || r::text;
  insert into t_scan values ('scan', v_id::text);
  r := public.ingest_snapshot(s, 'airline', jsonb_build_object('snapshot_id', v_id, 'enterprise_id', 999555, 'name', 'History Test Rival',
         'flights', '[["HT", "100", "JFK", "LHR", "1357", "08:00", "20:00", "32N", ""], ["HT", "101", "LHR", "JFK", "1357", "22:00", "01:00", "32N", ""], ["HT", "102", "JFK", "ORD", "1234567", "09:00", "11:00", "32N", ""]]'::jsonb,
         'n_flights', 3, 'n_weekly', 15, 'n_airports', 3));
  assert r = '{"ok": true}'::jsonb, 'airline didn''t answer as before: ' || r::text;
  r := public.ingest_snapshot(s, 'airline', jsonb_build_object('snapshot_id', v_id, 'enterprise_id', 113, 'name', 'History Test Name For Kingfisher',
         'flights', '[["KF", "1001", "DEL", "JFK", "135", "01:30", "04:19", "32N", ""]]'::jsonb, 'n_flights', 1, 'n_weekly', 3, 'n_airports', 2));
  assert r = '{"ok": true}'::jsonb, 'airline (one of ours) didn''t answer as before: ' || r::text;
  r := public.ingest_snapshot(s, 'airport', jsonb_build_object('snapshot_id', v_id, 'code', 'JFK', 'airport_id', 4242, 'info', '{"size": "huge"}'::jsonb,
         'stations', '[{"enterprise_id": 999555, "name": "History Test Rival", "weekly": 11}, {"enterprise_id": 999556, "name": "History Test Station", "weekly": 4}]'::jsonb,
         'news', '[]'::jsonb));
  assert r = '{"ok": true}'::jsonb, 'airport didn''t answer as before: ' || r::text;
  r := public.ingest_snapshot(s, 'finish', jsonb_build_object('snapshot_id', v_id, 'note', 'history test, finished'));
  assert r = '{"ok": true}'::jsonb, 'finish didn''t answer as before: ' || r::text;
  r := public.ingest_snapshot(s, 'markets', jsonb_build_object('snapshot_id', v_id, 'markets', '[
         {"enterprise_id": 999555, "market": "Transatlantic", "weekly_departures": 8, "city_pairs": 1},
         {"enterprise_id": 999555, "market": "US domestic", "weekly_departures": 7, "city_pairs": 1},
         {"enterprise_id": 999557, "market": "Intra-Europe", "weekly_departures": 2, "city_pairs": 2}]'::jsonb));
  assert r = '{"ok": true, "rows": 3}'::jsonb, 'markets didn''t store 3 rows: ' || r::text;
  r := public.ingest_snapshot(s, 'markets', jsonb_build_object('snapshot_id', v_id, 'markets', '[
         {"enterprise_id": 999555, "market": "Transatlantic", "weekly_departures": 9, "city_pairs": 1},
         {"enterprise_id": 113, "market": "South Asia–North America", "weekly_departures": 3, "city_pairs": 1}]'::jsonb));
  assert r = '{"ok": true, "rows": 2}'::jsonb, 'markets sent again didn''t replace them with 2 rows: ' || r::text;
  begin
    perform public.ingest_snapshot(s || 'x', 'start', '{}'); refused := false;
  exception when others then refused := sqlerrm = 'not allowed';
  end;
  assert refused, 'a wrong secret wasn''t refused';
  begin
    perform public.ingest_snapshot(s, 'gossip', '{}'); refused := false;
  exception when others then refused := sqlerrm = 'unknown kind';
  end;
  assert refused, 'an unknown kind wasn''t refused';
end
$test$;
reset role;

do $test$
declare v_id bigint := (select v::bigint from t_scan where k = 'scan'); s text := (select v from t_scan where k = 'secret');
  w bigint := (select id from public.worlds where is_default); a jsonb; v_rival bigint; v_station bigint; v_eu bigint; kf bigint;
begin
  select id into kf from public.airlines where world_id = w and game_id = 113;
  select id into v_rival from public.airlines where world_id = w and game_id = 999555 and game_name = 'History Test Rival' and group_id is null;
  select id into v_station from public.airlines where world_id = w and game_id = 999556 and game_name = 'History Test Station';
  select id into v_eu from public.airlines where world_id = w and game_id = 999557;
  assert v_rival is not null and v_station is not null and v_eu is not null,
    'the airlines the scan saw (scanned, stationed at an airport, in a market) weren''t all added by game ID';
  assert coalesce((select game_name from public.airlines where id = kf), '(none)') = (select v from t_scan where k = 'kf_name'),
    'the scan changed one of our airlines'' names';
  assert (select count(*) from public.change_log l where l.id > (select v::bigint from t_scan where k = 'log_from')
            and l.table_name = 'airlines' and l.op = 'insert' and l.actor = 'script' and l.actor_detail = 'ingest_snapshot') = 3,
    'the added airlines weren''t logged as the script';
  assert exists (select 1 from public.game_scans where id = v_id and world_id = w and status = 'done' and week = 'W99' and note = 'history test, finished'),
    'the scan isn''t in game_scans, finished, with its world';
  assert (select count(*) from public.game_scan_airlines where scan_id = v_id) = 2
     and exists (select 1 from public.game_scan_airlines where scan_id = v_id and airline_id = v_rival and enterprise_id = 999555 and n_weekly = 15)
     and exists (select 1 from public.game_scan_airlines where scan_id = v_id and airline_id = kf and name = 'History Test Name For Kingfisher'),
    'the scanned airlines'' totals aren''t in game_scan_airlines';
  assert (select jsonb_array_length(flights) from public.game_scan_schedules where scan_id = v_id and airline_id = v_rival) = 3,
    'the rival''s schedule isn''t in game_scan_schedules';
  assert exists (select 1 from public.game_scan_airports where scan_id = v_id and airport_code = 'JFK' and game_airport_id = 4242 and world_id = w),
    'the airport page isn''t in game_scan_airports';
  -- the airport summaries, built at finish: the rival leaves JFK 4 + 7 times a week to 2 places, LHR 4 times to 1
  assert (select jsonb_object_agg(y.airport_code, jsonb_build_array(y.weekly_departures, y.destinations)) from public.scan_airline_airports y
           where y.scan_id = v_id and y.airline_id = v_rival) = '{"JFK": [11, 2], "LHR": [4, 1]}'::jsonb,
    'the rival''s airport summaries aren''t right';
  assert (select jsonb_object_agg(y.airport_code, jsonb_build_array(y.weekly_departures, y.destinations)) from public.scan_airline_airports y
           where y.scan_id = v_id and y.airline_id = kf) = '{"DEL": [3, 1]}'::jsonb,
    'our airline''s airport summary isn''t right';
  -- the market summaries: the second sending replaced the first
  assert (select jsonb_object_agg(al.game_id || ' ' || m.market, jsonb_build_array(m.weekly_departures, m.city_pairs))
            from public.scan_airline_markets m join public.airlines al on al.id = m.airline_id where m.scan_id = v_id)
         = '{"999555 Transatlantic": [9, 1], "113 South Asia–North America": [3, 1]}'::jsonb,
    'the market summaries sent again didn''t replace the first ones';
  -- and the report gets the scan back as it was sent: airlines by game ID, with their schedules
  insert into public.ingest_secret (secret) values (s) on conflict do nothing;
  a := public.export_for_report(s, 'airlines', v_id::text);
  assert jsonb_array_length(a) = 2 and (a -> 0 ->> 'id')::int = 113 and (a -> 1 ->> 'id')::int = 999555
     and a -> 1 -> 'flights' = (select flights from public.game_scan_schedules where scan_id = v_id and airline_id = v_rival)
     and a -> 1 ->> 'name' = 'History Test Rival' and (a -> 1 ->> 'n_weekly')::int = 15,
    'export_for_report(''airlines'') doesn''t give the scan back as sent';
  a := public.export_for_report(s, 'airports', v_id::text);
  assert jsonb_array_length(a) = 1 and a -> 0 ->> 'code' = 'JFK' and a -> 0 -> 'info' = '{"size": "huge"}'::jsonb
     and jsonb_array_length(a -> 0 -> 'stations') = 2, 'export_for_report(''airports'') doesn''t give the scan back as sent';
  assert exists (select 1 from jsonb_array_elements(public.export_for_report(s, 'snapshots')) e
                  where (e ->> 'id')::bigint = v_id and e ->> 'status' = 'done' and e ->> 'week' = 'W99'),
    'export_for_report(''snapshots'') doesn''t list the scan';
  raise notice 'ingest_snapshot(), signed out with the secret: a hand-made scan (2 airlines, 1 airport) stored in the new tables with its airport summaries; 3 airlines it saw added and logged as the script, ours left alone; market summaries stored and replaced; export_for_report() gives it back as sent; a wrong secret and an unknown kind refused';
end
$test$;

do $$ begin raise notice 'world scans: all checks passed'; end $$;

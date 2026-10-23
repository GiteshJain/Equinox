-- Each week's rivals by pair, kept for good (spec docs/specs/2026-10-23-rival-pairs-history.md §1–§5; migration
-- 20261023160000_rival_pairs_history.sql). Run by database/rehearse.sh on the copy of last night's backup, after the new
-- migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (codes, counts
-- and words of the hand-made world only). Everything is made in a world of its own, so nothing on the copy is touched or
-- counted; the copy's own numbers are printed at the end (counts and timings only).
--   1. scan_pair_airlines (RLS on, no rule, no access for anon or authenticated, every column described), the three new
--      internal functions (closed to everyone, empty search path, described); the archive leaves it alone: not in
--      private.archive_tables(), never in archive_due(), and the guarded delete refuses it.
--   2. A world of its own (our airline P1 flying YP1–YP2 since 1 Feb 2030) and four scans finished through
--      private.scan_ingest() as the capture finishes one: s1 Saturday 2 Mar, s2 Monday 4 Mar (the same week), s3 Saturday
--      9 Mar, s4 Sunday 10 Mar (the same week as s3). The finish writes s1's and s3's rows once: s2 and s4 write none, nor
--      s1 kept again by hand; the rows are each airline's departures each way on every pair (ours too, a pair none of ours
--      flies too, a freighter apart); the scan's note is as before.
--   3. The fill-back: with this world's rows taken away, private.scan_pairs_fill_back() keeps s1 and s3 again (one a week,
--      the first), and nothing for a week already kept or a scan not finished.
--   4. route_story(): as of 3 Mar, the same rivals and share from s1's schedules and from its kept rows; with week one's
--      schedules archived (s1, s2), s1's point still shows (weekly, the same figures), s2's is gone, s3 and s4 are read
--      from their schedules; weekly_points and daily_from say so, and the freighter never counts.
--   On the copy: the rows kept for each scan, and the first airline's busiest route's story timed.

create temporary table t_ph (k text primary key, v jsonb) on commit drop;
grant select, insert, update on t_ph to anon, authenticated;

-- a flight in a scan's schedule: [code, number, from, to, weekdays, departure, arrival, type, operator]
create function pg_temp.ph_fl(code text, no int, o text, d text, days text, ty text default '320') returns jsonb language sql immutable as $f$
  select jsonb_build_array(code, no::text, o, d, days, '08:00', '09:00', ty, '')
$f$;

-- ---------------------------------------------------------------- 1. the table, the functions, the archive leaves it alone
do $test$
declare g text; bad text; m date := (date_trunc('month', now() at time zone 'UTC') - interval '3 months')::date;
begin
  assert (select relrowsecurity from pg_class where oid = 'public.scan_pair_airlines'::regclass), 'scan_pair_airlines has no RLS';
  assert not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'scan_pair_airlines'),
    'scan_pair_airlines has an access rule: it''s read through functions only';
  select string_agg(r || ' ' || p, ', ') into bad from unnest(array['anon', 'authenticated']) r
   cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p
   where has_table_privilege(r, 'public.scan_pair_airlines', p);
  assert bad is null, 'scan_pair_airlines is open to: ' || bad;
  assert length(coalesce(obj_description('public.scan_pair_airlines'::regclass, 'pg_class'), '')) > 200, 'scan_pair_airlines has no description';
  assert (select array_agg(a.attname::text order by a.attnum) from pg_attribute a where a.attrelid = 'public.scan_pair_airlines'::regclass and a.attnum > 0 and not a.attisdropped)
       = array['scan_id', 'world_id', 'airline_id', 'a', 'b', 'weekly_a_to_b', 'weekly_b_to_a', 'passenger'],
    'scan_pair_airlines'' columns aren''t the spec''s';
  select string_agg(a.attname, ', ') into bad from pg_attribute a
   where a.attrelid = 'public.scan_pair_airlines'::regclass and a.attnum > 0 and not a.attisdropped and col_description(a.attrelid, a.attnum) is null;
  assert bad is null, 'scan_pair_airlines: columns without a description: ' || bad;
  foreach g in array array['private.scan_week(timestamptz)', 'private.scan_pairs_keep(bigint)', 'private.scan_pairs_fill_back()'] loop
    assert not has_function_privilege('anon', g, 'execute') and not has_function_privilege('authenticated', g, 'execute')
       and not has_function_privilege('service_role', g, 'execute'), g || ' can be called from outside';
    assert not exists (select 1 from pg_proc p cross join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                        where p.oid = g::regprocedure and a.grantee = 0), g || ' is open to public';
    assert (select not p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) from pg_proc p where p.oid = g::regprocedure),
      g || ' runs as owner or has no empty search path';
    assert length(coalesce(obj_description(g::regprocedure, 'pg_proc'), '')) > 100, g || ' has no description';
  end loop;
  assert position('private.scan_pairs_keep()' in obj_description('private.scan_ingest(bigint, text, jsonb)'::regprocedure, 'pg_proc')) > 0
     and position('private.scan_connections()' in obj_description('private.scan_ingest(bigint, text, jsonb)'::regprocedure, 'pg_proc')) > 0
     and position('Weekly points (since 23 Oct' in obj_description('public.route_story(bigint, timestamptz)'::regprocedure, 'pg_proc')) > 0
     and position('Connecting (since 23 Oct' in obj_description('public.route_story(bigint, timestamptz)'::regprocedure, 'pg_proc')) > 0,
    'a description doesn''t say what changed, or lost what it said before (the connections)';
  -- the week: the Saturday on or before the UTC date
  assert private.scan_week(timestamptz '2030-03-02 08:00:00+00') = date '2030-03-02' and private.scan_week(timestamptz '2030-03-08 23:59:00+00') = date '2030-03-02'
     and private.scan_week(timestamptz '2030-03-09 00:00:00+00') = date '2030-03-09' and private.scan_week(timestamptz '2026-10-23 00:23:00+00') = date '2026-10-17',
    'the week isn''t Saturday to Friday, UTC';
  -- the archive leaves it alone
  assert not exists (select 1 from private.archive_tables() t where t.table_name = 'scan_pair_airlines'), 'the archive lists scan_pair_airlines';
  assert not exists (select 1 from private.archive_due() d where d.table_name = 'scan_pair_airlines'), 'archive_due() names scan_pair_airlines';
  begin
    perform private.archive_delete(m, 'scan_pair_airlines', 0, 'x');
    assert false, 'the guarded delete didn''t refuse scan_pair_airlines';
  exception when others then
    assert sqlerrm like '%scan_pair_airlines is not a table the archive may touch%', 'the guarded delete refused scan_pair_airlines for another reason: ' || sqlerrm;
  end;
  raise notice 'scan_pair_airlines: RLS on with no rule, closed to anon and authenticated, the spec''s columns, every one described; scan_week(), scan_pairs_keep() and scan_pairs_fill_back() internal and described; the archive leaves it alone (not listed, never due, the guarded delete refuses it)';
end
$test$;

-- ---------------------------------------------------------------- 2. a world of its own, its scans finished as the capture does
do $setup$
declare
  dw bigint := (select id from public.worlds where is_default);
  w bigint; g bigint; p1 bigint; ty bigint; ids jsonb := '{}'::jsonb; sc jsonb := '{}'::jsonb; s bigint; x record; r_id bigint;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'rival pairs history test', true);
  insert into public.airports (code, utc_offset, lat, lon) values ('YP1', 0, 0, 0), ('YP2', 0, 2, 0), ('YP3', 0, 4, 0)
  on conflict (code) do update set utc_offset = excluded.utc_offset, lat = excluded.lat, lon = excluded.lon;
  insert into public.worlds (name, game_host, kind) values ('rival pairs history test', 'rival-pairs-history.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s2.key, s2.value, s2.unit, s2.description from public.settings s2 where s2.world_id = dw and s2.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990951, 'Pair One', 'Pair One', 'P1', 'YP1', true, 1) returning id into p1;
  insert into public.airline_bases (world_id, airline_id, airport_code, role, is_main, position) values (w, p1, 'YP1', 'hub', true, 1);
  insert into public.aircraft_types (world_id, name, seats_max, range_km, price, cruise_kmh, min_turn_min)
  values (w, 'PH A320', 180, 6000, 2000000, 840, 60) returning id into ty;
  insert into public.airline_aircraft_types (world_id, airline_id, aircraft_type_id) values (w, p1, ty);
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, stars, source) values (w, p1, 'YP1', 'YP2', 222, 4, 'research')
  returning id into r_id;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, p1, r_id, date '2030-02-01');
  insert into public.aircraft (world_id, airline_id, registration, aircraft_type_id, status, base_code) values (w, p1, 'YP-1', ty, 'active', 'YP1');
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min)
  select w, p1, ro.id, l.n, 100 + l.n, case when l.n = 1 then 'YP1' else 'YP2' end, case when l.n = 1 then 'YP2' else 'YP1' end,
         (select id from public.aircraft where registration = 'YP-1' and world_id = w), '{1,2,3,4,5,6,7}', 400 + 200 * l.n, 60
    from public.rotations ro cross join (values (1), (2)) l(n) where ro.world_id = w;
  ids := jsonb_build_object('pr1', private.scan_airline(w, 990961, 'Pair Rival One'), 'pr2', private.scan_airline(w, 990962, 'Pair Rival Two'),
                            'pc1', private.scan_airline(w, 990963, 'Pair Cargo'));
  perform set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

  -- the scans (08:00 UTC). On YP1–YP2: P1 daily both ways (14); Pair Rival One 7 out and 3 back in s1 and s2 (10), 7 both
  -- ways in s3 and s4 (14); Pair Rival Two only from s2 (5 out); Pair Cargo's freighter daily out (never a rival). Pair Rival
  -- One also flies YP2–YP3, a pair none of ours flies, 2 a week out
  for x in select * from (values
      ('s1', timestamptz '2030-03-02 08:00:00+00', '3'),
      ('s2', timestamptz '2030-03-04 08:00:00+00', '3'),
      ('s3', timestamptz '2030-03-09 08:00:00+00', '1234567'),
      ('s4', timestamptz '2030-03-10 08:00:00+00', '1234567')) v(k, at, back) loop
    s := (private.scan_ingest(w, 'start', jsonb_build_object('week', 'ph', 'note', 'rival pairs history test ' || x.k)) ->> 'snapshot_id')::bigint;
    update public.game_scans set taken_at = x.at where id = s;
    insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights) values
      (s, w, p1, jsonb_build_array(pg_temp.ph_fl('P1', 101, 'YP1', 'YP2', '1234567'), pg_temp.ph_fl('P1', 102, 'YP2', 'YP1', '1234567'))),
      (s, w, (ids ->> 'pr1')::bigint, jsonb_build_array(pg_temp.ph_fl('R1', 1, 'YP1', 'YP2', '1234567'), pg_temp.ph_fl('R1', 2, 'YP2', 'YP1', x.back),
                                                        pg_temp.ph_fl('R1', 3, 'YP2', 'YP3', '25'))),
      (s, w, (ids ->> 'pr2')::bigint, case when x.k = 's1' then '[]'::jsonb else jsonb_build_array(pg_temp.ph_fl('R2', 1, 'YP1', 'YP2', '12345')) end),
      (s, w, (ids ->> 'pc1')::bigint, jsonb_build_array(pg_temp.ph_fl('PC', 1, 'YP1', 'YP2', '1234567', '77F')));
    perform private.scan_ingest(w, 'finish', jsonb_build_object('snapshot_id', s, 'note', 'full scan: 4 enterprises'));
    sc := sc || jsonb_build_object(x.k, s);
  end loop;
  insert into t_ph values ('w', to_jsonb(w)), ('p1', to_jsonb(p1)), ('ids', ids), ('scans', sc), ('r', to_jsonb(r_id));
end
$setup$;

do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_ph where k = 'w'); sc jsonb := (select v from t_ph where k = 'scans'); got text;
begin
  select string_agg(x.k || ' ' || (select count(*) from public.scan_pair_airlines p where p.scan_id = (sc ->> x.k)::bigint), ', ' order by x.k) into got
    from (select jsonb_object_keys(sc) as k) x;
  assert got = 's1 4, s2 0, s3 5, s4 0', 'the finish didn''t keep s1 and s3 only (the first of each week), once: ' || got;
  select string_agg(format('%s %s-%s %s/%s %s', coalesce(a.public_name, a.game_name), p.a, p.b, p.weekly_a_to_b, p.weekly_b_to_a, case when p.passenger then 'pax' else 'freight' end), '; '
                    order by coalesce(a.public_name, a.game_name), p.a, p.b, p.passenger)
    into got from public.scan_pair_airlines p join public.airlines a on a.id = p.airline_id where p.scan_id = (sc ->> 's1')::bigint;
  assert got = 'Pair Cargo YP1-YP2 7/0 freight; Pair One YP1-YP2 7/7 pax; Pair Rival One YP1-YP2 7/1 pax; Pair Rival One YP2-YP3 2/0 pax',
    's1''s kept rows aren''t each airline''s departures each way on every pair (ours, a pair not ours, the freighter apart): ' || coalesce(got, 'none');
  assert (select string_agg(note, ' | ' order by taken_at) from public.game_scans where world_id = w)
         = 'full scan: 4 enterprises · connections: 0 rivals on 0 of our pairs | full scan: 4 enterprises · connections: 0 rivals on 0 of our pairs | full scan: 4 enterprises · connections: 0 rivals on 0 of our pairs | full scan: 4 enterprises · connections: 0 rivals on 0 of our pairs',
    'the finish note changed: ' || (select string_agg(note, ' | ' order by taken_at) from public.game_scans where world_id = w);
  assert (private.scan_pairs_keep((sc ->> 's2')::bigint)) ->> 'why' = 'the week has a kept scan'
     and (private.scan_pairs_keep((sc ->> 's1')::bigint)) ->> 'why' = 'already kept',
    'scan_pairs_keep() by hand doesn''t say why it wrote nothing';
  raise notice 'the finish: s1 (Saturday) and s3 (the next Saturday) kept, 4 and 5 rows; s2 and s4 the same weeks write none, nor s1 kept again by hand; the rows each airline''s each way on every pair (ours 7/7, a pair none of ours flies, the freighter apart); the note as before';
end
$test$;

-- ---------------------------------------------------------------- 3. the fill-back
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_ph where k = 'w'); sc jsonb := (select v from t_ph where k = 'scans');
  ids jsonb := (select v from t_ph where k = 'ids'); r jsonb; got text; s5 bigint; n_other bigint;
begin
  -- a scan still running in the third week: never kept
  insert into public.game_scans (world_id, taken_at, status) values (w, timestamptz '2030-03-16 08:00:00+00', 'running') returning id into s5;
  insert into public.game_scan_schedules (scan_id, world_id, airline_id, flights)
  values (s5, w, (ids ->> 'pr1')::bigint, jsonb_build_array(pg_temp.ph_fl('R1', 1, 'YP1', 'YP2', '1234567')));
  delete from public.scan_pair_airlines p using public.game_scans g where g.id = p.scan_id and g.world_id = w;
  select count(*) into n_other from public.scan_pair_airlines;
  r := private.scan_pairs_fill_back();
  select string_agg(case (e ->> 'scan_id')::bigint when (sc ->> 's1')::bigint then 's1' when (sc ->> 's2')::bigint then 's2'
                         when (sc ->> 's3')::bigint then 's3' when (sc ->> 's4')::bigint then 's4' when s5 then 's5' else 'other' end
                    || ' ' || (e ->> 'week') || ' ' || (e ->> 'rows'), ', ' order by e ->> 'week') into got
    from jsonb_array_elements(r) e;
  assert got = 's1 2030-03-02 4, s3 2030-03-09 5', 'the fill-back didn''t keep s1 and s3 only (one a week, the first; the copy''s weeks already kept): ' || coalesce(got, 'none');
  assert (select count(*) from public.scan_pair_airlines) = n_other + 9, 'the fill-back wrote other rows';
  assert private.scan_pairs_fill_back() = '[]'::jsonb, 'the fill-back run again wrote something';
  delete from public.game_scan_schedules where scan_id = s5;
  delete from public.game_scans where id = s5;
  raise notice 'the fill-back: s1 and s3 kept again (one a week, the first), s2, s4 and a running scan not; again, nothing';
end
$test$;

-- ---------------------------------------------------------------- 4. route_story() from the schedules and from the kept rows
do $test$
declare w bigint := (select (v #>> '{}')::bigint from t_ph where k = 'w'); sc jsonb := (select v from t_ph where k = 'scans');
  r_id bigint := (select (v #>> '{}')::bigint from t_ph where k = 'r'); t timestamptz := timestamptz '2030-03-11 12:00:00+00';
  early timestamptz := timestamptz '2030-03-03 12:00:00+00'; d0 jsonb; d1 jsonb; e0 jsonb; e1 jsonb; got text;
begin
  -- before the archive: every scan from its schedules, no weekly point
  d0 := private.fig_route_story(r_id, t);
  e0 := private.fig_route_story(r_id, early);
  assert (d0 #>> '{rivals,weekly_points}')::int = 0 and d0 #> '{rivals,daily_from}' = 'null'::jsonb
     and not exists (select 1 from jsonb_array_elements(d0 #> '{rivals,shares}') x where (x ->> 'weekly')::boolean),
    'with every scan''s schedules there, a point is weekly: ' || (d0 -> 'rivals')::text;
  select string_agg(format('%s %s/%s %s', left(x ->> 'taken_at', 10), x ->> 'ours', x ->> 'rivals', x ->> 'share'), ', ' order by i) into got
    from jsonb_array_elements(d0 #> '{rivals,shares}') with ordinality y(x, i);
  assert got = '2030-03-02 14/8 63.6, 2030-03-04 14/13 51.9, 2030-03-09 14/19 42.4, 2030-03-10 14/19 42.4',
    'the shares from the schedules aren''t as made (ours and rivals both ways, the freighter left out): ' || coalesce(got, 'none');
  -- the archive takes week one's schedules (s1 and s2, as the monthly archive takes a month's)
  delete from public.game_scan_schedules where scan_id in ((sc ->> 's1')::bigint, (sc ->> 's2')::bigint);
  d1 := private.fig_route_story(r_id, t);
  e1 := private.fig_route_story(r_id, early);
  -- as of 3 Mar, the latest scan is s1: the same rivals and share from its kept rows as from its schedules
  assert e1 #> '{rivals,airlines}' = e0 #> '{rivals,airlines}' and e1 #> '{rivals,rivals_weekly}' = e0 #> '{rivals,rivals_weekly}'
     and e1 #> '{rivals,share}' = e0 #> '{rivals,share}' and e1 #>> '{rivals,scan,id}' = sc ->> 's1' and (e1 #>> '{rivals,scan,weekly}')::boolean
     and e0 #> '{rivals,scan,weekly}' is null,
    's1''s rivals from its kept rows aren''t its rivals from its schedules: ' || (e1 -> 'rivals')::text || ' against ' || (e0 -> 'rivals')::text;
  assert (select string_agg(x ->> 'name' || ' ' || (x ->> 'weekly'), ', ') from jsonb_array_elements(e1 #> '{rivals,airlines}') x) = 'Pair Rival One 8',
    'as of 3 Mar the rivals aren''t Pair Rival One 8 (the freighter left out): ' || (e1 #> '{rivals,airlines}')::text;
  -- as of 11 Mar: s1's point still shows, weekly, with the same figures; s2's (not kept) is gone; s3 and s4 from schedules
  select string_agg(format('%s %s/%s %s%s', left(x ->> 'taken_at', 10), x ->> 'ours', x ->> 'rivals', x ->> 'share',
                           case when (x ->> 'weekly')::boolean then ' weekly' else '' end), ', ' order by i) into got
    from jsonb_array_elements(d1 #> '{rivals,shares}') with ordinality y(x, i);
  assert got = '2030-03-02 14/8 63.6 weekly, 2030-03-09 14/19 42.4, 2030-03-10 14/19 42.4',
    'with week one archived, the shares aren''t s1''s weekly point and s3, s4 from schedules: ' || coalesce(got, 'none');
  assert (d1 #>> '{rivals,weekly_points}')::int = 1 and left(d1 #>> '{rivals,daily_from}', 10) = '2030-03-09'
     and (select count(*) from jsonb_array_elements(d1 #> '{scans,since_launch}') x where (x ->> 'weekly')::boolean) = 1,
    'weekly_points and daily_from don''t say one weekly point before 9 Mar: ' || (d1 -> 'rivals' - 'airlines')::text;
  -- the latest scan's rivals stay; the week before (s2, not kept) becomes s1's weekly point
  assert (select jsonb_agg(x - 'weekly_before' - 'change') from jsonb_array_elements(d1 #> '{rivals,airlines}') x)
         = (select jsonb_agg(x - 'weekly_before' - 'change') from jsonb_array_elements(d0 #> '{rivals,airlines}') x)
     and d1 #> '{rivals,share}' = d0 #> '{rivals,share}' and d0 #>> '{rivals,week_before,id}' = sc ->> 's2'
     and d1 #>> '{rivals,week_before,id}' = sc ->> 's1' and (d1 #>> '{rivals,week_before,weekly}')::boolean,
    'the latest scan''s rivals moved when an older week was archived, or the week before isn''t s1''s weekly point: ' || (d1 #> '{rivals,week_before}')::text;
  assert exists (select 1 from jsonb_array_elements(d1 -> 'notes') n where n #>> '{}' like 'Weekly points (since 23 Oct)%'), 'no note on the weekly points';
  raise notice 'route_story(): as of 3 Mar, s1''s rivals the same from its kept rows as from its schedules (Pair Rival One 8, the freighter left out); with week one archived, s1''s point still shows (63.6%%, weekly), s2''s is gone, s3 and s4 from their schedules; weekly_points 1, daily_from 9 Mar; the latest scan''s rivals as before, the week before now s1''s weekly point';
end
$test$;

-- ---------------------------------------------------------------- the copy (counts and timings only)
do $test$
declare dw bigint := (select id from public.worlds where is_default); r record; a bigint; rid bigint; t0 timestamptz; d jsonb; got text;
begin
  select string_agg(format('scan %s (week of %s): %s rows', x.scan_id, private.scan_week(g.taken_at), x.n), ', ' order by g.taken_at) into got
    from (select p.scan_id, count(*) as n from public.scan_pair_airlines p where p.world_id = dw group by p.scan_id) x
    join public.game_scans g on g.id = x.scan_id;
  select al.airline_id into a from private.fig_airlines(dw) al order by al.ord limit 1;
  select x.route_id into rid from public.route_days x where x.airline_id = a and x.route_id is not null group by x.route_id order by sum(x.flights) desc limit 1;
  if rid is not null then
    t0 := clock_timestamp();
    d := private.fig_route_story(rid, now());
  end if;
  raise notice 'on the copy: kept %; the first airline''s busiest route''s story took % ms, % point(s) since launch, % weekly',
    coalesce(got, 'nothing'), coalesce(round(extract(epoch from clock_timestamp() - t0) * 1000)::text, '—'),
    coalesce(jsonb_array_length(d #> '{rivals,shares}'), 0), coalesce(d #>> '{rivals,weekly_points}', '0');
end
$test$;

do $$ begin raise notice 'each week''s rivals by pair: all checks passed'; end $$;

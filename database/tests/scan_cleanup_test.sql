-- The nightly clean-up of the world scans' connections and summaries (to-do 240; spec docs/specs/2026-11-15-scan-cleanup.md;
-- migration 20261115140000_scan_cleanup.sql). Run by database/rehearse.sh on the copy of last night's backup, after the
-- new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which (scan
-- ids, counts and keys, never figures).
--   1. The catalogue: settings.scan_keep_days is 14 days in every world, described, with its reason; private.scan_cleanup()
--      is postgres's only, runs as the caller with an empty search path and is described.
--   2. On the copy: the readers' answers for now are the same before and after the clean-up runs at now:
--      competition() for each of our active airlines, hub_progress(), the scan line of system_status(), the world scan's
--      airport list (capture_scan_plan()) and route_story() for a few flown routes, whose per-scan connection list
--      (connecting_scans) loses exactly the scans whose detail went and nothing else. Then the rows: no connection detail
--      older than 14 days but the latest finished scan's, and the two summary tables keep only the week's kept scans
--      among the older scans. Counts are printed.
--   3. A world of its own with hand-made scans: what goes and what stays (the week's kept scan by its scan_pair_airlines
--      rows and by being the week's first finished scan; a stopped scan; a scan 13 days old; the latest), a second run
--      deletes nothing, a run on an earlier day and then today (a missed night) ends the same, a world without the setting
--      keeps everything and says so, and the latest finished scan is never touched however old it is.
--   4. private.job_cleanup(): its job_runs row for the world gives the scan counts in its note and details; with the scan
--      part made to fail, the run fails and says so, the scan rows stay, and the raw pages still go.

-- ---------------------------------------------------------------- 1. the catalogue
do $test$
begin
  assert (select count(*) = (select count(*) from public.worlds)
                 and bool_and(s.value = '14'::jsonb and s.unit = 'days' and length(coalesce(s.description, '')) > 60
                              and coalesce(s.reason, '') like '%2026-11-15-scan-connections-growth%')
            from public.settings s where s.key = 'scan_keep_days' and s.airline_id is null),
    'settings.scan_keep_days isn''t 14 days, described and with its reason, in every world';
  assert not exists (select 1 from pg_proc p where p.oid = 'private.scan_cleanup(bigint, timestamptz)'::regprocedure
                       and (p.prosecdef or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                            or has_function_privilege('service_role', p.oid, 'execute') or not coalesce('search_path=""' = any (p.proconfig), false)
                            or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0)
                            or length(coalesce(obj_description(p.oid, 'pg_proc'), '')) < 60)),
    'private.scan_cleanup() is open to others, runs as owner, has no empty search path or no description';
  assert position('scan_keep_days' in coalesce(obj_description('private.job_cleanup(timestamptz)'::regprocedure, 'pg_proc'), '')) > 0,
    'private.job_cleanup()''s description doesn''t name the scan clean-up';
  raise notice 'catalogue: scan_keep_days 14 days in every world; scan_cleanup() closed, empty search path, described';
end
$test$;

-- ---------------------------------------------------------------- 2. on the copy: the readers for now, then the rows
do $test$
declare
  w bigint := (select id from public.worlds where is_default); v_at timestamptz := now(); v_cut timestamptz;
  v_latest bigint; v_latest_at timestamptz; x bigint; a jsonb; b jsonb; res jsonb; v_routes bigint[]; v_air bigint[];
  bef jsonb := '{}'::jsonb; n_routes int := 0; n_lost int := 0; bad text; n0 bigint; n1 bigint; n2 bigint;
begin
  v_cut := v_at - interval '14 days';
  select s.id, s.taken_at into v_latest, v_latest_at from public.game_scans s
   where s.world_id = w and s.status = 'done' order by s.taken_at desc, s.id desc limit 1;
  if v_latest is null then raise notice 'on the copy: no finished world scan, nothing to compare'; return; end if;
  select array_agg(al.id order by al.id) into v_air
    from public.airlines al join public.groups g on g.id = al.group_id and g.world_id = al.world_id
   where al.world_id = w and al.active and g.kind = 'ours';
  -- a few flown routes: those whose pair has the most connection rows in older scans first, so the list is tested
  select array_agg(x.id order by x.k desc, x.id) into v_routes from (
    select r2.id, (select count(*) from public.scan_rival_connections c join public.game_scans s on s.id = c.scan_id
                    where s.world_id = w and least(c.origin, c.dest) = least(r2.hub_code, r2.dest_code)
                      and greatest(c.origin, c.dest) = greatest(r2.hub_code, r2.dest_code)) as k
      from public.routes r2
     where r2.world_id = w and not r2.removed and exists (select 1 from public.rotations rt where rt.route_id = r2.id)
     order by 2 desc, 1 limit 6) x;
  select count(*) into n0 from public.scan_rival_connections c join public.game_scans s on s.id = c.scan_id where s.world_id = w;
  select count(*) into n1 from public.scan_rival_connections_week c join public.game_scans s on s.id = c.scan_id where s.world_id = w;
  select count(*) into n2 from public.scan_airline_airports c join public.game_scans s on s.id = c.scan_id where s.world_id = w;

  -- before
  foreach x in array coalesce(v_air, '{}') loop
    bef := bef || jsonb_build_object('competition ' || x, private.fig_competition(x, v_at));
  end loop;
  bef := bef || jsonb_build_object('hub_progress', private.fig_hub_progress(w, v_at),
                                   'system_status scan', public.system_status(w, v_at) -> 'scan',
                                   'capture_scan_plan', private.capture_scan_plan(w, v_at));
  foreach x in array coalesce(v_routes, '{}') loop
    bef := bef || jsonb_build_object('route_story ' || x, private.fig_route_story(x, v_at));
  end loop;

  res := private.scan_cleanup(w, v_at);
  assert (res ->> 'scan_enabled')::boolean, 'the clean-up is switched off on the copy: ' || (res ->> 'note');

  -- after: every answer the same; the route page's per-scan list without the scans whose detail went
  foreach x in array coalesce(v_air, '{}') loop
    assert private.fig_competition(x, v_at) = bef -> ('competition ' || x), format('competition() for airline %s changed', x);
  end loop;
  assert private.fig_hub_progress(w, v_at) = bef -> 'hub_progress', 'hub_progress() changed';
  assert public.system_status(w, v_at) -> 'scan' is not distinct from bef -> 'system_status scan', 'the Systems board''s scan line changed';
  assert private.capture_scan_plan(w, v_at) = bef -> 'capture_scan_plan', 'the world scan''s airport list (capture_scan_plan()) changed';
  foreach x in array coalesce(v_routes, '{}') loop
    a := bef -> ('route_story ' || x); b := private.fig_route_story(x, v_at);
    assert (a #- '{rivals,connecting_scans}') = (b #- '{rivals,connecting_scans}'),
      format('route_story() for route %s changed beyond its per-scan connection list', x);
    if a #> '{rivals,connecting_scans}' is not null then
      assert b #> '{rivals,connecting_scans}' = (
               select coalesce(jsonb_agg(e order by i), '[]'::jsonb) from jsonb_array_elements(a #> '{rivals,connecting_scans}') with ordinality x(e, i)
                where exists (select 1 from public.scan_rival_connections c where c.scan_id = (e ->> 'scan_id')::bigint)),
        format('route_story() for route %s: connecting_scans isn''t the same less the scans cleaned', x);
      n_lost := n_lost + jsonb_array_length(a #> '{rivals,connecting_scans}') - jsonb_array_length(b #> '{rivals,connecting_scans}');
      assert exists (select 1 from jsonb_array_elements(b #> '{rivals,connecting_scans}') e where (e ->> 'scan_id')::bigint = (b #>> '{rivals,scan,id}')::bigint)
          or (b #>> '{rivals,scan,id}') is distinct from v_latest::text,
        format('route_story() for route %s lost the latest scan''s connections', x);
    end if;
    n_routes := n_routes + 1;
  end loop;

  -- the rows
  select string_agg(distinct s.id::text, ', ') into bad from public.scan_rival_connections c join public.game_scans s on s.id = c.scan_id
   where s.world_id = w and s.taken_at < least(v_cut, v_latest_at);
  assert bad is null, 'connection detail older than 14 days left for scans ' || bad;
  assert exists (select 1 from public.scan_rival_connections c where c.scan_id = v_latest)
      or not exists (select 1 from public.scan_rival_connections_week c where c.scan_id = v_latest),
    'the latest finished scan lost its connections';
  select string_agg(distinct s.id::text, ', ') into bad
    from (select c.scan_id from public.scan_rival_connections_week c union select c.scan_id from public.scan_airline_airports c) x
    join public.game_scans s on s.id = x.scan_id
   where s.world_id = w and s.taken_at < least(v_cut, v_latest_at)
     and not exists (select 1 from public.scan_pair_airlines k where k.scan_id = s.id)
     and not (s.status = 'done' and not exists (select 1 from public.game_scans g where g.world_id = w and g.status = 'done'
                                                   and private.scan_week(g.taken_at) = private.scan_week(s.taken_at)
                                                   and (g.taken_at < s.taken_at or (g.taken_at = s.taken_at and g.id < s.id))));
  assert bad is null, 'summaries older than 14 days left for scans that aren''t the week''s kept scan: ' || bad;
  raise notice 'on the copy: competition() for % airline(s), hub_progress(), the scan line, the scan''s airport list and route_story() for % route(s) unchanged for now (% older scan(s) left the routes'' per-scan lists); deleted % of % connection, % of % by-week and % of % airport rows; kept scans among the older: %',
    coalesce(cardinality(v_air), 0), n_routes, n_lost, res ->> 'scan_connections_deleted', n0, res ->> 'scan_week_deleted', n1,
    res ->> 'scan_airports_deleted', n2, res -> 'scan_kept';
end
$test$;

-- ---------------------------------------------------------------- 3. a world of its own
create temporary table t_sc (k text primary key, v bigint) on commit drop;

create function pg_temp.sc_rows(p_scan bigint) returns text language sql stable as $f$
  select format('%s/%s/%s', (select count(*) from public.scan_rival_connections c where c.scan_id = p_scan),
                (select count(*) from public.scan_rival_connections_week c where c.scan_id = p_scan),
                (select count(*) from public.scan_airline_airports c where c.scan_id = p_scan))
$f$;

-- a scan with two connection rows, one by-week row and one airport row; with pair rows when kept is true
create function pg_temp.sc_scan(w bigint, rv bigint, at timestamptz, st text, kept boolean) returns bigint language plpgsql as $f$
declare s bigint;
begin
  insert into public.game_scans (world_id, taken_at, status, note) values (w, at, st, 'scan clean-up test') returning id into s;
  insert into public.scan_rival_connections (scan_id, world_id, airline_id, origin, dest, via, weekly_departures, best_gap_min)
  values (s, w, rv, 'ZQA', 'ZQB', 'ZQH', 7, 90), (s, w, rv, 'ZQB', 'ZQA', 'ZQH', 7, 95);
  insert into public.scan_rival_connections_week (scan_id, world_id, airline_id, airport_a, airport_b, weekly_a_to_b, weekly_b_to_a, weekly_departures)
  values (s, w, rv, 'ZQA', 'ZQB', 7, 7, 14);
  insert into public.scan_airline_airports (scan_id, world_id, airline_id, airport_code, weekly_departures, destinations)
  values (s, w, rv, 'ZQH', 28, 2);
  if kept then
    insert into public.scan_pair_airlines (scan_id, world_id, airline_id, a, b, weekly_a_to_b, weekly_b_to_a, passenger)
    values (s, w, rv, 'ZQA', 'ZQH', 14, 14, true);
  end if;
  return s;
end
$f$;

do $test$
declare
  v_at timestamptz := now(); sat date; w bigint; w2 bigint; w3 bigint; g bigint; rv bigint; ours bigint; res jsonb; v_raw bigint;
  s1 bigint; s2 bigint; s3 bigint; s4a bigint; s4 bigint; s5 bigint; s6 bigint; s7 bigint; o1 bigint; o2 bigint; ol bigint; orun bigint;
  x2 bigint; j record; v_before text;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'scan clean-up test', true);
  -- the Saturday that starts a week 35 to 41 days ago: every scan of its week and the next is older than 14 days
  sat := private.scan_week(v_at - interval '35 days');
  insert into public.worlds (name, game_host, kind) values ('scan clean-up test', 'scan-cleanup.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  values (w, null, 'scan_keep_days', '14', 'days', 'scan clean-up test');
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, active, position)
  values (w, g, 990951, 'Clean One', 'Clean One', 'Q1', true, 1) returning id into ours;
  insert into public.groups (world_id, name, kind) values (w, 'rivals', 'rival') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, active, position)
  values (w, g, 990952, 'Rival One', 'Rival One', 'Q9', true, 2) returning id into rv;

  s1 := pg_temp.sc_scan(w, rv, (sat + 0)::timestamp at time zone 'UTC' + interval '12 hours', 'done', false);   -- the week's first: kept
  s2 := pg_temp.sc_scan(w, rv, (sat + 1)::timestamp at time zone 'UTC' + interval '12 hours', 'done', false);   -- same week: goes
  s3 := pg_temp.sc_scan(w, rv, (sat + 7)::timestamp at time zone 'UTC' + interval '8 hours', 'stopped', false); -- stopped: goes
  s4a := pg_temp.sc_scan(w, rv, (sat + 7)::timestamp at time zone 'UTC' + interval '10 hours', 'done', false);  -- the week's first: kept
  s4 := pg_temp.sc_scan(w, rv, (sat + 7)::timestamp at time zone 'UTC' + interval '15 hours', 'done', true);    -- pair rows: kept
  s5 := pg_temp.sc_scan(w, rv, (sat + 9)::timestamp at time zone 'UTC' + interval '12 hours', 'done', false);   -- goes
  s6 := pg_temp.sc_scan(w, rv, v_at - interval '13 days', 'done', false);                                          -- young: all stays
  s7 := pg_temp.sc_scan(w, rv, v_at - interval '1 day', 'done', false);                                            -- the latest

  -- a missed night: first an earlier run whose 14-day cut-off falls on the oldest week's Wednesday (sat + 4), so only
  -- that week is due, then today's takes the rest. The earlier run is dated from sat, not from today: sat is 35 to 41
  -- days back by the weekday, and a run "16 days back" (cut-off 30 days back) also took the second week's scans
  -- (sat + 7, 28 to 34 days back) from Tuesday to Friday, so this test failed on those days (found 18 Nov).
  res := private.scan_cleanup(w, (sat + 18)::timestamp at time zone 'UTC');
  assert pg_temp.sc_rows(s1) = '0/1/1' and pg_temp.sc_rows(s2) = '0/0/0' and pg_temp.sc_rows(s3) = '2/1/1'
     and pg_temp.sc_rows(s4a) = '2/1/1' and pg_temp.sc_rows(s4) = '2/1/1' and pg_temp.sc_rows(s5) = '2/1/1',
    format('the earlier run (cut-off sat + 4): %s %s %s %s %s %s (%s)', pg_temp.sc_rows(s1), pg_temp.sc_rows(s2), pg_temp.sc_rows(s3),
           pg_temp.sc_rows(s4a), pg_temp.sc_rows(s4), pg_temp.sc_rows(s5), res ->> 'note');
  res := private.scan_cleanup(w, v_at);
  assert (res ->> 'scan_enabled')::boolean and (res ->> 'scan_keep_days')::int = 14, 'the clean-up ran switched off: ' || (res ->> 'note');
  assert pg_temp.sc_rows(s1) = '0/1/1', 'the week''s first finished scan, older than 14 days: ' || pg_temp.sc_rows(s1);
  assert pg_temp.sc_rows(s2) = '0/0/0', 'a scan older than 14 days, not the week''s kept scan: ' || pg_temp.sc_rows(s2);
  assert pg_temp.sc_rows(s3) = '0/0/0', 'a stopped scan older than 14 days: ' || pg_temp.sc_rows(s3);
  assert pg_temp.sc_rows(s4a) = '0/1/1', 'the week''s first finished scan, without pair rows: ' || pg_temp.sc_rows(s4a);
  assert pg_temp.sc_rows(s4) = '0/1/1', 'the week''s kept scan by its pair rows: ' || pg_temp.sc_rows(s4);
  assert pg_temp.sc_rows(s5) = '0/0/0', 'a later scan of the week, older than 14 days: ' || pg_temp.sc_rows(s5);
  assert pg_temp.sc_rows(s6) = '2/1/1', 'a scan 13 days old lost rows: ' || pg_temp.sc_rows(s6);
  assert pg_temp.sc_rows(s7) = '2/1/1', 'the latest scan lost rows: ' || pg_temp.sc_rows(s7);
  assert exists (select 1 from public.scan_pair_airlines k where k.scan_id = s4) and exists (select 1 from public.game_scans s where s.id = s2),
    'the clean-up touched scan_pair_airlines or game_scans';
  assert (res ->> 'scan_connections_deleted')::int = 8 and (res ->> 'scan_week_deleted')::int = 2 and (res ->> 'scan_airports_deleted')::int = 2
     and res -> 'scan_kept' = to_jsonb(array[s1, s4a, s4]),
    'today''s run (after the earlier run) counted: ' || res::text;
  assert res ->> 'note' = 'world scans older than 14 days: 8 connection, 2 by-week and 2 airport rows deleted (the weeks'' kept scans keep their summaries)',
    'the note: ' || (res ->> 'note');
  -- again: nothing more
  res := private.scan_cleanup(w, v_at);
  assert (res ->> 'scan_connections_deleted')::int = 0 and (res ->> 'scan_week_deleted')::int = 0 and (res ->> 'scan_airports_deleted')::int = 0
     and pg_temp.sc_rows(s1) = '0/1/1' and pg_temp.sc_rows(s6) = '2/1/1', 'a second run deleted something: ' || res::text;

  -- a world without the setting: nothing goes, and the note says so
  insert into public.worlds (name, game_host, kind) values ('scan clean-up test 2', 'scan-cleanup-2.test', 'exclusive') returning id into w2;
  insert into public.groups (world_id, name, kind) values (w2, 'rivals', 'rival') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, active) values (w2, g, 990953, 'Rival Two', true) returning id into x2;
  o1 := pg_temp.sc_scan(w2, x2, v_at - interval '40 days', 'done', false);
  o2 := pg_temp.sc_scan(w2, x2, v_at - interval '39 days', 'done', false);
  perform pg_temp.sc_scan(w2, x2, v_at - interval '1 day', 'done', false);
  res := private.scan_cleanup(w2, v_at);
  assert not (res ->> 'scan_enabled')::boolean and res ->> 'note' like 'world scans: switched off (no settings.scan_keep_days)%'
     and pg_temp.sc_rows(o1) = '2/1/1' and pg_temp.sc_rows(o2) = '2/1/1', 'without the setting: ' || res::text;

  -- the latest finished scan is never touched, however old; nor a scan after it that hasn't finished
  insert into public.worlds (name, game_host, kind) values ('scan clean-up test 3', 'scan-cleanup-3.test', 'exclusive') returning id into w3;
  insert into public.settings (world_id, airline_id, key, value, unit, description) values (w3, null, 'scan_keep_days', '14', 'days', 'scan clean-up test');
  insert into public.groups (world_id, name, kind) values (w3, 'rivals', 'rival') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, active) values (w3, g, 990954, 'Rival Three', true) returning id into x2;
  o1 := pg_temp.sc_scan(w3, x2, (sat + 0)::timestamp at time zone 'UTC' + interval '1 hour', 'done', false);
  o2 := pg_temp.sc_scan(w3, x2, (sat + 0)::timestamp at time zone 'UTC' + interval '2 hours', 'done', false);
  ol := pg_temp.sc_scan(w3, x2, (sat + 0)::timestamp at time zone 'UTC' + interval '3 hours', 'done', false);
  orun := pg_temp.sc_scan(w3, x2, (sat + 0)::timestamp at time zone 'UTC' + interval '4 hours', 'stopped', false);
  res := private.scan_cleanup(w3, v_at);
  assert pg_temp.sc_rows(o1) = '0/1/1' and pg_temp.sc_rows(o2) = '0/0/0' and pg_temp.sc_rows(ol) = '2/1/1' and pg_temp.sc_rows(orun) = '2/1/1',
    format('the latest finished scan, 35 days old: %s %s %s %s', pg_temp.sc_rows(o1), pg_temp.sc_rows(o2), pg_temp.sc_rows(ol), pg_temp.sc_rows(orun));

  -- ---------------------------------------------------------------- 4. the job
  -- a fresh scan older than 14 days in the first world (a later one in s4's week), and a raw page 15 days old
  s2 := pg_temp.sc_scan(w, rv, (sat + 8)::timestamp at time zone 'UTC' + interval '12 hours', 'done', false);
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (w, ours, 'Clean One', 'html', 'scan-cleanup-test', '[]', v_at - interval '15 days') returning id into v_raw;
  perform private.job_cleanup(v_at);
  select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
  assert j.status = 'ok' and j.note like '%; world scans older than 14 days: 2 connection, 1 by-week and 1 airport rows deleted (the weeks'' kept scans keep their summaries)'
     and (j.details ->> 'scan_connections_deleted')::int = 2 and (j.details ->> 'scan_week_deleted')::int = 1
     and (j.details ->> 'scan_airports_deleted')::int = 1 and (j.details ->> 'scan_enabled')::boolean and (j.details ->> 'raw_deleted')::int = 1
     and not (j.details ? 'note') and length(j.note) <= 300,
    format('the job''s row: %s, %s, %s', j.status, j.note, j.details);
  assert pg_temp.sc_rows(s2) = '0/0/0' and not exists (select 1 from public.game_capture_raw where id = v_raw), 'the job didn''t clean the world';

  -- the scan part fails: the run fails and says so, the scan rows stay, the raw pages still go
  s2 := pg_temp.sc_scan(w, rv, (sat + 8)::timestamp at time zone 'UTC' + interval '13 hours', 'done', false);
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (w, ours, 'Clean One', 'html', 'scan-cleanup-test', '[]', v_at - interval '15 days') returning id into v_raw;
  create function pg_temp.sc_refuse() returns trigger language plpgsql as $f$
  begin raise exception 'scan clean-up test: refused'; end $f$;
  create trigger sc_refuse before delete on public.scan_airline_airports for each row execute function pg_temp.sc_refuse();
  perform private.job_cleanup(v_at);
  drop trigger sc_refuse on public.scan_airline_airports;
  select * into j from public.job_runs where job = 'cleanup' and world_id = w order by id desc limit 1;
  assert j.status = 'failed' and j.note like '%; world scans: failed, nothing deleted: scan clean-up test: refused',
    format('a failing scan part: %s, %s', j.status, j.note);
  assert pg_temp.sc_rows(s2) = '2/1/1', 'a failing scan part still deleted rows: ' || pg_temp.sc_rows(s2);
  assert not exists (select 1 from public.game_capture_raw where id = v_raw), 'a failing scan part kept the raw pages too';

  raise notice 'a world of its own: older than 14 days, the connection detail goes and the summaries stay only for the week''s kept scans (by pair rows and as the week''s first finished scan), a stopped scan''s go, 13 days old and the latest keep all; a second run and a missed night end the same; without the setting nothing goes; the latest finished scan 35 days old keeps all; the job''s note and details count it; a failing scan part fails the run, keeps the scan rows and still deletes raw pages';
end
$test$;

do $$ begin raise notice 'scan clean-up: all checks passed'; end $$;

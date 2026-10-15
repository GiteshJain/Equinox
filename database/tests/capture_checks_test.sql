-- Capture page checks (decision #21) and the Systems board's figures (decision #23); spec
-- docs/specs/2026-10-14-capture-checks-and-systems.md. Run by database/rehearse.sh on the copy of last night's backup,
-- after the new migrations, inside a transaction that is rolled back. A failed check stops with an error that says which.
--   1. The limits are settings in every world, described; the new columns and functions are described; the internal
--      steps aren't open to the data API's roles; system_status() is for staff only, runs as owner with an empty search
--      path and only reads.
--   2. The saved sample (the newest tests/fixtures/capture_pages_<day>.json.gz: one airline's five pages of one
--      evening): each page read alone gives exactly the rows saved with it, and each is judged ok against what was
--      expected of it that evening. Then the cases that must be judged short or broken: half the loads rows (short),
--      no statement lines (short), events and an income statement with no rows (short), a balance sheet without the
--      cash account (broken), a page that doesn't read (broken).
--   3. What to expect, in a world of its own: the flights scheduled in a loads page's window (its weekdays, the window's
--      24 hours, each rotation from the day after it launched) and the median of the statement's recent nights (the latest page of
--      each of up to 7 earlier capture days).
--   4. Through capture_ingest(), signed out like the userscript, in that world: each page's verdict in the reply; after
--      the loads page, rows holds the capture panel's words ("all good", or what came in short, ending on "N of M" for
--      the panel's " flights"), count the rows read; capture_status() gives the airline's latest verdicts the moment a
--      short page arrives (Home lists it the same night).
--   5. system_status() on the copy: each part there, the usage figures measured as the board shows them against their
--      triggers, and refused to anyone but staff.

-- the newest saved sample, read as the test starts (null when there is none)
\set capture_sample `f=$(ls tests/fixtures/capture_pages_*.json.gz 2>/dev/null | sort | tail -n 1); if [ -n "$f" ]; then gzip -dc "$f"; else echo null; fi`
create temporary table t_cs (doc jsonb) on commit drop;
insert into t_cs values (:'capture_sample'::jsonb);
create temporary table t_cc (k text primary key, v text) on commit drop;
grant select on t_cc to anon;

-- the rows an airline's capture tables hold, in the columns the pages give, each list sorted (as
-- tests/fixtures/capture_sample.sql saves them)
create function pg_temp.cs_gives(al bigint) returns jsonb language sql as $$
  select jsonb_build_object(
    'statement', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(private.fig_ts(s.ts), s.descr, s.amount, s.side, s.route, s.pax, s.occ, s.blk, s.flight_id is null) x
          from public.game_statement s where s.airline_id = al) q),
    'payments', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(private.fig_ts(p.paid_at), p.kind, p.registration, p.descr, p.amount, p.side, p.occ, p.statement_blk) x
          from public.game_payments p where p.airline_id = al) q),
    'money', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(private.fig_ts(f.posted_at), f.statement_blk, f.statement_routes, f.maint_registration, f.statement_pax,
                                 f.pax_income, f.cargo_income, f.fuel, f.onboard, f.handling, f.landing, f.atc, f.maintenance,
                                 f.income_total, f.cost_total, f.profit, f.origin_code, f.dest_code) x
          from public.game_flights f where f.airline_id = al and f.posted_at is not null) q),
    'loads', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(f.game_date, f.flight_no, f.dep_local, f.origin_code, f.dest_code, f.arr_local, f.registration, f.status,
                                 f.eco_pax, f.eco_seats, f.eco_fare, f.eco_pct, f.bus_pax, f.bus_seats, f.bus_fare, f.bus_pct,
                                 f.fst_pax, f.fst_seats, f.fst_fare, f.fst_pct, f.cargo_units, f.cargo_cap, f.cargo_rate, f.cargo_pct) x
          from public.game_flights f where f.airline_id = al and f.flight_no is not null) q),
    'events', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(e.event_date, e.event_time, e.descr, e.credit, e.debit, e.balance) x
          from public.game_events e where e.airline_id = al) q),
    'balance', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(b.captured_on, b.capture_day, b.account, b.amount) x
          from public.game_balance b where b.airline_id = al) q),
    'pnl', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(g.captured_on, g.capture_day, g.line, g.current_p, g.last_p, g.total_p) x
          from public.game_pnl g where g.airline_id = al) q))
$$;

-- stores a page as the capture does (without reading it), and gives its id
create function pg_temp.cs_raw(w bigint, al bigint, nm text, k text, url text, rows_ jsonb, at timestamptz) returns bigint language sql as $$
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (w, al, nm, k, url, rows_, at) returning id
$$;

-- reads a stored page as private.capture_store() does (a page that doesn't read gives the error), then judges it
create function pg_temp.cs_judge(rid bigint, exp_ jsonb) returns jsonb language plpgsql as $$
declare res jsonb;
begin
  begin
    res := private.capture_page(rid);
  exception when others then
    res := jsonb_build_object('ok', false, 'error', 'parse: ' || sqlerrm);
  end;
  return private.capture_check(rid, res, coalesce(exp_, '{}'::jsonb)) || jsonb_build_object('parsed', res -> 'rows');
end
$$;

-- a loads-page row with the local times the game shows (as capture_data_matching_test.sql makes them)
create function pg_temp.loads_row(p_no int, p_dep timestamptz) returns jsonb language sql as $$
  select jsonb_build_array('VC ' || p_no, 'VC-' || p_no, 'ZY1', to_char(p_dep at time zone 'UTC', 'DD.MM. HH24:MI') || ' LT', 'ZY2',
           to_char((p_dep at time zone 'UTC') + interval '2 hours', 'DD.MM. HH24:MI') || ' LT',
           '100 AS$', '100 / 150 (67%)', '-', '-', '-', '-', '1 AS$', '1 / 10 (10%)', 'finished', 'details')
$$;

-- ---------------------------------------------------------------- 1. settings, descriptions, who may run what
do $test$
declare bad text; f regprocedure;
begin
  select string_agg(w.name || ' ' || k.key, ', ') into bad
    from public.worlds w cross join (values ('capture_loads_min_share', 0.9), ('capture_statement_min_share', 0.5)) k(key, val)
   where not exists (select 1 from public.settings s where s.world_id = w.id and s.airline_id is null and s.key = k.key
                       and coalesce(s.description, '') <> '');
  assert bad is null, 'a world is missing a capture limit, or its description: ' || bad;
  assert (select (s.value #>> '{}')::numeric from public.settings s join public.worlds w on w.id = s.world_id and w.is_default
           where s.airline_id is null and s.key = 'capture_loads_min_share') = 0.9
     and (select (s.value #>> '{}')::numeric from public.settings s join public.worlds w on w.id = s.world_id and w.is_default
           where s.airline_id is null and s.key = 'capture_statement_min_share') = 0.5,
    'the default world''s capture limits aren''t 0.9 and 0.5';
  select string_agg(a.attname, ', ') into bad from pg_attribute a
   where a.attrelid = 'public.game_capture_raw'::regclass and a.attname in ('verdict', 'verdict_note', 'verdict_facts') and not a.attisdropped
     and col_description(a.attrelid, a.attnum) is null;
  assert bad is null, 'game_capture_raw columns without a description: ' || bad;
  assert (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'game_capture_raw'
            and c.column_name in ('verdict', 'verdict_note', 'verdict_facts')) = 3, 'game_capture_raw lacks its verdict columns';
  foreach f in array array['private.capture_statement_lines(jsonb)', 'private.capture_expect(bigint)',
                           'private.capture_judge(text, integer, text, boolean, jsonb, numeric, numeric)', 'private.capture_check(bigint, jsonb, jsonb)',
                           'private.capture_airline_verdict(bigint, timestamptz)', 'private.capture_panel_words(jsonb)',
                           'public.system_status(bigint, timestamptz)']::regprocedure[] loop
    assert obj_description(f, 'pg_proc') is not null, f::text || ' has no description';
    if f::text like 'private.%' then
      assert not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute'),
        f::text || ' is open to the data API''s roles';
    end if;
  end loop;
  assert (select p.prosecdef and coalesce('search_path=""' = any (p.proconfig), false) and p.provolatile = 's'
            from pg_proc p where p.oid = 'public.system_status(bigint, timestamptz)'::regprocedure),
    'system_status() doesn''t run as owner, read only, with an empty search path';
  assert has_function_privilege('authenticated', 'public.system_status(bigint, timestamptz)', 'execute')
     and not has_function_privilege('anon', 'public.system_status(bigint, timestamptz)', 'execute'),
    'system_status() isn''t callable signed in only';
  raise notice 'the limits: capture_loads_min_share 0.9 and capture_statement_min_share 0.5 in every world, described; the verdicts'' columns and the 7 functions described; system_status() signed in only, as owner, read only';
end
$test$;

-- ---------------------------------------------------------------- 2. the saved sample, and the cases that must fail
do $test$
declare s jsonb := (select doc from t_cs); w bigint; al bigint; nm text; p jsonb; rid bigint; res jsonb; v jsonb; g jsonb; k text;
  bad text := ''; verdicts text := ''; n_diff int; t0 timestamptz; lp jsonb; half jsonb; n_flights int; got text; cases text := '';
begin
  if s is null or jsonb_typeof(s) <> 'object' then
    raise exception 'no saved capture sample: tests/fixtures/capture_pages_<capture day>.json.gz is missing (tests/README.md, "The capture sample")';
  end if;
  select a.id, a.world_id, a.planner_name into al, w, nm
    from public.airlines a join public.worlds x on x.id = a.world_id and x.is_default where a.game_id = (s ->> 'game_id')::int;
  assert al is not null, 'the sample''s airline (game ID ' || (s ->> 'game_id') || ') isn''t on the copy';
  -- the airline's capture rows emptied (rolled back with the test), then each page read alone, in the order it came
  delete from public.game_statement where airline_id = al;
  delete from public.game_flights where airline_id = al;
  delete from public.game_payments where airline_id = al;
  delete from public.game_events where airline_id = al;
  delete from public.game_balance where airline_id = al;
  delete from public.game_pnl where airline_id = al;
  for p in select e from jsonb_array_elements(s -> 'pages') with ordinality x(e, o) order by o loop
    rid := pg_temp.cs_raw(w, al, nm, p ->> 'kind', p ->> 'page_url', p -> 'rows', (p ->> 'captured_at')::timestamptz);
    v := pg_temp.cs_judge(rid, s -> 'expect' -> (p ->> 'kind'));
    if (v ->> 'parsed') is distinct from (s -> 'read' ->> (p ->> 'kind')) then
      bad := bad || format(' %s read %s rows, the sample says %s;', p ->> 'kind', coalesce(v ->> 'parsed', 'none'), s -> 'read' ->> (p ->> 'kind'));
    end if;
    verdicts := verdicts || format('%s %s (%s), ', p ->> 'kind', v ->> 'verdict', v ->> 'note');
    if v ->> 'verdict' is distinct from 'ok' then
      bad := bad || format(' the saved %s page is judged %s: %s;', p ->> 'kind', coalesce(v ->> 'verdict', 'nothing'), v ->> 'note');
    end if;
  end loop;
  g := pg_temp.cs_gives(al);
  for k in select jsonb_object_keys(s -> 'gives') loop
    if g -> k is distinct from s -> 'gives' -> k then
      select count(*) into n_diff from (
        (select e from jsonb_array_elements(g -> k) e except all select e from jsonb_array_elements(s -> 'gives' -> k) e)
        union all
        (select e from jsonb_array_elements(s -> 'gives' -> k) e except all select e from jsonb_array_elements(g -> k) e)) x;
      bad := bad || format(' %s: %s rows differ from the saved ones;', k, n_diff);
    end if;
  end loop;
  assert bad = '', format('the saved sample (%s, %s):%s', s ->> 'airline', s ->> 'capture_day', bad);

  -- the cases that must be judged short or broken, each against what was expected that evening
  t0 := (select max((e ->> 'captured_at')::timestamptz) from jsonb_array_elements(s -> 'pages') e) + interval '1 minute';
  lp := (select e from jsonb_array_elements(s -> 'pages') e where e ->> 'kind' = 'loads');
  select count(*) into n_flights from jsonb_array_elements(lp -> 'rows') e
   where jsonb_array_length(e) >= 15 and e ->> 0 ~ '^[A-Z0-9]{2,3}\s?\d{1,5}' and e ->> 3 ~ '\d{2}\.\d{2}\. \d{2}:\d{2}';
  -- half the loads rows: the page's other rows and the first half of its flights
  select jsonb_agg(x.e order by x.o) into half
    from (select e, o, case when jsonb_array_length(e) >= 15 and e ->> 0 ~ '^[A-Z0-9]{2,3}\s?\d{1,5}' and e ->> 3 ~ '\d{2}\.\d{2}\. \d{2}:\d{2}'
                            then count(*) filter (where jsonb_array_length(e) >= 15 and e ->> 0 ~ '^[A-Z0-9]{2,3}\s?\d{1,5}'
                                                    and e ->> 3 ~ '\d{2}\.\d{2}\. \d{2}:\d{2}') over (order by o) end as nth
            from jsonb_array_elements(lp -> 'rows') with ordinality y(e, o)) x
   where x.nth is null or x.nth <= n_flights / 2;
  for k, rid, got in
    select c.k, pg_temp.cs_raw(w, al, nm, c.kind, '/test', c.rows_, t0), c.want
      from (values
        ('half the loads rows', 'loads', half, 'short'),
        ('no statement lines', 'statement', '[]'::jsonb, 'short'),
        ('events with no rows', 'events', '[]'::jsonb, 'short'),
        ('an income statement with no rows', 'pnl', '[]'::jsonb, 'short'),
        ('a balance sheet without the cash account', 'balance',
         (select coalesce(jsonb_agg(e order by o), '[]') from jsonb_array_elements((select e -> 'rows' from jsonb_array_elements(s -> 'pages') e where e ->> 'kind' = 'balance')) with ordinality y(e, o)
           where not (e ->> 0 = '2800' or e ->> 3 = '2800')), 'broken'),
        ('a loads page that doesn''t read', 'loads', '[{"not": "a row"}]'::jsonb, 'broken')
      ) as c(k, kind, rows_, want)
  loop
    v := pg_temp.cs_judge(rid, s -> 'expect' -> (select kind from public.game_capture_raw where id = rid));
    assert v ->> 'verdict' = got, format('%s is judged %s, not %s: %s', k, coalesce(v ->> 'verdict', 'nothing'), got, v ->> 'note');
    cases := cases || format('%s %s (%s); ', k, v ->> 'verdict', v ->> 'note');
  end loop;
  raise notice 'the saved sample (% on %): each page reads the rows saved with it (% statement lines, % loads rows, % flights'' money, % payments, % events, % balance rows, % income lines) and is judged %',
    s ->> 'airline', s ->> 'capture_day', jsonb_array_length(g -> 'statement'), jsonb_array_length(g -> 'loads'), jsonb_array_length(g -> 'money'),
    jsonb_array_length(g -> 'payments'), jsonb_array_length(g -> 'events'), jsonb_array_length(g -> 'balance'), jsonb_array_length(g -> 'pnl'),
    rtrim(verdicts, ', ');
  raise notice 'the cases that must fail: %', rtrim(cases, '; ');
end
$test$;

-- ---------------------------------------------------------------- 3. what to expect, in a world of its own
do $test$
declare w bigint; g bigint; a1 bigint; a3 bigint; r bigint; rot1 bigint; rot2 bigint; rot3 bigint; rot4 bigint; rot5 bigint; rot6 bigint;
  t timestamptz := '2030-03-06 02:00+00'; dow smallint; rid bigint; e jsonb; i int;
begin
  perform set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'capture checks test', true);
  dow := extract(isodow from t at time zone 'UTC')::smallint;
  insert into public.airports (code, utc_offset) values ('ZY1', 0.00), ('ZY2', 0.00) on conflict (code) do update set utc_offset = excluded.utc_offset;
  insert into public.worlds (name, game_host, kind) values ('capture checks test', 'capture-checks.test', 'exclusive') returning id into w;
  insert into public.settings (world_id, airline_id, key, value, unit, description)
  select w, null, s.key, s.value, s.unit, s.description from public.settings s
    join public.worlds x on x.id = s.world_id and x.is_default where s.airline_id is null;
  insert into public.groups (world_id, name, kind) values (w, 'ours', 'ours') returning id into g;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990301, 'Verdict One', 'One', 'VA', 'ZY1', true, 1) returning id into a1;
  insert into public.airlines (world_id, group_id, game_id, planner_name, public_name, iata_code, home_airport_code, active, position)
  values (w, g, 990303, 'Verdict Three', 'Three', 'VC', 'ZY1', true, 3) returning id into a3;
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a1, 'ZY1', 'ZY2', 1000, 'research') returning id into r;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r, null) returning id into rot1;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r, null) returning id into rot2;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r, (t at time zone 'UTC')::date - 1) returning id into rot3;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r, (t at time zone 'UTC')::date - 2) returning id into rot4;
  -- in the 24 hours to 02:00: 06:00 and 23:00 daily (one each), 01:00 on the page's weekday only (one), 03:00 on that
  -- weekday only (after the page: none), 12:00 daily launched the day before the page (its 12:00 in the window is on its
  -- launch day, which doesn't count: none), launched two days before (one): 4
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min) values
    (w, a1, rot1, 1, 101, 'ZY1', 'ZY2', '{1,2,3,4,5,6,7}', 360, 120), (w, a1, rot1, 2, 102, 'ZY2', 'ZY1', '{1,2,3,4,5,6,7}', 1380, 120),
    (w, a1, rot2, 1, 103, 'ZY1', 'ZY2', array[dow], 60, 120), (w, a1, rot2, 2, 104, 'ZY2', 'ZY1', array[dow], 180, 120),
    (w, a1, rot3, 1, 105, 'ZY1', 'ZY2', '{1,2,3,4,5,6,7}', 720, 120), (w, a1, rot4, 1, 107, 'ZY1', 'ZY2', '{1,2,3,4,5,6,7}', 720, 120);
  rid := pg_temp.cs_raw(w, a1, 'Verdict One', 'loads', '/test', '[]', t);
  e := private.capture_expect(rid);
  assert (e ->> 'scheduled')::int = 4, 'a loads page''s window should hold 4 of One''s flights, not ' || coalesce(e ->> 'scheduled', 'none') || ': ' || e::text;
  -- an aircraft that hasn't flown yet doesn't count (15 Oct: aircraft filed on the 13th hadn't started); once a capture
  -- before the page names it flying, its legs count
  insert into public.aircraft (world_id, airline_id, registration, status) values (w, a1, 'VA-NEW', 'active') returning id into rot5;
  insert into public.rotations (world_id, airline_id, route_id, launched_on) values (w, a1, r, null) returning id into rot6;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, aircraft_id, days_utc, dep_utc_min, block_min) values
    (w, a1, rot6, 1, 109, 'ZY1', 'ZY2', rot5, '{1,2,3,4,5,6,7}', 360, 120);
  e := private.capture_expect(rid);
  assert (e ->> 'scheduled')::int = 4, 'an aircraft that hasn''t flown should not count, so still 4, not ' || coalesce(e ->> 'scheduled', 'none') || ': ' || e::text;
  insert into public.game_flights (world_id, airline_id, game_date, flight_no, registration, eco_pct, loads_captured_at)
  values (w, a1, (t at time zone 'UTC')::date - 2, '109', 'VA-NEW', 90, t - interval '2 days');
  e := private.capture_expect(rid);
  assert (e ->> 'scheduled')::int = 5, 'once a capture has seen it flying, its leg should count: 5, not ' || coalesce(e ->> 'scheduled', 'none') || ': ' || e::text;
  delete from public.game_flights where world_id = w and registration = 'VA-NEW';
  delete from public.flight_legs where rotation_id = rot6;
  delete from public.rotations where id = rot6;
  delete from public.aircraft where id = rot5;
  -- the statement's recent nights: 7 earlier capture days count (their latest page each); the page's own day and older
  -- nights don't
  for i in 1..9 loop
    perform pg_temp.cs_raw(w, a1, 'Verdict One', 'statement', '/test',
      (select jsonb_agg(jsonb_build_array('', '05.03. 08:00', 'line', '1 AS$ C')) from generate_series(1, (array[200, 300, 100, 110, 120, 130, 140, 9000, 9000])[i]))
        || '[["Total", "", ""]]'::jsonb,
      t - make_interval(days => i) + interval '1 hour');
  end loop;
  perform pg_temp.cs_raw(w, a1, 'Verdict One', 'statement', '/test', (select jsonb_agg(jsonb_build_array('05.03. 08:00', 'line', '1 AS$ C')) from generate_series(1, 50)),
                         t - interval '1 day');   -- earlier the same capture day as the 200: the later page counts
  perform pg_temp.cs_raw(w, a1, 'Verdict One', 'statement', '/test', '[["05.03. 08:00", "line", "1 AS$ C"]]', t - interval '1 minute');   -- the page's own day
  rid := pg_temp.cs_raw(w, a1, 'Verdict One', 'statement', '/test', '[]', t);
  e := private.capture_expect(rid);
  assert (e ->> 'median_lines')::numeric = 130 and (e ->> 'nights')::int = 7,
    'the statement''s recent nights should be 7 with a median of 130 lines: ' || e::text;
  insert into t_cc values ('w', w::text), ('a3', a3::text);
  raise notice 'what to expect: 4 flights in a loads page''s window (weekdays, the 24 hours, each rotation from the day after it launched, an aircraft once it has flown); a statement''s median of 130 lines over its 7 latest earlier nights';
end
$test$;

-- ---------------------------------------------------------------- 4. through capture_ingest(), signed out
do $setup$
declare w bigint := (select v::bigint from t_cc where k = 'w'); a3 bigint := (select v::bigint from t_cc where k = 'a3'); r bigint; rot bigint;
begin
  insert into public.capture_keys (label, key_hash, world_id) values ('capture checks test', extensions.crypt('capture-checks-key', extensions.gen_salt('bf')), w);
  insert into public.routes (world_id, airline_id, hub_code, dest_code, distance_km, source) values (w, a3, 'ZY1', 'ZY2', 1000, 'research') returning id into r;
  -- four flights a day, every day: four in any page's window
  insert into public.rotations (world_id, airline_id, route_id) values (w, a3, r) returning id into rot;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min) values
    (w, a3, rot, 1, 301, 'ZY1', 'ZY2', '{1,2,3,4,5,6,7}', 300, 120), (w, a3, rot, 2, 302, 'ZY2', 'ZY1', '{1,2,3,4,5,6,7}', 1020, 120);
  insert into public.rotations (world_id, airline_id, route_id) values (w, a3, r) returning id into rot;
  insert into public.flight_legs (world_id, airline_id, rotation_id, leg_no, flight_no, origin_code, dest_code, days_utc, dep_utc_min, block_min) values
    (w, a3, rot, 1, 303, 'ZY1', 'ZY2', '{1,2,3,4,5,6,7}', 540, 120), (w, a3, rot, 2, 304, 'ZY2', 'ZY1', '{1,2,3,4,5,6,7}', 1260, 120);
  insert into t_cc values ('loads4', (select jsonb_agg(pg_temp.loads_row(300 + i, now() - make_interval(hours => i)))::text from generate_series(1, 4) i)),
                          ('loads2', (select jsonb_agg(pg_temp.loads_row(300 + i, now() - make_interval(hours => i)))::text from generate_series(1, 2) i));
end
$setup$;

set local role anon;
do $test$
declare r jsonb; k text := 'capture-checks-key'; d text := to_char(now() at time zone 'UTC', 'DD.MM.');
begin
  r := public.capture_ingest(k, '990303', 'events', '/test', jsonb_build_array(jsonb_build_array(to_char(now() at time zone 'UTC', 'Dy, ') || d, '10:00', 'Leasing rate', '', '1,000 AS$', '5,000 AS$')));
  assert r #>> '{verdict,verdict}' = 'ok' and r #>> '{verdict,note}' = 'events 1 row', 'the events page''s reply: ' || r::text;
  r := public.capture_ingest(k, '990303', 'statement', '/test', jsonb_build_array(
         jsonb_build_array(d || ' 08:00', 'Passenger transport income', '20,000 AS$ C'),
         jsonb_build_array(d || ' 08:00', 'On-board services (ZY1-ZY2)', '1,000 AS$ D')));
  assert r #>> '{verdict,verdict}' = 'ok' and r #>> '{verdict,note}' = 'statement 2 lines', 'the statement''s reply: ' || r::text;
  r := public.capture_ingest(k, '990303', 'pnl', '/test', '[["Revenue", "1,000 AS$", "900 AS$", "5,000 AS$"]]');
  assert r #>> '{verdict,verdict}' = 'ok', 'the income statement''s reply: ' || r::text;
  r := public.capture_ingest(k, '990303', 'balance', '/test', '[["1000", "Aircraft", "5,000 AS$", "2800", "Cash", "1,000,000 AS$"]]');
  assert r #>> '{verdict,verdict}' = 'ok' and (r #>> '{verdict,cash}')::boolean, 'the balance sheet''s reply: ' || r::text;
  r := public.capture_ingest(k, '990303', 'loads', '/test', (select v::jsonb from t_cc where t_cc.k = 'loads4'));
  assert r #>> '{verdict,verdict}' = 'ok' and (r #>> '{verdict,scheduled}')::int = 4 and r -> 'count' = '4'::jsonb, 'the loads page''s reply: ' || (r - 'airline_verdict')::text;
  -- the capture panel prints "<airline> · loads " + rows + " flights"
  assert 'Verdict Three · loads ' || (r ->> 'rows') || ' flights' = E'Verdict Three · loads 4 flights read\nVerdict Three: all good · loads 4 of 4 flights',
    'the panel would print: ' || ('Verdict Three · loads ' || (r ->> 'rows') || ' flights');
  r := public.capture_ingest(k, '990303', 'loads', '/test', (select v::jsonb from t_cc where t_cc.k = 'loads2'));
  assert r #>> '{verdict,verdict}' = 'short' and r #>> '{verdict,note}' = 'loads 2 of 4 flights' and r -> 'count' = '2'::jsonb,
    'half the flights on the loads page isn''t short: ' || (r - 'airline_verdict')::text;
  assert 'Verdict Three · loads ' || (r ->> 'rows') || ' flights' = E'Verdict Three · loads 2 flights read\nVerdict Three: short · loads 2 of 4 flights',
    'the panel would print: ' || ('Verdict Three · loads ' || (r ->> 'rows') || ' flights');
  r := public.capture_ingest(k, '990303', 'loads', '/test', '[{"not": "a row"}]');
  assert r ->> 'ok' = 'false' and r #>> '{verdict,verdict}' = 'broken'
     and 'Verdict Three · loads ' || (r ->> 'rows') || ' flights' like E'Verdict Three · loads didn''t read (parse: %)\nVerdict Three: broken · loads unreadable, 0 of 4 flights',
    'a loads page that doesn''t read: the panel would print ' || ('Verdict Three · loads ' || coalesce(r ->> 'rows', r ->> 'error') || ' flights');
end
$test$;
reset role;

do $test$
declare w bigint := (select v::bigint from t_cc where k = 'w'); a3 bigint := (select v::bigint from t_cc where k = 'a3'); c jsonb; x jsonb;
begin
  -- the latest loads page didn't read: capture_status() says so the moment it arrives
  c := public.capture_status(w, now());
  select e into x from jsonb_array_elements(c -> 'airlines') e where (e ->> 'airline_id')::bigint = a3;
  assert x ->> 'verdict' = 'broken' and x ->> 'verdict_words' like 'broken: loads didn''t read%' and x #>> '{verdicts,loads,verdict}' = 'broken'
     and x #>> '{verdicts,statement,verdict}' = 'ok' and x ->> 'last_at' is not null and x ->> 'verdict_at' = x ->> 'last_at',
    'capture_status() doesn''t give Three''s broken loads page: ' || coalesce(x::text, 'no airline');
  -- captured again, short: short; and again, complete: all good
  perform private.capture_store(w, '990303', 'loads', '/test', (select v::jsonb from t_cc where k = 'loads2'), now());
  select e into x from jsonb_array_elements(public.capture_status(w, now()) -> 'airlines') e where (e ->> 'airline_id')::bigint = a3;
  assert x ->> 'verdict' = 'short' and x ->> 'verdict_words' = 'short: loads 2 of 4 flights', 'a short page isn''t Three''s verdict: ' || x::text;
  perform private.capture_store(w, '990303', 'loads', '/test', (select v::jsonb from t_cc where k = 'loads4'), now());
  select e into x from jsonb_array_elements(public.capture_status(w, now()) -> 'airlines') e where (e ->> 'airline_id')::bigint = a3;
  assert x ->> 'verdict' = 'ok' and x ->> 'verdict_words' = 'all good', 'a complete capture isn''t all good: ' || x::text;
  -- an airline with no page has no verdict
  assert (select e -> 'verdict' from jsonb_array_elements(public.capture_status(w, now()) -> 'airlines') e where (e ->> 'airline_id')::bigint <> a3) = 'null'::jsonb,
    'an airline with no capture has a verdict';
  raise notice 'through capture_ingest(): each page''s verdict in its reply; the panel''s line "all good · loads 4 of 4 flights", "short · loads 2 of 4 flights" and "broken · loads unreadable"; capture_status() gives the latest verdict the moment a page arrives';
end
$test$;

-- ---------------------------------------------------------------- 5. system_status() on the copy
do $test$
declare d jsonb; w bigint := (select id from public.worlds where is_default); u jsonb; db bigint; n int; bad text;
begin
  d := public.system_status();
  assert d ?& array['capture', 'snapshot', 'backup', 'archive', 'cleanup', 'scan', 'usage'], 'system_status() lacks a part: ' || left(d::text, 300);
  assert (d ->> 'world_id')::bigint = w, 'system_status() isn''t for the default world';
  select count(*) into n from private.fig_airlines(w) where home_code is not null;
  assert jsonb_array_length(d -> 'capture') = n, format('system_status() lists %s airlines'' captures, the copy has %s', jsonb_array_length(d -> 'capture'), n);
  assert d #>> '{snapshot,day}' is not distinct from (select max(ad.day)::text from public.airline_days ad where ad.world_id = w and ad.taken_at <= now()),
    'the snapshot isn''t the latest day in airline_days: ' || coalesce(d ->> 'snapshot', 'none');
  assert d #>> '{backup,last_good,ran_at}' is not distinct from
         (select private.fig_ts(b.ran_at) from public.backup_runs b where b.ok and coalesce(b.kind, '') <> 'test' order by b.ran_at desc, b.id desc limit 1),
    'the last good backup isn''t backup_runs'' latest good run: ' || coalesce(d ->> 'backup', 'none');
  assert d #>> '{cleanup,at}' is not distinct from
         (select private.fig_ts(j.started_at) from public.job_runs j where j.job = 'cleanup' and j.status <> 'running' order by j.started_at desc, j.id desc limit 1),
    'the clean-up isn''t job_runs'' latest: ' || coalesce(d ->> 'cleanup', 'none');
  -- usage: each against its trigger, measured as the board shows it
  db := pg_database_size(current_database());
  select e into u from jsonb_array_elements(d -> 'usage') e where e ->> 'key' = 'database';
  assert (u ->> 'trigger_bytes')::bigint = 350 * 1024 * 1024 and abs((u ->> 'bytes')::bigint - db) <= db / 100,
    format('database size %s (trigger %s), measured %s', u ->> 'bytes', u ->> 'trigger_bytes', db);
  select e into u from jsonb_array_elements(d -> 'usage') e where e ->> 'key' = 'report_pdfs';
  assert (u ->> 'trigger_bytes')::bigint = 50 * 1024 * 1024
     and (u ->> 'bytes')::bigint = (select coalesce(sum(octet_length(r.pdf_b64)), 0) * 3 / 4 from public.site_reports r where r.pdf_b64 is not null),
    'the report PDFs'' size isn''t three quarters of their base64 text: ' || u::text;
  select e into u from jsonb_array_elements(d -> 'usage') e where e ->> 'key' = 'site_public';
  assert (u ->> 'trigger_bytes')::bigint = 500 * 1024 and (u ->> 'bytes')::bigint = octet_length(public.site_public()::text),
    'the website''s data isn''t site_public()''s size: ' || u::text;
  -- refused signed out, and signed in without being staff
  begin
    set local role anon;
    perform public.system_status();
    bad := 'signed out';
  exception when insufficient_privilege then null;
  end;
  reset role;
  begin
    set local role authenticated;
    perform public.system_status();
    bad := coalesce(bad || ', ', '') || 'signed in without being staff';
  exception when insufficient_privilege then null;
  end;
  reset role;
  assert bad is null, 'system_status() answered ' || bad;
  raise notice 'system_status(): % airlines'' captures; snapshot %; last good backup %; clean-up %; world scan %; database % MB of 350, report PDFs % MB of 50, the website''s data % KB of 500; refused signed out and to a signed-in account that isn''t staff',
    jsonb_array_length(d -> 'capture'), coalesce((d #>> '{snapshot,day}') || ' (' || (d #>> '{snapshot,source}') || ')', 'none'),
    coalesce(d #>> '{backup,last_good,ran_at}', 'none'), coalesce(d #>> '{cleanup,at}', 'none'), coalesce(d #>> '{scan,taken_at}', 'none'),
    round((d #>> '{usage,0,bytes}')::numeric / 1048576, 1), round((d #>> '{usage,1,bytes}')::numeric / 1048576, 1), round((d #>> '{usage,2,bytes}')::numeric / 1024);
end
$test$;

-- Matching money to loads (#13 build, pull request 3; design §3.8). Run by database/rehearse.sh on the copy of last
-- night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an
-- error that says which.
--   1. Hand-made pages for a test airline, in 2099 so nothing real is near, through the capture's own path:
--      a. a flight posted late (2 h 50 after its departure) still finds its loads, and a flight 40 minutes later isn't
--         taken by mistake;
--      b. a block whose loads aren't captured yet stays money-only, and joins its loads at the next capture (and the
--         next statement page, which lists the block again, keeps the pair);
--      c. two flights on one route close together (08:00 and 08:20, posted 08:25 and 08:40) don't swap;
--      d. flight 1001 flown on three days by two aircraft (as Kingfisher flies 1001/1002 on VT-AAA and VT-AAB) pairs
--         day by day; and where the statement names the aircraft (a maintenance line), it pairs with that aircraft's
--         flight even when another is nearer.
--   2. On the copy's own data, with the airports' offsets loaded from the planner's research the way #13's pull request
--      4 will load them: matching changes none of the three compatibility views; every pair is on one route, inside
--      the window and of one aircraft where the statement names it; and no pair that could only go one way is left
--      unmatched.

-- ---------------------------------------------------------------- 1. hand-made pages
-- statement lines of one flight: [time, text, amount], newest first, as the bank statement lists them
create function pg_temp.flight_lines(p_at timestamptz, p_route text, p_reg text default null) returns jsonb language sql as $$
  select (case when p_reg is null then '[]'::jsonb
               else jsonb_build_array(jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'),
                                                        'Maintenance of ' || p_reg || ' (90 maintenance ratio)', '5,000 AS$ D')) end)
         || jsonb_build_array(
              jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'), 'Passenger transport income', '20,000 AS$ C'),
              jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'), 'On-board services (' || p_route || ')', '1,000 AS$ D'),
              jsonb_build_array(to_char(p_at at time zone 'UTC', 'DD.MM. HH24:MI'), 'Air traffic control fee (' || p_route || ')', '500 AS$ D'))
$$;
-- one loads-page row, with the local times the game shows (departure at the origin's offset, arrival two hours later)
create function pg_temp.loads_row(p_no int, p_reg text, p_origin text, p_dest text, p_dep timestamptz, p_off_o int, p_off_d int)
returns jsonb language sql as $$
  select jsonb_build_array('MT ' || p_no, p_reg, p_origin,
           to_char((p_dep at time zone 'UTC') + make_interval(mins => p_off_o), 'DD.MM. HH24:MI') || ' LT', p_dest,
           to_char((p_dep at time zone 'UTC') + interval '2 hours' + make_interval(mins => p_off_d), 'DD.MM. HH24:MI') || ' LT',
           '100 AS$', '100 / 150 (67%)', '-', '-', '-', '-', '1 AS$', '1 / 10 (10%)', 'finished', 'details')
$$;
create temporary table t_m (k text primary key, v bigint) on commit drop;

do $test$
declare w bigint; al bigint; res jsonb; n int; f record;
  d1 timestamptz := '2099-03-10 00:00+00'; d2 timestamptz := '2099-03-11 00:00+00'; d3 timestamptz := '2099-03-12 00:00+00';
begin
  select id into w from public.worlds where is_default;
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code, active)
  select w, g.id, 999013, 'Matching Test Air', 'MT', false from public.groups g where g.world_id = w and g.kind = 'ours' order by g.id limit 1
  returning id into al;
  insert into t_m values ('airline', al);
  -- three airports of our own making, with their offsets: +5:30, −5:00 and 0
  insert into public.airports (code, utc_offset) values ('QQA', 5.5), ('QQB', -5), ('QQC', 0);

  -- the first capture, the evening of 10 Mar: the statement and the loads page
  res := private.capture_store(w, '999013', 'statement', '/test', '[["Date", "Text", "Amount"]]'::jsonb
    || pg_temp.flight_lines(d1 + interval '18 hours 5 minutes', 'QQA-QQB')                -- b. MT 105, loads not on this page yet
    || pg_temp.flight_lines(d1 + interval '12 hours 30 minutes', 'QQC-QQA')               -- d. a block with no maintenance line
    || pg_temp.flight_lines(d1 + interval '12 hours 12 minutes', 'QQC-QQA', 'MT-AAA')     -- d. names MT-AAA
    || pg_temp.flight_lines(d1 + interval '8 hours 40 minutes', 'QQC-QQA')                -- c. MT 203, posted 20 minutes late
    || pg_temp.flight_lines(d1 + interval '8 hours 25 minutes', 'QQC-QQA')                -- c. MT 201, posted 25 minutes late
    || pg_temp.flight_lines(d1 + interval '8 hours 4 minutes', 'QQA-QQC')                 -- a. MT 103, on time
    || pg_temp.flight_lines(d1 + interval '7 hours 20 minutes', 'QQA-QQC')                -- a. MT 101, 2 h 50 late
    || pg_temp.flight_lines(d1 + interval '6 hours 7 minutes', 'QQA-QQB'),                -- d. MT 1001, day 1
    d1 + interval '23 hours', false);
  assert (res ->> 'ok')::boolean, 'the first statement page wasn''t taken: ' || res::text;
  res := private.capture_store(w, '999013', 'loads', '/test', '[["Flight", "Aircraft"]]'::jsonb || jsonb_build_array(
      pg_temp.loads_row(101, 'MT-AAC', 'QQA', 'QQC', d1 + interval '4 hours 30 minutes', 330, 0),
      pg_temp.loads_row(103, 'MT-AAD', 'QQA', 'QQC', d1 + interval '8 hours', 330, 0),
      pg_temp.loads_row(201, 'MT-AAE', 'QQC', 'QQA', d1 + interval '8 hours', 0, 330),
      pg_temp.loads_row(203, 'MT-AAF', 'QQC', 'QQA', d1 + interval '8 hours 20 minutes', 0, 330),
      pg_temp.loads_row(1101, 'MT-AAA', 'QQC', 'QQA', d1 + interval '12 hours', 0, 330),
      pg_temp.loads_row(1103, 'MT-AAB', 'QQC', 'QQA', d1 + interval '12 hours 10 minutes', 0, 330),
      pg_temp.loads_row(1001, 'MT-AAA', 'QQA', 'QQB', d1 + interval '6 hours', 330, -300)),
    d1 + interval '23 hours 1 minute', false);
  assert (res ->> 'ok')::boolean, 'the first loads page wasn''t taken: ' || res::text;

  -- a. the late flight finds its loads; the one 40 minutes after it isn't taken by mistake
  select * into f from public.game_flights where airline_id = al and posted_at = d1 + interval '7 hours 20 minutes';
  assert f.flight_no = 101, format('the block posted 2 h 50 late matched %s, not MT 101', coalesce(f.flight_no::text, 'nothing'));
  assert f.dep_at = d1 + interval '4 hours 30 minutes' and f.registration = 'MT-AAC' and f.eco_pax = 100,
    'the late flight didn''t take its loads';
  assert (select flight_no from public.game_flights where airline_id = al and posted_at = d1 + interval '8 hours 4 minutes') = 103,
    'MT 103 didn''t match its own block';
  -- b. money-only, for now
  select * into f from public.game_flights where airline_id = al and posted_at = d1 + interval '18 hours 5 minutes';
  assert f.flight_no is null and f.dep_at = f.posted_at and f.origin_code = 'QQA' and f.dest_code = 'QQB' and f.income_total = 20000,
    'a block with no loads yet isn''t a money-only row';
  -- c. two flights close together on one route keep their order
  assert (select flight_no from public.game_flights where airline_id = al and posted_at = d1 + interval '8 hours 25 minutes') = 201
     and (select flight_no from public.game_flights where airline_id = al and posted_at = d1 + interval '8 hours 40 minutes') = 203,
    'two flights close together on one route were swapped (or not matched)';
  -- d. the aircraft named by the statement wins over the nearer flight
  assert (select flight_no from public.game_flights where airline_id = al and posted_at = d1 + interval '12 hours 12 minutes') = 1101,
    'the block naming MT-AAA didn''t match MT-AAA''s flight';
  assert (select flight_no from public.game_flights where airline_id = al and posted_at = d1 + interval '12 hours 30 minutes') = 1103,
    'the next block didn''t match the other aircraft''s flight';

  -- the next evening, 11 Mar: the statement lists 10 Mar again with 11 Mar, and the loads page now has MT 105 and
  -- day 2 of MT 1001, flown by the other aircraft
  res := private.capture_store(w, '999013', 'statement', '/test', '[["Date", "Text", "Amount"]]'::jsonb
    || pg_temp.flight_lines(d2 + interval '6 hours 7 minutes', 'QQA-QQB', 'MT-AAB')       -- d. MT 1001, day 2, names MT-AAB
    || pg_temp.flight_lines(d1 + interval '18 hours 5 minutes', 'QQA-QQB')
    || pg_temp.flight_lines(d1 + interval '12 hours 30 minutes', 'QQC-QQA')
    || pg_temp.flight_lines(d1 + interval '12 hours 12 minutes', 'QQC-QQA', 'MT-AAA')
    || pg_temp.flight_lines(d1 + interval '8 hours 40 minutes', 'QQC-QQA')
    || pg_temp.flight_lines(d1 + interval '8 hours 25 minutes', 'QQC-QQA')
    || pg_temp.flight_lines(d1 + interval '8 hours 4 minutes', 'QQA-QQC')
    || pg_temp.flight_lines(d1 + interval '7 hours 20 minutes', 'QQA-QQC')
    || pg_temp.flight_lines(d1 + interval '6 hours 7 minutes', 'QQA-QQB'),
    d2 + interval '23 hours', false);
  assert (res ->> 'ok')::boolean, 'the second statement page wasn''t taken: ' || res::text;
  res := private.capture_store(w, '999013', 'loads', '/test', '[["Flight", "Aircraft"]]'::jsonb || jsonb_build_array(
      pg_temp.loads_row(105, 'MT-AAG', 'QQA', 'QQB', d1 + interval '18 hours', 330, -300),
      pg_temp.loads_row(1001, 'MT-AAB', 'QQA', 'QQB', d2 + interval '6 hours', 330, -300)),
    d2 + interval '23 hours 1 minute', false);
  -- the third evening: day 3 of MT 1001, back on MT-AAA
  res := private.capture_store(w, '999013', 'statement', '/test', '[["Date", "Text", "Amount"]]'::jsonb
    || pg_temp.flight_lines(d3 + interval '6 hours 9 minutes', 'QQA-QQB')
    || pg_temp.flight_lines(d2 + interval '6 hours 7 minutes', 'QQA-QQB', 'MT-AAB'),
    d3 + interval '23 hours', false);
  res := private.capture_store(w, '999013', 'loads', '/test', '[["Flight", "Aircraft"]]'::jsonb || jsonb_build_array(
      pg_temp.loads_row(1001, 'MT-AAA', 'QQA', 'QQB', d3 + interval '6 hours', 330, -300)),
    d3 + interval '23 hours 1 minute', false);

  -- b. joined at the next capture, and the pairs made the evening before were kept through the second statement page
  select * into f from public.game_flights where airline_id = al and posted_at = d1 + interval '18 hours 5 minutes';
  assert f.flight_no = 105 and f.dep_at = d1 + interval '18 hours' and f.registration = 'MT-AAG',
    'the money-only block didn''t join its loads when they came';
  select count(*) into n from public.game_flights where airline_id = al and (flight_no is null or posted_at is null);
  assert n = 0, format('%s rows of the test airline are still one-sided', n);
  -- d. day by day, each on its own aircraft
  select count(*) into n from public.game_flights
   where airline_id = al and flight_no = 1001 and posted_at - dep_at between interval '7 minutes' and interval '9 minutes'
     and registration = case when game_date = '2099-03-11' then 'MT-AAB' else 'MT-AAA' end;
  assert n = 3, format('MT 1001 paired on %s of its 3 days', n);
  -- every statement line of the test airline points at its flight, and the views see the flights as before
  assert not exists (select 1 from public.game_statement where airline_id = al and flight_id is null), 'a flight line isn''t tied to its flight';
  assert (select count(*) from public.game_flight_pnl where airline = 'Matching Test Air') = 10, 'game_flight_pnl doesn''t show the 10 blocks';
  assert (select count(*) from public.game_loads where airline = 'Matching Test Air') = 10, 'game_loads doesn''t show the 10 loads rows';
end
$test$;

-- ---------------------------------------------------------------- 2. the copy's own data, with offsets
do $test$
declare w bigint; n bigint; bad text; res jsonb; v_blocks bigint; v_loads bigint;
begin
  select id into w from public.worlds where is_default;
  delete from public.game_statement where airline_id = (select v from t_m where k = 'airline');
  delete from public.game_flights where airline_id = (select v from t_m where k = 'airline');
  if not exists (select 1 from public.planner_data where key = 'DATA' and value ? 'utc') then
    raise notice 'matching on the copy: skipped, the copy has no route research with UTC offsets';
    return;
  end if;
  -- the offsets as the planner has them (its research, with its own corrections on top), for every airport the
  -- capture has seen
  insert into public.airports (code, utc_offset)
  select x.code, coalesce(nullif(s.json::jsonb #>> array['ref', 'utcOverrides', x.code], '')::numeric, (d.value -> 'utc' ->> x.code)::numeric)
    from (select origin_code as code from public.game_flights union select dest_code from public.game_flights) x
    join public.planner_data d on d.key = 'DATA' and d.value -> 'utc' ? x.code
    left join public.planner_state s on s.id = 'main'
   where x.code is not null
  on conflict (code) do update set utc_offset = excluded.utc_offset;

  create temporary table t_v_loads on commit drop as select * from public.game_loads;
  create temporary table t_v_pnl on commit drop as select * from public.game_flight_pnl;
  create temporary table t_v_ops on commit drop as select * from public.game_ops_recent;
  select count(*) filter (where posted_at is not null), count(*) filter (where flight_no is not null) into v_blocks, v_loads from public.game_flights;
  res := private.capture_refresh(w);

  -- matching changes none of the views
  select count(*) into n from ((select * from t_v_loads except all select * from public.game_loads)
                               union all (select * from public.game_loads except all select * from t_v_loads)) x;
  assert n = 0, format('matching changed game_loads in %s rows', n);
  select count(*) into n from ((select * from t_v_pnl except all select * from public.game_flight_pnl)
                               union all (select * from public.game_flight_pnl except all select * from t_v_pnl)) x;
  assert n = 0, format('matching changed game_flight_pnl in %s rows', n);
  select count(*) into n from ((select * from t_v_ops except all select * from public.game_ops_recent)
                               union all (select * from public.game_ops_recent except all select * from t_v_ops)) x;
  assert n = 0, format('matching changed game_ops_recent in %s rows', n);

  -- every pair is inside the window, on one route, and of one aircraft where the statement names it
  select count(*) into n from public.game_flights f
   where f.flight_no is not null and f.posted_at is not null
     and (f.posted_at - f.dep_at not between interval '-30 minutes' and interval '3 hours' or f.statement_routes <> 1
          or (f.maint_registration is not null and f.registration is distinct from f.maint_registration));
  assert n = 0, format('%s pairs break the rules', n);

  -- no pair that could only go one way is left: a block with exactly one possible loads row, which has exactly one
  -- possible block, must have been joined
  with mo as (select * from public.game_flights where flight_no is null and posted_at is not null and statement_routes = 1),
  lo as (select * from public.game_flights where posted_at is null and flight_no is not null and dep_at is not null),
  c as (select mo.id as mid, lo.id as lid from mo join lo on lo.airline_id = mo.airline_id and lo.origin_code = mo.origin_code
          and lo.dest_code = mo.dest_code and mo.posted_at - lo.dep_at between interval '-30 minutes' and interval '3 hours'
          and (mo.maint_registration is null or lo.registration is null or mo.maint_registration = lo.registration))
  select count(*) into n from c join mo on mo.id = c.mid join lo on lo.id = c.lid
   where (select count(*) from c c2 where c2.mid = c.mid) = 1 and (select count(*) from c c3 where c3.lid = c.lid) = 1
     -- (unless joining them would cross a pair already made on that route, which time order rules out)
     and not exists (select 1 from public.game_flights x
                      where x.airline_id = mo.airline_id and x.flight_no is not null and x.posted_at is not null
                        and x.origin_code = mo.origin_code and x.dest_code = mo.dest_code
                        and ((x.posted_at < mo.posted_at and x.dep_at > lo.dep_at) or (x.posted_at > mo.posted_at and x.dep_at < lo.dep_at)));
  assert n = 0, format('%s blocks were left unmatched although only one flight could be theirs', n);

  raise notice 'matching on the copy (offsets from the planner''s research): % statement blocks and % loads rows; % matched, % blocks and % loads rows left one-sided',
    v_blocks, v_loads, (res ->> 'matched'),
    (select count(*) from public.game_flights where flight_no is null),
    (select count(*) from public.game_flights where posted_at is null);
end
$test$;

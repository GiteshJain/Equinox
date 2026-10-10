-- The capture data in the new model (#13 build, pull request 3): what the planner, the website and the scripts read is
-- exactly what it was before the pending changes. Compares against the outputs database/tests/before/capture_outputs.sql
-- saved before the migrations ran (rehearsal_before). Run by database/rehearse.sh on the copy of last night's backup,
-- inside a transaction that is rolled back. A failed check stops with an error that says which.
--   1. game_loads, game_flight_pnl and game_ops_recent: the same rows, row by row, every column (numbers by value).
--      One allowed change, from 20261010180000 (10 Oct): payments that aren't flights (salaries above all) leave the
--      two money views. game_flight_pnl may lose whole rows that are exactly such a payment's block, and
--      game_ops_recent's costs and income may drop by exactly those payments within its 24 hours. Nothing else.
--   2. export_capture() (every captured row), export_for_report('planner') and site_public(): the same JSON, the rows
--      of each list in any order. export_capture()'s pnl and ops come straight from the two money views: they must
--      equal those views as they are now.
--   3. planner_loads: unchanged.
--   4. Every statement line is in exactly one place: tied to a flight in game_flights, or a payment in game_payments;
--      every row of the old loads table (game_loads_before_13) is in game_loads.

do $test$
declare n bigint; bad text; s text := 'compat-test-' || gen_random_uuid(); a jsonb; b jsonb; k text;
begin
  assert to_regclass('rehearsal_before.outputs') is not null,
    'the outputs from before the changes weren''t saved (database/tests/before/capture_outputs.sql)';

  -- 1. the three views, row by row
  select count(*) into n from (
    (select * from rehearsal_before.game_loads except all select * from public.game_loads)
    union all
    (select * from public.game_loads except all select * from rehearsal_before.game_loads)) x;
  select string_agg(x.airline || ' ' || x.n, ', ') into bad from (
    select airline, count(*) n from ((select * from rehearsal_before.game_loads except all select * from public.game_loads)
                                     union all (select * from public.game_loads except all select * from rehearsal_before.game_loads)) d
     group by airline) x;
  assert n = 0, format('game_loads differs from before in %s rows (%s)', n, bad);

  -- nothing new or changed in game_flight_pnl
  select string_agg(x.airline || ' ' || x.n, ', ') into bad from (
    select airline, count(*) n from (select * from public.game_flight_pnl except all select * from rehearsal_before.game_flight_pnl) d
     group by airline) x;
  assert bad is null, 'game_flight_pnl has rows that weren''t there before (rows per airline): ' || bad;
  -- rows gone from it must each be exactly one payment's own block (a salary payment, say), never a flight
  select string_agg(d.airline || ' ' || d.ts, ', ') into bad
    from (select * from rehearsal_before.game_flight_pnl except all select * from public.game_flight_pnl) d
   where d.route is not null
      or not exists (select 1 from public.game_payments p join public.airlines al on al.id = p.airline_id
                      where al.planner_name = d.airline and p.paid_at = d.ts and coalesce(p.statement_blk::integer, 1) = d.blk
                        and p.kind <> 'other' and p.descr not ilike 'Week-end closing%' and p.descr not ilike 'Leasing rate%')
      or exists (select 1 from public.game_flights f join public.airlines al on al.id = f.airline_id
                  where al.planner_name = d.airline and f.posted_at = d.ts and f.statement_blk = d.blk);
  assert bad is null, 'game_flight_pnl lost rows that aren''t a payment''s own block: ' || bad;
  select count(*) into n from (select * from rehearsal_before.game_flight_pnl except all select * from public.game_flight_pnl) d;
  raise notice 'game_flight_pnl: % statement blocks before; % payment blocks left out (salaries and the like), every other block the same',
    (select count(*) from rehearsal_before.game_flight_pnl), n;

  -- game_ops_recent: the same rows, except that costs and income drop by exactly the payments the old wording let in
  -- (salaries under their new label) within each airline's 24 hours; its hours may move only then
  with left_out as (
    select al.planner_name as airline,
           coalesce(sum(case when p.side = 'C' then 0 else p.amount end), 0) as debit,
           coalesce(sum(case when p.side = 'C' then p.amount else 0 end), 0) as credit
      from rehearsal_before.game_ops_recent b
      join public.airlines al on al.planner_name = b.airline
      join public.game_payments p on p.airline_id = al.id
     where p.kind <> 'other' and p.paid_at > b.last_ts - interval '24 hours' and p.paid_at <= b.last_ts
       and p.descr not ilike 'Leasing rate%' and p.descr not ilike 'Week-end closing%' and p.descr not ilike '%deposit%'
       and p.descr not ilike '%purchase%' and p.descr not ilike '%cabin%' and p.descr not ilike '%configuration%'
     group by al.planner_name)
  select string_agg(coalesce(b.airline, a.airline), ', ') into bad
    from rehearsal_before.game_ops_recent b
    full join public.game_ops_recent a using (airline)
    left join left_out o on o.airline = b.airline
   where a.airline is null or b.airline is null
      or a.last_ts is distinct from b.last_ts or a.flights is distinct from b.flights
      or a.costs is distinct from b.costs - coalesce(o.debit, 0)
      or a.income is distinct from b.income - coalesce(o.credit, 0)
      or (o.airline is null and a.hours is distinct from b.hours);
  assert bad is null, 'game_ops_recent differs from before by more than the payments it now leaves out, for: ' || bad;

  -- 2. the functions' JSON (each list compared as a set of rows, since the order of a list was never fixed)
  insert into public.ingest_secret (secret) values (s);
  a := public.export_capture(s, 3650);
  select value into b from rehearsal_before.outputs where name = 'export_capture';
  assert (select array_agg(x order by x) from jsonb_object_keys(a) x) = (select array_agg(x order by x) from jsonb_object_keys(b) x),
    'export_capture() returns other parts than before';
  for k in select jsonb_object_keys(b) loop
    continue when k in ('pnl', 'ops');   -- checked against the views below
    select count(*) into n from (
      (select value from jsonb_array_elements(a -> k) except all select value from jsonb_array_elements(b -> k))
      union all
      (select value from jsonb_array_elements(b -> k) except all select value from jsonb_array_elements(a -> k))) x;
    assert n = 0, format('export_capture() %s differs from before in %s rows', k, n);
  end loop;
  select count(*) into n from (
    (select value from jsonb_array_elements(a -> 'pnl') except all
     select to_jsonb(f) from public.game_flight_pnl f where f.ts >= now() - make_interval(days => 3650))
    union all
    (select to_jsonb(f) from public.game_flight_pnl f where f.ts >= now() - make_interval(days => 3650) except all
     select value from jsonb_array_elements(a -> 'pnl'))) x;
  assert n = 0, format('export_capture() pnl differs from game_flight_pnl in %s rows', n);
  select count(*) into n from (
    (select value from jsonb_array_elements(a -> 'ops') except all select to_jsonb(o) from public.game_ops_recent o)
    union all
    (select to_jsonb(o) from public.game_ops_recent o except all select value from jsonb_array_elements(a -> 'ops'))) x;
  assert n = 0, format('export_capture() ops differs from game_ops_recent in %s rows', n);
  assert public.export_for_report(s, 'planner') = (select value from rehearsal_before.outputs where name = 'export_for_report planner'),
    'export_for_report(''planner'') differs from before';
  assert public.site_public() = (select value from rehearsal_before.outputs where name = 'site_public'),
    'site_public() differs from before';
  delete from public.ingest_secret where secret = s;

  -- 3. planner_loads
  select count(*) into n from (
    (select month, json, saved_at from rehearsal_before.planner_loads except all select month, json, saved_at from public.planner_loads)
    union all
    (select month, json, saved_at from public.planner_loads except all select month, json, saved_at from rehearsal_before.planner_loads)) x;
  assert n = 0, format('planner_loads changed in %s months', n);

  -- 4. nothing lost or counted twice
  select count(*) into n from public.game_statement s
   where (s.flight_id is not null)
         = exists (select 1 from public.game_payments p where p.airline_id = s.airline_id and p.paid_at = s.ts
                     and p.descr = s.descr and p.amount = s.amount and p.occ = s.occ);
  assert n = 0, format('%s statement lines are in both game_flights and game_payments, or in neither', n);
  select count(*) into n from public.game_payments p
   where not exists (select 1 from public.game_statement s where s.airline_id = p.airline_id and s.ts = p.paid_at
                       and s.descr = p.descr and s.amount = p.amount and s.occ = p.occ)
     and p.paid_at >= (select min(ts) from public.game_statement);
  assert n = 0, format('%s payments have no statement line', n);
  if to_regclass('public.game_loads_before_13') is not null then
    -- (from the oldest flight game_flights still holds: older months leave it with the monthly archive)
    select count(*) into n from public.game_loads_before_13 l
     where l.flight_date >= (select min(f.game_date) from public.game_flights f)
       and not exists (select 1 from public.game_loads v where v.airline = l.airline and v.flight_date = l.flight_date
                         and v.code = l.code and v.dep_time = l.dep_time);
    assert n = 0, format('%s rows of game_loads_before_13 aren''t in game_loads', n);
  end if;

  raise notice 'capture data, before and after: all checks passed';
end
$test$;

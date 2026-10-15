-- The capture data in the new model (#13 build, pull request 3): what the planner, the website and the scripts read is
-- exactly what it was before the pending changes. Compares against the outputs database/tests/before/capture_outputs.sql
-- saved before the migrations ran (rehearsal_before). Run by database/rehearse.sh on the copy of last night's backup,
-- inside a transaction that is rolled back. A failed check stops with an error that says which.
--   1. game_loads, game_flight_pnl and game_ops_recent: the same rows, row by row, every column (numbers by value).
--      One allowed change, from 20261010180000 (10 Oct): payments that aren't flights (salaries above all) leave the
--      two money views. game_flight_pnl may lose whole rows that are exactly such a payment's block, and
--      game_ops_recent's costs and income may drop by exactly those payments within its 24 hours. Nothing else.
--      Whether the change shows depends on the backup: one older than 20261010180000 still has those payments in its
--      "before" figures, a newer one doesn't. So each row is accepted either way (#13 pull request 6): game_flight_pnl
--      losing no rows, or only such blocks; a game_ops_recent row unchanged, or lower by exactly those payments. A
--      hand-made airline shows both paths (and that a figure off by anything else fails), whatever the backup's age.
--      The payments the pilot-training re-sort (20261015200000) names get their kinds from before back first, since
--      leaving those views is its purpose (pilot_training_test.sql).
--   2. export_capture() (every captured row): the same JSON, the rows of each list in any order. Its pnl and ops come
--      straight from the two money views: they must equal those views as they are now. One allowed change, from
--      20261011120000 (#13 pull request 6): a balance row's captured_at may move later, to the capture that gave its
--      figures (two captures on one UTC date); its figures may not change. (export_for_report('planner')
--      and site_public() were compared here until pull request 8 made them read the tables; website_scripts_outputs_test.sql
--      compares them now, with the differences that pull request allows.)
--   3. (planner_loads was compared here until the clean-up, build pull request 14, removed it.)
--   4. Every statement line is in exactly one place: tied to a flight in game_flights, or a payment in game_payments;
--      every row of the old loads table (game_loads_before_13) is in game_loads.

-- One game_ops_recent row against its figures from before the pending changes, from either side of 20261010180000:
-- 'unchanged' (the backup already had it: the same costs, income and hours), 'salaries left out' (it didn't: costs and
-- income lower by exactly the payments the old wording let in, within its 24 hours; the hours may move then), or null.
create function pg_temp.ops_path(a_costs numeric, a_income numeric, a_hours numeric, b_costs numeric, b_income numeric,
                                 b_hours numeric, p_debit numeric, p_credit numeric) returns text language sql immutable as $$
  select case when (a_costs, a_income, a_hours) is not distinct from (b_costs, b_income, b_hours) then 'unchanged'
              when coalesce(p_debit, 0) + coalesce(p_credit, 0) > 0
                   and (a_costs, a_income) is not distinct from (b_costs - coalesce(p_debit, 0), b_income - coalesce(p_credit, 0))
                then 'salaries left out' end
$$;

-- both paths on a hand-made airline: a flight and a salary line in its 24 hours. game_ops_recent leaves the salary out;
-- "before" figures that still had it (a backup older than 20261010180000) and figures that didn't (a newer one) are
-- both accepted; one off by anything else is not.
do $case$
declare al bigint; w bigint; t timestamptz := '2099-02-01 12:00+00'; r record;
begin
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code)
  select g.world_id, g.id, 999903, 'Compat Test Air', 'CQ'
    from public.groups g join public.worlds wd on wd.id = g.world_id and wd.is_default
   where g.kind = 'ours' order by g.id limit 1
  returning id, world_id into al, w;
  insert into public.game_flights (world_id, airline_id, posted_at, statement_blk, statement_routes, dep_at, pax_income, income_total, cost_total)
  values (w, al, t - interval '2 hours', 1, 1, t - interval '2 hours', 1000, 1000, 400);
  insert into public.game_payments (world_id, airline_id, paid_at, kind, descr, amount, side, occ, statement_blk)
  values (w, al, t - interval '1 hour', 'salaries', 'Payment of employee salaries', 300, 'D', 1, 1);
  select * into r from public.game_ops_recent where airline = 'Compat Test Air';
  assert r.costs = 400 and r.income = 1000, format('game_ops_recent counts the salary line: costs %s, income %s', r.costs, r.income);
  assert pg_temp.ops_path(r.costs, r.income, r.hours, r.costs + 300, r.income, r.hours, 300, 0) = 'salaries left out',
    'before figures that still had the salary line (an older backup) aren''t accepted';
  assert pg_temp.ops_path(r.costs, r.income, r.hours, r.costs, r.income, r.hours, 300, 0) = 'unchanged',
    'before figures that already left it out (a newer backup) aren''t accepted';
  assert pg_temp.ops_path(r.costs, r.income, r.hours, r.costs + 250, r.income, r.hours, 300, 0) is null
     and pg_temp.ops_path(r.costs, r.income, r.hours, r.costs + 300, r.income, r.hours, 0, 0) is null
     and pg_temp.ops_path(r.costs, r.income, r.hours + 1, r.costs, r.income, r.hours, 300, 0) is null,
    'figures off by something other than the salary lines are accepted';
  delete from public.game_payments where airline_id = al;
  delete from public.game_flights where airline_id = al;
  delete from public.airlines where id = al;
  raise notice 'game_ops_recent from either side of 20261010180000 (a hand-made airline): before figures with the salary line in, or already without it, both accepted; off by anything else, refused';
end
$case$;

do $test$
declare n bigint; bad text; s text := 'compat-test-' || gen_random_uuid(); v_paths text; a jsonb; b jsonb; k text; n_later bigint; n_earlier bigint;
begin
  assert to_regclass('rehearsal_before.outputs') is not null,
    'the outputs from before the changes weren''t saved (database/tests/before/capture_outputs.sql)';
  -- the pilot-training re-sort (20261015200000) takes those payments out of the two money views on purpose
  -- (pilot_training_test.sql checks it): they get their kinds from before the changes back here, rolled back with the
  -- test, so everything else must be as before. Once it is live, the copy has nothing for it to name.
  if to_regclass('rehearsal_before.payment_kinds') is not null then
    update public.game_payments p set kind = k.kind
      from rehearsal_before.payment_kinds k where k.id = p.id and p.kind is distinct from k.kind;
  end if;

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

  -- game_ops_recent: the same rows, either unchanged or with costs and income lower by exactly the payments the old
  -- wording let in (salaries under their new label) within each airline's 24 hours, as pg_temp.ops_path() says
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
      or pg_temp.ops_path(a.costs, a.income, a.hours, b.costs, b.income, b.hours, o.debit, o.credit) is null;
  assert bad is null, 'game_ops_recent differs from before by more than the payments it now leaves out, for: ' || bad;
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
  select string_agg(x.path || ' ' || x.n, ', ' order by x.path) into v_paths
    from (select pg_temp.ops_path(a.costs, a.income, a.hours, b.costs, b.income, b.hours, o.debit, o.credit) as path, count(*) as n
            from rehearsal_before.game_ops_recent b join public.game_ops_recent a using (airline)
            left join left_out o on o.airline = b.airline group by 1) x;
  raise notice 'game_ops_recent: every airline the same as before, or lower by exactly the salary lines (%)', v_paths;

  -- 2. the functions' JSON (each list compared as a set of rows, since the order of a list was never fixed)
  insert into public.ingest_secret (secret) values (s);
  a := public.export_capture(s, 3650);
  select value into b from rehearsal_before.outputs where name = 'export_capture';
  assert (select array_agg(x order by x) from jsonb_object_keys(a) x) = (select array_agg(x order by x) from jsonb_object_keys(b) x),
    'export_capture() returns other parts than before';
  for k in select jsonb_object_keys(b) loop
    continue when k in ('pnl', 'ops');   -- checked against the views below
    select count(*) into n from (
      (select value - case when k = 'balance' then 'captured_at' else '' end from jsonb_array_elements(a -> k)
       except all select value - case when k = 'balance' then 'captured_at' else '' end from jsonb_array_elements(b -> k))
      union all
      (select value - case when k = 'balance' then 'captured_at' else '' end from jsonb_array_elements(b -> k)
       except all select value - case when k = 'balance' then 'captured_at' else '' end from jsonb_array_elements(a -> k))) x;
    assert n = 0, format('export_capture() %s differs from before in %s rows', k, n);
  end loop;
  -- the balance rows' capture times: the same, or later (the two-captures fix of 20261011120000), never earlier
  select count(*) filter (where (na.value ->> 'captured_at')::timestamptz > (nb.value ->> 'captured_at')::timestamptz),
         count(*) filter (where (na.value ->> 'captured_at')::timestamptz < (nb.value ->> 'captured_at')::timestamptz)
    into n_later, n_earlier
    from jsonb_array_elements(a -> 'balance') na
    join jsonb_array_elements(b -> 'balance') nb
      on (na.value ->> 'airline', na.value ->> 'captured_on', na.value ->> 'account') = (nb.value ->> 'airline', nb.value ->> 'captured_on', nb.value ->> 'account');
  assert n_earlier = 0, format('export_capture() balance: %s rows'' capture times moved earlier', n_earlier);
  raise notice 'export_capture(): every part the same as before; % balance rows carry their figures'' own (later) capture time since the two-captures fix', n_later;
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
  -- export_for_report('planner') and site_public() read the tables since pull request 8: website_scripts_outputs_test.sql
  -- compares them with before, allowing site_public()'s new airlines key and the getters' differences
  delete from public.ingest_secret where secret = s;

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

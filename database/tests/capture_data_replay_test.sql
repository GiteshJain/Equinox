-- The capture data (#13 build, pull request 3): the new capture path produces what the backfill produced.
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says which.
-- Every raw page the copy keeps (game_capture_raw, 14 days) is replayed through the new path (private.capture_store:
-- find the airline, store the page, parse it, fold the statement, match), each at its own capture time, into emptied
-- capture tables. The result must equal what was there: game_flights (its loads side and its money side),
-- game_payments, game_events, game_balance, game_pnl and the statement lines. Twice: with the airline named as today's
-- userscript names it, then by its game ID as the new userscript sends it.
-- Only rows the kept pages can produce are compared: once older pages have rolled off, a row from before the oldest kept
-- page of its kind (for that airline) can't be rebuilt from them. On the night this pull request was rehearsed, every
-- row was (the oldest page was the first capture).

-- what the backfill and the capture wrote, by natural keys (ids, row times and flight ids aside)
create temporary table t_was_loads on commit drop as
  select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
         eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
         cargo_units, cargo_cap, cargo_rate, cargo_pct, loads_captured_at
    from public.game_flights where flight_no is not null;
create temporary table t_was_money on commit drop as
  select airline_id, posted_at, statement_blk, statement_routes, maint_registration, statement_pax, pax_income, cargo_income,
         fuel, onboard, handling, landing, atc, maintenance, income_total, cost_total, profit, money_captured_at, origin_code, dest_code
    from public.game_flights where posted_at is not null;
create temporary table t_was_payments on commit drop as
  select world_id, airline_id, paid_at, kind, registration, aircraft_id, descr, amount, side, occ, statement_blk from public.game_payments;
create temporary table t_was_statement on commit drop as
  select world_id, airline_id, airline, ts, descr, amount, side, route, pax, occ, blk, captured_at, flight_id is null as payment
    from public.game_statement;
create temporary table t_was_events on commit drop as select * from public.game_events;
create temporary table t_was_balance on commit drop as select * from public.game_balance;
create temporary table t_was_pnl on commit drop as select * from public.game_pnl;
-- the pages to replay, oldest first, and from when each airline's pages of each kind are kept
create temporary table t_pages on commit drop as
  select r.id, r.world_id, r.airline_id, r.airline, a.game_id, r.kind, r.page_url, r.rows, r.captured_at
    from public.game_capture_raw r join public.airlines a on a.id = r.airline_id
   where r.kind <> 'html';
create temporary table t_kept on commit drop as
  select airline_id, kind, min(captured_at) as since from t_pages group by airline_id, kind;
create temporary table t_report (pass text, part text, n bigint) on commit drop;

-- empties the capture tables, replays every page with the airline named one way, and compares
create function pg_temp.replay(p_pass text) returns void language plpgsql as $replay$
declare pg record; res jsonb; failed int := 0;
begin
  delete from public.game_statement; delete from public.game_flights; delete from public.game_payments;
  delete from public.game_events; delete from public.game_balance; delete from public.game_pnl;
  for pg in select * from t_pages order by captured_at, id loop
    res := private.capture_store(pg.world_id, case when p_pass = 'game id' then pg.game_id::text else pg.airline end,
                                 pg.kind, pg.page_url, pg.rows, pg.captured_at, false);
    if not coalesce((res ->> 'ok')::boolean, false) then failed := failed + 1; end if;
  end loop;
  insert into t_report values (p_pass, 'pages that failed', failed);

  -- statement lines: those from the kept pages' time on (an airline whose lines all came back is compared in full)
  create temporary table t_full on commit drop as
    select k.airline_id from t_kept k where k.kind = 'statement'
       and not exists (select airline_id, ts, descr, amount, occ from t_was_statement w where w.airline_id = k.airline_id
                       except
                       select airline_id, ts, descr, amount, occ from public.game_statement s where s.airline_id = k.airline_id);
  create temporary table t_stmt_since on commit drop as
    select k.airline_id, case when exists (select 1 from t_full f where f.airline_id = k.airline_id) then '-infinity'::timestamptz
                              else k.since end as since
      from t_kept k where k.kind = 'statement';
  insert into t_report select p_pass, 'statement lines', count(*) from (
    (select w.* from t_was_statement w join t_stmt_since k using (airline_id) where w.ts >= k.since
     except all
     select s.world_id, s.airline_id, s.airline, s.ts, s.descr, s.amount, s.side, s.route, s.pax, s.occ, s.blk, s.captured_at, s.flight_id is null
       from public.game_statement s)
    union all
    (select s.world_id, s.airline_id, s.airline, s.ts, s.descr, s.amount, s.side, s.route, s.pax, s.occ, s.blk, s.captured_at, s.flight_id is null
       from public.game_statement s join t_stmt_since k using (airline_id) where s.ts >= k.since
     except all
     select * from t_was_statement)) x;
  insert into t_report select p_pass, 'flights: money', count(*) from (
    (select w.* from t_was_money w join t_stmt_since k using (airline_id) where w.posted_at >= k.since
     except all
     select airline_id, posted_at, statement_blk, statement_routes, maint_registration, statement_pax, pax_income, cargo_income,
            fuel, onboard, handling, landing, atc, maintenance, income_total, cost_total, profit, money_captured_at, origin_code, dest_code
       from public.game_flights where posted_at is not null)
    union all
    (select f.airline_id, f.posted_at, f.statement_blk, f.statement_routes, f.maint_registration, f.statement_pax, f.pax_income,
            f.cargo_income, f.fuel, f.onboard, f.handling, f.landing, f.atc, f.maintenance, f.income_total, f.cost_total, f.profit,
            f.money_captured_at, f.origin_code, f.dest_code
       from public.game_flights f join t_stmt_since k using (airline_id) where f.posted_at >= k.since
     except all
     select * from t_was_money)) x;
  insert into t_report select p_pass, 'payments', count(*) from (
    (select w.* from t_was_payments w join t_stmt_since k using (airline_id) where w.paid_at >= k.since
     except all
     select world_id, airline_id, paid_at, kind, registration, aircraft_id, descr, amount, side, occ, statement_blk from public.game_payments)
    union all
    (select p.world_id, p.airline_id, p.paid_at, p.kind, p.registration, p.aircraft_id, p.descr, p.amount, p.side, p.occ, p.statement_blk
       from public.game_payments p join t_stmt_since k using (airline_id) where p.paid_at >= k.since
     except all
     select * from t_was_payments)) x;
  -- loads rows: those last written from the kept pages' time on
  insert into t_report select p_pass, 'flights: loads', count(*) from (
    (select w.* from t_was_loads w join t_kept k on k.airline_id = w.airline_id and k.kind = 'loads' where w.loads_captured_at >= k.since
     except all
     select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
            eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
            cargo_units, cargo_cap, cargo_rate, cargo_pct, loads_captured_at from public.game_flights where flight_no is not null)
    union all
    (select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
            eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
            cargo_units, cargo_cap, cargo_rate, cargo_pct, loads_captured_at from public.game_flights where flight_no is not null
     except all
     select * from t_was_loads)) x;
  -- events, balance sheet, income statement: rows first written from the kept pages' time on (a row first written
  -- before then is left out on both sides)
  insert into t_report select p_pass, 'events', count(*) from (
    (select w.* from t_was_events w join t_kept k on k.airline_id = w.airline_id and k.kind = 'events' where w.captured_at >= k.since
     except all select * from public.game_events)
    union all
    (select e.* from public.game_events e
      where not exists (select 1 from t_was_events w join t_kept k on k.airline_id = w.airline_id and k.kind = 'events'
                         where w.captured_at < k.since and w.airline = e.airline and w.event_date = e.event_date
                           and w.event_time = e.event_time and w.descr = e.descr)
     except all select * from t_was_events)) x;
  insert into t_report select p_pass, 'balance sheet', count(*) from (
    (select w.* from t_was_balance w join t_kept k on k.airline_id = w.airline_id and k.kind = 'balance' where w.captured_at >= k.since
     except all select * from public.game_balance)
    union all
    (select b.* from public.game_balance b
      where not exists (select 1 from t_was_balance w join t_kept k on k.airline_id = w.airline_id and k.kind = 'balance'
                         where w.captured_at < k.since and w.airline = b.airline and w.captured_on = b.captured_on and w.account = b.account)
     except all select * from t_was_balance)) x;
  insert into t_report select p_pass, 'income statement', count(*) from (
    (select w.* from t_was_pnl w join t_kept k on k.airline_id = w.airline_id and k.kind = 'pnl' where w.captured_at >= k.since
     except all select * from public.game_pnl)
    union all
    (select g.* from public.game_pnl g
      where not exists (select 1 from t_was_pnl w join t_kept k on k.airline_id = w.airline_id and k.kind = 'pnl'
                         where w.captured_at < k.since and w.airline = g.airline and w.captured_on = g.captured_on and w.line = g.line)
     except all select * from t_was_pnl)) x;
  drop table t_stmt_since;
  drop table t_full;
end
$replay$;

do $test$
declare bad text; v_pages bigint;
begin
  select count(*) into v_pages from t_pages;
  perform pg_temp.replay('name');
  perform pg_temp.replay('game id');
  select string_agg(r.pass || ': ' || r.part || ' ' || r.n, '; ' order by r.pass, r.part) into bad from t_report r where r.n > 0;
  assert bad is null, 'the replay differs from the backfill (rows that differ): ' || bad;
  raise notice 'replay: % pages, by name and by game ID, gave the same rows as the backfill (% flights'' money, % loads rows, % payments compared)',
    v_pages, (select count(*) from t_was_money), (select count(*) from t_was_loads), (select count(*) from t_was_payments);
end
$test$;

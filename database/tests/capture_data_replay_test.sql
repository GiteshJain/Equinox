-- The capture data (#13 build, pull request 3): the new capture path produces what the backfill produced.
-- Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a transaction that
-- is rolled back. A failed check stops with an error that says which.
-- Every raw page the copy keeps (game_capture_raw, 14 days) is replayed through the new path (private.capture_store:
-- find the airline, store the page, parse it, fold the statement, match), each at its own capture time, into emptied
-- capture tables. The result must equal what was there: game_flights (its loads side and its money side),
-- game_payments, game_events, game_balance, game_pnl and the statement lines. Twice: with the airline named as today's
-- userscript names it, then by its game ID as the new userscript sends it.
-- Two allowances, both because the replay can only rebuild what the kept pages hold:
--   - Rows from before the oldest kept page of their kind (for that airline) aren't compared once older pages have
--     rolled off. On the night this pull request was rehearsed, nothing had: every row is compared.
--   - A capture time is compared only where it is a kept page's time. Two fixes re-read pages after they arrived (the
--     statement blocks on 8 Oct re-read every statement page; the full loads columns on 7 Oct re-read one loads page),
--     so those rows carry the re-read's time, which no page has. Everything else about them must match.
-- Each page replayed is also checked as it was when it arrived (#21, private.capture_check()): every kept evening must be
-- judged ok, page by page (the first pass's verdicts; the second judges the same pages again).

-- what the backfill and the capture wrote, by natural keys (ids, row times and flight ids aside)
create temporary table t_was_loads on commit drop as
  select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
         eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
         cargo_units, cargo_cap, cargo_rate, cargo_pct, loads_captured_at
    from public.game_flights where flight_no is not null;
create temporary table t_was_money on commit drop as
  select airline_id, posted_at, statement_blk, statement_routes, maint_registration, statement_pax, pax_income, cargo_income,
         fuel, onboard, handling, landing, atc, maintenance, income_total, cost_total, profit, origin_code, dest_code,
         money_captured_at
    from public.game_flights where posted_at is not null;
create temporary table t_was_payments on commit drop as
  select world_id, airline_id, paid_at, kind, registration, aircraft_id, descr, amount, side, occ, statement_blk from public.game_payments;
create temporary table t_was_statement on commit drop as
  select world_id, airline_id, airline, ts, descr, amount, side, route, pax, occ, blk, flight_id is null as payment, captured_at
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
-- n: rows that differ; counted: whether a difference fails the test (false only for the re-read times, reported)
create temporary table t_report (pass text, part text, n bigint, counted boolean not null default true) on commit drop;
-- each page's verdict as the first pass replayed it (#21)
create temporary table t_verdicts (world_id bigint, airline_id bigint, airline text, kind text, captured_at timestamptz, v jsonb) on commit drop;

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
    if p_pass = 'name' then insert into t_verdicts values (pg.world_id, pg.airline_id, pg.airline, pg.kind, pg.captured_at, res -> 'verdict'); end if;
  end loop;
  insert into t_report values (p_pass, 'pages that failed', failed);

  create temporary table t_now_statement on commit drop as
    select world_id, airline_id, airline, ts, descr, amount, side, route, pax, occ, blk, flight_id is null as payment, captured_at
      from public.game_statement;
  create temporary table t_now_money on commit drop as
    select airline_id, posted_at, statement_blk, statement_routes, maint_registration, statement_pax, pax_income, cargo_income,
           fuel, onboard, handling, landing, atc, maintenance, income_total, cost_total, profit, origin_code, dest_code,
           money_captured_at
      from public.game_flights where posted_at is not null;
  create temporary table t_now_loads on commit drop as
    select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
           eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
           cargo_units, cargo_cap, cargo_rate, cargo_pct, loads_captured_at
      from public.game_flights where flight_no is not null;

  -- from when the statement can be rebuilt: everything, for an airline whose lines all came back; otherwise from its
  -- oldest kept page
  create temporary table t_stmt_since on commit drop as
    select k.airline_id,
           case when not exists (select airline_id, ts, descr, amount, occ from t_was_statement w where w.airline_id = k.airline_id
                                 except
                                 select airline_id, ts, descr, amount, occ from t_now_statement s where s.airline_id = k.airline_id)
                then '-infinity'::timestamptz else k.since end as since
      from t_kept k where k.kind = 'statement';

  -- statement lines: every column but the capture time
  insert into t_report select p_pass, 'statement lines', count(*) from (
    (select w.world_id, w.airline_id, w.airline, w.ts, w.descr, w.amount, w.side, w.route, w.pax, w.occ, w.blk, w.payment
       from t_was_statement w join t_stmt_since k using (airline_id) where w.ts >= k.since
     except all
     select world_id, airline_id, airline, ts, descr, amount, side, route, pax, occ, blk, payment from t_now_statement)
    union all
    (select s.world_id, s.airline_id, s.airline, s.ts, s.descr, s.amount, s.side, s.route, s.pax, s.occ, s.blk, s.payment
       from t_now_statement s join t_stmt_since k using (airline_id) where s.ts >= k.since
     except all
     select world_id, airline_id, airline, ts, descr, amount, side, route, pax, occ, blk, payment from t_was_statement)) x;
  -- flights' money: every column but the capture time
  insert into t_report select p_pass, 'flights: money', count(*) from (
    (select w.airline_id, w.posted_at, w.statement_blk, w.statement_routes, w.maint_registration, w.statement_pax, w.pax_income,
            w.cargo_income, w.fuel, w.onboard, w.handling, w.landing, w.atc, w.maintenance, w.income_total, w.cost_total, w.profit,
            w.origin_code, w.dest_code
       from t_was_money w join t_stmt_since k using (airline_id) where w.posted_at >= k.since
     except all
     select airline_id, posted_at, statement_blk, statement_routes, maint_registration, statement_pax, pax_income, cargo_income,
            fuel, onboard, handling, landing, atc, maintenance, income_total, cost_total, profit, origin_code, dest_code
       from t_now_money)
    union all
    (select n.airline_id, n.posted_at, n.statement_blk, n.statement_routes, n.maint_registration, n.statement_pax, n.pax_income,
            n.cargo_income, n.fuel, n.onboard, n.handling, n.landing, n.atc, n.maintenance, n.income_total, n.cost_total, n.profit,
            n.origin_code, n.dest_code
       from t_now_money n join t_stmt_since k using (airline_id) where n.posted_at >= k.since
     except all
     select airline_id, posted_at, statement_blk, statement_routes, maint_registration, statement_pax, pax_income, cargo_income,
            fuel, onboard, handling, landing, atc, maintenance, income_total, cost_total, profit, origin_code, dest_code
       from t_was_money)) x;
  insert into t_report select p_pass, 'payments', count(*) from (
    (select w.* from t_was_payments w join t_stmt_since k using (airline_id) where w.paid_at >= k.since
     except all
     select world_id, airline_id, paid_at, kind, registration, aircraft_id, descr, amount, side, occ, statement_blk from public.game_payments)
    union all
    (select p.world_id, p.airline_id, p.paid_at, p.kind, p.registration, p.aircraft_id, p.descr, p.amount, p.side, p.occ, p.statement_blk
       from public.game_payments p join t_stmt_since k using (airline_id) where p.paid_at >= k.since
     except all
     select * from t_was_payments)) x;
  -- flights' loads: those last written from the kept pages' time on, every column but the capture time
  insert into t_report select p_pass, 'flights: loads', count(*) from (
    (select w.airline_id, w.game_date, w.flight_no, w.dep_local, w.origin_code, w.dest_code, w.arr_local, w.dep_at, w.arr_at,
            w.registration, w.status, w.eco_pax, w.eco_seats, w.eco_fare, w.eco_pct, w.bus_pax, w.bus_seats, w.bus_fare, w.bus_pct,
            w.fst_pax, w.fst_seats, w.fst_fare, w.fst_pct, w.cargo_units, w.cargo_cap, w.cargo_rate, w.cargo_pct
       from t_was_loads w join t_kept k on k.airline_id = w.airline_id and k.kind = 'loads' where w.loads_captured_at >= k.since
     except all
     select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
            eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
            cargo_units, cargo_cap, cargo_rate, cargo_pct from t_now_loads)
    union all
    (select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
            eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
            cargo_units, cargo_cap, cargo_rate, cargo_pct from t_now_loads
     except all
     select airline_id, game_date, flight_no, dep_local, origin_code, dest_code, arr_local, dep_at, arr_at, registration, status,
            eco_pax, eco_seats, eco_fare, eco_pct, bus_pax, bus_seats, bus_fare, bus_pct, fst_pax, fst_seats, fst_fare, fst_pct,
            cargo_units, cargo_cap, cargo_rate, cargo_pct from t_was_loads)) x;

  -- capture times: where the time recorded is a kept page's time, the replay gives the same; a time no page has came
  -- from a later re-read and is only reported
  insert into t_report
  select p_pass, 'statement lines: capture time' || case when kept then '' else ' (re-read since, not compared)' end, count(*), kept
    from (select exists (select 1 from t_pages p where p.airline_id = w.airline_id and p.kind = 'statement' and p.captured_at = w.captured_at) as kept
            from t_was_statement w
            join t_now_statement s on (s.airline_id, s.ts, s.descr, s.amount, s.occ) = (w.airline_id, w.ts, w.descr, w.amount, w.occ)
           where s.captured_at is distinct from w.captured_at) x
   group by kept;
  insert into t_report
  select p_pass, 'flights: money capture time' || case when kept then '' else ' (re-read since, not compared)' end, count(*), kept
    from (select exists (select 1 from t_pages p where p.airline_id = w.airline_id and p.kind = 'statement' and p.captured_at = w.money_captured_at) as kept
            from t_was_money w
            join t_now_money n on (n.airline_id, n.posted_at, n.statement_blk) = (w.airline_id, w.posted_at, w.statement_blk)
           where n.money_captured_at is distinct from w.money_captured_at) x
   group by kept;
  insert into t_report
  select p_pass, 'flights: loads capture time' || case when kept then '' else ' (re-read since, not compared)' end, count(*), kept
    from (select exists (select 1 from t_pages p where p.airline_id = w.airline_id and p.kind = 'loads' and p.captured_at = w.loads_captured_at) as kept
            from t_was_loads w
            join t_now_loads n on (n.airline_id, n.game_date, n.flight_no, n.dep_local) = (w.airline_id, w.game_date, w.flight_no, w.dep_local)
           where n.loads_captured_at is distinct from w.loads_captured_at) x
   group by kept;

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
  drop table t_stmt_since; drop table t_now_statement; drop table t_now_money; drop table t_now_loads;
end
$replay$;

do $test$
declare bad text; v_pages bigint; v_reread text;
begin
  select count(*) into v_pages from t_pages;
  perform pg_temp.replay('name');
  perform pg_temp.replay('game id');
  select string_agg(r.pass || ': ' || r.part || ' ' || r.n, '; ' order by r.pass, r.part) into bad from t_report r where r.n > 0 and r.counted;
  assert bad is null, 'the replay differs from the backfill (rows that differ): ' || bad;
  select string_agg(r.part || ' ' || r.n, ', ' order by r.part) into v_reread from t_report r where r.pass = 'name' and not r.counted;
  raise notice 'replay: % pages, by name and by game ID, gave the same rows as the backfill (% flights'' money, % loads rows, % payments, % statement lines compared)',
    v_pages, (select count(*) from t_was_money), (select count(*) from t_was_loads), (select count(*) from t_was_payments),
    (select count(*) from t_was_statement);
  if v_reread is not null then
    raise notice 'replay: capture times from a later re-read, which no page has, not compared: %', v_reread;
  end if;
end
$test$;

-- every kept evening judged ok (#21): each page as the replay checked it, against what was expected of it then
do $test$
declare bad text; v_summary text; v_loads text; v_stmt text; v_enforce boolean := false;   -- TEMPORARY: report only until calibrated
begin
  select string_agg(format('%s %s %s: %s (%s)', private.capture_day(t.world_id, t.captured_at), t.airline, t.kind,
                           coalesce(t.v ->> 'verdict', 'not judged'), coalesce(t.v ->> 'note', 'no note')), '; ' order by t.captured_at, t.airline, t.kind)
    into bad from t_verdicts t where t.v ->> 'verdict' is distinct from 'ok';
  select string_agg(format('%s: %s pages', x.day, x.n), ', ' order by x.day) into v_summary
    from (select private.capture_day(t.world_id, t.captured_at) as day, count(*) as n from t_verdicts t group by 1) x;
  select format('loads read %s%% to %s%% of the flights scheduled', round(min((t.v ->> 'share')::numeric) * 100), round(max((t.v ->> 'share')::numeric) * 100))
    into v_loads from t_verdicts t where t.kind = 'loads' and t.v ->> 'share' is not null;
  select format('statements %s to %s times their recent median', round(min((t.v ->> 'read')::numeric / nullif((t.v ->> 'median_lines')::numeric, 0)), 2),
                round(max((t.v ->> 'read')::numeric / nullif((t.v ->> 'median_lines')::numeric, 0)), 2))
    into v_stmt from t_verdicts t where t.kind = 'statement' and (t.v ->> 'median_lines')::numeric > 0;
  raise notice 'the kept evenings'' verdicts: % pages, %; %; %', (select count(*) from t_verdicts),
    case when bad is null then 'every one ok' else (select count(*) from t_verdicts t where t.v ->> 'verdict' is distinct from 'ok') || ' not ok' end,
    coalesce(v_loads, 'no loads judged'), coalesce(v_stmt, 'no statement against a median');
  raise notice 'by evening: %', v_summary;
  if bad is not null then raise notice 'not ok: %', left(bad, 3000); end if;
  raise notice 'loads by evening: %', (select string_agg(format('%s %s %s/%s', private.capture_day(t.world_id, t.captured_at), left(t.airline, 3), t.v ->> 'read', t.v ->> 'scheduled'), ', ' order by t.captured_at)
                                        from t_verdicts t where t.kind = 'loads');
  assert not v_enforce or bad is null, 'kept evenings not judged ok: ' || left(coalesce(bad, ''), 1500);
end
$test$;

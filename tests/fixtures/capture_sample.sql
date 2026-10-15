-- The capture's saved pages (decision #21; tests/README.md, "The capture sample"): one airline's five pages of one
-- evening, as the capture sent them, with what to expect of them and the rows they give, as one JSON document on
-- stdout. Run by database/rehearse.sh on the rehearsal's copy (with CAPTURE_SAMPLE_DIR set) after the pull request's
-- migrations and before any test or save touches the copy; database/tests/capture_checks_test.sql reads the newest
-- tests/fixtures/capture_pages_<capture day>.json.gz.
--   - the airline: Kingfisher (game ID 113, as the schedule check's saved page), in the default world;
--   - the evening: the newest capture day on which it has all five pages; of each kind, that day's latest page;
--   - expect: private.capture_expect() of the loads and statement pages on the copy (the flights scheduled in the loads
--     page's window, the median of the statement's recent nights), so the test judges the pages as they were judged;
--   - gives: the rows the five pages give when read alone (the airline's capture rows emptied first, then each page read
--     by private.capture_page() in the order it came), in the columns the pages give, each list sorted. Times in UTC.
-- Everything happens in one transaction that is rolled back: the copy is left as it was.
begin;

create temporary table t_cs_pages on commit drop as
  with al as (select a.id, a.world_id from public.airlines a join public.worlds w on w.id = a.world_id and w.is_default where a.game_id = 113),
  days as (select private.capture_day(r.world_id, r.captured_at) as day
             from public.game_capture_raw r, al
            where r.airline_id = al.id and r.kind in ('events', 'statement', 'pnl', 'balance', 'loads')
            group by 1 having count(distinct r.kind) = 5),
  pick as (select max(day) as day from days)
  select distinct on (r.kind) r.id, r.world_id, r.airline_id, r.airline, r.kind, r.page_url, r.rows, r.captured_at, pick.day
    from public.game_capture_raw r, al, pick
   where r.airline_id = al.id and r.kind in ('events', 'statement', 'pnl', 'balance', 'loads')
     and private.capture_day(r.world_id, r.captured_at) = pick.day
   order by r.kind, r.captured_at desc, r.id desc;

create temporary table t_cs_expect on commit drop as
  select p.kind, private.capture_expect(p.id) as expect from t_cs_pages p where p.kind in ('loads', 'statement');

create temporary table t_cs_read (kind text, res jsonb) on commit drop;

do $$
declare al bigint := (select max(airline_id) from t_cs_pages); p record;
begin
  if (select count(*) from t_cs_pages) <> 5 then raise exception 'Kingfisher has no capture day with all five pages on the copy'; end if;
  delete from public.game_statement where airline_id = al;
  delete from public.game_flights where airline_id = al;
  delete from public.game_payments where airline_id = al;
  delete from public.game_events where airline_id = al;
  delete from public.game_balance where airline_id = al;
  delete from public.game_pnl where airline_id = al;
  for p in select * from t_cs_pages order by captured_at, id loop
    insert into t_cs_read values (p.kind, private.capture_page(p.id));
  end loop;
end
$$;

select jsonb_build_object(
  'what', 'One airline''s five capture pages of one evening, as the capture sent them, with what to expect of them and the rows they give (tests/fixtures/capture_sample.sql; decision #21)',
  'airline', (select max(airline) from t_cs_pages),
  'game_id', 113,
  'capture_day', (select max(day) from t_cs_pages),
  'pages', (select jsonb_agg(jsonb_build_object('kind', p.kind, 'page_url', p.page_url, 'captured_at', private.fig_ts(p.captured_at), 'rows', p.rows)
                             order by p.captured_at, p.id) from t_cs_pages p),
  'expect', (select jsonb_object_agg(e.kind, e.expect) from t_cs_expect e),
  'read', (select jsonb_object_agg(r.kind, r.res -> 'rows') from t_cs_read r),
  'gives', jsonb_build_object(
    'statement', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(private.fig_ts(s.ts), s.descr, s.amount, s.side, s.route, s.pax, s.occ, s.blk, s.flight_id is null) x
          from public.game_statement s where s.airline_id = (select max(airline_id) from t_cs_pages)) q),
    'payments', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(private.fig_ts(p.paid_at), p.kind, p.registration, p.descr, p.amount, p.side, p.occ, p.statement_blk) x
          from public.game_payments p where p.airline_id = (select max(airline_id) from t_cs_pages)) q),
    'money', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(private.fig_ts(f.posted_at), f.statement_blk, f.statement_routes, f.maint_registration, f.statement_pax,
                                 f.pax_income, f.cargo_income, f.fuel, f.onboard, f.handling, f.landing, f.atc, f.maintenance,
                                 f.income_total, f.cost_total, f.profit, f.origin_code, f.dest_code) x
          from public.game_flights f where f.airline_id = (select max(airline_id) from t_cs_pages) and f.posted_at is not null) q),
    'loads', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(f.game_date, f.flight_no, f.dep_local, f.origin_code, f.dest_code, f.arr_local, f.registration, f.status,
                                 f.eco_pax, f.eco_seats, f.eco_fare, f.eco_pct, f.bus_pax, f.bus_seats, f.bus_fare, f.bus_pct,
                                 f.fst_pax, f.fst_seats, f.fst_fare, f.fst_pct, f.cargo_units, f.cargo_cap, f.cargo_rate, f.cargo_pct) x
          from public.game_flights f where f.airline_id = (select max(airline_id) from t_cs_pages) and f.flight_no is not null) q),
    'events', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(e.event_date, e.event_time, e.descr, e.credit, e.debit, e.balance) x
          from public.game_events e where e.airline_id = (select max(airline_id) from t_cs_pages)) q),
    'balance', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(b.captured_on, b.capture_day, b.account, b.amount) x
          from public.game_balance b where b.airline_id = (select max(airline_id) from t_cs_pages)) q),
    'pnl', (select coalesce(jsonb_agg(x order by x), '[]') from (
        select jsonb_build_array(g.captured_on, g.capture_day, g.line, g.current_p, g.last_p, g.total_p) x
          from public.game_pnl g where g.airline_id = (select max(airline_id) from t_cs_pages)) q)))::text;

rollback;

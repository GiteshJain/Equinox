-- Profit leaves out what's put back into the fleet (migration 20261026160000_profit_without_reinvestment.sql; Gitesh,
-- 26 Oct). Run by database/rehearse.sh on the copy of last night's backup, after the new migrations, inside a
-- transaction that is rolled back.
--   1. Between two reported days with balance captures, fig_capex() takes the bank statement's payments between the two
--      captures: a deposit, a purchase, a cabin, a refit, pilot training and a bid provision count; a refunded deposit
--      and a bid provision's refund count against them; a lease, salaries and a line outside the two captures don't.
--   2. A day with no balance capture (typed by hand) falls back to the spending log, as before.
--   3. airline_profit()'s day carries the same: profit a day moves by exactly the statement's reinvestment over the days.

do $test$
declare
  a bigint; w bigint; d0 date; d1 date; t0 timestamptz; t1 timestamptz; base numeric; after numeric;
  p_before numeric; p_after numeric; n int; v_days int;
begin
  -- the airline and the latest two consecutive reported days that both have a balance capture after its first payment
  select x.airline_id, x.world_id, x.d0, x.d1, x.t0, x.t1 into a, w, d0, d1, t0, t1
    from (select b.airline_id, al.world_id, b.captured_on as d1, max(b.captured_at) as t1,
                 lag(b.captured_on) over (partition by b.airline_id order by b.captured_on) as d0,
                 lag(max(b.captured_at)) over (partition by b.airline_id order by b.captured_on) as t0
            from public.game_balance b join public.airlines al on al.id = b.airline_id
           where b.account like '2800%' and b.amount is not null
           group by b.airline_id, al.world_id, b.captured_on) x
   where x.d0 is not null
     and x.t0 >= (select min(p.paid_at) from public.game_payments p where p.airline_id = x.airline_id)
     and not exists (select 1 from public.cash_entries e where e.airline_id = x.airline_id and e.day in (x.d0, x.d1))
   order by x.d1 desc, x.airline_id limit 1;
  if a is null then
    raise notice 'profit without reinvestment: the copy has no two reported days with captures after the payments begin; nothing to try';
    return;
  end if;
  base := private.fig_capex(a, d0, d1);
  select (x ->> 'profit_day')::numeric, (x ->> 'days')::int into p_before, v_days
    from jsonb_array_elements(public.airline_profit(a, t1 + interval '1 minute') -> 'days') x where (x ->> 'date')::date = d1;

  -- 1. a minute after the first capture: 2.00 deposit, 0.50 deposit refunded, 3.00 purchase, 0.10 cabin, 0.20 refit,
  --    0.05 pilot training, 1.00 bid provision and its 1.00 refund; and 0.30 lease, 0.70 salaries and a 9.00 deposit
  --    outside the two captures, which don't count
  insert into public.game_payments (world_id, airline_id, paid_at, kind, descr, amount, side, occ) values
    (w, a, t0 + interval '1 minute', 'deposit', 'Security deposit for leasing of aircraft (TEST-1)', 2000000, 'D', 901),
    (w, a, t0 + interval '2 minutes', 'deposit', 'Refund of security deposit (TEST-2)', 500000, 'C', 902),
    (w, a, t0 + interval '3 minutes', 'purchase', 'Purchase of aircraft (TEST-3)', 3000000, 'D', 903),
    (w, a, t0 + interval '4 minutes', 'cabin', 'Installation of cabin interior (TEST-1)', 100000, 'D', 904),
    (w, a, t0 + interval '5 minutes', 'refit', 'Refit of cabin interior (TEST-4)', 200000, 'D', 905),
    (w, a, t0 + interval '6 minutes', 'cabin', 'Pilot training', 50000, 'D', 906),
    (w, a, t0 + interval '7 minutes', 'other', 'Provisions for bid for aircraft', 1000000, 'D', 907),
    (w, a, t0 + interval '8 minutes', 'other', 'Refund of provisions for bid for aircraft', 1000000, 'C', 908),
    (w, a, t0 + interval '9 minutes', 'lease', 'Leasing of aircraft (TEST-1)', 300000, 'D', 909),
    (w, a, t0 + interval '10 minutes', 'salaries', 'Salaries', 700000, 'D', 910),
    (w, a, t0 - interval '1 minute', 'deposit', 'Security deposit for leasing of aircraft (TEST-5)', 9000000, 'D', 911),
    (w, a, t1 + interval '1 minute', 'deposit', 'Security deposit for leasing of aircraft (TEST-6)', 9000000, 'D', 912);
  after := private.fig_capex(a, d0, d1);
  assert abs(after - base - 4.85) < 1e-9,
    format('fig_capex() moved by %s, not 4.85 (2.00 - 0.50 + 3.00 + 0.10 + 0.20 + 0.05 + 1.00 - 1.00)', after - base);

  -- 3. the day's profit moves by the same, over its days
  select (x ->> 'profit_day')::numeric into p_after
    from jsonb_array_elements(public.airline_profit(a, t1 + interval '1 minute') -> 'days') x where (x ->> 'date')::date = d1;
  assert p_before is not null and abs((p_after - p_before) - 4.85 / greatest(1, v_days)) < 1e-9,
    format('airline_profit()''s %s moved by %s, not %s', d1, p_after - p_before, 4.85 / greatest(1, v_days));

  -- 2. a day typed by hand (no balance capture) reads the spending log
  select count(*) into n from public.spending_log s where s.airline_id = a and s.kind <> 'loss' and s.spent_on > d1 - 400 and s.spent_on <= d1;
  assert private.fig_capex(a, d1 + 1000, d1 + 1001) = 0, 'no capture and no log: not 0';
  insert into public.spending_log (world_id, airline_id, spent_on, kind, amount, note)
  values (w, a, d1 + 1001, 'order', 1230000, 'profit_without_reinvestment_test');
  assert private.fig_capex(a, d1 + 1000, d1 + 1001) = 1.23, 'a day with no balance capture didn''t read the spending log';

  raise notice 'profit without reinvestment: airline % from % to %, the statement''s deposits, purchase, cabin, refit, pilot training and bid provision counted, the refunds against them, lease, salaries and lines outside the captures not (+4.85M); the day''s profit moved by 4.85 over % day(s); a day without a capture read the spending log',
    a, d0, d1, v_days;
end
$test$;

-- Payments that aren't flights stay out of the flight-money views (20261010180000, bug found 10 Oct 2026).
-- The weekly salary payment, under its new label "Payment of employee salaries", used to show in game_flight_pnl as a
-- flight with no route and in game_ops_recent's costs. Run by database/rehearse.sh on the copy of last night's backup,
-- inside a transaction that is rolled back.
--   1. On the copy: no game_flight_pnl row is a payment's block (anything but kind 'other').
--   2. Hand-made: an airline with both salary labels, a lease and one 'other' line. The classifier knows both salary
--      labels; game_flight_pnl shows none of them; game_ops_recent counts only the 'other' line.

do $test$
declare n bigint; al bigint; w bigint; t timestamptz := '2099-01-05 12:00+00'; r record;
begin
  -- 1. the copy
  select count(*) into n
    from public.game_flight_pnl f
    join public.airlines a on a.planner_name = f.airline
    join public.game_payments p on p.airline_id = a.id and p.paid_at = f.ts and coalesce(p.statement_blk::integer, 1) = f.blk
   where p.kind <> 'other';
  assert n = 0, format('%s rows of game_flight_pnl are payments, not flights', n);

  -- 2. hand-made
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code)
  select g.world_id, g.id, 999902, 'Payments Test Air', 'PQ'
    from public.groups g join public.worlds wd on wd.id = g.world_id and wd.is_default
   where g.kind = 'ours' order by g.id limit 1
  returning id, world_id into al, w;
  assert al is not null, 'no group of ours in the default world to add a test airline to';

  insert into public.game_payments (world_id, airline_id, paid_at, kind, descr, amount, side, occ, statement_blk)
  select w, al, t - x.ago, private.payment_kind(x.descr), x.descr, x.amount, 'D', 1, x.blk
    from (values (interval '2 hours', 'Payment of employee salaries', 700000::numeric, 1::smallint),
                 (interval '3 hours', 'Week-end closing of Payments Test Air', 500000, 1),
                 (interval '4 hours', 'Leasing rate for PQ-AAA', 200000, 1),
                 (interval '1 hour', 'Something the game hasn''t named before', 1000, 0)) as x(ago, descr, amount, blk);

  select count(*) into n from public.game_payments where airline_id = al and kind = 'salaries';
  assert n = 2, format('the classifier knows %s of the 2 salary labels', n);

  select count(*) into n from public.game_flight_pnl where airline = 'Payments Test Air';
  assert n = 0, format('game_flight_pnl shows %s payments of the test airline as flights', n);

  select * into r from public.game_ops_recent where airline = 'Payments Test Air';
  assert r.costs = 1000 and r.income = 0 and r.flights = 0,
    format('game_ops_recent counts payments it should leave out: costs %s, income %s, flights %s', r.costs, r.income, r.flights);

  raise notice 'payments stay out of the flight-money views: both salary labels, leases; only unnamed lines count';
end
$test$;

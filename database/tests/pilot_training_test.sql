-- Pilot training is an order's payment, never a flight's cost (20261015200000; spec docs/specs/2026-10-15-small-fixes.md
-- §1). The 14 Oct orders brought 34 "Pilot training" lines on the bank statements, each beside a cabin payment; the
-- capture didn't know the label, so it stored them as unnamed payments (kind other), which game_flight_pnl,
-- game_ops_recent and the captured figures counted as flight costs. Run by database/rehearse.sh on the copy of last
-- night's backup, after the new migrations, inside a transaction that is rolled back. A failed check stops with an error
-- that says which (counts, never figures from the copy).
--   1. Hand-made, through the capture's own fold (private.fold_statement()): one minute with a flight's lines and a
--      pilot-training line in the same block, and another with a cabin payment and a pilot-training line beside it. The
--      flight's costs are its own lines only; both training lines are payments of kind cabin, tied to no flight; the
--      flight-money views and the flight profit a day's source (private.fig_ops_recent()) count the flight only.
--   2. On the copy: every stored line that names training is a payment of kind cabin, none tied to a flight or left
--      unnamed; every payment the re-sort named (its kind other before the changes, rehearsal_before) is such a line.

do $test$
declare
  al bigint; w bigint; t timestamptz := '2099-03-02 12:00+00'; t2 timestamptz := '2099-03-02 12:30+00';
  r record; n int; n2 int; n3 int; n4 int; v_costs numeric; v_income numeric; v_profit numeric;
begin
  -- ---------------------------------------------------------------- 1. hand-made
  insert into public.airlines (world_id, group_id, game_id, planner_name, iata_code)
  select g.world_id, g.id, 999904, 'Training Test Air', 'TQ'
    from public.groups g join public.worlds wd on wd.id = g.world_id and wd.is_default
   where g.kind = 'ours' order by g.id limit 1
  returning id, world_id into al, w;
  assert al is not null, 'no group of ours in the default world to add a test airline to';

  -- a flight (income 29212, costs 1463 + 2345 + 3867 = 7675) with a pilot-training line in its minute and block; then a
  -- cabin payment with a pilot-training line beside it, in a minute of their own
  insert into public.game_statement (world_id, airline_id, airline, ts, descr, amount, side, occ, blk)
  values (w, al, 'Training Test Air', t, 'Air traffic control fee (TQA-TQB)', 1463, 'D', 1, 1),
         (w, al, 'Training Test Air', t, 'Fuel (4563 Liters)', 2345, 'D', 1, 1),
         (w, al, 'Training Test Air', t, 'On-board services (TQA-TQB)', 3867, 'D', 1, 1),
         (w, al, 'Training Test Air', t, 'Passenger transport income', 29212, 'C', 1, 1),
         (w, al, 'Training Test Air', t, 'Pilot training', 156800, 'D', 1, 1),
         (w, al, 'Training Test Air', t2, 'New cabin for TQ-AAA', 300000, 'D', 1, 1),
         (w, al, 'Training Test Air', t2, 'Pilot training', 156800, 'D', 1, 1);
  perform private.fold_statement(al, array[t, t2]);

  select count(*) into n from public.game_flights f where f.airline_id = al;
  select f.cost_total, f.income_total into v_costs, v_income from public.game_flights f where f.airline_id = al and f.posted_at = t;
  assert n = 1, format('the statement made %s flights, not 1 (a payments-only minute became a flight?)', n);
  assert v_costs = 7675 and v_income = 29212,
    format('the flight''s costs are %s, not its own lines'' 7675 (a pilot-training line counted as a flight cost?); income %s', v_costs, v_income);

  select count(*) into n from public.game_statement s where s.airline_id = al and s.descr = 'Pilot training' and s.flight_id is not null;
  assert n = 0, format('%s pilot-training lines are tied to a flight', n);
  select count(*) filter (where p.descr = 'Pilot training' and p.kind = 'cabin'), count(*) filter (where p.kind = 'cabin'), count(*)
    into n, n2, n3 from public.game_payments p where p.airline_id = al;
  assert n = 2 and n2 = 3 and n3 = 3,
    format('payments: %s of 2 pilot-training lines of kind cabin, %s of 3 lines of kind cabin, %s in all', n, n2, n3);

  assert private.payment_kind('Pilot training for TQ-AAA') = 'cabin' and private.is_payment_line('Pilot training', 1),
    'the classifier doesn''t name "Pilot training ..." as a payment of kind cabin';

  select count(*), max(f.profit) into n, v_profit from public.game_flight_pnl f where f.airline = 'Training Test Air';
  assert n = 1 and v_profit = 29212 - 7675,
    format('game_flight_pnl: %s rows, profit %s; the flight only (profit 21537) expected', n, v_profit);
  select * into r from public.game_ops_recent where airline = 'Training Test Air';
  assert r.costs = 7675 and r.income = 29212 and r.flights = 1,
    format('game_ops_recent counts pilot training: costs %s, income %s, flights %s', r.costs, r.income, r.flights);
  select * into r from private.fig_ops_recent(al, t2 + interval '1 hour');
  assert r.costs = 7675 and r.income = 29212 and r.flights = 1,
    format('the flight profit a day''s source (private.fig_ops_recent) counts pilot training: costs %s, income %s, flights %s', r.costs, r.income, r.flights);

  delete from public.game_statement where airline_id = al;
  delete from public.game_payments where airline_id = al;
  delete from public.game_flights where airline_id = al;
  delete from public.airlines where id = al;
  raise notice 'hand-made: a pilot-training line in a flight''s block and one beside a cabin payment are both payments of kind cabin; the flight''s costs, game_flight_pnl, game_ops_recent and fig_ops_recent count its own lines only';

  -- ---------------------------------------------------------------- 2. on the copy
  select count(*), count(*) filter (where p.kind = 'cabin'), count(*) filter (where p.kind = 'other') into n, n2, n3
    from public.game_payments p where p.descr ilike '%training%';
  assert n3 = 0 and n2 = n, format('%s of %s stored pilot-training lines are kind cabin (%s left unnamed)', n2, n, n3);
  select count(*) into n4 from public.game_statement s where s.descr ilike '%training%' and s.flight_id is not null;
  assert n4 = 0, format('%s stored pilot-training lines are tied to a flight', n4);

  assert to_regclass('rehearsal_before.payment_kinds') is not null,
    'the payments'' kinds from before the changes weren''t saved (database/tests/before/pilot_training_before.sql)';
  select count(*), count(*) filter (where p.descr not ilike '%training%' or p.kind <> 'cabin') into n2, n3
    from rehearsal_before.payment_kinds b join public.game_payments p on p.id = b.id
   where p.kind is distinct from b.kind;
  assert n3 = 0, format('the re-sort named %s payments that aren''t pilot training', n3);
  raise notice 'on the copy: % pilot-training lines, each a payment of kind cabin and none tied to a flight; % of them named by the re-sort, nothing else', n, n2;
end
$test$;

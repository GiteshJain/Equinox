-- The captured figures before and after a pull request's database changes, for database/figures_moved.py (run by
-- database/rehearse.sh after the database tests): what database/tests/before/figures_before.sql saved, and the same
-- worked out again on the copy as the changes left it: private.fig_export() at the same moment, and the flight-money
-- views and the last two weeks of daily history per airline (keep this query the same as the before file's). Also the
-- payments whose kind the changes changed (from rehearsal_before.payment_kinds), per airline and kind, with when they
-- were paid and stored against each airline's 24 hours of game_ops_recent. One JSON document.
select jsonb_build_object(
  'as_of', (select value from rehearsal_before.figures where name = 'as_of'),
  'before', jsonb_build_object(
    'figures', (select value from rehearsal_before.figures where name = 'figures'),
    'money', (select value from rehearsal_before.figures where name = 'money')),
  'after', jsonb_build_object(
    'figures', private.fig_export((select (value #>> '{}')::bigint from rehearsal_before.figures where name = 'world_id'),
                                  (select (value #>> '{}')::timestamptz from rehearsal_before.figures where name = 'as_of')),
    'money', jsonb_build_object(
      'game_flight_pnl', (select coalesce(jsonb_agg(jsonb_build_object('airline', x.airline, 'blocks', x.n, 'profit', x.profit,
                                                                       'blocks_without_route', x.nr, 'profit_without_route', x.pr) order by x.airline), '[]')
                            from (select f.airline, count(*) as n, sum(f.profit) as profit, count(*) filter (where f.route is null) as nr,
                                         coalesce(sum(f.profit) filter (where f.route is null), 0) as pr
                                    from public.game_flight_pnl f group by f.airline) x),
      'game_ops_recent', (select coalesce(jsonb_agg(to_jsonb(o) order by o.airline), '[]') from public.game_ops_recent o),
      'airline_days', (select coalesce(jsonb_agg(jsonb_build_object('airline', a.planner_name, 'day', d.day, 'flight_costs', d.flight_costs,
                                                                    'flight_profit', d.flight_profit, 'purchases_paid', d.purchases_paid)
                                                 order by a.planner_name, d.day), '[]')
                         from public.airline_days d join public.airlines a on a.id = d.airline_id
                        where d.day >= (now() at time zone 'UTC')::date - 14))),
  'payments_named', (
    select coalesce(jsonb_agg(jsonb_build_object('airline', y.airline, 'kind_before', y.kb, 'kind', y.ka, 'lines', y.n,
                                                 'amount', y.amount, 'blocks_0', y.n0, 'first_paid', y.p0, 'last_paid', y.p1,
                                                 'first_stored', y.c0, 'last_stored', y.c1, 'ops_window_from', y.win)
                              order by y.airline, y.ka), '[]')
      from (select a.planner_name as airline, k.kind as kb, p.kind as ka, count(*) as n, sum(p.amount) as amount,
                   count(*) filter (where p.statement_blk = 0) as n0, min(p.paid_at) as p0, max(p.paid_at) as p1,
                   min(p.created_at) as c0, max(p.created_at) as c1, max(o.last_ts) - interval '24 hours' as win
              from rehearsal_before.payment_kinds k
              join public.game_payments p on p.id = k.id and p.kind is distinct from k.kind
              join public.airlines a on a.id = p.airline_id
              left join public.game_ops_recent o on o.airline = a.planner_name
             group by a.planner_name, k.kind, p.kind) y));

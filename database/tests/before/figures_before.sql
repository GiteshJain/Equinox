-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before (spec
-- docs/specs/2026-10-15-small-fixes.md §1). Nothing is printed.
--   figures: for the rehearsal's "figures moved" step, every captured figure for every airline
--     (export_for_report('figures')'s document, private.fig_export()) at one moment, the copy's latest capture plus an hour
--     (the planner's frozen moment), and the flight-money views and daily history they sit beside (database/figures_moved.sql
--     says which; the same query works them out again after the changes). The step writes every value that moved, before
--     and after, to the run's figures-moved artifact.
--   payment_kinds: each payment the capture stored as unnamed (game_payments kind other), by id, so the step can list the
--     payments a change named, pilot_training_test.sql can show the pilot-training re-sort named only those, and
--     capture_data_compat_test.sql and clean_up_test.sql can put their kinds back before comparing everything else.
create table rehearsal_before.payment_kinds as
  select p.id, p.kind, p.descr from public.game_payments p where p.kind = 'other';

create table rehearsal_before.figures (name text primary key, value jsonb);
do $$
declare w bigint := (select x.id from public.worlds x where x.is_default);
  v_at timestamptz := '2026-10-15 00:30+00';   -- TEMPORARY, reverted next commit: the figures just after the capture that stored the pilot-training lines
begin
  insert into rehearsal_before.figures (name, value) values
    ('world_id', to_jsonb(w)),
    ('as_of', to_jsonb(v_at)),
    ('figures', private.fig_export(w, v_at));
end
$$;
-- the flight-money views and the last two weeks of daily history, per airline (AS$): the same query as
-- database/figures_moved.sql's, which works them out again after the changes
insert into rehearsal_before.figures (name, value)
select 'money', jsonb_build_object(
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
                    where d.day >= (now() at time zone 'UTC')::date - 14));

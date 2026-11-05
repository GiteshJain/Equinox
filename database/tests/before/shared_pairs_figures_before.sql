-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and read afterwards by
-- database/tests/shared_pairs_figures_test.sql §9 (spec docs/specs/2026-11-05-shared-pairs.md, pull request 2: none of
-- these may get noticeably slower): each of our airlines' fare_ladder(), competition(), route_profit() and route_story()
-- builders (route_story() on the airline's route with the most rotations), and growth_signals() for the world, timed one
-- at a time. A builder missing before is left out.
create table rehearsal_before.shared_figures_ms (airline_id bigint, iata text, fn text, ms integer);

do $save$
declare x record; t0 timestamptz; r bigint; w bigint := private.fig_world(null);
begin
  t0 := clock_timestamp();
  perform private.fig_growth_signals(w, now());
  insert into rehearsal_before.shared_figures_ms values (null, null, 'growth_signals', round(extract(epoch from clock_timestamp() - t0) * 1000));
  for x in select f.airline_id, a.iata_code from private.fig_airlines(w) f join public.airlines a on a.id = f.airline_id order by f.ord loop
    t0 := clock_timestamp(); perform private.fig_fare_ladder(x.airline_id, now());
    insert into rehearsal_before.shared_figures_ms values (x.airline_id, x.iata_code, 'fare_ladder', round(extract(epoch from clock_timestamp() - t0) * 1000));
    t0 := clock_timestamp(); perform private.fig_competition(x.airline_id, now(), 50);
    insert into rehearsal_before.shared_figures_ms values (x.airline_id, x.iata_code, 'competition', round(extract(epoch from clock_timestamp() - t0) * 1000));
    t0 := clock_timestamp(); perform private.fig_route_profit(x.airline_id, 7, now());
    insert into rehearsal_before.shared_figures_ms values (x.airline_id, x.iata_code, 'route_profit', round(extract(epoch from clock_timestamp() - t0) * 1000));
    select ro.id into r from public.routes ro where ro.airline_id = x.airline_id and not ro.removed
     order by (select count(*) from public.rotations rt where rt.route_id = ro.id) desc, ro.id limit 1;
    if r is not null then
      t0 := clock_timestamp(); perform private.fig_route_story(r, now());
      insert into rehearsal_before.shared_figures_ms values (x.airline_id, x.iata_code, 'route_story', round(extract(epoch from clock_timestamp() - t0) * 1000));
    end if;
  end loop;
end
$save$;

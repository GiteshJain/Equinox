-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and read afterwards by
-- database/tests/flight_links_test.sql (spec docs/specs/2026-10-21-links-and-business-index.md). Nothing is printed.
--   flight_links: how many captured flights had their route and aircraft, and how many route days their route, before
--     the fill-back; and the moment the fare ladder is read at, the copy's latest capture plus an hour (the planner's
--     frozen moment), so before and after are read at the same moment.
--   flight_links_ladder: each of our airlines' fare ladder rows (private.fig_fare_ladder()) at that moment, both cabins,
--     with their baseline, fare index, level and move, so the test can list the rows the business index from the daily
--     history changes (and show nothing else moved). Left empty when the copy has no fare ladder.
create table rehearsal_before.flight_links as
  select (select count(*) from public.game_flights) as flights,
         (select count(*) from public.game_flights where route_id is not null) as flights_with_route,
         (select count(*) from public.game_flights where aircraft_id is not null) as flights_with_aircraft,
         (select count(*) from public.route_days) as route_days,
         (select count(*) from public.route_days where route_id is not null) as route_days_with_route,
         date_trunc('minute', coalesce((select max(r.captured_at) from public.game_capture_raw r), now())) + interval '1 hour' as as_of;

create table rehearsal_before.flight_links_ladder (airline_id bigint, iata text, route_id bigint, hub text, dest text, cabin text,
                                                   baseline_fare numeric, baseline_on date, fare_index numeric, index_matches boolean,
                                                   level numeric, move text, new_level numeric, fix boolean);
do $save$
declare v_at timestamptz := (select x.as_of from rehearsal_before.flight_links x);
begin
  if to_regprocedure('private.fig_fare_ladder(bigint, timestamp with time zone)') is not null then
    insert into rehearsal_before.flight_links_ladder
    select x.airline_id, a.iata_code, (e ->> 'route_id')::bigint, e ->> 'hub', e ->> 'dest', e ->> 'cabin',
           (e ->> 'baseline_fare')::numeric, (e ->> 'baseline_on')::date, (e ->> 'fare_index')::numeric,
           (e ->> 'index_matches')::boolean, (e ->> 'level')::numeric, e ->> 'move', (e ->> 'new_level')::numeric, (e ->> 'fix')::boolean
      from private.fig_airlines(private.fig_world(null)) x
      join public.airlines a on a.id = x.airline_id
      cross join lateral jsonb_array_elements(private.fig_fare_ladder(x.airline_id, v_at) -> 'routes') e;
  end if;
end
$save$;

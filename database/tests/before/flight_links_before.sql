-- Saved by database/rehearse.sh before the pending changes run, into the schema rehearsal_before, and read afterwards by
-- database/tests/flight_links_test.sql (spec docs/specs/2026-10-21-links-and-business-index.md). Nothing is printed.
--   flight_links: how many captured flights had their route and aircraft, and how many route days their route, before
--     the fill-back.
create table rehearsal_before.flight_links as
  select (select count(*) from public.game_flights) as flights,
         (select count(*) from public.game_flights where route_id is not null) as flights_with_route,
         (select count(*) from public.game_flights where aircraft_id is not null) as flights_with_aircraft,
         (select count(*) from public.route_days) as route_days,
         (select count(*) from public.route_days where route_id is not null) as route_days_with_route;

-- The new planner's Routes screen (decision #18, build pull request 6). Spec: docs/specs/2026-10-13-routes.md §1
-- ("Loads: per route and per flight over 7 days from the database. Extend route_loads() with each flight's figures (by
-- flight number) rather than working them out on the screen").
--
-- Changes one function's answer and its builder; adds nothing else and takes nothing away from anyone:
--   public.route_loads(p_world_id, p_as_of) and private.fig_route_loads(): besides each route's loads ('routes', exactly
--     as before), each flight's ('flights'): for every airline and flight number the load reports cover over the same 7
--     days, the same figures as a route's (departures, their sum and average, how many at 95% or more or not reported,
--     under 95, under 85 and under 70, and the days seen). The old planner's loadStats() keeps both, under the route's
--     key and under "F|airline|number"; the Routes screen shows the flight's on each line of a frequency. The function's
--     arguments don't change, so its grants stay as they are and the new planner's types are the same.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261013220000_routes', true);

create or replace function private.fig_route_loads(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  with d as (select (p_as_of at time zone 'UTC')::date as d0),
  ld as (select x.* from d cross join lateral private.fig_load_days(p_world_id, p_as_of, d.d0 - 6, d.d0) x where x.done),
  lv as (select x.* from d cross join lateral private.fig_load_values(p_world_id, p_as_of, d.d0 - 6, d.d0) x where x.v is not null),
  fl as materialized (
    select x.day, x.airline_id, x.flight_no, x.route_id, lv.v
      from d cross join lateral private.fig_flights_on(p_world_id, d.d0 - 6, d.d0) x
      join ld on ld.day = x.day
      left join lv on lv.day = x.day and lv.airline_id = x.airline_id and lv.flight_no = x.flight_no
     where not (x.launched_on is not null and x.day < x.launched_on)
       and not (ld.captured and lv.v is null)),
  r as (select fl.route_id, fl.airline_id, count(*)::int as n,
               sum(case when coalesce(fl.v, 0) = 0 then 97.5 else fl.v end) as s,
               count(*) filter (where coalesce(fl.v, 0) = 0 or fl.v >= 95)::int as full_n,
               count(*) filter (where fl.v > 0 and fl.v >= 85 and fl.v < 95)::int as b95,
               count(*) filter (where fl.v > 0 and fl.v >= 70 and fl.v < 85)::int as b85,
               count(*) filter (where fl.v > 0 and fl.v < 70)::int as b70,
               count(distinct fl.day)::int as days
          from fl group by fl.route_id, fl.airline_id),
  -- each flight number's, as loadStats() keeps them under "F|airline|number": the same figures over the same flights
  f as (select fl.airline_id, fl.flight_no, count(*)::int as n,
               sum(case when coalesce(fl.v, 0) = 0 then 97.5 else fl.v end) as s,
               count(*) filter (where coalesce(fl.v, 0) = 0 or fl.v >= 95)::int as full_n,
               count(*) filter (where fl.v > 0 and fl.v >= 85 and fl.v < 95)::int as b95,
               count(*) filter (where fl.v > 0 and fl.v >= 70 and fl.v < 85)::int as b85,
               count(*) filter (where fl.v > 0 and fl.v < 70)::int as b70,
               count(distinct fl.day)::int as days
          from fl where fl.flight_no is not null group by fl.airline_id, fl.flight_no)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'from', (select d0 - 6 from d), 'to', (select d0 from d),
    'routes', coalesce((select jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'route_id', r.route_id, 'hub', ro.hub_code, 'dest', ro.dest_code,
        'departures', r.n, 'sum', r.s, 'average', r.s / r.n, 'full', r.full_n, 'under_95', r.b95, 'under_85', r.b85,
        'under_70', r.b70, 'days', r.days)
        order by a.position nulls last, r.airline_id, ro.hub_code, ro.dest_code)
      from r join public.routes ro on ro.id = r.route_id join public.airlines a on a.id = r.airline_id), '[]'::jsonb),
    'flights', coalesce((select jsonb_agg(jsonb_build_object(
        'airline_id', f.airline_id, 'flight_no', f.flight_no,
        'departures', f.n, 'sum', f.s, 'average', f.s / f.n, 'full', f.full_n, 'under_95', f.b95, 'under_85', f.b85,
        'under_70', f.b70, 'days', f.days)
        order by a.position nulls last, f.airline_id, f.flight_no)
      from f join public.airlines a on a.id = f.airline_id), '[]'::jsonb))
$function$;

comment on function private.fig_route_loads(bigint, timestamptz) is 'The captured figures (#19): the old planner''s loadStats() over the last 7 days, for each route and each flight number, with no check of its own. See route_loads().';
comment on function public.route_loads(bigint, timestamptz) is 'Each route''s and each flight''s economy loads over the last 7 days for our airlines in a world (the default world when null; decision #19, design §9: Home''s map and Routes'' loads; the old planner''s loadStats): every flight each day''s load report covers on the 7 days to p_as_of''s UTC date (from and to), done days only, on a captured day only the flights the capture has a load for, none before its rotation''s launch, a flight without a load counting as 97.5%: departures, their sum and average, how many at 95% or more (or not reported), under 95, under 85 and under 70, and the days seen. routes: by route, in airline position, hub and destination order; flights (#18 build pull request 6, the Routes screen''s lines): the same by airline and flight number, in airline position and number order. Staff only; runs as owner and checks the caller itself.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

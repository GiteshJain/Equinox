-- The route page (22 Oct 2026; spec docs/specs/2026-10-21-route-page.md, step 3 of four from
-- docs/specs/2026-10-20-today-performance-systems.md).
--
-- Why (Gitesh, 20 Oct): load monitoring is too simple and the screens aren't fun to use. A route gets one page that tells
-- its story since launch, so a fare move, a new frequency or a rival can be judged by what happened after it. One call
-- answers it, route_story(), which the Scheduling chat can read too; and the daily history keeps loads and fares by cabin
-- and the hours flown, so the story survives the month's archiving of game_flights.
--
-- Adds columns and functions and replaces one function with the same arguments; drops and renames nothing, so it can be
-- applied from the chat:
--   1. route_days, new columns, each described: eco_pax, eco_seats, bus_pax and bus_seats (seats only from flights whose
--      loads were captured, as seats is), bus_fare_avg (weighted by business passengers, as eco_fare_avg) and block_min
--      (the flights' scheduled block, arr_at − dep_at, summed over the flights that have both). No first-class columns:
--      no cabin layout has first-class seats (cabin_configs has economy and business only) and the notice below counts
--      game_flights rows with first-class seats on the copy (route_story_test.sql fails if there are any).
--   2. private.history_flows() replaced, same arguments (the daily snapshot's writer, from private.take_snapshot()): fills
--      the new columns for the days it recomputes, with the same matching as before. Its working table is a new temporary
--      one, pg_temp.t_history_flights, so a session that still holds the old one can't mix them.
--   3. The new columns filled back for every day game_flights still holds (since 6 Oct), as one statement (route_days is
--      the only table that changes); days older than game_flights keep nulls. It says how many rows and how long.
--   4. private.fig_route_story(p_route_id, p_as_of) and public.route_story(p_route_id, p_as_of default now()): staff only,
--      read with GET, as the other figures.
-- route_story() is granted to staff (signed in) only; the private functions get no grants, as the other figures.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261022020000_route_story', true);

-- ============================================================ 1. the daily history by cabin
alter table public.route_days
  add column if not exists eco_pax integer,
  add column if not exists eco_seats integer,
  add column if not exists bus_pax integer,
  add column if not exists bus_seats integer,
  add column if not exists bus_fare_avg numeric(14,2),
  add column if not exists block_min integer;

comment on column public.route_days.eco_pax is 'Economy passengers on the flights whose loads were captured (game_flights.eco_pax); null when none were. Since 22 Oct, filled back to the first day game_flights held (6 Oct)';
comment on column public.route_days.eco_seats is 'Economy seats on the flights whose loads were captured, as seats is; null when none were';
comment on column public.route_days.bus_pax is 'Business passengers on the flights whose loads were captured; null when none had business (the economy-only layouts)';
comment on column public.route_days.bus_seats is 'Business seats on the flights whose loads were captured, as seats is; null when none had business';
comment on column public.route_days.bus_fare_avg is 'Average business fare, AS$, weighted by business passengers (as eco_fare_avg), from the flights with business seats; null with none';
comment on column public.route_days.block_min is 'The flights'' scheduled block, minutes: arr_at − dep_at summed over the flights that have both (game_flights); null when none has. Hours flown, for profit per aircraft hour (route_story())';

-- ============================================================ 2. the writer fills them
CREATE OR REPLACE FUNCTION private.history_flows(p_world_id bigint, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare n_routes int := 0; n_days int := 0;
begin
  if p_from is null or p_to is null or p_to < p_from then
    return jsonb_build_object('route_days', 0, 'airline_days', 0);
  end if;
  -- the flights of the span, one row each (since 22 Oct a new working table, with each cabin and the block)
  if to_regclass('pg_temp.t_history_flights') is null then
    create temporary table t_history_flights (airline_id bigint, route_id bigint, origin_code text, dest_code text, day date,
      is_flight boolean, has_loads boolean, pax int, seats int, eco_pax int, eco_seats int, eco_fare numeric,
      bus_pax int, bus_seats int, bus_fare numeric, block_min int, income numeric, costs numeric) on commit drop;
  end if;
  truncate pg_temp.t_history_flights;
  insert into pg_temp.t_history_flights
  select f.airline_id, f.route_id, nullif(f.origin_code, ''), nullif(f.dest_code, ''),
         coalesce((f.dep_at at time zone 'UTC')::date, f.game_date),
         f.flight_no is not null or f.pax_income is not null, f.flight_no is not null,
         case when f.flight_no is not null then coalesce(f.eco_pax, 0) + coalesce(f.bus_pax, 0) + coalesce(f.fst_pax, 0)
              else f.statement_pax end,
         case when f.flight_no is not null then coalesce(f.eco_seats, 0) + coalesce(f.bus_seats, 0) + coalesce(f.fst_seats, 0) end,
         case when f.flight_no is not null then f.eco_pax end, case when f.flight_no is not null then f.eco_seats end,
         f.eco_fare,
         case when f.flight_no is not null then f.bus_pax end, case when f.flight_no is not null then f.bus_seats end,
         case when f.flight_no is not null and f.bus_seats > 0 then f.bus_fare end,
         case when f.dep_at is not null and f.arr_at is not null then round(extract(epoch from f.arr_at - f.dep_at) / 60)::int end,
         f.income_total, f.cost_total
    from public.game_flights f
   where f.world_id = p_world_id
     and f.dep_at >= (p_from::timestamp at time zone 'UTC') and f.dep_at < ((p_to + 1)::timestamp at time zone 'UTC')
  union all
  select f.airline_id, f.route_id, nullif(f.origin_code, ''), nullif(f.dest_code, ''), f.game_date, true, true,
         coalesce(f.eco_pax, 0) + coalesce(f.bus_pax, 0) + coalesce(f.fst_pax, 0),
         coalesce(f.eco_seats, 0) + coalesce(f.bus_seats, 0) + coalesce(f.fst_seats, 0),
         f.eco_pax, f.eco_seats, f.eco_fare, f.bus_pax, f.bus_seats, case when f.bus_seats > 0 then f.bus_fare end, null,
         f.income_total, f.cost_total
    from public.game_flights f
   where f.world_id = p_world_id and f.dep_at is null and f.flight_no is not null and f.game_date between p_from and p_to;

  delete from public.route_days r where r.world_id = p_world_id and r.day between p_from and p_to;
  insert into public.route_days (world_id, airline_id, route_id, origin_code, dest_code, day, flights, passengers, seats,
                                 revenue, costs, profit, eco_fare_avg, eco_pax, eco_seats, bus_pax, bus_seats, bus_fare_avg, block_min)
  select p_world_id, x.airline_id, max(x.route_id), x.origin_code, x.dest_code, x.day, count(*)::int,
         sum(x.pax)::int, sum(x.seats)::int,
         coalesce(sum(x.income), 0), coalesce(sum(x.costs), 0), coalesce(sum(x.income), 0) - coalesce(sum(x.costs), 0),
         round(coalesce(sum(x.eco_fare * x.eco_pax) filter (where x.eco_pax > 0)
                          / nullif(sum(x.eco_pax) filter (where x.eco_pax > 0 and x.eco_fare is not null), 0),
                        avg(x.eco_fare)), 2),
         sum(x.eco_pax)::int, sum(x.eco_seats)::int, sum(x.bus_pax)::int, sum(x.bus_seats)::int,
         round(coalesce(sum(x.bus_fare * x.bus_pax) filter (where x.bus_pax > 0)
                          / nullif(sum(x.bus_pax) filter (where x.bus_pax > 0 and x.bus_fare is not null), 0),
                        avg(x.bus_fare)), 2),
         sum(x.block_min)::int
    from pg_temp.t_history_flights x
   where x.is_flight and x.origin_code is not null and x.dest_code is not null
   group by x.airline_id, x.origin_code, x.dest_code, x.day;
  get diagnostics n_routes = row_count;

  update public.airline_days a
     set flights_flown = coalesce(v.flights, 0), passengers = coalesce(v.pax, 0), seats_flown = coalesce(v.seats, 0),
         load_pct = round(100.0 * v.loads_pax / nullif(v.seats, 0), 1),
         eco_load_pct = round(100.0 * v.eco_pax / nullif(v.eco_seats, 0), 1),
         revenue = coalesce(v.income, 0), flight_costs = coalesce(v.costs, 0),
         flight_profit = coalesce(v.income, 0) - coalesce(v.costs, 0),
         leases_paid = coalesce(p.leases, 0), salaries_paid = coalesce(p.salaries, 0), purchases_paid = coalesce(p.purchases, 0)
    from public.airline_days d
    left join lateral (
      select count(*) filter (where x.is_flight) as flights,
             sum(x.pax) filter (where x.is_flight) as pax,
             sum(x.seats) filter (where x.is_flight and x.has_loads) as seats,
             sum(x.pax) filter (where x.is_flight and x.has_loads) as loads_pax,
             sum(x.eco_pax) filter (where x.is_flight and x.has_loads) as eco_pax,
             sum(x.eco_seats) filter (where x.is_flight and x.has_loads) as eco_seats,
             sum(x.income) as income, sum(x.costs) as costs
        from pg_temp.t_history_flights x where x.airline_id = d.airline_id and x.day = d.day) v on true
    left join lateral (
      select sum(case when y.side = 'C' then -y.amount else y.amount end) filter (where y.kind = 'lease') as leases,
             sum(case when y.side = 'C' then -y.amount else y.amount end) filter (where y.kind = 'salaries') as salaries,
             sum(case when y.side = 'C' then -y.amount else y.amount end)
               filter (where y.kind in ('purchase', 'deposit', 'cabin', 'refit')) as purchases
        from public.game_payments y
       where y.airline_id = d.airline_id
         and y.paid_at >= (d.day::timestamp at time zone 'UTC') and y.paid_at < ((d.day + 1)::timestamp at time zone 'UTC')) p on true
   where a.airline_id = d.airline_id and a.day = d.day and d.world_id = p_world_id and d.day between p_from and p_to;
  get diagnostics n_days = row_count;
  truncate pg_temp.t_history_flights;
  return jsonb_build_object('route_days', n_routes, 'airline_days', n_days);
end
$function$;

-- ============================================================ 3. filled back for every day game_flights still holds
-- One statement: each route day's new columns from its flights in game_flights, the rows history_flows() reads (a flight's
-- day the UTC date it departs, or the game's date where that isn't known), matched by airline, airports and day. A day
-- game_flights no longer holds (none yet: it holds every flight since 6 Oct) keeps nulls.
do $backfill$
declare t0 timestamptz := clock_timestamp(); n int; n_all int; d0 date; d1 date; n_first int;
begin
  with x as (
    select f.world_id, f.airline_id, nullif(f.origin_code, '') as o, nullif(f.dest_code, '') as d,
           coalesce((f.dep_at at time zone 'UTC')::date, f.game_date) as day,
           case when f.flight_no is not null then f.eco_pax end as eco_pax, case when f.flight_no is not null then f.eco_seats end as eco_seats,
           case when f.flight_no is not null then f.bus_pax end as bus_pax, case when f.flight_no is not null then f.bus_seats end as bus_seats,
           case when f.flight_no is not null and f.bus_seats > 0 then f.bus_fare end as bus_fare,
           case when f.dep_at is not null and f.arr_at is not null then round(extract(epoch from f.arr_at - f.dep_at) / 60)::int end as block_min
      from public.game_flights f
     where (f.flight_no is not null or f.pax_income is not null) and (f.dep_at is not null or f.flight_no is not null)),
  a as (
    select x.world_id, x.airline_id, x.o, x.d, x.day,
           sum(x.eco_pax)::int as eco_pax, sum(x.eco_seats)::int as eco_seats, sum(x.bus_pax)::int as bus_pax, sum(x.bus_seats)::int as bus_seats,
           round(coalesce(sum(x.bus_fare * x.bus_pax) filter (where x.bus_pax > 0)
                            / nullif(sum(x.bus_pax) filter (where x.bus_pax > 0 and x.bus_fare is not null), 0),
                          avg(x.bus_fare)), 2) as bus_fare_avg,
           sum(x.block_min)::int as block_min
      from x where x.o is not null and x.d is not null
     group by x.world_id, x.airline_id, x.o, x.d, x.day)
  update public.route_days r
     set eco_pax = a.eco_pax, eco_seats = a.eco_seats, bus_pax = a.bus_pax, bus_seats = a.bus_seats,
         bus_fare_avg = a.bus_fare_avg, block_min = a.block_min
    from a
   where r.world_id = a.world_id and r.airline_id = a.airline_id and r.origin_code = a.o and r.dest_code = a.d and r.day = a.day;
  get diagnostics n = row_count;
  select count(*), min(r.day), max(r.day) into n_all, d0, d1 from public.route_days r;
  select count(*) into n_first from public.game_flights f where coalesce(f.fst_seats, 0) > 0;
  raise notice '%', format('route_days filled back: %s of %s rows (the daily history from %s to %s), in %s ms; game_flights rows with first-class seats: %s',
                           n, n_all, coalesce(d0::text, 'none'), coalesce(d1::text, 'none'),
                           round(extract(epoch from clock_timestamp() - t0) * 1000), n_first);
end
$backfill$;

-- ============================================================ 4. route_story(): a route's story since launch
CREATE OR REPLACE FUNCTION private.fig_route_story(p_route_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_today date := (p_as_of at time zone 'UTC')::date;
  w bigint; al bigint; v_code text; v_name text; v_hub text; v_dest text; v_pair text; v_removed boolean;
  v_route jsonb; v_launch date; v_launch_from text; v_latest date; v_from date; v_wfrom date; v_min numeric;
  v_out int := 0; v_back int := 0; v_rotations int := 0; v_types jsonb; v_ladder jsonb; v_fares jsonb;
  v_scan bigint; v_scan_at timestamptz; v_before bigint; v_before_at timestamptz; v_ids bigint[];
  v_days jsonb; v_weeks jsonb; v_changes jsonb; v_other jsonb; v_scanpart jsonb;
begin
  select r.world_id, r.airline_id, r.hub_code, r.dest_code, r.removed,
         jsonb_build_object(
           'id', r.id, 'hub', r.hub_code, 'dest', r.dest_code, 'pair', least(r.hub_code, r.dest_code) || '-' || greatest(r.hub_code, r.dest_code),
           'city', coalesce(r.city_override, r.city), 'stars', coalesce(r.stars_override, r.stars),
           'distance_km', coalesce(r.distance_override_km, r.distance_km), 'removed', r.removed,
           'market', case when mk.id is null then null else jsonb_build_object('id', mk.id, 'name', mk.name, 'layout', mk.layout) end,
           -- the cabin it calls for: its own choice, else its market's (Routes' header, since 21 Oct)
           'cabin', jsonb_build_object('layout', coalesce(nullif(r.cabin_choice, ''), mk.layout), 'own', nullif(r.cabin_choice, '') is not null,
                                       'market_layout', mk.layout))
    into w, al, v_hub, v_dest, v_removed, v_route
    from public.routes r
    left join public.markets mk on mk.id = case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end
   where r.id = p_route_id;
  if w is null then raise exception 'no such route: %', coalesce(p_route_id::text, 'none given') using errcode = '22023'; end if;
  v_pair := least(v_hub, v_dest) || '-' || greatest(v_hub, v_dest);
  select a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) into v_code, v_name from public.airlines a where a.id = al;
  v_min := private.fig_num(w, al, 'competition_threat_min_weekly');

  -- launched: its earliest rotation's launch day, as route profit and the fare ladder find a route's age; else its first
  -- day in the daily history
  select min(rt.launched_on) into v_launch from public.rotations rt where rt.route_id = p_route_id and rt.airline_id = al;
  if v_launch is not null then
    v_launch_from := 'rotation';
  else
    select min(d.day) into v_launch from public.route_days d
     where d.airline_id = al and d.flights > 0 and d.day <= v_today
       and ((d.origin_code = v_hub and d.dest_code = v_dest) or (d.origin_code = v_dest and d.dest_code = v_hub))
       and (d.route_id = p_route_id or d.route_id is null);
    if v_launch is not null then v_launch_from := 'history'; end if;
  end if;
  -- the latest captured day: the airline's latest day in the daily history by the moment
  select max(d.day) into v_latest from public.route_days d where d.airline_id = al and d.day <= v_today;
  -- the days from launch, or the last 90 if longer; the weeks, 13 blocks of 7 days ending on the latest captured day
  v_from := greatest(coalesce(v_launch, v_latest - 89), v_latest - 89);
  v_wfrom := greatest(coalesce(v_launch, v_latest - 90), v_latest - 90);

  -- ---------- now: the live schedule each way, the types flying it, the fare ladder's rows
  select coalesce(sum(cardinality(l.days_utc)) filter (where l.leg_no = 1), 0)::int,
         coalesce(sum(cardinality(l.days_utc)) filter (where l.leg_no = 2), 0)::int, count(distinct rt.id)::int
    into v_out, v_back, v_rotations
    from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
   where rt.route_id = p_route_id and rt.airline_id = al and not v_removed;
  select coalesce(jsonb_agg(jsonb_build_object('type_id', x.id, 'type', x.name, 'aircraft', x.n) order by x.n desc, x.name), '[]'::jsonb) into v_types
    from (select t.id, t.name, count(distinct a.id)::int as n
            from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
            join public.aircraft a on a.id = l.aircraft_id join public.aircraft_types t on t.id = a.aircraft_type_id
           where rt.route_id = p_route_id and rt.airline_id = al and not v_removed
           group by t.id, t.name) x;
  v_ladder := private.fig_fare_ladder(al, p_as_of);
  select coalesce(jsonb_agg(e - 'route_id' - 'hub' - 'dest' order by e ->> 'cabin' = 'business'), '[]'::jsonb) into v_fares
    from jsonb_array_elements(v_ladder -> 'routes') e where (e ->> 'route_id')::bigint = p_route_id;

  -- ---------- the days and the weeks, both directions together, from the daily history
  with rd as (
    select d.day, d.flights, d.passengers, d.seats, d.eco_pax, d.eco_seats, d.bus_pax, d.bus_seats, d.eco_fare_avg, d.bus_fare_avg,
           d.revenue, d.costs, d.profit, d.block_min,
           -- the passengers on the flights whose loads were captured (the flights seats counts): by cabin, else (a day
           -- before the cabins were kept) the passengers up to the seats
           case when d.eco_pax is not null or d.bus_pax is not null then coalesce(d.eco_pax, 0) + coalesce(d.bus_pax, 0)
                else least(d.passengers, d.seats) end as lpax,
           (v_latest - d.day) / 7 as wk
      from public.route_days d
     where d.airline_id = al and d.day between v_wfrom and v_latest and d.flights > 0
       and ((d.origin_code = v_hub and d.dest_code = v_dest) or (d.origin_code = v_dest and d.dest_code = v_hub))
       and (d.route_id = p_route_id or d.route_id is null)),
  g as (
    select true as is_day, rd.day as d0, rd.day as d1, count(distinct rd.day)::int as n_days,
           sum(rd.flights) as flights, sum(rd.passengers) as pax, sum(rd.seats) as seats, sum(rd.lpax) as lpax,
           sum(rd.eco_pax) as eco_pax, sum(rd.eco_seats) as eco_seats, sum(rd.bus_pax) as bus_pax, sum(rd.bus_seats) as bus_seats,
           sum(rd.eco_fare_avg * rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null) as eco_fx,
           sum(rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null) as eco_fn, avg(rd.eco_fare_avg) as eco_fa,
           sum(rd.bus_fare_avg * rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null) as bus_fx,
           sum(rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null) as bus_fn, avg(rd.bus_fare_avg) as bus_fa,
           sum(rd.revenue) as revenue, sum(rd.costs) as costs, sum(rd.profit) as profit, sum(rd.block_min) as block_min
      from rd where rd.day >= v_from group by rd.day
    union all
    select false, v_latest - rd.wk * 7 - 6, v_latest - rd.wk * 7, count(distinct rd.day)::int,
           sum(rd.flights), sum(rd.passengers), sum(rd.seats), sum(rd.lpax),
           sum(rd.eco_pax), sum(rd.eco_seats), sum(rd.bus_pax), sum(rd.bus_seats),
           sum(rd.eco_fare_avg * rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null),
           sum(rd.eco_pax) filter (where rd.eco_pax > 0 and rd.eco_fare_avg is not null), avg(rd.eco_fare_avg),
           sum(rd.bus_fare_avg * rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null),
           sum(rd.bus_pax) filter (where rd.bus_pax > 0 and rd.bus_fare_avg is not null), avg(rd.bus_fare_avg),
           sum(rd.revenue), sum(rd.costs), sum(rd.profit), sum(rd.block_min)
      from rd where rd.wk < 13 group by rd.wk),
  f as (
    select g.is_day, g.d0, g.d1,
           jsonb_build_object(
             'flights', g.flights, 'passengers', g.pax, 'seats', g.seats,
             'load_pct', round(100.0 * g.lpax / nullif(g.seats, 0), 1),
             'eco_pax', g.eco_pax, 'eco_seats', g.eco_seats, 'eco_load_pct', round(100.0 * g.eco_pax / nullif(g.eco_seats, 0), 1),
             'bus_pax', g.bus_pax, 'bus_seats', g.bus_seats, 'bus_load_pct', round(100.0 * g.bus_pax / nullif(g.bus_seats, 0), 1),
             'eco_fare', round(coalesce(g.eco_fx / nullif(g.eco_fn, 0), g.eco_fa), 2),
             'bus_fare', round(coalesce(g.bus_fx / nullif(g.bus_fn, 0), g.bus_fa), 2),
             'revenue', round(g.revenue / 1000000, 5), 'costs', round(g.costs / 1000000, 5), 'profit', round(g.profit / 1000000, 5),
             'block_hours', round(g.block_min / 60.0, 2),
             'profit_per_hour', case when g.block_min > 0 then round((g.profit / 1000000) / (g.block_min / 60.0), 5) end)
           || case when g.is_day then jsonb_build_object('day', g.d0)
                   else jsonb_build_object('from', g.d0, 'to', g.d1, 'days', g.n_days) end as o
      from g)
  select coalesce(jsonb_agg(f.o order by f.d0) filter (where f.is_day), '[]'::jsonb),
         coalesce(jsonb_agg(f.o order by f.d0 desc) filter (where not f.is_day), '[]'::jsonb)
    into v_days, v_weeks
    from f;

  -- ---------- events from the change log: the schedule's saves for this route's rotations and legs (each save, its
  -- txid, one event), and the route's own cabin choice. Changes made by a migration (data loads and fixes) aren't events.
  with rots as (
    select rt.id from public.rotations rt where rt.route_id = p_route_id
    union
    select (c.row_key ->> 'id')::bigint from public.change_log c
     where c.table_name = 'rotations' and c.world_id = w and c.op in ('insert', 'delete')
       and (coalesce(c.new_values, c.old_values) ->> 'route_id')::bigint = p_route_id),
  legs as (
    select l.id, l.flight_no from public.flight_legs l where l.rotation_id in (select rots.id from rots)
    union
    select (c.row_key ->> 'id')::bigint, (coalesce(c.new_values, c.old_values) ->> 'flight_no')::int from public.change_log c
     where c.table_name = 'flight_legs' and c.world_id = w and c.op in ('insert', 'delete')
       and (coalesce(c.new_values, c.old_values) ->> 'rotation_id')::bigint in (select rots.id from rots)),
  ch as materialized (
    select c.txid, c.changed_at, c.table_name, c.op, c.old_values, c.new_values, (c.row_key ->> 'id')::bigint as rid,
           (select max(lg.flight_no) from legs lg where lg.id = (c.row_key ->> 'id')::bigint) as fno
      from public.change_log c
     where c.world_id = w and c.changed_at <= p_as_of and coalesce(c.actor, '') <> 'migration'
       and ((c.table_name = 'rotations' and (c.row_key ->> 'id')::bigint in (select rots.id from rots))
         or (c.table_name = 'flight_legs' and (c.row_key ->> 'id')::bigint in (select legs.id from legs)))),
  sv as (
    select ch.txid, min(ch.changed_at) as at,
           bool_or(ch.table_name = 'rotations' and ch.op = 'insert') as added,
           bool_or(ch.table_name = 'rotations' and ch.op = 'delete') as removed,
           bool_or(ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ? 'aircraft_id') as ac,
           bool_or(ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ?| array['dep_utc_min', 'days_utc', 'block_min']) as timed,
           -- the rotations a save adds are the launch itself when each launched on the route's launch day or before
           coalesce(bool_and((ch.new_values ->> 'launched_on')::date <= v_launch) filter (where ch.table_name = 'rotations' and ch.op = 'insert'), false) as at_launch,
           string_agg(distinct ch.fno::text, '/' order by ch.fno::text) filter (where ch.table_name = 'flight_legs' and ch.op = 'insert') as nos_in,
           string_agg(distinct ch.fno::text, '/' order by ch.fno::text) filter (where ch.table_name = 'flight_legs' and ch.op = 'delete') as nos_out,
           min(case when jsonb_typeof(ch.new_values -> 'days_utc') = 'array' then jsonb_array_length(ch.new_values -> 'days_utc') end)
             filter (where ch.table_name = 'flight_legs' and ch.op = 'insert') as days_in,
           min(ch.new_values ->> 'days_utc') filter (where ch.table_name = 'flight_legs' and ch.op = 'insert') as days_in_text,
           string_agg(distinct ch.fno::text, '/' order by ch.fno::text) filter (where ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ? 'aircraft_id') as nos_ac,
           string_agg(distinct coalesce((select a.registration from public.aircraft a where a.id = (ch.new_values ->> 'aircraft_id')::bigint), 'no aircraft'), ', ')
             filter (where ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ? 'aircraft_id') as regs,
           string_agg(
             concat_ws(' ', coalesce(v_code || ' ' || ch.fno, 'a flight'),
                       case when ch.new_values ? 'dep_utc_min' then
                         format('%s → %s UTC', coalesce(to_char(make_interval(mins => (ch.old_values ->> 'dep_utc_min')::int), 'HH24:MI'), '—'),
                                coalesce(to_char(make_interval(mins => (ch.new_values ->> 'dep_utc_min')::int), 'HH24:MI'), '—')) end,
                       case when ch.new_values ? 'days_utc' then
                         format('days %s → %s', coalesce(translate(ch.old_values ->> 'days_utc', '[], ', ''), '—'),
                                coalesce(translate(ch.new_values ->> 'days_utc', '[], ', ''), '—')) end,
                       case when ch.new_values ? 'block_min' then
                         format('block %s → %s', coalesce(to_char(make_interval(mins => (ch.old_values ->> 'block_min')::int), 'FMHH24:MI'), '—'),
                                coalesce(to_char(make_interval(mins => (ch.new_values ->> 'block_min')::int), 'FMHH24:MI'), '—')) end),
             ', ' order by ch.fno, ch.rid)
             filter (where ch.table_name = 'flight_legs' and ch.op = 'update' and ch.new_values ?| array['dep_utc_min', 'days_utc', 'block_min']) as times
      from ch group by ch.txid),
  ev as (
    select (sv.at at time zone 'UTC')::date as day, sv.at,
           case when sv.added then 'frequency added' when sv.removed then 'frequency removed' when sv.ac then 'aircraft changed' else 'retimed' end as kind,
           case when sv.added then format('%s added, %s', coalesce(v_code || ' ' || sv.nos_in, 'a frequency'),
                                          case when sv.days_in = 7 then 'daily' when sv.days_in is not null then 'days ' || translate(sv.days_in_text, '[], ', '') else 'its days not given' end)
                when sv.removed then format('%s removed', coalesce(v_code || ' ' || sv.nos_out, 'a frequency'))
                when sv.ac then format('%s now on %s', coalesce(v_code || ' ' || sv.nos_ac, 'its flights'), sv.regs) || case when sv.timed then ' and retimed: ' || sv.times else '' end
                else sv.times end as words
      from sv
     where (sv.added and not sv.at_launch) or (not sv.added and (sv.removed or sv.ac or sv.timed)))
  select coalesce(jsonb_agg(jsonb_build_object('day', ev.day, 'kind', ev.kind, 'words', ev.words, 'at', private.fig_ts(ev.at))), '[]'::jsonb)
    into v_changes from ev;

  -- the fare plan's rows for the route (fare tests, and the ladder's moves with level_pct), and the route's cabin choice
  select coalesce(jsonb_agg(x.e), '[]'::jsonb) into v_other
    from (select jsonb_build_object(
                   'day', fp.proposed_on, 'kind', 'fare', 'cabin', coalesce(fp.cabin_class, 'economy'), 'level', fp.level_pct,
                   'change_pct', fp.change_pct, 'move', fp.ladder_move, 'dropped', fp.status = 'dropped', 'reason', fp.reason,
                   'words', case when fp.level_pct is not null
                                 then format('%s %s %s%%', coalesce(fp.cabin_class, 'economy'),
                                             case fp.ladder_move when 'up' then 'up to' when 'down' then 'down to' else 'holds at' end, trim_scale(fp.level_pct))
                                 else format('%s %s%s%% fare test', coalesce(fp.cabin_class, 'economy'),
                                             case when coalesce(fp.change_pct, 0) >= 0 then '+' else '−' end, trim_scale(abs(coalesce(fp.change_pct, 0)))) end
                            || case when fp.status = 'dropped' then ', dropped' else '' end) as e
            from public.fare_plan fp
           where fp.route_id = p_route_id and fp.airline_id = al and fp.proposed_on <= v_today
          union all
          select jsonb_build_object(
                   'day', (c.changed_at at time zone 'UTC')::date, 'kind', 'cabin', 'at', private.fig_ts(c.changed_at),
                   'cabin', nullif(c.new_values ->> 'cabin_choice', ''), 'before', nullif(c.old_values ->> 'cabin_choice', ''),
                   'words', case when nullif(c.new_values ->> 'cabin_choice', '') is null
                                 then format('own cabin %s cleared: its market''s from now', coalesce(nullif(c.old_values ->> 'cabin_choice', ''), ''))
                                 else format('cabin set to %s', c.new_values ->> 'cabin_choice')
                                      || case when nullif(c.old_values ->> 'cabin_choice', '') is not null
                                              then format(' (was %s)', c.old_values ->> 'cabin_choice') else '' end end)
            from public.change_log c
           where c.table_name = 'routes' and c.world_id = w and c.op = 'update' and (c.row_key ->> 'id')::bigint = p_route_id
             and c.new_values ? 'cabin_choice' and c.changed_at <= p_as_of and coalesce(c.actor, '') <> 'migration') x;

  -- ---------- the scans: the latest finished by the moment (with its schedules), and the week before as competition()
  -- picks it (the latest at least 6 days older, else the oldest there is)
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  if v_scan is not null then
    select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= v_scan_at - interval '6 days'
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
     order by s.taken_at desc, s.id desc limit 1;
    if v_before is null then
      select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
       where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of and s.id <> v_scan
         and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
       order by s.taken_at, s.id limit 1;
    end if;
  end if;
  -- every finished scan by the moment with its schedules, each with the one before it; read: the latest, the week before,
  -- and each scan since launch with the one before it
  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
    window o as (order by s.taken_at, s.id))
  select array_remove(array_agg(distinct z.id), null) into v_ids
    from (select v_scan as id union all select v_before
          union all select sc.id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'
          union all select sc.prev_id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC') z;

  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
    window o as (order by s.taken_at, s.id)),
  since as (select sc.* from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'),
  -- each airline's passenger departures a week on the pair, both ways, in each scan read (private.scan_pair_flights());
  -- every airline that isn't one of ours is a rival (competition analysis's rule)
  ex as materialized (
    select x.scan_id, x.airline_id, sum(x.weekly)::int as weekly, coalesce(g.kind, 'rival') <> 'ours' as rival,
           coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || x.airline_id) as name
      from private.scan_pair_flights(coalesce(v_ids, '{}'::bigint[]), array[v_pair]) x
      join public.airlines ra on ra.id = x.airline_id
      left join public.groups g on g.id = ra.group_id
     group by x.scan_id, x.airline_id, g.kind, ra.public_name, ra.game_name, ra.planner_name),
  -- a rival that started on the pair (none in the scan before) or added competition_threat_min_weekly a week, between
  -- each pair of consecutive scans since launch (competition_threats()'s rule)
  rv as (
    select s.id, s.taken_at, n.airline_id, n.name, coalesce(p.weekly, 0) as then_w, n.weekly as now_w
      from since s
      join ex n on n.scan_id = s.id and n.rival
      left join ex p on p.scan_id = s.prev_id and p.airline_id = n.airline_id
     where s.prev_id is not null and n.weekly > 0 and (coalesce(p.weekly, 0) = 0 or n.weekly - p.weekly >= v_min)),
  sh as (
    select s.id, s.taken_at,
           coalesce((select sum(e.weekly) from ex e where e.scan_id = s.id and e.airline_id = al), 0)::int as ours,
           coalesce((select sum(e.weekly) from ex e where e.scan_id = s.id and e.rival), 0)::int as rivals
      from since s),
  lt as (
    select e.airline_id, e.name, e.weekly, b.weekly as before_w
      from ex e left join ex b on b.scan_id = v_before and b.airline_id = e.airline_id
     where e.scan_id = v_scan and e.rival),
  tot as (select coalesce(sum(lt.weekly), 0)::int as rivals from lt),
  bt as (select coalesce(sum(e.weekly) filter (where e.rival), 0)::int as rivals,
                coalesce(sum(e.weekly) filter (where e.airline_id = al), 0)::int as ours
           from ex e where e.scan_id = v_before)
  select jsonb_build_object(
           'events', (select coalesce(jsonb_agg(jsonb_build_object(
                         'day', (rv.taken_at at time zone 'UTC')::date, 'kind', 'rival', 'at', private.fig_ts(rv.taken_at), 'scan_id', rv.id,
                         'rival_id', rv.airline_id, 'rival', rv.name, 'change', case when rv.then_w = 0 then 'started' else 'added' end,
                         'then', rv.then_w, 'now', rv.now_w, 'added', rv.now_w - rv.then_w,
                         'words', case when rv.then_w = 0 then format('%s started here, %s a week', rv.name, rv.now_w)
                                       else format('%s added %s a week (%s → %s)', rv.name, rv.now_w - rv.then_w, rv.then_w, rv.now_w) end)), '[]'::jsonb)
                        from rv),
           'rivals', jsonb_build_object(
             'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
             'week_before', case when v_before is null then null else jsonb_build_object('id', v_before, 'taken_at', private.fig_ts(v_before_at)) end,
             -- ours: the live schedule, both ways (competition()'s); before: the airline's flights in the week-before scan
             'ours', v_out + v_back, 'rivals_weekly', (select tot.rivals from tot),
             'share', case when v_scan is not null then round(100.0 * (v_out + v_back) / nullif(v_out + v_back + (select tot.rivals from tot), 0), 1) end,
             'ours_before', case when v_before is not null then (select bt.ours from bt) end,
             'rivals_before', case when v_before is not null then (select bt.rivals from bt) end,
             'share_before', case when v_before is not null then (select round(100.0 * bt.ours / nullif(bt.ours + bt.rivals, 0), 1) from bt) end,
             'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                             'airline_id', lt.airline_id, 'name', lt.name, 'weekly', lt.weekly,
                             'weekly_before', case when v_before is not null then coalesce(lt.before_w, 0) end,
                             'change', case when v_before is not null then lt.weekly - coalesce(lt.before_w, 0) end)
                             order by lt.weekly desc, lt.name), '[]'::jsonb) from lt),
             -- our share at each finished scan since launch: the airline's departures in the scan against every rival's
             'shares', (select coalesce(jsonb_agg(jsonb_build_object(
                           'scan_id', sh.id, 'taken_at', private.fig_ts(sh.taken_at), 'ours', sh.ours, 'rivals', sh.rivals,
                           'share', round(100.0 * sh.ours / nullif(sh.ours + sh.rivals, 0), 1)) order by sh.taken_at, sh.id), '[]'::jsonb) from sh)),
           'used', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', private.fig_ts(s.taken_at)) order by s.taken_at, s.id), '[]'::jsonb)
                      from since s))
    into v_scanpart;

  return jsonb_build_object(
    'route_id', p_route_id, 'as_of', private.fig_ts(p_as_of), 'latest_day', v_latest,
    'route', v_route || jsonb_build_object(
      'airline', jsonb_build_object('id', al, 'code', v_code, 'name', v_name),
      'launched', v_launch, 'launched_from', v_launch_from,
      'launched_days', case when v_launch is not null then v_today - v_launch end),
    'now', jsonb_build_object(
      'departures', jsonb_build_object('out', v_out, 'back', v_back), 'rotations', v_rotations, 'types', v_types,
      'fares', v_fares, 'launch_pct', v_ladder #> '{settings,launch_pct}', 'week_of', v_ladder -> 'week_of'),
    'days', v_days,
    'weeks', v_weeks,
    'events', (select coalesce(jsonb_agg(x.e order by (x.e ->> 'day')::date desc,
                                          array_position(array['rival', 'fare', 'cabin', 'retimed', 'aircraft changed', 'frequency removed',
                                                               'frequency added', 'launched'], x.e ->> 'kind'),
                                          x.e ->> 'at' desc nulls last, x.e ->> 'words'), '[]'::jsonb)
                 from (select jsonb_array_elements(v_changes) as e
                       union all select jsonb_array_elements(v_other)
                       union all select jsonb_array_elements(v_scanpart -> 'events')
                       union all select jsonb_build_object('day', v_launch, 'kind', 'launched',
                                                           'words', case v_launch_from when 'rotation' then 'launched' else 'first flights in the daily history' end)
                                  where v_launch is not null and v_launch <= v_today) x),
    'rivals', v_scanpart -> 'rivals',
    'scans', jsonb_build_object(
      'latest', v_scanpart #> '{rivals,scan}', 'week_before', v_scanpart #> '{rivals,week_before}', 'since_launch', v_scanpart -> 'used'),
    'notes', jsonb_build_array(
      'Both directions together, from the daily history (route_days): a day is a UTC day, and one with no flights is left out. load_pct is the passengers on the flights whose loads were captured over their seats; profit_per_hour is profit (millions of AS$) over block hours (the scheduled block of the flights that have one). Weeks are 7-day blocks ending on latest_day, newest first.',
      'Events: the schedule''s saves from the change log (one per save; changes a migration made left out; the rotations that are the launch itself not repeated), the fare plan''s rows, the route''s own cabin choice, and rivals that started or added competition_threat_min_weekly a week between consecutive scans since launch (passenger flights only).',
      'Rivals are every airline in the scan that isn''t one of ours; ours now are the live schedule both ways, ours in a scan the airline''s flights in it.'));
end
$function$;

CREATE OR REPLACE FUNCTION public.route_story(p_route_id bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_route_story(p_route_id, coalesce(p_as_of, now()));
end
$function$;

-- ============================================================ 5. grants and descriptions
revoke all on function private.history_flows(bigint, date, date) from public, anon, authenticated, service_role;
revoke all on function private.fig_route_story(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.route_story(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.route_story(bigint, timestamptz) to authenticated;

comment on function private.history_flows(bigint, date, date) is 'The daily history''s flows for a span of UTC days (design §7): route_days replaced for those days, and each airline_days row of those days given its flights, passengers, seats, loads, money and payments, from game_flights and game_payments. Since 22 Oct each route day also keeps its economy and business passengers and seats, the average business fare and the flights'' scheduled block (eco_pax, eco_seats, bus_pax, bus_seats, bus_fare_avg, block_min). Returns how many rows of each it wrote.';
comment on function private.fig_route_story(bigint, timestamptz) is 'The captured figures (#19): builds route_story()''s document with no check of its own. See route_story().';
comment on function public.route_story(bigint, timestamptz) is 'A route''s story since launch (spec docs/specs/2026-10-21-route-page.md §2), as of p_as_of: the planner''s route page (/planner/performance/<code>/<route>), and the Scheduling chat''s "how has this route done since launch, and what changed on it". The route is its airline''s hub and destination; both directions are counted together. route: id, hub, dest, pair, city, stars, distance_km (overrides applied), market (id, name, layout), cabin (layout: its own cabin_choice, else its market''s, as Routes'' header; own; market_layout), removed, airline (id, code, name), launched (its earliest rotation''s launch day, as route profit and the fare ladder find a route''s age, else its first day in route_days; launched_from rotation or history; launched_days). now: departures a week each way from the live schedule (out from the hub, back), rotations, the aircraft types flying it with how many aircraft, fares (fare_ladder()''s rows for the route, economy first: level, steps, this Saturday''s move, new_level, reason, planned, applied, to_plan, fix, fare_index and the rest), launch_pct and week_of. latest_day: the airline''s latest day in the daily history by the moment. days: one row per UTC day with flights, from launch or the last 90 days if longer to latest_day (route_days, both directions; rows of no route matched by the airports): flights, passengers, seats, load_pct (passengers on the flights whose loads were captured ÷ their seats), eco_ and bus_ passengers, seats and load_pct, eco_fare and bus_fare (weighted by passengers), revenue, costs and profit (millions of AS$), block_hours and profit_per_hour (profit ÷ block hours). weeks: the same in 7-day blocks ending on latest_day (from, to, days with flights), newest first, at most 13. events, newest first, each with day, kind and words: launched; frequency added, frequency removed, aircraft changed and retimed from change_log on rotations and flight_legs (one per save, its txid; a save''s rotations that are the launch itself and a migration''s changes left out); fare, each fare_plan row (cabin, level or change_pct, move, dropped); cabin, the route''s cabin_choice changed; rival, a rival that started on the pair or added settings.competition_threat_min_weekly departures a week between consecutive finished scans since launch with their schedules (private.scan_pair_flights(), passenger flights only, as competition_threats()). rivals: from the latest finished scan (scan) with the week-before scan (week_before, as competition() picks it), every rival flying the pair either way with its departures a week, before and change; ours (the live schedule, both ways), rivals_weekly and our share; ours_before, rivals_before and share_before (the airline''s flights in the week-before scan, as competition()''s me_then); shares, our share at each finished scan since launch (scan_id, taken_at, ours, rivals, share). scans: latest, week_before and since_launch with their dates. notes say how it reads. Staff only; runs as owner and checks the caller itself. Read with GET.';

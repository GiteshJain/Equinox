-- Add a flight or raise fares, by profit per aircraft hour (17 Oct; brief docs/briefs/2026-10-17-add-or-raise.md, B;
-- manual §3). A sold-out route was marked add when its profit a flight was at or above its airline's middle route, and
-- raise fares when below; that favoured long routes, which earn more a flight because they take longer. The mark now
-- compares profit per aircraft hour: the route's average flight's profit ÷ its aircraft hours, each leg's block time plus
-- the type's turnaround (aircraft_types.min_turn_min) and the turn margin (settings.turn_margin_min), the hours the
-- aircraft can fly nothing else. The middle route is the airline's median profit an aircraft hour. A route with no legs
-- on record (so no hours) is still compared by profit a flight. Each route also gives its aircraft_hours and
-- profit_per_aircraft_hour. The fix, losing-money and cash rules don't change.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: add or raise by aircraft hour', true);

CREATE OR REPLACE FUNCTION private.fig_route_profit(p_airline_id bigint, p_days integer, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_since timestamptz; v_pnl jsonb; v_loads jsonb; v_used boolean[]; v_mp int[] := '{}'; v_ml int[] := '{}';
  c record; v_cur int := -1; v_got boolean := false;
  v_losing numeric; v_sold_share numeric; v_sold_min numeric; v_fix_min numeric; v_fix_eco numeric; v_fix_routes numeric; v_fix_margin numeric; v_new_days numeric;
  v_margin_min numeric; v_allow_min numeric;
begin
  if p_days is null or p_days < 1 then raise exception 'p_days must be 1 or more' using errcode = '22023'; end if;
  v_losing := private.fig_num(w, p_airline_id, 'growth_losing_min_departures');
  v_sold_share := private.fig_num(w, p_airline_id, 'growth_sold_out_share');
  v_sold_min := private.fig_num(w, p_airline_id, 'growth_sold_out_min_departures');
  v_fix_min := private.fig_num(w, p_airline_id, 'growth_fix_min_departures');
  v_fix_eco := private.fig_num(w, p_airline_id, 'growth_fix_economy_pct');
  v_fix_routes := private.fig_num(w, p_airline_id, 'growth_fix_min_routes');
  v_fix_margin := private.fig_num(w, p_airline_id, 'growth_fix_margin');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  v_margin_min := private.fig_num(w, p_airline_id, 'turn_margin_min');
  v_allow_min := private.fig_num(w, p_airline_id, 'block_allowance_min');
  -- the statement blocks posted since now − p_days (inside the old planner's window of 8 UTC days), as game_flight_pnl
  -- groups them: one per minute and block, its route when its lines name one, and its money
  v_since := greatest(p_as_of - p_days * interval '24 hours', (v_today - 8)::timestamp at time zone 'UTC');
  with money as (
    select f.posted_at as ts, f.statement_blk::int as blk, f.statement_routes::int as routes_n,
           case when f.statement_routes > 0 then f.origin_code || '-' || f.dest_code end as route,
           f.maint_registration as tail, f.pax_income, f.cargo_income, f.fuel, f.onboard, f.handling, f.landing, f.atc, f.maintenance,
           f.income_total as income, f.cost_total as costs
      from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at >= v_since and coalesce(f.money_captured_at, f.posted_at) <= p_as_of
    union all
    select p.paid_at, p.statement_blk::int, 0, null, null, null, null, null, null, null, null, null, null,
           case when p.side = 'C' then p.amount else 0 end, case when p.side = 'C' then 0 else p.amount end
      from public.game_payments p
     where p.airline_id = p_airline_id and p.paid_at >= v_since and p.created_at <= p_as_of
       and coalesce(p.statement_blk::int, 1) > 0 and p.kind = 'other'),
  pnl as (
    select m.ts, m.blk, max(m.route) as route, coalesce(max(m.routes_n), 0) as routes_n, max(m.tail) as tail,
           coalesce(sum(m.pax_income), 0) as pax_income, coalesce(sum(m.cargo_income), 0) as cargo_income,
           coalesce(sum(m.fuel), 0) as fuel, coalesce(sum(m.onboard), 0) as onboard, coalesce(sum(m.handling), 0) as handling,
           coalesce(sum(m.landing), 0) as landing, coalesce(sum(m.atc), 0) as atc, coalesce(sum(m.maintenance), 0) as maintenance,
           coalesce(sum(m.income) - sum(m.costs), 0) as profit
      from money m group by m.ts, m.blk)
  select coalesce(jsonb_agg(to_jsonb(x) order by x.i), '[]'::jsonb) into v_pnl
    from (select pnl.*, (row_number() over (order by pnl.ts, pnl.blk nulls first))::int as i from pnl) x;
  -- the loads of the last 9 days (CAP.loads: one per date and flight number) with a route and departure time, each
  -- departure in UTC from its origin's offset in the world, with its correction (capDepUTC; since the clean-up)
  select coalesce(jsonb_agg(to_jsonb(y) order by y.j), '[]'::jsonb) into v_loads
    from (select x.*, (row_number() over (order by x.id))::int as j,
                 private.local_to_utc(x.game_date, x.dep_local, coalesce(private.airport_offset_min(w, x.origin), 0)) as dep_utc
            from (select distinct on (f.game_date, f.flight_no) f.id, f.game_date, f.flight_no, f.origin_code as origin,
                         f.dest_code as dest, f.dep_local, f.registration, f.eco_pct as eco, f.bus_pct as bus,
                         f.cargo_pct as cargo, trim_scale(f.eco_fare) as eco_fare
                    from public.game_flights f
                   where f.airline_id = p_airline_id and f.flight_no is not null and f.game_date >= v_today - 9
                     and f.loads_captured_at <= p_as_of
                   order by f.game_date, f.flight_no, f.id desc) x
           where coalesce(x.origin, '') <> '' and coalesce(x.dest, '') <> '' and coalesce(x.dep_local, '') <> '') y;

  -- each one-route block, in order, takes the nearest loads row of its route departing within 31 minutes that no earlier
  -- block took (the first in the list on a tie)
  v_used := array_fill(false, array[greatest(jsonb_array_length(v_loads), 1)]);
  for c in
    select p.i, l.j
      from jsonb_to_recordset(v_pnl) as p(i int, ts timestamptz, route text, routes_n int)
      join jsonb_to_recordset(v_loads) as l(j int, origin text, dest text, dep_utc timestamptz)
        on p.routes_n = 1 and p.route is not null and l.dep_utc is not null
       and l.origin = split_part(p.route, '-', 1) and l.dest = split_part(p.route, '-', 2)
       and abs(extract(epoch from (l.dep_utc - p.ts))) < 1860
     order by p.i, abs(extract(epoch from (l.dep_utc - p.ts))), l.j
  loop
    if c.i <> v_cur then v_cur := c.i; v_got := false; end if;
    if v_got or v_used[c.j] then continue; end if;
    v_used[c.j] := true; v_got := true;
    v_mp := v_mp || c.i; v_ml := v_ml || c.j;
  end loop;

  return (
    with p as (select * from jsonb_to_recordset(v_pnl) as x(i int, ts timestamptz, route text, routes_n int, tail text, profit numeric,
                                                             pax_income numeric, cargo_income numeric, fuel numeric, onboard numeric,
                                                             handling numeric, landing numeric, atc numeric, maintenance numeric)),
    l as (select * from jsonb_to_recordset(v_loads) as x(j int, game_date date, origin text, dest text, registration text,
                                                          eco numeric, bus numeric, cargo numeric, eco_fare numeric)),
    m as (select * from unnest(v_mp, v_ml) as m(i, j)),
    fl as (select p.*, split_part(p.route, '-', 1) as o, split_part(p.route, '-', 2) as d, l.j, l.eco, l.bus, l.cargo, l.eco_fare,
                  coalesce(nullif(l.registration, ''), nullif(p.tail, '')) as reg
             from p left join m on m.i = p.i left join l on l.j = m.j
            where p.route is not null and p.routes_n = 1),
    -- keyOf(): the route as the airline's list has it, either way round, else as flown (materialized: worked out once,
    -- not again for each flight joined to it)
    rk as materialized (select distinct fl.o, fl.d, coalesce(r1.id, r2.id) as route_id,
                  coalesce(r1.hub_code, r2.hub_code, fl.o) as hub, coalesce(r1.dest_code, r2.dest_code, fl.d) as dest
             from fl
             left join public.routes r1 on r1.airline_id = p_airline_id and not r1.removed and r1.hub_code = fl.o and r1.dest_code = fl.d
             left join public.routes r2 on r2.airline_id = p_airline_id and not r2.removed and r2.hub_code = fl.d and r2.dest_code = fl.o),
    -- the airline's rotations (an aircraft flies only its own airline's rotations, so legsDay's rotations by aircraft are
    -- among them)
    fq as (select * from private.fig_freqs(w, p_airline_id)),
    wk as (select f.route_id, sum(f.flights_week)::int as wk from fq f where f.live and f.airline_id = p_airline_id group by f.route_id),
    -- a route's age: its earliest rotation's launch day (a second daily added later doesn't make an old route new)
    age as (select f.route_id, min(f.launched_on) as first_day from fq f where f.airline_id = p_airline_id group by f.route_id),
    -- a route's aircraft hours a flight (manual §3, 17 Oct): each of its legs' block time (or, untimed, the estimate:
    -- block_allowance_min + distance ÷ the type's cruise speed) plus the type's turnaround (min_turn_min) and the turn
    -- margin (turn_margin_min), averaged over the flights a week each leg flies
    hrs as (select ro.id as route_id,
                   sum((coalesce(l.block_min, round(ro.distance_km / ty.cruise_kmh * 60 + v_allow_min)) + ty.min_turn_min + v_margin_min)
                       * coalesce(cardinality(l.days_utc), 7))::numeric
                     / nullif(sum(coalesce(cardinality(l.days_utc), 7)), 0) / 60 as h
              from public.rotations rt
              join public.routes ro on ro.id = rt.route_id
              join public.flight_legs l on l.rotation_id = rt.id
              join public.aircraft a on a.id = l.aircraft_id
              join public.aircraft_types ty on ty.id = a.aircraft_type_id
             where rt.airline_id = p_airline_id and ty.min_turn_min is not null
               and (l.block_min is not null or (ro.distance_km is not null and ty.cruise_kmh > 0))
             group by ro.id),
    g as (select rk.hub, rk.dest, rk.route_id, count(*)::int as n, sum(fl.profit) / 1000000 as profit,
                 sum(fl.pax_income + fl.cargo_income) / 1000000 as income,
                 avg(fl.eco) as eco_a, avg(fl.bus) as bus_a, avg(fl.cargo) as cargo_a, avg(fl.eco_fare) as fare_a,
                 count(fl.eco)::int as eco_n, (count(*) filter (where fl.eco >= 100))::int as sold, min(fl.i) as first_i
            from fl join rk on rk.o = fl.o and rk.d = fl.d
           group by rk.hub, rk.dest, rk.route_id),
    r as (select g.*, g.profit / g.n as ppf, case when g.income > 0 then g.profit / g.income end as margin,
                 coalesce(wk.wk, 0) as wk, (g.profit / g.n) * coalesce(wk.wk, 0) as pwk,
                 case when g.eco_n > 0 then g.sold::numeric / g.eco_n end as sold_share,
                 -- young: launched fewer than growth_new_route_days days ago; no launch day on record counts as old
                 coalesce(ag.first_day is not null and v_today - ag.first_day < v_new_days, false) as young,
                 hh.h as hours, case when hh.h > 0 then (g.profit / g.n) / hh.h end as pph
            from g left join wk on wk.route_id = g.route_id left join age ag on ag.route_id = g.route_id
            left join hrs hh on hh.route_id = g.route_id),
    pp as (select array_agg(r.ppf order by r.ppf) as a, array_agg(r.pph order by r.pph) filter (where r.pph is not null) as h from r),
    -- the middle route: by profit a flight, and by profit an aircraft hour among the routes with their hours
    q as (select pp.a[floor(cardinality(pp.a) / 2.0)::int + 1] as med, pp.a[floor(cardinality(pp.a) * 0.25)::int + 1] as q25,
                 pp.h[floor(cardinality(pp.h) / 2.0)::int + 1] as med_h,
                 coalesce(cardinality(pp.a), 0) as len from pp),
    mk as (select r.*, case when r.ppf < 0 and r.n >= v_losing and not r.young then 'losing'
                            when r.sold_share is not null and r.sold_share >= v_sold_share and r.n >= v_sold_min
                              -- add at or above the middle route's profit an aircraft hour, raise below; a route with no
                              -- aircraft hours (no legs on record) is compared by profit a flight, as before 17 Oct
                              then case when r.pph is not null and q.med_h is not null then case when r.pph >= q.med_h then 'add' else 'raise' end
                                        when r.ppf >= q.med then 'add' else 'raise' end
                            when r.n >= v_fix_min and not r.young and r.eco_a is not null and r.eco_a < v_fix_eco then 'fix'
                            when r.n >= v_fix_min and not r.young and q.len >= v_fix_routes and r.ppf <= q.q25 and r.margin is not null and r.margin < v_fix_margin then 'fix-margin'
                            else 'hold' end as k, q.med, q.med_h
             from r cross join q),
    routes as (select coalesce(jsonb_agg(jsonb_build_object(
                 'route_id', mk.route_id, 'hub', mk.hub, 'dest', mk.dest, 'flights', mk.n, 'profit', mk.profit, 'income', mk.income,
                 'margin', mk.margin, 'profit_per_flight', mk.ppf, 'flights_week', mk.wk, 'profit_week', mk.pwk,
                 'aircraft_hours', mk.hours, 'profit_per_aircraft_hour', mk.pph,
                 'economy', mk.eco_a, 'business', mk.bus_a, 'cargo', mk.cargo_a, 'economy_fare', mk.fare_a,
                 'sold_out', mk.sold, 'with_loads', mk.eco_n, 'sold_out_share', mk.sold_share,
                 'mark', case when mk.k = 'fix-margin' then 'fix' else mk.k end,
                 'why', case mk.k when 'losing' then 'its average flight loses money'
                                  when 'add' then format('sold out on %s of %s departures, profit %s at or above the airline''s middle route', mk.sold, mk.eco_n,
                                                         case when mk.pph is not null and mk.med_h is not null then 'an aircraft hour' else 'a flight' end)
                                  when 'raise' then format('sold out on %s of %s departures, profit %s below the airline''s middle route', mk.sold, mk.eco_n,
                                                           case when mk.pph is not null and mk.med_h is not null then 'an aircraft hour' else 'a flight' end)
                                  when 'fix' then format('economy averaging %s%%', floor(mk.eco_a + 0.5))
                                  when 'fix-margin' then format('bottom-quarter profit a flight on a margin under %s%%', floor(v_fix_margin * 100 + 0.5))
                                  else '' end)
                 order by mk.pwk desc, mk.ppf desc, mk.first_i), '[]'::jsonb) as v from mk),
    -- the aircraft: each one's average flight × its scheduled flights a day, plus its statement lines without a route
    -- spread over the days captured, less its lease a day (the last leasing payment the events list for it, ÷ 7)
    lease as materialized (select distinct on (x.reg) x.reg, x.amount
                from (select (regexp_match(e.descr, 'Leasing payment for ([A-Z0-9-]+)'))[1] as reg, e.amount, e.event_date, e.event_time
                        from private.fig_events(w, p_as_of, p_airline_id) e where e.airline_id = p_airline_id) x
               where x.reg is not null order by x.reg, x.event_date desc, x.event_time desc),
    extra as (select p.tail as reg, sum(p.profit) / 1000000 as v from p where p.route is null and coalesce(p.tail, '') <> '' group by p.tail),
    capdays as (select greatest(1, least(p_days, count(distinct (p.ts at time zone 'UTC')::date)))::int as v from p),
    legs as (select f.tail as reg, sum(f.flights_week::numeric / 7) as v from fq f group by f.tail),
    tl as (select fl.reg, count(*)::int as n, sum(fl.profit) / 1000000 as profit, min(fl.i) as first_i
             from fl where fl.reg is not null group by fl.reg),
    t as (select tl.*, (tl.profit / tl.n) * coalesce(nullif(lg.v, 0), tl.n) + coalesce(ex.v, 0) / cd.v as day, ls.amount / 7 as ls,
                 coalesce((select ty.name from public.aircraft a join public.aircraft_types ty on ty.id = a.aircraft_type_id
                            where a.world_id = w and a.registration = tl.reg and a.status = 'active' limit 1), '') as type,
                 (select coalesce(jsonb_agg(z.lab order by z.fi), '[]'::jsonb)
                    from (select fl2.o || '–' || fl2.d as lab, min(fl2.i) as fi from fl fl2 where fl2.reg = tl.reg group by 1) z) as routes
            from tl cross join capdays cd
            left join legs lg on lg.reg = tl.reg left join extra ex on ex.reg = tl.reg left join lease ls on ls.reg = tl.reg),
    aircraft as (select coalesce(jsonb_agg(jsonb_build_object(
                   'registration', t.reg, 'type', t.type, 'flights', t.n, 'flight_profit_day', t.day, 'lease_day', t.ls,
                   'net_day', t.day - t.ls, 'routes', t.routes)
                   order by coalesce(t.day - t.ls, t.day) desc, t.first_i), '[]'::jsonb) as v from t),
    -- the fare changes: each route's average captured economy fare by date against the date before, over 1% apart
    fd as (select l.origin, l.dest, l.game_date, avg(l.eco_fare) as fare, avg(l.eco) as eco
             from l where l.eco_fare is not null group by l.origin, l.dest, l.game_date),
    ch as (select fd.*, lag(fd.fare) over w1 as prev_fare, lag(fd.eco) over w1 as prev_eco
             from fd window w1 as (partition by fd.origin, fd.dest order by fd.game_date)),
    changes as (select coalesce(jsonb_agg(jsonb_build_object(
                  'origin', ch.origin, 'dest', ch.dest, 'date', ch.game_date, 'fare_before', ch.prev_fare, 'fare_after', ch.fare,
                  'economy_before', ch.prev_eco, 'economy_after', ch.eco)
                  order by ch.game_date desc, ch.origin, ch.dest), '[]'::jsonb) as v
                  from ch where ch.prev_fare is not null and ch.prev_fare <> 0 and ch.fare <> 0 and abs(ch.fare - ch.prev_fare) / ch.prev_fare > 0.01),
    av as (select count(*)::int as n,
                  jsonb_build_object('passengers', sum(fl.pax_income), 'cargo', sum(fl.cargo_income), 'fuel', sum(fl.fuel),
                                     'handling', sum(fl.handling), 'onboard', sum(fl.onboard), 'landing', sum(fl.landing),
                                     'air_traffic', sum(fl.atc), 'maintenance', sum(fl.maintenance)) as sums,
                  count(*) filter (where fl.j is not null)::int as matched
             from fl)
    select jsonb_build_object(
             'airline_id', p_airline_id, 'days', p_days, 'as_of', private.fig_ts(p_as_of), 'since', private.fig_ts(v_since),
             'flights', av.n, 'matched', av.matched, 'mixed', (select count(*)::int from p where p.routes_n > 1),
             'average_flight', case when av.n = 0 then null
                                    else (select jsonb_object_agg(e.key, (e.value #>> '{}')::numeric / av.n / 1000000) from jsonb_each(av.sums) e) end,
             'routes', (select v from routes), 'aircraft', (select v from aircraft), 'fare_changes', (select v from changes))
      from av);
end
$function$;

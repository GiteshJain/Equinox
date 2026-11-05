-- Shared city pairs, pull request 2 of 2: growth, openings, the route page and the report's figures (5 Nov 2026; spec
-- docs/specs/2026-11-05-shared-pairs.md §3, §4 and §5; brief docs/briefs/2026-11-04-shared-pairs.md, option B with Ryanair
-- out). Pull request 1 (20261105000000_shared_pairs.sql) added the joiner's route row, the view shared_pairs, join_pair()
-- and the pair's one fare ladder. This one makes the other figures read a joined pair as one market:
--
-- Adds three functions and replaces six with the same arguments; changes, drops and renames nothing else, so it can be
-- applied from the chat (no delete, drop or truncate):
--   - private.fig_route_pair(p_route_id): the route's place on a joined pair (owner or joiner) and the other route.
--   - private.fig_pair_side(p_route_id, p_days, p_as_of): one airline's flights, loads and profit on its route of the pair
--     over route profit's window, as route_profit() counts them, for the other airline's rows.
--   - public.shared_pairs_status(p_world_id, p_as_of): the group Performance page's Shared pairs row: every joined pair,
--     both airlines' flights a week, the pair's load over 7 days, its level each way and the 6-pair limit while it holds.
--   - private.fig_route_profit(): a shared pair's rows carry shared_role and pair (the other airline's flights, flights a
--     week, loads and profit on the pair, and the pair's combined figures); sold out, ready for another flight, losing and
--     fix or reduce are judged on both airlines' flights together.
--   - private.fig_growth_signals(): a joined pair is listed once, under its owner, with shared_with; the joiner's row goes
--     to follows with the owner's mark.
--   - private.fig_competition(): openings on a shared pair carry shared (role, the other airline); a joiner's unflown shared
--     pair (on its list or not) is an opening only while the owner's cash forecast can't order that evening, marked "owner
--     can't fund tonight" (worked out only when openings are listed: p_limit above 0).
--   - private.fig_fare_results(): a joiner's directions take the owner's fare plan rows (the pair's moves, its direction
--     the other way round) with their before and after figures its own, marked follows.
--   - public.route_story(): for a route on a joined pair, private.fig_pair_story(): both airlines' stories as one page.
--   - private.fig_pair_story(p_route_id, p_as_of): the pair's story: combined days, weeks and departures, each airline's
--     own flights, revenue and profit, and one timeline with each event marked with its airline.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261105010000_shared_pairs_figures', true);

-- ============================================================ 1. the pair of a route, and one airline's side of it
create or replace function private.fig_route_pair(p_route_id bigint)
 returns table (role text, owner_route_id bigint, joiner_route_id bigint, other_route_id bigint, other_airline_id bigint)
 language sql
 stable
 set search_path to ''
as $function$
  select 'joiner'::text, o.id, j.id, o.id, o.airline_id
    from public.routes j join public.routes o on o.id = j.shares_route_id
   where j.id = p_route_id and not j.removed and not o.removed
  union all
  select 'owner'::text, o.id, j.id, j.id, j.airline_id
    from public.routes o join public.routes j on j.shares_route_id = o.id and not j.removed
   where o.id = p_route_id and not o.removed
$function$;
revoke all on function private.fig_route_pair(bigint) from public, anon, authenticated, service_role;
comment on function private.fig_route_pair(bigint) is 'A route''s place on a joined shared pair (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §3–§4): one row when the route is the owner''s (role owner, a joiner''s row names it in shares_route_id) or the joiner''s (role joiner), with the owner''s and the joiner''s route ids, the other route and its airline; no row for a route on no joined pair or a removed one. Internal: route profit, fare results and the route story read it.';

create or replace function private.fig_pair_side(p_route_id bigint, p_days integer, p_as_of timestamp with time zone)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare r record; v_today date := (p_as_of at time zone 'UTC')::date; v_since timestamptz;
  v_n int; v_profit numeric; v_income numeric; v_eco numeric; v_sold int; v_eco_n int; v_week int; v_first date;
begin
  select ro.id, ro.airline_id, ro.hub_code, ro.dest_code, a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) as name
    into r from public.routes ro join public.airlines a on a.id = ro.airline_id where ro.id = p_route_id;
  if r.id is null then return null; end if;
  -- route profit's window: since now − p_days, inside the 8 UTC days before
  v_since := greatest(p_as_of - p_days * interval '24 hours', (v_today - 8)::timestamp at time zone 'UTC');
  -- the statement blocks of one route on the pair, either way (one row each: game_flights_money_key)
  select count(*)::int, sum(f.income_total - f.cost_total) / 1000000, sum(coalesce(f.pax_income, 0) + coalesce(f.cargo_income, 0)) / 1000000
    into v_n, v_profit, v_income
    from public.game_flights f
   where f.airline_id = r.airline_id and f.posted_at >= v_since and coalesce(f.money_captured_at, f.posted_at) <= p_as_of
     and f.statement_routes = 1
     and ((f.origin_code = r.hub_code and f.dest_code = r.dest_code) or (f.origin_code = r.dest_code and f.dest_code = r.hub_code));
  -- the captured loads of its flights on the pair in the same days (one per date and flight number, the latest)
  select avg(x.eco), count(*) filter (where x.eco >= 100)::int, count(x.eco)::int into v_eco, v_sold, v_eco_n
    from (select distinct on (f.game_date, f.flight_no) f.eco_pct as eco
            from public.game_flights f
           where f.airline_id = r.airline_id and f.flight_no is not null and f.loads_captured_at <= p_as_of
             and f.game_date >= (v_since at time zone 'UTC')::date and f.game_date <= v_today
             and ((f.origin_code = r.hub_code and f.dest_code = r.dest_code) or (f.origin_code = r.dest_code and f.dest_code = r.hub_code))
           order by f.game_date, f.flight_no, f.id desc) x;
  select coalesce(sum(coalesce(cardinality(l.days_utc), 7)), 0)::int, min(rt.launched_on) into v_week, v_first
    from public.rotations rt left join public.flight_legs l on l.rotation_id = rt.id
   where rt.route_id = r.id and rt.airline_id = r.airline_id;
  return jsonb_build_object(
    'airline_id', r.airline_id, 'code', r.iata_code, 'airline', r.name, 'route_id', r.id, 'hub', r.hub_code, 'dest', r.dest_code,
    'flights', coalesce(v_n, 0), 'flights_week', coalesce(v_week, 0), 'profit', v_profit, 'income', v_income,
    'profit_per_flight', case when v_n > 0 then v_profit / v_n end,
    'economy', v_eco, 'sold_out', coalesce(v_sold, 0), 'with_loads', coalesce(v_eco_n, 0),
    'sold_out_share', case when v_eco_n > 0 then v_sold::numeric / v_eco_n end, 'first_day', v_first);
end
$function$;
revoke all on function private.fig_pair_side(bigint, integer, timestamptz) from public, anon, authenticated, service_role;
comment on function private.fig_pair_side(bigint, integer, timestamptz) is 'One airline''s side of a shared pair (since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §3–§4), for the other airline''s route profit rows: over route profit''s window (since p_as_of − p_days, inside the 8 UTC days before), the route''s airline''s one-route statement blocks on the pair either way (flights, profit and income in millions of AS$, profit_per_flight), its captured loads in the same days (economy average, sold_out at 100%, with_loads, sold_out_share), its flights a week from its legs and its first rotation''s launch day (first_day). Close to what route_profit() gives for that airline''s own row (route profit matches blocks to loads one by one; this counts each separately). Internal.';


-- ============================================================ 2. route profit: a joined pair's rows
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
                   sum((coalesce(l.block_min, round(ro.distance_km::numeric / ty.cruise_kmh * 60 + v_allow_min)) + ty.min_turn_min + v_margin_min)
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
    -- a joined shared pair (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §3–§4): the other airline's side, and
    -- the pair's figures with both airlines' flights (sold out, ready for another flight, losing and fix are judged on
    -- them); a route on no joined pair keeps its own figures exactly
    sp as (select r.route_id, pr.role, x.d
             from r cross join lateral private.fig_route_pair(r.route_id) pr
             cross join lateral (select private.fig_pair_side(pr.other_route_id, p_days, p_as_of) as d offset 0) x
            where r.route_id is not null),
    rc as (select r.*, sp.role as shared_role, sp.d as pair,
                  r.n + coalesce((sp.d ->> 'flights')::int, 0) as cn,
                  r.sold + coalesce((sp.d ->> 'sold_out')::int, 0) as csold,
                  r.eco_n + coalesce((sp.d ->> 'with_loads')::int, 0) as ceco_n,
                  case when sp.role is null then r.profit else r.profit + coalesce((sp.d ->> 'profit')::numeric, 0) end as cprofit,
                  case when sp.role is null then r.income else r.income + coalesce((sp.d ->> 'income')::numeric, 0) end as cincome,
                  case when sp.role is null or coalesce((sp.d ->> 'with_loads')::int, 0) = 0 then r.eco_a
                       when r.eco_n = 0 then (sp.d ->> 'economy')::numeric
                       else (r.eco_a * r.eco_n + (sp.d ->> 'economy')::numeric * (sp.d ->> 'with_loads')::int) / (r.eco_n + (sp.d ->> 'with_loads')::int) end as ceco_a,
                  -- the pair is young while both airlines' routes are (a joiner's first flights aren't a new route)
                  case when sp.role is null or coalesce((sp.d ->> 'flights')::int, 0) = 0 then r.young
                       else r.young and coalesce(v_today - (sp.d ->> 'first_day')::date < v_new_days, false) end as cyoung
             from r left join sp on sp.route_id = r.route_id),
    rcc as (select rc.*, rc.cprofit / rc.cn as cppf, case when rc.cincome > 0 then rc.cprofit / rc.cincome end as cmargin,
                   case when rc.ceco_n > 0 then rc.csold::numeric / rc.ceco_n end as csold_share
              from rc),
    pp as (select array_agg(r.ppf order by r.ppf) as a, array_agg(r.pph order by r.pph) filter (where r.pph is not null) as h from r),
    -- the middle route: by profit a flight, and by profit an aircraft hour among the routes with their hours
    q as (select pp.a[floor(cardinality(pp.a) / 2.0)::int + 1] as med, pp.a[floor(cardinality(pp.a) * 0.25)::int + 1] as q25,
                 pp.h[floor(cardinality(pp.h) / 2.0)::int + 1] as med_h,
                 coalesce(cardinality(pp.a), 0) as len from pp),
    mk as (select r.*, case when r.cppf < 0 and r.cn >= v_losing and not r.cyoung then 'losing'
                            when r.csold_share is not null and r.csold_share >= v_sold_share and r.cn >= v_sold_min
                              -- add at or above the middle route's profit an aircraft hour, sold_out below (since 31 Oct, was
                              -- raise: the fare ladder raises a sold-out direction each Saturday by itself); a route with no
                              -- aircraft hours (no legs on record) is compared by profit a flight, as before 17 Oct
                              then case when r.pph is not null and q.med_h is not null then case when r.pph >= q.med_h then 'add' else 'sold_out' end
                                        when r.cppf >= q.med then 'add' else 'sold_out' end
                            when r.cn >= v_fix_min and not r.cyoung and r.ceco_a is not null and r.ceco_a < v_fix_eco then 'fix'
                            when r.cn >= v_fix_min and not r.cyoung and q.len >= v_fix_routes and r.cppf <= q.q25 and r.cmargin is not null and r.cmargin < v_fix_margin then 'fix-margin'
                            else 'hold' end as k, q.med, q.med_h
             from rcc r cross join q),
    routes as (select coalesce(jsonb_agg(jsonb_build_object(
                 'route_id', mk.route_id, 'hub', mk.hub, 'dest', mk.dest, 'flights', mk.n, 'profit', mk.profit, 'income', mk.income,
                 'margin', mk.margin, 'profit_per_flight', mk.ppf, 'flights_week', mk.wk, 'profit_week', mk.pwk,
                 'aircraft_hours', mk.hours, 'profit_per_aircraft_hour', mk.pph,
                 'economy', mk.eco_a, 'business', mk.bus_a, 'cargo', mk.cargo_a, 'economy_fare', mk.fare_a,
                 'sold_out', mk.sold, 'with_loads', mk.eco_n, 'sold_out_share', mk.sold_share,
                 'mark', case when mk.k = 'fix-margin' then 'fix' else mk.k end,
                 'why', case mk.k when 'losing' then case when mk.shared_role is null then 'its average flight loses money' else 'the pair''s average flight loses money' end
                                  when 'add' then format('sold out on %s of %s departures, profit %s at or above the airline''s middle route', mk.csold, mk.ceco_n,
                                                         case when mk.pph is not null and mk.med_h is not null then 'an aircraft hour' else 'a flight' end)
                                  when 'sold_out' then 'sold out · fares climbing (the fare ladder raises it each Saturday)'
                                  when 'fix' then format('economy averaging %s%%', floor(mk.ceco_a + 0.5))
                                  when 'fix-margin' then format('bottom-quarter profit a flight on a margin under %s%%', floor(v_fix_margin * 100 + 0.5))
                                  else '' end
                        || case when mk.shared_role is not null and mk.k <> 'hold' then format(' (both airlines'' flights, with %s''s)', mk.pair ->> 'airline') else '' end)
                 -- a joined shared pair (since 5 Nov): this airline's role, and the other airline's side with the pair's figures
                 || case when mk.shared_role is null then '{}'::jsonb else jsonb_build_object(
                      'shared_role', mk.shared_role,
                      'pair', mk.pair || jsonb_build_object('combined', jsonb_build_object(
                                'flights', mk.cn, 'flights_week', mk.wk + coalesce((mk.pair ->> 'flights_week')::int, 0), 'profit', mk.cprofit,
                                'income', mk.cincome, 'profit_per_flight', mk.cppf, 'economy', mk.ceco_a, 'sold_out', mk.csold,
                                'with_loads', mk.ceco_n, 'sold_out_share', mk.csold_share))) end
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


-- ============================================================ 3. growth signals: a joined pair listed once
CREATE OR REPLACE FUNCTION private.fig_growth_signals(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_days int := private.fig_num(p_world_id, null, 'growth_window_days')::int; v_docs jsonb;
        v_today date := (p_as_of at time zone 'UTC')::date; v_profit boolean;
begin
  -- each airline's route and aircraft profit over the growth window, for those with flights captured
  select coalesce(jsonb_agg(jsonb_build_object('airline_id', al.airline_id, 'ord', al.ord, 'doc', x.doc) order by al.ord), '[]'::jsonb) into v_docs
    from private.fig_airlines(p_world_id) al
    cross join lateral (select private.fig_route_profit(al.airline_id, v_days, p_as_of) as doc offset 0) x   -- once each
   where al.home_code is not null and (x.doc ->> 'flights')::int > 0;
  -- any profit captured: a bank-statement line posted since midnight UTC 8 days ago (the old Home's CAP.pnl,
  -- game_flight_pnl since utcDay(-8)); with none, Home lists the routes the load patterns say to reduce instead
  v_profit := exists (select 1 from public.game_flights f join public.airlines a on a.id = f.airline_id
                       where a.world_id = p_world_id and f.posted_at >= (v_today - 8)::timestamp at time zone 'UTC'
                         and coalesce(f.money_captured_at, f.posted_at) <= p_as_of)
           or exists (select 1 from public.game_payments p join public.airlines a on a.id = p.airline_id
                       where a.world_id = p_world_id and p.paid_at >= (v_today - 8)::timestamp at time zone 'UTC' and p.created_at <= p_as_of
                         and coalesce(p.statement_blk::int, 1) > 0 and p.kind = 'other');
  return (
    with r0 as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
                  from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'routes') with ordinality as e(x, i)),
    -- a joined shared pair (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §3) is judged on both airlines' flights
    -- (route profit's mark) and listed once, under its owner with shared_with; the joiner's row, when the owner's is there,
    -- goes to follows with the owner's mark
    jn as (select j.airline_id, j.ord, j.x, j.i, o.x as ox
             from r0 j join r0 o on (o.x ->> 'route_id') = (j.x #>> '{pair,route_id}') and o.x ->> 'shared_role' = 'owner'
            where j.x ->> 'shared_role' = 'joiner'),
    r as (select r0.airline_id, r0.ord,
                 case when r0.x ->> 'shared_role' = 'owner'
                      then r0.x || jsonb_build_object('shared_with', jsonb_build_object(
                             'airline_id', (r0.x #>> '{pair,airline_id}')::bigint, 'code', r0.x #>> '{pair,code}', 'airline', r0.x #>> '{pair,airline}',
                             'route_id', (r0.x #>> '{pair,route_id}')::bigint, 'flights', (r0.x #>> '{pair,flights}')::int,
                             'flights_week', (r0.x #>> '{pair,flights_week}')::int,
                             'flies', coalesce((r0.x #>> '{pair,flights}')::int, 0) > 0 or coalesce((r0.x #>> '{pair,flights_week}')::int, 0) > 0))
                      else r0.x end as x, r0.i
            from r0
           where not exists (select 1 from jn where jn.airline_id = r0.airline_id and jn.i = r0.i)),
    t as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
            from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'aircraft') with ordinality as e(x, i))
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'days', v_days, 'profit_captured', v_profit,
      'ready_for_another_flight', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                                     order by (r.x ->> 'profit_week')::numeric desc, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' = 'add'),
      'sold_out', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                     order by (r.x ->> 'flights')::int desc, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' = 'sold_out'),
      'fix_or_reduce', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                          order by (r.x ->> 'profit_per_flight')::numeric, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' in ('losing', 'fix')),
      'aircraft_losing_after_lease', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', t.airline_id) || t.x
                                        order by (t.x ->> 'net_day')::numeric, t.ord, t.i), '[]'::jsonb)
                                        from t where (t.x ->> 'net_day')::numeric < 0),
      'follows', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', jn.airline_id) || (jn.x - 'mark' - 'why')
                       || jsonb_build_object('mark', jn.ox ->> 'mark', 'why', jn.ox ->> 'why',
                                             'follows', jsonb_build_object('airline_id', (jn.x #>> '{pair,airline_id}')::bigint, 'code', jn.x #>> '{pair,code}',
                                                                           'airline', jn.x #>> '{pair,airline}', 'route_id', (jn.x #>> '{pair,route_id}')::bigint))
                       order by jn.ord, jn.i), '[]'::jsonb) from jn where jn.ox ->> 'mark' <> 'hold'),
      'load_patterns', private.fig_patterns(p_world_id, p_as_of)));
end
$function$;


-- ============================================================ 4. competition: the owner first on a shared pair
CREATE OR REPLACE FUNCTION private.fig_competition(p_airline_id bigint, p_as_of timestamp with time zone, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_limit int := greatest(coalesce(p_limit, 50), 0);
  -- the wide-body line (manual §3): its listed range is with a full load and not a limit; the A350-900, cheapest per
  -- seat, keeps its full cabin to settings.a350_1000_from_km, and beyond that the type with the most seats
  v_wide_km int;
  v_latest bigint; v_latest_at timestamptz; v_before bigint; v_before_at timestamptz; v_prev bigint; v_prev_at timestamptz;
  v_main text; v_exempt boolean; v_target numeric; v_rival_weekly numeric; v_rival_daily numeric; v_min numeric; v_dep int;
  v_code text; v_name text; v_pairs text[]; v_ids bigint[];
  v_threats jsonb; v_body jsonb; v_group jsonb; v_flags jsonb; v_conn_scan bigint;
  v_trunk_from date; v_trunk_to date; v_trunks boolean;
  v_mrun bigint; v_mrun_doc jsonb;
  v_fund jsonb := '{}'::jsonb;
begin
  select a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) into v_code, v_name from public.airlines a where a.id = p_airline_id;
  v_min := private.fig_num(w, p_airline_id, 'competition_threat_min_weekly');
  v_exempt := private.fig_flag(w, p_airline_id, 'hub_first_exempt');
  v_target := private.fig_num(w, p_airline_id, 'hub_first_departures');
  v_rival_weekly := private.fig_num(w, p_airline_id, 'contested_rival_weekly');
  v_rival_daily := private.fig_num(w, p_airline_id, 'contested_rival_daily');
  -- the A350-900/-1000 cut-over (manual §3, since 27 Oct), from settings (an airline's own first); if the row is
  -- missing, 14,200 km, the -900's reach with a full cabin (brief docs/briefs/2026-10-27-real-aircraft-reach.md)
  select (s.value #>> '{}')::numeric::int into v_wide_km from public.settings s
   where s.world_id = w and s.key = 'a350_1000_from_km' and (s.airline_id is null or s.airline_id = p_airline_id)
     and jsonb_typeof(s.value) = 'number' order by s.airline_id nulls last limit 1;
  v_wide_km := coalesce(v_wide_km, 14200);
  select b.airport_code into v_main from public.airline_bases b where b.airline_id = p_airline_id and b.is_main order by b.id limit 1;
  -- November's trunks (manual §4): the month's first and last day (UTC), from settings (an airline's own first)
  select (s.value #>> '{}')::date into v_trunk_from from public.settings s
   where s.world_id = w and s.key = 'trunk_month_from' and (s.airline_id is null or s.airline_id = p_airline_id) order by s.airline_id nulls last limit 1;
  select (s.value #>> '{}')::date into v_trunk_to from public.settings s
   where s.world_id = w and s.key = 'trunk_month_to' and (s.airline_id is null or s.airline_id = p_airline_id) order by s.airline_id nulls last limit 1;
  v_trunks := coalesce((p_as_of at time zone 'UTC')::date between v_trunk_from and v_trunk_to, false);
  -- the main hub's departures a week, as hub_progress() counts them: outbound legs from it, and returns to it
  select coalesce(sum(f.days_n) filter (where f.hub_code = v_main), 0) + coalesce(sum(f.days_n) filter (where f.dest_code = v_main and f.has_back), 0)
    into v_dep from private.fig_freqs(w, p_airline_id) f where f.live;

  -- the scans: latest, the latest finished by the moment (with its schedules); week before, the latest at least 6 days
  -- older, else the oldest there is; previous, the latest before latest
  select s.id, s.taken_at into v_latest, v_latest_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  if v_latest is not null then
    select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= v_latest_at - interval '6 days'
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
     order by s.taken_at desc, s.id desc limit 1;
    if v_before is null then
      select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
       where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of and s.id <> v_latest
         and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
       order by s.taken_at, s.id limit 1;
    end if;
    select s.id, s.taken_at into v_prev, v_prev_at from public.game_scans s
     where s.world_id = w and s.status = 'done' and (s.taken_at < v_latest_at or (s.taken_at = v_latest_at and s.id < v_latest))
       and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
     order by s.taken_at desc, s.id desc limit 1;
  end if;

  -- the city pairs on the airline's list (its routes not removed, flown or not, either direction)
  select array_agg(distinct least(r.hub_code, r.dest_code) || '-' || greatest(r.hub_code, r.dest_code)) into v_pairs
    from public.routes r where r.airline_id = p_airline_id and r.world_id = w and not r.removed;
  v_ids := array_remove(array[v_latest, v_before], null);
  -- the rivals' connections (spec docs/specs/2026-10-23-rival-connections.md §3): the latest scan's, when they were worked
  -- out for it (its row in scan_rival_connections_week, written with the detail); a scan from before them gives none, so
  -- its answer has no connecting figures rather than zeros
  select v_latest into v_conn_scan where v_latest is not null
     and exists (select 1 from public.scan_rival_connections_week c where c.scan_id = v_latest);
  -- the market pages (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §4, §5): the world's latest finished
  -- market run by the moment, or none
  select r.id, jsonb_build_object('id', r.id, 'started_at', private.fig_ts(r.started_at), 'finished_at', private.fig_ts(r.finished_at))
    into v_mrun, v_mrun_doc
    from public.market_runs r
   where r.world_id = w and r.status = 'done' and r.started_at <= p_as_of
   order by r.started_at desc, r.id desc limit 1;

  -- shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §3): the owner first. For each owner of a pair
  -- this airline may join that neither flies, whether its cash forecast can order this evening (next_order when now);
  -- only when openings are listed (p_limit above 0), otherwise a joiner's shared openings are left out
  if v_limit > 0 then
    select coalesce(jsonb_object_agg(x.owner_airline_id::text, private.fig_cash_forecast(x.owner_airline_id, '[]'::jsonb, p_as_of) #>> '{next_order,when}'), '{}'::jsonb)
      into v_fund
      from (select distinct sp.owner_airline_id from public.shared_pairs sp
             where sp.world_id = w and sp.joiner_airline_id = p_airline_id and sp.owner_airline_id is not null
               and sp.owner_flights_week = 0 and sp.joiner_flights_week = 0) x;
  end if;

  -- the group line: our airlines' passenger departures a week against the world's, in the latest and week-before scans
  -- (each airline's schedule, freighters left out as the weekly report counts: private.scan_passenger())
  if v_latest is not null then
    with x as (select sc.scan_id, coalesce(g.kind, 'rival') = 'ours' as ours,
                      length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')) as n
                 from public.game_scan_schedules sc
                 join public.airlines ra on ra.id = sc.airline_id
                 left join public.groups g on g.id = ra.group_id
                 cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
                where sc.scan_id = any (v_ids) and jsonb_typeof(f) = 'array' and private.scan_passenger(f ->> 7)),
    t as (select coalesce(sum(x.n) filter (where x.scan_id = v_latest and x.ours), 0)::int as ours,
                 coalesce(sum(x.n) filter (where x.scan_id = v_latest), 0)::int as world,
                 case when v_before is not null then coalesce(sum(x.n) filter (where x.scan_id = v_before and x.ours), 0)::int end as ours_b,
                 case when v_before is not null then coalesce(sum(x.n) filter (where x.scan_id = v_before), 0)::int end as world_b
            from x)
    select jsonb_build_object(
             'ours', t.ours, 'world', t.world, 'share', round(100.0 * t.ours / nullif(t.world, 0), 1),
             'ours_before', t.ours_b, 'world_before', t.world_b, 'share_before', round(100.0 * t.ours_b / nullif(t.world_b, 0), 1),
             'ours_change', t.ours - t.ours_b, 'world_change', t.world - t.world_b,
             'share_change', round(100.0 * t.ours / nullif(t.world, 0), 1) - round(100.0 * t.ours_b / nullif(t.world_b, 0), 1))
      into v_group from t;
  end if;

  -- the world's big order books and airlines starting with orders (spec docs/specs/2026-10-23-rival-fleets.md §4), each
  -- marked whether it meets this airline (its city pairs or its bases); feeds nothing else here
  v_flags := private.scan_order_flags(p_airline_id, v_latest, v_before, v_pairs);

  -- the threats (1b): the shared function the fare ladder's rival pause reads too
  select coalesce(jsonb_agg(jsonb_build_object(
           'rival_id', t.rival_id, 'rival', t.rival, 'pair', t.a || '-' || t.b,
           'route', coalesce(rc.hub, t.a) || '–' || coalesce(rc.dest, t.b), 'hub', coalesce(rc.hub, t.a), 'dest', coalesce(rc.dest, t.b),
           'kind', t.kind, 'then', t.then_weekly, 'added', t.added_weekly, 'now', t.now_weekly, 'ours', t.ours_weekly,
           'scan_id', t.scan_id, 'on', private.fig_ts(t.scan_at), 'previous_id', t.previous_id, 'previous_on', private.fig_ts(t.previous_at),
           'until', private.fig_ts(t.until), 'latest', t.scan_id = v_latest,
           'words', format('%s %s on %s, %s a week', t.rival, t.kind, coalesce(rc.hub, t.a) || '–' || coalesce(rc.dest, t.b),
                           case when t.kind = 'started' then t.added_weekly::text else t.then_weekly || ' → ' || (t.then_weekly + t.added_weekly) end))
           order by t.scan_at desc, t.now_weekly desc, t.rival, t.a, t.b), '[]'::jsonb)
    into v_threats
    from private.competition_threats(p_airline_id, p_as_of) t
    -- the route the airline flies the pair as (from the main hub first)
    left join (select distinct on (least(f.hub_code, f.dest_code), greatest(f.hub_code, f.dest_code))
                      least(f.hub_code, f.dest_code) as a, greatest(f.hub_code, f.dest_code) as b, f.hub_code as hub, f.dest_code as dest
                 from private.fig_freqs(w, p_airline_id) f where f.live
                order by least(f.hub_code, f.dest_code), greatest(f.hub_code, f.dest_code), (f.hub_code = v_main) desc, f.route_id) rc
      on rc.a = t.a and rc.b = t.b;

  with
  ro as (select r.id, r.hub_code as hub, r.dest_code as dest, least(r.hub_code, r.dest_code) as a, greatest(r.hub_code, r.dest_code) as b,
                coalesce(r.city_override, r.city) as city, coalesce(r.stars_override, r.stars)::int as stars,
                coalesce(r.distance_override_km, r.distance_km) as dist,
                case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end as market_id
           from public.routes r where r.airline_id = p_airline_id and r.world_id = w and not r.removed),
  fq as materialized (select * from private.fig_freqs(w) f where f.live),
  -- this airline's departures a week on each pair (its live legs), and the pairs any airline of ours flies
  mine as (select least(f.hub_code, f.dest_code) as a, greatest(f.hub_code, f.dest_code) as b, sum(f.flights_week)::int as weekly
             from fq f where f.airline_id = p_airline_id group by 1, 2),
  ourall as (select distinct least(f.hub_code, f.dest_code) as a, greatest(f.hub_code, f.dest_code) as b from fq f),
  -- the latest and week-before scans' flights on the airline's pairs, by direction
  ex as materialized (
    select x.scan_id, x.airline_id, x.origin, x.dest, least(x.origin, x.dest) as a, greatest(x.origin, x.dest) as b, x.weekly,
           coalesce(g.kind, 'rival') <> 'ours' as rival, coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || x.airline_id) as name
      from private.scan_pair_flights(v_ids, coalesce(v_pairs, '{}'::text[])) x
      join public.airlines ra on ra.id = x.airline_id
      left join public.groups g on g.id = ra.group_id),
  -- each rival's departures a week on each pair, both ways
  rv as (select ex.scan_id, ex.airline_id, ex.name, ex.a, ex.b, sum(ex.weekly)::int as weekly from ex where ex.rival group by 1, 2, 3, 4, 5),
  me_then as (select ex.a, ex.b, sum(ex.weekly)::int as weekly from ex where ex.scan_id = v_before and ex.airline_id = p_airline_id group by 1, 2),
  -- the rivals' connecting departures a week on the airline's pairs in the latest scan (since 23 Oct, spec
  -- docs/specs/2026-10-23-rival-connections.md §3), both ways, by connecting airport: shown beside direct, never added
  cx as materialized (
    select c.airline_id, coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || c.airline_id) as name,
           least(c.origin, c.dest) as a, greatest(c.origin, c.dest) as b, c.via, sum(c.weekly_departures)::int as weekly
      from public.scan_rival_connections c
      join public.airlines ra on ra.id = c.airline_id
     where c.scan_id = v_conn_scan
       and least(c.origin, c.dest) || '-' || greatest(c.origin, c.dest) = any (coalesce(v_pairs, '{}'::text[]))
     group by 1, 2, 3, 4, 5),
  -- by pair and rival, by pair (the total, each rival's own and the top 3 airports) and by rival
  cxr as (select cx.a, cx.b, cx.airline_id, cx.name, sum(cx.weekly)::int as weekly,
                 private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cx.via, 'weekly', cx.weekly))) as via
            from cx group by 1, 2, 3, 4),
  cxp as (select r.a, r.b, sum(r.weekly)::int as weekly,
                 jsonb_agg(jsonb_build_object('airline_id', r.airline_id, 'name', r.name, 'weekly', r.weekly, 'via', r.via) order by r.weekly desc, r.name) as rivals,
                 (select private.scan_connection_via(jsonb_agg(jsonb_build_object('via', y.via, 'weekly', y.weekly))) from cx y where y.a = r.a and y.b = r.b) as via
            from cxr r group by 1, 2),
  cxa as (select cx.airline_id, sum(cx.weekly)::int as weekly, count(distinct (cx.a, cx.b))::int as pairs,
                 private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cx.via, 'weekly', cx.weekly))) as via
            from cx group by 1),

  -- ---------- 1a. market share, by the airline's markets
  mp as (select distinct ro.market_id, ro.a, ro.b from ro),
  mk as (select mp.market_id, count(*)::int as pairs, (count(*) filter (where m.a is not null))::int as flown,
                coalesce(sum(m.weekly), 0)::int as ours, case when v_before is not null then coalesce(sum(t.weekly), 0)::int end as ours_before
           from mp left join mine m on m.a = mp.a and m.b = mp.b left join me_then t on t.a = mp.a and t.b = mp.b
          group by mp.market_id),
  mr as (select mp.market_id, rv.airline_id, rv.name,
                coalesce(sum(rv.weekly) filter (where rv.scan_id = v_latest), 0)::int as weekly,
                case when v_before is not null then coalesce(sum(rv.weekly) filter (where rv.scan_id = v_before), 0)::int end as weekly_before
           from mp join rv on rv.a = mp.a and rv.b = mp.b group by 1, 2, 3),
  mt as (select mr.market_id, sum(mr.weekly)::int as rivals, sum(mr.weekly_before)::int as rivals_before from mr group by 1),
  -- by market: every rival's connecting departures on its pairs, with the top 3 airports (since 23 Oct)
  mcx as (select mp.market_id, sum(cx.weekly)::int as weekly,
                 private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cx.via, 'weekly', cx.weekly))) as via
            from mp join cx on cx.a = mp.a and cx.b = mp.b group by 1),
  -- the game's passenger share (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §4): each direction of each
  -- of the market's pairs read in the latest finished market run, the airline's share (0 when the page doesn't list it)
  -- and last week's (share − change), weighted by the direction's seats offered in the latest week read (market_weeks)
  gr as (select mp.market_id, mp.a, mp.b, m.id as read_id, m.share_week, m.read_at,
                coalesce(s.share_pct, 0) as share, s.share_pct - s.change_pts as before,
                (select k.seats from public.market_weeks k
                  where k.world_id = w and k.origin = m.origin and k.dest = m.dest and k.week <= coalesce(m.share_week, k.week)
                  order by k.week desc limit 1) as seats
           from mp
           join public.market_reads m on m.run_id = v_mrun and m.ok
                                     and ((m.origin = mp.a and m.dest = mp.b) or (m.origin = mp.b and m.dest = mp.a))
           left join public.market_shares s on s.read_id = m.id and s.kind = 'passengers' and s.airline_id = p_airline_id),
  gm as (select gr.market_id, count(distinct (gr.a, gr.b))::int as pairs_read, sum(gr.seats)::bigint as seats,
                coalesce(round(sum(gr.share * gr.seats) / nullif(sum(gr.seats) filter (where gr.seats > 0), 0), 2), round(avg(gr.share), 2)) as share,
                coalesce(round(sum(gr.before * gr.seats) / nullif(sum(gr.seats) filter (where gr.seats > 0 and gr.before is not null), 0), 2),
                         round(avg(gr.before), 2)) as before,
                max(gr.share_week) as week, max(gr.read_at) as read_at
           from gr group by 1),
  ms as (select mk.*, coalesce(mt.rivals, 0) as rivals, case when v_before is not null then coalesce(mt.rivals_before, 0) end as rivals_before,
                mkt.name as market
           from mk left join mt on mt.market_id is not distinct from mk.market_id
           left join public.markets mkt on mkt.id = mk.market_id),
  markets as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'market_id', ms.market_id, 'name', coalesce(ms.market, 'No market'), 'pairs', ms.pairs, 'flown', ms.flown,
             'ours', ms.ours, 'ours_before', ms.ours_before, 'ours_change', ms.ours - ms.ours_before,
             'rivals', ms.rivals, 'rivals_before', ms.rivals_before, 'rivals_change', ms.rivals - ms.rivals_before,
             'total', ms.ours + ms.rivals,
             'share', case when v_latest is not null then round(100.0 * ms.ours / nullif(ms.ours + ms.rivals, 0), 1) end,
             'share_before', round(100.0 * ms.ours_before / nullif(ms.ours_before + ms.rivals_before, 0), 1),
             'share_change', case when v_latest is not null then round(100.0 * ms.ours / nullif(ms.ours + ms.rivals, 0), 1) end
                             - round(100.0 * ms.ours_before / nullif(ms.ours_before + ms.rivals_before, 0), 1),
             'top', (select coalesce(jsonb_agg(jsonb_build_object(
                              'airline_id', t.airline_id, 'name', t.name, 'weekly', t.weekly, 'weekly_before', t.weekly_before,
                              'change', t.weekly - t.weekly_before, 'share', round(100.0 * t.weekly / nullif(ms.ours + ms.rivals, 0), 1))
                              order by t.weekly desc, t.name), '[]'::jsonb)
                       from (select mr.* from mr where mr.market_id is not distinct from ms.market_id and mr.weekly > 0
                              order by mr.weekly desc, mr.name limit 5) t),
             -- the game's passenger share beside the scan's (since 30 Oct): null when none of its pairs has been read
             'game_share', (select jsonb_build_object('share', g.share, 'share_before', g.before, 'change', g.share - g.before,
                                                     'pairs_read', g.pairs_read, 'pairs', ms.pairs, 'seats', g.seats, 'week', g.week,
                                                     'run_id', v_mrun, 'read_at', private.fig_ts(g.read_at))
                              from gm g where g.market_id is not distinct from ms.market_id))
             -- connecting (since 23 Oct): never part of total or share; absent when the latest scan has none worked out
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce((select x.weekly from mcx x where x.market_id is not distinct from ms.market_id), 0),
                  'connecting_via', coalesce((select x.via from mcx x where x.market_id is not distinct from ms.market_id), '[]'::jsonb))
                else '{}'::jsonb end
             order by ms.ours + ms.rivals desc, ms.market nulls last, ms.market_id), '[]'::jsonb) as d
      from ms),

  -- ---------- 1c. openings: pairs on the list no airline of ours flies, one route each (from the main hub first)
  -- our bases, every airline's (hubs and focus cities): a pair between two of them is a trunk (manual §4); a station
  -- (since 22 Oct, manual §2) is no base, so a pair with a station end is never a trunk
  ob as (select distinct b.airport_code from public.airline_bases b
           join public.airlines a on a.id = b.airline_id join public.groups g on g.id = a.group_id
          where b.world_id = w and g.kind = 'ours' and b.role <> 'station'),
  -- shared pairs (since 5 Nov): each base-to-base pair of this airline and another of ours (not excluded), its role and
  -- the other airline; and the pairs it would join that aren't on its list, as openings from its base (the owner's row's
  -- stars, distance and market)
  spx as (select least(sp.owner_base, sp.joiner_base) as a, greatest(sp.owner_base, sp.joiner_base) as b,
                 case when sp.owner_airline_id = p_airline_id then 'owner' else 'joiner' end as role,
                 case when sp.owner_airline_id = p_airline_id then sp.joiner_airline_id else sp.owner_airline_id end as other_id,
                 sp.owner_airline_id, sp.owner_route_id, sp.joiner_route_id
            from public.shared_pairs sp
           where sp.world_id = w and p_airline_id in (sp.owner_airline_id, sp.joiner_airline_id)),
  rox as (select r.id, sp.joiner_base as hub, sp.owner_base as dest, least(r.hub_code, r.dest_code) as a, greatest(r.hub_code, r.dest_code) as b,
                 coalesce(ap.city, r.dest_code) as city, coalesce(r.stars_override, r.stars)::int as stars,
                 coalesce(r.distance_override_km, r.distance_km) as dist,
                 case when r.market_cleared then null else coalesce(r.market_override_id, r.market_id) end as market_id
            from public.shared_pairs sp
            join public.routes r on r.id = sp.owner_route_id
            left join public.airports ap on ap.code = sp.owner_base
           where sp.world_id = w and sp.joiner_airline_id = p_airline_id and sp.joiner_route_id is null
             and not exists (select 1 from ro where ro.a = least(sp.owner_base, sp.joiner_base) and ro.b = greatest(sp.owner_base, sp.joiner_base))),
  -- the other airlines of ours that have the pair on their own list (one airline per city pair, manual §2, decides)
  ol as (select least(r.hub_code, r.dest_code) as a, greatest(r.hub_code, r.dest_code) as b, array_agg(distinct al.iata_code order by al.iata_code) as codes
           from public.routes r join public.airlines al on al.id = r.airline_id join public.groups g on g.id = al.group_id
          where r.world_id = w and r.airline_id <> p_airline_id and not r.removed and g.kind = 'ours' and al.iata_code is not null
          group by 1, 2),
  -- at_base: from one of the airline's hubs or focus cities; at_station: from one of its stations (manual §2, since 22 Oct)
  op0 as (select distinct on (ro.a, ro.b) ro.*,
                 exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub and b.role <> 'station') as at_base,
                 exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub and b.role = 'station') as at_station,
                 -- in the trunk month only (trunk_month_from to trunk_month_to)
                 v_trunks and ro.hub in (select ob.airport_code from ob) and ro.dest in (select ob.airport_code from ob) as trunk
            from (select * from ro union all select * from rox) ro
           where not exists (select 1 from ourall o where o.a = ro.a and o.b = ro.b)
             -- a pair this airline would join waits for its owner: an opening only while the owner can't order this evening
             and not exists (select 1 from spx where spx.a = ro.a and spx.b = ro.b and spx.role = 'joiner'
                               and coalesce(v_fund ->> spx.owner_airline_id::text, 'now') = 'now')
           order by ro.a, ro.b, (ro.hub = v_main) desc,
                    exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub and b.role <> 'station') desc,
                    exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub) desc, ro.id),
  orv as (select rv.a, rv.b, sum(rv.weekly)::int as weekly,
                 jsonb_agg(jsonb_build_object('airline_id', rv.airline_id, 'name', rv.name, 'weekly', rv.weekly) order by rv.weekly desc, rv.name) as rivals
            from rv where rv.scan_id = v_latest group by 1, 2),
  -- the types of the world by size from their seats (manual §3's table): small (the E-jets, up to 150 seats), mid (the
  -- A320neo, up to 200), large (the A321s, up to 300), wide (the A350s); own: the airline may buy it
  ty as (select t.id, t.name, t.seats_max, t.range_km, t.price,
                case when t.seats_max <= 150 then 1 when t.seats_max <= 200 then 2 when t.seats_max <= 300 then 3 else 4 end as size,
                exists (select 1 from public.airline_aircraft_types x where x.aircraft_type_id = t.id and x.airline_id = p_airline_id) as own
           from public.aircraft_types t
          where t.world_id = w and t.seats_max > 0 and t.price > 0),
  op1 as (select op0.*, coalesce(orv.weekly, 0) as rivals_weekly, coalesce(orv.rivals, '[]'::jsonb) as rivals,
                 -- the stars' size band (manual §3): 1–2 stars small; 3 small or mid; 4 small, mid or large; 5 mid or large
                 case when coalesce(op0.stars, 0) >= 5 then 2 else 1 end as band_lo,
                 case when coalesce(op0.stars, 0) <= 2 then 1 when op0.stars = 3 then 2 else 3 end as band_hi,
                 v.id as type_id, v.name as type, v.seats_max as seats, v.range_km, v.size, v.own
            from op0
            left join orv on orv.a = op0.a and orv.b = op0.b
            -- the variant (the default line): the smallest size in the band, else bigger for reach, whose range covers the
            -- distance, the cheapest per seat; beyond every narrowbody, the wide-body line; among the types the airline may
            -- buy, and for a November trunk none of them reaches, the world's (manual §4: any distance, the A350s beyond
            -- the A321XLR), so a trunk is never left out for reach
            left join lateral (
              select t.* from ty t
               where (t.own or (op0.trunk and not exists (select 1 from ty o where o.own and (o.size = 4 or (o.size between (case when coalesce(op0.stars, 0) >= 5 then 2 else 1 end) and 3
                                                                                                          and o.range_km >= coalesce(op0.dist, 0))))))
                 and ((t.size between (case when coalesce(op0.stars, 0) >= 5 then 2 else 1 end) and 3 and t.range_km >= coalesce(op0.dist, 0))
                      or (t.size = 4 and not exists (select 1 from ty n where (n.own or not t.own) and n.size between (case when coalesce(op0.stars, 0) >= 5 then 2 else 1 end) and 3
                                                                           and n.range_km >= coalesce(op0.dist, 0))))
               order by t.own desc, t.size, case when t.size = 4 and coalesce(op0.dist, 0) > v_wide_km then -t.seats_max else 0 end,
                        t.price / t.seats_max, t.name
               limit 1) v on true),
  -- hubs first (manual §3), from the latest scan: the busiest rival at a base (a hub or focus city: a station is never
  -- contested), and each rival's departures a week from the base to the destination
  bt as (select x.airport_code, max(x.weekly_departures)::int as weekly from public.scan_airline_airports x
            join public.airlines ra on ra.id = x.airline_id left join public.groups g on g.id = ra.group_id
           where x.scan_id = v_latest and coalesce(g.kind, 'rival') <> 'ours'
             and x.airport_code in (select b.airport_code from public.airline_bases b where b.airline_id = p_airline_id and b.role <> 'station')
           group by 1),
  rt as (select ex.origin, ex.dest, max(ex.weekly)::int as weekly from ex where ex.scan_id = v_latest and ex.rival group by 1, 2),
  op2 as (select op1.*, bt.weekly as base_top, rt.weekly as route_top
            from op1 left join bt on bt.airport_code = op1.hub left join rt on rt.origin = op1.hub and rt.dest = op1.dest
           where op1.type_id is not null),
  op3 as (select op2.*,
                 -- hubs first is suspended for trunks in the trunk month (manual §4); a station opens nothing until the main
                 -- hub reaches its target, contested or not (manual §3, since 22 Oct): not at_base, so null below
                 case when op2.trunk then 'November trunk'
                      when v_exempt then 'exempt' when v_main is null then 'no main hub' when op2.hub = v_main then 'main hub'
                      when v_dep >= v_target then 'main hub at its target'
                      when not op2.at_base then null
                      when coalesce(op2.base_top, 0) > v_rival_weekly then 'contested base'
                      when coalesce(op2.route_top, 0) > 7 * v_rival_daily then 'contested route' end as allowed_by
            from op2),
  op4 as (select op3.*, op3.allowed_by is not null as allowed,
                 case when op3.allowed_by is not null then null
                      when op3.at_station then format('hubs first: stations wait for %s''s %s', v_main, trim_scale(v_target))
                      when not op3.at_base then format('hubs first: %s isn''t one of its bases', op3.hub)
                      when v_latest is null then format('hubs first: %s at %s of %s departures a week, and no world scan to show %s contested',
                                                        v_main, v_dep, trim_scale(v_target), op3.hub)
                      else format('hubs first: %s at %s of %s departures a week, and %s isn''t contested (busiest rival there %s a week, over %s needed; none over %s a day on %s–%s)',
                                  v_main, v_dep, trim_scale(v_target), op3.hub, coalesce(op3.base_top, 0), trim_scale(v_rival_weekly),
                                  trim_scale(v_rival_daily), op3.hub, op3.dest) end as reason,
                 -- in the trunk month the trunks first, shortest first (manual §4: shortest to longest); then as always
                 row_number() over (order by op3.trunk desc, case when op3.trunk then op3.dist end nulls last,
                                             op3.allowed_by is not null desc, op3.stars desc nulls last, op3.rivals_weekly desc,
                                             op3.dist nulls last, op3.hub || '–' || op3.dest) as rank
            from op3),
  openings as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'rank', o.rank, 'route_id', o.id, 'route', o.hub || '–' || o.dest, 'hub', o.hub, 'dest', o.dest, 'pair', o.a || '-' || o.b,
             'city', o.city, 'stars', o.stars, 'distance_km', o.dist, 'market_id', o.market_id,
             'rivals_weekly', o.rivals_weekly, 'rivals', o.rivals,
             'variant', jsonb_build_object('type_id', o.type_id, 'type', o.type, 'seats', o.seats, 'range_km', o.range_km,
                                           'size', (array['small', 'mid', 'large', 'wide'])[o.size], 'for_reach', o.size > o.band_hi, 'own', o.own),
             'allowed', o.allowed, 'allowed_by', o.allowed_by, 'reason', o.reason,
             'trunk', o.trunk, 'other_lists', coalesce(to_jsonb(l.codes), '[]'::jsonb),
             -- a shared pair (since 5 Nov): this airline's role and the other airline; a joiner's carries the owner's cash
             'shared', case when sx.role is not null then jsonb_build_object(
                         'role', sx.role, 'airline_id', sx.other_id, 'code', sxa.iata_code,
                         'airline', coalesce(sxa.public_name, sxa.planner_name, sxa.game_name), 'owner_route_id', sx.owner_route_id)
                         || case when sx.role = 'joiner' then jsonb_build_object('owner_next_order', v_fund ->> sx.owner_airline_id::text,
                                                                                  'mark', 'owner can''t fund tonight') else '{}'::jsonb end end)
             -- connecting (since 23 Oct): the rivals' one-stop departures on the pair, beside rivals_weekly, never in it
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce(oc.weekly, 0), 'connecting_via', coalesce(oc.via, '[]'::jsonb), 'connecting', coalesce(oc.rivals, '[]'::jsonb))
                else '{}'::jsonb end
             order by o.rank) filter (where o.rank <= v_limit), '[]'::jsonb) as d,
           count(*)::int as n, (count(*) filter (where o.allowed))::int as n_allowed, (count(*) filter (where o.trunk))::int as n_trunks
      from op4 o left join ol l on l.a = o.a and l.b = o.b left join cxp oc on oc.a = o.a and oc.b = o.b
      left join spx sx on sx.a = o.a and sx.b = o.b left join public.airlines sxa on sxa.id = sx.other_id),
  left_out as (select count(*)::int as n from op1 where op1.type_id is null),
  -- the shared pairs this airline would join that wait for their owner tonight (since 5 Nov)
  waiting as (select count(*)::int as n from (select * from ro union all select * from rox) ro
               where not exists (select 1 from ourall o where o.a = ro.a and o.b = ro.b)
                 and exists (select 1 from spx where spx.a = ro.a and spx.b = ro.b and spx.role = 'joiner'
                              and coalesce(v_fund ->> spx.owner_airline_id::text, 'now') = 'now')),

  -- ---------- 1d. rival profiles: the rivals who fly most of the airline's city pairs (latest scan)
  shared as (select rv.airline_id, rv.name, rv.a, rv.b, rv.weekly, m.weekly as ours from rv join mine m on m.a = rv.a and m.b = rv.b
              where rv.scan_id = v_latest),
  pf as (select s.airline_id, s.name, count(*)::int as pairs, sum(s.weekly)::int as weekly_on_pairs from shared s
          group by 1, 2 order by count(*) desc, sum(s.weekly) desc, s.name limit 10),
  -- each profiled rival's passenger flights in the latest and week-before scans (freighters left out, as the weekly
  -- report counts): its size, airports and biggest airports
  pfx as materialized (
    select sc.scan_id, sc.airline_id, f ->> 2 as origin, f ->> 3 as dest, length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')) as n
      from public.game_scan_schedules sc
      cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
     where sc.scan_id = any (v_ids) and sc.airline_id in (select pf.airline_id from pf) and jsonb_typeof(f) = 'array'
       and private.scan_passenger(f ->> 7)),
  pfs as (select x.scan_id, x.airline_id, sum(x.n)::int as weekly,
                 (select count(*) from (select y.origin from pfx y where y.scan_id = x.scan_id and y.airline_id = x.airline_id and y.n > 0
                                        union select y.dest from pfx y where y.scan_id = x.scan_id and y.airline_id = x.airline_id and y.n > 0) z)::int as airports
            from pfx x group by 1, 2),
  profiles as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'airline_id', pf.airline_id, 'name', pf.name, 'pairs_shared', pf.pairs, 'weekly_on_pairs', pf.weekly_on_pairs,
             'weekly', n.weekly, 'weekly_before', o.weekly, 'change', n.weekly - o.weekly, 'airports', n.airports,
             'pairs', (select jsonb_agg(jsonb_build_object('pair', s.a || '-' || s.b,
                                                           'route', coalesce(rc.hub, s.a) || '–' || coalesce(rc.dest, s.b),
                                                           'weekly', s.weekly, 'ours', s.ours) order by s.weekly desc, s.a, s.b)
                         from shared s
                         left join lateral (select ro.hub, ro.dest from ro where ro.a = s.a and ro.b = s.b
                                             order by (ro.hub = v_main) desc, ro.id limit 1) rc on true
                        where s.airline_id = pf.airline_id),
             'biggest_airports', (select coalesce(jsonb_agg(jsonb_build_object('code', x.origin, 'weekly', x.weekly) order by x.weekly desc, x.origin), '[]'::jsonb)
                                    from (select y.origin, sum(y.n)::int as weekly from pfx y where y.scan_id = v_latest and y.airline_id = pf.airline_id
                                           group by 1 having sum(y.n) > 0 order by 2 desc, 1 limit 3) x),
             -- its fleet from its overview page (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §4)
             'fleet', private.scan_fleet(v_latest, v_before, pf.airline_id))
             -- connecting (since 23 Oct): its one-stop departures a week on this airline's pairs, beside weekly_on_pairs, never in it
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce((select x.weekly from cxa x where x.airline_id = pf.airline_id), 0),
                  'connecting_pairs', coalesce((select x.pairs from cxa x where x.airline_id = pf.airline_id), 0),
                  'connecting_via', coalesce((select x.via from cxa x where x.airline_id = pf.airline_id), '[]'::jsonb))
                else '{}'::jsonb end
             order by pf.pairs desc, pf.weekly_on_pairs desc, pf.name), '[]'::jsonb) as d
      from pf
      left join pfs n on n.scan_id = v_latest and n.airline_id = pf.airline_id
      left join pfs o on o.scan_id = v_before and o.airline_id = pf.airline_id),

  -- ---------- the weekly report's three biggest competitors (manual §7; spec docs/specs/2026-10-21-report-three-competitors.md
  -- §1): the three rivals with the most departures a week on the city pairs the airline flies (both ways) in the latest
  -- scan, ties by name; then each one's whole passenger network, and the airline's own, in the latest and week-before scans
  cr as (select s.airline_id, s.name, sum(s.weekly)::int as on_pairs, count(*)::int as pairs,
                row_number() over (order by sum(s.weekly) desc, s.name, s.airline_id) as rank
           from shared s group by 1, 2
          order by sum(s.weekly) desc, s.name, s.airline_id limit 3),
  -- the airline itself on its pairs, from the same scan's schedule
  me_now as (select count(*)::int as pairs, coalesce(sum(x.weekly), 0)::int as on_pairs
               from (select ex.a, ex.b, sum(ex.weekly) as weekly from ex join mine m on m.a = ex.a and m.b = ex.b
                      where ex.scan_id = v_latest and ex.airline_id = p_airline_id group by 1, 2) x),
  -- each one's passenger flights in both scans (freighters count 0, as the weekly report counts); an airline whose schedule
  -- the scan holds keeps a row even with no flights, so one the week-before scan doesn't hold has no weekly_before
  crx as materialized (
    select sc.scan_id, sc.airline_id, f ->> 2 as origin, f ->> 3 as dest,
           case when jsonb_typeof(f) = 'array' and private.scan_passenger(f ->> 7)
                then length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')) else 0 end as n
      from public.game_scan_schedules sc
      left join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f on true
     where sc.scan_id = any (v_ids) and (sc.airline_id = p_airline_id or sc.airline_id in (select cr.airline_id from cr))),
  crs as (select x.scan_id, x.airline_id, sum(x.n)::int as weekly,
                 (select count(*) from (select y.origin from crx y where y.scan_id = x.scan_id and y.airline_id = x.airline_id and y.n > 0
                                        union select y.dest from crx y where y.scan_id = x.scan_id and y.airline_id = x.airline_id and y.n > 0) z)::int as airports
            from crx x group by 1, 2),
  competitors as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'rank', cr.rank, 'airline_id', cr.airline_id, 'name', cr.name, 'on_pairs', cr.on_pairs, 'pairs', cr.pairs,
             'weekly', n.weekly, 'airports', n.airports, 'weekly_before', o.weekly, 'change', n.weekly - o.weekly,
             'change_pct', round(100.0 * (n.weekly - o.weekly) / nullif(o.weekly, 0), 1),
             'fleet', private.scan_fleet(v_latest, v_before, cr.airline_id))
             -- connecting (since 23 Oct): its one-stop departures a week on this airline's pairs, beside on_pairs, never in it
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce((select x.weekly from cxa x where x.airline_id = cr.airline_id), 0),
                  'connecting_pairs', coalesce((select x.pairs from cxa x where x.airline_id = cr.airline_id), 0),
                  'connecting_via', coalesce((select x.via from cxa x where x.airline_id = cr.airline_id), '[]'::jsonb))
                else '{}'::jsonb end
             order by cr.rank), '[]'::jsonb) as d
      from cr
      left join crs n on n.scan_id = v_latest and n.airline_id = cr.airline_id
      left join crs o on o.scan_id = v_before and o.airline_id = cr.airline_id),
  self as (
    select jsonb_build_object(
             'airline_id', p_airline_id, 'code', v_code, 'name', v_name, 'on_pairs', me_now.on_pairs, 'pairs', me_now.pairs,
             'pairs_flown', (select count(*) from mine)::int, 'weekly', n.weekly, 'airports', n.airports, 'weekly_before', o.weekly,
             'change', n.weekly - o.weekly, 'change_pct', round(100.0 * (n.weekly - o.weekly) / nullif(o.weekly, 0), 1)) as d
      from me_now
      left join crs n on n.scan_id = v_latest and n.airline_id = p_airline_id
      left join crs o on o.scan_id = v_before and o.airline_id = p_airline_id),
  -- ---------- the weekly report's contested pairs (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §5): each
  -- city pair the airline flies where a rival has at least as many departures a week as ours in the latest scan, with the
  -- latest market run's fares and passenger share each way (private.fig_market_pair())
  cpr as (select distinct on (least(f.hub_code, f.dest_code), greatest(f.hub_code, f.dest_code))
                 least(f.hub_code, f.dest_code) as a, greatest(f.hub_code, f.dest_code) as b, f.hub_code as hub, f.dest_code as dest, f.route_id
            from fq f where f.airline_id = p_airline_id
           order by least(f.hub_code, f.dest_code), greatest(f.hub_code, f.dest_code), (f.hub_code = v_main) desc, f.route_id),
  contested as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'pair', m.a || '-' || m.b, 'route_id', c.route_id, 'hub', c.hub, 'dest', c.dest, 'ours', m.weekly,
             'rival_id', t.airline_id, 'rival', t.name, 'rival_weekly', t.weekly,
             'market', private.fig_market_pair(w, p_airline_id, c.hub, c.dest, v_mrun))
             order by t.weekly - m.weekly desc, m.a, m.b), '[]'::jsonb) as d
      from mine m
      join cpr c on c.a = m.a and c.b = m.b
      cross join lateral (select rv.airline_id, rv.name, rv.weekly from rv
                           where rv.scan_id = v_latest and rv.a = m.a and rv.b = m.b order by rv.weekly desc, rv.name, rv.airline_id limit 1) t
     where t.weekly >= m.weekly)
  select jsonb_build_object(
           'markets', (select d from markets), 'openings', (select d from openings),
           'openings_count', (select n from openings), 'openings_allowed', (select n_allowed from openings),
           'openings_left_out', (select n from left_out), 'openings_trunks', (select n_trunks from openings), 'profiles', (select d from profiles),
           'openings_owner_first', (select n from waiting),
           'pairs_flown', (select count(*) from mine), 'pairs_listed', (select count(distinct (ro.a, ro.b)) from ro),
           'competitors', (select d from competitors), 'self', (select d from self), 'contested', (select d from contested))
    into v_body;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'code', v_code, 'name', v_name, 'as_of', private.fig_ts(p_as_of), 'limit', v_limit,
    'scans', jsonb_build_object(
      'latest', case when v_latest is null then null else jsonb_build_object('id', v_latest, 'taken_at', private.fig_ts(v_latest_at)) end,
      'week_before', case when v_before is null then null else jsonb_build_object('id', v_before, 'taken_at', private.fig_ts(v_before_at)) end,
      'previous', case when v_prev is null then null else jsonb_build_object('id', v_prev, 'taken_at', private.fig_ts(v_prev_at)) end),
    'settings', jsonb_build_object('threat_min_weekly', v_min, 'hub_first_departures', v_target, 'contested_rival_weekly', v_rival_weekly,
                                   'contested_rival_daily', v_rival_daily, 'hub_first_exempt', v_exempt, 'wide_full_cabin_km', v_wide_km),
    'hubs_first', jsonb_build_object('main_hub', v_main, 'departures', v_dep, 'target', v_target, 'exempt', v_exempt,
                                     'open', v_exempt or v_main is null or v_dep >= v_target),
    'trunk_month', jsonb_build_object('on', v_trunks, 'from', v_trunk_from, 'to', v_trunk_to),
    'group', v_group,
    'markets', v_body -> 'markets',
    'threats', v_threats,
    'openings', v_body -> 'openings', 'openings_count', v_body -> 'openings_count', 'openings_allowed', v_body -> 'openings_allowed',
    'openings_left_out', v_body -> 'openings_left_out', 'openings_trunks', v_body -> 'openings_trunks',
    'openings_owner_first', v_body -> 'openings_owner_first',
    'profiles', v_body -> 'profiles',
    'pairs_flown', v_body -> 'pairs_flown', 'pairs_listed', v_body -> 'pairs_listed',
    -- the weekly report's three biggest competitors and the airline beside them (none without a scan)
    'competitors', case when v_latest is null then '[]'::jsonb else v_body -> 'competitors' end,
    'self', case when v_latest is null then null else v_body -> 'self' end,
    'order_flags', v_flags,
    -- the market pages (since 30 Oct): the latest finished run, and the contested pairs with their fares and share
    'market_run', v_mrun_doc,
    'contested', case when v_latest is null then '[]'::jsonb else v_body -> 'contested' end,
    'notes', jsonb_build_array(
      'Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §3): a pair between this airline''s base and another of our airlines'' (neither excluded) carries shared (role owner or joiner, the other airline). A shared pair either airline flies is no opening for the other. A pair this airline would join (on its list or not, from its base) is an opening only while the owner''s cash forecast can''t order this evening (next_order not now), marked "owner can''t fund tonight" with owner_next_order; otherwise it waits for the owner and openings_owner_first counts it. With p_limit 0 the owner''s cash isn''t read and those wait too.',
      'Rivals are every airline in the scan that isn''t one of ours; departures a week count each flight''s days, as gscan.py counts them, passenger flights only (freighters left out, as the weekly report counts). Our own now are the airline''s live legs; before, its flights in the week-before scan.',
      'From trunk_month_from to trunk_month_to (November, manual §4) the trunks, pairs between two of our bases (any of our airlines''), come first, shortest first: hubs first isn''t applied to them and no distance leaves one out. Whether a trunk makes sense stays the Scheduling chat''s judgment.',
      'The variant is the default line''s (manual §3): the smallest size the city''s stars allow (1–2 stars small, 3 small or mid, 4 small to large, 5 mid or large), bigger only for reach, the cheapest per seat whose range with a full load covers the distance, among the types the airline may buy; beyond every narrowbody the A350 that is cheapest per seat, and beyond settings.a350_1000_from_km (wide_full_cabin_km under settings here) the one with the most seats.',
      'competitors (the weekly report''s, manual §7): the three rivals with the most departures a week on the city pairs the airline flies (its live legs, both ways) in the latest scan, ties by name; weekly and airports are each one''s whole passenger network in the latest scan, weekly_before in the week-before scan (none when that scan holds no schedule for it), the change against it as a number and a percent. self is the airline on the same terms, from the same scans'' schedules.',
      'fleet (each competitor''s and rival profile''s, since 23 Oct): from its overview page in the latest scan (scan_airline_fleet, scan_airline_profile): overall, on order, average age and its 5 biggest types, with the change in overall and on order against the week-before scan (null when either scan didn''t read its page); null when the latest scan didn''t read it. order_flags: every airline in the latest scan that isn''t one of ours, freighters only left out, with aircraft on order at least rival_orders_flag_pct of its fleet and at least rival_orders_flag_min (kind orders), or on order and no flights in the scan (kind starting); the same list for every airline, each marked on_pairs (it flies one of this airline''s city pairs), at_bases (it departs from one of its hubs or focus cities) and meets (either). No flag feeds the openings, the contested test or the fare pause.',
      'Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §4, §5): each market''s game_share is the game''s own passenger share from the Market Analysis pages read in the latest finished market run (market_run): over each direction of the market''s pairs that was read, the airline''s share (0 where the page doesn''t list it) weighted by the direction''s seats offered in the latest week read (market_weeks; a plain average when no seats are known), with share_before (last week: share − change), pairs_read of pairs, seats and week; beside the scan''s departures share, never replacing it; null when none of its pairs has been read. contested: each city pair the airline flies where a rival has at least as many departures a week as ours in the latest scan (ours from the live legs, the rival with the most), with market: each way, our economy fare against the cheapest rival''s and the game''s passenger share this week and last, from the latest market run (null without a read). The openings, the contested test, hubs first and the threats don''t read them.',
      'connecting (since 23 Oct): each rival''s one-stop departures a week on the airline''s city pairs in the latest scan (scan_rival_connections, worked out at the scan''s finish by private.scan_connections(): same airline, the second flight from the connecting airport''s minimum connection time to connection_max_wait_h after the first lands, both legs together at most rival_connection_detour_max times the direct distance, each first flight counted once). connecting_weekly on each market, each opening (with each rival''s own in connecting), each rival profile and each competitor (with connecting_pairs), each with its top 3 connecting airports (connecting_via); shown beside direct, never added to it: total, share, rivals_weekly, on_pairs and the three biggest competitors (chosen by direct departures) are direct only, and the openings'' order, the contested test, hubs first, the threats and the fare pause don''t read it. Absent when the latest scan has no connections worked out.'));
end
$function$;


-- ============================================================ 5. fare results: a joiner's moves are the pair's
CREATE OR REPLACE FUNCTION private.fig_fare_results(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  -- this Saturday, as fare_ladder() finds it: a row proposed since then is this week's and counts once it is seen
  v_week date := v_today - ((extract(isodow from v_today)::int + 1) % 7);
  v_launch numeric := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_cap numeric := v_launch + private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_floor numeric;
  v_days date[]; v_from date;
  v_rows jsonb; v_base jsonb; v_totals jsonb;
begin
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
  -- the latest 7 complete days by the moment (airline_days.complete: the evening's capture was complete)
  select coalesce(array_agg(x.day order by x.day), '{}') into v_days
    from (select ad.day from public.airline_days ad
           where ad.world_id = w and ad.airline_id = p_airline_id and ad.complete and ad.taken_at <= p_as_of and ad.day <= v_today
           order by ad.day desc limit 7) x;
  -- the earliest day any change could be seen: the flights read for the day fares start there
  select min(fp.proposed_on) into v_from from public.fare_plan fp
   where fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped' and fp.route_id is not null and fp.proposed_on <= v_today
     and (fp.airline_id = p_airline_id
          or fp.route_id in (select j.shares_route_id from public.routes j where j.airline_id = p_airline_id and j.shares_route_id is not null and not j.removed));

  with
  -- the fare ladder's rows of the airline by the moment (holds included: they carry a level)
  ch as materialized (
    select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, fp.direction, coalesce(fp.direction, 'both') as dk,
           fp.level_pct, fp.ladder_move, fp.proposed_on, fp.fare_from, fp.change_pct, null::bigint as owner_route
      from public.fare_plan fp
     where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped' and fp.route_id is not null
       and fp.proposed_on <= v_today
       and not exists (select 1 from public.routes j where j.id = fp.route_id and j.shares_route_id is not null)
    union all
    -- a joiner's route (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §4): its moves are the pair's, the owner's
    -- fare plan rows, each direction the other way round (the joiner's route runs from the other base)
    select fp.id, j.id, coalesce(fp.cabin_class, 'economy'),
           case fp.direction when 'out' then 'back' when 'back' then 'out' end,
           coalesce(case fp.direction when 'out' then 'back' when 'back' then 'out' end, 'both'),
           fp.level_pct, fp.ladder_move, fp.proposed_on, fp.fare_from, fp.change_pct, fp.route_id
      from public.routes j
      join public.fare_plan fp on fp.route_id = j.shares_route_id
     where j.airline_id = p_airline_id and j.world_id = w and not j.removed and j.shares_route_id is not null
       and fp.level_pct is not null and fp.status <> 'dropped' and fp.proposed_on <= v_today),
  pr as (select ro.id as route_id, ro.hub_code as hub, ro.dest_code as dest, coalesce(ro.distance_override_km, ro.distance_km) as km
           from public.routes ro where ro.id in (select distinct ch.route_id from ch)),
  -- each captured flight since the first row was proposed, one per date and flight number (the latest), as
  -- fare_plan_status() reads them
  fl as materialized (
    select distinct on (f.game_date, f.flight_no) f.game_date as day, f.origin_code as o, f.dest_code as d, f.eco_fare as eco,
           case when coalesce(f.bus_seats, 0) > 0 then f.bus_fare end as bus
      from public.game_flights f
     where f.airline_id = p_airline_id and f.flight_no is not null and f.loads_captured_at <= p_as_of
       and f.game_date >= v_from and f.game_date <= v_today
     order by f.game_date, f.flight_no, f.id desc),
  fx as (select pr.route_id, case when fl.o = pr.hub then 'out' else 'back' end as dir, fl.day, fl.eco, fl.bus
           from pr join fl on (fl.o = pr.hub and fl.d = pr.dest) or (fl.o = pr.dest and fl.d = pr.hub)),
  -- each day's average fare by cabin, each direction's and both directions' together (dir both, for a row with no direction)
  fd as (select fx.route_id, coalesce(fx.dir, 'both') as dir, fx.day, avg(fx.eco) as eco, avg(fx.bus) as bus
           from fx group by grouping sets ((fx.route_id, fx.dir, fx.day), (fx.route_id, fx.day))),
  -- the daily history's, for the days whose flights are archived: route_days' average fare in that cabin (business on a day
  -- with business passengers)
  hx as (select pr.route_id, case when d.origin_code = pr.hub then 'out' else 'back' end as dir, d.day,
                case when d.eco_fare_avg > 0 then d.eco_fare_avg end as eco,
                case when d.bus_pax > 0 and d.bus_fare_avg > 0 then d.bus_fare_avg end as bus
           from public.route_days d
           join pr on (d.origin_code = pr.hub and d.dest_code = pr.dest) or (d.origin_code = pr.dest and d.dest_code = pr.hub)
          where d.airline_id = p_airline_id and d.world_id = w and d.day >= v_from and d.day <= v_today),
  hd as (select hx.route_id, coalesce(hx.dir, 'both') as dir, hx.day, avg(hx.eco) as eco, avg(hx.bus) as bus
           from hx group by grouping sets ((hx.route_id, hx.dir, hx.day), (hx.route_id, hx.day))),
  df as materialized (
    select coalesce(fd.route_id, hd.route_id) as route_id, coalesce(fd.dir, hd.dir) as dir, coalesce(fd.day, hd.day) as day,
           coalesce(fd.eco, hd.eco) as eco, coalesce(fd.bus, hd.bus) as bus
      from fd full join hd on hd.route_id = fd.route_id and hd.dir = fd.dir and hd.day = fd.day),
  -- each row and the day the captures saw it (fare_plan_status()'s rule for a fare ladder row, over every day kept)
  cs as materialized (
    select ch.*,
           (select min(df.day) from df
             where df.route_id = ch.route_id and df.dir = ch.dk and df.day >= ch.proposed_on and ch.fare_from > 0
               and abs((case when ch.cabin = 'business' then df.bus else df.eco end) / ch.fare_from - (1 + coalesce(ch.change_pct, 0) / 100)) <= 0.01) as seen_on
      from ch),
  -- each row for the direction(s) it is for: a row with no direction (before 26 Oct) for both
  cd as (select cs.*, d.dir from cs cross join (values ('out'), ('back')) d (dir) where cs.direction is null or cs.direction = d.dir),
  mv as (select * from cd where cd.ladder_move is distinct from 'hold'),
  -- the repriced directions: at least one seen change
  rp as (select mv.route_id, mv.dir, count(*)::int as n, min(mv.seen_on) as first_seen
           from mv where mv.seen_on is not null group by mv.route_id, mv.dir),
  lt as (select distinct on (mv.route_id, mv.dir) mv.route_id, mv.dir, mv.id, mv.proposed_on, mv.seen_on, mv.ladder_move, mv.level_pct, mv.cabin
           from mv where mv.seen_on is not null order by mv.route_id, mv.dir, mv.proposed_on desc, mv.id desc),
  -- changes planned but not yet seen
  pn as (select distinct on (mv.route_id, mv.dir) mv.route_id, mv.dir, mv.proposed_on, mv.ladder_move, mv.level_pct, mv.cabin,
                count(*) over (partition by mv.route_id, mv.dir)::int as n
           from mv where mv.seen_on is null order by mv.route_id, mv.dir, mv.proposed_on desc, mv.id desc),
  -- each cabin's level now (fare_ladder()'s rule): the latest recorded before this Saturday, or this week's once seen
  lv as (select distinct on (cd.route_id, cd.dir, cd.cabin) cd.route_id, cd.dir, cd.cabin, cd.level_pct
           from cd where cd.proposed_on < v_week or cd.seen_on is not null
          order by cd.route_id, cd.dir, cd.cabin, cd.proposed_on desc, cd.id desc),
  base as (select rp.*, pr.hub, pr.dest, pr.km,
                  case rp.dir when 'out' then pr.hub else pr.dest end as dir_from,
                  case rp.dir when 'out' then pr.dest else pr.hub end as dir_to,
                  (select count(*)::int from unnest(v_days) x where x >= rp.first_seen) as now_days
             from rp join pr on pr.route_id = rp.route_id),
  -- the direction's days in route_days: the 7 before first_seen, and the latest complete days on or after it
  fig as (select b.*, s.*
            from base b
            cross join lateral (
              select sum(d.flights) filter (where d.day < b.first_seen) as b_flights,
                     sum(d.flights) filter (where d.day < b.first_seen and d.profit is not null) as b_mflights,
                     sum(d.revenue) filter (where d.day < b.first_seen and d.profit is not null) as b_rev,
                     sum(d.profit) filter (where d.day < b.first_seen) as b_profit,
                     sum(d.eco_fare_avg * d.eco_pax) filter (where d.day < b.first_seen and d.eco_pax > 0) as b_fare_x,
                     sum(d.eco_pax) filter (where d.day < b.first_seen and d.eco_pax > 0 and d.eco_fare_avg is not null) as b_fare_n,
                     avg(d.eco_fare_avg) filter (where d.day < b.first_seen) as b_fare_avg,
                     sum(d.eco_pax) filter (where d.day < b.first_seen and d.eco_seats > 0) as b_eco_pax,
                     sum(d.eco_seats) filter (where d.day < b.first_seen and d.eco_seats > 0) as b_eco_seats,
                     sum(d.bus_pax) filter (where d.day < b.first_seen and d.bus_seats > 0) as b_bus_pax,
                     sum(d.bus_seats) filter (where d.day < b.first_seen and d.bus_seats > 0) as b_bus_seats,
                     sum(d.flights) filter (where d.day >= b.first_seen) as n_flights,
                     sum(d.flights) filter (where d.day >= b.first_seen and d.profit is not null) as n_mflights,
                     sum(d.revenue) filter (where d.day >= b.first_seen and d.profit is not null) as n_rev,
                     sum(d.profit) filter (where d.day >= b.first_seen) as n_profit,
                     sum(d.eco_fare_avg * d.eco_pax) filter (where d.day >= b.first_seen and d.eco_pax > 0) as n_fare_x,
                     sum(d.eco_pax) filter (where d.day >= b.first_seen and d.eco_pax > 0 and d.eco_fare_avg is not null) as n_fare_n,
                     avg(d.eco_fare_avg) filter (where d.day >= b.first_seen) as n_fare_avg,
                     sum(d.eco_pax) filter (where d.day >= b.first_seen and d.eco_seats > 0) as n_eco_pax,
                     sum(d.eco_seats) filter (where d.day >= b.first_seen and d.eco_seats > 0) as n_eco_seats,
                     sum(d.bus_pax) filter (where d.day >= b.first_seen and d.bus_seats > 0) as n_bus_pax,
                     sum(d.bus_seats) filter (where d.day >= b.first_seen and d.bus_seats > 0) as n_bus_seats
                from public.route_days d
               where d.world_id = w and d.airline_id = p_airline_id and d.origin_code = b.dir_from and d.dest_code = b.dir_to
                 and ((d.day >= b.first_seen - 7 and d.day < b.first_seen) or (d.day >= b.first_seen and d.day = any (v_days)))) s),
  calc as (select f.*,
                  f.b_profit / nullif(f.b_mflights, 0) as b_ppf, f.n_profit / nullif(f.n_mflights, 0) as n_ppf,
                  f.b_rev / nullif(f.b_mflights, 0) as b_rpf, f.n_rev / nullif(f.n_mflights, 0) as n_rpf,
                  coalesce(f.b_fare_x / nullif(f.b_fare_n, 0), f.b_fare_avg) as b_fare, coalesce(f.n_fare_x / nullif(f.n_fare_n, 0), f.n_fare_avg) as n_fare,
                  100.0 * f.b_eco_pax / nullif(f.b_eco_seats, 0) as b_eco, 100.0 * f.n_eco_pax / nullif(f.n_eco_seats, 0) as n_eco,
                  100.0 * f.b_bus_pax / nullif(f.b_bus_seats, 0) as b_bus, 100.0 * f.n_bus_pax / nullif(f.n_bus_seats, 0) as n_bus,
                  coalesce(f.b_flights, 0) as b_fw,
                  case when f.now_days > 0 then coalesce(f.n_flights, 0) * 7.0 / f.now_days end as n_fw,
                  (select l.level_pct from lv l where l.route_id = f.route_id and l.dir = f.dir and l.cabin = 'economy') as eco_rec,
                  (select l.level_pct from lv l where l.route_id = f.route_id and l.dir = f.dir and l.cabin = 'business') as bus_rec
             from fig f),
  rw as (select c.*,
                coalesce(c.eco_rec, v_launch) as eco_level,
                -- business: its recorded level, else launch where the direction flew business in its windows; none otherwise
                case when c.bus_rec is not null then c.bus_rec when coalesce(c.b_bus_seats, 0) + coalesce(c.n_bus_seats, 0) > 0 then v_launch end as bus_level,
                (c.n_ppf - c.b_ppf) * c.n_fw as profit_week
           from calc c),
  fin as (select r.*,
                 r.eco_level >= v_cap or coalesce(r.bus_level >= v_cap, false) as at_cap,
                 coalesce(r.eco_level <= v_floor or r.bus_level <= v_floor, false) as at_floor,
                 coalesce(r.n_eco < 95 and r.b_eco >= 95, false) as load_fell,
                 coalesce(r.n_fw is not null and abs(r.n_fw - r.b_fw) >= 2, false) as freq_changed,
                 r.now_days < 3 as too_soon
            from rw r)
  select coalesce(jsonb_agg(jsonb_build_object(
           'route_id', f.route_id, 'hub', f.hub, 'dest', f.dest, 'direction', f.dir, 'from', f.dir_from, 'to', f.dir_to, 'km', f.km,
           'economy_level', trim_scale(f.eco_level), 'business_level', trim_scale(f.bus_level), 'at_cap', f.at_cap, 'at_floor', f.at_floor,
           'moves', jsonb_build_object(
             'count', f.n, 'first_seen', f.first_seen,
             'latest', (select jsonb_build_object('id', l.id, 'proposed_on', l.proposed_on, 'seen_on', l.seen_on, 'move', l.ladder_move,
                                                  'level', trim_scale(l.level_pct), 'cabin', l.cabin)
                          from lt l where l.route_id = f.route_id and l.dir = f.dir),
             'pending', (select jsonb_build_object('proposed_on', p.proposed_on, 'move', p.ladder_move, 'level', trim_scale(p.level_pct), 'cabin', p.cabin, 'count', p.n)
                           from pn p where p.route_id = f.route_id and p.dir = f.dir),
             'changes', (select jsonb_agg(jsonb_build_object('id', m.id, 'proposed_on', m.proposed_on, 'seen_on', m.seen_on, 'cabin', m.cabin,
                                                             'move', m.ladder_move, 'level', trim_scale(m.level_pct)) order by m.proposed_on, m.id)
                           from mv m where m.route_id = f.route_id and m.dir = f.dir and m.seen_on is not null)),
           'before', jsonb_build_object('from', f.first_seen - 7, 'to', f.first_seen - 1, 'days', 7,
             'flights', coalesce(f.b_flights, 0), 'flights_week', round(f.b_fw, 1), 'economy_fare', round(f.b_fare, 2),
             'economy_load', round(f.b_eco, 1), 'business_load', round(f.b_bus, 1),
             'revenue_per_flight', round(f.b_rpf), 'profit_per_flight', round(f.b_ppf)),
           'now', jsonb_build_object('from', (select min(x) from unnest(v_days) x where x >= f.first_seen), 'to', (select max(x) from unnest(v_days) x where x >= f.first_seen),
             'days', f.now_days, 'flights', coalesce(f.n_flights, 0), 'flights_week', round(f.n_fw, 1), 'economy_fare', round(f.n_fare, 2),
             'economy_load', round(f.n_eco, 1), 'business_load', round(f.n_bus, 1),
             'revenue_per_flight', round(f.n_rpf), 'profit_per_flight', round(f.n_ppf)),
           'change', jsonb_build_object(
             'economy_fare_pct', round((f.n_fare / nullif(f.b_fare, 0) - 1) * 100, 1),
             'economy_load_pts', round(f.n_eco - f.b_eco, 1), 'business_load_pts', round(f.n_bus - f.b_bus, 1),
             'revenue_per_flight_pct', round((f.n_rpf - f.b_rpf) / nullif(abs(f.b_rpf), 0) * 100, 1),
             'profit_per_flight_pct', round((f.n_ppf - f.b_ppf) / nullif(abs(f.b_ppf), 0) * 100, 1),
             'flights_week', round(f.n_fw - f.b_fw, 1)),
           'profit_week', round(f.profit_week),
           -- a joiner's direction (since 5 Nov): the pair's moves, the owner's airline and route
           'follows', (select jsonb_build_object('airline_id', o.airline_id, 'airline', coalesce(a.public_name, a.planner_name, a.game_name), 'route_id', o.id)
                         from public.routes j join public.routes o on o.id = j.shares_route_id join public.airlines a on a.id = o.airline_id
                        where j.id = f.route_id),
           'flags', to_jsonb(array_remove(array[case when f.load_fell then 'load_fell' end, case when f.freq_changed then 'frequency_changed' end,
                                                case when f.too_soon then 'too_soon' end, case when f.at_cap then 'at_cap' end], null)),
           -- the sums the totals add up (AS$ and flights with money), so a reader can weight them as the totals do
           'sums', jsonb_build_object('before_flights', coalesce(f.b_mflights, 0), 'before_profit', round(coalesce(f.b_profit, 0)),
                                      'now_flights', coalesce(f.n_mflights, 0), 'now_profit', round(coalesce(f.n_profit, 0))))
           order by f.profit_week desc nulls last, f.hub, f.dest, f.dir = 'back'), '[]'::jsonb)
    into v_rows
    from fin f;

  -- the baseline: the airline's directions with no seen change, before the 7 days before the earliest first_seen, now the
  -- latest complete days on or after it
  with rs as (select e from jsonb_array_elements(v_rows) e),
       fs as (select min((e #>> '{moves,first_seen}')::date) as d from rs),
       rd as (select d.* from public.route_days d, fs
               where fs.d is not null and d.world_id = w and d.airline_id = p_airline_id
                 and not exists (select 1 from rs where rs.e ->> 'from' = d.origin_code and rs.e ->> 'to' = d.dest_code)
                 and ((d.day >= fs.d - 7 and d.day < fs.d) or (d.day >= fs.d and d.day = any (v_days)))),
       s as (select fs.d,
                    count(distinct (rd.origin_code, rd.dest_code))::int as dirs,
                    sum(rd.flights) filter (where rd.day < fs.d and rd.profit is not null) as b_f, sum(rd.profit) filter (where rd.day < fs.d) as b_p,
                    sum(rd.flights) filter (where rd.day >= fs.d and rd.profit is not null) as n_f, sum(rd.profit) filter (where rd.day >= fs.d) as n_p,
                    sum(rd.eco_pax) filter (where rd.day < fs.d and rd.eco_seats > 0) as b_ep, sum(rd.eco_seats) filter (where rd.day < fs.d and rd.eco_seats > 0) as b_es,
                    sum(rd.eco_pax) filter (where rd.day >= fs.d and rd.eco_seats > 0) as n_ep, sum(rd.eco_seats) filter (where rd.day >= fs.d and rd.eco_seats > 0) as n_es
               from fs left join rd on true group by fs.d)
  select case when s.d is null then null else jsonb_build_object(
           'directions', s.dirs,
           'before', jsonb_build_object('from', s.d - 7, 'to', s.d - 1, 'flights', coalesce(s.b_f, 0), 'profit_per_flight', round(s.b_p / nullif(s.b_f, 0)),
                                        'economy_load', round(100.0 * s.b_ep / nullif(s.b_es, 0), 1)),
           'now', jsonb_build_object('from', (select min(x) from unnest(v_days) x where x >= s.d), 'to', (select max(x) from unnest(v_days) x where x >= s.d),
                                     'days', (select count(*) from unnest(v_days) x where x >= s.d),
                                     'flights', coalesce(s.n_f, 0), 'profit_per_flight', round(s.n_p / nullif(s.n_f, 0)),
                                     'economy_load', round(100.0 * s.n_ep / nullif(s.n_es, 0), 1)),
           'profit_per_flight_pct', round((s.n_p / nullif(s.n_f, 0) - s.b_p / nullif(s.b_f, 0)) / nullif(abs(s.b_p / nullif(s.b_f, 0)), 0) * 100, 1)) end
    into v_base
    from s;

  -- the totals: every repriced direction together, its profit a flight weighted by flights (the sums), and the rows'
  -- profit a week added up
  with rs as (select e from jsonb_array_elements(v_rows) e),
       t as (select count(*)::int as n,
                    count(*) filter (where e #>> '{moves,latest,move}' in ('up', 'revert'))::int as up,
                    count(*) filter (where e #>> '{moves,latest,move}' in ('down', 'jump'))::int as down,
                    count(*) filter (where (e ->> 'at_cap')::boolean)::int as at_cap,
                    count(*) filter (where e -> 'flags' ? 'load_fell')::int as load_fell,
                    count(*) filter (where e -> 'flags' ? 'frequency_changed')::int as freq,
                    count(*) filter (where e -> 'flags' ? 'too_soon')::int as soon,
                    sum((e #>> '{sums,before_flights}')::numeric) as bf, sum((e #>> '{sums,before_profit}')::numeric) as bp,
                    sum((e #>> '{sums,now_flights}')::numeric) as nf, sum((e #>> '{sums,now_profit}')::numeric) as np,
                    sum((e ->> 'profit_week')::numeric) as pw
               from rs)
  select jsonb_build_object(
           'directions', t.n, 'up', t.up, 'down', t.down, 'at_cap', t.at_cap, 'load_fell', t.load_fell, 'frequency_changed', t.freq, 'too_soon', t.soon,
           'before', jsonb_build_object('flights', coalesce(t.bf, 0), 'profit_per_flight', round(t.bp / nullif(t.bf, 0))),
           'now', jsonb_build_object('flights', coalesce(t.nf, 0), 'profit_per_flight', round(t.np / nullif(t.nf, 0))),
           'profit_per_flight_pct', round((t.np / nullif(t.nf, 0) - t.bp / nullif(t.bf, 0)) / nullif(abs(t.bp / nullif(t.bf, 0)), 0) * 100, 1),
           'baseline_profit_per_flight_pct', v_base -> 'profit_per_flight_pct',
           'profit_week', coalesce(round(t.pw), 0))
    into v_totals
    from t;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of), 'week_of', v_week,
    'days', jsonb_build_object('from', (select min(x) from unnest(v_days) x), 'to', (select max(x) from unnest(v_days) x), 'count', cardinality(v_days)),
    'settings', jsonb_build_object('launch_pct', v_launch, 'cap_pct', v_cap, 'floor_pct', v_floor, 'load_fell_pct', 95, 'frequency_changed_week', 2, 'too_soon_days', 3),
    'totals', v_totals, 'baseline', v_base, 'routes', v_rows,
    'notes', jsonb_build_array(
      'Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §4): on a joiner''s route the moves are the pair''s, the owner''s fare plan rows (each direction the other way round, since the joiner''s route runs from the other base), seen on the joiner''s own captured fares; its before and after figures are its own flights''. Such a row carries follows (the owner''s airline and route).',
      'A direction is repriced once the captures see a fare ladder change on it (up, down, jump or revert, either cabin): the first day its average fare in that cabin and direction is the fare then times the change, within 1% (fare_plan_status()''s rule, over every day kept). Before is the 7 UTC days before that first day; now is the latest 7 complete days on or after it, so a change seen a few days ago is judged on those days only. Money is AS$ a flight from the daily history (route_days), before leases. The baseline is the airline''s other directions over the same days, so fuel, fees and aircraft changes don''t pass for fare effects.'));
end
$function$;

-- ============================================================ 6. the route story of a joined pair: one page for both airlines
create or replace function private.fig_pair_story(p_route_id bigint, p_as_of timestamp with time zone)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare pr record; v jsonb; x jsonb; o jsonb; jn jsonb; v_role text; v_latest date; v_joined date;
  v_days jsonb; v_weeks jsonb; v_dirdays jsonb; v_events jsonb; v_fares jsonb; v_side jsonb; v_rivals jsonb;
begin
  select * into pr from private.fig_route_pair(p_route_id) limit 1;
  if pr.role is null then return private.fig_route_story(p_route_id, p_as_of); end if;
  v_role := pr.role;
  -- v: the story of the route the address names, x: the other airline's; the page is drawn from v's side (its hub, its
  -- directions), the same pair either way
  v := private.fig_route_story(p_route_id, p_as_of);
  x := private.fig_route_story(pr.other_route_id, p_as_of);
  o := case when v_role = 'owner' then v else x end;
  jn := case when v_role = 'owner' then x else v end;
  select (r.created_at at time zone 'UTC')::date into v_joined from public.routes r where r.id = pr.joiner_route_id;
  v_latest := greatest((v ->> 'latest_day')::date, (x ->> 'latest_day')::date);

  -- combined where the market is one: each day's flights, seats, passengers and loads of both airlines together, the
  -- fare weighted by passengers, and the money added up (each airline's own is in pair.airlines)
  with d as (select e from jsonb_array_elements(coalesce(v -> 'days', '[]')) e union all select e from jsonb_array_elements(coalesce(x -> 'days', '[]')) e),
  g as (select (e ->> 'day')::date as day, sum((e ->> 'flights')::numeric) as flights, sum((e ->> 'passengers')::numeric) as pax,
               sum((e ->> 'seats')::numeric) as seats, sum((e ->> 'load_pct')::numeric * (e ->> 'seats')::numeric / 100) as lpax,
               sum((e ->> 'eco_pax')::numeric) as eco_pax, sum((e ->> 'eco_seats')::numeric) as eco_seats,
               sum((e ->> 'bus_pax')::numeric) as bus_pax, sum((e ->> 'bus_seats')::numeric) as bus_seats,
               sum((e ->> 'eco_fare')::numeric * (e ->> 'eco_pax')::numeric) filter (where (e ->> 'eco_pax')::numeric > 0) as eco_fx,
               sum((e ->> 'eco_pax')::numeric) filter (where (e ->> 'eco_pax')::numeric > 0 and e ->> 'eco_fare' is not null) as eco_fn,
               avg((e ->> 'eco_fare')::numeric) as eco_fa,
               sum((e ->> 'bus_fare')::numeric * (e ->> 'bus_pax')::numeric) filter (where (e ->> 'bus_pax')::numeric > 0) as bus_fx,
               sum((e ->> 'bus_pax')::numeric) filter (where (e ->> 'bus_pax')::numeric > 0 and e ->> 'bus_fare' is not null) as bus_fn,
               avg((e ->> 'bus_fare')::numeric) as bus_fa,
               sum((e ->> 'revenue')::numeric) as revenue, sum((e ->> 'costs')::numeric) as costs, sum((e ->> 'profit')::numeric) as profit,
               sum((e ->> 'block_hours')::numeric) as block_hours
          from d group by 1),
  wk as (select (v_latest - g.day) / 7 as w, min(g.day) as d0, count(*)::int as n,
                sum(g.flights) as flights, sum(g.pax) as pax, sum(g.seats) as seats, sum(g.lpax) as lpax, sum(g.eco_pax) as eco_pax,
                sum(g.eco_seats) as eco_seats, sum(g.bus_pax) as bus_pax, sum(g.bus_seats) as bus_seats, sum(g.eco_fx) as eco_fx,
                sum(g.eco_fn) as eco_fn, avg(g.eco_fa) as eco_fa, sum(g.bus_fx) as bus_fx, sum(g.bus_fn) as bus_fn, avg(g.bus_fa) as bus_fa,
                sum(g.revenue) as revenue, sum(g.costs) as costs, sum(g.profit) as profit, sum(g.block_hours) as block_hours
           from g where (v_latest - g.day) / 7 < 13 group by 1),
  f as (select true as is_day, g.day as d0, g.day as d1, null::int as n, g.flights, g.pax, g.seats, g.lpax, g.eco_pax, g.eco_seats, g.bus_pax, g.bus_seats,
               g.eco_fx, g.eco_fn, g.eco_fa, g.bus_fx, g.bus_fn, g.bus_fa, g.revenue, g.costs, g.profit, g.block_hours from g
        union all
        select false, v_latest - wk.w * 7 - 6, v_latest - wk.w * 7, wk.n, wk.flights, wk.pax, wk.seats, wk.lpax, wk.eco_pax, wk.eco_seats,
               wk.bus_pax, wk.bus_seats, wk.eco_fx, wk.eco_fn, wk.eco_fa, wk.bus_fx, wk.bus_fn, wk.bus_fa, wk.revenue, wk.costs, wk.profit, wk.block_hours from wk),
  j as (select f.is_day, f.d0, jsonb_build_object(
               'flights', f.flights, 'passengers', f.pax, 'seats', f.seats, 'load_pct', round(100.0 * f.lpax / nullif(f.seats, 0), 1),
               'eco_pax', f.eco_pax, 'eco_seats', f.eco_seats, 'eco_load_pct', round(100.0 * f.eco_pax / nullif(f.eco_seats, 0), 1),
               'bus_pax', f.bus_pax, 'bus_seats', f.bus_seats, 'bus_load_pct', round(100.0 * f.bus_pax / nullif(f.bus_seats, 0), 1),
               'eco_fare', round(coalesce(f.eco_fx / nullif(f.eco_fn, 0), f.eco_fa), 2), 'bus_fare', round(coalesce(f.bus_fx / nullif(f.bus_fn, 0), f.bus_fa), 2),
               'revenue', round(f.revenue, 5), 'costs', round(f.costs, 5), 'profit', round(f.profit, 5), 'block_hours', round(f.block_hours, 2),
               'profit_per_hour', case when f.block_hours > 0 then round(f.profit / f.block_hours, 5) end)
               || case when f.is_day then jsonb_build_object('day', f.d0) else jsonb_build_object('from', f.d0, 'to', f.d1, 'days', f.n) end as e
          from f)
  select coalesce(jsonb_agg(j.e order by j.d0) filter (where j.is_day), '[]'::jsonb), coalesce(jsonb_agg(j.e order by j.d0 desc) filter (where not j.is_day), '[]'::jsonb)
    into v_days, v_weeks from j;

  -- by direction, from the named route's side: the other route's out is this one's back
  with d as (select e ->> 'day' as day, e ->> 'direction' as dir, e from jsonb_array_elements(coalesce(v -> 'days_by_direction', '[]')) e
             union all
             select e ->> 'day', case e ->> 'direction' when 'out' then 'back' else 'out' end, e from jsonb_array_elements(coalesce(x -> 'days_by_direction', '[]')) e),
  g as (select d.day, d.dir, sum((d.e ->> 'flights')::int)::int as flights, sum((d.e ->> 'eco_pax')::int)::int as eco_pax, sum((d.e ->> 'eco_seats')::int)::int as eco_seats,
               sum((d.e ->> 'bus_pax')::int)::int as bus_pax, sum((d.e ->> 'bus_seats')::int)::int as bus_seats
          from d group by 1, 2)
  select coalesce(jsonb_agg(jsonb_build_object('day', g.day, 'direction', g.dir, 'flights', g.flights,
                    'eco_pax', g.eco_pax, 'eco_seats', g.eco_seats, 'eco_load_pct', round(100.0 * g.eco_pax / nullif(g.eco_seats, 0), 1),
                    'bus_pax', g.bus_pax, 'bus_seats', g.bus_seats, 'bus_load_pct', round(100.0 * g.bus_pax / nullif(g.bus_seats, 0), 1))
                  order by g.day, g.dir = 'back'), '[]'::jsonb)
    into v_dirdays from g;

  -- one timeline: both airlines' events, each marked with its airline; the rivals once (the owner's story's); the joiner's
  -- first flights, and the day its row was added, as the day it came in
  select coalesce(jsonb_agg(z.e order by (z.e ->> 'day')::date desc,
                             array_position(array['rival', 'fare', 'retimed', 'aircraft changed', 'frequency removed', 'frequency added', 'joined', 'launched'], z.e ->> 'kind'),
                             z.e ->> 'at' desc nulls last, z.e ->> 'words'), '[]'::jsonb)
    into v_events
    from (select e || jsonb_build_object('airline', o #>> '{route,airline,code}', 'airline_id', (o #>> '{route,airline,id}')::bigint) as e
            from jsonb_array_elements(coalesce(o -> 'events', '[]')) e
          union all
          select case when e ->> 'kind' = 'launched'
                      then e || jsonb_build_object('kind', 'joined', 'words', format('%s''s first flights on the pair', jn #>> '{route,airline,name}'))
                      else e end
                 || jsonb_build_object('airline', jn #>> '{route,airline,code}', 'airline_id', (jn #>> '{route,airline,id}')::bigint)
            from jsonb_array_elements(coalesce(jn -> 'events', '[]')) e where e ->> 'kind' <> 'rival'
          union all
          select jsonb_build_object('day', v_joined, 'kind', 'joined', 'words', format('%s joined the pair (%s owns it)', jn #>> '{route,airline,name}', o #>> '{route,airline,name}'),
                                    'airline', jn #>> '{route,airline,code}', 'airline_id', (jn #>> '{route,airline,id}')::bigint)
           where v_joined is not null and v_joined <= (p_as_of at time zone 'UTC')::date) z;

  -- the fare level: the pair's, the owner's ladder; from the named route's side (a joiner's own rows follow it; with none
  -- yet, the owner's rows the other way round)
  v_fares := case when jsonb_array_length(coalesce(v #> '{now,fares}', '[]')) > 0 then v #> '{now,fares}'
                  else (select coalesce(jsonb_agg(e || jsonb_build_object('direction', case e ->> 'direction' when 'out' then 'back' when 'back' then 'out' else e ->> 'direction' end)), '[]'::jsonb)
                          from jsonb_array_elements(coalesce(x #> '{now,fares}', '[]')) e) end;

  -- each airline's side, separate where the money is
  select jsonb_agg(jsonb_build_object(
           'role', s.role, 'airline_id', (s.d #>> '{route,airline,id}')::bigint, 'code', s.d #>> '{route,airline,code}', 'airline', s.d #>> '{route,airline,name}',
           'route_id', (s.d #>> '{route,id}')::bigint, 'hub', s.d #>> '{route,hub}', 'dest', s.d #>> '{route,dest}',
           'departures', (s.d #>> '{now,departures,out}')::int + (s.d #>> '{now,departures,back}')::int,
           'types', s.d #> '{now,types}', 'launched', s.d #> '{route,launched}', 'latest_day', s.d -> 'latest_day',
           'days', (select coalesce(jsonb_agg(jsonb_build_object('day', e -> 'day', 'flights', e -> 'flights', 'seats', e -> 'seats', 'passengers', e -> 'passengers',
                                                                 'load_pct', e -> 'load_pct', 'revenue', e -> 'revenue', 'costs', e -> 'costs', 'profit', e -> 'profit')
                                              order by e ->> 'day'), '[]'::jsonb)
                      from jsonb_array_elements(coalesce(s.d -> 'days', '[]')) e),
           'weeks', (select coalesce(jsonb_agg(jsonb_build_object('from', e -> 'from', 'to', e -> 'to', 'days', e -> 'days', 'flights', e -> 'flights',
                                                                  'load_pct', e -> 'load_pct', 'revenue', e -> 'revenue', 'profit', e -> 'profit')
                                               order by e ->> 'from' desc), '[]'::jsonb)
                       from jsonb_array_elements(coalesce(s.d -> 'weeks', '[]')) e))
           order by s.role = 'joiner')
    into v_side
    from (values ('owner', o), ('joiner', jn)) s (role, d);

  -- rivals on the pair: the owner's story's (the same scans), with ours both airlines' departures and our share again
  v_rivals := o -> 'rivals';
  if jsonb_typeof(v_rivals) = 'object' then
    v_rivals := v_rivals || jsonb_build_object(
      'ours', coalesce((o #>> '{rivals,ours}')::int, 0) + coalesce((jn #>> '{rivals,ours}')::int, 0),
      'share', case when v_rivals -> 'scan' is not null and jsonb_typeof(v_rivals -> 'scan') = 'object'
                    then round(100.0 * (coalesce((o #>> '{rivals,ours}')::int, 0) + coalesce((jn #>> '{rivals,ours}')::int, 0))
                               / nullif(coalesce((o #>> '{rivals,ours}')::int, 0) + coalesce((jn #>> '{rivals,ours}')::int, 0) + coalesce((v_rivals ->> 'rivals_weekly')::int, 0), 0), 1) end,
      'shares', (select coalesce(jsonb_agg(e || jsonb_build_object(
                          'ours', (e ->> 'ours')::int + coalesce(js.ours, 0),
                          'share', round(100.0 * ((e ->> 'ours')::int + coalesce(js.ours, 0)) / nullif((e ->> 'ours')::int + coalesce(js.ours, 0) + (e ->> 'rivals')::int, 0), 1))
                          order by e ->> 'taken_at', e ->> 'scan_id'), '[]'::jsonb)
                   from jsonb_array_elements(coalesce(v_rivals -> 'shares', '[]')) e
                   left join lateral (select (k ->> 'ours')::int as ours from jsonb_array_elements(coalesce(jn #> '{rivals,shares}', '[]')) k
                                       where k ->> 'scan_id' = e ->> 'scan_id' limit 1) js on true));
  end if;

  return v || jsonb_build_object(
    'latest_day', v_latest,
    'now', (v -> 'now') || jsonb_build_object(
      'departures', jsonb_build_object('out', (v #>> '{now,departures,out}')::int + (x #>> '{now,departures,back}')::int,
                                       'back', (v #>> '{now,departures,back}')::int + (x #>> '{now,departures,out}')::int),
      'rotations', (v #>> '{now,rotations}')::int + (x #>> '{now,rotations}')::int,
      'types', (select coalesce(jsonb_agg(e order by (e ->> 'aircraft')::int desc, e ->> 'type'), '[]'::jsonb)
                  from (select jsonb_build_object('type_id', t.type_id, 'type', t.type, 'aircraft', sum(t.n)::int) as e
                          from (select (e ->> 'type_id')::bigint as type_id, e ->> 'type' as type, (e ->> 'aircraft')::int as n
                                  from jsonb_array_elements(coalesce(v #> '{now,types}', '[]') || coalesce(x #> '{now,types}', '[]')) e) t
                         group by t.type_id, t.type) y),
      'fares', v_fares),
    'days', v_days, 'days_by_direction', v_dirdays, 'weeks', v_weeks, 'events', v_events, 'rivals', v_rivals,
    'pair', jsonb_build_object(
      'role', v_role, 'follows', v_role = 'joiner',
      'title', format('%s · %s', o #>> '{route,airline,name}', jn #>> '{route,airline,name}'),
      'owner', jsonb_build_object('airline_id', (o #>> '{route,airline,id}')::bigint, 'code', o #>> '{route,airline,code}', 'airline', o #>> '{route,airline,name}',
                                  'route_id', pr.owner_route_id, 'hub', o #>> '{route,hub}', 'dest', o #>> '{route,dest}'),
      'joiner', jsonb_build_object('airline_id', (jn #>> '{route,airline,id}')::bigint, 'code', jn #>> '{route,airline,code}', 'airline', jn #>> '{route,airline,name}',
                                   'route_id', pr.joiner_route_id, 'hub', jn #>> '{route,hub}', 'dest', jn #>> '{route,dest}', 'joined_on', v_joined),
      'airlines', v_side),
    'notes', (v -> 'notes') || jsonb_build_array(
      'Shared pair (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §4): two of our airlines fly this pair at one price, the owner''s level. days, weeks, days_by_direction and now (departures, rotations, types) are both airlines'' flights together, from the route the address names (its hub, its directions); weeks are 7-day blocks of those days ending on the later latest_day. Money there is the pair''s total; each airline keeps what it flies, so pair.airlines gives each one''s own days, weeks, departures, revenue and profit. events is one timeline, each marked with its airline (rivals once, the joiner''s first flights and the day it joined as joined). rivals counts both airlines as ours. now.fares is the pair''s level: on the joiner''s side its rows follow the owner''s ladder.'));
end
$function$;
revoke all on function private.fig_pair_story(bigint, timestamptz) from public, anon, authenticated, service_role;
comment on function private.fig_pair_story(bigint, timestamptz) is 'route_story()''s builder for a route on a joined shared pair (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §4): both airlines'' stories (private.fig_route_story()) as one page, from the side of the route asked for. Combined where the market is one (days, weeks, days_by_direction, departures, rotations and types both airlines'' together; the fare level the pair''s, the owner''s ladder; rivals with both airlines as ours), separate where the money is (pair.airlines: each airline''s role, route, departures, days and weeks with its own revenue and profit), and one timeline (events from both, each marked with its airline; the rivals once; the joiner''s coming in as joined). pair: role (of the route asked for), follows (true on the joiner''s side), title (both airlines), owner and joiner. Any other route: fig_route_story()''s answer. Internal.';

create or replace function public.route_story(p_route_id bigint, p_as_of timestamp with time zone default now())
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
 set statement_timeout to '30s'
 set plan_cache_mode to 'force_custom_plan'
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  -- a route on a joined shared pair (since 5 Nov): the pair's one page
  if exists (select 1 from private.fig_route_pair(p_route_id)) then
    return private.fig_pair_story(p_route_id, coalesce(p_as_of, now()));
  end if;
  return private.fig_route_story(p_route_id, coalesce(p_as_of, now()));
end
$function$;

-- ============================================================ 7. the group Performance page's Shared pairs row
create or replace function public.shared_pairs_status(p_world_id bigint default null, p_as_of timestamp with time zone default now())
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
 set statement_timeout to '30s'
 set plan_cache_mode to 'force_custom_plan'
as $function$
declare w bigint; v_as_of timestamptz := coalesce(p_as_of, now()); v_today date; v_from date; v_limit numeric; v_days numeric; v_n int; v_pairs jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  w := private.fig_world(p_world_id);
  v_today := (v_as_of at time zone 'UTC')::date;
  select (s.value #>> '{}')::date into v_from from public.settings s
   where s.world_id = w and s.airline_id is null and s.key = 'shared_pairs_from' and jsonb_typeof(s.value) = 'string';
  v_limit := private.fig_num(w, null, 'shared_pairs_limit');
  v_days := private.fig_num(w, null, 'shared_pairs_limit_days');
  select count(*)::int into v_n from public.routes r where r.world_id = w and r.shares_route_id is not null and not r.removed;
  with sp as (select sp.* from public.shared_pairs sp where sp.world_id = w and sp.joiner_route_id is not null),
  s as (select sp.*, private.fig_pair_side(sp.owner_route_id, 7, v_as_of) as o, private.fig_pair_side(sp.joiner_route_id, 7, v_as_of) as j from sp),
  -- the pair's level each way and cabin: the owner's latest fare plan row with a level by the moment, else its launch level
  lv as (select distinct on (fp.route_id, coalesce(fp.direction, 'both'), coalesce(fp.cabin_class, 'economy'))
                fp.route_id, coalesce(fp.direction, 'both') as dir, coalesce(fp.cabin_class, 'economy') as cabin, fp.level_pct
           from public.fare_plan fp
          where fp.route_id in (select sp.owner_route_id from sp) and fp.level_pct is not null and fp.status <> 'dropped' and fp.proposed_on <= v_today
          order by fp.route_id, coalesce(fp.direction, 'both'), coalesce(fp.cabin_class, 'economy'), fp.proposed_on desc, fp.id desc)
  select coalesce(jsonb_agg(jsonb_build_object(
           'owner_airline_id', s.owner_airline_id, 'owner', s.o ->> 'airline', 'owner_code', s.o ->> 'code', 'owner_route_id', s.owner_route_id,
           'joiner_airline_id', s.joiner_airline_id, 'joiner', s.j ->> 'airline', 'joiner_code', s.j ->> 'code', 'joiner_route_id', s.joiner_route_id,
           'owner_base', s.owner_base, 'joiner_base', s.joiner_base, 'joined_on', s.joined_on,
           'owner_flights_week', s.owner_flights_week, 'joiner_flights_week', s.joiner_flights_week,
           'owner_load', round((s.o ->> 'economy')::numeric, 1), 'joiner_load', round((s.j ->> 'economy')::numeric, 1),
           'load', round(((coalesce((s.o ->> 'economy')::numeric, 0) * (s.o ->> 'with_loads')::int + coalesce((s.j ->> 'economy')::numeric, 0) * (s.j ->> 'with_loads')::int)
                          / nullif((s.o ->> 'with_loads')::int + (s.j ->> 'with_loads')::int, 0)), 1),
           'sold_out_share', round(((s.o ->> 'sold_out')::int + (s.j ->> 'sold_out')::int)::numeric / nullif((s.o ->> 'with_loads')::int + (s.j ->> 'with_loads')::int, 0), 3),
           'levels', (select coalesce(jsonb_agg(jsonb_build_object('direction', l.dir, 'cabin', l.cabin, 'level', trim_scale(l.level_pct),
                                                                    'from', case l.dir when 'back' then s.joiner_base else s.owner_base end,
                                                                    'to', case l.dir when 'back' then s.owner_base else s.joiner_base end)
                                               order by l.dir = 'back', l.cabin = 'business'), '[]'::jsonb)
                        from lv l where l.route_id = s.owner_route_id),
           'launch_pct', private.fig_num(w, s.owner_airline_id, 'fare_launch_pct'))
           order by s.joined_on, s.owner_base, s.joiner_base), '[]'::jsonb)
    into v_pairs from s;
  return jsonb_build_object(
    'world_id', w, 'as_of', private.fig_ts(v_as_of), 'joined', v_n,
    'limit', case when v_from is null or v_today - v_from < v_days
                  then jsonb_build_object('pairs', v_limit, 'from', v_from, 'until', v_from + v_days::int, 'left', greatest(v_limit - v_n, 0)) end,
    'pairs', v_pairs,
    'notes', jsonb_build_array('Every joined shared pair (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §4): both airlines'' flights a week (their legs), each airline''s and the pair''s economy load and sold-out share over the last 7 days of captured flights (private.fig_pair_side()), and the pair''s level each way and cabin: the owner''s latest fare plan row with a level (direction out from the owner''s base; launch_pct when it has none). limit: settings.shared_pairs_limit pairs until shared_pairs_from + shared_pairs_limit_days (null once it no longer applies), with how many are left.'));
end
$function$;
revoke all on function public.shared_pairs_status(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.shared_pairs_status(bigint, timestamptz) to authenticated;
comment on function public.shared_pairs_status(bigint, timestamptz) is 'The group Performance page''s Shared pairs row (manual §2, since 5 Nov; spec docs/specs/2026-11-05-shared-pairs.md §4): every joined shared pair of the world (p_world_id, the default world when null), each with its owner and joiner (airline, code, route, base), joined_on, both airlines'' flights a week from their legs, each airline''s economy load and the pair''s (load, weighted by flights with loads) and sold_out_share over the last 7 days of captured flights, and the pair''s level each way and cabin (levels: the owner''s latest fare plan row with a level by the moment, direction out from the owner''s base; launch_pct, the owner''s fare_launch_pct, when it has none). joined counts the joined pairs; limit is settings.shared_pairs_limit with from, until (shared_pairs_from + shared_pairs_limit_days) and left while it applies, null after. Staff only; runs as owner and checks the caller itself. Read with GET.';

-- ============================================================ 8. the descriptions say how a shared pair is read
do $d$
declare f text; add text;
begin
  for f, add in values
    ('public.route_profit(bigint, integer, timestamptz)', ' Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §3–§4): a route on a joined shared pair carries shared_role (owner or joiner) and pair (the other airline''s airline_id, code, airline, route_id, flights, flights_week, profit, income, profit_per_flight, economy, sold_out, with_loads, sold_out_share over the same window, from private.fig_pair_side(), and combined: the pair''s figures with both airlines'' flights); its mark (losing, add, sold_out, fix) is judged on the combined figures, the middle route still the airline''s own.'),
    ('private.fig_route_profit(bigint, integer, timestamptz)', ' Since 5 Nov a route on a joined shared pair carries shared_role and pair (the other airline''s side, private.fig_pair_side(), with the combined figures), and its mark is judged on both airlines'' flights together.'),
    ('public.growth_signals(bigint, timestamptz)', ' Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §3): a joined pair is judged on both airlines'' flights (route profit''s combined mark) and listed once, under its owner, with shared_with (the joiner''s airline_id, code, airline, route_id, flights, flights_week and flies); the joiner''s row, when the owner''s is listed, is in follows with the owner''s mark and why and follows (the owner''s airline and route).'),
    ('private.fig_growth_signals(bigint, timestamptz)', ' Since 5 Nov a joined shared pair is listed once, under its owner with shared_with; the joiner''s row goes to follows with the owner''s mark.'),
    ('public.competition(bigint, timestamptz, integer)', ' Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §3): an opening on a pair between this airline''s base and another of our airlines'' (neither excluded) carries shared (role owner or joiner, the other airline''s airline_id, code and airline, owner_route_id). A shared pair either airline flies is no opening for the other. A pair this airline would join (on its list or not; from its base, with the owner''s row''s stars, distance and market) is an opening only while the owner''s cash forecast can''t order that evening (cash_forecast(owner) next_order not now), with shared.mark "owner can''t fund tonight" and owner_next_order; otherwise it waits for the owner and openings_owner_first counts it. With p_limit 0 the owner''s cash isn''t read and those wait too. The evening proposal offers a shared pair to the owner first, then the joiner, by that mark.'),
    ('private.fig_competition(bigint, timestamptz, integer)', ' Since 5 Nov a shared pair''s opening carries shared; a pair this airline would join is an opening only while its owner can''t order that evening ("owner can''t fund tonight"), else openings_owner_first counts it.'),
    ('public.fare_results(bigint, timestamptz)', ' Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §4): on a joiner''s route the moves are the pair''s (the owner''s fare plan rows, each direction the other way round) and the before and after figures its own, marked follows (the owner''s airline_id, airline and route_id).'),
    ('private.fig_fare_results(bigint, timestamptz)', ' Since 5 Nov a joiner''s directions take the owner''s fare plan rows (the pair''s moves), marked follows.'),
    ('public.route_story(bigint, timestamptz)', ' Shared pairs (since 5 Nov, spec docs/specs/2026-11-05-shared-pairs.md §4): for a route on a joined shared pair, the owner''s and the joiner''s route give the same page (private.fig_pair_story()), from the side of the route asked for: days, weeks, days by direction, departures, rotations, types, the fare level and rivals'' ours combined; pair.airlines each airline''s own flights, revenue and profit; one timeline marked with each event''s airline; pair (role, follows, title, owner, joiner).')
  loop
    execute format('comment on function %s is %L', f, coalesce(obj_description(f::regprocedure, 'pg_proc'), '') || add);
  end loop;
end
$d$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

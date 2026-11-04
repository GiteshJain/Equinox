-- Fare results: what the fare ladder has done to each route (3 Nov 2026; spec docs/specs/2026-11-03-fare-results.md).
--
-- Why: the fare ladder moves hundreds of fares a week and nothing showed what that did. This adds one captured figure,
-- fare_results(), read by Performance's new Fare results board (each airline's page, and a line per airline on the group
-- page) and by the weekly report. Nothing new is stored: it reads fare_plan, route_days, airline_days and routes.
--
-- Adds two functions and replaces one; changes, drops and renames nothing else, so it can be applied from the chat.
--   - private.fig_fare_results(p_airline_id, p_as_of): the builder, with no check of its own.
--   - public.fare_results(p_airline_id, p_as_of default now()): staff only, as fare_plan_status() (its own 30 s limit,
--     each call planned afresh, signed in only).
--   - public.export_for_report(): a new kind, fare_results, one airline at a time with the ingest secret, so the weekly
--     report's pull.py can read the figure (the report reads through export_for_report(), never as staff). Every other
--     kind answers as before.
--
-- How it reads (spec §1):
--   - A change is a fare ladder row of the fare plan (level_pct set, not dropped, proposed by the moment) that isn't a
--     hold: up, down, jump or revert. It is seen by fare_plan_status()'s rule (the first day on or after it was proposed
--     whose average fare in its cabin and direction is the fare then times (1 + change), within 1%), read over every day
--     kept, not only the last 9: the captured flights' day fare (one per date and flight number, as fare_plan_status()),
--     else route_days' average fare in that cabin once the flights are archived. So the day a change was seen holds when
--     its flights are older than fare_plan_status()'s window (the fare ladder's under-launch jumps read it the same way).
--     A row with no direction (before 26 Oct) counts for both directions and is seen on both directions' fares.
--   - A repriced direction (out from the route's hub, back to it) has at least one seen change; first_seen is the first.
--   - Levels now: fare_ladder()'s rule, each cabin and direction's latest recorded level (its own row, or a
--     both-directions row if that is later; holds count), taking this week's row once the captures see it, as the level
--     fare_ladder() expects the game to show; launch where nothing is recorded. Worked out here from fare_plan, not by
--     calling fare_ladder() (10 to 15 s an airline), so the group page can read all six airlines.
--   - Before: route_days for that direction, the 7 UTC days before first_seen. Now: the latest 7 complete days (the
--     airline's airline_days rows marked complete by the moment) on or after first_seen, so a change seen 3 days ago is
--     judged on those 3 days, never on days before it. Flights a week now = flights × 7 ÷ the days counted.
--   - The baseline: the airline's directions with no seen change (by airports, in route_days), before the 7 days before
--     the earliest first_seen, now the same latest 7 complete days on or after it.

select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: fare results', true);

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
   where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped' and fp.route_id is not null
     and fp.proposed_on <= v_today;

  with
  -- the fare ladder's rows of the airline by the moment (holds included: they carry a level)
  ch as materialized (
    select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, fp.direction, coalesce(fp.direction, 'both') as dk,
           fp.level_pct, fp.ladder_move, fp.proposed_on, fp.fare_from, fp.change_pct
      from public.fare_plan fp
     where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped' and fp.route_id is not null
       and fp.proposed_on <= v_today),
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
      'A direction is repriced once the captures see a fare ladder change on it (up, down, jump or revert, either cabin): the first day its average fare in that cabin and direction is the fare then times the change, within 1% (fare_plan_status()''s rule, over every day kept). Before is the 7 UTC days before that first day; now is the latest 7 complete days on or after it, so a change seen a few days ago is judged on those days only. Money is AS$ a flight from the daily history (route_days), before leases. The baseline is the airline''s other directions over the same days, so fuel, fees and aircraft changes don''t pass for fare effects.'));
end
$function$

;

CREATE OR REPLACE FUNCTION public.fare_results(p_airline_id bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_fare_results(p_airline_id, coalesce(p_as_of, now()));
end
$function$

;

-- export_for_report(): the new kind fare_results (one airline, as briefing names it); every other kind as before
CREATE OR REPLACE FUNCTION public.export_for_report(p_secret text, p_kind text, p_arg text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare v_arg jsonb; v_world bigint; v_airline bigint;
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  if p_kind = 'snapshots' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', s.taken_at, 'week', s.week, 'status', s.status) order by s.id), '[]'::jsonb)
              from public.game_scans s);
  elsif p_kind = 'airlines' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', a.enterprise_id, 'name', a.name, 'flights', sc.flights, 'n_weekly', a.n_weekly)
                                      order by a.position, a.enterprise_id), '[]'::jsonb)
              from public.game_scan_airlines a
              left join public.game_scan_schedules sc on sc.scan_id = a.scan_id and sc.airline_id = a.airline_id
             where a.scan_id = p_arg::bigint);
  elsif p_kind = 'airports' then
    return (select coalesce(jsonb_agg(jsonb_build_object('code', a.airport_code, 'info', a.info, 'stations', a.stations, 'news', a.news)
                                      order by a.position, a.airport_code), '[]'::jsonb)
              from public.game_scan_airports a where a.scan_id = p_arg::bigint);
  elsif p_kind = 'planner' then
    -- the old planner's two documents went with it (the clean-up, build pull request 14)
    raise exception 'kind planner is gone since the clean-up (build pull request 14): use rules or figures' using errcode = '22023';
  elsif p_kind = 'rules' then
    -- the planning library's input, exactly as rules_input() gives it (design §7); p_arg: the world, or empty for the default
    return private.rules_input_doc(nullif(p_arg, '')::bigint);
  elsif p_kind = 'figures' then
    -- the captured figures (design §8) for every airline; p_arg: {"as_of": ..., "world": ...}, both optional
    v_arg := coalesce(nullif(btrim(coalesce(p_arg, '')), '')::jsonb, '{}'::jsonb);
    if jsonb_typeof(v_arg) <> 'object' then raise exception 'figures: p_arg is a JSON object, {"as_of": ..., "world": ...}' using errcode = '22023'; end if;
    return private.fig_export(private.fig_world((v_arg ->> 'world')::bigint), coalesce((v_arg ->> 'as_of')::timestamptz, now()));
  elsif p_kind in ('briefing', 'fare_results') then
    -- one airline: its briefing, its deliveries, plan cards, open to-dos, fare plan and loads by route (#24); or since 3 Nov
    -- its fare results (fare_results(), for the weekly report). p_arg: {"airline": its id, code or name (one of our active
    -- airlines), "as_of": ..., "world": ...}, the airline required
    v_arg := coalesce(nullif(btrim(coalesce(p_arg, '')), '')::jsonb, '{}'::jsonb);
    if jsonb_typeof(v_arg) <> 'object' or nullif(btrim(coalesce(v_arg ->> 'airline', '')), '') is null then
      raise exception '%: p_arg is a JSON object naming the airline, {"airline": ..., "as_of": ..., "world": ...}', p_kind using errcode = '22023';
    end if;
    v_world := private.fig_world((v_arg ->> 'world')::bigint);
    select al.airline_id into v_airline
      from private.fig_airlines(v_world) al join public.airlines a on a.id = al.airline_id
     where al.airline_id::text = btrim(v_arg ->> 'airline')
        or lower(btrim(v_arg ->> 'airline')) in (lower(a.iata_code), lower(a.planner_name), lower(a.public_name), lower(a.game_name))
     order by al.ord
     limit 1;
    if v_airline is null then
      raise exception '%: % isn''t one of our active airlines in world %', p_kind, v_arg ->> 'airline', v_world using errcode = '22023';
    end if;
    if p_kind = 'fare_results' then
      return private.fig_fare_results(v_airline, coalesce((v_arg ->> 'as_of')::timestamptz, now()));
    end if;
    return private.briefing_doc(v_airline, coalesce((v_arg ->> 'as_of')::timestamptz, now()));
  end if;
  raise exception 'unknown kind';
end
$function$

;

revoke all on function private.fig_fare_results(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.fare_results(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.fare_results(bigint, timestamptz) to authenticated;

comment on function private.fig_fare_results(bigint, timestamptz) is 'The captured figures (#19): builds fare_results()''s document with no check of its own (since 3 Nov; spec docs/specs/2026-11-03-fare-results.md). See fare_results().';
comment on function public.fare_results(bigint, timestamptz) is 'Fare results for one airline (since 3 Nov; spec docs/specs/2026-11-03-fare-results.md): what the fare ladder has done to each direction it repriced, for Performance''s Fare results board, the group page''s line per airline and the weekly report. A change is a fare ladder row of fare_plan (level_pct set, not dropped, proposed by the moment) that isn''t a hold (up, down, jump or revert, either cabin), seen on the first day on or after it was proposed whose average fare in its cabin and direction is the fare then times (1 + change), within 1% (fare_plan_status()''s rule, read over every day kept: the captured flights'' day fare, one per date and flight number, else route_days'' average fare in that cabin once they are archived); a row with no direction (before 26 Oct) counts for both directions, seen on both directions'' fares. routes: one row per repriced direction (a route and direction, out from its hub or back to it, with at least one seen change), largest profit_week first: route_id, hub, dest, direction, from, to, km; economy_level and business_level now (fare_ladder()''s rule: the latest recorded level for that cabin and direction, its own row or a later both-directions row, holds included, taking this week''s row once seen; launch where none; business only where recorded or flown), at_cap (either cabin at launch + fare_ladder_cap_pts) and at_floor (at or under world_rules.fare_floor_pct); moves (count of seen changes, first_seen, latest seen change with its proposed_on, seen_on, move, level and cabin, pending: the latest change not yet seen with how many, and changes, every seen change); before (route_days for that direction, origin = from: the 7 UTC days before first_seen) and now (the latest 7 complete days, airline_days.complete by the moment, on or after first_seen), each with from, to, days, flights, flights_week (now: flights × 7 ÷ days), economy_fare (weighted by economy passengers), economy_load and business_load (passengers ÷ seats), revenue_per_flight and profit_per_flight (AS$, over the days with money); change (economy_fare_pct, economy_load_pts, business_load_pts, revenue_per_flight_pct, profit_per_flight_pct, flights_week); profit_week ((profit a flight now − before) × flights a week now); flags: load_fell (economy load now under 95% while before was 95% or more), frequency_changed (flights a week now and before 2 or more apart), too_soon (fewer than 3 complete days since first_seen), at_cap; sums (the flights with money and profit behind each side, for weighting). baseline: the airline''s directions with no seen change (by airports, in route_days), before the 7 days before the earliest first_seen, now the same latest complete days on or after it: directions, before and now (flights, profit_per_flight, economy_load) and profit_per_flight_pct; null with nothing repriced. totals: directions, up and down (by the latest seen move), at_cap, load_fell, frequency_changed, too_soon, before and now profit_per_flight over every repriced direction weighted by flights, profit_per_flight_pct, baseline_profit_per_flight_pct and profit_week (the rows'' added up). days: the complete days used for now; settings: launch_pct, cap_pct, floor_pct and the flags'' thresholds. Nothing is stored. Staff only; runs as owner and checks the caller itself.';

-- export_for_report() keeps every word of its description (older tests read it); the new kind is added at the end, once
do $describe$
declare d text := obj_description('public.export_for_report(text, text, text)'::regprocedure, 'pg_proc');
begin
  if position('fare-results.md' in coalesce(d, '')) = 0 then
    execute format('comment on function public.export_for_report(text, text, text) is %L', coalesce(d, '')
      || ' Since 3 Nov (spec docs/specs/2026-11-03-fare-results.md §3) kind fare_results, p_arg {"airline": its id, code or name, "as_of", "world"} as briefing, the airline required: that airline''s fare_results() (private.fig_fare_results()), for the weekly report''s Fare results section; read only.');
  end if;
end
$describe$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

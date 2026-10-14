-- The clean-up, part 1 of 2: what only adds or replaces (decision #18, build pull request 14). Spec:
-- docs/specs/2026-10-14-clean-up.md. CLAUDE APPLIES THIS FILE FROM THE CHAT after "merge", once Cloudflare has published
-- the merged planner (which no longer reads what this clears). Gitesh then runs 20261014200100_clean_up_removals.sql
-- in Supabase's SQL editor. Takes nothing away and changes no function's arguments:
--   1. The captured figures use an airport's UTC offset in the world, with its correction (world_airports.
--      utc_offset_override; design §16, found by #29), as the schedules do: private.fig_events() (each payment's moment,
--      from the airline's home airport) and private.fig_route_profit() (each flight's departure, from its origin) take
--      private.airport_offset_min() instead of private.fig_eq_off(), which the removals drop. No airport has a correction
--      today, so no figure moves (database/tests/clean_up_test.sql compares the export's figures before and after).
--   2. public.loads_by_day(): the loads days the planner's "Loads by hand" reads (until now through planner_loads_get()),
--      by the captured figures' own rules (private.fig_load_values() and fig_load_days()), with the typed rows behind
--      each day, which its saves through planner_save() change.
--   3. Off the adapter, with the same answers otherwise: site_public() (the aircraft flying are those in service, status
--      active, in the order they were added, as the planner's Tails lists them; updated_at from the change log, as
--      planner_state_version() gave it), site_investor() (cash and next-7-day costs worked out here, as
--      planner_state_get() did), export_for_report() (kind planner refused, saying why), private.capture_store() (no
--      loads step: it did nothing since the switch-over) and planner_data_set() (the route research only, into its
--      tables; nothing is kept in planner_data).
--   4. The old planner's leftovers in the data, which only the adapter read (the planner and the website no longer do):
--      the places in the old lists and the old delivery items (aircraft.extra tails_index, deliveries_index, delivery),
--      the hidden copy of plan-card legs and anything else in plan_cards.extra, and todos.extra and fare_plan.extra. An
--      aircraft with a delivery the old deliveries list didn't hold loses it, as the old planner's removal did, so the
--      deliveries board stays the same (none on last night's copy: database/tests/clean_up_test.sql). The change log
--      keeps every value cleared (actor migration), so private.restore_row() can bring one back. aircraft.extra keeps
--      its tail notes and rotations.extra the SLF figures: the planner reads both.
--   5. The descriptions that named what goes.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261014200000_clean_up', true);

-- ============================================================ 1. the captured figures, with each airport's UTC correction
CREATE OR REPLACE FUNCTION private.fig_events(p_world_id bigint, p_as_of timestamp with time zone, p_airline_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(airline_id bigint, at timestamp with time zone, amount numeric, descr text, event_date date, event_time text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with t as (select (p_as_of at time zone 'UTC')::date as today),
  f as (select coalesce(min(b.captured_on), (select today from t) - 7) as first_day
          from public.game_balance b
         where b.world_id = p_world_id and b.account like '2800%' and b.captured_at <= p_as_of
           and b.captured_on >= (select today from t) - 7)
  select e.airline_id, private.local_to_utc(e.event_date, e.event_time, coalesce(private.airport_offset_min(p_world_id, h.code), 0)), e.debit / 1000000,
         e.descr, e.event_date, e.event_time
    from public.game_events e
    cross join f
    join public.airlines a on a.id = e.airline_id
    left join public.airline_bases mb on mb.airline_id = e.airline_id and mb.is_main
    cross join lateral (select coalesce(mb.airport_code, a.home_airport_code) as code) h   -- fig_home()
   where e.world_id = p_world_id and (p_airline_id is null or e.airline_id = p_airline_id) and e.debit > 0 and e.captured_at <= p_as_of
     and e.event_date >= f.first_day and e.event_date <= (select today from t) + 16
$function$;

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
  v_losing numeric; v_sold_share numeric; v_sold_min numeric; v_fix_min numeric; v_fix_eco numeric; v_fix_routes numeric; v_fix_margin numeric;
begin
  if p_days is null or p_days < 1 then raise exception 'p_days must be 1 or more' using errcode = '22023'; end if;
  v_losing := private.fig_num(w, p_airline_id, 'growth_losing_min_departures');
  v_sold_share := private.fig_num(w, p_airline_id, 'growth_sold_out_share');
  v_sold_min := private.fig_num(w, p_airline_id, 'growth_sold_out_min_departures');
  v_fix_min := private.fig_num(w, p_airline_id, 'growth_fix_min_departures');
  v_fix_eco := private.fig_num(w, p_airline_id, 'growth_fix_economy_pct');
  v_fix_routes := private.fig_num(w, p_airline_id, 'growth_fix_min_routes');
  v_fix_margin := private.fig_num(w, p_airline_id, 'growth_fix_margin');
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
    g as (select rk.hub, rk.dest, rk.route_id, count(*)::int as n, sum(fl.profit) / 1000000 as profit,
                 sum(fl.pax_income + fl.cargo_income) / 1000000 as income,
                 avg(fl.eco) as eco_a, avg(fl.bus) as bus_a, avg(fl.cargo) as cargo_a, avg(fl.eco_fare) as fare_a,
                 count(fl.eco)::int as eco_n, (count(*) filter (where fl.eco >= 100))::int as sold, min(fl.i) as first_i
            from fl join rk on rk.o = fl.o and rk.d = fl.d
           group by rk.hub, rk.dest, rk.route_id),
    r as (select g.*, g.profit / g.n as ppf, case when g.income > 0 then g.profit / g.income end as margin,
                 coalesce(wk.wk, 0) as wk, (g.profit / g.n) * coalesce(wk.wk, 0) as pwk,
                 case when g.eco_n > 0 then g.sold::numeric / g.eco_n end as sold_share
            from g left join wk on wk.route_id = g.route_id),
    pp as (select array_agg(r.ppf order by r.ppf) as a from r),
    q as (select pp.a[floor(cardinality(pp.a) / 2.0)::int + 1] as med, pp.a[floor(cardinality(pp.a) * 0.25)::int + 1] as q25,
                 coalesce(cardinality(pp.a), 0) as len from pp),
    mk as (select r.*, case when r.ppf < 0 and r.n >= v_losing then 'losing'
                            when r.sold_share is not null and r.sold_share >= v_sold_share and r.n >= v_sold_min
                              then case when r.ppf >= q.med then 'add' else 'raise' end
                            when r.n >= v_fix_min and r.eco_a is not null and r.eco_a < v_fix_eco then 'fix'
                            when r.n >= v_fix_min and q.len >= v_fix_routes and r.ppf <= q.q25 and r.margin is not null and r.margin < v_fix_margin then 'fix-margin'
                            else 'hold' end as k, q.med
             from r cross join q),
    routes as (select coalesce(jsonb_agg(jsonb_build_object(
                 'route_id', mk.route_id, 'hub', mk.hub, 'dest', mk.dest, 'flights', mk.n, 'profit', mk.profit, 'income', mk.income,
                 'margin', mk.margin, 'profit_per_flight', mk.ppf, 'flights_week', mk.wk, 'profit_week', mk.pwk,
                 'economy', mk.eco_a, 'business', mk.bus_a, 'cargo', mk.cargo_a, 'economy_fare', mk.fare_a,
                 'sold_out', mk.sold, 'with_loads', mk.eco_n, 'sold_out_share', mk.sold_share,
                 'mark', case when mk.k = 'fix-margin' then 'fix' else mk.k end,
                 'why', case mk.k when 'losing' then 'its average flight loses money'
                                  when 'add' then format('sold out on %s of %s departures, profit a flight above the airline''s middle route', mk.sold, mk.eco_n)
                                  when 'raise' then format('sold out on %s of %s departures, profit a flight below the airline''s middle route', mk.sold, mk.eco_n)
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

-- ============================================================ 2. the loads days, for the planner's "Loads by hand"
create or replace function public.loads_by_day(p_world_id bigint, p_from date, p_to date)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare w bigint;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the planner' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then
    raise exception 'loads_by_day: from and to are dates, to on or after from, at most 62 days apart' using errcode = '22023';
  end if;
  w := private.fig_world(p_world_id);
  return (
    with ours as (
      select a.id, a.planner_name from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
       where a.world_id = w and g.kind = 'ours'),
    vals as (select v.* from private.fig_load_values(w, now(), p_from, p_to) v),
    days as (select d.* from private.fig_load_days(w, now(), p_from, p_to) d)
    select coalesce(jsonb_object_agg(d.day::text,
             jsonb_build_object(
               -- the day as the old planner's loads document held it: done (the one rule, design §8, unless a flag typed
               -- after the day's last capture says otherwise) and each flight's economy load (captured or typed, the latest)
               'done', coalesce(d.done, false),
               'f', coalesce((select jsonb_object_agg(o.planner_name || '|' || v.flight_no, v.v)
                                from vals v join ours o on o.id = v.airline_id
                               where v.day = d.day and v.v is not null and o.planner_name is not null), '{}'::jsonb),
               -- the typed rows behind it, with the updated_at a save changes them from
               'entries', coalesce((select jsonb_agg(jsonb_build_object('airline_id', e.airline_id, 'flight_no', e.flight_no,
                                                                        'eco_pct', trim_scale(e.eco_pct), 'updated_at', e.updated_at)
                                                     order by e.airline_id, e.flight_no)
                                      from public.load_entries e join ours o on o.id = e.airline_id
                                     where e.world_id = w and e.game_date = d.day), '[]'::jsonb),
               'flags', (select jsonb_build_object('done', ld.done, 'saved_at_ms', ld.saved_at_ms, 'updated_at', ld.updated_at)
                           from public.load_days ld where ld.world_id = w and ld.game_date = d.day))
             || case when d.captured then jsonb_build_object('source', 'capture') else '{}'::jsonb end
             || coalesce((select jsonb_build_object('savedAt', ld.saved_at_ms) from public.load_days ld
                           where ld.world_id = w and ld.game_date = d.day and ld.saved_at_ms is not null), '{}'::jsonb)),
             '{}'::jsonb)
      from days d);
end
$function$;

revoke all on function public.loads_by_day(bigint, date, date) from public, anon, authenticated, service_role;
grant execute on function public.loads_by_day(bigint, date, date) to authenticated;

-- ============================================================ 3. off the adapter: the website, the investors, the exports, the capture
CREATE OR REPLACE FUNCTION public.site_public()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with w as (select x.id from public.worlds x where x.is_default),
  -- each frequency with its local times (design §4), in its order
  freqs as (
    select r.id, r.airline_id, ro.hub_code,
           jsonb_build_object(
             'routeKey', al.planner_name || '|' || ro.hub_code || '|' || ro.dest_code,
             'days', (select string_agg(d::text, '' order by d) from unnest(x.days_local) as d),
             'tail', coalesce(ac.registration, ''),
             'noOut', coalesce(l1.flight_no::text, ''),
             'noBack', coalesce(l2.flight_no::text, ''),
             'depHub', coalesce(to_char(make_time(x.dep_hub / 60, x.dep_hub % 60, 0), 'HH24:MI'), ''),
             'arrDest', coalesce(to_char(make_time(x.arr_dest / 60, x.arr_dest % 60, 0), 'HH24:MI'), ''),
             'depDest', coalesce(to_char(make_time(x.dep_dest / 60, x.dep_dest % 60, 0), 'HH24:MI'), ''),
             'arrHub', coalesce(to_char(make_time(x.arr_hub / 60, x.arr_hub % 60, 0), 'HH24:MI'), ''),
             'launched', r.launched_on::text)
           || r.extra as j
      from w
      join public.rotations r on r.world_id = w.id
      join public.routes ro on ro.id = r.route_id
      join public.airlines al on al.id = r.airline_id
      left join public.flight_legs l1 on l1.rotation_id = r.id and l1.leg_no = 1
      left join public.flight_legs l2 on l2.rotation_id = r.id and l2.leg_no = 2
      left join public.aircraft ac on ac.id = coalesce(l1.aircraft_id, l2.aircraft_id)
      left join public.airports ah on ah.code = ro.hub_code
      left join public.world_airports wh on wh.world_id = w.id and wh.airport_code = ro.hub_code
      left join public.airports ad on ad.code = ro.dest_code
      left join public.world_airports wd on wd.world_id = w.id and wd.airport_code = ro.dest_code
      -- each end's offset in minutes; an airport whose offset isn't known counts as UTC, as the planner counts it
      cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                                 round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
      cross join lateral (
        select (((l1.dep_utc_min + o.oh) % 1440) + 1440) % 1440 as dep_hub,
               (((l1.dep_utc_min + l1.block_min + o.od) % 1440) + 1440) % 1440 as arr_dest,
               (((l2.dep_utc_min + o.od) % 1440) + 1440) % 1440 as dep_dest,
               (((l2.dep_utc_min + l2.block_min + o.oh) % 1440) + 1440) % 1440 as arr_hub,
               -- the old planner keeps the outbound's local weekdays at the hub
               dl.days_local
          from (select case when l1.dep_utc_min is null then l1.days_utc
                            else array(select distinct ((((d - 1 + floor((l1.dep_utc_min + o.oh) / 1440.0)::int) % 7) + 7) % 7 + 1)::smallint
                                         from unnest(l1.days_utc) as d order by 1) end as days_local) dl) x),
  -- each aircraft flying (status active), in the order it was added, as the planner's Tails lists it
  tails as (
    select a.id,
           jsonb_strip_nulls(jsonb_build_object('id', a.registration, 'airline', al.planner_name, 'type', coalesce(t.name, '')))
           || coalesce(a.extra -> 'tail', '{}'::jsonb) as j
      from w
      join public.aircraft a on a.world_id = w.id and a.status = 'active'
      join public.airlines al on al.id = a.airline_id
      left join public.aircraft_types t on t.id = a.aircraft_type_id)
  select jsonb_build_object(
    -- when the planner's data last changed: its latest logged change in the world, or to airports and countries
    -- (which carry no world), to the millisecond
    'updated_at', (select to_timestamp(floor(extract(epoch from greatest(
                              (select max(c.changed_at) from public.change_log c where c.world_id = w.id),
                              (select max(c.changed_at) from public.change_log c where c.world_id is null))) * 1000) / 1000.0)
                     from w),
    -- our airlines in the world the website shows, in display order: what the website used to keep in its code
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
                   'key', a.planner_name, 'name', a.public_name, 'code', a.iata_code, 'color', a.livery_color,
                   'slug', a.slug, 'region', a.region_text, 'role', a.role_text, 'blurb', a.blurb, 'photo', a.photo_city,
                   'position', a.position) order by a.position nulls last, a.id), '[]'::jsonb)
                   from w
                   join public.airlines a on a.world_id = w.id
                   join public.groups g on g.id = a.group_id and g.world_id = a.world_id
                  where g.kind = 'ours' and a.active and a.planner_name is not null),
    -- hubs and focus cities an airline of theirs flies from: code, airline and role only (no banks, no connection times)
    'hubs', (select coalesce(jsonb_agg(jsonb_build_object('code', b.airport_code, 'airline', al.planner_name, 'role', b.role)
                                       order by b.position, b.id), '[]'::jsonb)
               from w
               join public.airline_bases b on b.world_id = w.id
               join public.airlines al on al.id = b.airline_id
              where exists (select 1 from freqs f where f.airline_id = b.airline_id and f.hub_code = b.airport_code)),
    'tails', (select coalesce(jsonb_agg(jsonb_build_object('id', t.j ->> 'id', 'airline', t.j ->> 'airline', 'type', t.j ->> 'type')
                                        order by t.id), '[]'::jsonb) from tails t),
    'freqs', (select coalesce(jsonb_agg(jsonb_build_object('r', f.j ->> 'routeKey', 't', f.j ->> 'tail', 'a', f.j ->> 'depHub',
                                                           'b', f.j ->> 'arrDest', 'c', f.j ->> 'depDest', 'd', f.j ->> 'arrHub',
                                                           'days', f.j ->> 'days', 'o', f.j ->> 'noOut', 'k', f.j ->> 'noBack',
                                                           'l', f.j ->> 'launched') order by f.id), '[]'::jsonb) from freqs f),
    -- signed interline agreements, in the order the old document's keys came in (jsonb: shorter keys first, then bytes)
    'interline', (select coalesce(jsonb_agg(jsonb_build_object('pair', x.pair, 'partner', x.partner, 'date', x.date)
                                            order by octet_length(x.pair), x.pair collate "C"), '[]'::jsonb)
                    from (select al.planner_name || '|' || i.country_code as pair, i.partner, i.decided_on::text as date
                            from w
                            join public.interline_agreements i on i.world_id = w.id
                            join public.airlines al on al.id = i.airline_id
                           where i.status = 'signed') x),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('slug', p.slug, 'at', p.published_at, 'title', p.title, 'summary', p.summary,
                                                           'body', p.body, 'tag', p.tag, 'airline', p.airline, 'image', p.image,
                                                           'credit', p.image_credit) order by p.published_at desc), '[]'::jsonb)
                from public.site_posts p),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period', r.period, 'title', r.title,
                                                             'summary', case when r.kind = 'newsletter' then r.summary end,
                                                             'at', r.published_at, 'status', r.status, 'has_pdf', r.pdf_b64 is not null)
                                          order by coalesce(r.published_at, now() + interval '1 year') desc), '[]'::jsonb)
                  from public.site_reports r),
    -- site_content's keys (photos, logos ...; markets is the investors'), with mct from world_airports, and the longest
    -- wait for a connection from settings (connection_max_wait_h, hours, manual §4), for the trip search (#19)
    'content', coalesce((select jsonb_object_agg(c.key, c.value) from public.site_content c where c.key not in ('markets', 'mct')), '{}'::jsonb)
               || coalesce((select jsonb_build_object('mct', jsonb_object_agg(wa.airport_code, wa.mct_min))
                              from w join public.world_airports wa on wa.world_id = w.id
                             where wa.mct_min is not null
                            having count(*) > 0), '{}'::jsonb)
               || coalesce((select jsonb_build_object('connection_max_wait_h', (s.value #>> '{}')::numeric)
                              from w join public.settings s on s.world_id = w.id
                             where s.airline_id is null and s.key = 'connection_max_wait_h'
                               and (s.value #>> '{}') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$'), '{}'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.site_investor(p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h text; w bigint; v_cash jsonb; v_fixed jsonb;
begin
  select r.pass_hash into h from public.report_access r limit 1;
  if h is null or p_password is null or extensions.crypt(p_password, h) <> h then return jsonb_build_object('ok', false); end if;
  select x.id into w from public.worlds x where x.is_default;
  -- cash and next-7-day costs by date and airline, in millions (design §8): the capture's figure unless a cash_entries row
  -- says otherwise, rounded as the planner rounds (to 0.01M); next-7-day costs only when above zero. As the old planner's
  -- document had them (until the clean-up, build pull request 14, through planner_state_get())
  with pairs as (
    select coalesce(e.airline_id, cc.airline_id) as airline_id, coalesce(e.day, cc.day) as day,
           coalesce(e.cash / 1000000, floor(cc.cash / 10000 + 0.5) / 100) as cash_m,
           coalesce(e.fixed_next7, cc.fixed_next7) as fixed_raw,
           e.fixed_next7 is not null as fixed_typed
      from (select * from public.cash_entries x where x.world_id = w) e
      full join (select * from public.capture_cash x where x.world_id = w) cc on cc.airline_id = e.airline_id and cc.day = e.day),
  named as (
    select al.planner_name, p.day::text as day, trim_scale(p.cash_m) as cash_m,
           case when p.fixed_raw > 0 then trim_scale(case when p.fixed_typed then p.fixed_raw / 1000000
                                                          else floor(p.fixed_raw / 10000 + 0.5) / 100 end) end as fixed_m
      from pairs p join public.airlines al on al.id = p.airline_id)
  select (select coalesce(jsonb_object_agg(x.day, x.v), '{}'::jsonb)
            from (select n.day, jsonb_object_agg(n.planner_name, n.cash_m) as v from named n where n.cash_m is not null group by n.day) x),
         (select coalesce(jsonb_object_agg(x.day, x.v), '{}'::jsonb)
            from (select n.day, jsonb_object_agg(n.planner_name, n.fixed_m) as v from named n where n.fixed_m is not null group by n.day) x)
    into v_cash, v_fixed;
  return jsonb_build_object('ok', true, 'cash', v_cash, 'fixed7', v_fixed,
    -- money spent, in the planner's order and millions; orders were logged without a kind
    'capex', (select coalesce(jsonb_agg(jsonb_build_object('date', s.spent_on::text, 'airline', al.planner_name,
                                                           'm', trim_scale(s.amount / 1000000),
                                                           'kind', case when s.kind <> 'order' then s.kind end) order by s.id), '[]'::jsonb)
                from public.spending_log s join public.airlines al on al.id = s.airline_id
               where s.world_id = w),
    'markets', (select c.value from public.site_content c where c.key = 'markets'),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'period', r.period, 'title', r.title,
                                                             'summary', r.summary, 'at', r.published_at, 'status', r.status,
                                                             'has_pdf', r.pdf_b64 is not null)
                                          order by coalesce(r.published_at, now() + interval '1 year') desc), '[]'::jsonb)
                  from public.site_reports r where r.kind <> 'newsletter'));
end
$function$;

CREATE OR REPLACE FUNCTION public.export_for_report(p_secret text, p_kind text, p_arg text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_arg jsonb;
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
  end if;
  raise exception 'unknown kind';
end
$function$;

CREATE OR REPLACE FUNCTION private.capture_store(p_world_id bigint, p_airline text, p_kind text, p_page text, p_rows jsonb, p_at timestamp with time zone, p_loads_step boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_al bigint; v_name text; v_rid bigint; v_res jsonb; v_day date; v_complete boolean; v_snap jsonb;
  t0 timestamptz;
begin
  v_al := private.capture_find_airline(p_world_id, p_airline);
  if v_al is null then
    return jsonb_build_object('ok', false, 'error', 'not an airline of this capture key''s world: ' || coalesce(p_airline, '(none)'));
  end if;
  select coalesce(a.planner_name, a.public_name, a.game_name, a.game_id::text) into v_name from public.airlines a where a.id = v_al;
  insert into public.game_capture_raw (world_id, airline_id, airline, kind, page_url, rows, captured_at)
  values (p_world_id, v_al, v_name, p_kind, p_page, coalesce(p_rows, '[]'::jsonb), p_at)
  returning id into v_rid;
  if p_kind = 'html' then return jsonb_build_object('ok', true, 'kind', 'html', 'rows', 1, 'airline', v_name); end if;   -- page inspection: stored only
  begin
    v_res := private.capture_page(v_rid) || jsonb_build_object('airline', v_name);
  exception when others then
    v_res := jsonb_build_object('ok', false, 'airline', v_name, 'error', 'parse: ' || sqlerrm, 'raw_id', v_rid);   -- the raw rows stay for inspection
  end;
  v_day := private.capture_day(p_world_id, p_at);
  v_complete := private.capture_day_complete(p_world_id, v_day);
  -- the daily snapshot, when this page completes the day's capture (design §7)
  if v_complete and p_kind in ('statement', 'events', 'pnl', 'balance', 'loads') and private.snapshot_due(p_world_id, v_day, p_at) then
    t0 := clock_timestamp();
    begin
      v_snap := private.take_snapshot(p_world_id, v_day, p_at, 'capture');
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'ok', v_day,
              format('capture complete: %s airline(s), %s route day(s)', v_snap ->> 'airlines', v_snap ->> 'route_days'), v_snap);
    exception when others then
      v_snap := jsonb_build_object('ok', false, 'error', sqlerrm);
      insert into public.job_runs (job, world_id, started_at, finished_at, status, for_day, note, details)
      values ('snapshot', p_world_id, t0, clock_timestamp(), 'failed', v_day, 'snapshot: ' || sqlerrm,
              jsonb_build_object('at', p_at, 'source', 'capture'));
    end;
  end if;
  return v_res || jsonb_build_object('capture_day', v_day, 'day_complete', v_complete)
         || case when v_snap is null then '{}'::jsonb else jsonb_build_object('snapshot', v_snap) end;
end
$function$;

create or replace function public.planner_data_set(p_secret text, p_key text, p_value jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w bigint; v_tables jsonb;
  v_actor text := current_setting('equinox.actor', true); v_detail text := current_setting('equinox.actor_detail', true);
begin
  if not exists (select 1 from public.ingest_secret s where s.secret = p_secret) then raise exception 'not allowed'; end if;
  -- only the route research is kept, in its own tables: the old planner's planner_data went with it (the clean-up)
  if p_key is distinct from 'DATA' then
    raise exception 'planner_data_set: only key DATA (the route research) is kept since the clean-up (build pull request 14)' using errcode = '22023';
  end if;
  -- the change log names the script, unless the caller named itself (design §6)
  perform set_config('equinox.actor', coalesce(nullif(v_actor, ''), 'script'), true),
          set_config('equinox.actor_detail', coalesce(nullif(v_detail, ''), 'planner_data_set'), true);
  select x.id into w from public.worlds x where x.is_default;
  v_tables := private.research_apply(w, p_value);
  perform set_config('equinox.actor', coalesce(v_actor, ''), true), set_config('equinox.actor_detail', coalesce(v_detail, ''), true);
  return jsonb_build_object('ok', true, 'bytes', length(p_value::text))
         || case when v_tables is null then '{}'::jsonb else jsonb_build_object('tables', v_tables) end;
end
$function$;

-- ============================================================ 4. the old planner's leftovers in the data
-- The deliveries board is every aircraft with a delivery that isn't retired (until now, those the old list held:
-- aircraft.extra.deliveries_index). One with a delivery the old list didn't hold loses its order details, as the old
-- planner's removal of a delivery did, so the board shows what it showed.
update public.aircraft a
   set ordered_on = null, delivery_at = null, order_base_code = null, order_config_id = null, order_note = null
 where a.delivery_at is not null and a.status <> 'retired' and not a.extra ? 'deliveries_index';

-- the old lists' places and the old delivery items; the tail's notes (extra.tail) stay, as Tails shows them
update public.aircraft a set extra = a.extra - 'tails_index' - 'deliveries_index' - 'delivery'
 where a.extra ?| array['tails_index', 'deliveries_index', 'delivery'];

-- the hidden copy of each plan card's legs (its plan_card_legs rows are the legs) and any other old field; the old
-- planner's fields of to-dos and fare plans
update public.plan_cards c set extra = '{}'::jsonb where c.extra <> '{}'::jsonb;
update public.todos t set extra = '{}'::jsonb where t.extra <> '{}'::jsonb;
update public.fare_plan f set extra = '{}'::jsonb where f.extra <> '{}'::jsonb;

-- ============================================================ 5. descriptions
comment on function private.fig_events(bigint, timestamptz, bigint) is 'The captured figures (#19): the events page''s payments as the old planner loads them (CAP.events): debits from the first balance date of the 7 days to p_as_of to 16 days ahead, each at its UTC moment from the airline''s home airport''s offset in the world (private.airport_offset_min(), with the world''s correction, since the clean-up; the old planner''s eqOff had none), in millions. p_airline_id: one airline''s, or null for all.';
comment on function private.fig_route_profit(bigint, integer, timestamptz) is 'The captured figures (#19): builds routeProfit()''s document (routes, aircraft, fare changes, the average flight) with no check of its own; each flight''s departure in UTC from its origin''s offset in the world, with its correction (since the clean-up). See route_profit(), aircraft_profit() and fare_changes().';
comment on function public.loads_by_day(bigint, date, date) is 'The loads days from p_from to p_to (at most 62 days apart) in a world (the default when null), as the planner''s Loads by hand reads them (#18 build pull request 14; until then through planner_loads_get()): {date: {done, f: {"Airline|flight": economy %}, source: capture when a capture reached the day, savedAt: when it was last saved by hand (ms), entries: the typed load_entries rows with their updated_at, flags: the load_days row or null}}. The loads and the complete mark by the captured figures'' rules as of now (private.fig_load_values(), private.fig_load_days()): a typed figure wins where it is newer than the day''s capture. A day with nothing captured or typed isn''t there. Staff only; runs as owner.';
comment on function public.site_public() is 'Everything the public website shows, in one call: hubs and focus cities an airline flies from, aircraft flying (status active, in the order they were added, as the planner''s Tails lists them, since the clean-up), the week''s frequencies (local times), signed interlines, posts, the reports list, site_content (photos, logos), the minimum connection times (content.mct) and the longest wait for a connection (content.connection_max_wait_h, hours, from settings; the trip search''s window with the planning library, #19), built from the tables (#13, pull request 8), plus our airlines (names, codes, colours, the website''s text, display order) from airlines. updated_at: when the planner''s data last changed (the latest change in the change log for the world, or to airports and countries). No bank or transfer times, cabin layouts or aircraft on order (6 Oct). Anyone may call it; runs as owner.';
comment on function public.site_investor(text) is 'The investor page''s data, when the password matches report_access: cash and next-7-day costs by date and airline in millions (the capture''s figure unless typed by hand in cash_entries, as the planner rounds them), money spent from spending_log, markets from site_content, and the investor reports list. Runs as owner.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report, gander monthly and the planning library: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); and the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19). Kind planner (the old planner''s documents) is refused since the clean-up (build pull request 14). Needs the ingest secret.';
comment on function public.planner_data_set(text, text, jsonb) is 'Writes the route research (key DATA: routes, coords, utc, countries) to the countries, airports and routes tables, only the rows that change (private.research_apply(); change log actor script unless the caller named itself), and answers what changed under tables. Any other key is refused: the old planner''s planner_data went with it at the clean-up (build pull request 14). Needs the ingest secret.';
comment on function private.capture_store(bigint, text, text, text, jsonb, timestamptz, boolean) is 'Stores one page for an airline of the given world and parses it, at the given capture time, and says whether that capture day is now complete. When the page completes the world''s capture for the day (private.snapshot_due), takes the daily snapshot (private.take_snapshot, one job_runs row, ok or failed; a failure never loses the page) and answers with it under snapshot. Refuses a page for an airline outside the world. capture_ingest() calls it with now(); the tests replay saved pages with their own times. p_loads_step is no longer used: the old planner''s loads step went with the clean-up (build pull request 14).';
comment on function private.research_apply(bigint, jsonb) is 'planner_data_set()''s step for the route research (key DATA: routes, coords, utc, countries): writes countries, airports and a world''s research routes, only the rows that change, by the loader''s rules. Added routes and the planner''s overrides are never touched; a research route no longer listed goes unless something points at it or it carries an edit. A new UTC offset for an airport that flights or plan-card legs use (with no world correction) is held back and named, since their UTC times were worked out with the old one (design §4). A part missing from the document leaves its rows alone. Returns how many rows each part changed.';
comment on function private.json_int(jsonb) is 'A whole number from JSON (a flight number, seats, minutes); null when it isn''t one. Used by research_apply() and world_mct_set().';
comment on function private.json_num(jsonb) is 'A number from JSON: a JSON number, or text that is plainly a number; null for anything else. Used by research_apply() and world_mct_set().';
comment on function private.fig_freqs(bigint, bigint) is 'The captured figures (#19): each rotation as the old planner read it (planner_state_get(), until the clean-up): its airline, route (live when the route is on the airline''s list), the outbound''s local weekdays at the hub and the return''s at the destination, flights a week (flightsPerDay: 2 with a return number, else 1, × the outbound''s days; 7 days with no outbound), its aircraft, launch date and flight numbers. p_airline_id: one airline''s, or null for all.';
comment on function private.fig_load_days(bigint, timestamptz, date, date) is 'The captured figures (#19): each loads day''s flags for local dates in the range as of p_as_of, as the old planner''s loads document had them: done (the one rule, unless a flag typed after the day''s last capture says otherwise) and captured (the day''s source is the capture). loads_by_day() reads it.';
comment on function private.fig_load_values(bigint, timestamptz, date, date) is 'The captured figures (#19): the economy loads per flight for local dates in the range, using only the captures and typed entries made by p_as_of (a typed figure wins where it is newer than the day''s capture), as the old planner''s loads document had them. loads_by_day() reads it.';
comment on function public.site_admin(text, text, jsonb) is 'Publishes website content: newsroom posts, reports and site content. Content mct (minimum connection times, {airport code: minutes}) also sets world_airports, which site_public() reads (private.world_mct_set(); change log actor script unless the caller named itself); site_content.mct is kept too (the planner''s Reference shows it). Needs the ingest secret.';

comment on table public.site_content is 'Website content kept as data, one row per key: media (destination photos and airline logos), markets, and mct (minimum connection times, also used by the schedule optimiser; since #13''s pull request 8 site_admin() writes them to world_airports too, and site_public() reads them from there; this copy is kept for the planner''s Reference, which shows it). Written by site_admin() and the planner''s Photos screen. Read by site_public() and site_investor().';

comment on table public.aircraft is 'Each aircraft from order to delivery to service to retirement, one row each. Replaced the old planner''s tails and deliveries: status active is a tail (on the planner''s Tails), and one with a delivery that isn''t retired is on the deliveries board.';
comment on column public.aircraft.status is 'on_order, delivered (arrived, not yet filed into the planner), active (in service: a tail) or retired';
comment on column public.aircraft.extra is 'What the old planner kept on a tail that the table has no column for, under tail (its notes, which Tails shows). The old lists'' places and delivery items went with the clean-up (build pull request 14). Expected otherwise empty';
comment on column public.plan_cards.extra is 'Fields the table doesn''t know; the old planner''s (the hidden copy of the legs among them) were cleared at the clean-up (build pull request 14). Expected empty';
comment on column public.todos.extra is 'Fields the table doesn''t know; the old planner''s were cleared at the clean-up (build pull request 14). Expected empty';
comment on column public.fare_plan.extra is 'Fields the table doesn''t know; the old planner''s were cleared at the clean-up (build pull request 14). Expected empty';
comment on column public.rotations.extra is 'Fields the table doesn''t know: the old planner''s SLF figures (slfOut, slfBack), which Routes edits and the flights export lists. Expected otherwise empty';
comment on column public.todos.legacy_key is 'The old planner''s to-do id, the to-do''s key on Home and in a dismissal (todo|<id>); new to-dos get one too';
comment on column public.rotations.legacy_key is 'The old planner''s frequency id, e.g. z5qbaeg, by which Routes names a frequency; new ones get one too';
comment on column public.fare_plan.legacy_key is 'The old planner''s fare-plan id; new rows get one too';
comment on column public.job_runs.job is 'backup, snapshot, snapshot_fallback, cleanup or archive; adapter_mirror and adapter_check are the old adapter''s runs, until the clean-up (build pull request 14)';
comment on table public.load_entries is 'Economy loads typed by hand, per flight and game date (the planner''s Loads by hand, through planner_save()). Replaced the typed part of the old planner_loads.';
comment on table public.load_days is 'A load day''s flags typed in the planner (whether the day is complete). Replaced the day flags in the old planner_loads.';
comment on table public.settings is 'Our own planning choices as data (decision #14): the manual''s rule numbers, thresholds and display choices for a world, with per-airline overrides.';
comment on table public.worlds is 'One row per AirlineSim world we play in (decision #14). Gander is the only one; is_default marks the world the planner and the website show. Every planner table carries its world_id.';
comment on column public.worlds.is_default is 'The world the planner and the website show; at most one';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

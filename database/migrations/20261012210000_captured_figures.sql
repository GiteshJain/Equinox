-- The captured figures in the database (decision #19, build pull request 3, "the captured figures"). Design:
-- docs/design/2026-10-12-planner-app.md §8. Spec: docs/specs/2026-10-12-captured-figures.md.
--
-- Adds nine staff functions and their internal builders, and changes one; removes nothing, writes no rows:
--   public.cash_forecast(p_airline_id, p_orders, p_as_of)   "Cash, next 14 days" and when an airline can order (manual §3)
--   public.airline_cards(p_world_id, p_as_of)               Review's card for each airline, and the group today
--   public.airline_profit(p_airline_id, p_as_of)            profit for each day between captures
--   public.route_profit(p_airline_id, p_days, p_as_of)      each route over 1, 3 or 7 days, with its mark
--   public.aircraft_profit(p_airline_id, p_days, p_as_of)   each aircraft's flight profit a day, less its lease
--   public.growth_signals(p_world_id, p_as_of)              the Check screen's growth lists and the load patterns
--   public.hub_progress(p_world_id, p_as_of)                each main hub towards hub_first_departures; contested bases
--   public.capture_status(p_world_id, p_as_of)              what the capture collected for each airline, today and yesterday
--   public.fare_changes(p_airline_id, p_as_of)              economy fare changes seen in the captures
--   public.export_for_report(): gains kind 'figures' for the scripts (every function above for every airline).
-- Each is a faithful port of the old planner's code (web/planner/index.html, frozen since 12 Oct): the comment on each part
-- names the old function it follows, with the same windows, roundings and edge cases. Each takes p_as_of (now by
-- default) and uses only what the capture had recorded by then, so a test can freeze time. Money is in millions of AS$,
-- as the old planner shows it, unrounded: the screens round. Airlines come from airlines (ours, active, in position
-- order); each airline's home airport, where the game's events page shows its times, is its main base. Staff only;
-- each runs as owner with an empty search path and checks the caller itself. Nothing calls them yet: the scripts move
-- onto them in pull request 4 and the new planner's screens from pull request 5.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261012210000_captured_figures', true);

-- ============================================================ 0. small helpers
create or replace function private.fig_world(p_world_id bigint)
 returns bigint
 language plpgsql
 stable
 set search_path to ''
as $function$
declare w bigint;
begin
  select x.id into w from public.worlds x where x.id = p_world_id or (p_world_id is null and x.is_default) order by x.id limit 1;
  if w is null then raise exception 'no such world: %', coalesce(p_world_id::text, 'no default world') using errcode = '22023'; end if;
  return w;
end
$function$;

create or replace function private.fig_airline_world(p_airline_id bigint)
 returns bigint
 language plpgsql
 stable
 set search_path to ''
as $function$
declare w bigint;
begin
  select a.world_id into w from public.airlines a where a.id = p_airline_id;
  if w is null then raise exception 'no such airline: %', coalesce(p_airline_id::text, 'none given') using errcode = '22023'; end if;
  return w;
end
$function$;

-- a rule number from settings: the airline's own value where it has one, else the world's (decision #14)
create or replace function private.fig_num(p_world_id bigint, p_airline_id bigint, p_key text)
 returns numeric
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v jsonb;
begin
  select s.value into v from public.settings s
   where s.world_id = p_world_id and s.key = p_key and (s.airline_id is null or s.airline_id = p_airline_id)
   order by s.airline_id nulls last limit 1;
  if v is null or jsonb_typeof(v) <> 'number' then
    raise exception 'setting % is missing or isn''t a number', p_key using errcode = '22023';
  end if;
  return (v #>> '{}')::numeric;
end
$function$;

create or replace function private.fig_flag(p_world_id bigint, p_airline_id bigint, p_key text)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce((select (s.value #>> '{}')::boolean from public.settings s
                    where s.world_id = p_world_id and s.key = p_key and (s.airline_id is null or s.airline_id = p_airline_id)
                    order by s.airline_id nulls last limit 1), false)
$function$;

-- an airline's home airport, where the game's events page shows its times (the old planner's CAP_HOME): its main base;
-- for an airline with no main base (Ryanair, exempt from hubs first) the home airport the airline's row names, as the
-- capture itself uses it
create or replace function private.fig_home(p_airline_id bigint)
 returns text
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce((select b.airport_code from public.airline_bases b where b.airline_id = p_airline_id and b.is_main order by b.id limit 1),
                  (select a.home_airport_code from public.airlines a where a.id = p_airline_id))
$function$;

-- our active airlines in display order, each with its home airport (fig_home) and its main base (null for none)
create or replace function private.fig_airlines(p_world_id bigint)
 returns table (airline_id bigint, ord integer, iata_code text, name text, home_code text, main_code text)
 language sql
 stable
 set search_path to ''
as $function$
  select a.id, (row_number() over (order by a.position nulls last, a.id))::int, a.iata_code,
         coalesce(a.public_name, a.planner_name, a.game_name), private.fig_home(a.id),
         (select b.airport_code from public.airline_bases b where b.airline_id = a.id and b.is_main order by b.id limit 1)
    from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = p_world_id and g.kind = 'ours' and a.active
$function$;

-- the old planner's eqOff(): an airport's UTC offset in minutes as the route research gives it (airports.utc_offset),
-- 0 when it isn't known. It converts the events page's times and the loads page's departures to UTC this way.
create or replace function private.fig_eq_off(p_code text)
 returns integer
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce((select round(a.utc_offset * 60)::int from public.airports a where a.code = p_code), 0)
$function$;

-- a moment as the figures give it: UTC, to the millisecond
create or replace function private.fig_ts(p timestamptz)
 returns text
 language sql
 stable
 set search_path to ''
as $function$
  select to_char(p at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$function$;

-- an aircraft type's name as leaseM() compares names: upper case, AIRBUS dropped, EMBRAER as E, letters and digits only
create or replace function private.fig_type_key(p text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select regexp_replace(regexp_replace(regexp_replace(upper(coalesce(p, '')), 'AIRBUS', '', 'g'), 'EMBRAER', 'E', 'g'), '[^A-Z0-9]', '', 'g')
$function$;

-- ============================================================ 1. the schedule as the old planner reads it
-- One row per rotation (the old planner's frequency), as planner_state_get() gives it: the outbound's local weekdays at
-- the hub (offsets with the world's correction, 0 when unknown), its flight numbers, its aircraft and launch date.
-- live: its route is on the airline's list (M.routeMap has it). flights_week: flightsPerDay()'s count, (2 with a return
-- number, else 1) × the outbound's days, 7 days when there is no outbound. back_days: the return's local weekdays at the
-- destination (flightsOn()'s return day, wkday(date − depDay) in the outbound's days, as the table stores it).
create or replace function private.fig_freqs(p_world_id bigint, p_airline_id bigint default null)
 returns table (rotation_id bigint, airline_id bigint, route_id bigint, hub_code text, dest_code text, live boolean,
                days_n integer, flights_week integer, has_back boolean, tail text, launched_on date, no_out integer, no_back integer,
                out_days smallint[], back_days smallint[])
 language sql
 stable
 set search_path to ''
as $function$
  select r.id, r.airline_id, r.route_id, ro.hub_code, ro.dest_code,
         not ro.removed and ro.airline_id = r.airline_id,
         coalesce(cardinality(l1.days_utc), 7),
         (case when l2.flight_no is not null then 2 else 1 end) * coalesce(cardinality(l1.days_utc), 7),
         l2.flight_no is not null,
         coalesce(ac.registration, ''), r.launched_on, l1.flight_no, coalesce(l2.flight_no, l1.flight_no - 1),
         case when l1.id is null then null
              when l1.dep_utc_min is null then l1.days_utc
              else private.shift_weekdays(l1.days_utc, floor((l1.dep_utc_min + o.oh) / 1440.0)::int) end,
         case when l1.id is null or l2.id is null or l2.dep_utc_min is null then null
              else private.shift_weekdays(l2.days_utc, floor((l2.dep_utc_min + o.od) / 1440.0)::int) end
    from public.rotations r
    join public.routes ro on ro.id = r.route_id
    left join public.flight_legs l1 on l1.rotation_id = r.id and l1.leg_no = 1
    left join public.flight_legs l2 on l2.rotation_id = r.id and l2.leg_no = 2
    left join public.aircraft ac on ac.id = coalesce(l1.aircraft_id, l2.aircraft_id)
    left join public.airports ah on ah.code = ro.hub_code
    left join public.world_airports wh on wh.world_id = r.world_id and wh.airport_code = ro.hub_code
    left join public.airports ad on ad.code = ro.dest_code
    left join public.world_airports wd on wd.world_id = r.world_id and wd.airport_code = ro.dest_code
    cross join lateral (select round(coalesce(wh.utc_offset_override, ah.utc_offset, 0) * 60)::int as oh,
                               round(coalesce(wd.utc_offset_override, ad.utc_offset, 0) * 60)::int as od) o
   where r.world_id = p_world_id and (p_airline_id is null or r.airline_id = p_airline_id)
$function$;

-- flightsOn(): every scheduled flight departing on each local date from p_from to p_to, with its airline, number, route,
-- aircraft and its rotation's launch date
create or replace function private.fig_flights_on(p_world_id bigint, p_from date, p_to date)
 returns table (day date, airline_id bigint, flight_no integer, route_id bigint, tail text, launched_on date)
 language sql
 stable
 set search_path to ''
as $function$
  with f as (select * from private.fig_freqs(p_world_id) x where x.live),
  d as (select g::date as day, extract(isodow from g)::smallint as wd
          from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') g)
  select d.day, f.airline_id, f.no_out, f.route_id, f.tail, f.launched_on
    from f join d on d.wd = any (f.out_days) where f.no_out is not null
  union all
  select d.day, f.airline_id, f.no_back, f.route_id, f.tail, f.launched_on
    from f join d on d.wd = any (f.back_days) where f.no_back is not null
$function$;

-- ============================================================ 2. the daily loads as the old planner reads them
-- planner_loads_get()'s loads for local dates p_from to p_to, using only captures and typed entries made by p_as_of:
-- each flight's economy load, the typed figure where it is newer than the day's capture, else the captured one
create or replace function private.fig_load_values(p_world_id bigint, p_as_of timestamptz, p_from date, p_to date)
 returns table (day date, airline_id bigint, flight_no integer, v numeric)
 language sql
 stable
 set search_path to ''
as $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and g.kind = 'ours'),
  flown as (
    select f.airline_id, f.game_date, f.flight_no, f.eco_pct, f.loads_captured_at
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.game_date is not null and f.loads_captured_at <= p_as_of),
  captures as (
    select r.airline_id, r.captured_at from public.game_capture_raw r join ours on ours.id = r.airline_id
     where r.kind = 'loads' and r.captured_at <= p_as_of
    union
    select f.airline_id, f.loads_captured_at from flown f),
  stamped as (
    select x.airline_id, x.day, max(c.captured_at) as at
      from (select distinct f.airline_id, f.game_date as day from flown f where f.game_date between p_from and p_to) x
      join captures c on c.airline_id = x.airline_id and (c.captured_at at time zone 'UTC')::date - 3 <= x.day
     group by x.airline_id, x.day),
  caught as (
    select f.airline_id, f.game_date as day, f.flight_no, max(f.eco_pct) as eco_pct
      from flown f where f.eco_pct is not null and f.game_date between p_from and p_to
     group by f.airline_id, f.game_date, f.flight_no),
  typed as (
    select e.* from public.load_entries e join ours on ours.id = e.airline_id
     where e.world_id = p_world_id and e.game_date between p_from and p_to and (e.entered_at is null or e.entered_at <= p_as_of))
  select coalesce(c.day, e.game_date), coalesce(c.airline_id, e.airline_id), coalesce(c.flight_no, e.flight_no),
         case when e.airline_id is not null and (c.eco_pct is null or s.at is null or e.entered_at is null or e.entered_at >= s.at)
              then trim_scale(e.eco_pct) else c.eco_pct end
    from caught c
    full join typed e on e.airline_id = c.airline_id and e.game_date = c.day and e.flight_no = c.flight_no
    left join stamped s on s.airline_id = coalesce(c.airline_id, e.airline_id) and s.day = coalesce(c.day, e.game_date)
$function$;

-- loads_day_captured() as of p_as_of: every active airline of ours in the world was captured for that date
create or replace function private.fig_day_captured(p_world_id bigint, p_day date, p_as_of timestamptz)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and a.active and g.kind = 'ours'),
  s as (select private.capture_day_start(p_world_id, p_day) as v_from)
  select exists (select 1 from ours)
     and not exists (
       select 1 from ours a, s
        where not exists (select 1 from public.game_flights f
                           where f.airline_id = a.id and f.game_date = p_day and f.flight_no is not null
                             and f.loads_captured_at >= s.v_from and f.loads_captured_at <= p_as_of)
          and not exists (select 1 from public.game_capture_raw r
                           where r.airline_id = a.id and r.kind = 'loads' and r.captured_at <= p_as_of
                             and r.captured_at >= s.v_from and r.captured_at < s.v_from + interval '1 day'))
$function$;

-- planner_loads_get()'s day flags for local dates p_from to p_to, as of p_as_of: whether the day is done (the one rule,
-- unless a flag typed after the last capture says otherwise) and whether a capture wrote it (its source "capture")
create or replace function private.fig_load_days(p_world_id bigint, p_as_of timestamptz, p_from date, p_to date)
 returns table (day date, done boolean, captured boolean)
 language sql
 stable
 set search_path to ''
as $function$
  with ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and g.kind = 'ours'),
  flown as (
    select f.airline_id, f.game_date, f.loads_captured_at
      from public.game_flights f join ours on ours.id = f.airline_id
     where f.flight_no is not null and f.game_date is not null and f.loads_captured_at <= p_as_of),
  captures as (
    select r.airline_id, r.captured_at from public.game_capture_raw r join ours on ours.id = r.airline_id
     where r.kind = 'loads' and r.captured_at <= p_as_of
    union
    select f.airline_id, f.loads_captured_at from flown f),
  stamped as (
    select x.airline_id, x.day, max(c.captured_at) as at
      from (select distinct f.airline_id, f.game_date as day from flown f where f.game_date between p_from and p_to) x
      join captures c on c.airline_id = x.airline_id and (c.captured_at at time zone 'UTC')::date - 3 <= x.day
     group by x.airline_id, x.day),
  flags as (
    select ld.* from public.load_days ld
     where ld.world_id = p_world_id and ld.game_date between p_from and p_to and (ld.entered_at is null or ld.entered_at <= p_as_of)),
  days as (
    select f.game_date as day from flown f where f.game_date between p_from and p_to
    union select fl.game_date from flags fl
    union select e.game_date from public.load_entries e join ours on ours.id = e.airline_id
           where e.world_id = p_world_id and e.game_date between p_from and p_to and (e.entered_at is null or e.entered_at <= p_as_of)),
  day_stamp as (select s.day, max(s.at) as at from stamped s group by s.day)
  select d.day,
         case when ld.game_date is null then private.fig_day_captured(p_world_id, d.day, p_as_of)
              when ds.at is not null and (ld.entered_at is null or ds.at > ld.entered_at)
                then ld.done or private.fig_day_captured(p_world_id, d.day, p_as_of)
              else ld.done end,
         ds.day is not null
    from days d
    left join flags ld on ld.game_date = d.day
    left join day_stamp ds on ds.day = d.day
$function$;

-- dayOps(): for each local date and airline, the flights it flew that day (rotations launched by then), how many
-- aircraft, and the average load once the day's report is done (a flight without a load counts as full, 97.5%; on a
-- captured day only the flights the capture has)
create or replace function private.fig_day_ops(p_world_id bigint, p_as_of timestamptz, p_from date, p_to date)
 returns table (day date, airline_id bigint, flights integer, aircraft integer, load numeric)
 language sql
 stable
 set search_path to ''
as $function$
  with fl as (select x.* from private.fig_flights_on(p_world_id, p_from, p_to) x where x.launched_on is null or x.launched_on <= x.day),
  ld as (select * from private.fig_load_days(p_world_id, p_as_of, p_from, p_to)),
  lv as (select * from private.fig_load_values(p_world_id, p_as_of, p_from, p_to) x where x.v is not null),
  j as (select fl.day, fl.airline_id, fl.tail, lv.v, coalesce(ld.done, false) as done, coalesce(ld.captured, false) as captured,
               ld.day is not null as has_day
          from fl
          left join ld on ld.day = fl.day
          left join lv on lv.day = fl.day and lv.airline_id = fl.airline_id and lv.flight_no = fl.flight_no)
  select j.day, j.airline_id, count(*)::int, count(distinct j.tail)::int,
         case when bool_and(j.has_day) and bool_and(j.done)
              then avg(case when coalesce(j.v, 0) = 0 then 97.5 else j.v end) filter (where not j.captured or j.v is not null) end
    from j group by j.day, j.airline_id
$function$;

-- patterns(): each route's loads over the load window (load_window_days, ending two days ahead), leaving out each
-- rotation's first load_leeway_days: departures seen, how many at 95%+ (or not reported on a typed day), under 95, under
-- 85 and under 70, and the mark (cut, watch, add or hold) from the pattern_* settings
create or replace function private.fig_patterns(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_today date := (p_as_of at time zone 'UTC')::date; v_to date; v_from date; v_lw int;
begin
  v_to := v_today + 2;
  v_from := v_to - private.fig_num(p_world_id, null, 'load_window_days')::int + 1;
  v_lw := private.fig_num(p_world_id, null, 'load_leeway_days')::int;
  return (
    with ld as (select * from private.fig_load_days(p_world_id, p_as_of, v_from, v_to) x where x.done),
    lv as (select * from private.fig_load_values(p_world_id, p_as_of, v_from, v_to) x where x.v is not null),
    fl as (select x.day, x.airline_id, x.flight_no, x.route_id, lv.v
             from private.fig_flights_on(p_world_id, v_from, v_to) x
             join ld on ld.day = x.day
             left join lv on lv.day = x.day and lv.airline_id = x.airline_id and lv.flight_no = x.flight_no
            where not (x.launched_on is not null and x.day - x.launched_on < v_lw)
              and not (ld.captured and lv.v is null)),
    p as (select fl.route_id, fl.airline_id, count(*)::int as n,
                 count(*) filter (where coalesce(fl.v, 0) = 0 or fl.v >= 95)::int as full_n,
                 count(*) filter (where fl.v > 0 and fl.v >= 85 and fl.v < 95)::int as b95,
                 count(*) filter (where fl.v > 0 and fl.v >= 70 and fl.v < 85)::int as b85,
                 count(*) filter (where fl.v > 0 and fl.v < 70)::int as b70,
                 count(distinct fl.day)::int as days, count(distinct fl.flight_no)::int as flights
            from fl group by fl.route_id, fl.airline_id),
    th as (select x.airline_id,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_min_departures') as min_n,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_cut_under70_share') as cut70,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_cut_under85_share') as cut85,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_watch_under85_share') as watch85,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_add_min_departures') as add_n,
                  private.fig_num(p_world_id, x.airline_id, 'pattern_add_full_share') as add_full
             from (select distinct p.airline_id from p) x),
    m as (select p.*, ro.hub_code, ro.dest_code, a.position, th.min_n, th.cut70, th.cut85, th.watch85, th.add_n, th.add_full
            from p join public.routes ro on ro.id = p.route_id join public.airlines a on a.id = p.airline_id
            join th on th.airline_id = p.airline_id),
    s as (select m.*, case when m.n >= m.min_n and (m.b70::numeric / m.n >= m.cut70 or (m.b85 + m.b70)::numeric / m.n >= m.cut85) then 'cut'
                           when m.n >= m.min_n and (m.b85 + m.b70)::numeric / m.n >= m.watch85 then 'watch'
                           when m.n >= m.add_n and m.full_n::numeric / m.n >= m.add_full then 'add'
                           else 'hold' end as mark
            from m)
    select coalesce(jsonb_agg(jsonb_build_object(
             'airline_id', s.airline_id, 'route_id', s.route_id, 'hub', s.hub_code, 'dest', s.dest_code,
             'departures', s.n, 'full', s.full_n, 'under_95', s.b95, 'under_85', s.b85, 'under_70', s.b70,
             'days', s.days, 'flights', s.flights, 'mark', s.mark,
             'why', case s.mark when 'cut' then 'under 85% on most departures — reduce frequency or downgauge'
                                when 'watch' then 'a third of departures under 85%'
                                when 'add' then '95%+ on nearly every departure — add frequency or upgauge' else '' end)
             order by s.position nulls last, s.airline_id, s.hub_code, s.dest_code), '[]'::jsonb)
      from s);
end
$function$;

-- ============================================================ 3. money from the capture
-- game_ops_recent as of p_as_of: the airline's last 24 hours before its latest statement line (flights, income, costs)
create or replace function private.fig_ops_recent(p_airline_id bigint, p_as_of timestamptz)
 returns table (flights bigint, income numeric, costs numeric, last_ts timestamptz)
 language sql
 stable
 set search_path to ''
as $function$
  with money as (
    select f.posted_at as ts, f.income_total as income, f.cost_total as costs, (f.pax_income is not null)::int as flights
      from public.game_flights f
     where f.airline_id = p_airline_id and f.posted_at is not null and coalesce(f.money_captured_at, f.posted_at) <= p_as_of
    union all
    select p.paid_at, case when p.side = 'C' then p.amount else 0 end, case when p.side = 'C' then 0 else p.amount end, 0
      from public.game_payments p
     where p.airline_id = p_airline_id and p.kind = 'other' and p.created_at <= p_as_of),
  last as (
    select max(x.ts) as lt from (
      select f.posted_at as ts from public.game_flights f
       where f.airline_id = p_airline_id and f.posted_at is not null and coalesce(f.money_captured_at, f.posted_at) <= p_as_of
      union all
      select p.paid_at from public.game_payments p where p.airline_id = p_airline_id and p.created_at <= p_as_of) x)
  select sum(m.flights)::bigint, coalesce(sum(m.income), 0), coalesce(sum(m.costs), 0), max(l.lt)
    from money m cross join last l
   where l.lt is not null and m.ts > l.lt - interval '24 hours'
$function$;

-- the events page's payments as the old planner loads them (CAP.events): debits, from the first balance date of the
-- last 7 days (any airline) to 16 days ahead, each at its UTC moment from the airline's home airport (eqOff), in millions
create or replace function private.fig_events(p_world_id bigint, p_as_of timestamptz, p_airline_id bigint default null)
 returns table (airline_id bigint, at timestamptz, amount numeric, descr text, event_date date, event_time text)
 language sql
 stable
 set search_path to ''
as $function$
  with t as (select (p_as_of at time zone 'UTC')::date as today),
  f as (select coalesce(min(b.captured_on), (select today from t) - 7) as first_day
          from public.game_balance b
         where b.world_id = p_world_id and b.account like '2800%' and b.captured_at <= p_as_of
           and b.captured_on >= (select today from t) - 7)
  select e.airline_id, private.local_to_utc(e.event_date, e.event_time, private.fig_eq_off(h.code)), e.debit / 1000000,
         e.descr, e.event_date, e.event_time
    from public.game_events e
    cross join f
    join public.airlines a on a.id = e.airline_id
    left join public.airline_bases mb on mb.airline_id = e.airline_id and mb.is_main
    cross join lateral (select coalesce(mb.airport_code, a.home_airport_code) as code) h   -- fig_home()
   where e.world_id = p_world_id and (p_airline_id is null or e.airline_id = p_airline_id) and e.debit > 0 and e.captured_at <= p_as_of
     and e.event_date >= f.first_day and e.event_date <= (select today from t) + 16
$function$;

-- the cabin an order is priced with (the old planner's DEFAULT_CABIN, a table of cabin codes in its code): for a
-- low-cost airline the type's Standard layout; otherwise its Leisure layout, or its Comfort layout where it has no
-- Leisure one; where two layouts share that cabin, the one the airline's markets use as their default, then the newest
create or replace function private.fig_order_cabin(p_airline_id bigint, p_type_id bigint)
 returns bigint
 language sql
 stable
 set search_path to ''
as $function$
  with al as (select a.id, a.is_lcc from public.airlines a where a.id = p_airline_id),
  c as (select cc.id, cc.cabin from public.cabin_configs cc where cc.aircraft_type_id = p_type_id),
  want as (select case when al.is_lcc and exists (select 1 from c where c.cabin = 'Standard') then 'Standard'
                       when exists (select 1 from c where c.cabin = 'Leisure') then 'Leisure'
                       else 'Comfort' end as cabin from al)
  select c.id from c, want
   where c.cabin = want.cabin
   order by exists (select 1 from public.markets m where m.airline_id = p_airline_id and m.default_config_id = c.id) desc,
            exists (select 1 from public.markets m where m.default_config_id = c.id) desc, c.id desc
   limit 1
$function$;

-- an order's own lease (manual §3): weekly, first paid 7 days after it arrives, taken as arriving the moment it is ordered
-- (p_td; the most it could cost inside the 14 days). How many of its payments have fallen by p_t: inside the forecast's
-- 14 days, cashForecast's fits() count, (p_t >= p_td + 7 days) + (p_t >= p_td + 14 days)
create or replace function private.fig_lease_weeks(p_t timestamptz, p_td timestamptz)
 returns integer
 language sql
 stable
 set search_path to ''
as $function$
  select greatest(0, floor(extract(epoch from (p_t - (p_td + interval '336 hours'))) / 604800) + 1)::int   -- DELIBERATE FAILURE (spec "Proving it"): lease from 14 days, not 7; reverted next commit
$function$;

-- cashForecast()'s fits(): an order of p_n at p_price (cabin included) placed at p_td stays safe if, at every point of the
-- forecast from then on, the cash less the orders and their own weekly lease p_lease keeps p_cushion
create or replace function private.fig_fits(p_t timestamptz[], p_v numeric[], p_td timestamptz, p_n integer, p_price numeric,
                                            p_lease numeric, p_cushion numeric)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce(bool_and(x.v - p_n * (p_price + p_lease * private.fig_lease_weeks(x.t, p_td)) >= p_cushion), true)
    from unnest(p_t, p_v) as x(t, v)
   where x.t >= p_td
$function$;

-- ============================================================ 4. the cash forecast (cashForecast, flightsPerDay, leaseM, orderNow, fcNext)
-- leaseM()'s table: each type's highest weekly leasing payment in the world's events (fig_events), by type key
create or replace function private.fig_lease_map(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce(jsonb_object_agg(x.k, x.m), '{}'::jsonb)
    from (select private.fig_type_key((regexp_match(e.descr, 'Leasing payment for [^(]*\(([^)]+)\)', 'i'))[1]) as k, max(e.amount) as m
            from private.fig_events(p_world_id, p_as_of) e
           where e.descr ~* 'Leasing payment for'
           group by 1) x
   where x.k <> ''
$function$;

-- p_lease_map: fig_lease_map() for the world, when the caller has it already (airline_cards() works it out once)
create or replace function private.fig_cash_forecast(p_airline_id bigint, p_orders jsonb, p_as_of timestamptz, p_lease_map jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_home text; v_amount numeric; v_t0 timestamptz; v_cash0 numeric;
  v_flights bigint; v_income numeric; v_costs numeric; v_per_flight numeric; v_fpd numeric; v_ops_day numeric;
  v_cushion numeric; v_pct numeric; v_lease_map jsonb;
  v_pat timestamptz[]; v_pam numeric[]; v_pwhat text[]; v_prep boolean[];
  v_t timestamptz[]; v_v numeric[]; v_li int; v_cause jsonb;
  v_types jsonb; v_p numeric; v_l numeric;
  v_o jsonb; v_oty record; v_n int; v_sum_p numeric := 0; v_sum_l numeric := 0; v_olist jsonb := '[]'::jsonb; v_orders jsonb;
  v_low_after record; v_next jsonb; v_now jsonb;
  v_doc jsonb;
begin
  v_home := private.fig_home(p_airline_id);
  v_doc := jsonb_build_object('airline_id', p_airline_id, 'home_airport', v_home, 'as_of', private.fig_ts(p_as_of));
  -- cashForecast(): the airline's latest balance captured in the last 7 days (CAP.bal)
  select b.amount, b.captured_at into v_amount, v_t0
    from public.game_balance b
   where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_at <= p_as_of
   order by b.captured_at desc limit 1;
  if v_t0 is null or v_home is null then
    return v_doc || jsonb_build_object('status', 'no capture', 'missing', 'a capture: balance sheet, events and bank statement');
  end if;
  v_cash0 := coalesce(v_amount, 0) / 1000000;
  v_doc := v_doc || jsonb_build_object('cash', v_cash0, 'cash_at', private.fig_ts(v_t0));
  -- flight profit from the last 24 hours of the bank statement (game_ops_recent); fewer than 5 flights isn't enough
  select o.flights, o.income, o.costs into v_flights, v_income, v_costs from private.fig_ops_recent(p_airline_id, p_as_of) o;
  if v_flights is null or v_flights < 5 then
    return v_doc || jsonb_build_object('status', 'missing', 'missing', 'a bank statement capture');
  end if;
  v_per_flight := (v_income - v_costs) / v_flights / 1000000;
  -- flightsPerDay(): the planned flights a day
  select coalesce(sum(f.flights_week::numeric / 7), 0) into v_fpd from private.fig_freqs(w, p_airline_id) f where f.live and f.airline_id = p_airline_id;
  v_ops_day := v_per_flight * v_fpd;
  v_cushion := private.fig_num(w, p_airline_id, 'order_cushion') / 1000000;
  v_pct := private.fig_num(w, p_airline_id, 'lease_estimate_pct') / 100;

  -- every scheduled payment after the capture, and each one in its first week again a week later where the game
  -- doesn't list that far yet; up to 14 days after the capture
  with ev as (select e.at, e.amount, e.descr, e.event_date, e.event_time from private.fig_events(w, p_as_of, p_airline_id) e
               where e.airline_id = p_airline_id and e.at > v_t0),
  hz as (select coalesce(max(ev.at), v_t0) as h from ev),
  allp as (select ev.at, ev.amount, ev.descr, false as rep, ev.event_date, ev.event_time from ev
           union all
           select ev.at + interval '168 hours', ev.amount, ev.descr, true, ev.event_date, ev.event_time from ev, hz
            where ev.at <= v_t0 + interval '168 hours' and ev.at + interval '168 hours' > hz.h)
  select coalesce(array_agg(a.at order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.amount order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.descr order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}'),
         coalesce(array_agg(a.rep order by a.at, a.rep, a.event_date, a.event_time, a.descr), '{}')
    into v_pat, v_pam, v_pwhat, v_prep
    from allp a where a.at <= v_t0 + interval '336 hours';

  -- the balance at each payment and at the capture's moment on each of the 14 days after it
  select array_agg(y.t order by y.t), array_agg(y.v order by y.t) into v_t, v_v
    from (select x.t, v_cash0 + v_ops_day * (extract(epoch from (x.t - v_t0)) / 86400)
                      - coalesce((select sum(p.a) from unnest(v_pat, v_pam) as p(at, a) where p.at <= x.t), 0) as v
            from (select unnest(v_pat) as t union select v_t0 + i * interval '24 hours' from generate_series(0, 14) i) x) y;
  -- the lowest point (the first, if two are equal), and the payment that makes it: the largest at that moment, else the
  -- largest in the day before it
  select u.i into v_li from unnest(v_v) with ordinality as u(v, i) order by u.v, u.i limit 1;
  select jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) into v_cause
    from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)
   where p.at = v_t[v_li] order by p.amount desc, p.i limit 1;
  if v_cause is null then
    select jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) into v_cause
      from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)
     where p.at <= v_t[v_li] and p.at > v_t[v_li] - interval '24 hours' order by p.amount desc, p.i limit 1;
  end if;

  -- leaseM(): each type's weekly lease, the highest leasing payment seen for it in the events (any airline), else
  -- lease_estimate_pct of its price
  v_lease_map := coalesce(p_lease_map, private.fig_lease_map(w, p_as_of));

  -- each type the airline may buy (airline_aircraft_types): the first day in the next 14 it can be ordered and keep the
  -- cushion (fits() at the capture's moment on each day), with its price (cabin included) and its own lease; how many at
  -- once if today, up to 9 (the most n for which every point from then on keeps the cushion after n orders)
  with ty as (
    select t.id, t.name, t.price / 1000000 as price, cc.code as cabin, coalesce(cc.cost, 0) / 1000000 as cabin_cost,
           (v_lease_map ->> private.fig_type_key(t.name))::numeric as seen_lease
      from public.airline_aircraft_types aat
      join public.aircraft_types t on t.id = aat.aircraft_type_id
      left join public.cabin_configs cc on cc.id = private.fig_order_cabin(p_airline_id, t.id)
     where aat.airline_id = p_airline_id and coalesce(t.price, 0) <> 0),
  tp as (select ty.*, ty.price + ty.cabin_cost as p, coalesce(ty.seen_lease, ty.price * v_pct) as l from ty),
  -- for an order placed on day d, each point from then on and how many of its own lease payments have fallen by then
  -- (worked out once for all types)
  pw as materialized (
    select d.d, x.t, x.v, private.fig_lease_weeks(x.t, v_t0 + d.d * interval '24 hours') as wk
      from generate_series(0, 14) as d(d)
      join unnest(v_t, v_v) as x(t, v) on x.t >= v_t0 + d.d * interval '24 hours'),
  ok as (select tp.id, pw.d, bool_and(pw.v - (tp.p + tp.l * pw.wk) >= v_cushion) as fits
           from tp cross join pw
          group by tp.id, pw.d),
  first_day as (select ok.id, min(ok.d) filter (where ok.fits) as d from ok group by ok.id),
  most as (select tp.id, least(9, floor(min((pw.v - v_cushion) / (tp.p + tp.l * pw.wk))))::int as n
             from tp join pw on pw.d = 0 group by tp.id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'aircraft_type_id', tp.id, 'type', tp.name, 'price', tp.price, 'cabin', tp.cabin, 'cabin_cost', tp.cabin_cost,
           'price_with_cabin', tp.p, 'lease_week', tp.l, 'lease_seen', tp.seen_lease is not null,
           'safe_day', f.d, 'safe_from', private.fig_ts(v_t0 + f.d * interval '24 hours'),
           'count_today', case when f.d = 0 then m.n end) order by tp.id), '[]'::jsonb)
    into v_types
    from tp join first_day f on f.id = tp.id join most m on m.id = tp.id;

  -- orderNow() and fcNext(): what can be ordered today (dearest first), else the first safe day
  select coalesce(jsonb_agg(x ->> 'type' order by (x ->> 'price_with_cabin')::numeric desc, (x ->> 'aircraft_type_id')::bigint), '[]'::jsonb)
    into v_now from jsonb_array_elements(v_types) x where (x ->> 'safe_day')::int = 0;
  if jsonb_array_length(v_now) > 0 then
    v_next := jsonb_build_object('when', 'now', 'types', v_now);
  else
    select jsonb_build_object('when', 'later', 'type', x ->> 'type', 'aircraft_type_id', (x ->> 'aircraft_type_id')::bigint,
                              'safe_day', (x ->> 'safe_day')::int, 'safe_from', x ->> 'safe_from')
      into v_next
      from jsonb_array_elements(v_types) x where x ->> 'safe_day' is not null
     order by (x ->> 'safe_day')::int, (x ->> 'price_with_cabin')::numeric desc, (x ->> 'aircraft_type_id')::bigint limit 1;
    v_next := coalesce(v_next, jsonb_build_object('when', 'not within 14 days'));
  end if;

  -- p_orders: several orders tested together, all placed now, each with its own lease (manual §3)
  if p_orders is not null and jsonb_typeof(p_orders) <> 'array' then
    raise exception 'p_orders must be a list: [{"type": "<aircraft type>", "count": 1}, ...]' using errcode = '22023';
  end if;
  if p_orders is not null and jsonb_array_length(p_orders) > 0 then
    for v_o in select * from jsonb_array_elements(p_orders) loop
      if jsonb_typeof(v_o) <> 'object' then raise exception 'p_orders: each order is an object, e.g. {"type": "A321 NEO LIGHT", "count": 1}' using errcode = '22023'; end if;
      select t.id, t.name, coalesce(t.price, 0) / 1000000 as price, cc.code as cabin, coalesce(cc.cost, 0) / 1000000 as cabin_cost,
             (v_lease_map ->> private.fig_type_key(t.name))::numeric as seen_lease,
             exists (select 1 from public.airline_aircraft_types aat where aat.airline_id = p_airline_id and aat.aircraft_type_id = t.id) as may_buy
        into v_oty
        from public.aircraft_types t
        left join public.cabin_configs cc on cc.id = private.fig_order_cabin(p_airline_id, t.id)
       where t.world_id = w and (t.id = (v_o ->> 'aircraft_type_id')::bigint or (v_o ? 'type' and t.name = v_o ->> 'type'))
       order by t.id limit 1;
      if v_oty.id is null then raise exception 'p_orders: no such aircraft type: %', coalesce(v_o ->> 'type', v_o ->> 'aircraft_type_id') using errcode = '22023'; end if;
      v_n := coalesce((v_o ->> 'count')::int, 1);
      if v_n < 1 then raise exception 'p_orders: the count must be 1 or more' using errcode = '22023'; end if;
      v_p := v_oty.price + v_oty.cabin_cost;
      v_l := coalesce(v_oty.seen_lease, v_oty.price * v_pct);
      v_sum_p := v_sum_p + v_n * v_p; v_sum_l := v_sum_l + v_n * v_l;
      v_olist := v_olist || jsonb_build_object('aircraft_type_id', v_oty.id, 'type', v_oty.name, 'count', v_n, 'may_buy', v_oty.may_buy,
                                               'price_with_cabin', v_p, 'lease_week', v_l, 'lease_seen', v_oty.seen_lease is not null);
    end loop;
    select x.t, x.v - (v_sum_p + v_sum_l * private.fig_lease_weeks(x.t, v_t0)) as v
      into v_low_after
      from unnest(v_t, v_v) with ordinality as x(t, v, i)
     order by 2, x.i limit 1;
    v_orders := jsonb_build_object('orders', v_olist,
                                   'safe', private.fig_fits(v_t, v_v, v_t0, 1, v_sum_p, v_sum_l, v_cushion),
                                   'lowest', jsonb_build_object('at', private.fig_ts(v_low_after.t), 'balance', v_low_after.v),
                                   -- the forecast after the orders: each point less their prices and the leases fallen by then
                                   'points', (select jsonb_agg(jsonb_build_object('at', private.fig_ts(x.t),
                                                'balance', x.v - (v_sum_p + v_sum_l * private.fig_lease_weeks(x.t, v_t0))) order by x.i)
                                                from unnest(v_t, v_v) with ordinality as x(t, v, i)));
  end if;

  return v_doc || jsonb_build_object(
    'status', 'ok',
    'profit_per_flight', v_per_flight, 'flights_per_day', v_fpd, 'flight_profit_day', v_ops_day,
    'cushion', v_cushion,
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('at', private.fig_ts(p.at), 'amount', p.amount, 'what', p.what, 'repeat', p.rep) order by p.i), '[]'::jsonb)
                   from unnest(v_pat, v_pam, v_pwhat, v_prep) with ordinality as p(at, amount, what, rep, i)),
    'payments_next_7_days', (select coalesce(sum(p.a), 0) from unnest(v_pat, v_pam) as p(at, a) where p.at <= v_t0 + interval '168 hours'),
    'points', (select jsonb_agg(jsonb_build_object('at', private.fig_ts(x.t), 'balance', x.v) order by x.i)
                 from unnest(v_t, v_v) with ordinality as x(t, v, i)),
    'lowest', jsonb_build_object('at', private.fig_ts(v_t[v_li]), 'balance', v_v[v_li], 'payment', v_cause),
    'types', v_types,
    'can_order_now', v_now,
    'next_order', v_next)
    || case when v_orders is null then '{}'::jsonb else jsonb_build_object('orders_tested', v_orders) end;
end
$function$;

-- ============================================================ 5. route and aircraft profit, fare changes (routeProfit)
create or replace function private.fig_route_profit(p_airline_id bigint, p_days integer, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
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
  -- departure in UTC from its origin's offset (capDepUTC)
  select coalesce(jsonb_agg(to_jsonb(y) order by y.j), '[]'::jsonb) into v_loads
    from (select x.*, (row_number() over (order by x.id))::int as j,
                 private.local_to_utc(x.game_date, x.dep_local, private.fig_eq_off(x.origin)) as dep_utc
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

-- ============================================================ 6. Review's cards and profit by day (finSeries, finStats, capexIn, dayOps)
-- finSeries(): the airline's cash by date, in millions: each capture date's latest balance, rounded to 0.01M as the
-- planner keeps it (applyCaptureCash for the last 7 days; before that a figure typed in cash_entries wins), up to p_as_of
create or replace function private.fig_cash_days(p_airline_id bigint, p_as_of timestamptz)
 returns table (day date, cash numeric)
 language sql
 stable
 set search_path to ''
as $function$
  with t as (select (p_as_of at time zone 'UTC')::date as today),
  cap as (select distinct on (b.captured_on) b.captured_on as day, b.amount
            from public.game_balance b
           where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_at <= p_as_of
             and b.captured_on <= (select today from t) and b.amount is not null
           order by b.captured_on, b.captured_at desc),
  typed as (select e.day, e.cash from public.cash_entries e
             where e.airline_id = p_airline_id and e.day <= (select today from t) and e.cash is not null)
  select coalesce(c.day, e.day),
         case when c.day is not null and c.day >= (select today from t) - 7 then floor(c.amount / 10000 + 0.5) / 100
              when e.day is not null then e.cash / 1000000
              else floor(c.amount / 10000 + 0.5) / 100 end
    from cap c full join typed e on e.day = c.day
$function$;

-- capexIn(): order payments (orders and cabins, not losses) logged after d0 up to d1, in millions
create or replace function private.fig_capex(p_airline_id bigint, p_d0 date, p_d1 date)
 returns numeric
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce(sum(s.amount), 0) / 1000000 from public.spending_log s
   where s.airline_id = p_airline_id and s.kind <> 'loss' and s.spent_on > p_d0 and s.spent_on <= p_d1
$function$;

-- finStats(): one airline's card and its profit for each day between captures. p_ops: dayOps for the world, if the
-- caller has it already ({airline_id: {date: {flights, aircraft, load}}}), else worked out here
create or replace function private.fig_fin_stats(p_airline_id bigint, p_as_of timestamptz, p_ops jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_s jsonb; v_ops jsonb; v_iv jsonb; v_from date;
  v_last_d date; v_last_c numeric; v_first_d date; v_first_c numeric; v_span int; v_profit numeric;
  v_avg_tails numeric; v_per_ac numeric; v_flying int; v_fly_val numeric; v_avg_price numeric;
  v_now_f int; v_then_f int; v_then_t int; v_load7 numeric; v_on_order int;
begin
  select coalesce(jsonb_agg(jsonb_build_object('d', c.day, 'c', c.cash) order by c.day), '[]'::jsonb) into v_s
    from private.fig_cash_days(p_airline_id, p_as_of) c;
  if p_ops is not null then
    v_ops := coalesce(p_ops -> p_airline_id::text, '{}'::jsonb);
  else
    v_from := least(coalesce((v_s -> 0 ->> 'd')::date, v_today), v_today - 7);
    select coalesce(jsonb_object_agg(o.day::text, jsonb_build_object('flights', o.flights, 'aircraft', o.aircraft, 'load', o.load)), '{}'::jsonb)
      into v_ops from private.fig_day_ops(w, p_as_of, v_from, v_today) o where o.airline_id = p_airline_id;
  end if;
  -- each interval between two reported days: change in cash plus that period's order payments, per day
  with s as (select (x ->> 'd')::date as d, (x ->> 'c')::numeric as c, i from jsonb_array_elements(v_s) with ordinality as e(x, i))
  select coalesce(jsonb_agg(jsonb_build_object(
           'date', p.d, 'cash', p.c, 'change', p.c - q.c, 'order_payments', cap.v, 'days', greatest(1, p.d - q.d),
           'profit_day', (p.c - q.c + cap.v) / greatest(1, p.d - q.d),
           'aircraft', coalesce((v_ops -> p.d::text ->> 'aircraft')::int, 0),
           'flights', coalesce((v_ops -> p.d::text ->> 'flights')::int, 0),
           'load', (v_ops -> p.d::text ->> 'load')::numeric) order by p.i), '[]'::jsonb)
    into v_iv
    from s p join s q on q.i = p.i - 1
    cross join lateral (select private.fig_capex(p_airline_id, q.d, p.d) as v offset 0) cap;
  -- profit over the last 7 days (an early read over fewer), and per aircraft flying in that time
  if jsonb_array_length(v_s) > 0 then
    v_last_d := (v_s -> -1 ->> 'd')::date; v_last_c := (v_s -> -1 ->> 'c')::numeric;
    select (x ->> 'd')::date, (x ->> 'c')::numeric into v_first_d, v_first_c
      from jsonb_array_elements(v_s) with ordinality as e(x, i) where v_last_d - (x ->> 'd')::date <= 7 order by i limit 1;
    v_span := v_last_d - v_first_d;
    v_profit := case when v_span <> 0 then (v_last_c - v_first_c + private.fig_capex(p_airline_id, v_first_d, v_last_d)) / v_span end;
    select avg((x ->> 'aircraft')::numeric) into v_avg_tails from jsonb_array_elements(v_iv) x where (x ->> 'date')::date > v_first_d;
    v_per_ac := case when v_profit is not null and coalesce(v_avg_tails, 0) <> 0 then v_profit / v_avg_tails end;
  end if;
  -- the fleet (the old planner's tails: aircraft in service) and its value at today's prices
  select count(*)::int, coalesce(sum(coalesce(t.price, 0)), 0) / 1000000 into v_flying, v_fly_val
    from public.aircraft a left join public.aircraft_types t on t.id = a.aircraft_type_id
   where a.airline_id = p_airline_id and a.status = 'active';
  v_avg_price := case when v_flying > 0 then v_fly_val / v_flying else 0 end;
  v_now_f := coalesce((v_ops -> v_today::text ->> 'flights')::int, 0);
  v_then_f := coalesce((v_ops -> (v_today - 7)::text ->> 'flights')::int, 0);
  v_then_t := coalesce((v_ops -> (v_today - 7)::text ->> 'aircraft')::int, 0);
  select avg((v_ops -> (v_today - k)::text ->> 'load')::numeric) into v_load7 from generate_series(0, 6) k;
  select count(*)::int into v_on_order from public.aircraft a where a.airline_id = p_airline_id and a.status in ('on_order', 'delivered');
  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of),
    'profit_day', v_profit, 'span_days', v_span, 'early', case when v_span is not null then v_span < 7 end,
    'per_aircraft_day', v_per_ac,
    'return_on_fleet_pct_week', case when v_profit is not null and v_fly_val <> 0 then v_profit * 7 / v_fly_val * 100 end,
    'payback_days', case when v_per_ac > 0 and v_avg_price <> 0 then v_avg_price / v_per_ac end,
    'funds_aircraft_every_days', case when v_profit > 0 and v_avg_price <> 0 then v_avg_price / v_profit end,
    'fleet', v_flying, 'fleet_added_this_week', v_flying - v_then_t, 'on_order', v_on_order,
    'fleet_value', v_fly_val, 'average_price', v_avg_price,
    'flights_day', v_now_f, 'flights_added_this_week', v_now_f - v_then_f,
    'load_7_days', v_load7,
    'days', v_iv);
end
$function$;

-- groupOverviewHtml(): one airline's row of the group today: cash, flight profit a day, this week's leases and week-end
-- closing per day, net, and the aircraft arrived but not yet flying with their leases
create or replace function private.fig_group_today(p_airline_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_cash numeric; v_flights bigint; v_income numeric; v_costs numeric; v_ops numeric; v_fpd numeric;
  v_ground text[]; v_lease numeric; v_closing numeric; v_ground_lease numeric;
begin
  select b.amount / 1000000 into v_cash from public.game_balance b
   where b.airline_id = p_airline_id and b.account like '2800%' and b.captured_on >= v_today - 7 and b.captured_at <= p_as_of
   order by b.captured_at desc limit 1;
  select o.flights, o.income, o.costs into v_flights, v_income, v_costs from private.fig_ops_recent(p_airline_id, p_as_of) o;
  if v_flights >= 5 then
    select coalesce(sum(f.flights_week::numeric / 7), 0) into v_fpd from private.fig_freqs(w, p_airline_id) f where f.live and f.airline_id = p_airline_id;
    v_ops := (v_income - v_costs) / v_flights * v_fpd / 1000000;
  end if;
  select coalesce(array_agg(a.registration order by a.delivery_at, a.registration), '{}') into v_ground
    from public.aircraft a
   where a.airline_id = p_airline_id and a.status in ('on_order', 'delivered') and a.delivery_at <= p_as_of;
  select coalesce(sum(e.amount) filter (where e.descr ~* 'Leasing payment'), 0) / 7,
         coalesce(sum(e.amount) filter (where e.descr ~* 'Week-end closing'), 0) / 7,
         coalesce(sum(e.amount) filter (where exists (select 1 from unnest(v_ground) g where strpos(e.descr, g || ' ') > 0)), 0) / 7
    into v_lease, v_closing, v_ground_lease
    from private.fig_events(w, p_as_of, p_airline_id) e
   where e.airline_id = p_airline_id and e.at > p_as_of and e.at <= p_as_of + interval '168 hours';
  return jsonb_build_object('airline_id', p_airline_id, 'cash', v_cash, 'flight_profit_day', v_ops,
                            'leases_day', v_lease, 'closing_day', v_closing, 'net_day', v_ops - v_lease - v_closing,
                            'on_ground', to_jsonb(v_ground), 'on_ground_lease_day', v_ground_lease);
end
$function$;

-- ============================================================ 7. the Check screen: hubs first and the capture board
-- hubProgressHtml() and manual §3, hubs first
create or replace function private.fig_hub_progress(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_scan bigint; v_scan_at timestamptz; v_has_schedules boolean;
begin
  -- the latest world scan by then that has its airport summary
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = p_world_id and s.taken_at <= p_as_of
     and exists (select 1 from public.scan_airline_airports x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;
  v_has_schedules := exists (select 1 from public.game_scan_schedules x where x.scan_id = v_scan);
  return (
    with al as (select * from private.fig_airlines(p_world_id)),
    fq as (select * from private.fig_freqs(p_world_id) f where f.live),
    rivals as (select a.id from public.airlines a left join public.groups g on g.id = a.group_id
                where a.world_id = p_world_id and coalesce(g.kind, 'rival') <> 'ours'),
    -- the scan's rival flights from our bases, flights a week by origin, destination and airline (read once for all bases)
    sched as materialized (
      select f ->> 2 as origin, f ->> 3 as dest, sc.airline_id, coalesce(ra.public_name, ra.game_name, ra.planner_name) as name,
             sum(length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')))::int as weekly
        from public.game_scan_schedules sc
        join public.airlines ra on ra.id = sc.airline_id
        cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
       where v_has_schedules and sc.scan_id = v_scan and sc.airline_id in (select id from rivals)
         and jsonb_typeof(f) = 'array' and coalesce(f ->> 3, '') <> ''
         and f ->> 2 in (select b.airport_code from public.airline_bases b where b.world_id = p_world_id and not b.is_main)
       group by f ->> 2, f ->> 3, sc.airline_id, ra.public_name, ra.game_name, ra.planner_name),
    hubs as (
      select al.airline_id, al.ord, al.iata_code, al.name, al.main_code,
             private.fig_flag(p_world_id, al.airline_id, 'hub_first_exempt') as exempt,
             private.fig_num(p_world_id, al.airline_id, 'hub_first_departures') as target,
             -- departures a week flying from the main hub: outbound legs from it, and returns from it
             case when al.main_code is not null then
               (select coalesce(sum(f.days_n) filter (where f.hub_code = al.main_code), 0)
                       + coalesce(sum(f.days_n) filter (where f.dest_code = al.main_code and f.has_back), 0)
                  from fq f where f.airline_id = al.airline_id)::int end as departures,
             -- and those on the plan cards of aircraft not yet filed (each leg's days; every day unless set)
             case when al.main_code is not null then
               coalesce((select sum(coalesce(cardinality(l.days_utc), 7))
                           from public.aircraft a
                           join public.plan_cards c on c.aircraft_id = a.id
                           join public.plan_card_legs l on l.plan_card_id = c.id
                          where a.airline_id = al.airline_id and a.status in ('on_order', 'delivered') and l.origin_code = al.main_code), 0)::int end as planned
        from al),
    bases as (
      select b.airline_id, b.airport_code, b.role, b.position, b.id,
             (select jsonb_build_object('airline_id', x.airline_id, 'name', coalesce(ra.public_name, ra.game_name, ra.planner_name), 'weekly', x.weekly_departures)
                from public.scan_airline_airports x join public.airlines ra on ra.id = x.airline_id
               where x.scan_id = v_scan and x.airport_code = b.airport_code and x.airline_id in (select id from rivals)
               order by x.weekly_departures desc, x.airline_id limit 1) as top_rival,
             case when v_has_schedules then (
               select coalesce(jsonb_agg(jsonb_build_object('dest', z.dest, 'airline_id', z.airline_id, 'name', z.name, 'weekly', z.weekly)
                                         order by z.weekly desc, z.dest, z.airline_id), '[]'::jsonb)
                 from sched z
                where z.origin = b.airport_code and z.weekly > 7 * private.fig_num(p_world_id, b.airline_id, 'contested_rival_daily')) end as routes
        from public.airline_bases b
       where b.world_id = p_world_id and not b.is_main)
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of),
      'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at), 'schedules', v_has_schedules) end,
      'airlines', coalesce((select jsonb_agg(jsonb_build_object(
          'airline_id', h.airline_id, 'code', h.iata_code, 'name', h.name, 'main_hub', h.main_code,
          'exempt', h.exempt, 'target', h.target, 'departures', h.departures, 'planned', h.planned,
          'percent', h.departures / h.target * 100,
          'bases', coalesce((select jsonb_agg(jsonb_build_object(
              'code', b.airport_code, 'role', b.role, 'top_rival', b.top_rival,
              'contested_by_departures', coalesce((b.top_rival ->> 'weekly')::numeric > private.fig_num(p_world_id, b.airline_id, 'contested_rival_weekly'), false),
              'contested_routes', b.routes,
              'contested', coalesce((b.top_rival ->> 'weekly')::numeric > private.fig_num(p_world_id, b.airline_id, 'contested_rival_weekly'), false)
                           or coalesce(jsonb_array_length(b.routes) > 0, false))
              order by b.position nulls last, b.id) from bases b where b.airline_id = h.airline_id), '[]'::jsonb))
          order by h.ord) from hubs h), '[]'::jsonb)));
end
$function$;

-- captureBoard(): for each airline, today's and yesterday's capture (UTC dates): when each page kind last came, and how
-- many flights (flight numbers, by departure date as the game lists them) the loads page held
create or replace function private.fig_capture_status(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  with d as (select (p_as_of at time zone 'UTC')::date as d0),
  al as (select * from private.fig_airlines(p_world_id) where home_code is not null),
  k as (select * from unnest(array['loads', 'statement', 'events', 'pnl', 'balance']) with ordinality as k(kind, o)),
  runs as (select r.airline_id, r.kind, (r.captured_at at time zone 'UTC')::date as day, max(r.captured_at) as at
             from public.game_capture_raw r, d
            where r.world_id = p_world_id and r.captured_at <= p_as_of
              and r.captured_at >= ((d.d0 - 1)::timestamp at time zone 'UTC')
            group by 1, 2, 3),
  fl as (select f.airline_id, f.game_date, count(distinct f.flight_no)::int as n
           from public.game_flights f, d
          where f.world_id = p_world_id and f.flight_no is not null and f.game_date in (d.d0, d.d0 - 1) and f.loads_captured_at <= p_as_of
          group by 1, 2),
  rows_ as (
    select al.airline_id, al.ord, al.iata_code, al.name,
           (select jsonb_object_agg(k.kind, jsonb_build_object('today', private.fig_ts(t.at), 'yesterday', private.fig_ts(y.at)) order by k.o)
              from k left join runs t on t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0
                     left join runs y on y.airline_id = al.airline_id and y.kind = k.kind and y.day = d.d0 - 1) as pages,
           (select coalesce(jsonb_agg(k.kind order by k.o), '[]'::jsonb) from k
             where not exists (select 1 from runs t where t.airline_id = al.airline_id and t.kind = k.kind and t.day = d.d0)) as missing,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0) as flights_today,
           (select n from fl where fl.airline_id = al.airline_id and fl.game_date = d.d0 - 1) as flights_yesterday
      from al, d)
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'today', (select d0 from d), 'yesterday', (select d0 - 1 from d),
    'airlines', coalesce(jsonb_agg(jsonb_build_object(
        'airline_id', r.airline_id, 'code', r.iata_code, 'name', r.name, 'pages', r.pages,
        'flights_today', r.flights_today, 'flights_yesterday', r.flights_yesterday, 'missing', r.missing,
        'status', case when jsonb_array_length(r.missing) = 0 then 'complete' when jsonb_array_length(r.missing) = 5 then 'not captured' else 'missing' end)
        order by r.ord), '[]'::jsonb))
    from rows_ r
$function$;

-- ============================================================ 8. the growth signals (capSignalsHtml, patterns)
create or replace function private.fig_growth_signals(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_days int := private.fig_num(p_world_id, null, 'growth_window_days')::int; v_docs jsonb;
begin
  -- each airline's route and aircraft profit over the growth window, for those with flights captured
  select coalesce(jsonb_agg(jsonb_build_object('airline_id', al.airline_id, 'ord', al.ord, 'doc', x.doc) order by al.ord), '[]'::jsonb) into v_docs
    from private.fig_airlines(p_world_id) al
    cross join lateral (select private.fig_route_profit(al.airline_id, v_days, p_as_of) as doc offset 0) x   -- once each
   where al.home_code is not null and (x.doc ->> 'flights')::int > 0;
  return (
    with r as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
                 from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'routes') with ordinality as e(x, i)),
    t as (select (d ->> 'airline_id')::bigint as airline_id, (d ->> 'ord')::int as ord, e.x, e.i
            from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d -> 'doc' -> 'aircraft') with ordinality as e(x, i))
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'days', v_days,
      'ready_for_another_flight', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                                     order by (r.x ->> 'profit_week')::numeric desc, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' = 'add'),
      'raise_fares', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                        order by (r.x ->> 'flights')::int desc, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' = 'raise'),
      'fix_or_reduce', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', r.airline_id) || r.x
                          order by (r.x ->> 'profit_per_flight')::numeric, r.ord, r.i), '[]'::jsonb) from r where r.x ->> 'mark' in ('losing', 'fix')),
      'aircraft_losing_after_lease', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', t.airline_id) || t.x
                                        order by (t.x ->> 'net_day')::numeric, t.ord, t.i), '[]'::jsonb)
                                        from t where (t.x ->> 'net_day')::numeric < 0),
      'load_patterns', private.fig_patterns(p_world_id, p_as_of)));
end
$function$;

-- ============================================================ 9. Review's cards for every airline (renderFinance, groupOverviewHtml)
create or replace function private.fig_airline_cards(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_today date := (p_as_of at time zone 'UTC')::date; v_from date; v_ops jsonb;
        v_leases jsonb := private.fig_lease_map(p_world_id, p_as_of);
begin
  -- dayOps for every airline at once, from the first reported cash date (or a week back) to today
  select least(coalesce(min(c.day), v_today), v_today - 7) into v_from
    from private.fig_airlines(p_world_id) al cross join lateral private.fig_cash_days(al.airline_id, p_as_of) c;
  select coalesce(jsonb_object_agg(x.airline_id::text, x.days), '{}'::jsonb) into v_ops
    from (select o.airline_id, jsonb_object_agg(o.day::text, jsonb_build_object('flights', o.flights, 'aircraft', o.aircraft, 'load', o.load)) as days
            from private.fig_day_ops(p_world_id, p_as_of, v_from, v_today) o group by o.airline_id) x;
  return (
    -- materialized: each airline's card, forecast and row worked out once (folded in, each use would work them out again)
    with c as materialized (
      select al.*, private.fig_fin_stats(al.airline_id, p_as_of, v_ops) as card,
             case when al.home_code is not null then private.fig_cash_forecast(al.airline_id, '[]'::jsonb, p_as_of, v_leases) end as fc,
             case when al.home_code is not null then private.fig_group_today(al.airline_id, p_as_of) end as today
        from private.fig_airlines(p_world_id) al)
    select jsonb_build_object(
      'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of),
      'airlines', coalesce(jsonb_agg((c.card - 'days') || jsonb_build_object(
          'code', c.iata_code, 'name', c.name,
          -- fcNext(): needs a capture, needs a bank statement capture, can order now, safe from a day, or not within 14 days
          'next_order', case when c.fc is null or c.fc ->> 'status' = 'no capture' then jsonb_build_object('when', 'needs', 'missing', 'a capture')
                             when c.fc ->> 'status' <> 'ok' then jsonb_build_object('when', 'needs', 'missing', c.fc ->> 'missing')
                             else c.fc -> 'next_order' end,
          'can_order_now', coalesce(c.fc -> 'can_order_now', '[]'::jsonb))
          order by c.ord), '[]'::jsonb),
      -- the group today: shown once any airline has flight profit
      'group_today', coalesce(jsonb_agg(c.today || jsonb_build_object('code', c.iata_code, 'name', c.name) order by c.ord)
                                filter (where c.today is not null), '[]'::jsonb),
      'group_today_shown', coalesce(bool_or(c.today ->> 'flight_profit_day' is not null), false))
      from c);
end
$function$;

-- ============================================================ 10. the staff functions (design §8)
create or replace function public.cash_forecast(p_airline_id bigint, p_orders jsonb default '[]'::jsonb, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_cash_forecast(p_airline_id, coalesce(p_orders, '[]'::jsonb), coalesce(p_as_of, now()));
end
$function$;

create or replace function public.airline_cards(p_world_id bigint default null, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_airline_cards(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

create or replace function public.airline_profit(p_airline_id bigint, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare d jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_fin_stats(p_airline_id, coalesce(p_as_of, now()));
  return jsonb_build_object('airline_id', p_airline_id, 'as_of', d -> 'as_of', 'profit_day', d -> 'profit_day',
                            'span_days', d -> 'span_days', 'early', d -> 'early', 'days', d -> 'days');
end
$function$;

create or replace function public.route_profit(p_airline_id bigint, p_days integer default 7, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_route_profit(p_airline_id, p_days, coalesce(p_as_of, now())) - 'aircraft' - 'fare_changes';
end
$function$;

create or replace function public.aircraft_profit(p_airline_id bigint, p_days integer default 7, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare d jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_route_profit(p_airline_id, p_days, coalesce(p_as_of, now()));
  return jsonb_build_object('airline_id', p_airline_id, 'days', p_days, 'as_of', d -> 'as_of', 'since', d -> 'since', 'aircraft', d -> 'aircraft');
end
$function$;

create or replace function public.growth_signals(p_world_id bigint default null, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_growth_signals(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

create or replace function public.hub_progress(p_world_id bigint default null, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_hub_progress(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

create or replace function public.capture_status(p_world_id bigint default null, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_capture_status(private.fig_world(p_world_id), coalesce(p_as_of, now()));
end
$function$;

create or replace function public.fare_changes(p_airline_id bigint, p_as_of timestamptz default now())
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare d jsonb;
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  d := private.fig_route_profit(p_airline_id, 7, coalesce(p_as_of, now()));
  return jsonb_build_object('airline_id', p_airline_id, 'as_of', d -> 'as_of', 'changes', d -> 'fare_changes');
end
$function$;

-- every figure for every airline of a world, in one document, for the scripts (export_for_report('figures'))
create or replace function private.fig_export(p_world_id bigint, p_as_of timestamptz)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
begin
  return jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of),
    'airline_cards', private.fig_airline_cards(p_world_id, p_as_of),
    'growth_signals', private.fig_growth_signals(p_world_id, p_as_of),
    'hub_progress', private.fig_hub_progress(p_world_id, p_as_of),
    'capture_status', private.fig_capture_status(p_world_id, p_as_of),
    'airlines', (select coalesce(jsonb_agg(jsonb_build_object(
        'airline_id', al.airline_id, 'code', al.iata_code, 'name', al.name,
        'cash_forecast', private.fig_cash_forecast(al.airline_id, '[]'::jsonb, p_as_of),
        'airline_profit', private.fig_fin_stats(al.airline_id, p_as_of) -> 'days',
        'route_profit', jsonb_build_object('1', r1.d - 'aircraft' - 'fare_changes', '3', r3.d - 'aircraft' - 'fare_changes',
                                           '7', r7.d - 'aircraft' - 'fare_changes'),
        'aircraft_profit', jsonb_build_object('1', r1.d -> 'aircraft', '3', r3.d -> 'aircraft', '7', r7.d -> 'aircraft'),
        'fare_changes', r7.d -> 'fare_changes') order by al.ord), '[]'::jsonb)
        from private.fig_airlines(p_world_id) al
        -- offset 0 keeps each document worked out once (folded into the outer query, each use would work it out again)
        cross join lateral (select private.fig_route_profit(al.airline_id, 1, p_as_of) as d offset 0) r1
        cross join lateral (select private.fig_route_profit(al.airline_id, 3, p_as_of) as d offset 0) r3
        cross join lateral (select private.fig_route_profit(al.airline_id, 7, p_as_of) as d offset 0) r7));
end
$function$;

-- ============================================================ 11. export_for_report(): kind 'figures' for the scripts
-- As 20261012180000_rules_input.sql left it, with the one new kind.
create or replace function public.export_for_report(p_secret text, p_kind text, p_arg text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
    -- today's two documents, built from the tables by the adapter's getters (design §8)
    return jsonb_build_object('state', (public.planner_state_get() ->> 'json')::jsonb,
                              'loads', (select coalesce(jsonb_object_agg(g.month, g.json::jsonb), '{}'::jsonb) from public.planner_loads_get() g));
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

-- ============================================================ 12. access (design §8): staff call the public functions;
-- the builders are nobody's to call from outside the database
do $grants$
declare f text;
begin
  foreach f in array array[
    'private.fig_world(bigint)', 'private.fig_airline_world(bigint)', 'private.fig_num(bigint, bigint, text)',
    'private.fig_flag(bigint, bigint, text)', 'private.fig_home(bigint)', 'private.fig_airlines(bigint)', 'private.fig_eq_off(text)', 'private.fig_ts(timestamptz)',
    'private.fig_type_key(text)', 'private.fig_freqs(bigint, bigint)', 'private.fig_flights_on(bigint, date, date)',
    'private.fig_load_values(bigint, timestamptz, date, date)', 'private.fig_day_captured(bigint, date, timestamptz)',
    'private.fig_load_days(bigint, timestamptz, date, date)', 'private.fig_day_ops(bigint, timestamptz, date, date)',
    'private.fig_patterns(bigint, timestamptz)', 'private.fig_ops_recent(bigint, timestamptz)', 'private.fig_events(bigint, timestamptz, bigint)',
    'private.fig_order_cabin(bigint, bigint)', 'private.fig_lease_weeks(timestamptz, timestamptz)', 'private.fig_fits(timestamptz[], numeric[], timestamptz, integer, numeric, numeric, numeric)',
    'private.fig_lease_map(bigint, timestamptz)',
    'private.fig_cash_forecast(bigint, jsonb, timestamptz, jsonb)', 'private.fig_route_profit(bigint, integer, timestamptz)',
    'private.fig_cash_days(bigint, timestamptz)', 'private.fig_capex(bigint, date, date)', 'private.fig_fin_stats(bigint, timestamptz, jsonb)',
    'private.fig_group_today(bigint, timestamptz)', 'private.fig_hub_progress(bigint, timestamptz)',
    'private.fig_capture_status(bigint, timestamptz)', 'private.fig_growth_signals(bigint, timestamptz)',
    'private.fig_airline_cards(bigint, timestamptz)', 'private.fig_export(bigint, timestamptz)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
  foreach f in array array[
    'public.cash_forecast(bigint, jsonb, timestamptz)', 'public.airline_cards(bigint, timestamptz)',
    'public.airline_profit(bigint, timestamptz)', 'public.route_profit(bigint, integer, timestamptz)',
    'public.aircraft_profit(bigint, integer, timestamptz)', 'public.growth_signals(bigint, timestamptz)',
    'public.hub_progress(bigint, timestamptz)', 'public.capture_status(bigint, timestamptz)', 'public.fare_changes(bigint, timestamptz)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;
revoke all on function public.export_for_report(text, text, text) from public, anon, authenticated;
grant execute on function public.export_for_report(text, text, text) to anon, authenticated;

-- ============================================================ 13. descriptions (decision #10)
comment on function public.cash_forecast(bigint, jsonb, timestamptz) is 'Cash, next 14 days, and when an airline can order (manual §3; decision #19, design §8; the old planner''s cashForecast, flightsPerDay, leaseM, orderNow and fcNext). From the airline''s latest balance captured in the 7 days to p_as_of (cash, cash_at): flight profit a day (profit a flight over the last 24 hours of the bank statement × planned flights a day; status missing with fewer than 5 flights, no capture without a balance); every payment the events page lists for the 14 days after the capture, each in the first week repeated a week later beyond what the game lists (payments, repeat true), at the airline''s home airport (its main base); the balance at each payment and on each of the 14 days (points), the lowest point and the payment that makes it; for each type the airline may buy (airline_aircraft_types) its price with the cabin it would get, its weekly lease (the highest leasing payment seen for the type, else lease_estimate_pct of its price) and the first day it can be ordered keeping order_cushion in hand with its own lease from 7 days after it is ordered (safe_day 0 to 14, or null; count_today: how many at once today, up to 9); can_order_now and next_order. p_orders, a list of {"type" or "aircraft_type_id", "count"}: whether ordering them all now stays safe, each with its own lease, and the lowest point after (orders_tested). Money in millions of AS$, moments in UTC. Staff only; runs as owner and checks the caller itself.';
comment on function public.airline_cards(bigint, timestamptz) is 'Review''s card for each of our active airlines in a world (the default world when null), in display order (decision #19, design §8; the old planner''s finStats, renderFinance and fcNext): profit a day over the last 7 days of reported cash (an early read over fewer, early true), per aircraft, return on fleet a week, an aircraft pays back in and funds a new aircraft every (days), fleet, on order, flights a day and how many more than a week ago, average load over 7 days, next_order and can_order_now (cash_forecast()); and group_today (groupOverviewHtml): per airline cash, flight profit a day, this week''s leases and week-end closing per day, net, and aircraft arrived but not yet flying with their leases a day (group_today_shown once any airline has flight profit). No group totals (manual §1). Money in millions of AS$. Staff only; runs as owner and checks the caller itself.';
comment on function public.airline_profit(bigint, timestamptz) is 'Profit for each day between captures for one airline (decision #19, design §8; the old planner''s finSeries, finStats, capexIn and dayOps): each reported cash date (the capture''s balance rounded to 0.01M, or a figure typed in cash_entries) with the change in cash plus that period''s order payments (orders and cabins; losses stay in profit), per day over the days between, and the aircraft, flights and average load flown that day; with the 7-day profit a day. Money in millions of AS$. Staff only; runs as owner and checks the caller itself.';
comment on function public.route_profit(bigint, integer, timestamptz) is 'Each route''s profit over the last p_days (1, 3 or 7; decision #19, design §8; the old planner''s routeProfit): every bank-statement block with one route, matched to the nearest loads row of that route departing within 31 minutes, grouped by the route as the airline has it: flights, profit, income, margin, profit a flight and a week (× flights a week planned), average economy, business and cargo load and economy fare, departures sold out and their share, and the mark (add a flight, raise fares, fix or reduce, losing money, hold) from the growth_* settings, with why; plus how many flights, how many matched to loads, blocks with several routes (mixed), and the average flight''s income and costs. Money in millions of AS$. Staff only; runs as owner and checks the caller itself.';
comment on function public.aircraft_profit(bigint, integer, timestamptz) is 'Each aircraft''s flight profit a day over the last p_days (decision #19, design §8; routeProfit''s aircraft): its average captured flight × its scheduled flights a day, plus its statement lines with no route spread over the days captured, its lease a day (the last leasing payment the events page lists for it ÷ 7) and the net, with its type and routes, most profitable after lease first. Money in millions of AS$. Staff only; runs as owner and checks the caller itself.';
comment on function public.growth_signals(bigint, timestamptz) is 'The Check screen''s growth lists across our airlines in a world (the default world when null; decision #19, design §8; the old planner''s capSignalsHtml and patterns): from route_profit() and aircraft_profit() over growth_window_days, ready for another flight (mark add, by profit a week), raise fares (by flights), fix or reduce (losing or fix, by profit a flight) and aircraft losing money after their lease (by net); and the load patterns: each route''s departures over the load window (load_window_days, ending two days ahead, leaving out each rotation''s first load_leeway_days) by load band, marked cut, watch, add or hold from the pattern_* settings. Staff only; runs as owner and checks the caller itself.';
comment on function public.hub_progress(bigint, timestamptz) is 'Hubs first (manual §3; decision #19, design §8; the old planner''s hubProgressHtml): for each of our active airlines in a world (the default world when null), its main hub''s departures a week flying and those on plan cards of aircraft not yet filed, against hub_first_departures, and whether it is exempt (hub_first_exempt); and for each of its other bases, from the latest world scan by p_as_of, the busiest rival there and whether it is contested: a rival with more than contested_rival_weekly departures a week at the base, or more than contested_rival_daily a day on a route from it (listed). Staff only; runs as owner and checks the caller itself.';
comment on function public.capture_status(bigint, timestamptz) is 'What the capture collected for each of our airlines in a world (the default world when null; decision #19, design §8; the old planner''s captureBoard): for today and yesterday (UTC dates of p_as_of), when each page kind (loads, statement, events, pnl, balance) last came, how many flights the loads page held for each date (flight numbers, by departure date as the game lists them), which kinds are missing today, and complete, missing or not captured. Moments in UTC. Staff only; runs as owner and checks the caller itself.';
comment on function public.fare_changes(bigint, timestamptz) is 'Economy fare changes seen in an airline''s captures (decision #19, design §8; routeProfit''s fare changes): for each route flown in the last 9 days, each date whose average captured economy fare is more than 1% from the date before, with both fares and the economy load the day before and after, newest first. Staff only; runs as owner and checks the caller itself.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report, gander monthly and the planning library: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planner ({state, loads}: today''s planner_state and planner_loads documents, built from the tables by planner_state_get() and planner_loads_get()); the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); and the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19). Needs the ingest secret.';
comment on function private.fig_world(bigint) is 'The captured figures (#19): the world asked for, or the default world when null; refuses one that doesn''t exist.';
comment on function private.fig_airline_world(bigint) is 'The captured figures (#19): an airline''s world; refuses an airline that doesn''t exist.';
comment on function private.fig_num(bigint, bigint, text) is 'The captured figures (#19): a rule number from settings, the airline''s own value where it has one, else the world''s; refuses one that is missing or not a number.';
comment on function private.fig_flag(bigint, bigint, text) is 'The captured figures (#19): a true-or-false setting, the airline''s own value where it has one, else the world''s; false when neither is set (hub_first_exempt).';
comment on function private.fig_home(bigint) is 'The captured figures (#19): an airline''s home airport, where the game''s events page shows its times (the old planner''s CAP_HOME): its main base, or for an airline with none (Ryanair, exempt from hubs first) airlines.home_airport_code, as the capture uses it.';
comment on function private.fig_airlines(bigint) is 'The captured figures (#19): our active airlines in a world, in display order, each with its code, name, home airport (fig_home) and main base (null for none).';
comment on function private.fig_eq_off(text) is 'The captured figures (#19): the old planner''s eqOff(), an airport''s UTC offset in minutes as the route research gives it (airports.utc_offset, without a world''s correction), 0 when unknown; used for the events page''s times and the loads page''s departures, as the old planner converts them.';
comment on function private.fig_ts(timestamp with time zone) is 'The captured figures (#19): a moment as they give it, UTC to the millisecond (2026-10-12T21:05:00.000Z).';
comment on function private.fig_type_key(text) is 'The captured figures (#19): an aircraft type''s name as the old planner''s leaseM() compares names: upper case, AIRBUS dropped, EMBRAER as E, letters and digits only.';
comment on function private.fig_freqs(bigint, bigint) is 'The captured figures (#19): each rotation as the old planner reads it from planner_state_get(): its airline, route (live when the route is on the airline''s list), the outbound''s local weekdays at the hub and the return''s at the destination, flights a week (flightsPerDay: 2 with a return number, else 1, × the outbound''s days; 7 days with no outbound), its aircraft, launch date and flight numbers. p_airline_id: one airline''s, or null for all.';
comment on function private.fig_flights_on(bigint, date, date) is 'The captured figures (#19): the old planner''s flightsOn(), every scheduled flight departing on each local date in the range, with its airline, number, route, aircraft and its rotation''s launch date.';
comment on function private.fig_load_values(bigint, timestamp with time zone, date, date) is 'The captured figures (#19): planner_loads_get()''s economy loads per flight for local dates in the range, using only the captures and typed entries made by p_as_of (a typed figure wins where it is newer than the day''s capture).';
comment on function private.fig_day_captured(bigint, date, timestamp with time zone) is 'The captured figures (#19): loads_day_captured() as of p_as_of, whether every active airline of ours in the world had been captured for that date by then.';
comment on function private.fig_load_days(bigint, timestamp with time zone, date, date) is 'The captured figures (#19): planner_loads_get()''s day flags for local dates in the range as of p_as_of: done (the one rule, unless a flag typed after the day''s last capture says otherwise) and captured (the day''s source is the capture).';
comment on function private.fig_day_ops(bigint, timestamp with time zone, date, date) is 'The captured figures (#19): the old planner''s dayOps(), per local date and airline, the flights flown (rotations launched by then), the aircraft, and the average load once the day is done (a flight without a load counts as 97.5%; on a captured day only the flights it has).';
comment on function private.fig_patterns(bigint, timestamp with time zone) is 'The captured figures (#19): the old planner''s patterns(), each route''s departures over the load window by load band and its mark (cut, watch, add, hold) from the pattern_* settings. See growth_signals().';
comment on function private.fig_ops_recent(bigint, timestamp with time zone) is 'The captured figures (#19): game_ops_recent as of p_as_of, the airline''s flights, income and costs in the 24 hours before its latest statement line.';
comment on function private.fig_events(bigint, timestamp with time zone, bigint) is 'The captured figures (#19): the events page''s payments as the old planner loads them (CAP.events): debits from the first balance date of the 7 days to p_as_of to 16 days ahead, each at its UTC moment from the airline''s home airport (eqOff), in millions. p_airline_id: one airline''s, or null for all.';
comment on function private.fig_order_cabin(bigint, bigint) is 'The captured figures (#19): the cabin layout an order of a type is priced with (the old planner''s DEFAULT_CABIN): Standard for a low-cost airline, else Leisure, else Comfort; the airline''s market default among two of the same cabin, then the newest.';
comment on function private.fig_lease_weeks(timestamp with time zone, timestamp with time zone) is 'The captured figures (#19): an order''s own lease (manual §3), weekly from 7 days after it arrives, taken as arriving the moment it is ordered: how many of its payments have fallen by a moment.';
comment on function private.fig_fits(timestamp with time zone[], numeric[], timestamp with time zone, integer, numeric, numeric, numeric) is 'The captured figures (#19): cashForecast()''s fits(), whether orders placed at a moment keep the cushion at every forecast point from then on, counting their price and their own weekly lease from 7 days after they are ordered (manual §3).';
comment on function private.fig_lease_map(bigint, timestamp with time zone) is 'The captured figures (#19): the old planner''s leaseM() table, each aircraft type''s highest weekly leasing payment in the world''s captured events by p_as_of (fig_events), keyed as fig_type_key() keys a type. See cash_forecast().';
comment on function private.fig_cash_forecast(bigint, jsonb, timestamp with time zone, jsonb) is 'The captured figures (#19): builds cash_forecast()''s document with no check of its own; p_lease_map: fig_lease_map() for the world when the caller has it already. See cash_forecast().';
comment on function private.fig_route_profit(bigint, integer, timestamp with time zone) is 'The captured figures (#19): builds routeProfit()''s document (routes, aircraft, fare changes, the average flight) with no check of its own. See route_profit(), aircraft_profit() and fare_changes().';
comment on function private.fig_cash_days(bigint, timestamp with time zone) is 'The captured figures (#19): the old planner''s finSeries(), an airline''s cash by date in millions: each capture date''s latest balance rounded to 0.01M (a figure typed in cash_entries wins before the last 7 days), up to p_as_of.';
comment on function private.fig_capex(bigint, date, date) is 'The captured figures (#19): the old planner''s capexIn(), order payments (orders and cabins, not losses) logged after the first date up to the second, in millions.';
comment on function private.fig_fin_stats(bigint, timestamp with time zone, jsonb) is 'The captured figures (#19): builds the old planner''s finStats() for one airline (its card and its profit for each day between captures) with no check of its own; p_ops: dayOps for the world when the caller has it. See airline_cards() and airline_profit().';
comment on function private.fig_group_today(bigint, timestamp with time zone) is 'The captured figures (#19): one airline''s row of the group today (groupOverviewHtml), with no check of its own. See airline_cards().';
comment on function private.fig_hub_progress(bigint, timestamp with time zone) is 'The captured figures (#19): builds hub_progress()''s document with no check of its own. See hub_progress().';
comment on function private.fig_capture_status(bigint, timestamp with time zone) is 'The captured figures (#19): builds capture_status()''s document with no check of its own. See capture_status().';
comment on function private.fig_growth_signals(bigint, timestamp with time zone) is 'The captured figures (#19): builds growth_signals()''s document with no check of its own. See growth_signals().';
comment on function private.fig_airline_cards(bigint, timestamp with time zone) is 'The captured figures (#19): builds airline_cards()''s document with no check of its own. See airline_cards().';
comment on function private.fig_export(bigint, timestamp with time zone) is 'The captured figures (#19): every figure for every airline of a world in one document, for export_for_report(''figures''), with no check of its own.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

-- The market pages, part 2: the route page, the service check, Competition and the weekly report (30 Oct 2026; spec
-- docs/specs/2026-10-30-market-pages-planner.md; brief docs/briefs/2026-10-29-market-pages.md, option C, decided 30 Oct).
--
-- Why (Gitesh, 30 Oct): part 1 (20261030120000_market_pages.sql) reads the game's Market Analysis pages once a week into
-- market_reads, market_fares, market_shares and market_weeks; nothing showed them. This gives the planner and the weekly
-- report what they need from them, and checks the pair's service profile in the game against the planner.
--
-- Adds three functions and replaces three with the same arguments; changes, drops and renames nothing else, so it can be
-- applied from the chat:
--   - private.fig_route_story() (route_story()): three new keys, nothing existing changes. days_by_direction (each UTC day
--     and direction: each cabin's passengers, seats and load, from route_days); rivals.history (each airline's direct
--     departures a week on the pair at each scan since launch, ours included); market (each direction's latest page read
--     in a finished market run: fares by airline and class, the game's passenger shares this week and last, and the
--     pair's seats and price by week; null with no read).
--   - private.fig_competition() (competition()): each market gains game_share (the game's passenger share over its pairs
--     read, weighted by each direction's seats in the latest week; null with no read), and the answer gains market_run
--     and contested (each pair the airline flies where a rival has at least as many departures as ours, with its fares
--     and share each way from the latest read). Nothing else in it changes: openings, threats, contested test, hubs first.
--   - private.fig_export() (export_for_report('figures')): each airline also carries contested and market_run. Money untouched.
--   - private.fig_market_pair(): a pair's fares and share each way in a market run, for contested.
--   - public.market_service_checks(p_airline_id, p_as_of) and private.fig_market_service_checks(): the service check, a
--     captured figure (staff, GET, 30 seconds as the others).
-- Every new key is null or empty while no market run has finished (the tables are empty on live until the first weekly read).

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261030180000_market_pages_planner', true);

-- ============================================================ 1. the route page's figure
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
  v_dirdays jsonb; v_market jsonb;
begin
  select r.world_id, r.airline_id, r.hub_code, r.dest_code, r.removed,
         jsonb_build_object(
           'id', r.id, 'hub', r.hub_code, 'dest', r.dest_code, 'pair', least(r.hub_code, r.dest_code) || '-' || greatest(r.hub_code, r.dest_code),
           'city', coalesce(r.city_override, r.city), 'stars', coalesce(r.stars_override, r.stars),
           'distance_km', coalesce(r.distance_override_km, r.distance_km), 'removed', r.removed,
           -- since 26 Oct no cabin here: the layout is the route's distance's (manual §5), which the route page works out
           -- with the planning library (card.cabinRange), as Routes' header does
           'market', case when mk.id is null then null else jsonb_build_object('id', mk.id, 'name', mk.name, 'layout', mk.layout) end)
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
  -- since 26 Oct a row per direction and cabin: out then back, economy first
  select coalesce(jsonb_agg(e - 'route_id' - 'hub' - 'dest' order by e ->> 'direction' = 'back', e ->> 'cabin' = 'business'), '[]'::jsonb) into v_fares
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

  -- ---------- (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §2) the same days by direction: out from
  -- the hub, back to it; each cabin's passengers, seats and load, for the route page's Load by direction
  select coalesce(jsonb_agg(jsonb_build_object(
           'day', x.day, 'direction', x.dir, 'flights', x.flights,
           'eco_pax', x.eco_pax, 'eco_seats', x.eco_seats, 'eco_load_pct', round(100.0 * x.eco_pax / nullif(x.eco_seats, 0), 1),
           'bus_pax', x.bus_pax, 'bus_seats', x.bus_seats, 'bus_load_pct', round(100.0 * x.bus_pax / nullif(x.bus_seats, 0), 1))
           order by x.day, x.dir = 'back'), '[]'::jsonb)
    into v_dirdays
    from (select d.day, case when d.origin_code = v_hub then 'out' else 'back' end as dir, sum(d.flights)::int as flights,
                 sum(d.eco_pax)::int as eco_pax, sum(d.eco_seats)::int as eco_seats, sum(d.bus_pax)::int as bus_pax, sum(d.bus_seats)::int as bus_seats
            from public.route_days d
           where d.airline_id = al and d.day between v_from and v_latest and d.flights > 0
             and ((d.origin_code = v_hub and d.dest_code = v_dest) or (d.origin_code = v_dest and d.dest_code = v_hub))
             and (d.route_id = p_route_id or d.route_id is null)
           group by 1, 2) x;

  -- ---------- events from the change log: the schedule's saves for this route's rotations and legs (each save, its
  -- txid, one event). Changes made by a migration (data loads and fixes) aren't events. Since 26 Oct the route's own cabin
  -- choice is no event: distance alone decides the cabin (manual §5).
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

  -- the fare plan's rows for the route (fare tests, and the ladder's moves with level_pct)
  select coalesce(jsonb_agg(x.e), '[]'::jsonb) into v_other
    from (select jsonb_build_object(
                   'day', fp.proposed_on, 'kind', 'fare', 'cabin', coalesce(fp.cabin_class, 'economy'), 'level', fp.level_pct,
                   'change_pct', fp.change_pct, 'move', fp.ladder_move, 'dropped', fp.status = 'dropped', 'reason', fp.reason,
                   -- since 26 Oct a ladder row may be one direction's (out from the hub, back to it): its words say which
                   'direction', fp.direction,
                   'words', coalesce(fp.direction || ': ', '') || case when fp.level_pct is not null
                                 then format('%s %s %s%%', coalesce(fp.cabin_class, 'economy'),
                                             case fp.ladder_move when 'up' then 'up to' when 'down' then 'down to' else 'holds at' end, trim_scale(fp.level_pct))
                                 else format('%s %s%s%% fare test', coalesce(fp.cabin_class, 'economy'),
                                             case when coalesce(fp.change_pct, 0) >= 0 then '+' else '−' end, trim_scale(abs(coalesce(fp.change_pct, 0)))) end
                            || case when fp.status = 'dropped' then ', dropped' else '' end) as e
            from public.fare_plan fp
           where fp.route_id = p_route_id and fp.airline_id = al and fp.proposed_on <= v_today) x;

  -- ---------- the scans: the latest finished by the moment (with its schedules, or since 23 Oct its kept rows), and the
  -- week before as competition() picks it (the latest at least 6 days older, else the oldest there is)
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
   order by s.taken_at desc, s.id desc limit 1;
  if v_scan is not null then
    select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= v_scan_at - interval '6 days'
       and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
     order by s.taken_at desc, s.id desc limit 1;
    if v_before is null then
      select s.id, s.taken_at into v_before, v_before_at from public.game_scans s
       where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of and s.id <> v_scan
         and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
       order by s.taken_at, s.id limit 1;
    end if;
  end if;
  -- every finished scan by the moment with its schedules or its kept rows (scan_pair_airlines, since 23 Oct: the week's
  -- kept scan once the monthly archive has taken its schedules), each with the one before it; read: the latest, the week
  -- before, and each scan since launch with the one before it
  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
    window o as (order by s.taken_at, s.id))
  select array_remove(array_agg(distinct z.id), null) into v_ids
    from (select v_scan as id union all select v_before
          union all select sc.id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'
          union all select sc.prev_id from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC') z;

  with sc as (
    select s.id, s.taken_at, lag(s.id) over o as prev_id
      from public.game_scans s
     where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
       and (exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id) or exists (select 1 from public.scan_pair_airlines x where x.scan_id = s.id))
    window o as (order by s.taken_at, s.id)),
  since as (select sc.* from sc where v_launch is not null and sc.taken_at >= v_launch::timestamp at time zone 'UTC'),
  -- each airline's passenger departures a week on the pair, both ways, in each scan read: from its schedules where it
  -- still has them (private.scan_pair_flights()), otherwise from its kept rows (scan_pair_airlines, passenger rows only;
  -- spec docs/specs/2026-10-23-rival-pairs-history.md §3), the same figures; every airline that isn't one of ours is a
  -- rival (competition analysis's rule)
  fl as (
    select f.scan_id, f.airline_id, f.weekly from private.scan_pair_flights(coalesce(v_ids, '{}'::bigint[]), array[v_pair]) f
    union all
    select k.scan_id, k.airline_id, k.weekly_a_to_b + k.weekly_b_to_a
      from public.scan_pair_airlines k
     where k.scan_id = any (coalesce(v_ids, '{}'::bigint[])) and k.a = least(v_hub, v_dest) and k.b = greatest(v_hub, v_dest) and k.passenger
       and not exists (select 1 from public.game_scan_schedules y where y.scan_id = k.scan_id)),
  -- the scans read from their kept rows (weekly points)
  wk as (select s.scan_id from (select unnest(coalesce(v_ids, '{}'::bigint[])) as scan_id) s
          where not exists (select 1 from public.game_scan_schedules y where y.scan_id = s.scan_id)),
  ex as materialized (
    select x.scan_id, x.airline_id, sum(x.weekly)::int as weekly, coalesce(g.kind, 'rival') <> 'ours' as rival,
           coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || x.airline_id) as name
      from fl x
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
  -- each rival's one-stop departures on the pair at each scan read (since 23 Oct, spec
  -- docs/specs/2026-10-23-rival-connections.md §3), both ways, by connecting airport; shown beside direct, never added.
  -- Only the scans they were worked out for (a row in scan_rival_connections_week)
  cs as (select s.scan_id from (select unnest(coalesce(v_ids, '{}'::bigint[])) as scan_id) s
          where exists (select 1 from public.scan_rival_connections_week c where c.scan_id = s.scan_id)
            and not exists (select 1 from wk where wk.scan_id = s.scan_id)),
  cn as materialized (
    select c.scan_id, c.airline_id, coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || c.airline_id) as name,
           c.via, sum(c.weekly_departures)::int as weekly
      from public.scan_rival_connections c join public.airlines ra on ra.id = c.airline_id
     where c.scan_id in (select cs.scan_id from cs)
       and least(c.origin, c.dest) = least(v_hub, v_dest) and greatest(c.origin, c.dest) = greatest(v_hub, v_dest)
     group by 1, 2, 3, 4),
  cr as (select cn.scan_id, cn.airline_id, cn.name, sum(cn.weekly)::int as weekly,
                private.scan_connection_via(jsonb_agg(jsonb_build_object('via', cn.via, 'weekly', cn.weekly))) as via
           from cn group by 1, 2, 3),
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
             'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at))
                                                                 || case when v_scan in (select wk.scan_id from wk) then jsonb_build_object('weekly', true) else '{}'::jsonb end end,
             'week_before', case when v_before is null then null else jsonb_build_object('id', v_before, 'taken_at', private.fig_ts(v_before_at))
                                                                     || case when v_before in (select wk.scan_id from wk) then jsonb_build_object('weekly', true) else '{}'::jsonb end end,
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
                             -- connecting (since 23 Oct): its one-stop departures on the pair in the latest scan, beside weekly
                             || case when exists (select 1 from cs where cs.scan_id = v_scan)
                                     then jsonb_build_object('connecting_weekly', coalesce((select c.weekly from cr c where c.scan_id = v_scan and c.airline_id = lt.airline_id), 0),
                                                             'connecting_via', coalesce((select c.via from cr c where c.scan_id = v_scan and c.airline_id = lt.airline_id), '[]'::jsonb))
                                     else '{}'::jsonb end
                             order by lt.weekly desc, lt.name), '[]'::jsonb) from lt),
             -- our share at each finished scan since launch: the airline's departures in the scan against every rival's
             -- (since 23 Oct) weekly: the point is a week's kept scan read from its kept rows, its schedules archived
             'shares', (select coalesce(jsonb_agg(jsonb_build_object(
                           'scan_id', sh.id, 'taken_at', private.fig_ts(sh.taken_at), 'ours', sh.ours, 'rivals', sh.rivals,
                           'share', round(100.0 * sh.ours / nullif(sh.ours + sh.rivals, 0), 1),
                           'weekly', exists (select 1 from wk where wk.scan_id = sh.id)) order by sh.taken_at, sh.id), '[]'::jsonb) from sh),
             -- (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §2) each airline's direct departures a week on
             -- the pair at each of the same scans, ours (this airline) and every rival, passenger flights only
             'history', (select coalesce(jsonb_agg(jsonb_build_object(
                            'scan_id', s.id, 'taken_at', private.fig_ts(s.taken_at), 'weekly', exists (select 1 from wk where wk.scan_id = s.id),
                            'airlines', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', e.airline_id, 'name', e.name, 'weekly', e.weekly,
                                                                                      'ours', e.airline_id = al)
                                                                   order by e.airline_id = al desc, e.weekly desc, e.name), '[]'::jsonb)
                                           from ex e where e.scan_id = s.id and (e.rival or e.airline_id = al) and e.weekly > 0))
                            order by s.taken_at, s.id), '[]'::jsonb) from since s),
             'weekly_points', (select count(*)::int from sh where exists (select 1 from wk where wk.scan_id = sh.id)),
             'daily_from', case when exists (select 1 from sh join wk on wk.scan_id = sh.id)
                                then (select private.fig_ts(min(sh.taken_at)) from sh where not exists (select 1 from wk where wk.scan_id = sh.id)) end)
           -- connecting (since 23 Oct), only when the latest scan has them worked out: the rivals' one-stop departures on
           -- the pair, those with no direct flight that connect (connecting_only), and each rival's at each scan read
           || case when exists (select 1 from cs where cs.scan_id = v_scan) then jsonb_build_object(
                'connecting_weekly', (select coalesce(sum(c.weekly), 0)::int from cr c where c.scan_id = v_scan),
                'connecting_only', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', c.airline_id, 'name', c.name, 'weekly', 0,
                                                                                  'connecting_weekly', c.weekly, 'connecting_via', c.via)
                                                               order by c.weekly desc, c.name), '[]'::jsonb)
                                       from cr c where c.scan_id = v_scan and not exists (select 1 from lt where lt.airline_id = c.airline_id)),
                'connecting_scans', (select coalesce(jsonb_agg(jsonb_build_object(
                                        'scan_id', s.scan_id, 'taken_at', private.fig_ts(gs.taken_at),
                                        'weekly', (select coalesce(sum(c.weekly), 0)::int from cr c where c.scan_id = s.scan_id),
                                        'airlines', (select coalesce(jsonb_agg(jsonb_build_object('airline_id', c.airline_id, 'name', c.name, 'weekly', c.weekly, 'via', c.via)
                                                                               order by c.weekly desc, c.name), '[]'::jsonb) from cr c where c.scan_id = s.scan_id))
                                        order by gs.taken_at, s.scan_id), '[]'::jsonb)
                                       from cs s join public.game_scans gs on gs.id = s.scan_id))
              else '{}'::jsonb end,
           'used', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'taken_at', private.fig_ts(s.taken_at),
                                                                 'weekly', exists (select 1 from wk where wk.scan_id = s.id)) order by s.taken_at, s.id), '[]'::jsonb)
                      from since s))
    into v_scanpart;

  -- ---------- the market pages (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §2): each direction's
  -- latest page read in a finished market run by the moment, with its fares by airline and class, the game's passenger
  -- shares this week and last, and the pair's seats and price by week; null when neither direction has been read
  with rd as materialized (
    select distinct on (m.origin, m.dest) m.id, m.run_id, m.read_at, m.origin, m.dest, m.share_week, m.service_code,
           m.service_profile_game_id, m.airline_id, r.started_at, r.finished_at,
           case when m.origin = v_hub then 'out' else 'back' end as dir
      from public.market_reads m join public.market_runs r on r.id = m.run_id
     where m.world_id = w and m.ok and r.status = 'done' and m.read_at <= p_as_of
       and ((m.origin = v_hub and m.dest = v_dest) or (m.origin = v_dest and m.dest = v_hub))
     order by m.origin, m.dest, m.read_at desc, m.id desc),
  dirs as (
    select rd.dir, jsonb_build_object(
             'direction', rd.dir, 'from', rd.origin, 'to', rd.dest, 'read_id', rd.id, 'run_id', rd.run_id,
             'read_at', private.fig_ts(rd.read_at), 'week', rd.share_week, 'service_code', rd.service_code,
             'service_profile_game_id', rd.service_profile_game_id, 'read_by', rd.airline_id,
             'fares', (select coalesce(jsonb_agg(jsonb_build_object(
                         'airline_id', f.airline_id, 'code', f.airline_code,
                         'name', coalesce(a.public_name, a.game_name, a.planner_name, f.airline_code), 'ours', coalesce(f.airline_id = al, false),
                         'class', f.service_class, 'flights', f.flights, 'low', f.price_low, 'avg', f.price_avg, 'high', f.price_high,
                         'finished', f.finished, 'sold_out', f.sold_out)
                         order by coalesce(f.airline_id = al, false) desc, coalesce(a.public_name, a.game_name, a.planner_name, f.airline_code), f.airline_code,
                                  array_position(array['Y', 'C', 'F', 'Cargo'], f.service_class)), '[]'::jsonb)
                         from public.market_fares f left join public.airlines a on a.id = f.airline_id
                        where f.read_id = rd.id),
             'shares', (select coalesce(jsonb_agg(jsonb_build_object(
                          'airline_id', s.airline_id, 'name', coalesce(a.public_name, a.game_name, a.planner_name, 'airline ' || s.airline_id),
                          'ours', s.airline_id = al, 'share', s.share_pct, 'change', s.change_pts, 'before', s.share_pct - s.change_pts)
                          order by s.share_pct desc, s.airline_id), '[]'::jsonb)
                          from public.market_shares s join public.airlines a on a.id = s.airline_id
                         where s.read_id = rd.id and s.kind = 'passengers')) as d
      from rd)
  select case when exists (select 1 from rd) then jsonb_build_object(
           'run', (select jsonb_build_object('id', x.run_id, 'started_at', private.fig_ts(x.started_at), 'finished_at', private.fig_ts(x.finished_at))
                     from rd x order by x.read_at desc, x.id desc limit 1),
           'out', (select dirs.d from dirs where dirs.dir = 'out'),
           'back', (select dirs.d from dirs where dirs.dir = 'back'),
           'weeks', (select coalesce(jsonb_agg(jsonb_build_object(
                       'direction', case when k.origin = v_hub then 'out' else 'back' end, 'week', k.week, 'seats', k.seats,
                       'price_per_unit', k.price_per_unit) order by k.week, k.origin = v_dest), '[]'::jsonb)
                       from public.market_weeks k
                      where k.world_id = w and k.read_at <= p_as_of
                        and ((k.origin = v_hub and k.dest = v_dest) or (k.origin = v_dest and k.dest = v_hub)))) end
    into v_market;

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
    'days_by_direction', v_dirdays,
    'weeks', v_weeks,
    'events', (select coalesce(jsonb_agg(x.e order by (x.e ->> 'day')::date desc,
                                          array_position(array['rival', 'fare', 'retimed', 'aircraft changed', 'frequency removed',
                                                               'frequency added', 'launched'], x.e ->> 'kind'),
                                          x.e ->> 'at' desc nulls last, x.e ->> 'words'), '[]'::jsonb)
                 from (select jsonb_array_elements(v_changes) as e
                       union all select jsonb_array_elements(v_other)
                       union all select jsonb_array_elements(v_scanpart -> 'events')
                       union all select jsonb_build_object('day', v_launch, 'kind', 'launched',
                                                           'words', case v_launch_from when 'rotation' then 'launched' else 'first flights in the daily history' end)
                                  where v_launch is not null and v_launch <= v_today) x),
    'rivals', v_scanpart -> 'rivals',
    'market', v_market,
    'scans', jsonb_build_object(
      'latest', v_scanpart #> '{rivals,scan}', 'week_before', v_scanpart #> '{rivals,week_before}', 'since_launch', v_scanpart -> 'used'),
    'notes', jsonb_build_array(
      'Both directions together, from the daily history (route_days): a day is a UTC day, and one with no flights is left out. load_pct is the passengers on the flights whose loads were captured over their seats; profit_per_hour is profit (millions of AS$) over block hours (the scheduled block of the flights that have one). Weeks are 7-day blocks ending on latest_day, newest first.',
      'Events: the schedule''s saves from the change log (one per save; changes a migration made left out; the rotations that are the launch itself not repeated), the fare plan''s rows, and rivals that started or added competition_threat_min_weekly a week between consecutive scans since launch (passenger flights only).',
      'Rivals are every airline in the scan that isn''t one of ours; ours now are the live schedule both ways, ours in a scan the airline''s flights in it.',
      'Connecting (since 23 Oct): each rival''s one-stop departures a week on the pair, both ways, from scan_rival_connections (same airline, from the connecting airport''s minimum connection time to connection_max_wait_h, both legs together at most rival_connection_detour_max times the direct distance, each first flight once), with its top 3 connecting airports; beside weekly, never added to it, to rivals_weekly or to the share. connecting_only: rivals with no direct flight that connect; connecting_scans: each rival''s at each scan read that has them worked out. Absent when the latest scan has none worked out.',
      'Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md): days_by_direction is days by direction (out from the hub, back to it) with each cabin''s passengers, seats and load; rivals.history is each airline''s direct departures a week on the pair (this airline with ours true, and every rival; passenger flights only) at each scan in rivals.shares; market is the game''s Market Analysis pages, each direction''s latest page read in a finished market run (market_reads, fares by airline and class from market_fares with prices in AS$, passenger shares this week with change and before = share − change from market_shares), and weeks the pair''s seats offered and price per unit by calendar week from market_weeks, both directions; null when no page of the pair has been read.',
      'Weekly points (since 23 Oct): a scan whose schedules the monthly archive has taken is read from its kept rows (scan_pair_airlines: the week''s kept scan, the first finished on or after each Saturday, every airline''s departures on every pair, kept for good), the same figures; such a point has weekly true in shares, since_launch and the scans. weekly_points counts them and daily_from is the first point read from full schedules (null when every point is). Before the last month the line is weekly; connections only on scans with their schedules.'));
end
$function$
;

-- ============================================================ 2. Competition: the game's share, the contested pairs
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
            from ro
           where not exists (select 1 from ourall o where o.a = ro.a and o.b = ro.b)
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
             'trunk', o.trunk, 'other_lists', coalesce(to_jsonb(l.codes), '[]'::jsonb))
             -- connecting (since 23 Oct): the rivals' one-stop departures on the pair, beside rivals_weekly, never in it
             || case when v_conn_scan is not null then jsonb_build_object(
                  'connecting_weekly', coalesce(oc.weekly, 0), 'connecting_via', coalesce(oc.via, '[]'::jsonb), 'connecting', coalesce(oc.rivals, '[]'::jsonb))
                else '{}'::jsonb end
             order by o.rank) filter (where o.rank <= v_limit), '[]'::jsonb) as d,
           count(*)::int as n, (count(*) filter (where o.allowed))::int as n_allowed, (count(*) filter (where o.trunk))::int as n_trunks
      from op4 o left join ol l on l.a = o.a and l.b = o.b left join cxp oc on oc.a = o.a and oc.b = o.b),
  left_out as (select count(*)::int as n from op1 where op1.type_id is null),

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
      'Rivals are every airline in the scan that isn''t one of ours; departures a week count each flight''s days, as gscan.py counts them, passenger flights only (freighters left out, as the weekly report counts). Our own now are the airline''s live legs; before, its flights in the week-before scan.',
      'From trunk_month_from to trunk_month_to (November, manual §4) the trunks, pairs between two of our bases (any of our airlines''), come first, shortest first: hubs first isn''t applied to them and no distance leaves one out. Whether a trunk makes sense stays the Scheduling chat''s judgment.',
      'The variant is the default line''s (manual §3): the smallest size the city''s stars allow (1–2 stars small, 3 small or mid, 4 small to large, 5 mid or large), bigger only for reach, the cheapest per seat whose range with a full load covers the distance, among the types the airline may buy; beyond every narrowbody the A350 that is cheapest per seat, and beyond settings.a350_1000_from_km (wide_full_cabin_km under settings here) the one with the most seats.',
      'competitors (the weekly report''s, manual §7): the three rivals with the most departures a week on the city pairs the airline flies (its live legs, both ways) in the latest scan, ties by name; weekly and airports are each one''s whole passenger network in the latest scan, weekly_before in the week-before scan (none when that scan holds no schedule for it), the change against it as a number and a percent. self is the airline on the same terms, from the same scans'' schedules.',
      'fleet (each competitor''s and rival profile''s, since 23 Oct): from its overview page in the latest scan (scan_airline_fleet, scan_airline_profile): overall, on order, average age and its 5 biggest types, with the change in overall and on order against the week-before scan (null when either scan didn''t read its page); null when the latest scan didn''t read it. order_flags: every airline in the latest scan that isn''t one of ours, freighters only left out, with aircraft on order at least rival_orders_flag_pct of its fleet and at least rival_orders_flag_min (kind orders), or on order and no flights in the scan (kind starting); the same list for every airline, each marked on_pairs (it flies one of this airline''s city pairs), at_bases (it departs from one of its hubs or focus cities) and meets (either). No flag feeds the openings, the contested test or the fare pause.',
      'Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §4, §5): each market''s game_share is the game''s own passenger share from the Market Analysis pages read in the latest finished market run (market_run): over each direction of the market''s pairs that was read, the airline''s share (0 where the page doesn''t list it) weighted by the direction''s seats offered in the latest week read (market_weeks; a plain average when no seats are known), with share_before (last week: share − change), pairs_read of pairs, seats and week; beside the scan''s departures share, never replacing it; null when none of its pairs has been read. contested: each city pair the airline flies where a rival has at least as many departures a week as ours in the latest scan (ours from the live legs, the rival with the most), with market: each way, our economy fare against the cheapest rival''s and the game''s passenger share this week and last, from the latest market run (null without a read). The openings, the contested test, hubs first and the threats don''t read them.',
      'connecting (since 23 Oct): each rival''s one-stop departures a week on the airline''s city pairs in the latest scan (scan_rival_connections, worked out at the scan''s finish by private.scan_connections(): same airline, the second flight from the connecting airport''s minimum connection time to connection_max_wait_h after the first lands, both legs together at most rival_connection_detour_max times the direct distance, each first flight counted once). connecting_weekly on each market, each opening (with each rival''s own in connecting), each rival profile and each competitor (with connecting_pairs), each with its top 3 connecting airports (connecting_via); shown beside direct, never added to it: total, share, rivals_weekly, on_pairs and the three biggest competitors (chosen by direct departures) are direct only, and the openings'' order, the contested test, hubs first, the threats and the fare pause don''t read it. Absent when the latest scan has no connections worked out.'));
end
$function$
;

-- ============================================================ 3. the weekly report's figures
CREATE OR REPLACE FUNCTION private.fig_export(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
        'fare_changes', r7.d -> 'fare_changes',
        -- the weekly report's three biggest competitors (manual §7; since 22 Oct): competition()'s, with its scans
        'competitors', cp.d -> 'competitors', 'self', cp.d -> 'self', 'scans', cp.d -> 'scans',
        -- the world's flagged order books (since 23 Oct, spec docs/specs/2026-10-23-rival-fleets.md §5): the weekly report's risks
        'order_flags', cp.d -> 'order_flags',
        -- the market pages (since 30 Oct, spec docs/specs/2026-10-30-market-pages-planner.md §5): the weekly report's contested
        -- pairs with rivals' fares and the game's share, and the latest finished market run
        'contested', cp.d -> 'contested', 'market_run', cp.d -> 'market_run') order by al.ord), '[]'::jsonb)
        from private.fig_airlines(p_world_id) al
        -- offset 0 keeps each document worked out once (folded into the outer query, each use would work it out again)
        cross join lateral (select private.fig_route_profit(al.airline_id, 1, p_as_of) as d offset 0) r1
        cross join lateral (select private.fig_route_profit(al.airline_id, 3, p_as_of) as d offset 0) r3
        cross join lateral (select private.fig_route_profit(al.airline_id, 7, p_as_of) as d offset 0) r7
        cross join lateral (select private.fig_competition(al.airline_id, p_as_of, 0) as d offset 0) cp));
end
$function$
;

-- ============================================================ 4. a contested pair's fares and share (the weekly report)
create or replace function private.fig_market_pair(p_world_id bigint, p_airline_id bigint, p_hub text, p_dest text, p_run_id bigint)
 returns jsonb
 language sql
 stable
 set search_path to ''
as $function$
  -- each direction's page in the run: the airline's economy fare (its average), the cheapest rival's (the lowest average
  -- of any airline that isn't one of ours, a prefix no airline was matched to counting as a rival), and the airline's
  -- passenger share this week and last
  with rd as (
    select m.id, m.origin, m.dest, m.read_at, m.share_week, case when m.origin = p_hub then 'out' else 'back' end as dir
      from public.market_reads m
     where m.run_id = p_run_id and m.ok
       and ((m.origin = p_hub and m.dest = p_dest) or (m.origin = p_dest and m.dest = p_hub))),
  ours as (
    select a.id from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
     where a.world_id = p_world_id and g.kind = 'ours'),
  d as (
    select rd.dir, jsonb_build_object(
             'direction', rd.dir, 'from', rd.origin, 'to', rd.dest, 'read_at', private.fig_ts(rd.read_at), 'week', rd.share_week,
             'ours_eco', o.price_avg,
             'cheapest_rival', case when c.code is not null then jsonb_build_object('airline_id', c.airline_id, 'code', c.code, 'name', c.name, 'eco', c.price_avg) end,
             'vs_cheapest_pct', round(100.0 * (o.price_avg - c.price_avg) / nullif(c.price_avg, 0), 1),
             'share', coalesce(s.share_pct, 0), 'share_before', s.share_pct - s.change_pts, 'change', s.change_pts) as doc
      from rd
      left join public.market_fares o on o.read_id = rd.id and o.service_class = 'Y' and o.airline_id = p_airline_id
      left join lateral (
        select f.airline_id, f.airline_code as code, coalesce(a.public_name, a.game_name, a.planner_name, f.airline_code) as name, f.price_avg
          from public.market_fares f left join public.airlines a on a.id = f.airline_id
         where f.read_id = rd.id and f.service_class = 'Y' and f.price_avg is not null
           and (f.airline_id is null or f.airline_id not in (select ours.id from ours))
         order by f.price_avg, f.airline_code limit 1) c on true
      left join public.market_shares s on s.read_id = rd.id and s.kind = 'passengers' and s.airline_id = p_airline_id)
  select case when exists (select 1 from d) then jsonb_build_object(
           'out', (select d.doc from d where d.dir = 'out'), 'back', (select d.doc from d where d.dir = 'back')) end
$function$;

-- ============================================================ 5. the service check
create or replace function private.fig_market_service_checks(p_world_id bigint, p_airline_id bigint, p_as_of timestamp with time zone)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare v_run record; v_checked int := 0; v_rows jsonb := '[]'::jsonb;
begin
  -- the latest finished market run by the moment
  select r.id, r.started_at, r.finished_at, r.pages_read, r.pages_failed into v_run
    from public.market_runs r
   where r.world_id = p_world_id and r.status = 'done' and r.started_at <= p_as_of
   order by r.started_at desc, r.id desc limit 1;
  if v_run.id is not null then
    with rd as (
      select m.id, m.airline_id, m.origin, m.dest, m.read_at, nullif(btrim(m.service_code), '') as game_code
        from public.market_reads m
       where m.run_id = v_run.id and m.ok and (p_airline_id is null or m.airline_id = p_airline_id)),
    -- the read airline's route on the pair (not removed; one with rotations first, then the oldest)
    ro as (
      select distinct on (rd.id) rd.id as read_id, r.id as route_id, r.hub_code, r.dest_code,
             coalesce(r.distance_override_km, r.distance_km) as own_km
        from rd join public.routes r on r.world_id = p_world_id and r.airline_id = rd.airline_id and not r.removed
                                    and ((r.hub_code = rd.origin and r.dest_code = rd.dest) or (r.hub_code = rd.dest and r.dest_code = rd.origin))
       order by rd.id, exists (select 1 from public.rotations x where x.route_id = r.id) desc, r.id),
    ck as (
      select rd.*, ro.route_id, ro.hub_code, ro.dest_code, a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) as airline_name, a.position,
             -- the distance as the planning library takes it (block.distanceBetween): the airline's own route, else another
             -- route on the pair; no great circle here, so a pair with neither has no distance code
             coalesce(ro.own_km, (select coalesce(r2.distance_override_km, r2.distance_km) from public.routes r2
                                   where r2.world_id = p_world_id and coalesce(r2.distance_override_km, r2.distance_km) is not null
                                     and ((r2.hub_code = rd.origin and r2.dest_code = rd.dest) or (r2.hub_code = rd.dest and r2.dest_code = rd.origin))
                                   order by r2.airline_id = rd.airline_id desc, r2.id limit 1)) as km,
             -- the planner's codes on the legs that way: each rotation's service code on the route with a leg from origin to dest
             (select array_agg(distinct coalesce(nullif(btrim(rt.service_code), ''), 'none') order by coalesce(nullif(btrim(rt.service_code), ''), 'none'))
                from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
               where rt.route_id = ro.route_id and l.origin_code = rd.origin and l.dest_code = rd.dest) as planner_codes
        from rd join ro on ro.read_id = rd.id join public.airlines a on a.id = rd.airline_id),
    wanted as (
      -- the code the distance calls for (manual §4; service.profileFor): an airline's own profile on every route (Ryanair's
      -- R), else the first shared profile whose up_to_km is over the distance, else the last of them
      select ck.*, coalesce(
               (select p.code from public.service_profiles p where p.world_id = p_world_id and p.airline_id = ck.airline_id order by p.id limit 1),
               case when ck.km is not null then coalesce(
                 (select p.code from public.service_profiles p where p.world_id = p_world_id and p.airline_id is null and p.up_to_km is not null
                     and ck.km < p.up_to_km order by p.up_to_km, p.id limit 1),
                 (select p.code from public.service_profiles p where p.world_id = p_world_id and p.airline_id is null and p.up_to_km is not null
                   order by p.up_to_km desc, p.id desc limit 1)) end) as distance_code
        from ck),
    judged as (
      select x.*,
             x.distance_code is not null and x.game_code is distinct from x.distance_code as off_distance,
             exists (select 1 from unnest(coalesce(x.planner_codes, '{}'::text[])) c where c <> coalesce(x.game_code, 'none')) as off_planner
        from wanted x)
    select count(*)::int,
           coalesce(jsonb_agg(jsonb_build_object(
             'route_id', j.route_id, 'airline_id', j.airline_id, 'code', j.iata_code, 'airline', j.airline_name,
             'pair', least(j.origin, j.dest) || '-' || greatest(j.origin, j.dest), 'hub', j.hub_code, 'dest', j.dest_code,
             'from', j.origin, 'to', j.dest, 'direction', case when j.origin = j.hub_code then 'out' else 'back' end,
             'game_code', j.game_code, 'distance_code', j.distance_code, 'distance_km', j.km, 'planner_codes', to_jsonb(coalesce(j.planner_codes, '{}'::text[])),
             'kind', case when j.off_distance then 'distance' else 'planner' end,
             'off_distance', j.off_distance, 'off_planner', j.off_planner, 'read_at', private.fig_ts(j.read_at))
             order by j.off_distance desc, j.position nulls last, j.airline_id, least(j.origin, j.dest), greatest(j.origin, j.dest), j.origin <> j.hub_code)
             filter (where j.off_distance or j.off_planner), '[]'::jsonb)
      into v_checked, v_rows
      from judged j;
  end if;
  return jsonb_build_object(
    'world_id', p_world_id, 'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of),
    'run', case when v_run.id is not null then jsonb_build_object(
             'id', v_run.id, 'started_at', private.fig_ts(v_run.started_at), 'finished_at', private.fig_ts(v_run.finished_at),
             'age_days', round((extract(epoch from p_as_of - v_run.finished_at) / 86400)::numeric, 1),
             'pages_read', v_run.pages_read, 'pages_failed', v_run.pages_failed) end,
    'checked', v_checked,
    'mismatches', v_rows,
    'notes', jsonb_build_array(
      'The service check (spec docs/specs/2026-10-30-market-pages-planner.md §3): each page read in the latest finished market run (one direction of one pair, read with our airline that flies it), on a route of that airline not removed. game_code is the On-Board Service the game shows selected on the pair (market_reads.service_code; null when none). distance_code is the code the route''s distance calls for (manual §4: the airline''s own profile, Ryanair''s R, on every route, else the first shared service_profiles row whose up_to_km is over the distance, else the last), the distance as the planning library takes it (the airline''s own route with any override, else another route on the pair; null when neither has one). planner_codes are the service codes of the route''s rotations with a leg that way (none for a rotation without one).',
      'A row for every direction where the game differs from the distance''s code (kind distance, listed first) or, failing that, from a planner code (kind planner). checked counts the directions looked at; with no finished run, run is null and there is nothing to check.'));
end
$function$;

create or replace function public.market_service_checks(p_airline_id bigint default null, p_as_of timestamp with time zone default now())
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
 set statement_timeout to '30s'
 set plan_cache_mode to 'force_custom_plan'
as $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_market_service_checks(
    case when p_airline_id is null then private.fig_world(null) else private.fig_airline_world(p_airline_id) end, p_airline_id, coalesce(p_as_of, now()));
end
$function$;

-- ============================================================ 6. who may call them
revoke all on function private.fig_market_pair(bigint, bigint, text, text, bigint) from public, anon, authenticated, service_role;
revoke all on function private.fig_market_service_checks(bigint, bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.market_service_checks(bigint, timestamptz) from public, anon, authenticated;
grant execute on function public.market_service_checks(bigint, timestamptz) to authenticated;

-- ============================================================ 7. descriptions
comment on function private.fig_market_pair(bigint, bigint, text, text, bigint) is 'The market pages, part 2 (spec docs/specs/2026-10-30-market-pages-planner.md §5), for competition()''s contested pairs, with no check of its own: for one pair (p_hub, p_dest) and one market run, each direction''s page read (out from p_hub, back to it): the airline''s economy fare (its Y price_avg in market_fares), the cheapest rival''s (the lowest Y price_avg of any airline that isn''t one of ours; a prefix no airline was matched to counts as a rival; with airline_id, code, name, eco), vs_cheapest_pct (ours against it, %), and the airline''s passenger share this week (0 when the page doesn''t list it), share_before (share − change) and change in points, with the read''s time and week. Answers {out, back}, either null when that direction wasn''t read; null when neither was.';
comment on function private.fig_market_service_checks(bigint, bigint, timestamptz) is 'The service check''s builder (spec docs/specs/2026-10-30-market-pages-planner.md §3), for market_service_checks(), with no check of its own: in p_world_id''s latest finished market run by p_as_of, each page read (of p_airline_id''s pairs, or every airline''s when null) against the code its route''s distance calls for (manual §4, service_profiles as the planning library reads them) and the planner''s codes on the legs that way (the route''s rotations). Answers world_id, airline_id, as_of, run (id, started_at, finished_at, age_days, pages_read, pages_failed; null with no finished run), checked, mismatches (one row per direction where the game differs: route_id, airline_id, code, airline, pair, hub, dest, from, to, direction, game_code, distance_code, distance_km, planner_codes, kind distance or planner, off_distance, off_planner, read_at; distance first) and notes.';
comment on function public.market_service_checks(bigint, timestamptz) is 'The service check (since 30 Oct; spec docs/specs/2026-10-30-market-pages-planner.md §3), a captured figure: for each pair and direction read in the latest finished market run (the game''s Market Analysis pages, capture 1.9), our service profile in the game (market_reads.service_code) against (a) the code the route''s distance calls for (manual §4: S1 under 800 km, S2 800 to 1,500, S3 over 1,500, Ryanair R; from service_profiles as the planning library reads them) and (b) the service codes of the planner''s legs that way (the route''s rotations). A row for every mismatch, the game against the distance first, then the game against the planner: the pair, direction, airline, the game''s code, the distance''s code and the planner''s codes, with the route to link to (private.fig_market_service_checks()). p_airline_id: one airline''s pairs, or every airline''s in the default world when null. With no finished run (none read yet), run is null and mismatches empty. Read by Today (needs attention''s Service in the game), the Systems board''s market line and the route page''s header. Staff only; runs as owner and checks the caller itself, 30 seconds at most and each call planned afresh, as the other captured figures. Read with GET.';

-- route_story(), its builder, competition(), its builder, fig_export() and export_for_report() keep every word of their
-- descriptions as they stand (older tests read them); the market part is added at the end, once
do $describe$
declare x record; d text;
begin
  for x in select * from (values
      ('public.route_story(bigint, timestamptz)', 'market-pages-planner.md §2) also',
       ' Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §2) also: days_by_direction (each UTC day and direction, out from the hub and back to it: flights, eco_ and bus_ passengers, seats and load_pct, from route_days, the same days as days); rivals.history (at each scan in rivals.shares: scan_id, taken_at, weekly, and airlines, each airline''s direct departures a week on the pair, this airline with ours true and every rival, passenger flights only, none with 0); market (null when neither direction of the pair has been read; else run, the latest finished market run read, out and back, each direction''s latest page read in a finished run by the moment: from, to, read_id, run_id, read_at, week, service_code, service_profile_game_id, read_by, fares (market_fares by airline and class: airline_id, code, name, ours, class, flights, low, avg, high, finished, sold_out; ours first) and shares (market_shares, passengers: airline_id, name, ours, share, change, before), or null; and weeks, the pair''s seats and price_per_unit by calendar week, both directions, from market_weeks).'),
      ('private.fig_route_story(bigint, timestamptz)', 'market-pages-planner.md §2',
       ' Since 30 Oct also days_by_direction, rivals.history and market (spec docs/specs/2026-10-30-market-pages-planner.md §2).'),
      ('public.competition(bigint, timestamptz, integer)', 'market-pages-planner.md §4',
       ' Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §4, §5): each market has game_share, the game''s own passenger share from the market pages (share, share_before, change, pairs_read of pairs, seats, week, run_id, read_at; the airline''s share on each direction of the market''s pairs read in the latest finished market run, weighted by the direction''s seats offered in the latest week read), beside the scan''s departures share and never replacing it; null when none of its pairs has been read. market_run is that run (id, started_at, finished_at; null with none), and contested lists each city pair the airline flies where a rival has at least as many departures a week as ours in the latest scan (pair, route_id, hub, dest, ours, rival_id, rival, rival_weekly), with market: each way our economy fare against the cheapest rival''s and the game''s passenger share this week and last (private.fig_market_pair(); null without a read).'),
      ('private.fig_competition(bigint, timestamptz, integer)', 'market-pages-planner.md §4',
       ' Since 30 Oct also game_share on each market, market_run and contested (spec docs/specs/2026-10-30-market-pages-planner.md §4, §5).'),
      ('private.fig_export(bigint, timestamptz)', 'market-pages-planner.md §5',
       ' Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §5) each airline also carries competition()''s contested (its contested pairs with rivals'' fares and the game''s share each way) and market_run, for the weekly report''s competition section; money untouched.'),
      ('public.export_for_report(text, text, text)', 'market-pages-planner.md §5',
       ' Since 30 Oct (spec docs/specs/2026-10-30-market-pages-planner.md §5) figures also carry, per airline, contested (competition()''s contested pairs with rivals'' fares and the game''s passenger share each way, from the latest market run) and market_run.')
    ) v(f, mark, more) loop
    d := obj_description(x.f::regprocedure, 'pg_proc');
    if position(x.mark in coalesce(d, '')) = 0 then
      execute format('comment on function %s is %L', x.f, coalesce(d, '') || x.more);
    end if;
  end loop;
end
$describe$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

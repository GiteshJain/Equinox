-- Route page: the cabin by distance (26 Oct 2026; manual §5, Building chat, Gitesh).
--
-- Why: since 26 Oct distance alone decides the cabin (manual §5): no market layout or route choice overrides it. The
-- route page still showed "the cabin it calls for" from route_story()'s coalesce(routes.cabin_choice, markets.layout),
-- and its Events listed changes to routes.cabin_choice. The planner now works out the route's layout from its distance
-- with the planning library (card.cabinRange), as Routes' header does (one home for the rule, decision #19).
--
-- Replaces one function with the same arguments; drops and renames nothing, so it can be applied from the chat:
--   1. private.fig_route_story() (route_story()): route.cabin is gone (route.market keeps its layout), and a change to
--      routes.cabin_choice is no longer an event. Every other figure and event is as before.
--   2. route_story()'s description says so. The grants stay as they were.

select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: route page cabin by distance', true);

-- ============================================================ 1. route_story(): no cabin, no cabin events
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
    'scans', jsonb_build_object(
      'latest', v_scanpart #> '{rivals,scan}', 'week_before', v_scanpart #> '{rivals,week_before}', 'since_launch', v_scanpart -> 'used'),
    'notes', jsonb_build_array(
      'Both directions together, from the daily history (route_days): a day is a UTC day, and one with no flights is left out. load_pct is the passengers on the flights whose loads were captured over their seats; profit_per_hour is profit (millions of AS$) over block hours (the scheduled block of the flights that have one). Weeks are 7-day blocks ending on latest_day, newest first.',
      'Events: the schedule''s saves from the change log (one per save; changes a migration made left out; the rotations that are the launch itself not repeated), the fare plan''s rows, and rivals that started or added competition_threat_min_weekly a week between consecutive scans since launch (passenger flights only).',
      'Rivals are every airline in the scan that isn''t one of ours; ours now are the live schedule both ways, ours in a scan the airline''s flights in it.',
      'Connecting (since 23 Oct): each rival''s one-stop departures a week on the pair, both ways, from scan_rival_connections (same airline, from the connecting airport''s minimum connection time to connection_max_wait_h, both legs together at most rival_connection_detour_max times the direct distance, each first flight once), with its top 3 connecting airports; beside weekly, never added to it, to rivals_weekly or to the share. connecting_only: rivals with no direct flight that connect; connecting_scans: each rival''s at each scan read that has them worked out. Absent when the latest scan has none worked out.',
      'Weekly points (since 23 Oct): a scan whose schedules the monthly archive has taken is read from its kept rows (scan_pair_airlines: the week''s kept scan, the first finished on or after each Saturday, every airline''s departures on every pair, kept for good), the same figures; such a point has weekly true in shares, since_launch and the scans. weekly_points counts them and daily_from is the first point read from full schedules (null when every point is). Before the last month the line is weekly; connections only on scans with their schedules.'));
end
$function$
;

-- ============================================================ 2. access and description
revoke all on function private.fig_route_story(bigint, timestamptz) from public, anon, authenticated, service_role;
comment on function public.route_story(bigint, timestamptz) is 'A route''s story since launch (spec docs/specs/2026-10-21-route-page.md §2), as of p_as_of: the planner''s route page (/planner/performance/<code>/<route>), and the Scheduling chat''s "how has this route done since launch, and what changed on it". The route is its airline''s hub and destination; both directions are counted together. route: id, hub, dest, pair, city, stars, distance_km (overrides applied), market (id, name, layout), removed, airline (id, code, name), launched (its earliest rotation''s launch day, as route profit and the fare ladder find a route''s age, else its first day in route_days; launched_from rotation or history; launched_days). now: departures a week each way from the live schedule (out from the hub, back), rotations, the aircraft types flying it with how many aircraft, fares (fare_ladder()''s rows for the route, since 26 Oct one per direction and cabin, out before back and economy first, each with direction, from and to: level, steps, this Saturday''s move, new_level, reason, planned, applied, to_plan, fix, fare_index and the rest), launch_pct and week_of. latest_day: the airline''s latest day in the daily history by the moment. days: one row per UTC day with flights, from launch or the last 90 days if longer to latest_day (route_days, both directions; rows of no route matched by the airports): flights, passengers, seats, load_pct (passengers on the flights whose loads were captured ÷ their seats), eco_ and bus_ passengers, seats and load_pct, eco_fare and bus_fare (weighted by passengers), revenue, costs and profit (millions of AS$), block_hours and profit_per_hour (profit ÷ block hours). weeks: the same in 7-day blocks ending on latest_day (from, to, days with flights), newest first, at most 13. events, newest first, each with day, kind and words: launched; frequency added, frequency removed, aircraft changed and retimed from change_log on rotations and flight_legs (one per save, its txid; a save''s rotations that are the launch itself and a migration''s changes left out); fare, each fare_plan row (cabin, level or change_pct, move, dropped, and since 26 Oct its direction, named first in its words, "out: economy up to 105%"); rival, a rival that started on the pair or added settings.competition_threat_min_weekly departures a week between consecutive finished scans since launch with their schedules (private.scan_pair_flights(), passenger flights only, as competition_threats()). rivals: from the latest finished scan (scan) with the week-before scan (week_before, as competition() picks it), every rival flying the pair either way with its departures a week, before and change; ours (the live schedule, both ways), rivals_weekly and our share; ours_before, rivals_before and share_before (the airline''s flights in the week-before scan, as competition()''s me_then); shares, our share at each finished scan since launch (scan_id, taken_at, ours, rivals, share). scans: latest, week_before and since_launch with their dates. notes say how it reads. Staff only; runs as owner and checks the caller itself. Read with GET. Connecting (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): in rivals, each rival on the pair has connecting_weekly and connecting_via (its one-stop departures a week on the pair in the latest scan, both ways, and its top 3 connecting airports), beside weekly and never added to it, rivals_weekly or the share; rivals also has connecting_weekly (every rival''s), connecting_only (the rivals with no direct flight that connect) and connecting_scans (each rival''s connecting departures and airports at each scan read that has them worked out). Absent when the latest scan has none worked out. Weekly points (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §3): a scan whose schedules the monthly archive has taken is read from scan_pair_airlines (the week''s kept scan, kept for good; passenger rows), the same figures, and marked weekly true in rivals.shares, scans.since_launch and the scan refs; rivals.weekly_points counts them and rivals.daily_from is the first point read from full schedules. Connections only on the scans with their schedules. No cabin (since 26 Oct, manual §5): the route''s layout is its distance''s, worked out by the planner with the planning library (card.cabinRange), and a change to routes.cabin_choice is no event.';

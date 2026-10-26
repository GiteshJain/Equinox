-- The fare ladder per direction (26 Oct 2026; manual's "Decided, not yet built"; spec
-- docs/specs/2026-10-26-fare-ladder-per-direction.md, brief docs/briefs/2026-10-26-fare-ladder-per-direction.md, option A,
-- Gitesh).
--
-- Why: today each cabin of each route has one level, judged on both directions' flights together. Passengers book each
-- direction separately (manual §9) and the game's Ticket price adjustment already changes one direction at a time. In the
-- week to 26 Oct, 24 of 266 routes had one direction sell out every economy flight while the route as a whole held.
--
-- Adds a column and replaces functions with the same arguments; drops and renames nothing, so it can be applied from
-- the chat:
--   1. fare_plan.direction: 'out' (from the route's hub) or 'back' (to it), null for both directions (every row written
--      before this build), described. A direction with no row of its own reads the latest both-directions row, so each
--      direction starts at the route's level and nothing moves on day one.
--   2. private.fig_fare_ladder() (so fare_ladder(), and what reads it: capture_fare_actions(), the briefing, route_story()
--      and the plan card's fare levels): one row per route, cabin and direction, each judged on its own direction's
--      flights (up, hold, down, the hold after a step down, under launch's jumps and the set-back); a new route, the
--      capacity hold, the rival pause and the 60% floor stay the whole route's. Each row gains direction, from, to and
--      load; one action per direction.
--   3. private.fig_fare_plan() (fare_plan_status()): a row with a direction is seen by that direction's day average fare.
--   4. private.capture_fare_actions_doc() (capture_fare_actions()): an action matches its direction's rows.
--   5. private.fig_route_story() (route_story()): a fare plan row's event names its direction.
--   6. private.briefing_doc() (the briefing): the fare ladder's rows per direction.
--   The grants stay as they were.

select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: fare ladder per direction', true);

-- ============================================================ 1. the fare plan's direction
alter table public.fare_plan add column direction text;
alter table public.fare_plan add constraint fare_plan_direction_check check (direction in ('out', 'back'));
comment on column public.fare_plan.direction is 'The fare ladder''s direction (since 26 Oct, manual §5): out (from the route''s hub) or back (to it); null for both directions, as every row written before the ladder went per direction. A direction''s level is its latest row, or the latest both-directions row if that is later';

-- ============================================================ 2. the fare ladder, per direction
CREATE OR REPLACE FUNCTION private.fig_fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
  v_week date;
  v_step numeric; v_up numeric; v_down numeric; v_min numeric; v_hold numeric; v_cap numeric; v_launch numeric; v_floor numeric;
  v_new_days numeric; v_added_days numeric;
  -- every route was at its launch level on 21 Oct 2026 (Gitesh; manual §5): each route's fare that day is its baseline
  v_base_day constant date := date '2026-10-21';
  v_scan bigint; v_scan_at timestamptz;
  v_rows jsonb; v_actions jsonb := '[]'::jsonb; v_n int := 0;
  v_r record; v_sets jsonb; v_change jsonb; v_lv numeric; v_words text;
  -- the fare ladder under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md)
  v_ul_load numeric; v_ul_days numeric; v_ul_min numeric; v_ul_decide numeric; v_ul_levels numeric[]; v_ul_below numeric[]; v_ul_j jsonb; v_ul_span text;
begin
  v_step := private.fig_num(w, p_airline_id, 'fare_ladder_step_pts');
  v_up := private.fig_num(w, p_airline_id, 'fare_ladder_up_share');
  v_down := private.fig_num(w, p_airline_id, 'fare_ladder_down_share');
  v_min := private.fig_num(w, p_airline_id, 'fare_ladder_min_departures');
  v_hold := private.fig_num(w, p_airline_id, 'fare_ladder_hold_weeks');
  v_cap := private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_launch := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  v_added_days := private.fig_num(w, p_airline_id, 'fare_ladder_capacity_hold_days');
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
  -- under launch: a cabin at launch averaging under fare_under_launch_load_pct full over fare_under_launch_days jumps to
  -- the first of fare_under_launch_levels, holds that many days and is judged on its revenue a flight (an airline's own
  -- row wins over the world's, as fig_num() reads them)
  v_ul_load := private.fig_num(w, p_airline_id, 'fare_under_launch_load_pct');
  v_ul_days := private.fig_num(w, p_airline_id, 'fare_under_launch_days');
  v_ul_min := private.fig_num(w, p_airline_id, 'fare_under_launch_min_flights');
  v_ul_decide := private.fig_num(w, p_airline_id, 'fare_under_launch_decide_load_pct');
  select s.value into v_ul_j from public.settings s
   where s.world_id = w and s.key = 'fare_under_launch_levels' and (s.airline_id is null or s.airline_id = p_airline_id)
   order by s.airline_id nulls last limit 1;
  if v_ul_j is null or jsonb_typeof(v_ul_j) <> 'array'
     or exists (select 1 from jsonb_array_elements(v_ul_j) e where jsonb_typeof(e) <> 'number') then
    raise exception 'setting fare_under_launch_levels is missing or isn''t a list of numbers' using errcode = '22023';
  end if;
  select array_agg((e #>> '{}')::numeric order by i) into v_ul_levels from jsonb_array_elements(v_ul_j) with ordinality as t(e, i);
  v_ul_span := case when v_ul_days > 0 and v_ul_days % 7 = 0
                    then format('%s week%s', trim_scale(v_ul_days / 7), case when v_ul_days = 7 then '' else 's' end)
                    else format('%s days', trim_scale(v_ul_days)) end;
  -- the jump levels under this airline's launch, in order (a level at or above launch is never a jump)
  select array_agg(u.l order by u.i) into v_ul_below from unnest(v_ul_levels) with ordinality as u(l, i) where u.l < v_launch;
  -- this Saturday: the latest Saturday on or before the moment's UTC date. A move recorded on the fare plan since then is
  -- this week's (on the fare plan already); the levels before it are the ones the week's move starts from
  v_week := v_today - ((extract(isodow from v_today)::int + 1) % 7);
  -- the latest finished world scan by then with its schedules: who else flies each pair (the 60% floor)
  select s.id, s.taken_at into v_scan, v_scan_at from public.game_scans s
   where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
     and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
   order by s.taken_at desc, s.id desc limit 1;

  with
  ro as (select r.id, r.hub_code, r.dest_code from public.routes r where r.airline_id = p_airline_id and r.world_id = w and not r.removed),
  fq as materialized (select * from private.fig_freqs(w, p_airline_id)),
  -- a route's age: its earliest rotation's launch day, as route profit has it (growth_new_route_days)
  age as (select f.route_id, min(f.launched_on) as first_day from fq f group by f.route_id),
  -- its newest live rotation's launch day: a flight added to a route already flown (manual §5, since 21 Oct)
  added as (select f.route_id, max(f.launched_on) as last_day from fq f where f.live group by f.route_id),
  -- business seats on an aircraft flying one of the route's rotations
  biz as (select distinct f.route_id from fq f
            join public.flight_legs fl on fl.rotation_id = f.rotation_id
            join public.aircraft a on a.id = fl.aircraft_id
            join public.cabin_configs cc on cc.id = a.cabin_config_id
           where f.live and coalesce(cc.business_seats, 0) > 0),
  -- every captured loads row of the airline by then (one per date and flight number, the latest), with its route as the
  -- airline's list has it, either way round (as route profit matches them: route_id is often empty), and since 26 Oct its
  -- direction: out from the route's hub, back to it
  lf as materialized (
    select coalesce(r1.id, r2.id) as route_id, case when r1.id is not null then 'out' else 'back' end as dir, x.*
      from (select distinct on (f.game_date, f.flight_no) f.game_date, f.origin_code as o, f.dest_code as d, f.dep_at,
                   f.eco_pct, f.eco_fare, f.bus_pct, f.bus_seats, f.bus_fare, f.eco_pax, f.bus_pax
              from public.game_flights f
             where f.airline_id = p_airline_id and f.flight_no is not null and f.loads_captured_at <= p_as_of and f.game_date <= v_today
             order by f.game_date, f.flight_no, f.id desc) x
      left join ro r1 on r1.hub_code = x.o and r1.dest_code = x.d
      left join ro r2 on r2.hub_code = x.d and r2.dest_code = x.o
     where coalesce(r1.id, r2.id) is not null),
  -- by cabin: economy on every row with its load, business on flights with business seats; each with its direction (o),
  -- and since 23 Oct its passengers (revenue a flight, under launch: pax × fare)
  lc as materialized (
    select lf.route_id, 'economy'::text as cabin, lf.dir, lf.o, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare, lf.eco_pax as pax,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') as at from lf where lf.eco_pct is not null
    union all
    select lf.route_id, 'business', lf.dir, lf.o, lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare, lf.bus_pax,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known), per direction since
  -- 26 Oct, with the direction's average load in the cabin
  st as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare,
                avg(lc.pct) as load
           from lc
          where lc.at >= p_as_of - interval '7 days' and lc.at < p_as_of
          group by lc.route_id, lc.cabin, lc.dir),
  -- the fare index's baseline (manual §5, since 21 Oct). Each captured day's fare by cabin and direction: the flights'
  -- lowest (one the game priced otherwise, as a new flight at the default price on a Ryanair route, sits above it), else
  -- the daily history's average fare in that cabin (route_days, kept for good once the flights are archived): economy's,
  -- and since 22 Oct business's, on a day with business passengers
  dd as (select lc.route_id, lc.cabin, lc.o, lc.game_date as day, min(lc.fare) as fare from lc where lc.fare > 0 group by 1, 2, 3, 4),
  hd as (select coalesce(r1.id, r2.id) as route_id, c.cabin, d.origin_code as o, d.day, avg(c.fare) as fare
           from public.route_days d
           left join ro r1 on r1.hub_code = d.origin_code and r1.dest_code = d.dest_code
           left join ro r2 on r2.hub_code = d.dest_code and r2.dest_code = d.origin_code
           cross join lateral (values ('economy'::text, case when d.eco_fare_avg > 0 then d.eco_fare_avg end),
                                      ('business'::text, case when d.bus_pax > 0 and d.bus_fare_avg > 0 then d.bus_fare_avg end)) c (cabin, fare)
          where d.airline_id = p_airline_id and c.fare is not null and d.day <= v_today and coalesce(r1.id, r2.id) is not null
          group by 1, 2, 3, 4),
  bd as materialized (
    select coalesce(dd.route_id, hd.route_id) as route_id, coalesce(dd.cabin, hd.cabin) as cabin, coalesce(dd.o, hd.o) as o,
           coalesce(dd.day, hd.day) as day, coalesce(dd.fare, hd.fare) as fare
      from dd full join hd on hd.route_id = dd.route_id and hd.cabin = dd.cabin and hd.o = dd.o and hd.day = dd.day),
  -- each direction's baseline day: the latest on or before 21 Oct 2026, when every route was at its launch level; for a
  -- route launched later, its first captured day, if within the route's first growth_new_route_days days (later than
  -- that, the first fare kept may not be at launch: the days before it archived)
  bk as (select bd.route_id, bd.cabin, bd.o, max(bd.day) filter (where bd.day <= v_base_day) as on_day, min(bd.day) as first_seen
           from bd group by 1, 2, 3),
  base as (select bk.route_id, bk.cabin, bk.o, bd.day, bd.fare
             from bk
             left join age ag on ag.route_id = bk.route_id
             join bd on bd.route_id = bk.route_id and bd.cabin = bk.cabin and bd.o = bk.o
                    and bd.day = coalesce(bk.on_day, case when ag.first_day is not null and bk.first_seen - ag.first_day < v_new_days then bk.first_seen end)),
  -- each direction's baseline (since 26 Oct a row each: out from the route's hub, back to it)
  bs as (select base.route_id, base.cabin, case when base.o = ro.hub_code then 'out' else 'back' end as dir, avg(base.fare) as fare, max(base.day) as day
           from base join ro on ro.id = base.route_id group by 1, 2, 3),
  -- the latest captured day by cabin and direction: its average fare, and each flight's fare against the direction's
  -- baseline
  lday as (select lc.route_id, lc.cabin, lc.dir, max(lc.game_date) as day from lc where lc.fare > 0 group by 1, 2, 3),
  latest as (select ld.route_id, ld.cabin, ld.dir, ld.day, avg(lc.fare) as fare,
                    array_agg(lc.fare / b.fare order by lc.dep_at) filter (where b.fare > 0) as ratios
               from lday ld
               join lc on lc.route_id = ld.route_id and lc.cabin = ld.cabin and lc.dir = ld.dir and lc.game_date = ld.day and lc.fare > 0
               left join base b on b.route_id = lc.route_id and b.cabin = lc.cabin and b.o = lc.o
              group by ld.route_id, ld.cabin, ld.dir, ld.day),
  -- the levels the fare plan recorded (manual §5): before this Saturday, the latest is the level; since it, this week's move.
  -- Since 26 Oct per direction: a row with a direction counts for that direction, a both-directions row (direction null,
  -- every row written before then) for each of them, so a direction's level is its own latest row, or the latest
  -- both-directions row if that is later (proposed on, then id)
  rec as (select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, d.dir, fp.direction, fp.level_pct, fp.ladder_move,
                 fp.proposed_on, fp.reason, fp.fare_from, fp.change_pct
            from public.fare_plan fp
           cross join (values ('out'), ('back')) d (dir)
           where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped'
             and fp.proposed_on <= v_today and (fp.direction is null or fp.direction = d.dir)),
  prev as (select distinct on (r.route_id, r.cabin, r.dir) r.* from rec r where r.proposed_on < v_week
            order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  wk as (select distinct on (r.route_id, r.cabin, r.dir) r.* from rec r where r.proposed_on >= v_week
          order by r.route_id, r.cabin, r.dir, r.proposed_on desc, r.id desc),
  dn as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as down_on from rec r where r.ladder_move = 'down' and r.proposed_on < v_week group by 1, 2, 3),
  -- under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md §2), per direction since 26 Oct.
  -- Each cabin's day by day fare, each direction's and both directions' together (dir 'both', for a both-directions row),
  -- and its jumps recorded before this Saturday, each with the day it took effect: the first captured day on or after it
  -- was proposed whose fare (the row's direction's, or both directions' for a both-directions row) is the fare then times
  -- its ratio, within 1% (fare_plan_status()'s rule, read over every captured day, so the day holds once the flights are
  -- older than its 10 days), else the day proposed
  cday as materialized (select lc.route_id, lc.cabin, coalesce(lc.dir, 'both') as dir, lc.game_date as day, avg(lc.fare) as fare
                          from lc where lc.fare > 0 group by grouping sets ((lc.route_id, lc.cabin, lc.dir, lc.game_date), (lc.route_id, lc.cabin, lc.game_date))),
  jr as (select r.id, r.route_id, r.cabin, r.dir, r.level_pct, r.proposed_on,
                coalesce((select min(c.day) from cday c
                           where c.route_id = r.route_id and c.cabin = r.cabin and c.dir = coalesce(r.direction, 'both') and c.day >= r.proposed_on and r.fare_from > 0
                             and abs(c.fare / r.fare_from - (1 + coalesce(r.change_pct, 0) / 100)) <= 0.01), r.proposed_on) as on_day
           from rec r where r.ladder_move = 'jump' and r.proposed_on < v_week),
  jf as (select distinct on (jr.route_id, jr.cabin, jr.dir) jr.route_id, jr.cabin, jr.dir, jr.on_day as first_on from jr
          order by jr.route_id, jr.cabin, jr.dir, jr.proposed_on, jr.id),
  jl as (select distinct on (jr.route_id, jr.cabin, jr.dir) jr.route_id, jr.cabin, jr.dir, jr.id, jr.proposed_on, jr.on_day as jumped_on
           from jr order by jr.route_id, jr.cabin, jr.dir, jr.proposed_on desc, jr.id desc),
  -- done: a revert recorded, or a row after the latest jump (the judgement that it paid, recorded as a hold, or the
  -- ladder's moves since): no more jumps for that cabin and direction
  ud as (select jl.route_id, jl.cabin, jl.dir from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.dir = jl.dir and r.proposed_on < v_week
                           and (r.ladder_move = 'revert' or (r.ladder_move in ('up', 'down', 'hold') and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))))),
  -- the latest recorded level change (any row but a hold): at launch, the window must be all at that level
  lch as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as changed_on from rec r where r.ladder_move is distinct from 'hold' group by 1, 2, 3),
  -- the window at launch: the fare_under_launch_days before the moment, by scheduled departure, the direction's flights
  uw as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load, avg(lc.pax * lc.fare) as rev
           from lc where lc.at >= p_as_of - make_interval(days => v_ul_days::int) and lc.at < p_as_of group by 1, 2, 3),
  -- the launch baseline: revenue a flight over the fare_under_launch_days before the first jump took effect, the
  -- direction's flights. By the last level's judgement those days can be 6 weeks old and their flights archived: a day
  -- with no captured flights in that direction is read from the daily history instead (route_days, the direction's row:
  -- passengers × average fare in that cabin, over the day's flights)
  ubf as (select lc.route_id, lc.cabin, lc.dir, lc.game_date as day, count(*) as n, sum(lc.pax * lc.fare) as rev
            from lc join jf on jf.route_id = lc.route_id and jf.cabin = lc.cabin and jf.dir = lc.dir
           where lc.at >= (jf.first_on - v_ul_days::int)::timestamp at time zone 'UTC' and lc.at < jf.first_on::timestamp at time zone 'UTC'
             and lc.pax is not null and lc.fare is not null
           group by 1, 2, 3, 4),
  ubh as (select jf.route_id, jf.cabin, jf.dir, d.day, sum(d.flights) as n,
                 sum(case jf.cabin when 'economy' then d.eco_pax * d.eco_fare_avg else d.bus_pax * d.bus_fare_avg end) as rev
            from jf
            join ro on ro.id = jf.route_id
            join public.route_days d on d.airline_id = p_airline_id
             and ((jf.dir = 'out' and d.origin_code = ro.hub_code and d.dest_code = ro.dest_code)
                  or (jf.dir = 'back' and d.origin_code = ro.dest_code and d.dest_code = ro.hub_code))
           where d.day >= jf.first_on - v_ul_days::int and d.day < jf.first_on and d.flights > 0
             and case jf.cabin when 'economy' then d.eco_pax is not null and d.eco_fare_avg is not null
                               else d.bus_pax is not null and d.bus_fare_avg is not null end
             and not exists (select 1 from ubf where ubf.route_id = jf.route_id and ubf.cabin = jf.cabin and ubf.dir = jf.dir and ubf.day = d.day)
           group by 1, 2, 3, 4),
  ub as (select x.route_id, x.cabin, x.dir, sum(x.rev) / nullif(sum(x.n), 0) as rev
           from (select ubf.route_id, ubf.cabin, ubf.dir, ubf.n, ubf.rev from ubf union all select ubh.route_id, ubh.cabin, ubh.dir, ubh.n, ubh.rev from ubh) x
          group by 1, 2, 3),
  -- at the jump level: the direction's flights since the latest jump took effect, to the moment
  uj as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load, avg(lc.pax * lc.fare) as rev
           from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin and jl.dir = lc.dir
          where lc.at >= jl.jumped_on::timestamp at time zone 'UTC' and lc.at < p_as_of
          group by 1, 2, 3),
  -- whether the captures show this week's move yet (fare_plan_status()'s rule)
  seen as (select (e ->> 'id')::bigint as id, (e ->> 'applied')::boolean as applied, (e ->> 'seen_on')::date as seen_on
             from jsonb_array_elements(case when exists (select 1 from wk) then private.fig_fare_plan(p_airline_id, p_as_of) -> 'plan' else '[]'::jsonb end) e),
  -- another player on the pair, either way round (our own airlines included, manual §9): the latest scan, and our other
  -- airlines' own flights
  pairs as (select distinct least(ro.hub_code, ro.dest_code) as a, greatest(ro.hub_code, ro.dest_code) as b from ro),
  other as (select least(f ->> 2, f ->> 3) as a, greatest(f ->> 2, f ->> 3) as b
              from public.game_scan_schedules sc
              cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
             where sc.scan_id = v_scan and sc.airline_id <> p_airline_id and jsonb_typeof(f) = 'array'
            union
            select least(l.origin_code, l.dest_code), greatest(l.origin_code, l.dest_code)
              from public.flight_legs l where l.world_id = w and l.airline_id <> p_airline_id),
  contested as (select p.a, p.b from pairs p where exists (select 1 from other o where o.a = p.a and o.b = p.b)),
  -- a rival that started on the pair, or added competition_threat_min_weekly departures a week, in a scan of the last 7
  -- days pauses the route (manual §5, since 21 Oct): the threats as competition() lists them (1b), the one paused longest
  thr as (select distinct on (t.a, t.b) t.a, t.b, t.rival, t.kind, t.added_weekly, t.scan_at, t.until
            from private.competition_threats(p_airline_id, p_as_of) t
           order by t.a, t.b, t.until desc, t.now_weekly desc, t.rival),
  -- the routes and cabins on the ladder: each flying route in economy, and in business where its aircraft have business
  -- seats; any with flights captured in the 7 days or a move recorded this week. Since 26 Oct each in both directions
  rc as (select distinct x.route_id, x.cabin, d.dir
           from (select f.route_id, 'economy'::text as cabin from fq f where f.live
                 union all select bz.route_id, 'business' from biz bz
                 union all select st.route_id, st.cabin from st
                 union all select wk.route_id, wk.cabin from wk) x
           join ro on ro.id = x.route_id
           cross join (values ('out'), ('back')) d (dir)),
  lv as (select rc.route_id, rc.cabin, rc.dir, ro.hub_code as hub, ro.dest_code as dest,
                case rc.dir when 'out' then ro.hub_code else ro.dest_code end as dir_from,
                case rc.dir when 'out' then ro.dest_code else ro.hub_code end as dir_to,
                coalesce(st.n, 0) as n, coalesce(st.sold, 0) as sold, st.fare as fare_week, st.load as load_week,
                lt.fare as latest_fare, lt.day as latest_on, lt.ratios, bs.fare as baseline_fare, bs.day as baseline_on,
                coalesce(pv.level_pct, v_launch) as level, pv.id is not null as recorded,
                wk.id as plan_id, wk.level_pct as plan_level, wk.ladder_move as plan_move, wk.reason as plan_reason,
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, ag.first_day, ad.last_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested,
                th.rival as rv_name, th.kind as rv_kind, th.added_weekly as rv_added, th.scan_at as rv_on, th.until as rv_until,
                jl.jumped_on, jf.first_on, ud.route_id is not null as ul_done, lch.changed_on,
                coalesce(uw.n, 0) as w_n, uw.load as w_load, uw.rev as w_rev, ub.rev as b_rev,
                coalesce(uj.n, 0) as j_n, uj.load as j_load, uj.rev as j_rev
           from rc join ro on ro.id = rc.route_id
           left join thr th on th.a = least(ro.hub_code, ro.dest_code) and th.b = greatest(ro.hub_code, ro.dest_code)
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin and st.dir = rc.dir
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin and lt.dir = rc.dir
           left join bs on bs.route_id = rc.route_id and bs.cabin = rc.cabin and bs.dir = rc.dir
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin and pv.dir = rc.dir
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin and wk.dir = rc.dir
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin and dn.dir = rc.dir
           left join age ag on ag.route_id = rc.route_id
           left join added ad on ad.route_id = rc.route_id
           left join jl on jl.route_id = rc.route_id and jl.cabin = rc.cabin and jl.dir = rc.dir
           left join jf on jf.route_id = rc.route_id and jf.cabin = rc.cabin and jf.dir = rc.dir
           left join ud on ud.route_id = rc.route_id and ud.cabin = rc.cabin and ud.dir = rc.dir
           left join lch on lch.route_id = rc.route_id and lch.cabin = rc.cabin and lch.dir = rc.dir
           left join uw on uw.route_id = rc.route_id and uw.cabin = rc.cabin and uw.dir = rc.dir
           left join ub on ub.route_id = rc.route_id and ub.cabin = rc.cabin and ub.dir = rc.dir
           left join uj on uj.route_id = rc.route_id and uj.cabin = rc.cabin and uj.dir = rc.dir),
  mv0 as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                v_launch + v_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(v_launch, case when lv.contested then v_floor end) as floor_pct,
                coalesce(lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held,
                -- a flight added in the last fare_ladder_capacity_hold_days, to a route older than that (manual §5, since 21 Oct)
                coalesce(lv.last_day is not null and v_today - lv.last_day < v_added_days
                         and lv.first_day is not null and v_today - lv.first_day >= v_added_days, false) as added,
                -- under launch (since 23 Oct): the cabin's state, from the fare plan's rows before this Saturday. launch: at
                -- its launch level and never jumped; holding: its latest jump under fare_under_launch_days old, counted from
                -- the day it took effect; due: the hold is over; done: reverted, or judged (a row after the latest jump)
                case when lv.jumped_on is null then case when lv.level = v_launch and v_ul_below is not null then 'launch' end
                     when lv.ul_done then 'done'
                     when v_today - lv.jumped_on < v_ul_days then 'holding'
                     else 'due' end as ul_state,
                lv.jumped_on + v_ul_days::int as judge_on,
                -- the latest recorded level change (a cabin back at launch after a step down): the window must have none,
                -- so all its flights are at the launch level (spec §2); a new route waits as before (growth_new_route_days)
                lv.changed_on as launch_since,
                -- the jump levels under the cabin's level: the next is the first of them; at the last, none is left
                (select u.l from unnest(v_ul_below) with ordinality as u(l, i) where u.l < lv.level order by u.i limit 1) as next_level
           from lv),
  -- the under-launch kind (spec §2), worked out before this week's plan so a move put on the plan this week keeps it
  mv as (select mv0.*,
                case
                  when mv0.ul_state = 'launch' then
                    case when mv0.share >= v_down or mv0.n < v_min or mv0.w_load is null or mv0.w_load >= v_ul_load then null
                         when mv0.launch_since is not null and p_as_of - make_interval(days => v_ul_days::int) < mv0.launch_since::timestamp at time zone 'UTC' then 'ul_since'
                         when mv0.w_n < v_ul_min then 'ul_few'
                         else 'ul_jump' end
                  when mv0.ul_state = 'holding' then 'ul_hold'
                  when mv0.ul_state = 'due' then
                    case when mv0.j_n < v_ul_min or mv0.b_rev is null or mv0.j_rev is null then 'ul_few'
                         when mv0.j_rev >= mv0.b_rev and not (mv0.next_level is null and mv0.j_load < v_ul_decide) then 'ul_paid'
                         when mv0.j_rev < mv0.b_rev and mv0.next_level is not null then 'ul_jump'
                         when mv0.j_rev < mv0.b_rev then 'ul_revert'
                         else 'ul_keep' end
                end as uk
           from mv0),
  dc as (select mv.*,
                case when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     when mv.held then 'held'
                     when mv.added then 'added'
                     when mv.rv_name is not null then 'rival'
                     -- under launch (since 23 Oct; spec §2): the jump at launch only where the ladder would hold at launch
                     -- (under fare_ladder_down_share sold out); the hold, the judgement and the waits whatever it sells
                     when mv.uk in ('ul_hold', 'ul_paid', 'ul_keep', 'ul_revert') or (mv.uk = 'ul_jump' and mv.ul_state = 'due')
                          or (mv.uk = 'ul_few' and mv.ul_state = 'due') then mv.uk
                     when mv.uk in ('ul_jump', 'ul_few', 'ul_since') and mv.level <= mv.floor_pct then mv.uk
                     -- under launch, once jumped or done, the ladder only climbs or holds
                     when mv.level < v_launch and mv.share < v_down then 'ul_climb'
                     when mv.share >= v_up then case when mv.level >= mv.cap_pct then 'capped' else 'up' end
                     when mv.share >= v_down then 'hold'
                     when mv.level <= mv.floor_pct then 'floor'
                     else 'down' end as k
           from mv),
  fin as (select dc.*,
                 -- a jump is a move down and a revert a move up (since 23 Oct), so existing readers keep working; ladder_kind
                 -- says which
                 case dc.k when 'planned' then case dc.plan_move when 'jump' then 'down' when 'revert' then 'up' else dc.plan_move end
                           when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'down' when 'ul_revert' then 'up' else 'hold' end as move,
                 case dc.k when 'planned' then dc.plan_move when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'jump'
                           when 'ul_revert' then 'revert' else 'hold' end as ladder_kind,
                 case dc.k when 'planned' then dc.plan_level
                           when 'up' then least(dc.level + v_step, dc.cap_pct)
                           when 'down' then greatest(dc.level - v_step, dc.floor_pct)
                           when 'ul_jump' then dc.next_level
                           when 'ul_revert' then v_launch
                           else dc.level end as new_level,
                 -- a cut-or-keep decision for Gitesh (since 23 Oct): at the last jump level, reverted or holding under the
                 -- decide load; still shown once put on the fare plan this week
                 dc.uk in ('ul_revert', 'ul_keep') and dc.k in ('ul_revert', 'ul_keep', 'planned') as decide,
                 to_char(round(dc.b_rev), 'FM999,999,999,990') as b_words, to_char(round(dc.j_rev), 'FM999,999,999,990') as j_words,
                 case when dc.contested and v_floor > v_launch then format('the %s%% floor', trim_scale(v_floor))
                      else format('launch (%s%%)', trim_scale(v_launch)) end as floor_words
            from dc),
  od as (select fin.*,
                 case fin.k
                   when 'planned' then coalesce(fin.plan_reason, 'on the fare plan')
                   when 'young' then format('new route, launched %s', to_char(fin.first_day, 'FMDD Mon'))
                   when 'few' then case when fin.n = 0 then 'no departures captured'
                                        else format('%s departure%s captured, needs %s', fin.n, case when fin.n = 1 then '' else 's' end, trim_scale(v_min)) end
                   when 'held' then format('held after a step down on %s', to_char(fin.down_on, 'FMDD Mon'))
                   when 'added' then format('a flight added on %s: judged at its new size from %s', to_char(fin.last_day, 'FMDD Mon'),
                                            to_char(fin.last_day + v_added_days::int, 'FMDD Mon'))
                   when 'rival' then format('rival %s %s here on %s: paused until %s', fin.rv_name,
                                            case when fin.rv_kind = 'started' then 'started' else format('added %s a week', fin.rv_added) end,
                                            to_char(fin.rv_on at time zone 'UTC', 'FMDD Mon'), to_char(fin.rv_until at time zone 'UTC', 'FMDD Mon'))
                   when 'up' then format('sold out %s of %s', fin.sold, fin.n)
                                  || case when fin.level + v_step >= fin.cap_pct then format(', up to the %s%% cap', trim_scale(fin.cap_pct)) else '' end
                   when 'capped' then format('sold out %s of %s, capped at %s%%', fin.sold, fin.n, trim_scale(fin.cap_pct))
                   when 'hold' then format('sold out %s of %s', fin.sold, fin.n)
                   when 'down' then format('sold out %s of %s', fin.sold, fin.n)
                                    || case when fin.level - v_step <= fin.floor_pct then ', down to ' || fin.floor_words else '' end
                   -- under launch (since 23 Oct; spec §2)
                   when 'ul_jump' then case when fin.ul_state = 'due'
                     then format('at %s%%: revenue a flight %s against %s at launch: to %s%% for %s', trim_scale(fin.level), fin.j_words, fin.b_words,
                                 trim_scale(fin.next_level), v_ul_span)
                     else format('%s%% full over %s days at launch: to %s%% for %s', round(fin.w_load), trim_scale(v_ul_days), trim_scale(fin.next_level), v_ul_span) end
                   when 'ul_hold' then format('at %s%% since %s: judged on %s', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'), to_char(fin.judge_on, 'FMDD Mon'))
                   when 'ul_paid' then format('at %s%%: revenue a flight %s against %s at launch, paid off', trim_scale(fin.level), fin.j_words, fin.b_words)
                   when 'ul_revert' then format('at %s%% for %s: %s%% full, revenue a flight %s against %s at launch: back to launch; cut or keep? (Saturday review)',
                                                trim_scale(fin.level), v_ul_span, round(fin.j_load), fin.j_words, fin.b_words)
                   when 'ul_keep' then format('at %s%% for %s: %s%% full, revenue a flight %s against %s at launch: holds at %s%%; cut or keep? (Saturday review)',
                                              trim_scale(fin.level), v_ul_span, round(fin.j_load), fin.j_words, fin.b_words, trim_scale(fin.level))
                   when 'ul_few' then case when fin.ul_state = 'due' then
                       case when fin.j_n < v_ul_min then format('at %s%% since %s: %s flight%s, needs %s to be judged', trim_scale(fin.level),
                                                                to_char(fin.jumped_on, 'FMDD Mon'), fin.j_n, case when fin.j_n = 1 then '' else 's' end, trim_scale(v_ul_min))
                            else format('at %s%% since %s: no revenue captured at launch to judge it against', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon')) end
                     else format('sold out %s of %s, at %s: %s flight%s in %s days, needs %s to jump', fin.sold, fin.n, fin.floor_words, fin.w_n,
                                 case when fin.w_n = 1 then '' else 's' end, trim_scale(v_ul_days), trim_scale(v_ul_min)) end
                   when 'ul_since' then format('sold out %s of %s, at %s since %s: may jump from %s', fin.sold, fin.n, fin.floor_words,
                                               to_char(fin.launch_since, 'FMDD Mon'), to_char(fin.launch_since + v_ul_days::int, 'FMDD Mon'))
                   when 'ul_climb' then 'under launch: climbs or holds only'
                   else format('sold out %s of %s, at %s', fin.sold, fin.n, fin.floor_words) end as reason,
                 -- the level the game should show: this week's, once the captures see it
                 case when fin.plan_id is not null and fin.applied then fin.new_level else fin.level end as expect
            from fin),
  -- the fare index: each flight of the latest captured day against its direction's baseline, times the launch level; the
  -- day's average, and the flight furthest from the level the game should show
  ix as (select od.*,
                (select round(avg(r) * v_launch, 1) from unnest(od.ratios) r) as fare_index,
                (select r * v_launch from unnest(od.ratios) r order by abs(r * v_launch - od.expect) desc limit 1) as worst
           from od),
  fx as (select ix.*,
                case when ix.worst is not null then abs(ix.worst - ix.expect) <= 1 end as matches,
                -- set back (manual §5, since 21 Oct): off its level, not on the fare plan this week, not new, and captured
                -- since its newest rotation launched
                coalesce(ix.worst is not null and abs(ix.worst - ix.expect) > 1 and ix.plan_id is null and not ix.young
                         and (ix.last_day is null or ix.latest_on > ix.last_day), false) as fix
           from ix)
  select coalesce(jsonb_agg(jsonb_build_object(
           -- since 26 Oct a row per direction: out from the route's hub, back to it, with its airports that way round
           'route_id', o.route_id, 'hub', o.hub, 'dest', o.dest, 'direction', o.dir, 'from', o.dir_from, 'to', o.dir_to, 'cabin', o.cabin,
           'departures', o.n, 'sold_out', o.sold, 'sold_out_share', round(o.share, 1), 'load', round(o.load_week, 1), 'average_fare', round(o.fare_week, 2),
           'baseline_fare', round(o.baseline_fare, 2), 'baseline_on', o.baseline_on, 'latest_fare', round(o.latest_fare, 2), 'latest_on', o.latest_on,
           'fare_index', o.fare_index, 'index_matches', o.matches,
           'level', trim_scale(o.level), 'recorded', o.recorded, 'steps', trim_scale(round((o.level - v_launch) / v_step, 1)),
           'move', o.move, 'new_level', trim_scale(o.new_level), 'new_steps', trim_scale(round((o.new_level - v_launch) / v_step, 1)),
           'change_pct', case when o.level > 0 then trim_scale(round((o.new_level / o.level - 1) * 100, 1)) end,
           'reason', o.reason, 'contested', o.contested, 'floor', trim_scale(o.floor_pct), 'cap', trim_scale(o.cap_pct), 'new_route', o.young,
           'planned', o.plan_id is not null, 'plan_id', o.plan_id, 'applied', o.applied, 'seen_on', o.seen_on,
           -- what Put on the fare plan writes: every level that changes (jumps and reverts included), a hold that follows a
           -- step down, and since 23 Oct a judgement under launch that holds (so the cabin is done)
           'to_plan', o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k in ('held', 'ul_paid', 'ul_keep')),
           -- under launch (since 23 Oct): what Put on the fare plan writes as ladder_move, the cabin's state with its
           -- figures, and whether it is a cut-or-keep decision for Gitesh
           'ladder_kind', o.ladder_kind,
           'under_launch', case when o.ul_state is not null then jsonb_strip_nulls(jsonb_build_object(
             'state', o.ul_state,
             'baseline_revenue', round(o.b_rev, 2),
             'window_revenue', round(case when o.ul_state = 'launch' then o.w_rev else o.j_rev end, 2),
             'window_load', round(case when o.ul_state = 'launch' then o.w_load else o.j_load end, 1),
             'window_flights', case when o.ul_state = 'launch' then o.w_n else o.j_n end,
             'jumped_on', o.jumped_on, 'judge_on', o.judge_on)) end,
           'decide', o.decide,
           -- a change that sets it back to its level (manual §5, since 21 Oct)
           'fix', o.fix,
           'fix_reason', case when o.fix then format('captured fare at %s%%, level %s%%', trim_scale(round(o.worst, 1)), trim_scale(o.expect)) end)
           order by o.hub, o.dest, o.dir = 'back', o.cabin desc), '[]'::jsonb)
    into v_rows from fx o;

  -- the game's Ticket price adjustments, route by route only (manual §5, since 21 Oct: never a whole base, so a route
  -- under 7 days old is never touched). Each sets the level with the baseline default price. Since 26 Oct each direction
  -- has its own level, so each direction is an action of its own (From A to B, From B to A). First the set-back changes
  -- (fix), then the week's moves, each in the rows' order (hub, dest, out before back): for each direction, when both
  -- cabins go to the same level, one action with both classes ticked; otherwise one for each cabin, economy first. A
  -- direction whose levels don't change gets no action.
  for v_r in select x.fix, x.hub, x.dest, x.dir_from, x.dir_to,
                    jsonb_agg(jsonb_build_object('cabin', x.cabin, 'level', x.level, 'reason', x.reason) order by x.cabin = 'business') as moves
               from (select true as fix, e ->> 'route_id' as route_id, e ->> 'hub' as hub, e ->> 'dest' as dest, e ->> 'direction' as dir,
                            e ->> 'from' as dir_from, e ->> 'to' as dir_to, e ->> 'cabin' as cabin,
                            (e ->> 'level')::numeric as level, e ->> 'fix_reason' as reason
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'fix')::boolean
                     union all
                     select false, e ->> 'route_id', e ->> 'hub', e ->> 'dest', e ->> 'direction', e ->> 'from', e ->> 'to', e ->> 'cabin',
                            (e ->> 'new_level')::numeric, null
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric) x
              group by x.fix, x.route_id, x.hub, x.dest, x.dir, x.dir_from, x.dir_to
              order by x.fix desc, x.hub, x.dest, x.dir = 'back' loop
    if jsonb_array_length(v_r.moves) = 2 and (v_r.moves #>> '{0,level}')::numeric = (v_r.moves #>> '{1,level}')::numeric then
      v_sets := jsonb_build_array(jsonb_build_object(
        'classes', jsonb_build_array('economy', 'business'), 'level', v_r.moves #> '{0,level}',
        'reason', case when v_r.fix then format('economy: %s; business: %s', v_r.moves #>> '{0,reason}', v_r.moves #>> '{1,reason}') end));
    else
      select jsonb_agg(jsonb_build_object('classes', jsonb_build_array(m ->> 'cabin'), 'level', m -> 'level', 'reason', m -> 'reason') order by i) into v_sets
        from jsonb_array_elements(v_r.moves) with ordinality as t(m, i);
    end if;
    for v_change in select x from jsonb_array_elements(v_sets) x loop
      v_lv := (v_change ->> 'level')::numeric;
      select string_agg(c, ' and ' order by i) into v_words from jsonb_array_elements_text(v_change -> 'classes') with ordinality as t(c, i);
      v_n := v_n + 1;
      v_actions := v_actions || jsonb_build_object(
        'n', v_n, 'route', v_r.hub || '–' || v_r.dest, 'classes', v_change -> 'classes', 'from', v_r.dir_from, 'to', v_r.dir_to,
        'level', trim_scale(v_lv), 'sign', case when v_lv >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_lv - 100)),
        'baseline', 'default price', 'fix', v_r.fix, 'reason', v_change ->> 'reason',
        'text', format('From %s to %s: %s%s%% of the default price, %s', v_r.dir_from, v_r.dir_to,
                       case when v_lv >= 100 then '+' else '−' end, trim_scale(abs(v_lv - 100)), v_words));
    end loop;
  end loop;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of), 'week_of', v_week,
    'from', private.fig_ts(p_as_of - interval '7 days'), 'to', private.fig_ts(p_as_of),
    'settings', jsonb_build_object('step_pts', v_step, 'up_share', v_up, 'down_share', v_down, 'min_departures', v_min,
                                   'hold_weeks', v_hold, 'cap_pts', v_cap, 'launch_pct', v_launch, 'cap_pct', v_launch + v_cap,
                                   'floor_pct', v_floor, 'new_route_days', v_new_days, 'capacity_hold_days', v_added_days,
                                   'baseline_day', v_base_day,
                                   'under_launch', jsonb_build_object('load_pct', v_ul_load, 'levels', to_jsonb(v_ul_levels), 'days', v_ul_days,
                                                                      'min_flights', v_ul_min, 'decide_load_pct', v_ul_decide)),
    'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
    'moves', jsonb_build_object(
      'up', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'up'),
      'hold', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'hold'),
      'down', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'down'),
      'jumps', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'ladder_kind' = 'jump'),
      'decisions', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'decide')::boolean)),
    'to_plan', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'to_plan')::boolean),
    'planned', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'planned')::boolean),
    -- since 26 Oct the directions set back (a route and direction each)
    'off_level', (select count(distinct (e ->> 'route_id') || ' ' || (e ->> 'direction')) from jsonb_array_elements(v_rows) e where (e ->> 'fix')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'The fare index compares each flight of the latest captured day with its direction''s fare on 21 Oct 2026, when every route was at its launch level (or its first captured fare, for a route launched later), times the launch level. Since 26 Oct each direction has its own level, judged on its own flights: a direction more than 1 point off its level gets a change that sets it back, first in the list, unless it''s on the fare plan this week, its route is new, or it isn''t captured since its route''s newest flight launched.'));
end
$function$
;


-- ============================================================ 3. fare_plan_status(): a direction seen by its own fares
CREATE OR REPLACE FUNCTION private.fig_fare_plan(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_today date := (p_as_of at time zone 'UTC')::date;
begin
  return (
    with l as (select distinct on (f.game_date, f.flight_no) f.game_date, f.origin_code as origin, f.dest_code as dest,
                      f.eco_pct as eco, trim_scale(f.eco_fare) as fare,
                      f.bus_pct as bus, case when coalesce(f.bus_seats, 0) > 0 then trim_scale(f.bus_fare) end as bfare
                 from public.game_flights f
                where f.airline_id = p_airline_id and f.flight_no is not null and f.game_date >= v_today - 9
                  and f.loads_captured_at <= p_as_of
                order by f.game_date, f.flight_no, f.id desc),
    r as (select ro.id, ro.hub_code, ro.dest_code from public.routes ro where ro.airline_id = p_airline_id and ro.world_id = w),
    -- each route's fares and economy loads by date: the day's average fare, and the loads summed with their count (the
    -- before and after are averages over every flight, not over the days). Since 26 Oct each direction's too (dir out from
    -- the route's hub, back to it) beside both directions' together (dir both): a fare ladder row with a direction is read
    -- on its own direction's flights
    rd as materialized (
      select r.id as route_id, coalesce(case when l.origin = r.hub_code then 'out' else 'back' end, 'both') as dir, l.game_date as day,
             avg(l.fare) as fare, sum(l.eco) as eco_sum, count(l.eco) as eco_n
        from r join l on l.fare is not null
         and ((l.origin = r.hub_code and l.dest = r.dest_code) or (l.origin = r.dest_code and l.dest = r.hub_code))
       group by grouping sets ((r.id, case when l.origin = r.hub_code then 'out' else 'back' end, l.game_date), (r.id, l.game_date))),
    -- the same in business, for the fare ladder's business rows (flights with business seats)
    rb as materialized (
      select r.id as route_id, coalesce(case when l.origin = r.hub_code then 'out' else 'back' end, 'both') as dir, l.game_date as day,
             avg(l.bfare) as fare, sum(l.bus) as eco_sum, count(l.bus) as eco_n
        from r join l on l.bfare is not null
         and ((l.origin = r.hub_code and l.dest = r.dest_code) or (l.origin = r.dest_code and l.dest = r.hub_code))
       group by grouping sets ((r.id, case when l.origin = r.hub_code then 'out' else 'back' end, l.game_date), (r.id, l.game_date))),
    p as (select fp.*, ro.hub_code, ro.dest_code, coalesce(fp.direction, 'both') as dk,
                 fp.fare_from * (1 + fp.change_pct / 100) as target,
                 case when fp.level_pct is not null and fp.cabin_class = 'business'
                      then (select rb.fare from rb where rb.route_id = fp.route_id and rb.dir = coalesce(fp.direction, 'both') order by rb.day desc limit 1)
                      else (select rd.fare from rd where rd.route_id = fp.route_id and rd.dir = coalesce(fp.direction, 'both') order by rd.day desc limit 1) end as cur,
                 case
                   -- a fare test: seen once at least half the change shows in the day's average fare, on or after the day it
                   -- was proposed
                   when fp.level_pct is null
                     then (select min(rd.day) from rd where rd.route_id = fp.route_id and rd.dir = coalesce(fp.direction, 'both') and rd.day >= fp.proposed_on
                              and rd.fare >= fp.fare_from * (1 + fp.change_pct / 200))
                   -- the fare ladder's: seen once the day's average fare in its cabin is the fare then times the expected
                   -- ratio, within 1%, on or after the day it was proposed
                   when fp.cabin_class = 'business'
                     then (select min(rb.day) from rb where rb.route_id = fp.route_id and rb.dir = coalesce(fp.direction, 'both') and rb.day >= fp.proposed_on and fp.fare_from > 0
                              and abs(rb.fare / fp.fare_from - (1 + coalesce(fp.change_pct, 0) / 100)) <= 0.01)
                   else (select min(rd.day) from rd where rd.route_id = fp.route_id and rd.dir = coalesce(fp.direction, 'both') and rd.day >= fp.proposed_on and fp.fare_from > 0
                            and abs(rd.fare / fp.fare_from - (1 + coalesce(fp.change_pct, 0) / 100)) <= 0.01) end as seen,
                 fp.level_pct is not null and fp.cabin_class = 'business' as biz
            from public.fare_plan fp left join public.routes ro on ro.id = fp.route_id
           where fp.airline_id = p_airline_id and fp.status <> 'dropped')
    select jsonb_build_object(
      'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of),
      'plan', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', p.id, 'legacy_key', p.legacy_key, 'route_id', p.route_id, 'hub', p.hub_code, 'dest', p.dest_code,
                 'cabin_class', p.cabin_class, 'change_pct', trim_scale(p.change_pct), 'fare_from', trim_scale(p.fare_from),
                 'proposed_on', p.proposed_on, 'status', p.status, 'reason', p.reason, 'updated_at', p.updated_at,
                 'fare_now', p.cur, 'target', p.target, 'applied', p.seen is not null, 'seen_on', p.seen,
                 'economy_before', case when p.seen is null then null
                                        when p.biz then (select sum(rb.eco_sum) / nullif(sum(rb.eco_n), 0) from rb where rb.route_id = p.route_id and rb.dir = p.dk and rb.day < p.seen)
                                        else (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.dir = p.dk and rd.day < p.seen) end,
                 'economy_after', case when p.seen is null then null
                                       when p.biz then (select sum(rb.eco_sum) / nullif(sum(rb.eco_n), 0) from rb where rb.route_id = p.route_id and rb.dir = p.dk and rb.day >= p.seen)
                                       else (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.dir = p.dk and rd.day >= p.seen) end,
                 'level_pct', trim_scale(p.level_pct), 'ladder_move', p.ladder_move, 'direction', p.direction)
                 order by p.id) from p), '[]'::jsonb),
      'fares', coalesce((select jsonb_agg(jsonb_build_object('route_id', x.route_id, 'hub', r.hub_code, 'dest', r.dest_code, 'day', x.day, 'fare', x.fare)
                                          order by x.route_id)
                           from (select distinct on (rd.route_id) rd.route_id, rd.day, rd.fare from rd where rd.dir = 'both' order by rd.route_id, rd.day desc) x
                           join r on r.id = x.route_id), '[]'::jsonb)));
end
$function$
;

-- ============================================================ 4. capture_fare_actions(): the actions per direction
CREATE OR REPLACE FUNCTION private.capture_fare_actions_doc(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_al record; d jsonb; v_week text; v_keep jsonb;
  v_airlines jsonb := '[]'::jsonb; v_actions jsonb := '[]'::jsonb;
begin
  -- our active airlines of the world, as capture_airlines() lists them, in display order
  for v_al in select a.id, a.game_id, coalesce(a.public_name, a.planner_name, a.game_name) as name, a.game_name, a.iata_code
                from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
               where a.world_id = p_world_id and a.active and g.kind = 'ours'
               order by a.position nulls last, a.id loop
    d := private.fig_fare_ladder(v_al.id, p_as_of);
    v_week := coalesce(v_week, d ->> 'week_of');
    -- an action is kept when it sets a route back to its level (fix: no fare plan row; the index matching again is the
    -- proof), or when every class it names is a route row (matched by its route, "HUB–DEST", its direction, From and To,
    -- since 26 Oct, and cabin) that is on the fare plan this week (planned) and not yet seen in the captures (applied
    -- false, by its own direction's fares when the row has one)
    with acts as (select t.x, t.i from jsonb_array_elements(d -> 'actions') with ordinality as t(x, i)),
         cls as (select acts.i, c.k, m.rt
                   from acts
                   cross join lateral jsonb_array_elements_text(acts.x -> 'classes') with ordinality as c(cabin, k)
                   left join lateral (select e as rt from jsonb_array_elements(d -> 'routes') e
                                       where (e ->> 'hub') || '–' || (e ->> 'dest') = acts.x ->> 'route' and e ->> 'cabin' = c.cabin
                                         and e ->> 'from' = acts.x ->> 'from' and e ->> 'to' = acts.x ->> 'to'
                                       limit 1) m on true),
         ok as (select cls.i, jsonb_agg((cls.rt ->> 'plan_id')::bigint order by cls.k) as plan_ids
                  from cls
                 group by cls.i
                having bool_and(coalesce((cls.rt ->> 'planned')::boolean, false) and not coalesce((cls.rt ->> 'applied')::boolean, true))),
         keep as (select acts.i, acts.x, case when coalesce((acts.x ->> 'fix')::boolean, false) then '[]'::jsonb else ok.plan_ids end as plan_ids
                    from acts left join ok on ok.i = acts.i
                   where coalesce((acts.x ->> 'fix')::boolean, false) or ok.i is not null)
    select coalesce(jsonb_agg(jsonb_build_object(
             'game_id', v_al.game_id, 'airline', v_al.name, 'n', keep.x -> 'n', 'route', keep.x -> 'route',
             'from', keep.x -> 'from', 'to', keep.x -> 'to', 'level', keep.x -> 'level', 'sign', keep.x -> 'sign',
             'pct', keep.x -> 'pct', 'classes', keep.x -> 'classes', 'plan_ids', keep.plan_ids,
             'fix', coalesce((keep.x ->> 'fix')::boolean, false), 'reason', keep.x -> 'reason', 'text', keep.x -> 'text')
             order by keep.i), '[]'::jsonb)
      into v_keep
      from keep;
    v_actions := v_actions || v_keep;
    v_airlines := v_airlines || jsonb_build_object('game_id', v_al.game_id, 'name', v_al.name, 'game_name', v_al.game_name,
                                                   'code', v_al.iata_code, 'count', jsonb_array_length(v_keep),
                                                   'fixes', (select count(*) from jsonb_array_elements(v_keep) x where (x ->> 'fix')::boolean));
  end loop;
  return jsonb_build_object('as_of', private.fig_ts(p_as_of), 'week_of', v_week, 'airlines', v_airlines, 'actions', v_actions);
end
$function$
;

-- ============================================================ 5. route_story(): a fare event names its direction
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
                   -- since 26 Oct a ladder row may be one direction's (out from the hub, back to it): its words say which
                   'direction', fp.direction,
                   'words', coalesce(fp.direction || ': ', '') || case when fp.level_pct is not null
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
      'Rivals are every airline in the scan that isn''t one of ours; ours now are the live schedule both ways, ours in a scan the airline''s flights in it.',
      'Connecting (since 23 Oct): each rival''s one-stop departures a week on the pair, both ways, from scan_rival_connections (same airline, from the connecting airport''s minimum connection time to connection_max_wait_h, both legs together at most rival_connection_detour_max times the direct distance, each first flight once), with its top 3 connecting airports; beside weekly, never added to it, to rivals_weekly or to the share. connecting_only: rivals with no direct flight that connect; connecting_scans: each rival''s at each scan read that has them worked out. Absent when the latest scan has none worked out.',
      'Weekly points (since 23 Oct): a scan whose schedules the monthly archive has taken is read from its kept rows (scan_pair_airlines: the week''s kept scan, the first finished on or after each Saturday, every airline''s departures on every pair, kept for good), the same figures; such a point has weekly true in shares, since_launch and the scans. weekly_points counts them and daily_from is the first point read from full schedules (null when every point is). Before the last month the line is weekly; connections only on scans with their schedules.'));
end
$function$
;

-- ============================================================ 6. the briefing: the fare ladder per direction
CREATE OR REPLACE FUNCTION private.briefing_doc(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with al as (select a.id, a.world_id, a.iata_code, a.planner_name, a.public_name, a.game_name, a.game_id
                from public.airlines a where a.id = p_airline_id),
  -- loads by route and flight number over the 7 days to the moment, as route_loads() gives them, this airline's only
  rl as (select private.fig_route_loads(al.world_id, p_as_of) as d from al),
  -- the fare ladder (fare_ladder()'s document), for each route's fare level (since 21 Oct)
  fl as (select private.fig_fare_ladder(al.id, p_as_of) as d from al),
  -- competition analysis (competition()'s document, since 21 Oct): the scans, the group line, the threats and the top 20
  -- openings, for the evening proposal (manual §3)
  cp as (select private.fig_competition(al.id, p_as_of, 20) as d from al)
  select jsonb_build_object(
    'airline', (select jsonb_build_object('id', al.id, 'world_id', al.world_id, 'code', al.iata_code, 'planner_name', al.planner_name,
                                          'public_name', al.public_name, 'game_name', al.game_name, 'game_id', al.game_id) from al),
    'as_of', private.fig_ts(p_as_of),
    -- the aircraft not yet filed: on order, or arrived and not yet flying (status delivered), each with its plan cards
    -- (each with its cabin, config_id, since 21 Oct, for the card check's cabin)
    'deliveries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'aircraft_id', a.id, 'registration', a.registration, 'status', a.status,
               'type_id', a.aircraft_type_id, 'type', t.name, 'ordered_on', a.ordered_on,
               'delivery_at', private.fig_ts(a.delivery_at), 'arrived', a.delivery_at is not null and a.delivery_at <= p_as_of,
               'base_code', a.base_code, 'order_base_code', a.order_base_code,
               'cabin', c.code, 'order_cabin', oc.code, 'order_note', a.order_note,
               'plan_cards', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', pc.id, 'airline_id', pc.airline_id, 'title', pc.title, 'base_code', pc.base_code, 'note', pc.note,
                          'config_id', pc.config_id, 'updated_at', private.fig_ts(pc.updated_at),
                          'legs', coalesce((
                            select jsonb_agg(jsonb_build_object(
                                     'position', l.position, 'flight_no', l.flight_no, 'origin_code', l.origin_code, 'dest_code', l.dest_code,
                                     'days_utc', to_jsonb(l.days_utc), 'dep_utc_min', l.dep_utc_min, 'block_min', l.block_min,
                                     'service_code', l.service_code)
                                   order by l.position, l.id)
                              from public.plan_card_legs l where l.plan_card_id = pc.id), '[]'::jsonb))
                        order by pc.id)
                   from public.plan_cards pc where pc.aircraft_id = a.id), '[]'::jsonb))
             order by a.delivery_at nulls last, a.id)
        from public.aircraft a
        left join public.aircraft_types t on t.id = a.aircraft_type_id
        left join public.cabin_configs c on c.id = a.cabin_config_id
        left join public.cabin_configs oc on oc.id = a.order_config_id
       where a.airline_id = p_airline_id and a.status in ('on_order', 'delivered')), '[]'::jsonb),
    -- the open to-dos: the airline's own, and the group's (no airline)
    'todos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'legacy_key', t.legacy_key, 'airline_id', t.airline_id, 'group', t.airline_id is null,
               'title', t.title, 'due_on', t.due_on, 'note', t.note, 'created_at', private.fig_ts(t.created_at),
               'steps', (select coalesce(jsonb_agg(i.body order by i.position, i.id), '[]'::jsonb)
                           from public.todo_items i where i.todo_id = t.id))
             order by t.due_on nulls last, t.created_at, t.id)
        from public.todos t, al
       where t.world_id = al.world_id and t.done is not true and (t.airline_id = p_airline_id or t.airline_id is null)), '[]'::jsonb),
    -- the fare plan and whether the captures show each change (fare_plan_status()'s document)
    'fare_plan', private.fig_fare_plan(p_airline_id, p_as_of),
    -- each route, cabin and direction's fare level (fare_ladder()'s routes: the level, and this week's new level once it's
    -- on the fare plan; per direction since 26 Oct, from and to its airports that way round) and the launch level for a
    -- route not flown yet: the plan card check's fare line (manual §5, since 21 Oct)
    'fare_ladder', (select jsonb_build_object(
        'week_of', fl.d -> 'week_of', 'settings', jsonb_build_object('launch_pct', fl.d #> '{settings,launch_pct}'),
        'routes', coalesce((select jsonb_agg(jsonb_build_object('route_id', e -> 'route_id', 'hub', e -> 'hub', 'dest', e -> 'dest',
                                                               'direction', e -> 'direction', 'from', e -> 'from', 'to', e -> 'to', 'cabin', e -> 'cabin',
                                                               'level', e -> 'level', 'new_level', e -> 'new_level', 'planned', e -> 'planned') order by x.o)
                              from jsonb_array_elements(fl.d -> 'routes') with ordinality x(e, o)), '[]'::jsonb))
      from fl),
    'competition', (select jsonb_build_object(
        'scans', cp.d -> 'scans', 'group', cp.d -> 'group', 'hubs_first', cp.d -> 'hubs_first', 'threats', cp.d -> 'threats',
        'openings', cp.d -> 'openings', 'openings_count', cp.d -> 'openings_count', 'openings_allowed', cp.d -> 'openings_allowed',
        'openings_left_out', cp.d -> 'openings_left_out')
      from cp),
    'route_loads', (select jsonb_build_object(
        'from', rl.d -> 'from', 'to', rl.d -> 'to',
        'routes', coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(rl.d -> 'routes') with ordinality x(v, o)
                             where (x.v ->> 'airline_id')::bigint = p_airline_id), '[]'::jsonb),
        'flights', coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(rl.d -> 'flights') with ordinality x(v, o)
                              where (x.v ->> 'airline_id')::bigint = p_airline_id), '[]'::jsonb))
      from rl))
  from al
$function$
;

-- ============================================================ 7. access and descriptions
-- The replaced functions stay internal: nobody outside the database calls them. The public functions that read them say
-- what changed.
revoke all on function private.fig_fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.fig_fare_plan(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.capture_fare_actions_doc(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.fig_route_story(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.briefing_doc(bigint, timestamptz) from public, anon, authenticated, service_role;
comment on function public.fare_ladder(bigint, timestamptz) is 'The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md, docs/specs/2026-10-21-fare-actions-by-route.md, docs/specs/2026-10-21-frequencies-and-fares.md and docs/specs/2026-10-21-competition-analysis.md §2, and since 23 Oct docs/specs/2026-10-23-fare-ladder-under-launch.md): this Saturday''s move for each route, cabin and direction (since 26 Oct, spec docs/specs/2026-10-26-fare-ladder-per-direction.md), the changes that set a direction back to its level, and the game actions that make them. routes: one row per route, cabin and direction (out from the route''s hub, then back to it; direction, and from and to, its airports that way round), for each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin''s load at 100%), the sold-out share, the average load (load) and the average fare over those 7 days, that direction''s flights only (game_flights, matched to the route either way round); its level as a % of the game''s default price (the latest the fare plan recorded before this Saturday for that direction, or for both directions (direction null) if that is later, else settings.fare_launch_pct) and steps above launch; the fare index: each flight of the latest captured day (latest_on, its average latest_fare) against its direction''s baseline, times the launch level, the baseline being the direction''s fare on the latest captured day on or before 21 Oct 2026, when every route was at its launch level (Gitesh), or for a route launched later its first captured fare if captured in its first growth_new_route_days days (a day''s fare: its flights'' lowest, else route_days'' average fare in that cabin, eco_fare_avg and, since 22 Oct, bus_fare_avg on a day with business passengers, so a baseline survives the flights'' archiving in both cabins; baseline_fare and baseline_on, the directions'' average and latest day); fare_index the flights'' average, index_matches false when any flight is more than 1 point off the level the game should show (this week''s new level once the captures see it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, for fare_ladder_hold_weeks after a recorded step down, while the newest rotation is under fare_ladder_capacity_hold_days old on a route older than that (a flight added: "judged at its new size from ..."; a frequency taken away isn''t tracked, its rotation is deleted), and, since 21 Oct, while a rival threatens the pair (private.competition_threats(), as competition() lists them: a rival who started there or added competition_threat_min_weekly departures a week in a scan of the 7 days before the moment; "rival Air China started here on 22 Oct: paused until 29 Oct", the one paused longest), checked after planned, new, few, held and added and before the sold-out share; never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes; fix, a change that sets it back to its level (index_matches false, not on the fare plan this week, not a new route, and captured since its newest rotation launched), with fix_reason ("captured fare at 100%, level 110%"). moves, to_plan and planned count the rows (directions), off_level the directions set back. actions: the Ticket price adjustments (baseline default price), route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): first the set-back changes (fix true, with the reason), then the week''s moves, each in the rows'' order (hub, dest, out before back), one action per direction (From and To its airports; since 26 Oct) with classes ["economy","business"] when both cabins go to the same level, otherwise one for each cabin, economy first; a direction whose levels don''t change gets no action. Each action has n, route, classes, from, to, level, sign, pct, baseline, fix, reason (a set-back''s) and text, the text in the game''s words naming the classes. settings: the numbers used, with capacity_hold_days and baseline_day. notes: how the index reads. Since 23 Oct, under launch: a cabin at launch never jumped whose ladder result is to hold at launch (under fare_ladder_down_share sold out), with at least fare_under_launch_min_flights flights in the fare_under_launch_days before the moment, all at launch (no level change recorded in them), averaging under fare_under_launch_load_pct full, jumps to the first of fare_under_launch_levels (move down, ladder_kind jump; "41% full over 14 days at launch: to 80% for 2 weeks"); fewer flights, it waits, saying how many. It holds fare_under_launch_days from the day the captures saw the jump (fare_plan_status()''s rule, else the day proposed; "at 80% since 25 Oct: judged on 8 Nov"), then is judged with at least fare_under_launch_min_flights flights since then against its launch baseline, revenue a flight (pax × fare in the cabin) over the fare_under_launch_days before its first jump (the daily history''s for days whose flights are archived): not lower, it stays and the normal ladder goes on from there; lower with a next level, it jumps again; at the last level, lower, it reverts to launch (move up, ladder_kind revert), or not lower but under fare_under_launch_decide_load_pct full, it holds: either way decide is true and the reason asks "cut or keep? (Saturday review)". A revert, or a row recorded after the latest jump, marks the cabin done: no more jumps. Under launch, the ladder only climbs or holds ("under launch: climbs or holds only"). Each route row has ladder_kind (up, down, hold, jump or revert: what Put on the fare plan writes as ladder_move), under_launch (state launch, holding, due or done; baseline_revenue, window_revenue, window_load and window_flights, jumped_on and judge_on, where they apply) and decide; moves counts jumps and decisions too; settings.under_launch the numbers used. Staff only; runs as owner and checks the caller itself. Per direction (since 26 Oct): each direction''s level, move, the hold after a step down, under launch''s jumps (window, launch baseline and judgement on that direction''s flights) and the set-back are its own; a new route, the capacity hold after a new frequency, the rival pause and whether the pair is contested (the 60% floor) are the whole route''s, given on both its directions'' rows.';
comment on function public.fare_plan_status(bigint, timestamptz) is 'Performance''s fare plan for one airline (#18 build pull request 10, Review''s until 20 Oct; the old planner''s routeFares and farePlanStatus), from the fares and loads its captures give for each of its routes, both directions (the last 9 days'' loads, one per date and flight number): plan, each fare change not dropped (fare_plan, by id) with its row''s fields and updated_at, the fare now (the latest captured day''s average), the target (fare then × (1 + change)), applied and seen_on and the average load before and after that day. A fare test (no level_pct) is read in economy and seen on the first captured day on or after it was proposed whose average fare shows at least half the change; a fare ladder''s row (level_pct and ladder_move, since 21 Oct, manual §5) is read in its own cabin (business on flights with business seats) and seen when the day''s average fare is the fare then times (1 + change), within 1%. And fares: each route''s latest captured day with its average economy fare (what "+ fare plan" starts from). Since 26 Oct a row with a direction (out from the route''s hub, back to it) is read and seen on that direction''s flights only, and plan gives each row''s direction (null for both). Staff only; runs as owner and checks the caller itself.';
comment on function public.capture_fare_actions(text) is 'For the fares userscript (capture/fares_apply.user.js; manual §5, since 21 Oct; specs docs/specs/2026-10-21-fares-userscript.md and docs/specs/2026-10-21-frequencies-and-fares.md §3), with the capture key: the game''s Ticket price adjustments still to make. For each active airline of our groups in the key''s world, in display order (as capture_airlines()), its fare_ladder() actions that set a route back to its level (fix true: they need no fare plan row, and the index matching again is the proof), and those whose route is on the fare plan this week and not yet seen in the captures (every class the action names is a route row of the action''s direction, since 26 Oct, with planned true and applied false), in fare_ladder()''s order (the set-back changes first). airlines: each airline''s game_id, name (the website''s, else the planner''s), game_name, code, count of actions and fixes (how many of them set a route back); actions: each with game_id and airline (its name), n (the action''s number in fare_ladder()), route (HUB–DEST), from and to (IATA), level (% of the default price), sign (+ or -) and pct (the game''s percent, a whole number), classes (economy and/or business), plan_ids (the fare plan rows, one per class in the same order; none for a set-back change), fix and reason (a set-back''s, "captured fare at 100%, level 110%") and text (the action in words); week_of (this Saturday) and as_of. A wrong or missing key gets {"ok": false, "error": "bad key"} and nothing else. Runs as owner with an empty search path and its own statement limit of 30 seconds (it works out every airline''s fare ladder in one call, signed out).';
comment on function public.route_story(bigint, timestamptz) is 'A route''s story since launch (spec docs/specs/2026-10-21-route-page.md §2), as of p_as_of: the planner''s route page (/planner/performance/<code>/<route>), and the Scheduling chat''s "how has this route done since launch, and what changed on it". The route is its airline''s hub and destination; both directions are counted together. route: id, hub, dest, pair, city, stars, distance_km (overrides applied), market (id, name, layout), cabin (layout: its own cabin_choice, else its market''s, as Routes'' header; own; market_layout), removed, airline (id, code, name), launched (its earliest rotation''s launch day, as route profit and the fare ladder find a route''s age, else its first day in route_days; launched_from rotation or history; launched_days). now: departures a week each way from the live schedule (out from the hub, back), rotations, the aircraft types flying it with how many aircraft, fares (fare_ladder()''s rows for the route, since 26 Oct one per direction and cabin, out before back and economy first, each with direction, from and to: level, steps, this Saturday''s move, new_level, reason, planned, applied, to_plan, fix, fare_index and the rest), launch_pct and week_of. latest_day: the airline''s latest day in the daily history by the moment. days: one row per UTC day with flights, from launch or the last 90 days if longer to latest_day (route_days, both directions; rows of no route matched by the airports): flights, passengers, seats, load_pct (passengers on the flights whose loads were captured ÷ their seats), eco_ and bus_ passengers, seats and load_pct, eco_fare and bus_fare (weighted by passengers), revenue, costs and profit (millions of AS$), block_hours and profit_per_hour (profit ÷ block hours). weeks: the same in 7-day blocks ending on latest_day (from, to, days with flights), newest first, at most 13. events, newest first, each with day, kind and words: launched; frequency added, frequency removed, aircraft changed and retimed from change_log on rotations and flight_legs (one per save, its txid; a save''s rotations that are the launch itself and a migration''s changes left out); fare, each fare_plan row (cabin, level or change_pct, move, dropped, and since 26 Oct its direction, named first in its words, "out: economy up to 105%"); cabin, the route''s cabin_choice changed; rival, a rival that started on the pair or added settings.competition_threat_min_weekly departures a week between consecutive finished scans since launch with their schedules (private.scan_pair_flights(), passenger flights only, as competition_threats()). rivals: from the latest finished scan (scan) with the week-before scan (week_before, as competition() picks it), every rival flying the pair either way with its departures a week, before and change; ours (the live schedule, both ways), rivals_weekly and our share; ours_before, rivals_before and share_before (the airline''s flights in the week-before scan, as competition()''s me_then); shares, our share at each finished scan since launch (scan_id, taken_at, ours, rivals, share). scans: latest, week_before and since_launch with their dates. notes say how it reads. Staff only; runs as owner and checks the caller itself. Read with GET. Connecting (since 23 Oct; spec docs/specs/2026-10-23-rival-connections.md §3): in rivals, each rival on the pair has connecting_weekly and connecting_via (its one-stop departures a week on the pair in the latest scan, both ways, and its top 3 connecting airports), beside weekly and never added to it, rivals_weekly or the share; rivals also has connecting_weekly (every rival''s), connecting_only (the rivals with no direct flight that connect) and connecting_scans (each rival''s connecting departures and airports at each scan read that has them worked out). Absent when the latest scan has none worked out. Weekly points (since 23 Oct; spec docs/specs/2026-10-23-rival-pairs-history.md §3): a scan whose schedules the monthly archive has taken is read from scan_pair_airlines (the week''s kept scan, kept for good; passenger rows), the same figures, and marked weekly true in rivals.shares, scans.since_launch and the scan refs; rivals.weekly_points counts them and rivals.daily_from is the first point read from full schedules. Connections only on the scans with their schedules.';

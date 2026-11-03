-- The fare ladder's second jump under launch needs the load cut-off too (2 Nov 2026; to-do 197, manual §5, decided 2 Nov,
-- Gitesh, Review chat: "that should also have the 80% cut-off").
--
-- Why: since 26 Oct a cabin due at a jump level (80%, Ryanair 75%) that is under 90% sold out jumps to 60% on the sold-out
-- share alone, so a cabin nearly full but not selling out every flight still drops. KUL–TRV's business cabin, 89–94% full
-- at 80% but sold out on 4 of 6 and 5 of 7, would have jumped on 13 Nov. The first jump has always needed under 80% full
-- (fare_under_launch_load_pct); the next jump now needs the same, over the fare_under_launch_days (14) before the moment,
-- none before the jump took effect. 80% full or more (or no flights in that window) it holds at its level and is judged
-- again the next Saturday ("... but 88% full over 14 days: holds at 80%, judged again next Saturday"); nothing goes on the
-- fare plan for it. At the last level the cut-or-keep test is unchanged.
--
-- Replaces one function with the same arguments (private.fig_fare_ladder); its answer's under_launch gains judged_load and
-- judged_flights for a cabin due. Changes, drops and renames nothing else, so it can be applied from the chat.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261102240000_second_jump_load_cutoff', true);

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
  v_step numeric; v_up numeric; v_down numeric; v_min numeric; v_hold numeric; v_up_hold numeric; v_cap numeric; v_launch numeric; v_floor numeric;
  v_new_days numeric; v_added_days numeric;
  -- every route was at its launch level on 21 Oct 2026 (Gitesh; manual §5): each route's fare that day is its baseline
  v_base_day constant date := date '2026-10-21';
  v_scan bigint; v_scan_at timestamptz;
  v_rows jsonb; v_actions jsonb := '[]'::jsonb; v_n int := 0;
  v_r record; v_sets jsonb; v_change jsonb; v_lv numeric; v_words text;
  -- the fare ladder under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md; judged by loads
  -- since 26 Oct, spec docs/specs/2026-10-26-under-launch-by-loads.md)
  v_ul_load numeric; v_ul_days numeric; v_ul_min numeric; v_ul_levels numeric[]; v_ul_below numeric[]; v_ul_j jsonb; v_ul_span text;
begin
  v_step := private.fig_num(w, p_airline_id, 'fare_ladder_step_pts');
  v_up := private.fig_num(w, p_airline_id, 'fare_ladder_up_share');
  v_down := private.fig_num(w, p_airline_id, 'fare_ladder_down_share');
  v_min := private.fig_num(w, p_airline_id, 'fare_ladder_min_departures');
  v_hold := private.fig_num(w, p_airline_id, 'fare_ladder_hold_weeks');
  -- the hold after a step up (since 26 Oct, manual §5): bookings open 3 days ahead (§9), so the week after a change mostly
  -- flies at the old price
  v_up_hold := private.fig_num(w, p_airline_id, 'fare_ladder_up_hold_weeks');
  v_cap := private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_launch := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  v_added_days := private.fig_num(w, p_airline_id, 'fare_ladder_capacity_hold_days');
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
  -- under launch: a cabin at launch averaging under fare_under_launch_load_pct full over fare_under_launch_days jumps to
  -- the first of fare_under_launch_levels, holds that many days and is then judged on its loads like any direction (since
  -- 26 Oct; fare_under_launch_decide_load_pct is no longer read). An airline's own row wins over the world's, as fig_num()
  -- reads them
  v_ul_load := private.fig_num(w, p_airline_id, 'fare_under_launch_load_pct');
  v_ul_days := private.fig_num(w, p_airline_id, 'fare_under_launch_days');
  v_ul_min := private.fig_num(w, p_airline_id, 'fare_under_launch_min_flights');
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
                   f.eco_pct, f.eco_fare, f.bus_pct, f.bus_seats, f.bus_fare
              from public.game_flights f
             where f.airline_id = p_airline_id and f.flight_no is not null and f.loads_captured_at <= p_as_of and f.game_date <= v_today
             order by f.game_date, f.flight_no, f.id desc) x
      left join ro r1 on r1.hub_code = x.o and r1.dest_code = x.d
      left join ro r2 on r2.hub_code = x.d and r2.dest_code = x.o
     where coalesce(r1.id, r2.id) is not null),
  -- by cabin: economy on every row with its load, business on flights with business seats; each with its direction (o)
  lc as materialized (
    select lf.route_id, 'economy'::text as cabin, lf.dir, lf.o, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') as at from lf where lf.eco_pct is not null
    union all
    select lf.route_id, 'business', lf.dir, lf.o, lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare,
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
  -- the latest step up before this Saturday (since 26 Oct, manual §5), a both-directions row counting for both as above.
  -- Only up: a jump and a set-back never start this hold (nor a revert, recorded before 26 Oct)
  upr as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as up_on from rec r where r.ladder_move = 'up' and r.proposed_on < v_week group by 1, 2, 3),
  -- under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md §2), per direction since 26 Oct,
  -- judged by loads since 26 Oct (spec docs/specs/2026-10-26-under-launch-by-loads.md). Each cabin's day by day fare, each
  -- direction's and both directions' together (dir 'both', for a both-directions row), and its jumps recorded before this
  -- Saturday, each with the day it took effect: the first captured day on or after it was proposed whose fare (the row's
  -- direction's, or both directions' for a both-directions row) is the fare then times its ratio, within 1%
  -- (fare_plan_status()'s rule, read over every captured day, so the day holds once the flights are older than its 10
  -- days), else the day proposed
  cday as materialized (select lc.route_id, lc.cabin, coalesce(lc.dir, 'both') as dir, lc.game_date as day, avg(lc.fare) as fare
                          from lc where lc.fare > 0 group by grouping sets ((lc.route_id, lc.cabin, lc.dir, lc.game_date), (lc.route_id, lc.cabin, lc.game_date))),
  jr as (select r.id, r.route_id, r.cabin, r.dir, r.level_pct, r.proposed_on,
                coalesce((select min(c.day) from cday c
                           where c.route_id = r.route_id and c.cabin = r.cabin and c.dir = coalesce(r.direction, 'both') and c.day >= r.proposed_on and r.fare_from > 0
                             and abs(c.fare / r.fare_from - (1 + coalesce(r.change_pct, 0) / 100)) <= 0.01), r.proposed_on) as on_day
           from rec r where r.ladder_move = 'jump' and r.proposed_on < v_week),
  jl as (select distinct on (jr.route_id, jr.cabin, jr.dir) jr.route_id, jr.cabin, jr.dir, jr.id, jr.proposed_on, jr.on_day as jumped_on
           from jr order by jr.route_id, jr.cabin, jr.dir, jr.proposed_on desc, jr.id desc),
  -- done: a step recorded after the latest jump (it climbed: under launch the ladder then only climbs or holds, and never
  -- jumps again), or a revert recorded before 26 Oct (back at launch): no more jumps for that cabin and direction. A hold
  -- row doesn't end it (since 26 Oct)
  ud as (select jl.route_id, jl.cabin, jl.dir from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.dir = jl.dir and r.proposed_on < v_week
                           and (r.ladder_move = 'revert' or (r.ladder_move in ('up', 'down') and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))))),
  -- marked: a hold recorded after the latest jump (since 26 Oct the cut-or-keep mark, put on the fare plan the first
  -- Saturday a cabin at the last jump level is judged under fare_ladder_down_share sold out; before then the judgement
  -- that a jump paid): at the last level the cabin stays marked until it climbs
  um as (select jl.route_id, jl.cabin, jl.dir from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.dir = jl.dir and r.proposed_on < v_week
                           and r.ladder_move = 'hold' and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))),
  -- the latest recorded level change (any row but a hold): at launch, the window must be all at that level
  lch as (select r.route_id, r.cabin, r.dir, max(r.proposed_on) as changed_on from rec r where r.ladder_move is distinct from 'hold' group by 1, 2, 3),
  -- the window at launch: the fare_under_launch_days before the moment, by scheduled departure, the direction's flights
  uw as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
           from lc where lc.at >= p_as_of - make_interval(days => v_ul_days::int) and lc.at < p_as_of group by 1, 2, 3),
  -- at the jump level: the direction's flights since the latest jump took effect, to the moment (shown, not judged on)
  uj as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
           from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin and jl.dir = lc.dir
          where lc.at >= jl.jumped_on::timestamp at time zone 'UTC' and lc.at < p_as_of
          group by 1, 2, 3),
  -- the window a cabin due at a jump level is judged on (since 2 Nov, manual §5): the fare_under_launch_days before the
  -- moment, none before the jump took effect; under fare_under_launch_load_pct full it may jump again
  ujw as (select lc.route_id, lc.cabin, lc.dir, count(*)::int as n, avg(lc.pct) as load
            from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin and jl.dir = lc.dir
           where lc.at >= greatest(jl.jumped_on::timestamp at time zone 'UTC', p_as_of - make_interval(days => v_ul_days::int)) and lc.at < p_as_of
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
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, upr.up_on, ag.first_day, ad.last_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested,
                th.rival as rv_name, th.kind as rv_kind, th.added_weekly as rv_added, th.scan_at as rv_on, th.until as rv_until,
                jl.jumped_on, ud.route_id is not null as ul_done, um.route_id is not null as ul_marked, lch.changed_on,
                coalesce(uw.n, 0) as w_n, uw.load as w_load,
                coalesce(uj.n, 0) as j_n, uj.load as j_load,
                coalesce(ujw.n, 0) as jw_n, ujw.load as jw_load
           from rc join ro on ro.id = rc.route_id
           left join thr th on th.a = least(ro.hub_code, ro.dest_code) and th.b = greatest(ro.hub_code, ro.dest_code)
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin and st.dir = rc.dir
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin and lt.dir = rc.dir
           left join bs on bs.route_id = rc.route_id and bs.cabin = rc.cabin and bs.dir = rc.dir
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin and pv.dir = rc.dir
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin and wk.dir = rc.dir
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin and dn.dir = rc.dir
           left join upr on upr.route_id = rc.route_id and upr.cabin = rc.cabin and upr.dir = rc.dir
           left join age ag on ag.route_id = rc.route_id
           left join added ad on ad.route_id = rc.route_id
           left join jl on jl.route_id = rc.route_id and jl.cabin = rc.cabin and jl.dir = rc.dir
           left join ud on ud.route_id = rc.route_id and ud.cabin = rc.cabin and ud.dir = rc.dir
           left join um on um.route_id = rc.route_id and um.cabin = rc.cabin and um.dir = rc.dir
           left join lch on lch.route_id = rc.route_id and lch.cabin = rc.cabin and lch.dir = rc.dir
           left join uw on uw.route_id = rc.route_id and uw.cabin = rc.cabin and uw.dir = rc.dir
           left join uj on uj.route_id = rc.route_id and uj.cabin = rc.cabin and uj.dir = rc.dir
           left join ujw on ujw.route_id = rc.route_id and ujw.cabin = rc.cabin and ujw.dir = rc.dir),
  mv0 as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                v_launch + v_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(v_launch, case when lv.contested then v_floor end) as floor_pct,
                coalesce(lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held,
                -- the hold after a step up (since 26 Oct): the next Saturday, fare_ladder_up_hold_weeks
                coalesce(lv.up_on is not null and v_week - lv.up_on < v_up_hold * 7, false) as held_up,
                -- a flight added in the last fare_ladder_capacity_hold_days, to a route older than that (manual §5, since 21 Oct)
                coalesce(lv.last_day is not null and v_today - lv.last_day < v_added_days
                         and lv.first_day is not null and v_today - lv.first_day >= v_added_days, false) as added,
                -- under launch (since 23 Oct): the cabin's state, from the fare plan's rows before this Saturday. launch: at
                -- its launch level and never jumped; holding: its latest jump under fare_under_launch_days old, counted from
                -- the day it took effect; due: the hold is over, still at the jump level, judged on its loads each Saturday
                -- (since 26 Oct); done: it climbed after the jump, or is back at launch (a revert before 26 Oct)
                case when lv.jumped_on is null then case when lv.level = v_launch and v_ul_below is not null then 'launch' end
                     when lv.ul_done or lv.level >= v_launch then 'done'
                     when v_today - lv.jumped_on < v_ul_days then 'holding'
                     else 'due' end as ul_state,
                lv.jumped_on + v_ul_days::int as judge_on,
                -- the latest recorded level change (a cabin back at launch after a step down): the window must have none,
                -- so all its flights are at the launch level (spec §2); a new route waits as before (growth_new_route_days)
                lv.changed_on as launch_since,
                -- the jump levels under the cabin's level: the next is the first of them; at the last, none is left
                (select u.l from unnest(v_ul_below) with ordinality as u(l, i) where u.l < lv.level order by u.i limit 1) as next_level
           from lv),
  -- the under-launch kind (spec §2), worked out before this week's plan so a move put on the plan this week keeps it.
  -- Since 26 Oct (spec docs/specs/2026-10-26-under-launch-by-loads.md) a cabin due is judged on the week's loads as any
  -- direction: sold out it steps up and 90–99% sold out it holds (the normal ladder's own kinds); under 90% sold out, with
  -- the minimum departures, it jumps to the next level, or at the last level holds there marked cut or keep? Since 2 Nov
  -- (manual §5) the next jump also needs the cabin under fare_under_launch_load_pct full over its last fare_under_launch_days
  -- since the jump (ujw), as the first jump does; 80% full or more (or no flights in that window) it holds at its level
  -- (ul_full) and is judged again the next Saturday. The cut-or-keep test at the last level is unchanged.
  mv as (select mv0.*,
                case
                  when mv0.ul_state = 'launch' then
                    case when mv0.share >= v_down or mv0.n < v_min or mv0.w_load is null or mv0.w_load >= v_ul_load then null
                         when mv0.launch_since is not null and p_as_of - make_interval(days => v_ul_days::int) < mv0.launch_since::timestamp at time zone 'UTC' then 'ul_since'
                         when mv0.w_n < v_ul_min then 'ul_few'
                         else 'ul_jump' end
                  when mv0.ul_state = 'holding' then 'ul_hold'
                  when mv0.ul_state = 'due' then
                    case when mv0.n < v_min or mv0.share >= v_down then null
                         when mv0.next_level is not null and (mv0.jw_load is null or mv0.jw_load >= v_ul_load) then 'ul_full'
                         when mv0.next_level is not null then 'ul_jump'
                         else 'ul_decide' end
                end as uk
           from mv0),
  dc as (select mv.*,
                case when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     -- a direction held both ways takes the more recent move's reason (the step down on the same day)
                     when mv.held and not (mv.held_up and mv.up_on > mv.down_on) then 'held'
                     when mv.held_up then 'held_up'
                     when mv.added then 'added'
                     when mv.rv_name is not null then 'rival'
                     -- under launch (since 23 Oct; spec §2): the jump at launch only where the ladder would hold at launch
                     -- (under fare_ladder_down_share sold out); the hold whatever it sells; once due (since 26 Oct) the next
                     -- jump or the cut-or-keep hold under fare_ladder_down_share sold out, else the normal ladder below
                     when mv.uk in ('ul_hold', 'ul_decide', 'ul_full') or (mv.uk = 'ul_jump' and mv.ul_state = 'due') then mv.uk
                     when mv.uk in ('ul_jump', 'ul_few', 'ul_since') and mv.level <= mv.floor_pct then mv.uk
                     -- under launch, once jumped, the ladder only climbs or holds (never a 5-point step down)
                     when mv.level < v_launch and mv.share < v_down then 'ul_climb'
                     when mv.share >= v_up then case when mv.level >= mv.cap_pct then 'capped' else 'up' end
                     when mv.share >= v_down then 'hold'
                     when mv.level <= mv.floor_pct then 'floor'
                     else 'down' end as k
           from mv),
  fin as (select dc.*,
                 -- a jump is a move down (since 23 Oct), so existing readers keep working; ladder_kind says which (a revert
                 -- on the fare plan, recorded before 26 Oct, is a move up)
                 case dc.k when 'planned' then case dc.plan_move when 'jump' then 'down' when 'revert' then 'up' else dc.plan_move end
                           when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'down' else 'hold' end as move,
                 case dc.k when 'planned' then dc.plan_move when 'up' then 'up' when 'down' then 'down' when 'ul_jump' then 'jump'
                           else 'hold' end as ladder_kind,
                 case dc.k when 'planned' then dc.plan_level
                           when 'up' then least(dc.level + v_step, dc.cap_pct)
                           when 'down' then greatest(dc.level - v_step, dc.floor_pct)
                           when 'ul_jump' then dc.next_level
                           else dc.level end as new_level,
                 -- a cut-or-keep decision for Gitesh (since 23 Oct; by loads since 26 Oct): due at the last jump level and
                 -- held there this Saturday under fare_ladder_down_share sold out (or that hold put on the fare plan this
                 -- week), or marked so before (a hold recorded after the jump); it stays marked, whatever holds it, until it
                 -- climbs (a step up this Saturday, or on the fare plan)
                 coalesce(dc.ul_state = 'due' and dc.next_level is null
                          and (dc.k = 'ul_decide' or (dc.k = 'planned' and dc.uk = 'ul_decide') or dc.ul_marked)
                          and dc.k <> 'up' and not (dc.k = 'planned' and dc.plan_move is not distinct from 'up'), false) as decide,
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
                   when 'held_up' then format('held after a step up on %s', to_char(fin.up_on, 'FMDD Mon'))
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
                     then format('at %s%% since %s: sold out %s of %s: to %s%% for %s', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'),
                                 fin.sold, fin.n, trim_scale(fin.next_level), v_ul_span)
                     else format('%s%% full over %s days at launch: to %s%% for %s', round(fin.w_load), trim_scale(v_ul_days), trim_scale(fin.next_level), v_ul_span) end
                   when 'ul_full' then case when fin.jw_load is null
                     then format('at %s%% since %s: sold out %s of %s, no flights in the last %s days: holds at %s%%', trim_scale(fin.level),
                                 to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, trim_scale(v_ul_days), trim_scale(fin.level))
                     else format('at %s%% since %s: sold out %s of %s but %s%% full over %s days: holds at %s%%, judged again next Saturday', trim_scale(fin.level),
                                 to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, round(fin.jw_load), trim_scale(v_ul_days), trim_scale(fin.level)) end
                   when 'ul_hold' then format('at %s%% since %s: judged on %s', trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'), to_char(fin.judge_on, 'FMDD Mon'))
                   when 'ul_decide' then format('at %s%% since %s: sold out %s of %s: holds at %s%%; cut or keep? (Saturday review)',
                                                trim_scale(fin.level), to_char(fin.jumped_on, 'FMDD Mon'), fin.sold, fin.n, trim_scale(fin.level))
                   when 'ul_few' then format('sold out %s of %s, at %s: %s flight%s in %s days, needs %s to jump', fin.sold, fin.n, fin.floor_words, fin.w_n,
                                             case when fin.w_n = 1 then '' else 's' end, trim_scale(v_ul_days), trim_scale(v_ul_min))
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
           -- what Put on the fare plan writes: every level that changes (jumps included), a hold that follows a step down,
           -- and since 26 Oct the first cut-or-keep hold under launch (so the mark stays)
           'to_plan', o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k = 'held' or (o.k = 'ul_decide' and not o.ul_marked)),
           -- under launch (since 23 Oct): what Put on the fare plan writes as ladder_move, the cabin's state with its
           -- figures, and whether it is a cut-or-keep decision for Gitesh
           'ladder_kind', o.ladder_kind,
           'under_launch', case when o.ul_state is not null then jsonb_strip_nulls(jsonb_build_object(
             'state', o.ul_state,
             'window_load', round(case when o.ul_state = 'launch' then o.w_load else o.j_load end, 1),
             'window_flights', case when o.ul_state = 'launch' then o.w_n else o.j_n end,
             'jumped_on', o.jumped_on, 'judge_on', o.judge_on,
             -- since 2 Nov: the window a cabin due is judged on (the last fare_under_launch_days since the jump)
             'judged_load', case when o.ul_state = 'due' then round(o.jw_load, 1) end,
             'judged_flights', case when o.ul_state = 'due' then o.jw_n end)) end,
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
                                   'hold_weeks', v_hold, 'up_hold_weeks', v_up_hold, 'cap_pts', v_cap, 'launch_pct', v_launch, 'cap_pct', v_launch + v_cap,
                                   'floor_pct', v_floor, 'new_route_days', v_new_days, 'capacity_hold_days', v_added_days,
                                   'baseline_day', v_base_day,
                                   'under_launch', jsonb_build_object('load_pct', v_ul_load, 'levels', to_jsonb(v_ul_levels), 'days', v_ul_days,
                                                                      'min_flights', v_ul_min)),
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

do $describe$
declare d text;
begin
  d := obj_description('private.fig_fare_ladder(bigint, timestamptz)'::regprocedure, 'pg_proc');
  if position('load cut-off (since 2 Nov' in coalesce(d, '')) = 0 then
    execute format('comment on function private.fig_fare_ladder(bigint, timestamptz) is %L',
                   coalesce(d, '') || ' The next jump under launch needs the load cut-off (since 2 Nov, manual §5): a cabin due at a jump level and under 90% sold out jumps only when it is also under fare_under_launch_load_pct full over the fare_under_launch_days since the jump (under_launch.judged_load and judged_flights); 80% full or more it holds at its level and is judged again the next Saturday.');
  end if;
  d := obj_description('public.fare_ladder(bigint, timestamptz)'::regprocedure, 'pg_proc');
  if position('load cut-off (since 2 Nov' in coalesce(d, '')) = 0 then
    execute format('comment on function public.fare_ladder(bigint, timestamptz) is %L',
                   coalesce(d, '') || ' The next jump under launch needs the load cut-off (since 2 Nov): under fare_under_launch_load_pct full over the 14 days since the jump, else it holds at its level.');
  end if;
end
$describe$;

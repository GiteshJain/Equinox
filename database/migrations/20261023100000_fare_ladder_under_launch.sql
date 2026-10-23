-- The fare ladder under launch (23 Oct 2026; manual's "Decided, not yet built"; spec
-- docs/specs/2026-10-23-fare-ladder-under-launch.md, brief docs/briefs/2026-10-23-fare-ladder-under-launch.md, Gitesh).
--
-- Why: today a cabin under 90% sold out at launch is marked floor and holds there for ever. Gitesh decided on 23 Oct that
-- a cabin that doesn't fill may go under launch, in two jumps a fortnight's revenue can read (80%, then 60%), each judged
-- on revenue a flight against its launch baseline, ending in a cut-or-keep decision when the last level doesn't work.
--
-- Adds settings and replaces one function with the same arguments; drops and renames nothing, so it can be applied from
-- the chat:
--   1. five settings in every world, described: fare_under_launch_load_pct 80, fare_under_launch_levels [80, 60],
--      fare_under_launch_days 14, fare_under_launch_min_flights 10 and fare_under_launch_decide_load_pct 60; and
--      Ryanair's own fare_under_launch_levels, [75, 60] (Gitesh, 23 Oct: its launch is 85%, so 80% would be too small a
--      jump to read).
--   2. fare_plan.ladder_move also takes jump and revert (the check widened), described.
--   3. private.fig_fare_ladder() (so fare_ladder(), and what reads it: capture_fare_actions(), the briefing, route_story()
--      and the plan card's fare levels): the under-launch state of each cabin from its fare plan rows, the jump at launch,
--      the hold, the judgement on revenue a flight, the revert or hold with decide, and "under launch: climbs or holds
--      only". Moves above launch, the holds, the rival pause, set back, the actions and the notes are as they were. Each
--      route row gains ladder_kind, under_launch and decide; moves gains jumps and decisions; settings gains
--      under_launch. A jump is move down and a revert move up, so existing readers keep working; a level under 100 is
--      already a "−" action.
--   The grants stay as they were.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261023100000_fare_ladder_under_launch', true);

-- ============================================================ 1. the numbers, as settings (manual §1)
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, s.key, s.value, s.unit, s.description, date '2026-10-23', s.reason
  from public.worlds w
 cross join (values
   ('fare_under_launch_load_pct', '80'::jsonb, 'percent',
    'The fare ladder under launch: a cabin at its launch level averaging under this % full over fare_under_launch_days, with the ladder holding it at launch (under fare_ladder_down_share sold out), jumps to the first of fare_under_launch_levels (manual §5)',
    'Gitesh, 23 Oct: a cut only pays where the cabin doesn''t fill; option C of the under-launch brief'),
   ('fare_under_launch_levels', '[80, 60]'::jsonb, '% of default price',
    'The fare ladder under launch: the jump levels, % of the game''s default price, in order. The last is the floor under launch; a level at or above an airline''s launch is skipped. An airline may have its own row',
    'Gitesh, 23 Oct: two jumps instead of 2-point steps, so a fortnight''s revenue a flight can read each one'),
   ('fare_under_launch_days', '14'::jsonb, 'days',
    'The fare ladder under launch: the window. Days at launch before the first jump, and days held at a jump level (from the day the captures saw it) before it is judged on revenue a flight',
    'Gitesh, 23 Oct: two weeks per jump; one week''s revenue swings too much to read'),
   ('fare_under_launch_min_flights', '10'::jsonb, 'flights',
    'The fare ladder under launch: flights a cabin needs in a window to jump or be judged; with fewer it waits, and the reason says how many it has',
    'Gitesh, 23 Oct: each two-week judgement needs at least 10 flights'),
   ('fare_under_launch_decide_load_pct', '60'::jsonb, 'percent',
    'The fare ladder under launch: at the last jump level, a cabin still averaging under this % full goes to Gitesh as a cut-or-keep decision, even if its revenue a flight held up',
    'Gitesh, 23 Oct: at 60% and still under 60% full, a route is a cut-or-keep decision (weak routes get cut rather than launched cheap)')
 ) as s(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- Ryanair's own jump levels: its launch is 85%, so a first jump to 80% would be too small to read
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select a.world_id, a.id, 'fare_under_launch_levels', '[75, 60]'::jsonb, '% of default price',
       'Ryanair''s override of the fare ladder''s jump levels under launch, % of the default price, in order: its launch is 85%, so a first jump to 80% would be too small a jump to read',
       date '2026-10-23', 'Gitesh, 23 Oct: Ryanair launches at 85%; its first jump goes to 75%'
  from public.airlines a
 where a.id = 3 and a.planner_name = 'Ryanair'
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2. the fare plan records jumps and reverts
alter table public.fare_plan drop constraint fare_plan_ladder_move_check;
alter table public.fare_plan add constraint fare_plan_ladder_move_check check (ladder_move in ('up', 'down', 'hold', 'jump', 'revert'));
comment on column public.fare_plan.ladder_move is 'The fare ladder''s move: up, down or hold (a hold is recorded when it follows a step down, so the hold has a record, and since 23 Oct when a jump under launch is judged to stay); since 23 Oct also jump (a jump under launch, to a level of settings.fare_under_launch_levels) and revert (back to launch from the last jump level, a cut-or-keep decision). Null on a fare test that isn''t the ladder''s';

-- ============================================================ 3. the fare ladder under launch
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
  v_r record; v_sets jsonb; v_change jsonb; v_dir jsonb; v_lv numeric; v_words text;
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
  -- airline's list has it, either way round (as route profit matches them: route_id is often empty)
  lf as materialized (
    select coalesce(r1.id, r2.id) as route_id, x.*
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
    select lf.route_id, 'economy'::text as cabin, lf.o, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare, lf.eco_pax as pax,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') as at from lf where lf.eco_pct is not null
    union all
    select lf.route_id, 'business', lf.o, lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare, lf.bus_pax,
           coalesce(lf.dep_at, lf.game_date::timestamp at time zone 'UTC') from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known)
  st as (select lc.route_id, lc.cabin, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare
           from lc
          where coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') >= p_as_of - interval '7 days'
            and coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') < p_as_of
          group by lc.route_id, lc.cabin),
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
  bs as (select base.route_id, base.cabin, avg(base.fare) as fare, max(base.day) as day from base group by 1, 2),
  -- the latest captured day by cabin: its average fare, and each flight's fare against its direction's baseline
  lday as (select lc.route_id, lc.cabin, max(lc.game_date) as day from lc where lc.fare > 0 group by 1, 2),
  latest as (select ld.route_id, ld.cabin, ld.day, avg(lc.fare) as fare,
                    array_agg(lc.fare / b.fare order by lc.o, lc.dep_at) filter (where b.fare > 0) as ratios
               from lday ld
               join lc on lc.route_id = ld.route_id and lc.cabin = ld.cabin and lc.game_date = ld.day and lc.fare > 0
               left join base b on b.route_id = lc.route_id and b.cabin = lc.cabin and b.o = lc.o
              group by ld.route_id, ld.cabin, ld.day),
  -- the levels the fare plan recorded (manual §5): before this Saturday, the latest is the level; since it, this week's move
  rec as (select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, fp.level_pct, fp.ladder_move, fp.proposed_on, fp.reason,
                 fp.fare_from, fp.change_pct
            from public.fare_plan fp
           where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped'
             and fp.proposed_on <= v_today),
  prev as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on < v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  wk as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on >= v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  dn as (select r.route_id, r.cabin, max(r.proposed_on) as down_on from rec r where r.ladder_move = 'down' and r.proposed_on < v_week group by 1, 2),
  -- under launch (since 23 Oct; spec docs/specs/2026-10-23-fare-ladder-under-launch.md §2). Each cabin's day by day fare
  -- (both directions), and its jumps recorded before this Saturday, each with the day it took effect: the first captured
  -- day on or after it was proposed whose fare is the fare then times its ratio, within 1% (fare_plan_status()'s rule,
  -- read over every captured day, so the day holds once the flights are older than its 10 days), else the day proposed
  cday as materialized (select lc.route_id, lc.cabin, lc.game_date as day, avg(lc.fare) as fare from lc where lc.fare > 0 group by 1, 2, 3),
  jr as (select r.id, r.route_id, r.cabin, r.level_pct, r.proposed_on,
                coalesce((select min(c.day) from cday c
                           where c.route_id = r.route_id and c.cabin = r.cabin and c.day >= r.proposed_on and r.fare_from > 0
                             and abs(c.fare / r.fare_from - (1 + coalesce(r.change_pct, 0) / 100)) <= 0.01), r.proposed_on) as on_day
           from rec r where r.ladder_move = 'jump' and r.proposed_on < v_week),
  jf as (select distinct on (jr.route_id, jr.cabin) jr.route_id, jr.cabin, jr.on_day as first_on from jr order by jr.route_id, jr.cabin, jr.proposed_on, jr.id),
  jl as (select distinct on (jr.route_id, jr.cabin) jr.route_id, jr.cabin, jr.id, jr.proposed_on, jr.on_day as jumped_on
           from jr order by jr.route_id, jr.cabin, jr.proposed_on desc, jr.id desc),
  -- done: a revert recorded, or a row after the latest jump (the judgement that it paid, recorded as a hold, or the
  -- ladder's moves since): no more jumps for that cabin
  ud as (select jl.route_id, jl.cabin from jl
          where exists (select 1 from rec r where r.route_id = jl.route_id and r.cabin = jl.cabin and r.proposed_on < v_week
                           and (r.ladder_move = 'revert' or (r.ladder_move in ('up', 'down', 'hold') and (r.proposed_on, r.id) > (jl.proposed_on, jl.id))))),
  -- the latest recorded level change (any row but a hold): at launch, the window must be all at that level
  lch as (select r.route_id, r.cabin, max(r.proposed_on) as changed_on from rec r where r.ladder_move is distinct from 'hold' group by 1, 2),
  -- the window at launch: the fare_under_launch_days before the moment, by scheduled departure
  uw as (select lc.route_id, lc.cabin, count(*)::int as n, avg(lc.pct) as load, avg(lc.pax * lc.fare) as rev
           from lc where lc.at >= p_as_of - make_interval(days => v_ul_days::int) and lc.at < p_as_of group by 1, 2),
  -- the launch baseline: revenue a flight over the fare_under_launch_days before the first jump took effect. By the last
  -- level's judgement those days can be 6 weeks old and their flights archived: a day with no captured flights is read
  -- from the daily history instead (route_days: passengers × average fare in that cabin, over the day's flights)
  ubf as (select lc.route_id, lc.cabin, lc.game_date as day, count(*) as n, sum(lc.pax * lc.fare) as rev
            from lc join jf on jf.route_id = lc.route_id and jf.cabin = lc.cabin
           where lc.at >= (jf.first_on - v_ul_days::int)::timestamp at time zone 'UTC' and lc.at < jf.first_on::timestamp at time zone 'UTC'
             and lc.pax is not null and lc.fare is not null
           group by 1, 2, 3),
  ubh as (select jf.route_id, jf.cabin, d.day, sum(d.flights) as n,
                 sum(case jf.cabin when 'economy' then d.eco_pax * d.eco_fare_avg else d.bus_pax * d.bus_fare_avg end) as rev
            from jf
            join ro on ro.id = jf.route_id
            join public.route_days d on d.airline_id = p_airline_id
             and ((d.origin_code = ro.hub_code and d.dest_code = ro.dest_code) or (d.origin_code = ro.dest_code and d.dest_code = ro.hub_code))
           where d.day >= jf.first_on - v_ul_days::int and d.day < jf.first_on and d.flights > 0
             and case jf.cabin when 'economy' then d.eco_pax is not null and d.eco_fare_avg is not null
                               else d.bus_pax is not null and d.bus_fare_avg is not null end
             and not exists (select 1 from ubf where ubf.route_id = jf.route_id and ubf.cabin = jf.cabin and ubf.day = d.day)
           group by 1, 2, 3),
  ub as (select x.route_id, x.cabin, sum(x.rev) / nullif(sum(x.n), 0) as rev
           from (select ubf.route_id, ubf.cabin, ubf.n, ubf.rev from ubf union all select ubh.route_id, ubh.cabin, ubh.n, ubh.rev from ubh) x
          group by 1, 2),
  -- at the jump level: the flights since the latest jump took effect, to the moment
  uj as (select lc.route_id, lc.cabin, count(*)::int as n, avg(lc.pct) as load, avg(lc.pax * lc.fare) as rev
           from lc join jl on jl.route_id = lc.route_id and jl.cabin = lc.cabin
          where lc.at >= jl.jumped_on::timestamp at time zone 'UTC' and lc.at < p_as_of
          group by 1, 2),
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
  -- seats; any with flights captured in the 7 days or a move recorded this week
  rc as (select distinct x.route_id, x.cabin
           from (select f.route_id, 'economy'::text as cabin from fq f where f.live
                 union all select bz.route_id, 'business' from biz bz
                 union all select st.route_id, st.cabin from st
                 union all select wk.route_id, wk.cabin from wk) x
           join ro on ro.id = x.route_id),
  lv as (select rc.route_id, rc.cabin, ro.hub_code as hub, ro.dest_code as dest,
                coalesce(st.n, 0) as n, coalesce(st.sold, 0) as sold, st.fare as fare_week,
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
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin
           left join bs on bs.route_id = rc.route_id and bs.cabin = rc.cabin
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin
           left join age ag on ag.route_id = rc.route_id
           left join added ad on ad.route_id = rc.route_id
           left join jl on jl.route_id = rc.route_id and jl.cabin = rc.cabin
           left join jf on jf.route_id = rc.route_id and jf.cabin = rc.cabin
           left join ud on ud.route_id = rc.route_id and ud.cabin = rc.cabin
           left join lch on lch.route_id = rc.route_id and lch.cabin = rc.cabin
           left join uw on uw.route_id = rc.route_id and uw.cabin = rc.cabin
           left join ub on ub.route_id = rc.route_id and ub.cabin = rc.cabin
           left join uj on uj.route_id = rc.route_id and uj.cabin = rc.cabin),
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
           'route_id', o.route_id, 'hub', o.hub, 'dest', o.dest, 'cabin', o.cabin,
           'departures', o.n, 'sold_out', o.sold, 'sold_out_share', round(o.share, 1), 'average_fare', round(o.fare_week, 2),
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
           order by o.hub, o.dest, o.cabin desc), '[]'::jsonb)
    into v_rows from fx o;

  -- the game's Ticket price adjustments, route by route only (manual §5, since 21 Oct: never a whole base, so a route
  -- under 7 days old is never touched). Each sets the level with the baseline default price, and each direction is a
  -- change of its own (From A to B, From B to A). First the set-back changes (fix), then the week's moves, each in the
  -- routes' order (hub, dest): for each route, when both cabins go to the same level, one action each way with both
  -- classes ticked; otherwise one each way for each cabin, economy first. A route whose levels don't change gets no move.
  for v_r in select x.fix, x.hub, x.dest,
                    jsonb_agg(jsonb_build_object('cabin', x.cabin, 'level', x.level, 'reason', x.reason) order by x.cabin = 'business') as moves
               from (select true as fix, e ->> 'route_id' as route_id, e ->> 'hub' as hub, e ->> 'dest' as dest, e ->> 'cabin' as cabin,
                            (e ->> 'level')::numeric as level, e ->> 'fix_reason' as reason
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'fix')::boolean
                     union all
                     select false, e ->> 'route_id', e ->> 'hub', e ->> 'dest', e ->> 'cabin', (e ->> 'new_level')::numeric, null
                       from jsonb_array_elements(v_rows) e
                      where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric) x
              group by x.fix, x.route_id, x.hub, x.dest
              order by x.fix desc, x.hub, x.dest loop
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
      foreach v_dir in array array[jsonb_build_array(v_r.hub, v_r.dest), jsonb_build_array(v_r.dest, v_r.hub)] loop
        v_n := v_n + 1;
        v_actions := v_actions || jsonb_build_object(
          'n', v_n, 'route', v_r.hub || '–' || v_r.dest, 'classes', v_change -> 'classes', 'from', v_dir ->> 0, 'to', v_dir ->> 1,
          'level', trim_scale(v_lv), 'sign', case when v_lv >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_lv - 100)),
          'baseline', 'default price', 'fix', v_r.fix, 'reason', v_change ->> 'reason',
          'text', format('From %s to %s: %s%s%% of the default price, %s', v_dir ->> 0, v_dir ->> 1,
                         case when v_lv >= 100 then '+' else '−' end, trim_scale(abs(v_lv - 100)), v_words));
      end loop;
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
    'off_level', (select count(distinct e ->> 'route_id') from jsonb_array_elements(v_rows) e where (e ->> 'fix')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'The fare index compares each flight of the latest captured day with its direction''s fare on 21 Oct 2026, when every route was at its launch level (or its first captured fare, for a route launched later), times the launch level. A route more than 1 point off its level gets a change that sets it back, first in the list, unless it''s on the fare plan this week, new, or not captured since its newest flight launched.'));
end
$function$
;


-- ============================================================ 4. access and descriptions
-- The replaced function stays internal: nobody outside the database calls it.
revoke all on function private.fig_fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
comment on function private.fig_fare_ladder(bigint, timestamptz) is 'The captured figures (#19): builds fare_ladder()''s document with no check of its own. See fare_ladder().';
comment on function public.fare_ladder(bigint, timestamptz) is 'The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md, docs/specs/2026-10-21-fare-actions-by-route.md, docs/specs/2026-10-21-frequencies-and-fares.md and docs/specs/2026-10-21-competition-analysis.md §2, and since 23 Oct docs/specs/2026-10-23-fare-ladder-under-launch.md): this Saturday''s move for each route and cabin, the changes that set a route back to its level, and the game actions that make them. routes: each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin''s load at 100%), the sold-out share and the average fare over those 7 days (game_flights, matched to the route either way round); its level as a % of the game''s default price (the latest the fare plan recorded before this Saturday, else settings.fare_launch_pct) and steps above launch; the fare index: each flight of the latest captured day (latest_on, its average latest_fare) against its direction''s baseline, times the launch level, the baseline being the direction''s fare on the latest captured day on or before 21 Oct 2026, when every route was at its launch level (Gitesh), or for a route launched later its first captured fare if captured in its first growth_new_route_days days (a day''s fare: its flights'' lowest, else route_days'' average fare in that cabin, eco_fare_avg and, since 22 Oct, bus_fare_avg on a day with business passengers, so a baseline survives the flights'' archiving in both cabins; baseline_fare and baseline_on, the directions'' average and latest day); fare_index the flights'' average, index_matches false when any flight is more than 1 point off the level the game should show (this week''s new level once the captures see it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, for fare_ladder_hold_weeks after a recorded step down, while the newest rotation is under fare_ladder_capacity_hold_days old on a route older than that (a flight added: "judged at its new size from ..."; a frequency taken away isn''t tracked, its rotation is deleted), and, since 21 Oct, while a rival threatens the pair (private.competition_threats(), as competition() lists them: a rival who started there or added competition_threat_min_weekly departures a week in a scan of the 7 days before the moment; "rival Air China started here on 22 Oct: paused until 29 Oct", the one paused longest), checked after planned, new, few, held and added and before the sold-out share; never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes; fix, a change that sets it back to its level (index_matches false, not on the fare plan this week, not a new route, and captured since its newest rotation launched), with fix_reason ("captured fare at 100%, level 110%"). moves counts the moves, off_level the routes set back. actions: the Ticket price adjustments (baseline default price), route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): first the set-back changes (fix true, with the reason), then the week''s moves, each in the routes'' order (hub, dest), one action each way (From hub to dest, then From dest to hub) with classes ["economy","business"] when both cabins go to the same level, otherwise one each way for each cabin, economy first; a route whose levels don''t change gets no move. Each action has n, route, classes, from, to, level, sign, pct, baseline, fix, reason (a set-back''s) and text, the text in the game''s words naming the classes. settings: the numbers used, with capacity_hold_days and baseline_day. notes: how the index reads. Since 23 Oct, under launch: a cabin at launch never jumped whose ladder result is to hold at launch (under fare_ladder_down_share sold out), with at least fare_under_launch_min_flights flights in the fare_under_launch_days before the moment, all at launch (no level change recorded in them), averaging under fare_under_launch_load_pct full, jumps to the first of fare_under_launch_levels (move down, ladder_kind jump; "41% full over 14 days at launch: to 80% for 2 weeks"); fewer flights, it waits, saying how many. It holds fare_under_launch_days from the day the captures saw the jump (fare_plan_status()''s rule, else the day proposed; "at 80% since 25 Oct: judged on 8 Nov"), then is judged with at least fare_under_launch_min_flights flights since then against its launch baseline, revenue a flight (pax × fare in the cabin) over the fare_under_launch_days before its first jump (the daily history''s for days whose flights are archived): not lower, it stays and the normal ladder goes on from there; lower with a next level, it jumps again; at the last level, lower, it reverts to launch (move up, ladder_kind revert), or not lower but under fare_under_launch_decide_load_pct full, it holds: either way decide is true and the reason asks "cut or keep? (Saturday review)". A revert, or a row recorded after the latest jump, marks the cabin done: no more jumps. Under launch, the ladder only climbs or holds ("under launch: climbs or holds only"). Each route row has ladder_kind (up, down, hold, jump or revert: what Put on the fare plan writes as ladder_move), under_launch (state launch, holding, due or done; baseline_revenue, window_revenue, window_load and window_flights, jumped_on and judge_on, where they apply) and decide; moves counts jumps and decisions too; settings.under_launch the numbers used. Staff only; runs as owner and checks the caller itself.';

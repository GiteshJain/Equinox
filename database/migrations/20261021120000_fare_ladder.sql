-- The fare ladder, every Saturday (21 Oct 2026; manual §5; spec docs/specs/2026-10-21-fare-ladder.md, brief
-- docs/briefs/2026-10-21-fare-ladder.md, option A, Gitesh).
--
-- Why: almost every flight sells out at launch fares, and no fare had ever been raised. Each cabin of each route now has
-- a level, its fare as a % of the game's default price, and every Saturday it goes up 5 points when every flight of that
-- cabin sold out in the week, holds at 90–99%, and goes down 5 points under 90% (then holds for 2 weeks), at most 20
-- points above launch for now.
--
-- Adds, and replaces one function with the same arguments; drops and renames nothing, so it can be applied from the chat:
--   - six settings in every world: fare_ladder_step_pts 5, fare_ladder_up_share 100, fare_ladder_down_share 90,
--     fare_ladder_min_departures 5, fare_ladder_hold_weeks 2 and fare_ladder_cap_pts 20;
--   - two columns on fare_plan: level_pct (the level a ladder row sets) and ladder_move (up, down or hold). Existing rows
--     keep null: they are fare tests, not the ladder's;
--   - public.fare_ladder(p_airline_id, p_as_of) and its builder private.fig_fare_ladder(): for each route and cabin, the
--     week's departures, sold out and average fare, its level, fare index and this Saturday's move with its reason, and
--     the fewest Ticket price adjustments that put the airline's routes at their new levels;
--   - replaced, same arguments: private.fig_fare_plan() (so fare_plan_status()): a row with level_pct is the ladder's,
--     read in its own cabin and seen in the game when the captured fare moves by its expected ratio, within 1%. Every
--     other row is worked out exactly as before.
-- Rivals pausing a route (manual §5) needs the scans compared (step 4): until then the figure pauses nothing, and says
-- so in its notes.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261021120000_fare_ladder', true);

-- ============================================================ 1. the ladder's numbers, as settings (manual §1)
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, s.key, s.value, s.unit, s.description, date '2026-10-21', s.reason
  from public.worlds w
 cross join (values
   ('fare_ladder_step_pts', '5'::jsonb, 'points',
    'The fare ladder''s step: a route and cabin that moves goes up or down this many points of the game''s default price (manual §5)',
    'Gitesh, 21 Oct: option A of the fare-ladder brief, a weekly ladder of 5% steps'),
   ('fare_ladder_up_share', '100'::jsonb, 'percent',
    'The fare ladder goes up a step when at least this share of a cabin''s departures in the 7 days sold out (its load at 100%)',
    'Gitesh, 21 Oct: up only when every captured flight sold out'),
   ('fare_ladder_down_share', '90'::jsonb, 'percent',
    'The fare ladder goes down a step when under this share of a cabin''s departures in the 7 days sold out; from it to the up share, it holds',
    'Gitesh, 21 Oct: hold at 90–99%, down under 90%'),
   ('fare_ladder_min_departures', '5'::jsonb, 'departures',
    'A route and cabin needs at least this many captured departures in the 7 days to move on the fare ladder; with fewer it holds',
    'Gitesh, 21 Oct: a week of a few flights says too little'),
   ('fare_ladder_hold_weeks', '2'::jsonb, 'weeks',
    'After a step down recorded on the fare plan, a route and cabin holds this many weeks before it may climb again',
    'Gitesh, 21 Oct: a route that stops selling out goes back one step and holds there'),
   ('fare_ladder_cap_pts', '20'::jsonb, 'points',
    'For now the fare ladder goes at most this many points above launch (120%, Ryanair 105%); lifted only once loads and image show it''s safe',
    'Gitesh, 21 Oct: the game''s passengers are price-sensitive and higher fares may hurt the airline''s image')
 ) as s(key, value, unit, description, reason)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2. the fare plan records levels
alter table public.fare_plan add column level_pct numeric(5,1);
alter table public.fare_plan add column ladder_move text;
alter table public.fare_plan add constraint fare_plan_ladder_move_check check (ladder_move in ('up', 'down', 'hold'));

comment on table public.fare_plan is 'Fare changes to make in the game, and whether each is still planned or was dropped: fare tests (Performance''s + fare plan), and since 21 Oct the fare ladder''s moves (a row with level_pct, written by Performance''s Put on the fare plan; manual §5). Replaces the planner''s farePlan.';
comment on column public.fare_plan.level_pct is 'The fare ladder''s level the row sets, as a % of the game''s default price (manual §5): the latest one for a route and cabin is its level. Null on a fare test that isn''t the ladder''s';
comment on column public.fare_plan.ladder_move is 'The fare ladder''s move: up, down or hold (a hold is recorded when it follows a step down, so the hold has a record). Null on a fare test that isn''t the ladder''s';

-- ============================================================ 3. the fare plan's status reads a ladder row in its own cabin
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
    -- before and after are averages over every flight, not over the days)
    rd as materialized (
      select r.id as route_id, l.game_date as day, avg(l.fare) as fare, sum(l.eco) as eco_sum, count(l.eco) as eco_n
        from r join l on l.fare is not null
         and ((l.origin = r.hub_code and l.dest = r.dest_code) or (l.origin = r.dest_code and l.dest = r.hub_code))
       group by r.id, l.game_date),
    -- the same in business, for the fare ladder's business rows (flights with business seats)
    rb as materialized (
      select r.id as route_id, l.game_date as day, avg(l.bfare) as fare, sum(l.bus) as eco_sum, count(l.bus) as eco_n
        from r join l on l.bfare is not null
         and ((l.origin = r.hub_code and l.dest = r.dest_code) or (l.origin = r.dest_code and l.dest = r.hub_code))
       group by r.id, l.game_date),
    p as (select fp.*, ro.hub_code, ro.dest_code,
                 fp.fare_from * (1 + fp.change_pct / 100) as target,
                 case when fp.level_pct is not null and fp.cabin_class = 'business'
                      then (select rb.fare from rb where rb.route_id = fp.route_id order by rb.day desc limit 1)
                      else (select rd.fare from rd where rd.route_id = fp.route_id order by rd.day desc limit 1) end as cur,
                 case
                   -- a fare test: seen once at least half the change shows in the day's average fare, on or after the day it
                   -- was proposed
                   when fp.level_pct is null
                     then (select min(rd.day) from rd where rd.route_id = fp.route_id and rd.day >= fp.proposed_on
                              and rd.fare >= fp.fare_from * (1 + fp.change_pct / 200))
                   -- the fare ladder's: seen once the day's average fare in its cabin is the fare then times the expected
                   -- ratio, within 1%, on or after the day it was proposed
                   when fp.cabin_class = 'business'
                     then (select min(rb.day) from rb where rb.route_id = fp.route_id and rb.day >= fp.proposed_on and fp.fare_from > 0
                              and abs(rb.fare / fp.fare_from - (1 + coalesce(fp.change_pct, 0) / 100)) <= 0.01)
                   else (select min(rd.day) from rd where rd.route_id = fp.route_id and rd.day >= fp.proposed_on and fp.fare_from > 0
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
                                        when p.biz then (select sum(rb.eco_sum) / nullif(sum(rb.eco_n), 0) from rb where rb.route_id = p.route_id and rb.day < p.seen)
                                        else (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.day < p.seen) end,
                 'economy_after', case when p.seen is null then null
                                       when p.biz then (select sum(rb.eco_sum) / nullif(sum(rb.eco_n), 0) from rb where rb.route_id = p.route_id and rb.day >= p.seen)
                                       else (select sum(rd.eco_sum) / nullif(sum(rd.eco_n), 0) from rd where rd.route_id = p.route_id and rd.day >= p.seen) end,
                 'level_pct', trim_scale(p.level_pct), 'ladder_move', p.ladder_move)
                 order by p.id) from p), '[]'::jsonb),
      'fares', coalesce((select jsonb_agg(jsonb_build_object('route_id', x.route_id, 'hub', r.hub_code, 'dest', r.dest_code, 'day', x.day, 'fare', x.fare)
                                          order by x.route_id)
                           from (select distinct on (rd.route_id) rd.route_id, rd.day, rd.fare from rd order by rd.route_id, rd.day desc) x
                           join r on r.id = x.route_id), '[]'::jsonb)));
end
$function$;

comment on function public.fare_plan_status(bigint, timestamptz) is 'Performance''s fare plan for one airline (#18 build pull request 10, Review''s until 20 Oct; the old planner''s routeFares and farePlanStatus), from the fares and loads its captures give for each of its routes, both directions (the last 9 days'' loads, one per date and flight number): plan, each fare change not dropped (fare_plan, by id) with its row''s fields and updated_at, the fare now (the latest captured day''s average), the target (fare then × (1 + change)), applied and seen_on and the average load before and after that day. A fare test (no level_pct) is read in economy and seen on the first captured day on or after it was proposed whose average fare shows at least half the change; a fare ladder''s row (level_pct and ladder_move, since 21 Oct, manual §5) is read in its own cabin (business on flights with business seats) and seen when the day''s average fare is the fare then times (1 + change), within 1%. And fares: each route''s latest captured day with its average economy fare (what "+ fare plan" starts from). Staff only; runs as owner and checks the caller itself.';

-- ============================================================ 4. the fare ladder
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
  v_new_days numeric;
  v_scan bigint; v_scan_at timestamptz;
  v_rows jsonb; v_actions jsonb := '[]'::jsonb; v_n int := 0;
  v_cabin text; v_after jsonb; v_set jsonb; v_b record; v_r record; v_mode numeric; v_alone int; v_with int; v_lv numeric;
begin
  v_step := private.fig_num(w, p_airline_id, 'fare_ladder_step_pts');
  v_up := private.fig_num(w, p_airline_id, 'fare_ladder_up_share');
  v_down := private.fig_num(w, p_airline_id, 'fare_ladder_down_share');
  v_min := private.fig_num(w, p_airline_id, 'fare_ladder_min_departures');
  v_hold := private.fig_num(w, p_airline_id, 'fare_ladder_hold_weeks');
  v_cap := private.fig_num(w, p_airline_id, 'fare_ladder_cap_pts');
  v_launch := private.fig_num(w, p_airline_id, 'fare_launch_pct');
  v_new_days := private.fig_num(w, p_airline_id, 'growth_new_route_days');
  select (r.value #>> '{}')::numeric into v_floor from public.world_rules r where r.world_id = w and r.key = 'fare_floor_pct';
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
                   f.eco_pct, f.eco_fare, f.bus_pct, f.bus_seats, f.bus_fare
              from public.game_flights f
             where f.airline_id = p_airline_id and f.flight_no is not null and f.loads_captured_at <= p_as_of and f.game_date <= v_today
             order by f.game_date, f.flight_no, f.id desc) x
      left join ro r1 on r1.hub_code = x.o and r1.dest_code = x.d
      left join ro r2 on r2.hub_code = x.d and r2.dest_code = x.o
     where coalesce(r1.id, r2.id) is not null),
  -- by cabin: economy on every row with its load, business on flights with business seats
  lc as (select lf.route_id, 'economy'::text as cabin, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare from lf where lf.eco_pct is not null
         union all
         select lf.route_id, 'business', lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known)
  st as (select lc.route_id, lc.cabin, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare
           from lc
          where coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') >= p_as_of - interval '7 days'
            and coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') < p_as_of
          group by lc.route_id, lc.cabin),
  -- each captured day's average fare by cabin; the latest, and the first (economy's from the daily history too, kept for
  -- good once the flights are archived)
  fd as (select lc.route_id, lc.cabin, lc.game_date as day, avg(lc.fare) as fare from lc where lc.fare is not null group by 1, 2, 3),
  latest as (select distinct on (fd.route_id, fd.cabin) fd.* from fd order by fd.route_id, fd.cabin, fd.day desc),
  firsts as (select distinct on (y.route_id, y.cabin) y.*
               from (select fd.route_id, fd.cabin, fd.day, fd.fare from fd
                     union all
                     select coalesce(r1.id, r2.id), 'economy', d.day, avg(d.eco_fare_avg)
                       from public.route_days d
                       left join ro r1 on r1.hub_code = d.origin_code and r1.dest_code = d.dest_code
                       left join ro r2 on r2.hub_code = d.dest_code and r2.dest_code = d.origin_code
                      where d.airline_id = p_airline_id and d.eco_fare_avg is not null and d.day <= v_today and coalesce(r1.id, r2.id) is not null
                      group by 1, 3) y
              order by y.route_id, y.cabin, y.day, y.fare),
  -- the levels the fare plan recorded (manual §5): before this Saturday, the latest is the level; since it, this week's move
  rec as (select fp.id, fp.route_id, coalesce(fp.cabin_class, 'economy') as cabin, fp.level_pct, fp.ladder_move, fp.proposed_on, fp.reason
            from public.fare_plan fp
           where fp.airline_id = p_airline_id and fp.world_id = w and fp.level_pct is not null and fp.status <> 'dropped'
             and fp.proposed_on <= v_today),
  prev as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on < v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  wk as (select distinct on (r.route_id, r.cabin) r.* from rec r where r.proposed_on >= v_week order by r.route_id, r.cabin, r.proposed_on desc, r.id desc),
  dn as (select r.route_id, r.cabin, max(r.proposed_on) as down_on from rec r where r.ladder_move = 'down' and r.proposed_on < v_week group by 1, 2),
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
                lt.fare as latest_fare, lt.day as latest_on, fi.fare as first_fare, fi.day as first_on,
                coalesce(pv.level_pct, v_launch) as level, pv.id is not null as recorded,
                wk.id as plan_id, wk.level_pct as plan_level, wk.ladder_move as plan_move, wk.reason as plan_reason,
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, ag.first_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested
           from rc join ro on ro.id = rc.route_id
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin
           left join firsts fi on fi.route_id = rc.route_id and fi.cabin = rc.cabin
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin
           left join age ag on ag.route_id = rc.route_id),
  mv as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                v_launch + v_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(v_launch, case when lv.contested then v_floor end) as floor_pct,
                coalesce(lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held
           from lv),
  dc as (select mv.*,
                case when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     when mv.held then 'held'
                     when mv.share >= v_up then case when mv.level >= mv.cap_pct then 'capped' else 'up' end
                     when mv.share >= v_down then 'hold'
                     when mv.level <= mv.floor_pct then 'floor'
                     else 'down' end as k
           from mv),
  fin as (select dc.*,
                 case dc.k when 'planned' then dc.plan_move when 'up' then 'up' when 'down' then 'down' else 'hold' end as move,
                 case dc.k when 'planned' then dc.plan_level
                           when 'up' then least(dc.level + v_step, dc.cap_pct)
                           when 'down' then greatest(dc.level - v_step, dc.floor_pct)
                           else dc.level end as new_level,
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
                   when 'up' then format('sold out %s of %s', fin.sold, fin.n)
                                  || case when fin.level + v_step >= fin.cap_pct then format(', up to the %s%% cap', trim_scale(fin.cap_pct)) else '' end
                   when 'capped' then format('sold out %s of %s, capped at %s%%', fin.sold, fin.n, trim_scale(fin.cap_pct))
                   when 'hold' then format('sold out %s of %s', fin.sold, fin.n)
                   when 'down' then format('sold out %s of %s', fin.sold, fin.n)
                                    || case when fin.level - v_step <= fin.floor_pct then ', down to ' || fin.floor_words else '' end
                   else format('sold out %s of %s, at %s', fin.sold, fin.n, fin.floor_words) end as reason,
                 case when fin.latest_fare is not null and fin.first_fare > 0 then round(fin.latest_fare / fin.first_fare * v_launch, 1) end as fare_index
            from fin)
  select coalesce(jsonb_agg(jsonb_build_object(
           'route_id', o.route_id, 'hub', o.hub, 'dest', o.dest, 'cabin', o.cabin,
           'departures', o.n, 'sold_out', o.sold, 'sold_out_share', round(o.share, 1), 'average_fare', round(o.fare_week, 2),
           'first_fare', round(o.first_fare, 2), 'first_on', o.first_on, 'latest_fare', round(o.latest_fare, 2), 'latest_on', o.latest_on,
           'fare_index', o.fare_index,
           -- the index against the level the game should show: this week's, once the captures see it
           'index_matches', case when o.fare_index is null then null
                                 else abs(o.fare_index - case when o.plan_id is not null and o.applied then o.new_level else o.level end) <= 1 end,
           'level', trim_scale(o.level), 'recorded', o.recorded, 'steps', trim_scale(round((o.level - v_launch) / v_step, 1)),
           'move', o.move, 'new_level', trim_scale(o.new_level), 'new_steps', trim_scale(round((o.new_level - v_launch) / v_step, 1)),
           'change_pct', case when o.level > 0 then trim_scale(round((o.new_level / o.level - 1) * 100, 1)) end,
           'reason', o.reason, 'contested', o.contested, 'floor', trim_scale(o.floor_pct), 'cap', trim_scale(o.cap_pct), 'new_route', o.young,
           'planned', o.plan_id is not null, 'plan_id', o.plan_id, 'applied', o.applied, 'seen_on', o.seen_on,
           -- what Put on the fare plan writes: every level that changes, and a hold that follows a step down
           'to_plan', o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k = 'held'))
           order by o.hub, o.dest, o.cabin desc), '[]'::jsonb)
    into v_rows from od o;

  -- the game's Ticket price adjustments, cabin by cabin: each action sets a level with the baseline default price, so the
  -- order matters. For each base, in the bases' order: when setting the whole base to its most common new level (From
  -- base, To anywhere; From anywhere, To base) and then the single routes that differ takes fewer actions than single
  -- routes alone, the two base actions go first. Then every route still not at its new level, two actions each (From A to
  -- B, From B to A).
  foreach v_cabin in array array['economy', 'business'] loop
    v_after := '{}'::jsonb;
    for v_b in select y.airport_code from (
               select distinct on (x2.airport_code) x2.airport_code, x2.position, x2.id
                 from public.airline_bases x2 where x2.airline_id = p_airline_id and x2.world_id = w
                order by x2.airport_code, x2.position nulls last, x2.id) y
              order by y.position nulls last, y.id loop
      select count(*) filter (where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric)::int * 2 into v_alone
        from jsonb_array_elements(v_rows) e
       where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest');
      select (e ->> 'new_level')::numeric into v_mode
        from jsonb_array_elements(v_rows) e
       where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest')
       group by 1 order by count(*) desc, 1 limit 1;
      if v_mode is null then continue; end if;
      select 2 + 2 * (count(*) filter (where (e ->> 'new_level')::numeric <> v_mode))::int into v_with
        from jsonb_array_elements(v_rows) e
       where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest');
      if v_with < v_alone then
        foreach v_set in array array[jsonb_build_array(v_b.airport_code, 'anywhere'), jsonb_build_array('anywhere', v_b.airport_code)] loop
          v_n := v_n + 1;
          v_actions := v_actions || jsonb_build_object(
            'n', v_n, 'kind', 'base', 'base', v_b.airport_code, 'cabin', v_cabin, 'from', v_set ->> 0, 'to', v_set ->> 1,
            'level', trim_scale(v_mode), 'sign', case when v_mode >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_mode - 100)),
            'baseline', 'default price',
            'text', format('From %s to %s: %s%s%% of the default price, %s', v_set ->> 0, v_set ->> 1,
                           case when v_mode >= 100 then '+' else '−' end, trim_scale(abs(v_mode - 100)), v_cabin));
        end loop;
        select v_after || coalesce(jsonb_object_agg(e ->> 'route_id', v_mode), '{}'::jsonb) into v_after
          from jsonb_array_elements(v_rows) e
         where e ->> 'cabin' = v_cabin and v_b.airport_code in (e ->> 'hub', e ->> 'dest');
      end if;
    end loop;
    for v_r in select e ->> 'route_id' as route_id, e ->> 'hub' as hub, e ->> 'dest' as dest, (e ->> 'level')::numeric as level,
                    (e ->> 'new_level')::numeric as new_level
               from jsonb_array_elements(v_rows) e where e ->> 'cabin' = v_cabin order by e ->> 'hub', e ->> 'dest' loop
      v_lv := coalesce((v_after ->> v_r.route_id)::numeric, v_r.level);
      if v_lv = v_r.new_level then continue; end if;
      foreach v_set in array array[jsonb_build_array(v_r.hub, v_r.dest), jsonb_build_array(v_r.dest, v_r.hub)] loop
        v_n := v_n + 1;
        v_actions := v_actions || jsonb_build_object(
          'n', v_n, 'kind', 'route', 'route', v_r.hub || '–' || v_r.dest, 'cabin', v_cabin, 'from', v_set ->> 0, 'to', v_set ->> 1,
          'level', trim_scale(v_r.new_level), 'sign', case when v_r.new_level >= 100 then '+' else '-' end, 'pct', trim_scale(abs(v_r.new_level - 100)),
          'baseline', 'default price',
          'text', format('From %s to %s: %s%s%% of the default price, %s', v_set ->> 0, v_set ->> 1,
                         case when v_r.new_level >= 100 then '+' else '−' end, trim_scale(abs(v_r.new_level - 100)), v_cabin));
      end loop;
    end loop;
  end loop;

  return jsonb_build_object(
    'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of), 'week_of', v_week,
    'from', private.fig_ts(p_as_of - interval '7 days'), 'to', private.fig_ts(p_as_of),
    'settings', jsonb_build_object('step_pts', v_step, 'up_share', v_up, 'down_share', v_down, 'min_departures', v_min,
                                   'hold_weeks', v_hold, 'cap_pts', v_cap, 'launch_pct', v_launch, 'cap_pct', v_launch + v_cap,
                                   'floor_pct', v_floor, 'new_route_days', v_new_days),
    'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
    'moves', jsonb_build_object(
      'up', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'up'),
      'hold', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'hold'),
      'down', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'down')),
    'to_plan', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'to_plan')::boolean),
    'planned', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'planned')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'A rival starting on a pair pauses that route for a week (manual §5): that needs this week''s scan set against last week''s (step 4), so for now the figure pauses nothing and the Saturday review checks the scan by hand.',
      'The fare index is the latest captured fare against the first, times the launch level: a level more than 1 point from it is flagged, not changed.'));
end
$function$;

CREATE OR REPLACE FUNCTION public.fare_ladder(p_airline_id bigint, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_fare_ladder(p_airline_id, coalesce(p_as_of, now()));
end
$function$;

revoke all on function private.fig_fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.fare_ladder(bigint, timestamptz) to authenticated;

comment on function private.fig_fare_ladder(bigint, timestamptz) is 'The captured figures (#19): builds fare_ladder()''s document with no check of its own. See fare_ladder().';
comment on function public.fare_ladder(bigint, timestamptz) is 'The fare ladder for one airline (manual §5, since 21 Oct; spec docs/specs/2026-10-21-fare-ladder.md): this Saturday''s move for each route and cabin and the game actions that make them. routes: each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin''s load at 100%), the sold-out share and the average fare over those 7 days (game_flights, matched to the route either way round); its level as a % of the game''s default price (the latest the fare plan recorded before this Saturday, else settings.fare_launch_pct), steps above launch and the fare index (the latest captured fare against the first, times the launch level; index_matches false flags a level more than 1 point from it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, and for fare_ladder_hold_weeks after a recorded step down; never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes. moves counts them. actions: the fewest Ticket price adjustments (baseline default price) that put every route of the airline at its new level, by cabin: a base''s two actions first where they save actions, then single routes, each in the game''s words. notes: what it doesn''t do yet (a rival''s pause, step 4). Staff only; runs as owner and checks the caller itself.';

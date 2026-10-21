-- New frequencies and the fare ladder (21 Oct 2026; manual §5; spec docs/specs/2026-10-21-frequencies-and-fares.md).
--
-- Why (Gitesh, 21 Oct): "only new routes until 31 Oct" may be dropped soon, and then routes gain frequencies. The extra
-- seats lower a route's loads for a week, so a route that gained a flight holds on the fare ladder for that week. Each
-- plan card shows the fare level of each route it flies. And Gitesh thinks the game prices a new flight number at the
-- default price, not at its route's level: a route whose captured fares don't match its level now gets a change that sets
-- it back, which settles the question from the captures and fixes it either way.
--
-- Adds one setting and replaces three functions with the same arguments; drops and renames nothing, so it can be
-- applied from the chat:
--   - fare_ladder_capacity_hold_days 7, in every world, described.
--   - private.fig_fare_ladder() (so fare_ladder()):
--       1. a route whose newest live rotation launched within fare_ladder_capacity_hold_days, while its first rotation is
--          older than that, holds: "a flight added on 2 Nov: judged at its new size from 9 Nov". Checked after planned,
--          new route, too few departures and the hold after a step down, before the sold-out share. Launch days are
--          private.fig_freqs()'s, as the route's age is. A frequency taken away isn't tracked (its rotation is deleted).
--       2. the fare index has a baseline: every route was at its launch level on 21 Oct 2026 (Gitesh; manual §5), so each
--          direction's baseline is its fare on the latest captured day on or before 21 Oct, and for a route launched
--          later its first captured fare, if captured in the route's first growth_new_route_days days. A day's fare is
--          its flights' lowest (game_flights), else the daily history's average (route_days, economy, kept for good once
--          the flights are archived). Each flight of the route's latest captured day is compared with its direction's
--          baseline: index = fare ÷ baseline × launch level. fare_index is their average; index_matches is false when
--          any flight is more than 1 point off the level the game should show. Replaces "the latest fare against the
--          first", which read Ryanair's four early cuts (BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC) at about 72 against 85.
--          first_fare and first_on give way to baseline_fare and baseline_on.
--       3. a route and cabin off its level (index_matches false) that isn't on the fare plan this week, isn't new, and
--          whose latest captured day is after its newest rotation launched gets a set-back change: fix true, with the
--          reason "captured fare at 100%, level 110%". Its game actions (route by route, both ways, both classes together
--          when both cabins go back to the same level; fix true and the reason) come first in actions, ahead of the
--          week's moves. move stays as it is. off_level counts the routes with one.
--   - private.capture_fare_actions_doc() (so capture_fare_actions()): also the set-back actions, which need no fare plan
--     row (plan_ids empty; the index matching again is the proof), each with fix and reason, so the fares userscript
--     sets them back on its next run.
--   - private.briefing_doc() (so export_for_report(), kind briefing): fare_ladder, each route and cabin's level from
--     fare_ladder() (the new level once this week's move is on the fare plan) and the launch level, for the plan card
--     check's fare line (the planning library's card.cardFares).
--   The grants stay as they were.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261021230000_frequencies_and_fares', true);

-- ============================================================ 1. the setting, in every world
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'fare_ladder_capacity_hold_days', '7'::jsonb, 'days',
       'A route that gained a flight holds on the fare ladder while its newest rotation is under this many days old (its first older than that), so it is judged at its new size, not on the drop the extra seats cause (manual §5). A frequency taken away isn''t tracked: its rotation is deleted',
       date '2026-10-21', 'Gitesh, 21 Oct: routes will gain frequencies once "only new routes" ends; a new flight lowers the week''s loads'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2. the fare ladder
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
                   f.eco_pct, f.eco_fare, f.bus_pct, f.bus_seats, f.bus_fare
              from public.game_flights f
             where f.airline_id = p_airline_id and f.flight_no is not null and f.loads_captured_at <= p_as_of and f.game_date <= v_today
             order by f.game_date, f.flight_no, f.id desc) x
      left join ro r1 on r1.hub_code = x.o and r1.dest_code = x.d
      left join ro r2 on r2.hub_code = x.d and r2.dest_code = x.o
     where coalesce(r1.id, r2.id) is not null),
  -- by cabin: economy on every row with its load, business on flights with business seats; each with its direction (o)
  lc as materialized (
    select lf.route_id, 'economy'::text as cabin, lf.o, lf.game_date, lf.dep_at, lf.eco_pct as pct, lf.eco_fare as fare from lf where lf.eco_pct is not null
    union all
    select lf.route_id, 'business', lf.o, lf.game_date, lf.dep_at, lf.bus_pct, lf.bus_fare from lf where lf.bus_pct is not null and coalesce(lf.bus_seats, 0) > 0),
  -- the 7 days before the moment, by scheduled departure (the departure date where it isn't known)
  st as (select lc.route_id, lc.cabin, count(*)::int as n, (count(*) filter (where lc.pct >= 100))::int as sold, avg(lc.fare) as fare
           from lc
          where coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') >= p_as_of - interval '7 days'
            and coalesce(lc.dep_at, lc.game_date::timestamp at time zone 'UTC') < p_as_of
          group by lc.route_id, lc.cabin),
  -- the fare index's baseline (manual §5, since 21 Oct). Each captured day's fare by cabin and direction: the flights'
  -- lowest (one the game priced otherwise, as a new flight at the default price on a Ryanair route, sits above it), else
  -- the daily history's average economy fare (route_days, kept for good once the flights are archived)
  dd as (select lc.route_id, lc.cabin, lc.o, lc.game_date as day, min(lc.fare) as fare from lc where lc.fare > 0 group by 1, 2, 3, 4),
  hd as (select coalesce(r1.id, r2.id) as route_id, 'economy'::text as cabin, d.origin_code as o, d.day, avg(d.eco_fare_avg) as fare
           from public.route_days d
           left join ro r1 on r1.hub_code = d.origin_code and r1.dest_code = d.dest_code
           left join ro r2 on r2.hub_code = d.dest_code and r2.dest_code = d.origin_code
          where d.airline_id = p_airline_id and d.eco_fare_avg > 0 and d.day <= v_today and coalesce(r1.id, r2.id) is not null
          group by 1, 3, 4),
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
                lt.fare as latest_fare, lt.day as latest_on, lt.ratios, bs.fare as baseline_fare, bs.day as baseline_on,
                coalesce(pv.level_pct, v_launch) as level, pv.id is not null as recorded,
                wk.id as plan_id, wk.level_pct as plan_level, wk.ladder_move as plan_move, wk.reason as plan_reason,
                coalesce(se.applied, false) as applied, se.seen_on, dn.down_on, ag.first_day, ad.last_day,
                exists (select 1 from contested c where c.a = least(ro.hub_code, ro.dest_code) and c.b = greatest(ro.hub_code, ro.dest_code)) as contested
           from rc join ro on ro.id = rc.route_id
           left join st on st.route_id = rc.route_id and st.cabin = rc.cabin
           left join latest lt on lt.route_id = rc.route_id and lt.cabin = rc.cabin
           left join bs on bs.route_id = rc.route_id and bs.cabin = rc.cabin
           left join prev pv on pv.route_id = rc.route_id and pv.cabin = rc.cabin
           left join wk on wk.route_id = rc.route_id and wk.cabin = rc.cabin
           left join seen se on se.id = wk.id
           left join dn on dn.route_id = rc.route_id and dn.cabin = rc.cabin
           left join age ag on ag.route_id = rc.route_id
           left join added ad on ad.route_id = rc.route_id),
  mv as (select lv.*,
                case when lv.n > 0 then lv.sold * 100.0 / lv.n end as share,
                v_launch + v_cap as cap_pct,
                -- never under launch, nor under the house floor where another player flies the pair
                greatest(v_launch, case when lv.contested then v_floor end) as floor_pct,
                coalesce(lv.first_day is not null and v_today - lv.first_day < v_new_days, false) as young,
                coalesce(lv.down_on is not null and v_week - lv.down_on < v_hold * 7, false) as held,
                -- a flight added in the last fare_ladder_capacity_hold_days, to a route older than that (manual §5, since 21 Oct)
                coalesce(lv.last_day is not null and v_today - lv.last_day < v_added_days
                         and lv.first_day is not null and v_today - lv.first_day >= v_added_days, false) as added
           from lv),
  dc as (select mv.*,
                case when mv.plan_id is not null then 'planned'
                     when mv.young then 'young'
                     when mv.n < v_min then 'few'
                     when mv.held then 'held'
                     when mv.added then 'added'
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
                   when 'added' then format('a flight added on %s: judged at its new size from %s', to_char(fin.last_day, 'FMDD Mon'),
                                            to_char(fin.last_day + v_added_days::int, 'FMDD Mon'))
                   when 'up' then format('sold out %s of %s', fin.sold, fin.n)
                                  || case when fin.level + v_step >= fin.cap_pct then format(', up to the %s%% cap', trim_scale(fin.cap_pct)) else '' end
                   when 'capped' then format('sold out %s of %s, capped at %s%%', fin.sold, fin.n, trim_scale(fin.cap_pct))
                   when 'hold' then format('sold out %s of %s', fin.sold, fin.n)
                   when 'down' then format('sold out %s of %s', fin.sold, fin.n)
                                    || case when fin.level - v_step <= fin.floor_pct then ', down to ' || fin.floor_words else '' end
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
           -- what Put on the fare plan writes: every level that changes, and a hold that follows a step down
           'to_plan', o.plan_id is null and ((o.move in ('up', 'down') and o.new_level <> o.level) or o.k = 'held'),
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
                                   'baseline_day', v_base_day),
    'scan', case when v_scan is null then null else jsonb_build_object('id', v_scan, 'taken_at', private.fig_ts(v_scan_at)) end,
    'moves', jsonb_build_object(
      'up', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'up'),
      'hold', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'hold'),
      'down', (select count(*) from jsonb_array_elements(v_rows) e where e ->> 'move' = 'down')),
    'to_plan', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'to_plan')::boolean),
    'planned', (select count(*) from jsonb_array_elements(v_rows) e where (e ->> 'planned')::boolean),
    'off_level', (select count(distinct e ->> 'route_id') from jsonb_array_elements(v_rows) e where (e ->> 'fix')::boolean),
    'routes', v_rows, 'actions', v_actions,
    'notes', jsonb_build_array(
      'A rival starting on a pair pauses that route for a week (manual §5): that needs this week''s scan set against last week''s (step 4), so for now the figure pauses nothing and the Saturday review checks the scan by hand.',
      'The fare index compares each flight of the latest captured day with its direction''s fare on 21 Oct 2026, when every route was at its launch level (or its first captured fare, for a route launched later), times the launch level. A route more than 1 point off its level gets a change that sets it back, first in the list, unless it''s on the fare plan this week, new, or not captured since its newest flight launched.'));
end
$function$;

-- ============================================================ 3. the fares userscript's list: the set-back changes too
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
    -- proof), or when every class it names is a route row (matched by its route, "HUB–DEST", and cabin) that is on the
    -- fare plan this week (planned) and not yet seen in the captures (applied false)
    with acts as (select t.x, t.i from jsonb_array_elements(d -> 'actions') with ordinality as t(x, i)),
         cls as (select acts.i, c.k, m.rt
                   from acts
                   cross join lateral jsonb_array_elements_text(acts.x -> 'classes') with ordinality as c(cabin, k)
                   left join lateral (select e as rt from jsonb_array_elements(d -> 'routes') e
                                       where (e ->> 'hub') || '–' || (e ->> 'dest') = acts.x ->> 'route' and e ->> 'cabin' = c.cabin
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
$function$;

-- ============================================================ 4. the briefing: each route's fare level, for the plan cards
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
  fl as (select private.fig_fare_ladder(al.id, p_as_of) as d from al)
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
    -- each route and cabin's fare level (fare_ladder()'s routes: the level, and this week's new level once it's on the
    -- fare plan) and the launch level for a route not flown yet: the plan card check's fare line (manual §5, since 21 Oct)
    'fare_ladder', (select jsonb_build_object(
        'week_of', fl.d -> 'week_of', 'settings', jsonb_build_object('launch_pct', fl.d #> '{settings,launch_pct}'),
        'routes', coalesce((select jsonb_agg(jsonb_build_object('route_id', e -> 'route_id', 'hub', e -> 'hub', 'dest', e -> 'dest', 'cabin', e -> 'cabin',
                                                               'level', e -> 'level', 'new_level', e -> 'new_level', 'planned', e -> 'planned') order by x.o)
                              from jsonb_array_elements(fl.d -> 'routes') with ordinality x(e, o)), '[]'::jsonb))
      from fl),
    'route_loads', (select jsonb_build_object(
        'from', rl.d -> 'from', 'to', rl.d -> 'to',
        'routes', coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(rl.d -> 'routes') with ordinality x(v, o)
                             where (x.v ->> 'airline_id')::bigint = p_airline_id), '[]'::jsonb),
        'flights', coalesce((select jsonb_agg(x.v order by x.o) from jsonb_array_elements(rl.d -> 'flights') with ordinality x(v, o)
                              where (x.v ->> 'airline_id')::bigint = p_airline_id), '[]'::jsonb))
      from rl))
  from al
$function$;

-- ============================================================ 5. grants as they were, and the descriptions
revoke all on function private.fig_fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.capture_fare_actions_doc(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.briefing_doc(bigint, timestamptz) from public, anon, authenticated, service_role;

comment on function public.fare_ladder(bigint, timestamptz) is 'The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md, docs/specs/2026-10-21-fare-actions-by-route.md and docs/specs/2026-10-21-frequencies-and-fares.md): this Saturday''s move for each route and cabin, the changes that set a route back to its level, and the game actions that make them. routes: each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin''s load at 100%), the sold-out share and the average fare over those 7 days (game_flights, matched to the route either way round); its level as a % of the game''s default price (the latest the fare plan recorded before this Saturday, else settings.fare_launch_pct) and steps above launch; the fare index: each flight of the latest captured day (latest_on, its average latest_fare) against its direction''s baseline, times the launch level, the baseline being the direction''s fare on the latest captured day on or before 21 Oct 2026, when every route was at its launch level (Gitesh), or for a route launched later its first captured fare if captured in its first growth_new_route_days days (a day''s fare: its flights'' lowest, else route_days'' average economy fare; baseline_fare and baseline_on, the directions'' average and latest day); fare_index the flights'' average, index_matches false when any flight is more than 1 point off the level the game should show (this week''s new level once the captures see it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, for fare_ladder_hold_weeks after a recorded step down, and while the newest rotation is under fare_ladder_capacity_hold_days old on a route older than that (a flight added: "judged at its new size from ..."; a frequency taken away isn''t tracked, its rotation is deleted); never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes; fix, a change that sets it back to its level (index_matches false, not on the fare plan this week, not a new route, and captured since its newest rotation launched), with fix_reason ("captured fare at 100%, level 110%"). moves counts the moves, off_level the routes set back. actions: the Ticket price adjustments (baseline default price), route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): first the set-back changes (fix true, with the reason), then the week''s moves, each in the routes'' order (hub, dest), one action each way (From hub to dest, then From dest to hub) with classes ["economy","business"] when both cabins go to the same level, otherwise one each way for each cabin, economy first; a route whose levels don''t change gets no move. Each action has n, route, classes, from, to, level, sign, pct, baseline, fix, reason (a set-back''s) and text, the text in the game''s words naming the classes. settings: the numbers used, with capacity_hold_days and baseline_day. notes: what it doesn''t do yet (a rival''s pause, step 4) and how the index reads. Staff only; runs as owner and checks the caller itself.';
comment on function private.fig_fare_ladder(bigint, timestamptz) is 'The captured figures (#19): builds fare_ladder()''s document with no check of its own. See fare_ladder().';
comment on function public.capture_fare_actions(text) is 'For the fares userscript (capture/fares_apply.user.js; manual §5, since 21 Oct; specs docs/specs/2026-10-21-fares-userscript.md and docs/specs/2026-10-21-frequencies-and-fares.md §3), with the capture key: the game''s Ticket price adjustments still to make. For each active airline of our groups in the key''s world, in display order (as capture_airlines()), its fare_ladder() actions that set a route back to its level (fix true: they need no fare plan row, and the index matching again is the proof), and those whose route is on the fare plan this week and not yet seen in the captures (every class the action names is a route row with planned true and applied false), in fare_ladder()''s order (the set-back changes first). airlines: each airline''s game_id, name (the website''s, else the planner''s), game_name, code, count of actions and fixes (how many of them set a route back); actions: each with game_id and airline (its name), n (the action''s number in fare_ladder()), route (HUB–DEST), from and to (IATA), level (% of the default price), sign (+ or -) and pct (the game''s percent, a whole number), classes (economy and/or business), plan_ids (the fare plan rows, one per class in the same order; none for a set-back change), fix and reason (a set-back''s, "captured fare at 100%, level 110%") and text (the action in words); week_of (this Saturday) and as_of. A wrong or missing key gets {"ok": false, "error": "bad key"} and nothing else. Runs as owner with an empty search path and its own statement limit of 30 seconds (it works out every airline''s fare ladder in one call, signed out).';
comment on function private.capture_fare_actions_doc(bigint, timestamptz) is 'The fares userscript''s list (specs docs/specs/2026-10-21-fares-userscript.md and docs/specs/2026-10-21-frequencies-and-fares.md §3): builds capture_fare_actions()''s document for one world at a moment, with no check of its own. See capture_fare_actions().';
comment on function private.briefing_doc(bigint, timestamptz) is 'The airline briefing (#24): one airline''s document for export_for_report(''briefing''), read only, with no check of its own: the airline (id, world, code, names, game ID); deliveries, its aircraft not yet filed (status on_order or delivered) with type, cabin as ordered and now, bases, order date and note, delivery time and whether it has arrived by p_as_of, and each one''s plan cards (with the card''s cabin, config_id, since 21 Oct) with their legs in order (UTC weekdays and minute, block, service code); todos, the open to-dos (not done) of the airline and of the group (no airline), with their steps; fare_plan, fare_plan_status()''s document (private.fig_fare_plan()); fare_ladder, each route and cabin''s fare level from fare_ladder() (route_id, hub, dest, cabin, level, new_level and planned: the new level is the one to show once this week''s move is on the fare plan) with week_of and settings.launch_pct (the level of a route not flown yet), for the plan card check''s fare line (since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §2); route_loads, route_loads()''s routes and flights for this airline only (private.fig_route_loads()). Deliveries, plan cards and to-dos are the tables as they are now; the fare plan, the fare levels and the loads are as of p_as_of.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report, gander monthly, the airline briefing and the planning library: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19); and one airline''s briefing rows (kind briefing, p_arg {"airline": its id, code or name, "as_of", "world"}, the airline required: its deliveries with their plan cards and legs, open to-dos of the airline and the group, fare_plan_status(), each route''s fare level from fare_ladder() (since 21 Oct) and route_loads() for it, private.briefing_doc(), #24; read only). Kind planner (the old planner''s documents) is refused since the clean-up (build pull request 14). Needs the ingest secret.';

-- The fare ladder's game changes, route by route (21 Oct 2026; manual §5 as updated that morning; spec
-- docs/specs/2026-10-21-fare-actions-by-route.md).
--
-- Why (Gitesh, 21 Oct): the fare ladder's changes are made route by route only, never a whole base, so a route under 7
-- days old is never touched: loads are high because the world is young. In the game's Ticket price adjustment each
-- direction is changed on its own (From A to B, and From B to A), and Economy and Business can be ticked together in one
-- change. A fares userscript will make them later (its own spec), so the list is exact and in a form a script can read.
--
-- Replaces one function with the same arguments, and re-states two descriptions; adds, drops and renames nothing, so it
-- can be applied from the chat:
--   - private.fig_fare_ladder() (so fare_ladder()): actions are route by route. For each route whose level changes in
--     either cabin, in the routes' order (hub, dest), one action each way (From hub to dest, From dest to hub), naming
--     the classes it changes: both ("economy", "business") when the two cabins move to the same new level, otherwise one
--     action each way for each cabin that moves, economy first. A route whose levels don't change (held, new, capped,
--     too few departures, at its floor) gets none. No base actions: kind, base and cabin go from each action, classes
--     comes in; n, route, from, to, level, sign, pct, baseline and text stay, the text naming the classes ("economy and
--     business"). The routes, the moves, the levels and the settings are worked out exactly as before.
--   - the descriptions of private.fig_fare_ladder() and public.fare_ladder(), the latter saying how actions are made now.
--   - the grants as they were: the builder internal, fare_ladder() for signed-in staff only (it checks the caller itself).

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261021190000_fare_actions_by_route', true);

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

  -- the game's Ticket price adjustments, route by route only (manual §5, since 21 Oct: never a whole base, so a route
  -- under 7 days old is never touched). Each sets the level with the baseline default price, and each direction is a
  -- change of its own (From A to B, From B to A). For each route whose level changes in either cabin, in the routes'
  -- order (hub, dest): when both cabins move to the same new level, one action each way with both classes ticked;
  -- otherwise one each way for each cabin that changes, economy first. A route whose levels don't change gets none.
  for v_r in select e ->> 'hub' as hub, e ->> 'dest' as dest,
                    jsonb_agg(jsonb_build_object('cabin', e ->> 'cabin', 'level', (e ->> 'new_level')::numeric)
                              order by e ->> 'cabin' = 'business') as moves
               from jsonb_array_elements(v_rows) e
              where (e ->> 'new_level')::numeric <> (e ->> 'level')::numeric
              group by e ->> 'route_id', e ->> 'hub', e ->> 'dest'
              order by e ->> 'hub', e ->> 'dest' loop
    if jsonb_array_length(v_r.moves) = 2 and (v_r.moves #>> '{0,level}')::numeric = (v_r.moves #>> '{1,level}')::numeric then
      v_sets := jsonb_build_array(jsonb_build_object('classes', jsonb_build_array('economy', 'business'), 'level', v_r.moves #> '{0,level}'));
    else
      select jsonb_agg(jsonb_build_object('classes', jsonb_build_array(m ->> 'cabin'), 'level', m -> 'level') order by i) into v_sets
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
          'baseline', 'default price',
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

revoke all on function private.fig_fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.fare_ladder(bigint, timestamptz) to authenticated;

comment on function private.fig_fare_ladder(bigint, timestamptz) is 'The captured figures (#19): builds fare_ladder()''s document with no check of its own. See fare_ladder().';
comment on function public.fare_ladder(bigint, timestamptz) is 'The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md and docs/specs/2026-10-21-fare-actions-by-route.md): this Saturday''s move for each route and cabin and the game actions that make them. routes: each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin''s load at 100%), the sold-out share and the average fare over those 7 days (game_flights, matched to the route either way round); its level as a % of the game''s default price (the latest the fare plan recorded before this Saturday, else settings.fare_launch_pct), steps above launch and the fare index (the latest captured fare against the first, times the launch level; index_matches false flags a level more than 1 point from it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, and for fare_ladder_hold_weeks after a recorded step down; never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes. moves counts them. actions: the Ticket price adjustments (baseline default price) that put the airline''s routes at their new levels, route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): for each route whose level changes in either cabin, in the routes'' order (hub, dest), one action each way (From hub to dest, then From dest to hub) with classes ["economy","business"] when both cabins move to the same new level, otherwise one each way for each cabin that moves, economy first; a route whose levels don''t change gets none. Each action has n, route, classes, from, to, level, sign, pct, baseline and text, the text in the game''s words naming the classes. notes: what it doesn''t do yet (a rival''s pause, step 4). Staff only; runs as owner and checks the caller itself.';

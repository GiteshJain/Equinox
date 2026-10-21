-- Competition analysis (21 Oct 2026; manual §3 and §5; spec docs/specs/2026-10-21-competition-analysis.md, brief
-- docs/briefs/2026-10-21-competition-analysis.md).
--
-- Why (Gitesh, 20–21 Oct): route first, then the airline (manual §3): each evening's order proposal picks the route we
-- most want to fly and needs a ranked list; market share first: we need to see our share and the rivals' moves. The world
-- scan runs with the evening capture since 21 Oct, so the scans can be set against each other.
--
-- Adds one setting and four functions, and replaces two with the same arguments; drops and renames nothing, so it can be
-- applied from the chat:
--   - competition_threat_min_weekly 7, in every world, described.
--   - private.scan_pair_flights(p_scan_ids, p_pairs): each airline's departures a week by direction in the scans asked
--     for, on the city pairs asked for (each flight's days, as gscan.py counts n_weekly).
--   - private.competition_threats(p_airline_id, p_as_of): the threats (spec 1b), one home for competition() and the fare
--     ladder's rival pause: on each city pair the airline flies, a rival who started (none in the scan before) or added at
--     least competition_threat_min_weekly departures a week, in a finished scan of the 7 days before the moment against
--     the finished scan before it; each rival and pair once, from the scan that first showed it, listed until 7 days on.
--   - public.competition(p_airline_id, p_as_of, p_limit) and its builder private.fig_competition(): the scans used
--     (latest, week before, previous), market share by the airline's markets with the group line, the threats, the
--     openings ranked (stars, rivals' departures a week, the shorter distance, the pair's code; those hubs first doesn't
--     allow after, marked), each with the default line's variant, and the rival profiles. Staff only, read with GET.
--   - replaced, same arguments: private.fig_fare_ladder() (so fare_ladder() and capture_fare_actions()): a route and cabin
--     whose pair has a threat holds, "rival Air China started here on 22 Oct: paused until 29 Oct", checked after planned,
--     new, few, held and added, before the sold-out share; the note that said it waited for step 4 is gone.
--   - replaced, same arguments: private.briefing_doc() (so export_for_report(), kind briefing): competition, the scans,
--     the group line, hubs first, the threats and the top 20 openings, for the airline briefing (brief.py).
-- New functions get no grants but competition() for staff (signed in), as the other figures.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261021235000_competition', true);

-- ============================================================ 1. the setting, in every world
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, 'competition_threat_min_weekly', '7'::jsonb, 'departures a week',
       'A rival who adds at least this many departures a week on one of an airline''s city pairs since the previous world scan is a threat, as is one who starts there (competition(), manual §3); a threat is listed for 7 days from the scan that first showed it, and pauses that route on the fare ladder until then (manual §5)',
       date '2026-10-21', 'Gitesh, 21 Oct: competition analysis (spec docs/specs/2026-10-21-competition-analysis.md §1b): a daily flight more is a move worth seeing'
  from public.worlds w
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 2–3. the new internal functions
-- ============================================================ 2. the scans' flights on a set of city pairs
CREATE OR REPLACE FUNCTION private.scan_pair_flights(p_scan_ids bigint[], p_pairs text[])
 RETURNS TABLE(scan_id bigint, airline_id bigint, origin text, dest text, weekly integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- each airline's departures a week from origin to dest in each scan, on the city pairs asked for (either direction,
  -- 'AAA-BBB' with the codes in order); each flight's days counted as gscan.py counts n_weekly
  select sc.scan_id, sc.airline_id, f ->> 2, f ->> 3,
         sum(length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g')))::int
    from public.game_scan_schedules sc
    cross join lateral jsonb_array_elements(case when jsonb_typeof(sc.flights) = 'array' then sc.flights else '[]'::jsonb end) f
   where sc.scan_id = any (p_scan_ids) and jsonb_typeof(f) = 'array'
     and least(f ->> 2, f ->> 3) || '-' || greatest(f ->> 2, f ->> 3) in (select unnest(p_pairs))
   group by sc.scan_id, sc.airline_id, f ->> 2, f ->> 3
  having sum(length(regexp_replace(coalesce(f ->> 4, ''), '[^1-7]', '', 'g'))) > 0
$function$;

-- ============================================================ 3. the threats (1b), shared with the fare ladder's rival pause
CREATE OR REPLACE FUNCTION private.competition_threats(p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS TABLE(a text, b text, rival_id bigint, rival text, kind text, then_weekly integer, added_weekly integer, now_weekly integer,
               ours_weekly integer, scan_id bigint, scan_at timestamp with time zone, previous_id bigint,
               previous_at timestamp with time zone, until timestamp with time zone)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  w bigint := private.fig_airline_world(p_airline_id);
  v_min numeric; v_latest bigint; v_pairs text[]; v_ids bigint[];
begin
  v_min := private.fig_num(w, p_airline_id, 'competition_threat_min_weekly');
  -- the city pairs the airline flies (its live legs)
  select array_agg(distinct least(f.hub_code, f.dest_code) || '-' || greatest(f.hub_code, f.dest_code)) into v_pairs
    from private.fig_freqs(w, p_airline_id) f where f.live;
  if v_pairs is null then return; end if;
  -- the finished scans by then that still have their schedules, each with the one before it. The window is the 7 days
  -- before the moment: a threat stays listed for 7 days from the scan that first showed it. Read: the latest scan, each
  -- scan in the window that has one before it, and that one
  with sc as (select s.id, s.taken_at, row_number() over (order by s.taken_at desc, s.id desc) as rn,
                     lag(s.id) over (order by s.taken_at, s.id) as prev_id
                from public.game_scans s
               where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
                 and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id))
  select (select sc.id from sc where sc.rn = 1),
         array(select sc.id from sc where sc.rn = 1 or (sc.taken_at > p_as_of - interval '7 days' and sc.prev_id is not null)
               union
               select sc.prev_id from sc where sc.taken_at > p_as_of - interval '7 days' and sc.prev_id is not null)
    into v_latest, v_ids;
  if v_latest is null then return; end if;
  return query
  with sc as (select s.id, s.taken_at, lag(s.id) over (order by s.taken_at, s.id) as prev_id,
                     lag(s.taken_at) over (order by s.taken_at, s.id) as prev_at
                from public.game_scans s
               where s.world_id = w and s.status = 'done' and s.taken_at <= p_as_of
                 and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)),
  win as (select * from sc where sc.taken_at > p_as_of - interval '7 days' and sc.prev_id is not null),
  mine as (select least(f.hub_code, f.dest_code) as a, greatest(f.hub_code, f.dest_code) as b, sum(f.flights_week)::int as weekly
             from private.fig_freqs(w, p_airline_id) f where f.live group by 1, 2),
  -- the rivals' departures a week on those pairs in each scan read, both ways (every airline that isn't one of ours)
  ex as materialized (
    select x.scan_id, x.airline_id, least(x.origin, x.dest) as a, greatest(x.origin, x.dest) as b, sum(x.weekly)::int as weekly
      from private.scan_pair_flights(v_ids, v_pairs) x
      join public.airlines ra on ra.id = x.airline_id
      left join public.groups g on g.id = ra.group_id
     where coalesce(g.kind, 'rival') <> 'ours'
     group by 1, 2, 3, 4),
  -- a rival started (none in the scan before) or added at least competition_threat_min_weekly departures a week
  ev as (select s.id as sid, s.taken_at, s.prev_id, s.prev_at, n.a, n.b, n.airline_id, n.weekly as now_w, coalesce(p.weekly, 0) as then_w
           from win s
           join ex n on n.scan_id = s.id
           left join ex p on p.scan_id = s.prev_id and p.airline_id = n.airline_id and p.a = n.a and p.b = n.b
          where n.weekly > 0 and (coalesce(p.weekly, 0) = 0 or n.weekly - p.weekly >= v_min)),
  -- each rival on each pair once: the scan that first showed it
  fst as (select distinct on (ev.a, ev.b, ev.airline_id) ev.* from ev order by ev.a, ev.b, ev.airline_id, ev.taken_at, ev.sid)
  select f.a, f.b, f.airline_id, coalesce(ra.public_name, ra.game_name, ra.planner_name, 'airline ' || f.airline_id),
         case when f.then_w = 0 then 'started' else 'added' end, f.then_w, f.now_w - f.then_w, coalesce(l.weekly, 0), m.weekly,
         f.sid, f.taken_at, f.prev_id, f.prev_at, f.taken_at + interval '7 days'
    from fst f
    join mine m on m.a = f.a and m.b = f.b
    join public.airlines ra on ra.id = f.airline_id
    left join ex l on l.scan_id = v_latest and l.airline_id = f.airline_id and l.a = f.a and l.b = f.b
   order by f.taken_at desc, coalesce(l.weekly, 0) desc, 4, f.a, f.b;
end
$function$;

-- ============================================================ 4. competition(): market share, threats, openings, rivals
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
  -- seat, flies to about 15,000 km with its full cabin, and beyond that the type with the most seats
  v_wide_km constant int := 15000;
  v_latest bigint; v_latest_at timestamptz; v_before bigint; v_before_at timestamptz; v_prev bigint; v_prev_at timestamptz;
  v_main text; v_exempt boolean; v_target numeric; v_rival_weekly numeric; v_rival_daily numeric; v_min numeric; v_dep int;
  v_code text; v_name text; v_pairs text[]; v_ids bigint[];
  v_threats jsonb; v_body jsonb; v_group jsonb;
begin
  select a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) into v_code, v_name from public.airlines a where a.id = p_airline_id;
  v_min := private.fig_num(w, p_airline_id, 'competition_threat_min_weekly');
  v_exempt := private.fig_flag(w, p_airline_id, 'hub_first_exempt');
  v_target := private.fig_num(w, p_airline_id, 'hub_first_departures');
  v_rival_weekly := private.fig_num(w, p_airline_id, 'contested_rival_weekly');
  v_rival_daily := private.fig_num(w, p_airline_id, 'contested_rival_daily');
  select b.airport_code into v_main from public.airline_bases b where b.airline_id = p_airline_id and b.is_main order by b.id limit 1;
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

  -- the group line: our airlines' departures a week against the world's, from the scans' totals
  if v_latest is not null then
    select jsonb_build_object(
             'ours', n.ours, 'world', n.world, 'share', round(100.0 * n.ours / nullif(n.world, 0), 1),
             'ours_before', o.ours, 'world_before', o.world, 'share_before', round(100.0 * o.ours / nullif(o.world, 0), 1),
             'ours_change', n.ours - o.ours, 'world_change', n.world - o.world,
             'share_change', round(100.0 * n.ours / nullif(n.world, 0), 1) - round(100.0 * o.ours / nullif(o.world, 0), 1))
      into v_group
      from (select coalesce(sum(x.n_weekly) filter (where g.kind = 'ours'), 0)::int as ours, coalesce(sum(x.n_weekly), 0)::int as world
              from public.game_scan_airlines x left join public.airlines ra on ra.id = x.airline_id left join public.groups g on g.id = ra.group_id
             where x.scan_id = v_latest) n
      left join lateral (select coalesce(sum(x.n_weekly) filter (where g.kind = 'ours'), 0)::int as ours, coalesce(sum(x.n_weekly), 0)::int as world
                           from public.game_scan_airlines x left join public.airlines ra on ra.id = x.airline_id left join public.groups g on g.id = ra.group_id
                          where x.scan_id = v_before) o on v_before is not null;
  end if;

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
                              order by mr.weekly desc, mr.name limit 5) t))
             order by ms.ours + ms.rivals desc, ms.market nulls last, ms.market_id), '[]'::jsonb) as d
      from ms),

  -- ---------- 1c. openings: pairs on the list no airline of ours flies, one route each (from the main hub first)
  op0 as (select distinct on (ro.a, ro.b) ro.*,
                 exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub) as at_base
            from ro
           where not exists (select 1 from ourall o where o.a = ro.a and o.b = ro.b)
           order by ro.a, ro.b, (ro.hub = v_main) desc,
                    exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub) desc, ro.id),
  orv as (select rv.a, rv.b, sum(rv.weekly)::int as weekly,
                 jsonb_agg(jsonb_build_object('airline_id', rv.airline_id, 'name', rv.name, 'weekly', rv.weekly) order by rv.weekly desc, rv.name) as rivals
            from rv where rv.scan_id = v_latest group by 1, 2),
  -- the types the airline may buy, by size from their seats (manual §3's table): small (the E-jets, up to 150 seats),
  -- mid (the A320neo, up to 200), large (the A321s, up to 300), wide (the A350s)
  ty as (select t.id, t.name, t.seats_max, t.range_km, t.price,
                case when t.seats_max <= 150 then 1 when t.seats_max <= 200 then 2 when t.seats_max <= 300 then 3 else 4 end as size
           from public.aircraft_types t
           join public.airline_aircraft_types x on x.aircraft_type_id = t.id and x.airline_id = p_airline_id
          where t.world_id = w and t.seats_max > 0 and t.price > 0),
  op1 as (select op0.*, coalesce(orv.weekly, 0) as rivals_weekly, coalesce(orv.rivals, '[]'::jsonb) as rivals,
                 -- the stars' size band (manual §3): 1–2 stars small; 3 small or mid; 4 small, mid or large; 5 mid or large
                 case when coalesce(op0.stars, 0) >= 5 then 2 else 1 end as band_lo,
                 case when coalesce(op0.stars, 0) <= 2 then 1 when op0.stars = 3 then 2 else 3 end as band_hi,
                 v.id as type_id, v.name as type, v.seats_max as seats, v.range_km, v.size
            from op0
            left join orv on orv.a = op0.a and orv.b = op0.b
            -- the variant (the default line): the smallest size in the band, else bigger for reach, whose range covers the
            -- distance, the cheapest per seat; beyond every narrowbody, the wide-body line
            left join lateral (
              select t.* from ty t
               where (t.size between (case when coalesce(op0.stars, 0) >= 5 then 2 else 1 end) and 3 and t.range_km >= coalesce(op0.dist, 0))
                  or (t.size = 4 and not exists (select 1 from ty n where n.size between (case when coalesce(op0.stars, 0) >= 5 then 2 else 1 end) and 3
                                                                       and n.range_km >= coalesce(op0.dist, 0)))
               order by t.size, case when t.size = 4 and coalesce(op0.dist, 0) > v_wide_km then -t.seats_max else 0 end,
                        t.price / t.seats_max, t.name
               limit 1) v on true),
  -- hubs first (manual §3), from the latest scan: the busiest rival at a base, and each rival's departures a week from
  -- the base to the destination
  bt as (select x.airport_code, max(x.weekly_departures)::int as weekly from public.scan_airline_airports x
            join public.airlines ra on ra.id = x.airline_id left join public.groups g on g.id = ra.group_id
           where x.scan_id = v_latest and coalesce(g.kind, 'rival') <> 'ours'
             and x.airport_code in (select b.airport_code from public.airline_bases b where b.airline_id = p_airline_id)
           group by 1),
  rt as (select ex.origin, ex.dest, max(ex.weekly)::int as weekly from ex where ex.scan_id = v_latest and ex.rival group by 1, 2),
  op2 as (select op1.*, bt.weekly as base_top, rt.weekly as route_top
            from op1 left join bt on bt.airport_code = op1.hub left join rt on rt.origin = op1.hub and rt.dest = op1.dest
           where op1.type_id is not null),
  op3 as (select op2.*,
                 case when v_exempt then 'exempt' when v_main is null then 'no main hub' when op2.hub = v_main then 'main hub'
                      when v_dep >= v_target then 'main hub at its target'
                      when not op2.at_base then null
                      when coalesce(op2.base_top, 0) > v_rival_weekly then 'contested base'
                      when coalesce(op2.route_top, 0) > 7 * v_rival_daily then 'contested route' end as allowed_by
            from op2),
  op4 as (select op3.*, op3.allowed_by is not null as allowed,
                 case when op3.allowed_by is not null then null
                      when not op3.at_base then format('hubs first: %s isn''t one of its bases', op3.hub)
                      when v_latest is null then format('hubs first: %s at %s of %s departures a week, and no world scan to show %s contested',
                                                        v_main, v_dep, trim_scale(v_target), op3.hub)
                      else format('hubs first: %s at %s of %s departures a week, and %s isn''t contested (busiest rival there %s a week, over %s needed; none over %s a day on %s–%s)',
                                  v_main, v_dep, trim_scale(v_target), op3.hub, coalesce(op3.base_top, 0), trim_scale(v_rival_weekly),
                                  trim_scale(v_rival_daily), op3.hub, op3.dest) end as reason,
                 row_number() over (order by op3.allowed_by is not null desc, op3.stars desc nulls last, op3.rivals_weekly desc,
                                             op3.dist nulls last, op3.hub || '–' || op3.dest) as rank
            from op3),
  openings as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'rank', o.rank, 'route_id', o.id, 'route', o.hub || '–' || o.dest, 'hub', o.hub, 'dest', o.dest, 'pair', o.a || '-' || o.b,
             'city', o.city, 'stars', o.stars, 'distance_km', o.dist, 'market_id', o.market_id,
             'rivals_weekly', o.rivals_weekly, 'rivals', o.rivals,
             'variant', jsonb_build_object('type_id', o.type_id, 'type', o.type, 'seats', o.seats, 'range_km', o.range_km,
                                           'size', (array['small', 'mid', 'large', 'wide'])[o.size], 'for_reach', o.size > o.band_hi),
             'allowed', o.allowed, 'allowed_by', o.allowed_by, 'reason', o.reason)
             order by o.rank) filter (where o.rank <= v_limit), '[]'::jsonb) as d,
           count(*)::int as n, (count(*) filter (where o.allowed))::int as n_allowed
      from op4 o),
  left_out as (select count(*)::int as n from op1 where op1.type_id is null),

  -- ---------- 1d. rival profiles: the rivals who fly most of the airline's city pairs (latest scan)
  shared as (select rv.airline_id, rv.name, rv.a, rv.b, rv.weekly, m.weekly as ours from rv join mine m on m.a = rv.a and m.b = rv.b
              where rv.scan_id = v_latest),
  pf as (select s.airline_id, s.name, count(*)::int as pairs, sum(s.weekly)::int as weekly_on_pairs from shared s
          group by 1, 2 order by count(*) desc, sum(s.weekly) desc, s.name limit 10),
  profiles as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'airline_id', pf.airline_id, 'name', pf.name, 'pairs_shared', pf.pairs, 'weekly_on_pairs', pf.weekly_on_pairs,
             'weekly', n.n_weekly, 'weekly_before', o.n_weekly, 'change', n.n_weekly - o.n_weekly, 'airports', n.n_airports,
             'pairs', (select jsonb_agg(jsonb_build_object('pair', s.a || '-' || s.b,
                                                           'route', coalesce(rc.hub, s.a) || '–' || coalesce(rc.dest, s.b),
                                                           'weekly', s.weekly, 'ours', s.ours) order by s.weekly desc, s.a, s.b)
                         from shared s
                         left join lateral (select ro.hub, ro.dest from ro where ro.a = s.a and ro.b = s.b
                                             order by (ro.hub = v_main) desc, ro.id limit 1) rc on true
                        where s.airline_id = pf.airline_id),
             'biggest_airports', (select coalesce(jsonb_agg(jsonb_build_object('code', x.airport_code, 'weekly', x.weekly_departures)
                                                            order by x.weekly_departures desc, x.airport_code), '[]'::jsonb)
                                    from (select * from public.scan_airline_airports x where x.scan_id = v_latest and x.airline_id = pf.airline_id
                                           order by x.weekly_departures desc, x.airport_code limit 3) x))
             order by pf.pairs desc, pf.weekly_on_pairs desc, pf.name), '[]'::jsonb) as d
      from pf
      left join public.game_scan_airlines n on n.scan_id = v_latest and n.airline_id = pf.airline_id
      left join public.game_scan_airlines o on o.scan_id = v_before and o.airline_id = pf.airline_id)
  select jsonb_build_object(
           'markets', (select d from markets), 'openings', (select d from openings),
           'openings_count', (select n from openings), 'openings_allowed', (select n_allowed from openings),
           'openings_left_out', (select n from left_out), 'profiles', (select d from profiles),
           'pairs_flown', (select count(*) from mine), 'pairs_listed', (select count(distinct (ro.a, ro.b)) from ro))
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
    'group', v_group,
    'markets', v_body -> 'markets',
    'threats', v_threats,
    'openings', v_body -> 'openings', 'openings_count', v_body -> 'openings_count', 'openings_allowed', v_body -> 'openings_allowed',
    'openings_left_out', v_body -> 'openings_left_out',
    'profiles', v_body -> 'profiles',
    'pairs_flown', v_body -> 'pairs_flown', 'pairs_listed', v_body -> 'pairs_listed',
    'notes', jsonb_build_array(
      'Rivals are every airline in the scan that isn''t one of ours; departures a week count each flight''s days, as gscan.py counts them. Our own now are the airline''s live legs; before, its flights in the week-before scan.',
      'The variant is the default line''s (manual §3): the smallest size the city''s stars allow (1–2 stars small, 3 small or mid, 4 small to large, 5 mid or large), bigger only for reach, the cheapest per seat whose range with a full load covers the distance, among the types the airline may buy; beyond every narrowbody the A350 that is cheapest per seat, and beyond 15,000 km the one with the most seats.'));
end
$function$;

CREATE OR REPLACE FUNCTION public.competition(p_airline_id bigint, p_as_of timestamp with time zone DEFAULT now(), p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.caller_is_staff() then raise exception 'only planner staff can read the captured figures' using errcode = '42501'; end if;
  return private.fig_competition(p_airline_id, coalesce(p_as_of, now()), coalesce(p_limit, 50));
end
$function$;

-- ============================================================ 5. the fare ladder's rival pause (manual §5)
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
                th.rival as rv_name, th.kind as rv_kind, th.added_weekly as rv_added, th.scan_at as rv_on, th.until as rv_until
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
                     when mv.rv_name is not null then 'rival'
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
                   when 'rival' then format('rival %s %s here on %s: paused until %s', fin.rv_name,
                                            case when fin.rv_kind = 'started' then 'started' else format('added %s a week', fin.rv_added) end,
                                            to_char(fin.rv_on at time zone 'UTC', 'FMDD Mon'), to_char(fin.rv_until at time zone 'UTC', 'FMDD Mon'))
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
      'The fare index compares each flight of the latest captured day with its direction''s fare on 21 Oct 2026, when every route was at its launch level (or its first captured fare, for a route launched later), times the launch level. A route more than 1 point off its level gets a change that sets it back, first in the list, unless it''s on the fare plan this week, new, or not captured since its newest flight launched.'));
end
$function$;

-- ============================================================ 6. the briefing carries competition (spec §4)
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
    -- each route and cabin's fare level (fare_ladder()'s routes: the level, and this week's new level once it's on the
    -- fare plan) and the launch level for a route not flown yet: the plan card check's fare line (manual §5, since 21 Oct)
    'fare_ladder', (select jsonb_build_object(
        'week_of', fl.d -> 'week_of', 'settings', jsonb_build_object('launch_pct', fl.d #> '{settings,launch_pct}'),
        'routes', coalesce((select jsonb_agg(jsonb_build_object('route_id', e -> 'route_id', 'hub', e -> 'hub', 'dest', e -> 'dest', 'cabin', e -> 'cabin',
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
$function$;

-- ============================================================ 7. grants and descriptions
revoke all on function private.scan_pair_flights(bigint[], text[]) from public, anon, authenticated, service_role;
revoke all on function private.competition_threats(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.fig_competition(bigint, timestamptz, integer) from public, anon, authenticated, service_role;
revoke all on function private.fig_fare_ladder(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.briefing_doc(bigint, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.competition(bigint, timestamptz, integer) from public, anon, authenticated, service_role;
grant execute on function public.competition(bigint, timestamptz, integer) to authenticated;

comment on function private.scan_pair_flights(bigint[], text[]) is 'Competition analysis (spec docs/specs/2026-10-21-competition-analysis.md): each airline''s departures a week from origin to dest in each world scan asked for (game_scan_schedules), on the city pairs asked for, either direction (each pair as ''AAA-BBB'', its codes in order); each flight''s days counted as scripts/scanner/gscan.py counts n_weekly, a direction with none left out. Every airline, ours included: the callers tell rivals apart. Read by private.competition_threats() and private.fig_competition(), with no check of its own.';
comment on function private.competition_threats(bigint, timestamptz) is 'The threats (spec docs/specs/2026-10-21-competition-analysis.md §1b): on each city pair the airline flies (its live legs, private.fig_freqs()), each rival (every airline that isn''t one of ours, groups kind ours) who started (no departures in the scan before) or added at least settings.competition_threat_min_weekly departures a week, in a finished world scan with its schedules taken in the 7 days before p_as_of, against the finished scan before it; each rival and pair once, from the scan that first showed it (scan_id, scan_at; previous_id, previous_at), listed until 7 days after it (until). a and b are the pair''s codes in order; kind started or added; then_weekly (the scan before), added_weekly (what that scan added), now_weekly (the latest finished scan by p_as_of) and ours_weekly (the airline''s live legs, both ways). No rows with no scan or one scan. One home for competition() and the fare ladder''s rival pause (private.fig_fare_ladder()), with no check of its own.';
comment on function private.fig_competition(bigint, timestamptz, integer) is 'The captured figures (#19): builds competition()''s document with no check of its own. See competition().';
comment on function public.competition(bigint, timestamptz, integer) is 'Competition analysis for one airline (manual §3, market share first; spec docs/specs/2026-10-21-competition-analysis.md §1), as of p_as_of, from the world scans. scans: latest (the latest finished scan by then that still has its schedules), week_before (the latest at least 6 days older, else the oldest there is; null with one scan) and previous (the latest before latest), each with id and taken_at (UTC). group: our airlines'' departures a week against the world''s (the scans'' totals, game_scan_airlines.n_weekly) and our share, now, in the week-before scan and the change. markets: each of the airline''s markets (its routes not removed, flown or not, by market; No market for routes with none) with its city pairs (either direction) and how many it flies, ours (the airline''s live legs, both ways), ours_before (its flights in the week-before scan), every rival''s (every airline in the scan that isn''t one of ours) departures a week on the same pairs from the latest scan (rivals, rivals_before), our share (ours over ours and the rivals'', percent) and its change, and the top 5 rivals with their departures, change and share; biggest first. threats: private.competition_threats(), each with the rival, the route as the airline flies it, kind (started or added), then, added, now and ours, the scan''s day (on), until (7 days on), latest (shown by the latest scan) and words ("Air China started on PVG–CAN, 14 a week"). openings: each pair on the airline''s list (routes not removed; one route each, from the main hub first) that no airline of ours flies either way, with its stars, distance, the rivals flying it and their departures a week in the latest scan (both ways), the variant from the default line (manual §3: the smallest size the stars allow (1–2 small, 3 small or mid, 4 small to large, 5 mid or large; small up to 150 seats, mid 200, large 300, wide above), bigger only for reach (for_reach), the cheapest per seat whose range_km covers the distance, among the types the airline may buy (airline_aircraft_types); beyond every narrowbody the A350 cheapest per seat, beyond 15,000 km the one with the most seats; an opening no type reaches is left out and counted in openings_left_out), and hubs first (allowed, allowed_by and the reason when it isn''t: from the main hub always; from another base while the main hub is under hub_first_departures only if a rival has over contested_rival_weekly departures a week there (scan_airline_airports) or over contested_rival_daily a day from it to the destination; hub_first_exempt allows all). Ranked by stars, then rivals'' departures a week on the pair, then the shorter distance, then the route''s code, those hubs first doesn''t allow after the allowed ones; the top p_limit (50 by default; openings_count and openings_allowed count them all). profiles: the 10 rivals who fly most of the airline''s city pairs (latest scan), each with its departures a week (latest and week before, n_weekly), its airports, the pairs shared with their departures and ours, and its 3 biggest airports. hubs_first, settings and notes say what was used. Staff only; runs as owner and checks the caller itself. Read with GET.';
comment on function private.fig_fare_ladder(bigint, timestamptz) is 'The captured figures (#19): builds fare_ladder()''s document with no check of its own. See fare_ladder().';
comment on function public.fare_ladder(bigint, timestamptz) is 'The fare ladder for one airline (manual §5, since 21 Oct; specs docs/specs/2026-10-21-fare-ladder.md, docs/specs/2026-10-21-fare-actions-by-route.md, docs/specs/2026-10-21-frequencies-and-fares.md and docs/specs/2026-10-21-competition-analysis.md §2): this Saturday''s move for each route and cabin, the changes that set a route back to its level, and the game actions that make them. routes: each route not removed that flies (in economy, and in business where its aircraft have business seats) or has flights captured in the 7 days before the moment, with its departures, departures sold out (that cabin''s load at 100%), the sold-out share and the average fare over those 7 days (game_flights, matched to the route either way round); its level as a % of the game''s default price (the latest the fare plan recorded before this Saturday, else settings.fare_launch_pct) and steps above launch; the fare index: each flight of the latest captured day (latest_on, its average latest_fare) against its direction''s baseline, times the launch level, the baseline being the direction''s fare on the latest captured day on or before 21 Oct 2026, when every route was at its launch level (Gitesh), or for a route launched later its first captured fare if captured in its first growth_new_route_days days (a day''s fare: its flights'' lowest, else route_days'' average economy fare; baseline_fare and baseline_on, the directions'' average and latest day); fare_index the flights'' average, index_matches false when any flight is more than 1 point off the level the game should show (this week''s new level once the captures see it); the move (up when every departure sold out, hold at fare_ladder_down_share to 99%, down under it; hold under fare_ladder_min_departures, under growth_new_route_days old, for fare_ladder_hold_weeks after a recorded step down, while the newest rotation is under fare_ladder_capacity_hold_days old on a route older than that (a flight added: "judged at its new size from ..."; a frequency taken away isn''t tracked, its rotation is deleted), and, since 21 Oct, while a rival threatens the pair (private.competition_threats(), as competition() lists them: a rival who started there or added competition_threat_min_weekly departures a week in a scan of the 7 days before the moment; "rival Air China started here on 22 Oct: paused until 29 Oct", the one paused longest), checked after planned, new, few, held and added and before the sold-out share; never above launch + fare_ladder_cap_pts, nor under launch or, where another player flies the pair, world_rules.fare_floor_pct), the new level and the reason in words; planned, applied and seen_on for a move recorded since this Saturday; to_plan, what Put on the fare plan writes; fix, a change that sets it back to its level (index_matches false, not on the fare plan this week, not a new route, and captured since its newest rotation launched), with fix_reason ("captured fare at 100%, level 110%"). moves counts the moves, off_level the routes set back. actions: the Ticket price adjustments (baseline default price), route by route only, never a whole base (so a route under 7 days old is never touched; since 21 Oct): first the set-back changes (fix true, with the reason), then the week''s moves, each in the routes'' order (hub, dest), one action each way (From hub to dest, then From dest to hub) with classes ["economy","business"] when both cabins go to the same level, otherwise one each way for each cabin, economy first; a route whose levels don''t change gets no move. Each action has n, route, classes, from, to, level, sign, pct, baseline, fix, reason (a set-back''s) and text, the text in the game''s words naming the classes. settings: the numbers used, with capacity_hold_days and baseline_day. notes: how the index reads. Staff only; runs as owner and checks the caller itself.';
comment on function private.briefing_doc(bigint, timestamptz) is 'The airline briefing (#24): one airline''s document for export_for_report(''briefing''), read only, with no check of its own: the airline (id, world, code, names, game ID); deliveries, its aircraft not yet filed (status on_order or delivered) with type, cabin as ordered and now, bases, order date and note, delivery time and whether it has arrived by p_as_of, and each one''s plan cards (with the card''s cabin, config_id, since 21 Oct) with their legs in order (UTC weekdays and minute, block, service code); todos, the open to-dos (not done) of the airline and of the group (no airline), with their steps; fare_plan, fare_plan_status()''s document (private.fig_fare_plan()); fare_ladder, each route and cabin''s fare level from fare_ladder() (route_id, hub, dest, cabin, level, new_level and planned: the new level is the one to show once this week''s move is on the fare plan) with week_of and settings.launch_pct (the level of a route not flown yet), for the plan card check''s fare line (since 21 Oct; spec docs/specs/2026-10-21-frequencies-and-fares.md §2); competition (since 21 Oct; spec docs/specs/2026-10-21-competition-analysis.md §4), competition()''s scans, group line, hubs first, threats and top 20 openings with their counts (private.fig_competition(), p_limit 20); route_loads, route_loads()''s routes and flights for this airline only (private.fig_route_loads()). Deliveries, plan cards and to-dos are the tables as they are now; the fare plan, the fare levels, competition and the loads are as of p_as_of.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report, gander monthly, the airline briefing and the planning library: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19); and one airline''s briefing rows (kind briefing, p_arg {"airline": its id, code or name, "as_of", "world"}, the airline required: its deliveries with their plan cards and legs, open to-dos of the airline and the group, fare_plan_status(), each route''s fare level from fare_ladder() (since 21 Oct), competition()''s threats and top 20 openings (since 21 Oct) and route_loads() for it, private.briefing_doc(), #24; read only). Kind planner (the old planner''s documents) is refused since the clean-up (build pull request 14). Needs the ingest secret.';

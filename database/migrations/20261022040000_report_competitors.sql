-- The weekly report sets each airline against its three biggest competitors (22 Oct 2026; manual §7, the weekly report;
-- spec docs/specs/2026-10-21-report-three-competitors.md §1).
--
-- Why (Gitesh, decided 18 Oct, asked for on 21 Oct): to see whether each airline is gaining on its rivals. competition()
-- already has the scans and the rivals (#62), so the report reads it rather than working it out again.
--
-- Replaces two functions with the same arguments (CREATE OR REPLACE); adds, drops and renames nothing and changes no data,
-- so it can be applied from the chat:
--   - private.fig_competition() (so competition() and the briefing): adds competitors, the three rivals (every airline
--     that isn't one of ours, passenger flights only, as the rest of competition()) with the most departures a week on
--     the city pairs the airline flies (its live legs, both ways) in the latest scan, ties by name; each with on_pairs and
--     pairs, its whole passenger network in the latest scan (weekly, airports) and in the week-before scan
--     (weekly_before), and the change as a number and a percent. And self: the airline on the same terms, from the same
--     scans' schedules. Growth is against the week-before scan, since the scans run every evening (the spec). Nothing
--     else in the document changes.
--   - private.fig_export() (so export_for_report('figures'), which scripts/report/pull.py saves as figures.json): each
--     airline also carries competitors, self and scans (competition()'s, with their dates), from private.fig_competition()
--     with p_limit 0. Nothing else in the export changes.
-- Descriptions: competition(), export_for_report() and private.fig_export(). The private functions stay internal.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261022040000_report_competitors', true);

-- ============================================================ 1. competition(): the three biggest competitors, and self
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
  v_trunk_from date; v_trunk_to date; v_trunks boolean;
begin
  select a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) into v_code, v_name from public.airlines a where a.id = p_airline_id;
  v_min := private.fig_num(w, p_airline_id, 'competition_threat_min_weekly');
  v_exempt := private.fig_flag(w, p_airline_id, 'hub_first_exempt');
  v_target := private.fig_num(w, p_airline_id, 'hub_first_departures');
  v_rival_weekly := private.fig_num(w, p_airline_id, 'contested_rival_weekly');
  v_rival_daily := private.fig_num(w, p_airline_id, 'contested_rival_daily');
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
  -- our bases, every airline's (hubs and focus cities): a pair between two of them is a trunk (manual §4)
  ob as (select distinct b.airport_code from public.airline_bases b
           join public.airlines a on a.id = b.airline_id join public.groups g on g.id = a.group_id
          where b.world_id = w and g.kind = 'ours'),
  -- the other airlines of ours that have the pair on their own list (one airline per city pair, manual §2, decides)
  ol as (select least(r.hub_code, r.dest_code) as a, greatest(r.hub_code, r.dest_code) as b, array_agg(distinct al.iata_code order by al.iata_code) as codes
           from public.routes r join public.airlines al on al.id = r.airline_id join public.groups g on g.id = al.group_id
          where r.world_id = w and r.airline_id <> p_airline_id and not r.removed and g.kind = 'ours' and al.iata_code is not null
          group by 1, 2),
  op0 as (select distinct on (ro.a, ro.b) ro.*,
                 exists (select 1 from public.airline_bases b where b.airline_id = p_airline_id and b.airport_code = ro.hub) as at_base,
                 -- in the trunk month only (trunk_month_from to trunk_month_to)
                 v_trunks and ro.hub in (select ob.airport_code from ob) and ro.dest in (select ob.airport_code from ob) as trunk
            from ro
           where not exists (select 1 from ourall o where o.a = ro.a and o.b = ro.b)
           order by ro.a, ro.b, (ro.hub = v_main) desc,
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
                 v.id as type_id, v.name as type, v.seats_max as seats, v.range_km, v.size, v.own, alt.name as alt_type
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
               limit 1) v on true
            -- the thinnest 1-star city (manual §3's default line: the E190-E2 for "3,542–4,065 km, or the thinnest 1-star
            -- city"; spec docs/specs/2026-10-21-tidy-ups.md §2): nothing in our data says how thin a city is, so a 1-star
            -- opening whose variant is the default small aircraft (the E195-E2) also names the small type with the fewest
            -- seats that the airline may buy and that reaches it (the E190-E2); the evening proposal decides
            left join lateral (
              select a.name from ty a
               where a.own and a.size = 1 and a.range_km >= coalesce(op0.dist, 0) and a.seats_max < v.seats_max
               order by a.seats_max, a.price / a.seats_max, a.name
               limit 1) alt on coalesce(op0.stars, 0) = 1 and v.size = 1),
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
                 -- hubs first is suspended for trunks in the trunk month (manual §4)
                 case when op2.trunk then 'November trunk'
                      when v_exempt then 'exempt' when v_main is null then 'no main hub' when op2.hub = v_main then 'main hub'
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
             -- a thin 1-star city's alternative, only where there is one
             || case when o.alt_type is not null
                     then jsonb_build_object('variant_alt', o.alt_type, 'variant_note', format('or the %s if thin', o.alt_type))
                     else '{}'::jsonb end
             order by o.rank) filter (where o.rank <= v_limit), '[]'::jsonb) as d,
           count(*)::int as n, (count(*) filter (where o.allowed))::int as n_allowed, (count(*) filter (where o.trunk))::int as n_trunks
      from op4 o left join ol l on l.a = o.a and l.b = o.b),
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
                                           group by 1 having sum(y.n) > 0 order by 2 desc, 1 limit 3) x))
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
             'change_pct', round(100.0 * (n.weekly - o.weekly) / nullif(o.weekly, 0), 1))
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
      left join crs o on o.scan_id = v_before and o.airline_id = p_airline_id)
  select jsonb_build_object(
           'markets', (select d from markets), 'openings', (select d from openings),
           'openings_count', (select n from openings), 'openings_allowed', (select n_allowed from openings),
           'openings_left_out', (select n from left_out), 'openings_trunks', (select n_trunks from openings), 'profiles', (select d from profiles),
           'pairs_flown', (select count(*) from mine), 'pairs_listed', (select count(distinct (ro.a, ro.b)) from ro),
           'competitors', (select d from competitors), 'self', (select d from self))
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
    'notes', jsonb_build_array(
      'Rivals are every airline in the scan that isn''t one of ours; departures a week count each flight''s days, as gscan.py counts them, passenger flights only (freighters left out, as the weekly report counts). Our own now are the airline''s live legs; before, its flights in the week-before scan.',
      'From trunk_month_from to trunk_month_to (November, manual §4) the trunks, pairs between two of our bases (any of our airlines''), come first, shortest first: hubs first isn''t applied to them and no distance leaves one out. Whether a trunk makes sense stays the Scheduling chat''s judgment.',
      'The variant is the default line''s (manual §3): the smallest size the city''s stars allow (1–2 stars small, 3 small or mid, 4 small to large, 5 mid or large), bigger only for reach, the cheapest per seat whose range with a full load covers the distance, among the types the airline may buy; beyond every narrowbody the A350 that is cheapest per seat, and beyond 15,000 km the one with the most seats. A 1-star opening whose variant is the default small aircraft (the E195-E2) also names the small type with the fewest seats (variant_alt, the E190-E2, "or the E190-E2 if thin" in variant_note): the default line gives it to the thinnest 1-star city, and nothing in our data says how thin a city is, so the evening proposal decides.',
      'competitors (the weekly report''s, manual §7): the three rivals with the most departures a week on the city pairs the airline flies (its live legs, both ways) in the latest scan, ties by name; weekly and airports are each one''s whole passenger network in the latest scan, weekly_before in the week-before scan (none when that scan holds no schedule for it), the change against it as a number and a percent. self is the airline on the same terms, from the same scans'' schedules.'));
end
$function$;

-- ============================================================ 2. the export: each airline's competitors, self and scans
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
        'competitors', cp.d -> 'competitors', 'self', cp.d -> 'self', 'scans', cp.d -> 'scans') order by al.ord), '[]'::jsonb)
        from private.fig_airlines(p_world_id) al
        -- offset 0 keeps each document worked out once (folded into the outer query, each use would work it out again)
        cross join lateral (select private.fig_route_profit(al.airline_id, 1, p_as_of) as d offset 0) r1
        cross join lateral (select private.fig_route_profit(al.airline_id, 3, p_as_of) as d offset 0) r3
        cross join lateral (select private.fig_route_profit(al.airline_id, 7, p_as_of) as d offset 0) r7
        cross join lateral (select private.fig_competition(al.airline_id, p_as_of, 0) as d offset 0) cp));
end
$function$;

-- ============================================================ who may call them (unchanged: internal)
revoke all on function private.fig_competition(bigint, timestamptz, integer) from public, anon, authenticated, service_role;
revoke all on function private.fig_export(bigint, timestamptz) from public, anon, authenticated, service_role;

-- ============================================================ descriptions
comment on function private.fig_export(bigint, timestamp with time zone) is 'The captured figures (#19): every figure for every airline of a world in one document, for export_for_report(''figures''), with no check of its own. Since 22 Oct each airline also carries competition()''s competitors, self and scans (private.fig_competition() with p_limit 0), for the weekly report''s three biggest competitors (manual §7).';
comment on function public.competition(bigint, timestamptz, integer) is 'Competition analysis for one airline (manual §3, market share first; spec docs/specs/2026-10-21-competition-analysis.md §1), as of p_as_of, from the world scans. scans: latest (the latest finished scan by then that still has its schedules), week_before (the latest at least 6 days older, else the oldest there is; null with one scan) and previous (the latest before latest), each with id and taken_at (UTC). group: our airlines'' passenger departures a week against the world''s (every airline''s schedule in the scan, freighters left out by private.scan_passenger(), the weekly report''s rule) and our share, now, in the week-before scan and the change. Freighters are no one''s rivals anywhere here: market share, threats, the openings'' rivals and the profiles count passenger flights only. markets: each of the airline''s markets (its routes not removed, flown or not, by market; No market for routes with none) with its city pairs (either direction) and how many it flies, ours (the airline''s live legs, both ways), ours_before (its flights in the week-before scan), every rival''s (every airline in the scan that isn''t one of ours) departures a week on the same pairs from the latest scan (rivals, rivals_before), our share (ours over ours and the rivals'', percent) and its change, and the top 5 rivals with their departures, change and share; biggest first. threats: private.competition_threats(), each with the rival, the route as the airline flies it, kind (started or added), then, added, now and ours, the scan''s day (on), until (7 days on), latest (shown by the latest scan) and words ("Air China started on PVG–CAN, 14 a week"). openings: each pair on the airline''s list (routes not removed; one route each, from the main hub first) that no airline of ours flies either way, with its stars, distance, the rivals flying it and their departures a week in the latest scan (both ways), the variant from the default line (manual §3: the smallest size the stars allow (1–2 small, 3 small or mid, 4 small to large, 5 mid or large; small up to 150 seats, mid 200, large 300, wide above), bigger only for reach (for_reach), the cheapest per seat whose range_km covers the distance, among the types the airline may buy (airline_aircraft_types); beyond every narrowbody the A350 cheapest per seat, beyond 15,000 km the one with the most seats; an opening no type reaches is left out and counted in openings_left_out), and hubs first (allowed, allowed_by and the reason when it isn''t: from the main hub always; from another base while the main hub is under hub_first_departures only if a rival has over contested_rival_weekly departures a week there (scan_airline_airports) or over contested_rival_daily a day from it to the destination; hub_first_exempt allows all). Ranked by stars, then rivals'' departures a week on the pair, then the shorter distance, then the route''s code, those hubs first doesn''t allow after the allowed ones; the top p_limit (50 by default; openings_count and openings_allowed count them all). From settings.trunk_month_from to trunk_month_to (1 to 30 November 2026, manual §4; trunk_month gives on, from and to): each trunk (a pair between two of our bases, any of our airlines'' hubs and focus cities in airline_bases) is marked trunk, allowed with allowed_by ''November trunk'' (hubs first suspended for trunks), never left out for reach (the world''s types when none the airline may buy reaches, variant.own false), and the trunks come first, shortest first, then the other openings as always (openings_trunks counts them); outside those days trunk is false and nothing changes. other_lists: our other airlines that have the pair on their own list (one airline per city pair, manual §2, decides). variant_alt and variant_note (since 22 Oct; spec docs/specs/2026-10-21-tidy-ups.md §2): on a 1-star opening whose variant is the default small aircraft (the E195-E2), the small type with the fewest seats the airline may buy that reaches it (the E190-E2), and the words "or the E190-E2 if thin": the default line gives the E190-E2 to the thinnest 1-star city, which nothing in our data measures, so the evening proposal decides; not there on any other opening. profiles: the 10 rivals who fly most of the airline''s city pairs (latest scan), each with its passenger departures a week (latest and week before), its airports and its 3 biggest by passenger departures, from its schedule, and the pairs shared with their departures and ours. competitors (since 22 Oct; manual §7, the weekly report; spec docs/specs/2026-10-21-report-three-competitors.md): the three rivals with the most departures a week on the city pairs the airline flies (its live legs, both ways) in the latest scan, ties by name, each with rank, airline_id, name, on_pairs (its departures a week on those pairs), pairs (how many of them it flies), weekly and airports (its whole passenger network in the latest scan), weekly_before (in the week-before scan; null when that scan holds no schedule for it), change and change_pct (against weekly_before, a number and a percent to one decimal); empty without a scan. self: the airline on the same terms from the same scans'' schedules (on_pairs, pairs, weekly, airports, weekly_before, change, change_pct), with pairs_flown (how many pairs its live legs fly) and its code and name; null without a scan. hubs_first, settings and notes say what was used. Staff only; runs as owner and checks the caller itself. Read with GET.';
comment on function public.export_for_report(text, text, text) is 'Exports for the weekly report, gander monthly, the airline briefing and the planning library: the world scans (snapshots), a scan''s airlines (with their schedules) and airports, each in the order the scan stored them, from game_scans and its tables with the same answers as before #13; the planning rules (kind rules, p_arg the world or empty for the default: exactly what rules_input() gives, #19); the captured figures (kind figures, p_arg {"as_of", "world"}, both optional: airline_cards(), growth_signals(), hub_progress(), capture_status(), and for every airline cash_forecast(), airline_profit(), route_profit() and aircraft_profit() over 1, 3 and 7 days and fare_changes(), #19, and since 22 Oct competition()''s competitors, self and scans, the weekly report''s three biggest competitors); and one airline''s briefing rows (kind briefing, p_arg {"airline": its id, code or name, "as_of", "world"}, the airline required: its deliveries with their plan cards and legs, open to-dos of the airline and the group, fare_plan_status(), each route''s fare level from fare_ladder() (since 21 Oct), competition()''s threats and top 20 openings (since 21 Oct) and route_loads() for it, private.briefing_doc(), #24; read only). Kind planner (the old planner''s documents) is refused since the clean-up (build pull request 14). Needs the ingest secret.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

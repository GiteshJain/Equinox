-- The fleet check leaves out aircraft not delivered yet (26 Oct, Gitesh). The game lists an ordered aircraft in the fleet
-- before it arrives, parked at the factory with no seats, no pilots and an age that means nothing: on 24 Oct EI-ACF
-- (CDG), ordered new the day before, showed as "looks used (24.1 years in the game), marked new". An aircraft on order
-- in the planner, or one the game lists with no seats and no pilots, is now left out of the aircraft's checks
-- (maintenance, no pilots, seats, replacement by age, looks used) and marked undelivered in the list; it is checked from
-- its first fleet capture after it arrives. The other checks (in the game but not the planner, and the reverse) as before.
select set_config('equinox.actor', 'claude', true), set_config('equinox.actor_detail', 'building: fleet check undelivered', true);

CREATE OR REPLACE FUNCTION private.fig_fleet_checks(p_world_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_night date; v_doc jsonb;
  v_new numeric; v_used numeric; v_warn numeric;
begin
  -- the replacement ages (manual §3, since 22 Oct): new at replace_new_years, used at replace_used_years, warned
  -- replace_warn_days before
  v_new := private.fig_num(p_world_id, null, 'replace_new_years');
  v_used := private.fig_num(p_world_id, null, 'replace_used_years');
  v_warn := private.fig_num(p_world_id, null, 'replace_warn_days');
  -- the latest night any of our airlines' fleet pages came in, by the moment
  select max(f.capture_day) into v_night
    from public.game_fleet f join private.fig_airlines(p_world_id) al on al.airline_id = f.airline_id
   where f.world_id = p_world_id and f.captured_at <= p_as_of;

  with al as (
    select x.airline_id, x.ord, x.iata_code, x.name, private.fig_num(p_world_id, x.airline_id, 'maintenance_min_pct') as min_pct
      from private.fig_airlines(p_world_id) x),
  span as (select private.capture_day_start(p_world_id, v_night) as from_at),
  -- each airline's latest run of fleet pages that night (a run: the pages one press of the capture read, from one read
  -- of the fleet list), and whether every page of it came in ok
  pg as (
    select r.airline_id, r.rows ->> 'run' as run, private.json_int(r.rows -> 'page') as page, private.json_int(r.rows -> 'of') as of_,
           r.verdict, r.captured_at, r.id
      from public.game_capture_raw r, span
     where r.world_id = p_world_id and r.kind = 'fleet' and v_night is not null
       and r.captured_at >= span.from_at and r.captured_at < span.from_at + interval '1 day' and r.captured_at <= p_as_of),
  lastrun as (select distinct on (pg.airline_id) pg.airline_id, pg.run from pg order by pg.airline_id, pg.captured_at desc, pg.id desc),
  runpages as (
    select distinct on (pg.airline_id, pg.page) pg.airline_id, pg.page, pg.of_, pg.verdict
      from pg join lastrun l on l.airline_id = pg.airline_id and l.run is not distinct from pg.run
     order by pg.airline_id, pg.page, pg.captured_at desc, pg.id desc),
  runs as (
    select rp.airline_id, max(rp.of_) as expected, (count(*) filter (where rp.verdict = 'ok'))::int as ok_pages, count(*)::int as pages,
           coalesce(max(rp.of_), 0) > 0 and (count(*) filter (where rp.verdict = 'ok')) >= max(rp.of_)
             and not bool_or(rp.verdict is distinct from 'ok') as all_ok
      from runpages rp group by rp.airline_id),
  ac as (
    select a.id, a.airline_id, a.registration, a.base_code, a.status, a.cabin_config_id, c.code as cabin_code,
           a.acquired, a.delivery_at,
           c.economy_seats, c.business_seats,
           case when c.seats is not null and c.business_seats is not null and c.economy_seats is not null
                then greatest(c.seats - c.business_seats - c.economy_seats, 0) else 0 end as first_seats
      from public.aircraft a left join public.cabin_configs c on c.id = a.cabin_config_id
     where a.world_id = p_world_id and a.airline_id in (select al.airline_id from al)),
  fl as (
    select f.*, al.ord, al.iata_code, al.min_pct, m.id as planner_id, m.base_code, m.cabin_config_id, m.cabin_code,
           m.economy_seats, m.business_seats, m.first_seats, m.acquired, m.delivery_at,
           case when m.acquired = 'used' then v_used when m.acquired = 'new' then v_new end as replace_at,
           f.registration || ' (' || coalesce(m.base_code, f.fleet_name, '?') || ')' as who,
           -- not delivered yet (since 26 Oct): on order in the planner, or listed by the game with no seats and no pilots
           -- (an ordered aircraft waits at the factory with an age that means nothing); left out of the aircraft's checks
           coalesce(m.status = 'on_order', false)
             or (coalesce(f.seats_y, 0) = 0 and coalesce(f.seats_c, 0) = 0 and coalesce(f.seats_f, 0) = 0 and f.pilots is false) as undelivered,
           format('%s/%s/%s', coalesce(f.seats_y::text, '?'), coalesce(f.seats_c::text, '?'), coalesce(f.seats_f::text, '?')) as seats
      from public.game_fleet f
      join al on al.airline_id = f.airline_id
      left join lateral (select x.* from ac x where x.airline_id = f.airline_id and upper(x.registration) = f.registration
                          order by x.status = 'retired', x.id desc limit 1) m on true
     where f.world_id = p_world_id and f.capture_day = v_night and f.captured_at <= p_as_of),
  probs as (
    select 1 as rank, 'maintenance' as kind, fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name) as base,
           fl.planner_id as aircraft_id,
           format('%s: maintenance %s%%, condition %s%%', fl.who, fl.maintenance_pct, coalesce(trim_scale(fl.condition_pct)::text, '?')) as words
      from fl where fl.maintenance_pct < fl.min_pct and not fl.undelivered
    union all
    select 2, 'crew', fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name), fl.planner_id,
           format('%s: no pilots', fl.who)
      from fl where fl.pilots = false and not fl.undelivered
    union all
    select 3, 'cabin', fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name), fl.planner_id,
           case when fl.cabin_config_id is null then format('%s: no cabin in the planner (%s in the game)', fl.who, fl.seats)
                else format('%s: seats %s in the game, %s/%s/%s in the planner (%s)', fl.who, fl.seats, coalesce(fl.economy_seats::text, '?'),
                            coalesce(fl.business_seats::text, '?'), fl.first_seats, coalesce(nullif(fl.cabin_code, ''), 'its cabin')) end
      from fl
     where fl.planner_id is not null and not fl.undelivered
       and (fl.cabin_config_id is null
            or (fl.economy_seats is not null and fl.seats_y is distinct from fl.economy_seats)
            or (fl.business_seats is not null and fl.seats_c is distinct from fl.business_seats)
            or coalesce(fl.seats_f, 0) <> fl.first_seats)
    union all
    select 4, 'not_in_planner', fl.airline_id, fl.ord, fl.iata_code, fl.registration, fl.fleet_name, null::bigint,
           format('%s: in the game (%s fleet), not in the planner', fl.registration, coalesce(fl.fleet_name, 'its'))
      from fl where fl.planner_id is null
    union all
    select 5, 'not_in_game', a.airline_id, al.ord, al.iata_code, a.registration, a.base_code, a.id,
           format('%s (%s): in the planner, not on the game''s fleet pages', a.registration, coalesce(a.base_code, '?'))
      from ac a join al on al.airline_id = a.airline_id join runs ru on ru.airline_id = a.airline_id and ru.all_ok
     where a.status = 'active'
       and not exists (select 1 from fl where fl.airline_id = a.airline_id and fl.registration = upper(a.registration))
    union all
    -- replacement by age (manual §3, since 22 Oct): from replace_warn_days before the replacement age, on the game's age
    select 6, 'replace', fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name), fl.planner_id,
           case when fl.age_years >= fl.replace_at
                then format('%s: past its replacement age (%s years, now %s)', fl.who, trim_scale(fl.replace_at), fl.age_years)
                else format('%s: replace at %s years (now %s): order its replacement', fl.who, trim_scale(fl.replace_at), fl.age_years) end
      from fl
     where fl.planner_id is not null and not fl.undelivered and fl.replace_at is not null and fl.age_years is not null
       and fl.age_years >= fl.replace_at - v_warn / 365.25
    union all
    -- the cross-check: marked new, but older in the game than its time with us by more than 0.2 years
    select 7, 'age', fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name), fl.planner_id,
           format('%s: looks used (%s years in the game), marked new', fl.who, fl.age_years)
      from fl
     where fl.planner_id is not null and not fl.undelivered and fl.acquired = 'new' and fl.delivery_at is not null and fl.age_years is not null
       and fl.age_years - (v_night - (fl.delivery_at at time zone 'UTC')::date) / 365.25 > 0.2),
  kinds as (select * from unnest(array['maintenance', 'crew', 'cabin', 'not_in_planner', 'not_in_game', 'replace', 'age']) with ordinality k(kind, o))
  select jsonb_build_object(
    'world_id', p_world_id, 'as_of', private.fig_ts(p_as_of), 'night', v_night,
    'counts', (select jsonb_object_agg(k.kind, (select count(*) from probs p where p.kind = k.kind) order by k.o)
                      || jsonb_build_object('problems', (select count(*) from probs))
                 from kinds k),
    'problems', coalesce((select jsonb_agg(jsonb_build_object('kind', p.kind, 'airline_id', p.airline_id, 'code', p.iata_code,
                                                              'registration', p.registration, 'base', p.base, 'aircraft_id', p.aircraft_id,
                                                              'words', p.words)
                                           order by p.rank, p.ord, p.registration) from probs p), '[]'::jsonb),
    'airlines', coalesce((select jsonb_agg(jsonb_build_object(
        'airline_id', al.airline_id, 'code', al.iata_code, 'name', al.name, 'maintenance_min_pct', al.min_pct,
        'pages', (select jsonb_build_object('read', ru.pages, 'ok', ru.ok_pages, 'expected', ru.expected, 'all_ok', ru.all_ok)
                    from runs ru where ru.airline_id = al.airline_id),
        'at', (select private.fig_ts(max(fl.captured_at)) from fl where fl.airline_id = al.airline_id),
        'aircraft', coalesce((select jsonb_agg(jsonb_build_object(
            'registration', fl.registration, 'aircraft_id', fl.planner_id, 'base', coalesce(fl.base_code, fl.fleet_name),
            'fleet', fl.fleet_name, 'type', fl.type_name, 'nickname', fl.nickname, 'from', fl.location_from, 'to', fl.location_to,
            'flight', fl.flight, 'age_years', fl.age_years, 'acquired', fl.acquired, 'replace_at_years', fl.replace_at, 'undelivered', fl.undelivered,
            'condition_pct', fl.condition_pct, 'maintenance_pct', fl.maintenance_pct,
            'y', fl.seats_y, 'c', fl.seats_c, 'f', fl.seats_f, 'pilots', fl.pilots, 'owned', fl.owned, 'contract', fl.contract_status,
            'captured_at', private.fig_ts(fl.captured_at),
            'problems', coalesce((select jsonb_agg(p.kind order by p.rank) from probs p
                                   where p.airline_id = fl.airline_id and p.registration = fl.registration and p.kind <> 'not_in_game'), '[]'::jsonb))
            order by fl.registration) from fl where fl.airline_id = al.airline_id), '[]'::jsonb))
        order by al.ord) from al), '[]'::jsonb))
    into v_doc;
  return v_doc;
end
$function$;

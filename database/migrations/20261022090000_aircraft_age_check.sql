-- The aircraft age check and replacement warning (22 Oct 2026; spec docs/specs/2026-10-22-aircraft-age-check.md, brief
-- docs/briefs/2026-10-22-aircraft-age-check.md, option B simplified: the game's age, no built date; manual §3,
-- replacement by age: an aircraft we ordered new is replaced at 3 years, one from the used market at 10).
--
-- Why: nothing in the planner knew which aircraft came used (only aircraft.order_note, in prose), and nothing warned when
-- an aircraft neared its replacement age. The capture already reads each aircraft's age every night (game_fleet.age_years,
-- in tenths of a year), and fleet_checks() feeds Today's Fleet group, Systems' Fleet board and the Tails pop-up.
--
-- Adds a column and three settings, replaces one function with the same arguments; drops and renames nothing, so it can
-- be applied from the chat.
--   1. aircraft.acquired: new (the default) or used (the game's Aircraft Market), not null, checked; described. Backfilled
--      used for N023AW, 9M-AAY and G-AAFB (ids 283, 284, 285; their order_note starts "Used,"). Staff already read and
--      write aircraft (its grants and rules cover every column), and planner_save() takes any of its columns.
--   2. settings replace_new_years 3, replace_used_years 10 and replace_warn_days 60, world rows in every world, described.
--   3. private.fig_fleet_checks() (so fleet_checks()): each aircraft's row gains acquired and replace_at_years, and two
--      new kinds, replace (within replace_warn_days of the replacement age, or past it) and age (marked new, but older in
--      the game than its time with us by more than 0.2 years), in counts and problems as the others, after not_in_game.
-- The grants stay as they were.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261022090000_aircraft_age_check', true);

-- ============================================================ 1. new or used, on each aircraft
alter table public.aircraft add column acquired text not null default 'new';
alter table public.aircraft add constraint aircraft_acquired_kinds check (acquired in ('new', 'used'));
comment on column public.aircraft.acquired is
  'How we got the aircraft: new from the factory, or used from the game''s Aircraft Market; decides its replacement age, manual §3 (settings replace_new_years, replace_used_years)';
comment on constraint aircraft_acquired_kinds on public.aircraft is 'An aircraft came new or used (manual §3, since 22 Oct)';

-- the three used aircraft bought on 22 Oct (their order_note starts "Used,")
update public.aircraft a set acquired = 'used'
 where a.id in (283, 284, 285) and a.registration in ('N023AW', '9M-AAY', 'G-AAFB') and a.order_note like 'Used,%'
   and a.acquired <> 'used';

-- ============================================================ 2. the rule's numbers, in every world
insert into public.settings (world_id, airline_id, key, value, unit, description, since, reason)
select w.id, null, x.key, x.value, x.unit, x.description, date '2026-10-22', 'manual §3, replacement by age (Gitesh, 22 Oct)'
  from public.worlds w
 cross join (values
   ('replace_new_years', '3'::jsonb, 'years',
    'An aircraft we ordered new (aircraft.acquired new) is replaced when it reaches this age, by the game''s age (game_fleet.age_years); fleet_checks() warns from replace_warn_days before (manual §3)'),
   ('replace_used_years', '10'::jsonb, 'years',
    'An aircraft from the game''s used market (aircraft.acquired used) is replaced when it reaches this age, by the game''s age (game_fleet.age_years); fleet_checks() warns from replace_warn_days before (manual §3)'),
   ('replace_warn_days', '60'::jsonb, 'days',
    'How long before an aircraft''s replacement age (replace_new_years or replace_used_years) Today''s Fleet group starts to warn: order its replacement (manual §3)')
 ) as x(key, value, unit, description)
on conflict on constraint settings_world_airline_key_key do nothing;

-- ============================================================ 3. the fleet checks: replace and age
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
      from fl where fl.maintenance_pct < fl.min_pct
    union all
    select 2, 'crew', fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name), fl.planner_id,
           format('%s: no pilots', fl.who)
      from fl where fl.pilots = false
    union all
    select 3, 'cabin', fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name), fl.planner_id,
           case when fl.cabin_config_id is null then format('%s: no cabin in the planner (%s in the game)', fl.who, fl.seats)
                else format('%s: seats %s in the game, %s/%s/%s in the planner (%s)', fl.who, fl.seats, coalesce(fl.economy_seats::text, '?'),
                            coalesce(fl.business_seats::text, '?'), fl.first_seats, coalesce(nullif(fl.cabin_code, ''), 'its cabin')) end
      from fl
     where fl.planner_id is not null
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
     where fl.planner_id is not null and fl.replace_at is not null and fl.age_years is not null
       and fl.age_years >= fl.replace_at - v_warn / 365.25
    union all
    -- the cross-check: marked new, but older in the game than its time with us by more than 0.2 years
    select 7, 'age', fl.airline_id, fl.ord, fl.iata_code, fl.registration, coalesce(fl.base_code, fl.fleet_name), fl.planner_id,
           format('%s: looks used (%s years in the game), marked new', fl.who, fl.age_years)
      from fl
     where fl.planner_id is not null and fl.acquired = 'new' and fl.delivery_at is not null and fl.age_years is not null
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
            'flight', fl.flight, 'age_years', fl.age_years, 'acquired', fl.acquired, 'replace_at_years', fl.replace_at,
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

comment on function private.fig_fleet_checks(bigint, timestamptz) is 'The captured figures (#19): builds fleet_checks()''s document with no check of its own. See fleet_checks().';
comment on function public.fleet_checks(bigint, timestamptz) is 'The fleet checks (spec docs/specs/2026-10-22-fleet-capture.md §2; manual §7), in a world (the default when null), as of p_as_of (now by default), from the latest night''s game_fleet for our airlines (night: the latest capture day any of them has, captured by the moment). problems, worst first (maintenance, crew, cabin, not in the planner, not in the game, then since 22 Oct replace and age; then by airline and registration), each with its kind, airline, registration, base (the planner''s, else the fleet''s), aircraft and words: maintenance, the game''s maintenance under settings.maintenance_min_pct (100; an airline''s own where it has one), with the condition beside it ("N003AW (JFK): maintenance 0.0%, condition 83%"); crew, pilots no; cabin, seats Y/C/F that don''t match the aircraft''s cabin in the planner (aircraft.cabin_config_id, cabin_configs'' economy and business seats, first class 0), or no cabin in the planner; not_in_planner, a registration on the game''s fleet pages that no aircraft row of the airline has; not_in_game, an active aircraft of ours missing from that night''s fleet pages, only when every fleet page of its airline''s latest run that night came in ok. Since 22 Oct (spec docs/specs/2026-10-22-aircraft-age-check.md; manual §3, replacement by age): replace, an aircraft within settings.replace_warn_days (60) of its replacement age by the game''s age (age_years >= replace_at_years - replace_warn_days / 365.25; replace_at_years is settings.replace_new_years, 3, for one marked new in aircraft.acquired, replace_used_years, 10, for one marked used): "N001AW (JFK): replace at 3 years (now 2.9): order its replacement", and once at or past it "N001AW (JFK): past its replacement age (3 years, now 3.0)"; age, the cross-check, an aircraft marked new that is older in the game than its time with us (the night less its delivery_at) by more than 0.2 years: "N023AW (JFK): looks used (3.6 years in the game), marked new" (none without a delivery_at). counts: each kind''s and problems in all. airlines: each of ours with its maintenance limit, its latest run''s pages (read, ok, expected, all_ok), when its fleet was read and its aircraft that night (registration, planner aircraft, base, fleet, type, nickname, location, flight, age, since 22 Oct acquired (new or used) and replace_at_years, condition, maintenance, seats, pilots, owned, contract, captured_at and its problems). Staff only, read with GET; runs as owner with its own 30 second limit, as the other figures.';

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);

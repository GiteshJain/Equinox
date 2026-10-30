-- The market pages' service codes as the planner writes them (31 Oct 2026; the first live market run of 30 Oct).
--
-- Why: the game names its service profiles with a note, "S2 (min 800km)", "S3 (min 1500km)", and capture 1.9 stored
-- the whole name in market_reads.service_code, while the planner and service_profiles write the code alone (S2). The
-- service check compared the two as they stood, so every pair but Ryanair's (R) would read as a mismatch. Capture 1.10
-- sends the code alone; the 262 reads already stored keep the game's name, so the check compares on the code's leading
-- token, and capture_market() keeps only the token from now on, whatever a capture sends.
--
-- Adds one function and replaces two with the same arguments; changes, drops and renames nothing else, so it can be
-- applied from the chat:
--   - private.market_service_token(p text): the leading token before " (", trimmed; null when empty.
--   - private.fig_market_service_checks(): game_code is the token of market_reads.service_code (was the whole text).
--   - private.market_ingest(): stores the token as market_reads.service_code.

select set_config('equinox.actor', 'migration', true),
       set_config('equinox.actor_detail', '20261031120000_market_service_token', true);

create or replace function private.market_service_token(p text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select nullif(btrim(split_part(btrim(coalesce(p, '')), ' (', 1)), '')
$function$;

CREATE OR REPLACE FUNCTION private.fig_market_service_checks(p_world_id bigint, p_airline_id bigint, p_as_of timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_run record; v_checked int := 0; v_rows jsonb := '[]'::jsonb;
begin
  -- the latest finished market run by the moment
  select r.id, r.started_at, r.finished_at, r.pages_read, r.pages_failed into v_run
    from public.market_runs r
   where r.world_id = p_world_id and r.status = 'done' and r.started_at <= p_as_of
   order by r.started_at desc, r.id desc limit 1;
  if v_run.id is not null then
    with rd as (
      select m.id, m.airline_id, m.origin, m.dest, m.read_at, private.market_service_token(m.service_code) as game_code
        from public.market_reads m
       where m.run_id = v_run.id and m.ok and (p_airline_id is null or m.airline_id = p_airline_id)),
    -- the read airline's route on the pair (not removed; one with rotations first, then the oldest)
    ro as (
      select distinct on (rd.id) rd.id as read_id, r.id as route_id, r.hub_code, r.dest_code,
             coalesce(r.distance_override_km, r.distance_km) as own_km
        from rd join public.routes r on r.world_id = p_world_id and r.airline_id = rd.airline_id and not r.removed
                                    and ((r.hub_code = rd.origin and r.dest_code = rd.dest) or (r.hub_code = rd.dest and r.dest_code = rd.origin))
       order by rd.id, exists (select 1 from public.rotations x where x.route_id = r.id) desc, r.id),
    ck as (
      select rd.*, ro.route_id, ro.hub_code, ro.dest_code, a.iata_code, coalesce(a.public_name, a.planner_name, a.game_name) as airline_name, a.position,
             -- the distance as the planning library takes it (block.distanceBetween): the airline's own route, else another
             -- route on the pair; no great circle here, so a pair with neither has no distance code
             coalesce(ro.own_km, (select coalesce(r2.distance_override_km, r2.distance_km) from public.routes r2
                                   where r2.world_id = p_world_id and coalesce(r2.distance_override_km, r2.distance_km) is not null
                                     and ((r2.hub_code = rd.origin and r2.dest_code = rd.dest) or (r2.hub_code = rd.dest and r2.dest_code = rd.origin))
                                   order by r2.airline_id = rd.airline_id desc, r2.id limit 1)) as km,
             -- the planner's codes on the legs that way: each rotation's service code on the route with a leg from origin to dest
             (select array_agg(distinct coalesce(nullif(btrim(rt.service_code), ''), 'none') order by coalesce(nullif(btrim(rt.service_code), ''), 'none'))
                from public.rotations rt join public.flight_legs l on l.rotation_id = rt.id
               where rt.route_id = ro.route_id and l.origin_code = rd.origin and l.dest_code = rd.dest) as planner_codes
        from rd join ro on ro.read_id = rd.id join public.airlines a on a.id = rd.airline_id),
    wanted as (
      -- the code the distance calls for (manual §4; service.profileFor): an airline's own profile on every route (Ryanair's
      -- R), else the first shared profile whose up_to_km is over the distance, else the last of them
      select ck.*, coalesce(
               (select p.code from public.service_profiles p where p.world_id = p_world_id and p.airline_id = ck.airline_id order by p.id limit 1),
               case when ck.km is not null then coalesce(
                 (select p.code from public.service_profiles p where p.world_id = p_world_id and p.airline_id is null and p.up_to_km is not null
                     and ck.km < p.up_to_km order by p.up_to_km, p.id limit 1),
                 (select p.code from public.service_profiles p where p.world_id = p_world_id and p.airline_id is null and p.up_to_km is not null
                   order by p.up_to_km desc, p.id desc limit 1)) end) as distance_code
        from ck),
    judged as (
      select x.*,
             x.distance_code is not null and x.game_code is distinct from x.distance_code as off_distance,
             exists (select 1 from unnest(coalesce(x.planner_codes, '{}'::text[])) c where c <> coalesce(x.game_code, 'none')) as off_planner
        from wanted x)
    select count(*)::int,
           coalesce(jsonb_agg(jsonb_build_object(
             'route_id', j.route_id, 'airline_id', j.airline_id, 'code', j.iata_code, 'airline', j.airline_name,
             'pair', least(j.origin, j.dest) || '-' || greatest(j.origin, j.dest), 'hub', j.hub_code, 'dest', j.dest_code,
             'from', j.origin, 'to', j.dest, 'direction', case when j.origin = j.hub_code then 'out' else 'back' end,
             'game_code', j.game_code, 'distance_code', j.distance_code, 'distance_km', j.km, 'planner_codes', to_jsonb(coalesce(j.planner_codes, '{}'::text[])),
             'kind', case when j.off_distance then 'distance' else 'planner' end,
             'off_distance', j.off_distance, 'off_planner', j.off_planner, 'read_at', private.fig_ts(j.read_at))
             order by j.off_distance desc, j.position nulls last, j.airline_id, least(j.origin, j.dest), greatest(j.origin, j.dest), j.origin <> j.hub_code)
             filter (where j.off_distance or j.off_planner), '[]'::jsonb)
      into v_checked, v_rows
      from judged j;
  end if;
  return jsonb_build_object(
    'world_id', p_world_id, 'airline_id', p_airline_id, 'as_of', private.fig_ts(p_as_of),
    'run', case when v_run.id is not null then jsonb_build_object(
             'id', v_run.id, 'started_at', private.fig_ts(v_run.started_at), 'finished_at', private.fig_ts(v_run.finished_at),
             'age_days', round((extract(epoch from p_as_of - v_run.finished_at) / 86400)::numeric, 1),
             'pages_read', v_run.pages_read, 'pages_failed', v_run.pages_failed) end,
    'checked', v_checked,
    'mismatches', v_rows,
    'notes', jsonb_build_array(
      'The service check (spec docs/specs/2026-10-30-market-pages-planner.md §3): each page read in the latest finished market run (one direction of one pair, read with our airline that flies it), on a route of that airline not removed. game_code is the On-Board Service the game shows selected on the pair (market_reads.service_code; null when none). distance_code is the code the route''s distance calls for (manual §4: the airline''s own profile, Ryanair''s R, on every route, else the first shared service_profiles row whose up_to_km is over the distance, else the last), the distance as the planning library takes it (the airline''s own route with any override, else another route on the pair; null when neither has one). planner_codes are the service codes of the route''s rotations with a leg that way (none for a rotation without one).',
      'A row for every direction where the game differs from the distance''s code (kind distance, listed first) or, failing that, from a planner code (kind planner). checked counts the directions looked at; with no finished run, run is null and there is nothing to check.'));
end
$function$

;

CREATE OR REPLACE FUNCTION private.market_ingest(p_world_id bigint, p_kind text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_run record; v_al bigint; v_read bigint; v_origin text; v_dest text; v_scan bigint; v_at timestamptz;
  n_fares int := 0; n_shares int := 0; n_weeks int := 0; v_bad text; v_read_n int; v_failed_n int;
begin
  if p_kind is null or p_kind not in ('start', 'page', 'finish') then raise exception 'unknown kind'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'the payload isn''t an object'; end if;
  if p_kind = 'start' then
    insert into public.market_runs (world_id, note, capture_version, pages_expected)
    values (p_world_id, nullif(btrim(p_payload ->> 'note'), ''), nullif(btrim(p_payload ->> 'version'), ''),
            case when (p_payload ->> 'total') ~ '^\d{1,6}$' then (p_payload ->> 'total')::int end)
    returning id into v_read;
    return jsonb_build_object('run_id', v_read);
  end if;

  -- page and finish: a run of this world that is still open
  select r.* into v_run from public.market_runs r where r.id = (p_payload ->> 'run_id')::bigint and r.world_id = p_world_id;
  if not found then raise exception 'no such market run in this capture key''s world: %', coalesce(p_payload ->> 'run_id', '(none)'); end if;
  if v_run.status <> 'open' then raise exception 'market run % is %, not open', v_run.id, v_run.status; end if;

  if p_kind = 'finish' then
    -- more than 10% of the pages failed (or none were read): not finished, as the world scan
    if v_run.pages_read + v_run.pages_failed = 0 or v_run.pages_failed > 0.1 * (v_run.pages_read + v_run.pages_failed) then
      raise exception 'not finished: % of % pages failed, more than 10%%', v_run.pages_failed, v_run.pages_read + v_run.pages_failed;
    end if;
    update public.market_runs set status = 'done', finished_at = clock_timestamp(),
           note = coalesce(nullif(btrim(p_payload ->> 'note'), ''), note)
     where id = v_run.id;
    return jsonb_build_object('pages_read', v_run.pages_read, 'pages_failed', v_run.pages_failed);
  end if;

  -- page: our airline, the pair, ok or failed
  select a.id into v_al from public.airlines a join public.groups g on g.id = a.group_id and g.world_id = a.world_id
   where a.world_id = p_world_id and g.kind = 'ours' and a.game_id = (p_payload ->> 'airline')::int;
  if v_al is null then raise exception 'airline % isn''t one of ours in this world', coalesce(p_payload ->> 'airline', '(none)'); end if;
  v_origin := p_payload ->> 'origin'; v_dest := p_payload ->> 'dest';
  if coalesce(v_origin, '') !~ '^[A-Z0-9]{3}$' or coalesce(v_dest, '') !~ '^[A-Z0-9]{3}$' or v_origin = v_dest then
    raise exception 'origin and dest must be two airport codes, not % and %', coalesce(v_origin, '(none)'), coalesce(v_dest, '(none)');
  end if;
  if jsonb_typeof(p_payload -> 'ok') is distinct from 'boolean' then raise exception 'ok must be true or false'; end if;

  -- the same page sent again replaces what it gave
  select m.id into v_read from public.market_reads m where m.run_id = v_run.id and m.origin = v_origin and m.dest = v_dest;
  if v_read is not null then
    delete from public.market_fares where read_id = v_read;
    delete from public.market_shares where read_id = v_read;
    delete from public.market_reads where id = v_read;
  end if;

  if not (p_payload ->> 'ok')::boolean then
    insert into public.market_reads (run_id, world_id, airline_id, origin, dest, ok, error)
    values (v_run.id, p_world_id, v_al, v_origin, v_dest, false, coalesce(nullif(btrim(p_payload ->> 'error'), ''), 'no reason given'))
    returning id into v_read;
  else
    -- the lists, checked before anything is written
    if jsonb_typeof(coalesce(p_payload -> 'fares', '[]')) <> 'array' or jsonb_typeof(coalesce(p_payload -> 'shares', '[]')) <> 'array'
       or jsonb_typeof(coalesce(p_payload -> 'weeks', '[]')) <> 'array' then
      raise exception 'fares, shares and weeks must be lists';
    end if;
    select string_agg(coalesce(f ->> 'code', '?') || ' ' || coalesce(f ->> 'cls', '?'), ', ') into v_bad
      from jsonb_array_elements(coalesce(p_payload -> 'fares', '[]')) f
     where coalesce(f ->> 'code', '') !~ '^[A-Z0-9]{2,3}$' or coalesce(f ->> 'cls', '') not in ('Y', 'C', 'F', 'Cargo')
        or coalesce(f ->> 'flights', '') !~ '^[1-9]\d{0,5}$';
    if v_bad is not null then raise exception 'fares that don''t read: %', v_bad; end if;
    select string_agg(coalesce(s ->> 'enterprise_id', '?'), ', ') into v_bad
      from jsonb_array_elements(coalesce(p_payload -> 'shares', '[]')) s
     where coalesce(s ->> 'enterprise_id', '') !~ '^\d{1,9}$' or coalesce(s ->> 'kind', '') not in ('passengers', 'cargo')
        or jsonb_typeof(s -> 'share') is distinct from 'number';
    if v_bad is not null then raise exception 'shares that don''t read: %', v_bad; end if;
    if jsonb_array_length(coalesce(p_payload -> 'shares', '[]')) > 0 and coalesce(p_payload ->> 'week', '') !~ '^\d{4}-\d{2}$' then
      raise exception 'shares without their week (2026-44)';
    end if;

    insert into public.market_reads (run_id, world_id, airline_id, origin, dest, ok, share_week, service_code, service_profile_game_id)
    values (v_run.id, p_world_id, v_al, v_origin, v_dest, true, nullif(p_payload ->> 'week', ''),
            private.market_service_token(p_payload -> 'service' ->> 'code'),
            case when (p_payload -> 'service' ->> 'game_id') ~ '^\d{1,9}$' then (p_payload -> 'service' ->> 'game_id')::int end)
    returning id, read_at into v_read, v_at;

    -- the shares: each enterprise by its game id; one the database doesn't know gets an airlines row, as the scan does
    insert into public.market_shares (read_id, world_id, kind, airline_id, week, share_pct, change_pts)
    select v_read, p_world_id, s ->> 'kind', private.scan_airline(p_world_id, (s ->> 'enterprise_id')::int, s ->> 'name'),
           p_payload ->> 'week', (s ->> 'share')::numeric,
           case when jsonb_typeof(s -> 'change') = 'number' then (s ->> 'change')::numeric end
      from jsonb_array_elements(coalesce(p_payload -> 'shares', '[]')) s;
    get diagnostics n_shares = row_count;

    -- the fares: the airline by the flight prefix, where the latest finished world scan's schedules give one airline that
    -- prefix; else an airline on the page's share list with that code; else none (the prefix kept)
    select s.id into v_scan from public.game_scans s
     where s.world_id = p_world_id and s.status = 'done' and exists (select 1 from public.game_scan_schedules x where x.scan_id = s.id)
     order by s.taken_at desc, s.id desc limit 1;
    with codes as (
      select distinct f ->> 'code' as code from jsonb_array_elements(coalesce(p_payload -> 'fares', '[]')) f),
    by_scan as (
      select c.code, min(x.airline_id) as airline_id from codes c
        join public.game_scan_schedules x on x.scan_id = v_scan
       cross join lateral jsonb_array_elements(case when jsonb_typeof(x.flights) = 'array' then x.flights else '[]'::jsonb end) e
       where e ->> 0 = c.code
       group by c.code having count(distinct x.airline_id) = 1),
    by_share as (
      select c.code, min(a.id) as airline_id from codes c
        join public.airlines a on a.world_id = p_world_id and a.iata_code = c.code
       where a.game_id in (select (s ->> 'enterprise_id')::int from jsonb_array_elements(coalesce(p_payload -> 'shares', '[]')) s)
       group by c.code having count(*) = 1)
    insert into public.market_fares (read_id, world_id, airline_code, service_class, airline_id, flights, price_low, price_avg, price_high,
                                     finished, sold_out)
    select v_read, p_world_id, f ->> 'code', f ->> 'cls', coalesce(bs.airline_id, bh.airline_id), (f ->> 'flights')::int,
           (f ->> 'low')::numeric, round((f ->> 'avg')::numeric, 2), (f ->> 'high')::numeric,
           coalesce((f ->> 'finished')::int, 0), coalesce((f ->> 'sold_out')::int, 0)
      from jsonb_array_elements(coalesce(p_payload -> 'fares', '[]')) f
      left join by_scan bs on bs.code = f ->> 'code'
      left join by_share bh on bh.code = f ->> 'code';
    get diagnostics n_fares = row_count;

    -- the pair's weeks with figures: seats offered and price per unit, the latest read winning, kept for good
    insert into public.market_weeks as k (world_id, origin, dest, week, seats, price_per_unit, run_id, read_at)
    select p_world_id, v_origin, v_dest, w ->> 'week',
           case when jsonb_typeof(w -> 'seats') = 'number' then (w ->> 'seats')::numeric::int end,
           case when jsonb_typeof(w -> 'price') = 'number' then (w ->> 'price')::numeric end, v_run.id, v_at
      from jsonb_array_elements(coalesce(p_payload -> 'weeks', '[]')) w
     where coalesce(w ->> 'week', '') ~ '^\d{4}-\d{2}$'
       and (coalesce((w ->> 'seats')::numeric, 0) <> 0 or coalesce((w ->> 'price')::numeric, 0) <> 0)
    on conflict (world_id, origin, dest, week) do update
       set seats = excluded.seats, price_per_unit = excluded.price_per_unit, run_id = excluded.run_id, read_at = excluded.read_at
     where k.read_at <= excluded.read_at;
    get diagnostics n_weeks = row_count;
  end if;

  -- the run's counts, from its reads
  select count(*) filter (where m.ok), count(*) filter (where not m.ok) into v_read_n, v_failed_n
    from public.market_reads m where m.run_id = v_run.id;
  update public.market_runs set pages_read = v_read_n, pages_failed = v_failed_n where id = v_run.id;
  return jsonb_build_object('read_id', v_read, 'fares', n_fares, 'shares', n_shares, 'weeks', n_weeks,
                            'pages_read', v_read_n, 'pages_failed', v_failed_n);
end
$function$

;

revoke all on function private.market_service_token(text) from public, anon, authenticated, service_role;

comment on function private.market_service_token(text) is 'A service profile''s code as the planner and service_profiles write it (since 31 Oct): the game''s name up to " (", trimmed ("S2 (min 800km)" → S2, "R" → R); null when empty. Used by private.market_ingest() (market_reads.service_code) and private.fig_market_service_checks() (game_code), so the reads stored before capture 1.10 check right.';

-- the descriptions as they stand, with what changed added at the end, once
do $describe$
declare x record; d text;
begin
  for x in select * from (values
      ('private.fig_market_service_checks(bigint, bigint, timestamptz)', 'leading token (since 31 Oct', ' game_code is the code''s leading token (since 31 Oct, private.market_service_token(): the game names its profiles "S2 (min 800km)", the planner S2), so reads stored with the game''s whole name check right.'),
      ('public.market_service_checks(bigint, timestamptz)', 'leading token (since 31 Oct', ' The game''s code is compared by its leading token (since 31 Oct: "S2 (min 800km)" is S2).'),
      ('private.market_ingest(bigint, text, jsonb)', 'leading token (since 31 Oct', ' The service code is stored as its leading token (since 31 Oct, private.market_service_token(): "S2 (min 800km)" → S2).')
    ) v(f, mark, more) loop
    d := obj_description(x.f::regprocedure, 'pg_proc');
    if position(x.mark in coalesce(d, '')) = 0 then
      execute format('comment on function %s is %L', x.f, coalesce(d, '') || x.more);
    end if;
  end loop;
  d := col_description('public.market_reads'::regclass, (select attnum from pg_attribute where attrelid = 'public.market_reads'::regclass and attname = 'service_code'));
  if position('leading token' in coalesce(d, '')) = 0 then
    execute format('comment on column public.market_reads.service_code is %L', coalesce(d, '') || '. Since 31 Oct the code''s leading token (S2, as the planner writes it); the reads of 30 Oct hold the game''s whole name ("S2 (min 800km)"), which the service check reads by its token');
  end if;
end
$describe$;

select set_config('equinox.actor', '', true), set_config('equinox.actor_detail', '', true);
